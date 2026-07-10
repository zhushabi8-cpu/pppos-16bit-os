; ================================================================
; PPP OS FAT12 文件系统
; ================================================================

cwd_cluster dw 0                    ; 当前工作目录的起始簇号 (0 表示根目录)

; ----------------------------------------------------------------
; 切换当前工作目录
; 输入: DS:SI = 目录名 (FAT 8.3 格式)
; 输出: CF=0 成功, CWD 更新; CF=1 失败
; ----------------------------------------------------------------
fat12_change_dir:
    pusha
    call fat12_find_file
    jc .cd_fail
    test dl, 0x10                   ; 检查是否为目录属性
    jz .cd_fail
    mov [cs:cwd_cluster], ax        ; 更新当前目录簇号
    popa
    clc
    ret
.cd_fail:
    popa
    stc
    ret

; ----------------------------------------------------------------
; 在 FAT12 文件系统中查找文件/目录
; 输入: DS:SI = 文件名 (11字节, 8.3格式)
; 输出: CF=0 成功, AX=起始簇号, CX=文件大小, DL=属性; CF=1 未找到
; ----------------------------------------------------------------
fat12_find_file:
    push bx
    push es
    cld

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .search_subdir

.search_root:
    mov ax, 19                      ; 根目录起始扇区 (LBA)
    mov cx, 14                      ; 根目录占用14个扇区
    mov bx, 0x7000                  ; 加载到段 0x7000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov cx, 224                     ; 根目录最大条目数
    jmp .do_search

.search_subdir:
    add ax, 31                      ; 数据区起始簇号偏移
    mov cx, 1                       ; 子目录占1个扇区
    mov bx, 0x7000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov cx, 16                      ; 子目录每扇区16个条目

.do_search:
    xor bx, bx
.search_loop:
    mov al, [es:bx]                 ; 第一个字节: 文件名首字符
    cmp al, 0x00                    ; 0x00 表示目录结束
    je .not_found
    cmp al, 0xE5                    ; 0xE5 表示已删除条目
    je .next_entry
    
    mov dl, [es:bx+11]              ; 属性字节
    test dl, 0x08                   ; 跳过卷标 (0x08)
    jnz .next_entry

    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb                      ; 比较文件名 (11字节)
    pop di
    pop si
    pop cx
    je .found

.next_entry:
    add bx, 32                      ; 每个目录项32字节
    loop .search_loop

.not_found:
    pop es
    pop bx
    stc
    ret

.found:
    mov ax, [es:bx + 26]            ; 起始簇号 (低16位)
    mov cx, [es:bx + 28]            ; 文件大小
    pop es
    pop bx
    clc
    ret

; ----------------------------------------------------------------
; 写入文件到 FAT12 文件系统 (若文件已存在则覆盖)
; 输入: DS:SI = 文件名 (11字节), ES:DI = 数据缓冲区, CX = 文件大小
; 输出: CF=0 成功, CF=1 失败 (磁盘满)
; ----------------------------------------------------------------
fat12_write_file:
    pusha
    cld
    mov [cs:.data_ptr_off], di
    mov [cs:.data_ptr_seg], es
    mov [cs:.file_size], cx
    
    call fat12_delete_file          ; 删除同名旧文件 (若存在)
    
    ; 计算所需扇区数
    mov ax, [cs:.file_size]
    add ax, 511
    shr ax, 9
    or ax, ax
    jnz .save_sec
    inc ax                          ; 空文件至少占1扇区
.save_sec:
    mov [cs:.sectors_left], ax

    ; 读取 FAT 表到内存 (0x6000 段)
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1                       ; FAT 起始扇区
    mov cx, 9                       ; FAT 占9个扇区
    xor bx, bx
    call disk_read_lba
    pop es

    ; 扫描连续空闲簇
    mov dx, 2                       ; 从簇2开始 (0,1 保留)
.scan_fat:
    cmp dx, 2848                    ; FAT12 最大簇号限制
    jae .disk_full

    mov cx, [cs:.sectors_left]
    mov di, dx
.check_seq:
    push dx
    push cx
    mov ax, di
    mov bx, 3
    mul bx
    shr ax, 1                       ; 计算 FAT 表项字节偏移
    mov bx, ax
    push ds
    mov ax, 0x6000
    mov ds, ax
    mov ax, [bx]                    ; 读取12位表项
    pop ds
    test di, 1
    jnz .odd_cluster
.even_cluster:
    and ax, 0x0FFF                  ; 偶数字节: 取低12位
    jmp .check_free
.odd_cluster:
    shr ax, 4                       ; 奇数字节: 取高12位
.check_free:
    pop cx
    pop dx
    or ax, ax
    jnz .seq_broken                 ; 非0表示该簇已占用
    inc di
    loop .check_seq
    jmp .found_cluster              ; 找到足够的连续空闲簇

.seq_broken:
    inc dx
    jmp .scan_fat

.found_cluster:
    mov [cs:.new_cluster], dx
    mov cx, [cs:.sectors_left]
    mov di, dx
    
    ; 写入 FAT 链
.link_loop:
    push cx
    mov ax, di
    mov bx, 3
    mul bx
    shr ax, 1
    mov bx, ax
    pop cx
    cmp cx, 1
    je .write_eof
    mov dx, di
    inc dx                          ; 下一簇
    jmp .do_fat_write
.write_eof:
    mov dx, 0x0FFF                  ; EOF 标记 (0xFFF)

.do_fat_write:
    push ds
    push cx
    mov ax, 0x6000
    mov ds, ax
    mov ax, [bx]
    test di, 1
    jnz .mark_odd
.mark_even:
    and ax, 0xF000                  ; 保留高4位
    or ax, dx                       ; 写入12位值
    jmp .write_back
.mark_odd:
    and ax, 0x000F                  ; 保留低4位
    push cx
    mov cx, dx
    shl cx, 4                       ; 左移4位到高12位位置
    or ax, cx
    pop cx
.write_back:
    mov [bx], ax
    pop cx
    pop ds
    dec cx
    jz .link_done
    inc di
    jmp .link_loop

.link_done:
    ; 写回 FAT 表 (两份备份)
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_write_lba
    mov ax, 10                      ; FAT 备份
    mov cx, 9
    call disk_write_lba
    pop es

    ; 在父目录中创建目录项
    push es
    mov ax, 0x7000
    mov es, ax
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_read_sub
    mov ax, 19
    mov cx, 14
    mov dx, 224                     ; 根目录条目数
    jmp .w_do_read
.w_read_sub:
    add ax, 31
    mov cx, 1
    mov dx, 16                      ; 子目录条目数
.w_do_read:
    xor bx, bx
    call disk_read_lba

    ; 扫描空闲目录项
    xor bx, bx
    mov cx, dx
.scan_dir:
    mov al, [es:bx]
    cmp al, 0x00
    je .found_dir_entry
    cmp al, 0xE5
    je .found_dir_entry
    add bx, 32
    loop .scan_dir
    pop es
    jmp .disk_full                  ; 目录已满

.found_dir_entry:
    push di
    push si
    push cx
    mov di, bx
    mov cx, 11
    rep movsb                       ; 复制文件名
    mov cx, 21
    xor al, al
    rep stosb                       ; 清空其余字段
    mov byte [es:bx+11], 0x20       ; 属性: 普通文件 (0x20)
    mov ax, [cs:.new_cluster]
    mov [es:bx+26], ax              ; 起始簇号
    mov ax, [cs:.file_size]
    mov [es:bx+28], ax              ; 文件大小
    mov word [es:bx+30], 0          ; 时间戳 (简化)
    pop cx
    pop si
    pop di

    ; 写回目录扇区
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_write_sub
    mov ax, 19
    mov cx, 14
    jmp .w_do_write
.w_write_sub:
    add ax, 31
    mov cx, 1
.w_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop es

    ; 写入文件数据到数据区
    mov ax, [cs:.sectors_left]
    mov cx, ax
    mov ax, [cs:.new_cluster]
    add ax, 31                      ; 转换为 LBA (数据区起始偏移31)
    mov es, [cs:.data_ptr_seg]
    mov bx, [cs:.data_ptr_off]
    call disk_write_lba

    popa
    clc
    ret

.disk_full:
    popa
    stc
    ret

.new_cluster  dw 0
.file_size    dw 0
.data_ptr_off dw 0
.data_ptr_seg dw 0
.sectors_left dw 0

; ----------------------------------------------------------------
; 删除文件 (释放 FAT 簇链)
; 输入: DS:SI = 文件名 (11字节)
; 输出: CF=0 成功, CF=1 失败
; ----------------------------------------------------------------
fat12_delete_file:
    pusha
    cld
    push es
    mov ax, 0x7000
    mov es, ax
    
    ; 读取当前目录到 0x7000
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .d_read_sub
    mov ax, 19
    mov cx, 14
    mov dx, 224
    jmp .d_do_read
.d_read_sub:
    add ax, 31
    mov cx, 1
    mov dx, 16
.d_do_read:
    xor bx, bx
    call disk_read_lba

    ; 在目录中查找文件
    mov cx, dx
    xor bx, bx
.del_search:
    mov al, [es:bx]
    cmp al, 0
    je .del_fail
    cmp al, 0xE5
    je .del_next
    mov al, [es:bx+11]
    test al, 0x08                   ; 跳过卷标
    jnz .del_next

    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb
    pop di
    pop si
    pop cx
    je .del_found
.del_next:
    add bx, 32
    loop .del_search
.del_fail:
    pop es
    popa
    stc
    ret

.del_found:
    ; 标记目录项为已删除
    mov byte [es:bx], 0xE5
    mov dx, [es:bx+26]              ; 获取起始簇号
    push dx
    
    ; 写回目录扇区
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .d_write_sub
    mov ax, 19
    mov cx, 14
    jmp .d_do_write
.d_write_sub:
    add ax, 31
    mov cx, 1
.d_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop dx
    cmp dx, 2
    jb .del_done                    ; 保留簇0,1不处理

    ; 读取 FAT 表
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    push bx
    xor bx, bx
    call disk_read_lba

    ; 遍历并释放 FAT 链
.free_loop:
    mov ax, dx
    mov bx, 3
    mul bx
    shr ax, 1
    mov bx, ax
    mov ax, [es:bx]
    push ax
    test dx, 1
    jnz .free_odd
.free_even:
    and ax, 0xF000                  ; 保留高4位
    jmp .write_free
.free_odd:
    and ax, 0x000F                  ; 保留低4位
.write_free:
    mov [es:bx], ax                 ; 清除簇标记 (置0)
    pop ax
    test dx, 1
    jnz .get_odd
.get_even:
    and ax, 0x0FFF                  ; 获取下一簇号
    jmp .check_next
.get_odd:
    shr ax, 4
.check_next:
    mov dx, ax
    cmp dx, 0x0FF8
    jae .free_done                  ; 到达 EOF
    or dx, dx
    jz .free_done
    jmp .free_loop

.free_done:
    ; 写回 FAT 表
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_write_lba
    mov ax, 10
    call disk_write_lba
    pop bx

.del_done:
    pop es
    popa
    clc
    ret

; ----------------------------------------------------------------
; 重命名文件
; 输入: DS:SI = 旧文件名, ES:DI = 新文件名 (均为11字节)
; 输出: CF=0 成功, CF=1 失败
; ----------------------------------------------------------------
fat12_rename_file:
    pusha
    cld
    push es
    mov ax, 0x7000
    mov es, ax
    
    ; 读取当前目录
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .r_read_sub
    mov ax, 19
    mov cx, 14
    mov dx, 224
    jmp .r_do_read
.r_read_sub:
    add ax, 31
    mov cx, 1
    mov dx, 16
.r_do_read:
    xor bx, bx
    call disk_read_lba

    ; 查找旧文件名
    mov cx, dx
    xor bx, bx
.ren_search:
    mov al, [es:bx]
    cmp al, 0
    je .ren_fail
    cmp al, 0xE5
    je .ren_next
    mov al, [es:bx+11]
    test al, 0x08
    jnz .ren_next

    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb
    pop di
    pop si
    pop cx
    je .ren_found
.ren_next:
    add bx, 32
    loop .ren_search
.ren_fail:
    pop es
    popa
    stc
    ret

.ren_found:
    ; 用新文件名覆盖旧文件名
    push cx
    push si
    push di
    mov si, di                      ; 新文件名在 ES:DI
    mov di, bx                      ; 目标目录项
    mov cx, 11
    rep movsb
    pop di
    pop si
    pop cx

    ; 写回目录扇区
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .r_write_sub
    mov ax, 19
    mov cx, 14
    jmp .r_do_write
.r_write_sub:
    add ax, 31
    mov cx, 1
.r_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop es
    popa
    clc
    ret

; ----------------------------------------------------------------
; 创建目录
; 输入: DS:SI = 目录名 (11字节)
; 输出: CF=0 成功, CF=1 失败 (磁盘满)
; ----------------------------------------------------------------
fat12_make_dir:
    pusha
    cld

    ; 1. 扫描并分配空闲簇
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_read_lba
    pop es

    mov dx, 2
.scan_fat:
    cmp dx, 2848
    jae .disk_full

    push dx
    mov ax, dx
    mov bx, 3
    mul bx
    shr ax, 1
    mov bx, ax
    pop dx

    push ds
    mov ax, 0x6000
    mov ds, ax
    mov ax, [bx]
    pop ds

    test dx, 1
    jnz .odd_cluster
.even_cluster:
    and ax, 0x0FFF
    jz .found_cluster
    jmp .next_cluster
.odd_cluster:
    shr ax, 4
    jz .found_cluster
.next_cluster:
    inc dx
    jmp .scan_fat

.found_cluster:
    mov [cs:.new_cluster], dx

    ; 在 FAT 中标记为 EOF
    mov ax, dx
    mov bx, 3
    mul bx
    shr ax, 1
    mov bx, ax

    push ds
    mov ax, 0x6000
    mov ds, ax
    mov ax, [bx]
    test dx, 1
    jnz .mark_odd
.mark_even:
    and ax, 0xF000
    or ax, 0x0FFF
    jmp .write_back
.mark_odd:
    and ax, 0x000F
    or ax, 0xFFF0
.write_back:
    mov [bx], ax
    pop ds

    ; 写回 FAT 表
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_write_lba
    mov ax, 10
    call disk_write_lba
    pop es

    ; 2. 初始化新目录簇 (包含 "." 和 ".." 条目)
    push es
    mov ax, 0x5000
    mov es, ax
    mov cx, 256
    xor di, di
    xor ax, ax
    rep stosw                       ; 清零512字节

    ; 写入 "." 条目
    mov di, 0
    mov al, '.'
    mov [es:di], al
    mov al, ' '
    mov cx, 10
    inc di
    rep stosb
    mov byte [es:11], 0x10          ; 目录属性
    mov ax, [cs:.new_cluster]
    mov [es:26], ax                 ; 指向自身

    ; 写入 ".." 条目
    mov di, 32
    mov al, '.'
    mov [es:di], al
    mov [es:di+1], al
    mov al, ' '
    mov cx, 9
    add di, 2
    rep stosb
    mov byte [es:32+11], 0x10       ; 目录属性
    mov ax, [cs:cwd_cluster]
    mov [es:32+26], ax              ; 指向父目录

    ; 写入新簇到磁盘
    mov ax, [cs:.new_cluster]
    add ax, 31
    mov cx, 1
    xor bx, bx
    call disk_write_lba
    pop es

    ; 3. 在父目录中注册新目录项
    push es
    mov ax, 0x7000
    mov es, ax
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_read_sub
    mov ax, 19
    mov cx, 14
    mov dx, 224
    jmp .w_do_read
.w_read_sub:
    add ax, 31
    mov cx, 1
    mov dx, 16
.w_do_read:
    xor bx, bx
    call disk_read_lba

    ; 查找空闲目录项
    mov cx, dx
    xor bx, bx
.scan_dir:
    mov al, [es:bx]
    cmp al, 0
    je .found_dir_entry
    cmp al, 0xE5
    je .found_dir_entry
    add bx, 32
    loop .scan_dir

    pop es
    jmp .disk_full

.found_dir_entry:
    push di
    push si
    push cx
    mov di, bx
    mov cx, 11
    rep movsb                       ; 复制目录名
    mov cx, 21
    xor al, al
    rep stosb

    mov byte [es:bx+11], 0x10       ; 目录属性
    mov ax, [cs:.new_cluster]
    mov [es:bx+26], ax              ; 起始簇号
    mov word [es:bx+28], 0          ; 目录大小固定为0
    mov word [es:bx+30], 0
    pop cx
    pop si
    pop di

    ; 写回父目录扇区
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_write_sub
    mov ax, 19
    mov cx, 14
    jmp .w_do_write
.w_write_sub:
    add ax, 31
    mov cx, 1
.w_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop es

    popa
    clc
    ret

.disk_full:
    popa
    stc
    ret

.new_cluster dw 0