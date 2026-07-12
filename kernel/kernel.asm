; ================================================================
; PPP OS 内核主程序
; 16位实模式，由引导程序加载至 0x0000:0x0000
; ================================================================

[BITS 16]
[ORG 0x0000]

; ----------------------------------------------------------------
; 内核入口点
; 设置段寄存器，保存引导盘号，注册基础中断向量
; ----------------------------------------------------------------
kernel_start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov [boot_drive], dl          ; 保存引导盘号（BIOS 传入 DL）

    ; 注册驱动通信中断 (INT 0x81)
    ; 未加载驱动时使用 dummy_iret 防止空调用崩溃
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x81*4], dummy_iret
    mov word [es:0x81*4+2], cs
    pop es
    sti

    ; 初始化各子系统
    call setup_exceptions          ; 异常处理（INT 0x00-0x1F）
    call setup_keyboard            ; 键盘中断（IRQ1, INT 0x09）
    call setup_mouse               ; 鼠标中断（IRQ12, INT 0x74）
    call setup_syscalls            ; 系统调用（INT 0x80）
    call setup_dos_compat          ; DOS 转译层（INT 0x20/0x21）
    call setup_task_manager        ; 多任务调度器
    call create_daemon_task        ; 创建空闲守护任务
    call run_shell                 ; 启动 Shell（不返回）
    jmp $                          ; 安全回退

; ----------------------------------------------------------------
; 空中断返回（防爆墙）
; 用于未实现的中断向量，仅执行 IRET
; ----------------------------------------------------------------
dummy_iret:
    iret

; ----------------------------------------------------------------
; BIOS 字符输出（AL = 字符）
; 使用 INT 10h AH=0Eh，保持页号 0
; ----------------------------------------------------------------
print_char:
    mov ah, 0x0E
    int 0x10
    ret

; ----------------------------------------------------------------
; BIOS 字符串输出（DS:SI = 以零结尾的字符串）
; ----------------------------------------------------------------
print_string:
    pusha
.loop:
    lodsb
    or al, al
    jz .done
    call print_char
    jmp .loop
.done:
    popa
    ret

; ----------------------------------------------------------------
; 包含各功能模块
; ----------------------------------------------------------------
%include "keyboard.inc"
%include "syscall.inc"
%include "comcall.inc"
%include "fat12.inc"
%include "vfs.inc"
%include "memory.inc"
%include "shell.inc"
%include "task.inc"
%include "panic.inc"
%include "mouse.inc"
%include "sound.inc"

; ================================================================
; ATA PIO 硬盘读取（LBA28 模式）
; 输入: AX = LBA 地址（28 位低 16 位），CX = 扇区数，ES:BX = 目标缓冲区
; 输出: CF=0 成功，数据写入 ES:BX；CF=1 失败
; 说明: 每次读取 1 扇区（512 字节），循环 CX 次
; ================================================================
disk_read_lba:
    pusha
.read_loop:
    push cx
    push ax

    ; 选择驱动器（主盘，LBA 模式，高 4 位 LBA=0）
    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al

    ; 设置扇区计数（每次 1 扇区）
    mov dx, 0x1F2
    mov al, 1
    out dx, al

    ; LBA 低 8 位（0x1F3）
    mov dx, 0x1F3
    pop ax
    push ax
    out dx, al

    ; LBA 中 8 位（0x1F4）
    mov dx, 0x1F4
    mov al, ah
    out dx, al

    ; LBA 高 8 位（0x1F5），28 位地址高 4 位已在 0x1F6 中
    mov dx, 0x1F5
    xor al, al
    out dx, al

    ; 发送读命令（0x20）
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al

    ; 等待 DRQ（数据请求）就绪
.wait_ready:
    in al, dx
    test al, 0x08
    jz .wait_ready

    ; 从数据寄存器读取 256 个 16 位字（512 字节）
    mov dx, 0x1F0
    mov cx, 256
    mov di, bx
    push ds
    push es
    pop ds                ; DS = ES（目标段）
    rep insw
    pop ds

    ; 更新 LBA 和缓冲区指针
    pop ax
    inc ax
    pop cx
    add bx, 512
    loop .read_loop

    popa
    clc
    ret

; ================================================================
; ATA PIO 硬盘写入（LBA28 模式）
; 输入: AX = LBA 地址（28 位低 16 位），CX = 扇区数，ES:BX = 数据源
; 输出: CF=0 成功；CF=1 失败
; ================================================================
disk_write_lba:
    pusha
.write_loop:
    push cx
    push ax

    ; 选择驱动器（主盘，LBA 模式）
    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al

    ; 设置扇区计数
    mov dx, 0x1F2
    mov al, 1
    out dx, al

    ; LBA 低 8 位
    mov dx, 0x1F3
    pop ax
    push ax
    out dx, al

    ; LBA 中 8 位
    mov dx, 0x1F4
    mov al, ah
    out dx, al

    ; LBA 高 8 位
    mov dx, 0x1F5
    xor al, al
    out dx, al

    ; 发送写命令（0x30）
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al

    ; 等待 DRQ 就绪
.wait_ready_w:
    in al, dx
    test al, 0x08
    jz .wait_ready_w

    ; 写入 256 个 16 位字到数据寄存器
    mov dx, 0x1F0
    mov cx, 256
    mov si, bx
    push ds
    push es
    pop ds                ; DS = ES（数据源段）
    rep outsw
    pop ds

    ; 缓存刷新命令
    mov dx, 0x1F7
    mov al, 0xE7
    out dx, al

    ; 等待 BSY 清除
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush

    ; 更新 LBA 和缓冲区指针
    pop ax
    inc ax
    pop cx
    add bx, 512
    loop .write_loop

    popa
    clc
    ret

; ================================================================
; 全局变量
; ================================================================
boot_drive    db 0                     ; BIOS 引导盘号
msg_disk_r_err db "*** STOP: 0x00000013 (HDD_PIO_READ_FAULT)", 0
msg_disk_w_err db "*** STOP: 0x00000014 (HDD_PIO_WRITE_FAULT)", 0