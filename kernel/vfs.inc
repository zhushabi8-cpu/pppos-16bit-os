; ================================================================
; PPP OS 虚拟文件系统抽象层 (VFS)
; ================================================================

%define MAX_FDS     16              ; 最大同时打开文件数
%define FD_SIZE     8               ; 每个文件描述符占用字节数

; 文件描述符结构偏移量
%define FD_STATE    0               ; 0=空闲, 1=打开
%define FD_TYPE     1               ; 文件类型 (3=磁盘文件)
%define FD_LBA      2               ; 文件起始 LBA (2字节)
%define FD_LENGTH   4               ; 文件占用的扇区数 (2字节)
%define FD_OFFSET   6               ; 当前读写偏移 (2字节，未使用)

fd_table times MAX_FDS * FD_SIZE db 0

; ----------------------------------------------------------------
; VFS 初始化 (预留接口)
; ----------------------------------------------------------------
init_vfs:
    ret

; ----------------------------------------------------------------
; VFS 写入操作
; 输入: BX = 文件描述符, DS:SI = 数据指针
;       1 表示标准输出 (屏幕), 2~15 为打开的文件
; 输出: CF=0 成功, CF=1 失败
; ----------------------------------------------------------------
vfs_write:
    pusha
    cmp bx, 1
    je .do_stdout
    cmp bx, 2
    jb .error
    cmp bx, MAX_FDS
    jae .error

    ; 从文件描述符表获取文件信息
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    cmp byte [cs:di + FD_STATE], 0  ; 检查是否已打开
    je .error
    mov al, [cs:di + FD_TYPE]
    cmp al, 3                       ; 类型3 = 磁盘文件
    je .do_disk_write
    jmp .error

.do_stdout:
    call print_string               ; 输出到屏幕
    jmp .success

.do_disk_write:
    push es
    mov ax, [cs:di + FD_LBA]        ; 起始 LBA
    mov cx, [cs:di + FD_LENGTH]     ; 扇区数
    push ds
    pop es                          ; ES = DS (数据段)
    mov bx, si                      ; 数据指针
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
; 输入: BX = 文件描述符 (0=标准输入, 2~15=打开文件)
;       ES:DI = 数据缓冲区
; 输出: CF=0 成功, CF=1 失败
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
    cmp byte [cs:di + FD_STATE], 0  ; 检查文件是否打开
    je .error_pop
    mov cl, [cs:di + FD_TYPE]
    cmp cl, 3                       ; 类型3 = 磁盘文件
    je .do_disk_read

.error_pop:
    pop di
    stc
    ret

.do_stdin:
    call get_char                   ; 从键盘读取字符
    clc
    ret

.do_disk_read:
    mov ax, [cs:di + FD_LBA]        ; 起始 LBA
    mov cx, [cs:di + FD_LENGTH]     ; 扇区数
    pop di                          ; 恢复缓冲区指针 (ES:DI)
    mov bx, di
    call disk_read_lba
    clc
    ret

.error:
    stc
    ret

; ----------------------------------------------------------------
; VFS 打开文件
; 输入: DS:SI = 文件名
; 输出: CF=0 成功, AX=文件描述符 (2~15); CF=1 失败 (文件不存在或表满)
; ----------------------------------------------------------------
vfs_open:
    pusha
    cld
    push ds
    push si

    ; 将文件名转换为 FAT 8.3 格式
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
    mov di, vfs_fat_name + 8        ; 扩展名从第8字节开始
    jmp .copy_name

.done_copy:
    push cs
    pop ds
    mov si, vfs_fat_name
    call fat12_find_file            ; 查找文件
    jc .not_found

    ; 记录文件信息
    add ax, 31                      ; 转换为 LBA (数据区偏移)
    mov [cs:.tmp_lba], ax
    mov ax, cx
    add ax, 511
    shr ax, 9                       ; 计算所需扇区数
    mov [cs:.tmp_sec], ax

    ; 在文件描述符表中查找空闲槽
    mov bx, 2                       ; 从索引2开始 (0,1 为 stdin/stdout)
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
    mov byte [cs:di + FD_STATE], 1
    mov byte [cs:di + FD_TYPE], 3   ; 磁盘文件类型
    mov ax, [cs:.tmp_lba]
    mov [cs:di + FD_LBA], ax
    mov ax, [cs:.tmp_sec]
    mov [cs:di + FD_LENGTH], ax
    mov [cs:.tmp_fd], bx

    popa
    mov ax, [cs:.tmp_fd]
    clc
    ret

.not_found:
    popa
    stc
    ret

.tmp_lba dw 0
.tmp_sec dw 0
.tmp_fd  dw 0
vfs_fat_name times 11 db ' '

; ----------------------------------------------------------------
; VFS 关闭文件
; 输入: BX = 文件描述符
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
    mov byte [cs:di + FD_STATE], 0  ; 标记为空闲
.done:
    popa
    ret

; ----------------------------------------------------------------
; VFS 读取目录列表
; 输出: CX = 文件/目录数量
;       返回的目录项格式 (每个条目20字节):
;         0-10:  文件名 (11字节)
;         11:    属性 (0x10=目录, 0x20=文件)
;         12-13: 保留
;         14-15: 起始簇号
;         16-17: 文件大小
; ----------------------------------------------------------------
vfs_read_dir:
    pusha
    cld
    push es

    ; 根据当前目录类型读取相应扇区
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .read_subdir

    ; 读取根目录 (LBA 19, 14扇区)
    mov ax, 19
    mov cx, 14
    mov bx, 0x7000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov dx, 224                     ; 根目录条目数
    jmp .scan_start

.read_subdir:
    ; 读取子目录 (LBA = 簇号 + 31, 1扇区)
    add ax, 31
    mov cx, 1
    mov bx, 0x7000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov dx, 16                      ; 子目录每扇区16条目

.scan_start:
    pop es                          ; 恢复目标段 (ES:DI 指向输出缓冲区)
    push ds
    mov ax, 0x7000
    mov ds, ax                      ; DS 指向目录数据
    xor si, si

    xor cx, cx
    mov [cs:vfs_tmp_count], cx

.scan_loop:
    mov al, [si]
    or al, al
    jz .done

    cmp al, 0xE5
    je .next_entry

    mov bl, [si + 11]               ; 属性字节
    test bl, 0x08                   ; 跳过卷标 (0x08)
    jnz .next_entry

    ; 复制文件名 (11字节)
    push si
    push cx
    mov cx, 11
    rep movsb                       ; 从 DS:SI 复制到 ES:DI
    pop cx
    pop si

    ; 存储属性字节 (第11字节)
    mov al, bl
    stosb

    ; 填充保留字段 (4字节)
    mov al, ' '
    stosb
    stosb
    stosb
    stosb

    ; 存储起始簇号 (2字节)
    mov ax, [si + 26]
    stosw

    ; 存储文件大小 (2字节)
    mov ax, [si + 28]
    stosw

    inc word [cs:vfs_tmp_count]

.next_entry:
    add si, 32                      ; 每条目32字节
    dec dx
    jnz .scan_loop

.done:
    pop ds
    popa
    mov cx, [cs:vfs_tmp_count]
    clc
    ret

vfs_tmp_count dw 0