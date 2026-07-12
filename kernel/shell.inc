; ================================================================
; PPP OS 命令行外壳（Shell）
; 提供命令解释、内部命令执行、外部程序加载（PEX 格式）
; ================================================================

%define KERNEL_LOCK 0x04F0        ; 内核锁标志位（防止嵌套加载）

; ----------------------------------------------------------------
; Shell 主入口（不返回）
; 显示就绪信息，进入命令提示循环
; ----------------------------------------------------------------
run_shell:
    mov si, msg_ready
    call print_string

prompt_loop:
    ; 设置段寄存器为 CS
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; 输出换行和提示符
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    mov si, prompt
    call print_string
    
    mov di, cmd_buffer
    call read_line               ; 从键盘读取一行命令到 cmd_buffer

    mov al, 13
    call print_char
    mov al, 10
    call print_char

    ; 检查空命令
    mov si, cmd_buffer
    lodsb
    or al, al
    jz prompt_loop

    ; 将命令转换为大写以便匹配
    call uppercase_cmd

    ; ---- 优先检查内部命令 ----
    call check_exit_cmd
    jc .handle_exit
    
    ; 安全锁：仅内核空间（CS=0x0800）允许执行命令
    mov ax, cs
    cmp ax, 0x0800
    jne .kernel_locked

    call check_cd_cmd
    jc .run_cd_mode

    call check_md_cmd
    jc .run_md_mode

    call check_dir_cmd
    jc .run_dir_mode

    call check_time_cmd
    jc .run_time_mode

    call check_reboot_cmd
    jc .run_reboot

    call check_shutdown_cmd
    jc .run_shutdown
    
    call check_insmod_cmd
    jc .run_insmod

    ; 清空参数缓冲区，然后尝试执行外部程序
    pusha
    mov ax, cs
    mov es, ax
    mov di, sys_app_arg
    mov cx, 11
    mov al, ' '
    rep stosb
    mov di, sys_app_arg2
    mov cx, 11
    mov al, ' '
    rep stosb
    popa

    call find_and_execute
    jmp prompt_loop

; ---------- INSMOD 命令（加载驱动程序）----------
.run_insmod:
    mov si, cmd_buffer + 7       ; 跳过 "INSMOD "
    mov ah, 0x1E                 ; 系统调用：加载驱动
    int 0x80
    or al, al
    jz .insmod_fail
    mov si, msg_drv_ok
    call print_string
    jmp prompt_loop
.insmod_fail:
    mov si, msg_drv_err
    call print_string
    jmp prompt_loop

; ---------- CD 命令（切换目录）----------
.run_cd_mode:
    mov si, cmd_buffer + 3
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb

    cmp word [cmd_buffer + 3], 0x2E2E   ; ".." 父目录
    jne .fmt_cd
    mov byte [fat_filename], '.'
    mov byte [fat_filename+1], '.'
    jmp .do_cd

.fmt_cd:
    mov si, cmd_buffer + 3
    mov di, fat_filename
.cd_copy:
    lodsb
    or al, al
    jz .do_cd
    cmp al, ' '
    je .do_cd
    stosb
    jmp .cd_copy

.do_cd:
    mov si, fat_filename
    call fat12_change_dir
    jnc .cd_ok
    mov si, msg_cd_err
    call print_string
.cd_ok:
    jmp prompt_loop

; ---------- MD 命令（创建目录）----------
.run_md_mode:
    mov si, cmd_buffer + 3
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb

.fmt_md:
    mov si, cmd_buffer + 3
    mov di, fat_filename
.md_copy:
    lodsb
    or al, al
    jz .do_md
    cmp al, ' '
    je .do_md
    stosb
    jmp .md_copy

.do_md:
    mov si, fat_filename
    call fat12_make_dir
    jnc .md_ok
    mov si, msg_err
    call print_string
.md_ok:
    mov si, msg_md_ok
    call print_string
    jmp prompt_loop

; ---------- DIR 命令（列出目录）----------
.run_dir_mode:
    call print_dir_table
    jmp prompt_loop

; ---------- TIME 命令（显示当前时间）----------
.run_time_mode:
    mov si, msg_time
    call print_string
    mov ah, 0x02
    int 0x1A                     ; BIOS 获取时间（CH=时, CL=分, DH=秒）
    mov al, ch                   ; 小时
    call print_bcd_cli
    mov al, ':'
    call print_char
    mov al, cl                   ; 分钟
    call print_bcd_cli
    mov al, ':'
    call print_char
    mov al, dh                   ; 秒
    call print_bcd_cli
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    jmp prompt_loop

; ---------- REBOOT 命令（重启系统）----------
.run_reboot:
    mov si, msg_rebooting
    call print_string
    mov ax, 0x0040
    mov ds, ax
    mov word [0x0072], 0x1234     ; 设置热启动标志
    jmp 0xFFFF:0000               ; 跳转到 BIOS 入口

; ---------- SHUTDOWN 命令（关机）----------
.run_shutdown:
    mov si, msg_shutdown
    call print_string
    mov ax, 0x5301                ; APM 连接
    xor bx, bx
    int 0x15
    mov ax, 0x530E                ; APM 版本设置
    xor bx, bx
    mov cx, 0x0102
    int 0x15
    mov ax, 0x5307                ; APM 关机
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
    cli
    hlt

; ---------- 内核锁定错误 ----------
.kernel_locked:
    mov si, msg_locked_err
    call print_string
    jmp prompt_loop

; ---------- EXIT 命令处理 ----------
.handle_exit:
    mov ax, cs
    cmp ax, 0x0800
    je .is_primary_shell
    ; 子 Shell 退出，释放锁并返回父任务
    mov si, msg_exit
    call print_string
    xor ax, ax
    mov gs, ax
    mov byte [gs:KERNEL_LOCK], 0
    retf
.is_primary_shell:
    mov si, msg_no_exit
    call print_string
    jmp prompt_loop

; ----------------------------------------------------------------
; 内部命令检测函数
; 比较命令缓冲区与常量字符串，匹配时 CF=1
; ----------------------------------------------------------------

; 检测 INSMOD 命令（7 字符）
check_insmod_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_insmod
    mov cx, 7
    repe cmpsb
    jne .not_ins
    popa
    stc
    ret
.not_ins:
    popa
    clc
    ret

; 检测 CD 命令（3 字符）
check_cd_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_cd
    mov cx, 3
    repe cmpsb
    jne .not_cd
    popa
    stc
    ret
.not_cd:
    popa
    clc
    ret

; 检测 MD 命令（3 字符）
check_md_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_md
    mov cx, 3
    repe cmpsb
    jne .not_md
    popa
    stc
    ret
.not_md:
    popa
    clc
    ret

; 检测 REBOOT 命令（6 字符，必须完全匹配）
check_reboot_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_reboot
    mov cx, 6
    repe cmpsb
    jne .not_r
    lodsb
    or al, al
    jnz .not_r
    popa
    stc
    ret
.not_r:
    popa
    clc
    ret

; 检测 SHUTDOWN 命令（8 字符，必须完全匹配）
check_shutdown_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_shutdown
    mov cx, 8
    repe cmpsb
    jne .not_s
    lodsb
    or al, al
    jnz .not_s
    popa
    stc
    ret
.not_s:
    popa
    clc
    ret

; 检测 TIME 命令（4 字符，必须完全匹配）
check_time_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_time
    mov cx, 4
    repe cmpsb
    jne .not_t
    lodsb
    or al, al
    jnz .not_t
    popa
    stc
    ret
.not_t:
    popa
    clc
    ret

; 检测 DIR 命令（3 字符，必须完全匹配）
check_dir_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_dir
    mov cx, 3
    repe cmpsb
    jne .not_d
    lodsb
    or al, al
    jnz .not_d
    popa
    stc
    ret
.not_d:
    popa
    clc
    ret

; 检测 EXIT 命令（4 字符，必须完全匹配）
check_exit_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_exit
    mov cx, 4
    repe cmpsb
    jne .not_e
    lodsb
    or al, al
    jnz .not_e
    popa
    stc
    ret
.not_e:
    popa
    clc
    ret

; ----------------------------------------------------------------
; 打印当前目录列表（分页显示，每页 20 项）
; 调用 vfs_read_dir 读取目录项到 0x8000:0000
; ----------------------------------------------------------------
print_dir_table:
    pusha
    mov si, msg_sys_dir
    call print_string

    mov ax, 0x8000
    mov es, ax
    xor di, di
    mov al, 20                      ; 最多 20 个条目
    call vfs_read_dir               ; 读取目录项到 ES:0x8000
    
    or cx, cx
    jz .p_empty
    
    mov dx, cx
    push ds
    mov ax, 0x8000
    mov ds, ax
    xor si, si

    mov bp, 0                       ; 行计数器（分页）

.p_loop:
    push dx
    push si
    
    mov ax, cs
    mov ds, ax
    mov si, msg_item_pre
    call print_string
    
    pop si
    push si
    mov ax, 0x8000
    mov ds, ax
    mov cx, 11                      ; 文件名长度（8+3）
.p_char:
    lodsb
    cmp al, ' '
    je .p_next
    push ax
    mov ax, cs
    mov ds, ax
    pop ax
    call print_char
    mov ax, 0x8000
    mov ds, ax
.p_next:
    loop .p_char
    
    pop si
    push si
    mov ax, 0x8000
    mov ds, ax
    mov al, [si + 11]               ; 目录项属性
    test al, 0x10
    jz .print_nl
    
    mov ax, cs
    mov ds, ax
    mov si, msg_dir_tag
    call print_string
    
.print_nl:
    mov ax, cs
    mov ds, ax
    mov al, 13
    call print_char
    mov al, 10
    call print_char

    inc bp
    cmp bp, 20
    jne .no_pause
    
    ; 分页暂停（按任意键继续）
    push ax
    push si
    mov ax, cs
    mov ds, ax
    mov si, msg_pause_dir
    call print_string
    call kb_get_key
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    pop si
    pop ax
    mov bp, 0

.no_pause:
    pop si
    add si, 20                      ; 下一个目录项（每项 20 字节）
    pop dx
    mov ax, 0x8000
    mov ds, ax
    dec dx
    jnz .p_loop
    
    pop ds
    popa
    ret
.p_empty:
    mov si, msg_no_files
    call print_string
    popa
    ret

; ----------------------------------------------------------------
; 查找并执行外部程序（PEX 格式）
; 解析命令名和参数，分配内存，加载程序，创建新任务
; ----------------------------------------------------------------
find_and_execute:
    pusha
    push ds
    push es

    cld
    ; ---- 将命令名转换为 FAT 8.3 格式 ----
    mov si, cmd_buffer
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb
    
    mov si, cmd_buffer
    mov di, fat_filename
.copy_name:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .parse_arg
    cmp al, '.'
    je .next_part
    stosb
    jmp .copy_name
.next_part:
    mov di, fat_filename + 8        ; 转向扩展名部分
    jmp .copy_name

    ; ---- 解析参数1（不含扩展名，最多11字节）----
.parse_arg:
    mov cx, 11
.skip_spaces:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .skip_spaces
    dec si
    mov di, sys_app_arg
.arg_copy:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .parse_arg2
    cmp al, '.'
    je .arg_ext
    jcxz .arg_skip                 ; 已满 11 字节则跳过
    stosb
    dec cx
.arg_skip:
    jmp .arg_copy
.arg_ext:
    mov di, sys_app_arg + 8
    mov cx, 3                      ; 扩展名最多 3 字节
    jmp .arg_copy

    ; ---- 解析参数2（最多11字节）----
.parse_arg2:
    mov cx, 11
.skip_spaces2:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .skip_spaces2
    dec si
    mov di, sys_app_arg2
.arg2_copy:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .add_ext
    cmp al, '-'                    ; 跳过前导连字符
    je .arg2_copy
    jcxz .arg2_skip
    stosb
    dec cx
.arg2_skip:
    jmp .arg2_copy

    ; ---- 若无扩展名，默认添加 .PEX ----
.add_ext:
    cmp byte [fat_filename + 8], ' '
    jne .do_search
    mov di, fat_filename + 8
    mov al, 'P'
    stosb
    mov al, 'E'
    stosb
    mov al, 'X'
    stosb

.do_search:
    mov si, fat_filename
    call fat12_find_file
    jc .not_found

    test dl, 0x10                  ; 是目录则忽略
    jnz .not_found

    or cx, cx
    jz .invalid_format_no_free

    ; 计算数据区 LBA（簇号 + 31）
    add ax, 31
    mov bp, ax

    ; 计算所需扇区数
    mov ax, cx
    add ax, 511
    shr ax, 9
    mov cx, ax

    ; ---- 加内核锁，防止嵌套执行 ----
    xor ax, ax
    mov gs, ax
    mov byte [gs:KERNEL_LOCK], 1

    push cx
    ; ---- 查找空闲 TCB 槽 ----
    mov cx, 4
    mov si, tcb_array
    xor bx, bx
.find_slot:
    cmp byte [si], 0
    je .slot_found
    add si, 32
    inc bx
    loop .find_slot
    pop cx
    jmp .release_lock

.slot_found:
    pop cx
    call kmalloc                    ; 分配 64KB 程序内存
    jc .out_of_memory
    
    ; ---- 加载程序到分配的内存 ----
    mov es, ax
    push ax
    xor bx, bx
    mov ax, bp
    call disk_read_lba              ; 从硬盘读取程序
    
    pop dx
    push ds
    mov ds, dx
    ; 检查 PEX 格式签名（"PP" 0x5050, "P!" 0x2150）
    cmp word [0], 0x5050
    jne .invalid_format_pop
    cmp word [2], 0x2150
    jne .invalid_format_pop
    mov bp, [8]                     ; 程序入口栈顶偏移
    pop ds
    
    inc dx                          ; 跳过 16 字节 PEX 头部

    ; ---- 构造新任务栈帧 ----
    cli
    mov [si + 3], dx                ; TCB_SS = 程序段
    mov ax, ss
    mov cx, sp
    mov ss, dx
    mov sp, bp                      ; 设置栈指针

    pushf
    pop bx
    or bx, 0x0200
    push bx                         ; FLAGS（IF=1）
    push dx                         ; CS
    push word 0x0000                ; IP = 0
    pusha                           ; 通用寄存器
    push dx                         ; DS
    push dx                         ; ES

    mov [si + 1], sp                ; 保存栈指针到 TCB
    mov byte [si + 0], 1            ; 标记任务就绪

    mov ss, ax
    mov sp, cx
    sti

    ; ---- 等待子任务结束 ----
.wait_for_child:
    cmp byte [si + 0], 0
    je .child_exited
    hlt
    jmp .wait_for_child
.child_exited:
    jmp .release_lock

.invalid_format_pop:
    pop ds
    mov ax, dx
    call kfree
.invalid_format_no_free:
    mov si, msg_bad_format
    call print_string
    jmp .release_lock

.not_found:
    mov si, msg_unknown
    call print_string
    jmp .release_lock
    
.out_of_memory:
    mov si, msg_oom
    call print_string

.release_lock:
    xor ax, ax
    mov gs, ax
    mov byte [gs:KERNEL_LOCK], 0

.done:
    pop es
    pop ds
    popa
    ret

; ----------------------------------------------------------------
; 将命令缓冲区字符串转换为大写
; ----------------------------------------------------------------
uppercase_cmd:
    pusha
    mov si, cmd_buffer
.up:
    lodsb
    or al, al
    jz .ok
    cmp al, 'a'
    jb .up
    cmp al, 'z'
    ja .up
    sub al, 32                      ; 小写转大写
    mov [si-1], al
    jmp .up
.ok:
    popa
    ret

; ----------------------------------------------------------------
; 打印 BCD 格式数字（如时间值）
; 输入: AL = BCD 码（高半字节为十位，低半字节为个位）
; ----------------------------------------------------------------
print_bcd_cli:
    push ax
    push bx
    mov bl, al
    shr al, 4                       ; 十位
    add al, '0'
    call print_char
    mov al, bl
    and al, 0x0F                    ; 个位
    add al, '0'
    call print_char
    pop bx
    pop ax
    ret

; ----------------------------------------------------------------
; 消息字符串和命令常量
; ----------------------------------------------------------------
msg_ready      db 13, 10, "PPP OS V1.2 REL Ready.", 0
prompt         db "PPP:\> ", 0
msg_unknown    db 13, 10, "Bad command or file name", 0
msg_locked_err db 13, 10, "LOCKDOWN: Nested loading forbidden!", 0
msg_exit       db 13, 10, "Exiting...", 0
msg_no_exit    db 13, 10, "Primary shell cannot exit!", 0

msg_sys_dir    db 13, 10, " Directory of current folder:", 13, 10, 0
msg_item_pre   db "  - ", 0
msg_dir_tag    db "  <DIR>", 0
msg_no_files   db "  File Not Found", 13, 10, 0
msg_oom        db 13, 10, "System Error: Out of Memory!", 0
msg_time       db 13, 10, "Current time is ", 0

msg_rebooting  db 13, 10, "System is rebooting...", 13, 10, 0
msg_shutdown   db 13, 10, "System is shutting down... Good bye!", 13, 10, 0
msg_err        db 13, 10, "Directory Operation Failed!", 13, 10, 0
msg_md_ok      db 13, 10, "Directory Created successfully.", 13, 10, 0

msg_pause_dir  db "--- Press any key to continue ---", 0

msg_bad_format db 13, 10, "Execution Error: Invalid Executable Format (.PEX expected)!", 13, 10, 0
msg_cd_err     db 13, 10, "Path not found or not a directory.", 13, 10, 0
msg_drv_err    db 13, 10, "Failed to load driver module!", 0
msg_drv_ok     db 13, 10, "Driver loaded successfully.", 0

; 内部命令字符串常量
str_exit       db "EXIT", 0
str_dir        db "DIR", 0
str_time       db "TIME", 0
str_reboot     db "REBOOT", 0
str_shutdown   db "SHUTDOWN", 0
str_cd         db "CD ", 0
str_md         db "MD ", 0
str_insmod     db "INSMOD ", 0

; 全局缓冲区
fat_filename   times 11 db ' '     ; FAT 格式文件名（11 字节）
cmd_buffer     times 64 db 0        ; 命令输入缓冲区