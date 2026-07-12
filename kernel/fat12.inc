; ================================================================
; PPP OS FAT12 文件系统
; ================================================================

cwd_cluster dw 0                    ; 当前工作目录的起始簇号（0 表示根目录）

; ----------------------------------------------------------------
; 切换当前工作目录
; 输入: DS:SI = 目录名（FAT 8.3 格式，11 字节）
; 输出: CF=0 成功，CWD 更新为目录簇号；CF=1 失败（非目录或不存在）
; ----------------------------------------------------------------
fat12_change_dir:
    pusha
    call fat12_find_file            ; 查找目录项
    jc .cd_fail
    test dl, 0x10                   ; 检查属性中的目录位
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
; 在 FAT12 文件系统中查找文件或目录
; 输入: DS:SI = 文件名（11 字节，8.3 格式）
; 输出: CF=0 成功，AX=起始簇号，CX=文件大小，DL=属性；CF=1 未找到
; ----------------------------------------------------------------
fat12_find_file:
    push bx
    push es
    cld

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .search_subdir              ; 非零则搜索子目录

.search_root:
    ; 根目录位于 LBA 19，占 14 个扇区，共 224 个条目
    mov ax, 19
    mov cx, 14
    mov bx, 0x7000                  ; 暂存段 0x7000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov cx, 224
    jmp .do_search

.search_subdir:
    ; 子目录：簇号转 LBA（数据区从簇 2 开始，LBA = 簇号 + 31）
    push ax                         ; 保存当前簇号
    add ax, 31
    mov cx, 1                       ; 每簇 1 扇区
    mov bx, 0x7000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov cx, 16                      ; 每扇区 16 个目录项（32 字节/项）

.do_search:
    xor bx, bx
.search_loop:
    mov al, [es:bx]                 ; 目录项首字节
    cmp al, 0x00                    
    je .check_next_cluster          ; 0x00 表示此条目未用，但后面可能还有簇
    cmp al, 0xE5                    
    je .next_entry                  ; 0xE5 表示已删除项
    
    mov dl, [es:bx+11]              ; 属性字节
    test dl, 0x08                   ; 跳过卷标（属性位 0x08）
    jnz .next_entry

    ; 比较文件名（11 字节）
    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb
    pop di
    pop si
    pop cx
    je .found

.next_entry:
    add bx, 32                      ; 下一项
    loop .search_loop

.check_next_cluster:
    cmp word [cs:cwd_cluster], 0
    je .not_found                   ; 根目录空间连续，找不到即不存在

    ; 子目录：读取 FAT 表，获取下一簇
    pop dx                          ; 恢复当前簇号
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9                       ; FAT 表占 9 扇区（从 LBA 1 开始）
    push bx
    xor bx, bx
    call disk_read_lba              ; 加载 FAT 到 0x6000:0000
    pop bx
    
    mov ax, dx
    mov di, 3
    mul di                          ; 簇号 * 3
    shr ax, 1                       ; /2 得到字节偏移
    mov di, ax
    mov ax, [es:di]                 ; 读取 16 位
    test dx, 1
    jnz .odd_cluster
    and ax, 0x0FFF                  ; 偶簇取低 12 位
    jmp .eval_next
.odd_cluster:
    shr ax, 4                       ; 奇簇取高 12 位
.eval_next:
    pop es
    cmp ax, 0x0FF8                  ; 是否 EOF（>=0xFF8）
    jae .not_found
    or ax, ax
    jz .not_found                   ; 空闲簇（0）表示链断裂
    jmp .search_subdir              ; 继续读取下一簇

.not_found:
    cmp word [cs:cwd_cluster], 0
    je .ret_err
    pop ax                          ; 平衡栈（之前 push ax）
.ret_err:
    pop es
    pop bx
    stc
    ret

.found:
    cmp word [cs:cwd_cluster], 0
    je .get_info
    pop dx                          ; 平衡栈
.get_info:
    mov ax, [es:bx + 26]            ; 起始簇号
    mov cx, [es:bx + 28]            ; 文件大小（字节）
    pop es
    pop bx
    clc
    ret

; ----------------------------------------------------------------
; 写入文件到 FAT12（若文件已存在则覆盖）
; 输入: DS:SI = 文件名（11 字节）, ES:DI = 数据缓冲区, CX = 文件大小
; 输出: CF=0 成功，CF=1 失败（磁盘满）
; ----------------------------------------------------------------
fat12_write_file:
    pusha
    cld
    mov [cs:.data_ptr_off], di
    mov [cs:.data_ptr_seg], es
    mov [cs:.file_size], cx
    
    call fat12_delete_file          ; 先删除同名文件（实现覆盖）

    ; 计算所需扇区数
    mov ax, [cs:.file_size]
    add ax, 511
    shr ax, 9
    or ax, ax
    jnz .save_sec
    inc ax                          ; 空文件也分配 1 扇区
.save_sec:
    mov [cs:.sectors_left], ax

    ; 加载 FAT 表到 0x6000
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_read_lba
    pop es

    ; 扫描连续空闲簇
    mov dx, 2                       ; FAT12 簇号从 2 开始
.scan_fat:
    cmp dx, 2848                    ; 最大簇号（磁盘总簇数）
    jae .disk_full

    mov cx, [cs:.sectors_left]
    mov di, dx
.check_seq:
    push dx
    push cx
    mov ax, di
    mov bx, 3
    mul bx
    shr ax, 1
    mov bx, ax
    push ds
    mov ax, 0x6000
    mov ds, ax
    mov ax, [bx]
    pop ds
    test di, 1
    jnz .odd_cluster
.even_cluster:
    and ax, 0x0FFF
    jmp .check_free
.odd_cluster:
    shr ax, 4
.check_free:
    pop cx
    pop dx
    or ax, ax
    jnz .seq_broken                 ; 非零表示已被占用
    inc di
    loop .check_seq
    jmp .found_cluster              ; 找到足够连续空闲簇

.seq_broken:
    inc dx
    jmp .scan_fat

.found_cluster:
    mov [cs:.new_cluster], dx
    mov cx, [cs:.sectors_left]
    mov di, dx
    
    ; 更新 FAT 链
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
    inc dx                          ; 下一簇指针
    jmp .do_fat_write
.write_eof:
    mov dx, 0x0FFF                  ; EOF 标记

.do_fat_write:
    push ds
    push cx
    mov ax, 0x6000
    mov ds, ax
    mov ax, [bx]
    test di, 1
    jnz .mark_odd
.mark_even:
    and ax, 0xF000
    or ax, dx
    jmp .write_back
.mark_odd:
    and ax, 0x000F
    push cx
    mov cx, dx
    shl cx, 4
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
    ; 写回 FAT（第一份和第二份）
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_write_lba
    mov ax, 10
    mov cx, 9
    call disk_write_lba
    pop es

    ; 加载目录表
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

    ; 寻找空闲目录项
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
    jmp .disk_full

.found_dir_entry:
    ; 写入目录项
    push di
    push si
    push cx
    mov di, bx
    mov cx, 11
    rep movsb                      ; 复制文件名
    mov cx, 21
    xor al, al
    rep stosb                      ; 清零剩余字段
    mov byte [es:bx+11], 0x20      ; 属性：归档
    mov ax, [cs:.new_cluster]
    mov [es:bx+26], ax
    mov ax, [cs:.file_size]
    mov [es:bx+28], ax
    mov word [es:bx+30], 0
    pop cx
    pop si
    pop di

    ; 写回目录表
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
    add ax, 31                     ; 簇号转 LBA
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

; 局部变量
.new_cluster  dw 0
.file_size    dw 0
.data_ptr_off dw 0
.data_ptr_seg dw 0
.sectors_left dw 0

; ----------------------------------------------------------------
; 删除文件（释放 FAT 簇链）
; 输入: DS:SI = 文件名（11 字节）
; 输出: CF=0 成功，CF=1 失败（文件不存在）
; ----------------------------------------------------------------
fat12_delete_file:
    pusha
    cld
    push es
    mov ax, 0x7000
    mov es, ax
    
    ; 加载目录表
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

    ; 搜索文件名
    mov cx, dx
    xor bx, bx
.del_search:
    mov al, [es:bx]
    cmp al, 0
    je .del_fail
    cmp al, 0xE5
    je .del_next
    mov al, [es:bx+11]
    test al, 0x08
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
    ; 标记目录项为删除
    mov byte [es:bx], 0xE5
    mov dx, [es:bx+26]              ; 获取起始簇号
    push dx
    
    ; 写回目录表
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
    jb .del_done                    ; 无效簇，无需释放

    ; 加载 FAT 表
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    push bx
    xor bx, bx
    call disk_read_lba

    ; 遍历并释放簇链
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
    and ax, 0xF000
    jmp .write_free
.free_odd:
    and ax, 0x000F
.write_free:
    mov [es:bx], ax                 ; 将当前簇标记为 0（空闲）
    pop ax
    test dx, 1
    jnz .get_odd
.get_even:
    and ax, 0x0FFF
    jmp .check_next
.get_odd:
    shr ax, 4
.check_next:
    mov dx, ax
    cmp dx, 0x0FF8
    jae .free_done
    or dx, dx
    jz .free_done
    jmp .free_loop

.free_done:
    ; 写回 FAT 两份
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
; 输入: DS:SI = 旧文件名（11 字节）, ES:DI = 新文件名（11 字节）
; 输出: CF=0 成功，CF=1 失败（旧文件不存在）
; ----------------------------------------------------------------
fat12_rename_file:
    pusha
    cld
    push es
    mov ax, 0x7000
    mov es, ax
    
    ; 加载目录表
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

    ; 搜索旧文件名
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
    ; 覆盖写入新文件名
    push cx
    push si
    push di
    mov si, di                      ; ES:DI 指向新名字
    mov di, bx                      ; 目标目录项偏移
    mov cx, 11
    rep movsb
    pop di
    pop si
    pop cx

    ; 写回目录表
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
; 输入: DS:SI = 目录名（11 字节）
; 输出: CF=0 成功，CF=1 失败（磁盘满）
; ----------------------------------------------------------------
fat12_make_dir:
    pusha
    cld

    ; 加载 FAT 表
    push es
    mov ax, 0x6000
    mov es, ax
    mov ax, 1
    mov cx, 9
    xor bx, bx
    call disk_read_lba
    pop es

    ; 扫描一个空闲簇
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

    ; 标记该簇为 EOF (0xFFF)
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

    ; 写回 FAT
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

    ; 初始化目录块（包含 "." 和 ".." 条目）
    push es
    mov ax, 0x5000
    mov es, ax
    mov cx, 256                     ; 1 扇区（512 字节 = 16 项 * 32）
    xor di, di
    xor ax, ax
    rep stosw                       ; 清空

    ; "." 目录项
    mov di, 0
    mov al, '.'
    mov [es:di], al
    mov al, ' '
    mov cx, 10
    inc di
    rep stosb
    mov byte [es:11], 0x10          ; 目录属性
    mov ax, [cs:.new_cluster]
    mov [es:26], ax                 ; 起始簇号

    ; ".." 目录项
    mov di, 32
    mov al, '.'
    mov [es:di], al
    mov [es:di+1], al
    mov al, ' '
    mov cx, 9
    add di, 2
    rep stosb
    mov byte [es:32+11], 0x10
    mov ax, [cs:cwd_cluster]
    mov [es:32+26], ax              ; 父目录簇号

    ; 写入目录块到数据区
    mov ax, [cs:.new_cluster]
    add ax, 31
    mov cx, 1
    xor bx, bx
    call disk_write_lba
    pop es

    ; 加载父目录表
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

    ; 在父目录中查找空闲项
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
    ; 写入新目录的目录项
    push di
    push si
    push cx
    mov di, bx
    mov cx, 11
    rep movsb                      ; 复制目录名
    mov cx, 21
    xor al, al
    rep stosb
    mov byte [es:bx+11], 0x10      ; 属性：目录
    mov ax, [cs:.new_cluster]
    mov [es:bx+26], ax
    mov word [es:bx+28], 0
    mov word [es:bx+30], 0
    pop cx
    pop si
    pop di

    ; 写回父目录表
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