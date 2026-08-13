; ================================================================
; PPP OS 虚拟文件系统抽象层 (VFS)
; 为上层提供统一的文件操作接口，底层调用 FAT12 文件系统
; ================================================================

%define MAX_FDS     16              ; 最大同时打开文件数
%define FD_SIZE     14              ; 扩展为 14 字节，支持 32 位文件大小

; 文件描述符结构偏移量
%define FD_STATE    0               ; 0=空闲, 1=打开
%define FD_TYPE     1               ; 文件类型（3=磁盘文件）
%define FD_LBA      2               ; 文件起始 LBA（2 字节）
%define FD_LENGTH   4               ; 文件占用的扇区数（2 字节）
%define FD_OFFSET   6               ; 当前读写偏移（4 字节）
%define FD_EXACT_SZ 10              ; 精确文件大小（4 字节），防止 DOS 越界读取

fd_table times MAX_FDS * FD_SIZE db 0   ; 文件描述符表

; ----------------------------------------------------------------
; VFS 初始化（预留接口，当前为空实现）
; ----------------------------------------------------------------
init_vfs:
    ret

; ----------------------------------------------------------------
; VFS 写入操作
; 输入: BX = 文件描述符，DS:SI = 数据指针
;       BX=1 表示标准输出（屏幕），BX>=2 表示已打开的文件
; 输出: CF=0 成功，CF=1 失败
; ----------------------------------------------------------------
vfs_write:
    pusha
    cmp bx, 1
    je .do_stdout
    cmp bx, 2
    jb .error
    cmp bx, MAX_FDS
    jae .error

    ; 通过文件描述符索引获取 FD 表项
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    cmp byte [cs:di + FD_STATE], 0     ; 检查文件是否已打开
    je .error
    mov al, [cs:di + FD_TYPE]
    cmp al, 3                          ; 类型 3 = 磁盘文件
    je .do_disk_write
    jmp .error

.do_stdout:
    call print_string                  ; 输出到屏幕
    jmp .success

.do_disk_write:
    push es
    mov ax, [cs:di + FD_LBA]           ; 起始 LBA
    mov cx, [cs:di + FD_LENGTH]        ; 扇区数
    push ds
    pop es                             ; ES = DS（数据段）
    mov bx, si                         ; 数据指针
    call disk_write_lba
    pop es
    jmp .success

.success:
    popa
    clc
    ret

.error:
    popa
    stc
    ret

; ----------------------------------------------------------------
; VFS 读取操作
; 输入: BX = 文件描述符（0=标准输入，>=2=打开的文件）
;       ES:DI = 数据缓冲区
; 输出: CF=0 成功，CF=1 失败
; ----------------------------------------------------------------
vfs_read:
    cmp bx, 0
    je .do_stdin
    cmp bx, 2
    jb .error
    cmp bx, MAX_FDS
    jae .error

    push di
    push bx
    push ax
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    pop ax
    pop bx
    cmp byte [cs:di + FD_STATE], 0     ; 检查文件是否已打开
    je .error_pop
    mov cl, [cs:di + FD_TYPE]
    cmp cl, 3                          ; 类型 3 = 磁盘文件
    je .do_disk_read

.error_pop:
    pop di
    stc
    ret

.do_stdin:
    call get_char                      ; 从键盘读取字符
    clc
    ret

.do_disk_read:
    mov ax, [cs:di + FD_LBA]           ; 起始 LBA
    mov cx, [cs:di + FD_LENGTH]        ; 扇区数
    pop di                             ; 恢复缓冲区指针（ES:DI）
    mov bx, di
    call disk_read_lba
    clc
    ret

.error:
    stc
    ret

; ----------------------------------------------------------------
; VFS 打开文件
; 输入: DS:SI = 文件名（C 风格字符串）
; 输出: CF=0 成功，AX=文件描述符（2~15）；CF=1 失败（文件不存在或表满）
; 说明: 查找文件，记录起始 LBA、扇区数和精确大小到 FD 表
; ----------------------------------------------------------------
vfs_open:
    pusha
    cld
    push ds
    push si

    ; 安全检查：拒绝空文件名、空格或回车
    lodsb
    cmp al, 0
    je .not_found_pop
    cmp al, ' '
    je .not_found_pop
    cmp al, 13
    je .not_found_pop
    dec si

    ; 将文件名转换为 FAT 8.3 格式（11 字节，主名 8 字节 + 扩展名 3 字节）
    push cs
    pop es
    mov di, vfs_fat_name
    mov cx, 11
    mov al, ' '
    rep stosb
    pop si
    pop ds
    push cs
    pop es
    mov di, vfs_fat_name

.copy_name:
    lodsb
    or al, al
    jz .done_copy
    cmp al, '.'
    je .copy_ext
    stosb
    jmp .copy_name

.copy_ext:
    mov di, vfs_fat_name + 8            ; 扩展名从第 8 字节开始
    jmp .copy_name

.done_copy:
    push cs
    pop ds
    mov si, vfs_fat_name
    call fat12_find_file                ; 返回 DX:CX = 32位精确文件大小
    jc .not_found

    mov [cs:.tmp_exact_sz_l], cx          ; 暂存精确大小低 16 位
    mov [cs:.tmp_exact_sz_h], dx          ; 暂存精确大小高 16 位

    ; 计算数据区 LBA（簇号 + 31）
    add ax, 31
    mov [cs:.tmp_lba], ax

    ; 计算所需扇区数 = (DX:CX + 511) / 512
    mov ax, cx
    add ax, 511
    mov bx, dx
    adc bx, 0
    shl bx, 7
    shr ax, 9
    or ax, bx
    mov [cs:.tmp_sec], ax

    ; 在 FD 表中查找空闲槽（从索引 2 开始，0 和 1 保留给 stdin/stdout）
    mov bx, 2
.find_fd:
    cmp bx, MAX_FDS
    jae .not_found
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    cmp byte [cs:di + FD_STATE], 0
    je .found_fd
    inc bx
    jmp .find_fd

.found_fd:
    ; 填充 FD 表项
    mov byte [cs:di + FD_STATE], 1
    mov byte [cs:di + FD_TYPE], 3       ; 磁盘文件类型
    mov ax, [cs:.tmp_lba]
    mov [cs:di + FD_LBA], ax
    mov ax, [cs:.tmp_sec]
    mov [cs:di + FD_LENGTH], ax
    mov word [cs:di + FD_OFFSET], 0
    mov word [cs:di + FD_OFFSET + 2], 0
    mov ax, [cs:.tmp_exact_sz_l]
    mov [cs:di + FD_EXACT_SZ], ax       ; 存储精确大小低 16 位
    mov ax, [cs:.tmp_exact_sz_h]
    mov [cs:di + FD_EXACT_SZ + 2], ax   ; 存储精确大小高 16 位

    mov [cs:.tmp_fd], bx

    popa
    mov ax, [cs:.tmp_fd]
    clc
    ret

.not_found_pop:
    pop si
    pop ds
.not_found:
    popa
    stc
    ret

.tmp_lba dw 0
.tmp_sec dw 0
.tmp_fd  dw 0
.tmp_exact_sz_l dw 0
.tmp_exact_sz_h dw 0
vfs_fat_name times 11 db ' '

; ----------------------------------------------------------------
; VFS 关闭文件
; 输入: BX = 文件描述符
; 说明: 将 FD 表项标记为空闲
; ----------------------------------------------------------------
vfs_close:
    pusha
    cmp bx, 2
    jb .done
    cmp bx, MAX_FDS
    jae .done
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    mov byte [cs:di + FD_STATE], 0      ; 标记为空闲
.done:
    popa
    ret

; ----------------------------------------------------------------
; VFS 读取目录列表
; 输入: ES:DI = 输出缓冲区，AL = 最大条目数（本实现未使用）
; 输出: CX = 实际读取的目录项数
; 目录项格式（每个条目 20 字节）：
;   0-10:  文件名（11 字节，FAT 8.3 格式）
;   11:    属性（0x10=目录，0x20=文件）
;   12-15: 32位文件大小 (4 字节)
;   16-17: 起始簇号 (2 字节)
;   18-19: 保留填充 (2 字节)
; ----------------------------------------------------------------
vfs_read_dir:
    pusha
    cld
    push es

    ; 根据当前目录类型读取相应的扇区
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .read_subdir

    ; 根目录：LBA 19，占 14 个扇区
    mov ax, 19
    mov cx, 14
    mov bx, [cs:seg_dir_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov dx, 224                        ; 根目录最多 224 个条目
    jmp .scan_start

.read_subdir:
    ; 子目录：LBA = 簇号 + 31，占 1 个扇区
    add ax, 31
    mov cx, 1
    mov bx, [cs:seg_dir_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov dx, 16                         ; 子目录每扇区 16 个条目

.scan_start:
    pop es                             ; 恢复目标段（ES:DI 指向输出缓冲区）
    push ds
    mov ax, [cs:seg_dir_buf]
    mov ds, ax                         ; DS 指向目录数据
    xor si, si

    xor cx, cx
    mov [cs:vfs_tmp_count], cx

.scan_loop:
    mov al, [si]
    or al, al
    jz .done

    cmp al, 0xE5                        ; 0xE5 表示已删除项
    je .next_entry

    mov bl, [si + 11]                   ; 属性字节
    test bl, 0x08                       ; 跳过卷标（0x08）
    jnz .next_entry

    ; 复制文件名（11 字节）
    push si
    push cx
    mov cx, 11
    rep movsb                           ; DS:SI -> ES:DI
    pop cx
    pop si

    ; 存储属性字节（第 11 字节）
    mov al, bl
    stosb

    ; 存储文件大小（32位，4 字节，占据原保留字段）
    mov ax, [si + 28]
    stosw
    mov ax, [si + 30]
    stosw

    ; 存储起始簇号（2 字节）
    mov ax, [si + 26]
    stosw

    ; 保留对齐（2 字节，填充 0）
    xor ax, ax
    stosw

    inc word [cs:vfs_tmp_count]

.next_entry:
    add si, 32                          ; 每个目录项 32 字节
    dec dx
    jnz .scan_loop

.done:
    pop ds
    popa
    mov cx, [cs:vfs_tmp_count]
    clc
    ret

vfs_tmp_count dw 0