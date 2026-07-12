; ================================================================
; PPP OS 系统调用 (INT 0x80)
; 提供应用程序与内核之间的接口
; ================================================================

; ----------------------------------------------------------------
; 安装系统调用中断处理程序 (INT 0x80)
; ----------------------------------------------------------------
setup_syscalls:
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x80*4], syscall_handler
    mov word [es:0x80*4+2], cs
    pop es
    sti
    ret

; ----------------------------------------------------------------
; 系统调用总入口
; 根据 AH 寄存器中的功能号分发到对应的处理函数
; ----------------------------------------------------------------
syscall_handler:
    push ds
    push es
    pusha                               ; 保存所有通用寄存器

    ; 根据 AH 分发
    cmp ah, 0x00
    je .h_print
    cmp ah, 0x01
    je .h_getkey
    cmp ah, 0x02
    je .h_read
    cmp ah, 0x03
    je .h_write
    cmp ah, 0x04
    je .h_exit
    cmp ah, 0x05
    je .h_open
    cmp ah, 0x06
    je .h_close
    cmp ah, 0x07
    je .h_vfs_read
    cmp ah, 0x0A
    je .h_read_dir
    cmp ah, 0x0B
    je .h_exec
    cmp ah, 0x0C
    je .h_delete
    cmp ah, 0x0D
    je .h_rename
    cmp ah, 0x0E
    je .h_chdir
    cmp ah, 0x0F
    je .h_clip_set
    cmp ah, 0x10
    je .h_clip_paste
    cmp ah, 0x14
    je .h_mouse_get
    cmp ah, 0x15
    je .h_check_key
    cmp ah, 0x16
    je .h_get_arg
    cmp ah, 0x17
    je .h_mkdir
    cmp ah, 0x18
    je .h_mouse_raw
    cmp ah, 0x19
    je .h_sound
    cmp ah, 0x1A
    je .h_play_wav
    cmp ah, 0x1D
    je .h_get_arg2
    cmp ah, 0x1E
    je .h_insmod                     ; 动态加载驱动
    cmp ah, 0x25
    je .h_serial_write
    cmp ah, 0x26
    je .h_serial_read_blk
    cmp ah, 0x27
    je .h_serial_read_noblk

    jmp .exit                         ; 未知功能号则直接返回

; ---------- 系统调用: 打印字符串 (AH=0x00) ----------
; 输入: DS:SI = 字符串, CX = 长度
; 输出: 无返回值
.h_print:
    mov bx, 1                         ; 文件描述符 1（标准输出）
    call vfs_write
    jmp .exit

; ---------- 系统调用: 获取按键 (AH=0x01) ----------
; 输出: AX = 按键值（AH=扫描码, AL=ASCII）
.h_getkey:
    call kb_get_key
    mov bp, sp
    mov [bp + 14], ax                 ; 替换栈上保存的 AX
    jmp .exit

; ---------- 系统调用: 读取文件内容到缓冲区 (AH=0x02) ----------
; 输入: DS:SI = 文件名, ES:DI = 目标缓冲区
; 输出: AL=1 成功, AL=0 失败
.h_read:
    call fat12_find_file
    jc .read_err
    or cx, cx
    jz .read_empty
    add ax, 31                        ; 簇号转 LBA（数据区偏移）
    push cx
    add cx, 511
    shr cx, 9                         ; 计算所需扇区数 = (size+511)/512
    mov bx, di
    call disk_read_lba
    pop cx
    mov bx, di
    add bx, cx
    mov byte [es:bx], 0               ; 添加字符串结束符
    mov al, 1
    jmp .read_done
.read_empty:
    mov al, 1                         ; 空文件也视为成功
    jmp .read_done
.read_err:
    xor al, al
.read_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 写入文件 (AH=0x03) ----------
; 输入: DS:SI = 文件名, ES:DI = 数据源, CX = 数据长度
; 输出: AL=1 成功, AL=0 失败
.h_write:
    mov [cs:sys_tmp_cx], cx
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    push cx
    mov cx, 11
    mov al, ' '
    cld
    rep stosb
    pop cx
    ; 将 C 风格文件名转换为 8.3 FAT 格式
    mov di, sys_fat_name_buf
    mov cx, 8
.w_name_loop:
    lodsb
    or al, al
    jz .w_name_ok
    cmp al, '.'
    je .w_name_ext
    or cx, cx
    jz .w_name_loop
    stosb
    dec cx
    jmp .w_name_loop
.w_name_ext:
    mov di, sys_fat_name_buf + 8
    mov cx, 3
.w_ext_loop:
    lodsb
    or al, al
    jz .w_name_ok
    or cx, cx
    jz .w_ext_loop
    stosb
    dec cx
    jmp .w_ext_loop
.w_name_ok:
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    mov cx, [cs:sys_tmp_cx]
    call fat12_write_file
    pop ds
    jc .write_err
    mov al, 1
    jmp .write_done
.write_err:
    xor al, al
.write_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 打开文件 (AH=0x05) ----------
; 输入: DS:SI = 文件名
; 输出: AX = 文件描述符（成功）, AX=0xFFFF（失败）
.h_open:
    call vfs_open
    jc .open_err
    mov bp, sp
    mov [bp + 14], ax
    jmp .exit
.open_err:
    mov bp, sp
    mov word [bp + 14], 0xFFFF
    jmp .exit

; ---------- 系统调用: 关闭文件 (AH=0x06) ----------
; 输入: BX = 文件描述符
.h_close:
    call vfs_close
    jmp .exit

; ---------- 系统调用: VFS 读取 (AH=0x07) ----------
; 输入: BX = 文件描述符, ES:DI = 缓冲区, CX = 请求字节数
; 输出: AL=1 成功, AL=0 失败
.h_vfs_read:
    call vfs_read
    jc .vr_err
    mov bp, sp
    mov byte [bp + 14], 1
    jmp .exit
.vr_err:
    mov bp, sp
    mov byte [bp + 14], 0
    jmp .exit

; ---------- 系统调用: 退出当前任务 (AH=0x04) ----------
; 将当前任务标记为结束，进入死循环等待调度
.h_exit:
    cli
    mov ax, cs
    mov ds, ax
    xor ah, ah
    mov al, [current_task]
    mov bx, 32
    mul bx
    mov si, tcb_array
    add si, ax
    mov byte [si], 2                  ; 任务状态: 结束
    sti
.die_loop:
    hlt
    jmp .die_loop

; ---------- 系统调用: 读目录 (AH=0x0A) ----------
; 输入: ES:DI = 缓冲区, AL = 最大条目数
; 输出: CX = 实际读取的目录项数
.h_read_dir:
    call vfs_read_dir
    mov bp, sp
    mov [bp + 12], cx
    jmp .exit

; ---------- 系统调用: 删除文件 (AH=0x0C) ----------
; 输入: DS:SI = 文件名（11 字节 FAT 格式）
; 输出: AL=1 成功, AL=0 失败
.h_delete:
    call fat12_delete_file
    jc .del_err
    mov al, 1
    jmp .del_done
.del_err:
    xor al, al
.del_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 重命名文件 (AH=0x0D) ----------
; 输入: DS:SI = 旧文件名, ES:DI = 新文件名（均为 11 字节 FAT 格式）
; 输出: AL=1 成功, AL=0 失败
.h_rename:
    call fat12_rename_file
    jc .ren_err
    mov al, 1
    jmp .ren_done
.ren_err:
    xor al, al
.ren_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 切换目录 (AH=0x0E) ----------
; 输入: DS:SI = 目录名（C 风格字符串）
; 输出: AL=1 成功, AL=0 失败
.h_chdir:
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    push cx
    mov cx, 11
    mov al, ' '
    cld
    rep stosb
    pop cx

    cmp word [si], 0x2E2E             ; ".." 父目录
    jne .cd_fmt
    mov byte [cs:sys_fat_name_buf], '.'
    mov byte [cs:sys_fat_name_buf+1], '.'
    jmp .cd_do

.cd_fmt:
    mov di, sys_fat_name_buf
    mov cx, 8
.cd_loop:
    lodsb
    or al, al
    jz .cd_do
    cmp al, ' '
    je .cd_do
    cmp al, '.'
    je .cd_ext
    or cx, cx
    jz .cd_loop
    stosb
    dec cx
    jmp .cd_loop
.cd_ext:
    mov di, sys_fat_name_buf + 8
    mov cx, 3
.cd_ext_loop:
    lodsb
    or al, al
    jz .cd_do
    cmp al, ' '
    je .cd_do
    or cx, cx
    jz .cd_ext_loop
    stosb
    dec cx
    jmp .cd_ext_loop

.cd_do:
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_change_dir
    pop ds
    jc .cd_err
    mov al, 1
    jmp .cd_done
.cd_err:
    xor al, al
.cd_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 设置剪贴板 (AH=0x0F) ----------
; AL=0 清空剪贴板, AL=1 复制, AL=2 剪切
; DS:SI = 文件名（11 字节 FAT 格式）
; 输出: AL=1 成功, AL=0 失败
.h_clip_set:
    cmp al, 0
    jne .append_clip
    mov byte [cs:clip_count], 0
    mov byte [cs:clip_op], 0
    jmp .clip_set_ok

.append_clip:
    cmp byte [cs:clip_count], 64       ; 最多 64 个文件
    jae .clip_set_fail
    mov [cs:clip_op], al
    mov bx, [cs:cwd_cluster]
    mov [cs:clip_dir], bx
    xor ah, ah
    mov al, [cs:clip_count]
    mov cx, 11
    mul cx
    mov di, clip_names
    add di, ax
    push es
    push cs
    pop es
    mov cx, 11
    cld
    rep movsb                         ; 复制文件名到剪贴板
    pop es
    inc byte [cs:clip_count]
.clip_set_ok:
    mov al, 1
    mov bp, sp
    mov [bp + 14], al
    jmp .exit
.clip_set_fail:
    xor al, al
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 粘贴剪贴板 (AH=0x10) ----------
; 将剪贴板中的文件复制或移动到当前目录
; 输出: AL=1 成功, AL=0 失败
.h_clip_paste:
    cmp byte [cs:clip_op], 0
    je .paste_fail
    cmp byte [cs:clip_count], 0
    je .paste_fail

    mov bx, [cs:cwd_cluster]
    mov [cs:paste_dest_dir], bx
    mov byte [cs:.paste_idx], 0

.paste_loop:
    mov al, [cs:.paste_idx]
    cmp al, [cs:clip_count]
    jae .paste_done

    xor ah, ah
    mov cx, 11
    mul cx
    mov si, clip_names
    add si, ax
    mov [cs:.current_name], si

    ; 切换到源目录查找文件
    mov bx, [cs:clip_dir]
    mov [cs:cwd_cluster], bx
    push cs
    pop ds
    mov si, [cs:.current_name]
    call fat12_find_file
    jc .paste_next_restore

    mov [cs:paste_size], cx
    or cx, cx
    jz .do_write

    ; 读取文件到临时缓冲区 (0x5000:0000)
    push ax
    push cx
    add ax, 31
    pop cx
    add cx, 511
    shr cx, 9
    mov bx, 0x5000
    mov es, bx
    xor bx, bx
    call disk_read_lba
    pop ax

    ; 如果是剪切操作，删除源文件
    cmp byte [cs:clip_op], 2
    jne .do_write
    mov si, [cs:.current_name]
    call fat12_delete_file

.do_write:
    ; 写入到目标目录
    mov bx, [cs:paste_dest_dir]
    mov [cs:cwd_cluster], bx
    mov si, [cs:.current_name]
    mov cx, [cs:paste_size]
    mov ax, 0x5000
    mov es, ax
    xor di, di
    call fat12_write_file

.paste_next:
    inc byte [cs:.paste_idx]
    jmp .paste_loop

.paste_next_restore:
    mov bx, [cs:paste_dest_dir]
    mov [cs:cwd_cluster], bx
    jmp .paste_next

.paste_done:
    ; 剪切操作完成后清空剪贴板
    cmp byte [cs:clip_op], 2
    jne .paste_exit_ok
    mov byte [cs:clip_count], 0
    mov byte [cs:clip_op], 0
.paste_exit_ok:
    mov al, 1
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

.paste_fail:
    xor al, al
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

.paste_idx db 0
.current_name dw 0

; ---------- 系统调用: 获取鼠标位置（字符坐标）(AH=0x14) ----------
; 输出: CX=列 (X/8), DX=行 (Y/8), BX=按键状态
.h_mouse_get:
    mov cx, [cs:mouse_x]
    shr cx, 3                         ; 像素转字符列
    mov dx, [cs:mouse_y]
    shr dx, 3                         ; 像素转字符行
    mov bl, [cs:mouse_btn]
    xor bh, bh
    mov bp, sp
    mov [bp + 12], cx
    mov [bp + 10], dx
    mov [bp + 8], bx
    jmp .exit

; ---------- 系统调用: 获取原始鼠标像素坐标 (AH=0x18) ----------
; 输出: CX=X 坐标, DX=Y 坐标, BX=按键状态
.h_mouse_raw:
    mov cx, [cs:mouse_x]
    mov dx, [cs:mouse_y]
    mov bl, [cs:mouse_btn]
    xor bh, bh
    mov bp, sp
    mov [bp + 12], cx
    mov [bp + 10], dx
    mov [bp + 8], bx
    jmp .exit

; ---------- 系统调用: 非阻塞检测按键 (AH=0x15) ----------
; 输出: AX=按键值（有按键）, AX=0（无按键）
.h_check_key:
    call kb_check_key
    mov bp, sp
    mov [bp + 14], ax
    jmp .exit

; ---------- 系统调用: 获取命令行参数1 (AH=0x16) ----------
; 输出: ES:DI = 参数1（11 字节）
.h_get_arg:
    push ds
    push cs
    pop ds
    mov si, sys_app_arg
    mov cx, 11
    rep movsb
    pop ds
    jmp .exit

; ---------- 系统调用: 获取命令行参数2 (AH=0x1D) ----------
; 输出: ES:DI = 参数2（11 字节）
.h_get_arg2:
    push ds
    push cs
    pop ds
    mov si, sys_app_arg2
    mov cx, 11
    rep movsb
    pop ds
    jmp .exit

; ---------- 系统调用: 创建目录 (AH=0x17) ----------
; 输入: DS:SI = 目录名（11 字节 FAT 格式）
; 输出: AL=1 成功, AL=0 失败
.h_mkdir:
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    mov cx, 11
    cld
    rep movsb
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_make_dir
    pop ds
    jc .md_err
    mov al, 1
    jmp .md_done
.md_err:
    xor al, al
.md_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 执行程序 (AH=0x0B) ----------
; 输入: DS:SI = 命令字符串, ES:DI = 参数1（11 字节）
; 输出: 无返回值（新任务接管）
.h_exec:
    sti
    cld
    push ds
    push es
    push di

    ; 复制命令到 cmd_buffer
    mov ax, cs
    mov es, ax
    mov di, cmd_buffer
.copy_cmd:
    lodsb
    stosb
    or al, al
    jnz .copy_cmd

    ; 复制参数1到 sys_app_arg
    pop si
    mov di, sys_app_arg
    mov cx, 11
    rep movsb

    ; 清空参数2
    mov di, sys_app_arg2
    mov cx, 11
    mov al, ' '
    rep stosb

    mov ax, cs
    mov ds, ax
    call find_and_execute
    pop es
    pop ds
    jmp .exit

; ================================================================
; 系统调用: 加载驱动模块 (AH=0x1E, INSMOD)
; 驱动加载到固定的 16KB 驱动舱 (段地址 0x1400)，不使用 kmalloc
; 输入: DS:SI = 驱动文件名（C 风格字符串）
; 输出: AL=1 成功, AL=0 失败
; ================================================================
.h_insmod:
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    push cx
    mov cx, 11
    mov al, ' '
    cld
    rep stosb
    pop cx

    ; 1. 将文件名转换为 8.3 FAT 格式
    mov di, sys_fat_name_buf
    mov cx, 8
.ins_name_loop:
    lodsb
    cmp al, '.'
    je .ins_ext
    cmp al, ' '
    je .ins_do
    or al, al
    jz .ins_do
    stosb
    loop .ins_name_loop
    jmp .ins_skip_to_ext
.ins_skip_to_ext:
    lodsb
    cmp al, '.'
    je .ins_ext
    or al, al
    jz .ins_do
    jmp .ins_skip_to_ext
.ins_ext:
    mov di, sys_fat_name_buf + 8
    mov cx, 3
.ins_ext_loop:
    lodsb
    cmp al, ' '
    je .ins_do
    or al, al
    jz .ins_do
    stosb
    loop .ins_ext_loop

.ins_do:
    pop di
    pop es

    ; 2. 查找驱动文件
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_find_file
    pop ds
    jc .insmod_err

    ; 3. 目标地址：固定的 16KB 驱动舱 (0x1400:0000)
    mov word [cs:.drv_ptr+2], 0x1400    ; 段地址
    mov word [cs:.drv_ptr], 0x0000      ; 偏移量

    ; 4. 先读到临时缓冲区 (0x1C00:0000)
    add ax, 31                          ; 簇号转 LBA
    mov bp, ax
    mov ax, cx
    add ax, 511
    shr ax, 9
    mov cx, ax                          ; 扇区数

    push es
    mov ax, 0x1C00
    mov es, ax
    xor bx, bx
    mov ax, bp
    call disk_read_lba
    pop es
    jc .insmod_err

    ; 5. 将机器码搬移到驱动舱
    push ds
    push es
    mov ax, 0x1C00
    mov ds, ax
    xor si, si

    mov ax, 0x1400
    mov es, ax
    xor di, di

    ; 检查 PEX 头并跳过（如果存在）
    cmp word [ds:0], 0x5050
    jne .raw_bin
    add si, 16                          ; 跳过 16 字节 PEX 头部
.raw_bin:
    shl cx, 9                           ; 扇区数转字节数
    rep movsb                           ; 精确复制

    pop es
    pop ds

    ; 6. 远调用触发驱动的初始化入口
    call far [cs:.drv_ptr]
    cmp al, 1
    je .insmod_ok
    jmp .insmod_err

.insmod_ok:
    mov al, 1
    jmp .insmod_exit
.insmod_err:
    xor al, al
.insmod_exit:
    mov bp, sp
    mov [bp+14], al
    jmp .exit

.drv_ptr dd 0

; ---------- 系统调用: 蜂鸣器控制 (AH=0x19) ----------
; AL=1 打开蜂鸣器, AL=0 关闭蜂鸣器
.h_sound:
    cmp al, 1
    je .sound_on
    cmp al, 0
    je .sound_off
    jmp .exit
.sound_on:
    call pc_beep_on
    jmp .exit
.sound_off:
    call pc_beep_off
    jmp .exit

; ---------- 系统调用: 播放 WAV 音频 (AH=0x1A) ----------
; 转发到驱动 (INT 0x81 AH=0x02)
.h_play_wav:
    mov ah, 0x02
    int 0x81
    jmp .exit

; ---------- 系统调用: 串口发送 (AH=0x25) ----------
; 转发到串口驱动 (INT 0x82 AH=0x01)
.h_serial_write:
    mov ah, 0x01
    int 0x82
    jmp .exit

; ---------- 系统调用: 串口阻塞接收 (AH=0x26) ----------
; 转发到串口驱动 (INT 0x82 AH=0x02)
.h_serial_read_blk:
    mov ah, 0x02
    int 0x82
    mov bp, sp
    mov [bp + 14], al
    jmp .exit

; ---------- 系统调用: 串口非阻塞接收 (AH=0x27) ----------
; 转发到串口驱动 (INT 0x82 AH=0x03)
.h_serial_read_noblk:
    mov ah, 0x03
    int 0x82
    mov bp, sp
    mov [bp + 14], ax
    jmp .exit

; ---------- 系统调用返回 ----------
.exit:
    popa
    pop es
    pop ds
    iret

; ----------------------------------------------------------------
; 全局变量（仅本文件使用）
; ----------------------------------------------------------------
sys_fat_name_buf times 11 db ' '        ; FAT 8.3 文件名缓冲区
clip_op         db 0                    ; 剪贴板操作类型（1=复制, 2=剪切）
clip_dir        dw 0                    ; 剪贴板源目录簇号
clip_count      db 0                    ; 剪贴板中文件数量
clip_names      times 64 * 11 db ' '    ; 剪贴板文件名列表（最多 64 个）
paste_dest_dir  dw 0                    ; 粘贴目标目录簇号
paste_size      dw 0                    ; 粘贴文件大小
sys_app_arg     times 11 db ' '         ; 应用程序参数1（11 字节）
sys_app_arg2    times 11 db ' '         ; 应用程序参数2（11 字节）
sys_tmp_cx      dw 0                    ; 临时保存 CX