; ================================================================
; PPP OS 内核主程序
; 16位实模式，由引导程序加载至 0x0000:0x0000
; ================================================================

[BITS 16]
[ORG 0x0000]

kernel_start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov [boot_drive], dl          ; 保存引导盘号

    ; 注册驱动通信中断 (INT 0x81)，未加载驱动时使用空函数防止崩溃
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x81*4], dummy_iret
    mov word [es:0x81*4+2], cs
    pop es
    sti

    call setup_exceptions          ; 异常处理
    call setup_keyboard            ; 键盘中断 (IRQ1)
    call setup_mouse               ; 鼠标中断 (IRQ12)
    call setup_syscalls            ; 系统调用 (INT 0x80)
    
    call setup_task_manager        ; 多任务调度器
    call create_daemon_task        ; 创建空闲守护任务
    call run_shell                 ; 启动Shell（不返回）
    jmp $

; 空中断返回（防爆墙）
dummy_iret:
    iret

; BIOS字符输出 (AL=字符)
print_char:
    mov ah, 0x0E
    int 0x10
    ret

; 字符串输出 (DS:SI=地址)
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

; 包含各功能模块
%include "keyboard.inc"
%include "syscall.inc"
%include "fat12.inc"
%include "vfs.inc"
%include "memory.inc"
%include "shell.inc"
%include "task.inc"
%include "panic.inc"
%include "mouse.inc"
%include "sound.inc"

; ATA PIO 硬盘读取 (LBA28)
; 输入: AX=LBA, CX=扇区数, ES:BX=目标缓冲区
; 输出: CF=0成功，数据写入ES:BX
disk_read_lba:
    pusha
.read_loop:
    push cx
    push ax

    mov dx, 0x1F6
    mov al, 0xE0          ; 主盘，LBA模式，高4位=0
    out dx, al

    mov dx, 0x1F2
    mov al, 1             ; 每次读1扇区
    out dx, al

    mov dx, 0x1F3
    pop ax
    push ax
    out dx, al            ; LBA低8位

    mov dx, 0x1F4
    mov al, ah
    out dx, al            ; LBA中8位

    mov dx, 0x1F5
    xor al, al
    out dx, al            ; LBA高8位=0

    mov dx, 0x1F7
    mov al, 0x20          ; 读命令
    out dx, al

.wait_ready:
    in al, dx
    test al, 0x08         ; 等待DRQ=1
    jz .wait_ready

    mov dx, 0x1F0
    mov cx, 256
    mov di, bx
    push ds
    push es
    pop ds                ; 使DS指向目标段 (rep insw使用ES:DI)
    rep insw
    pop ds

    pop ax
    inc ax                ; 下一LBA
    pop cx
    add bx, 512           ; 下一缓冲区
    loop .read_loop

    popa
    clc
    ret

; ================================================================
; ATA PIO 硬盘写入 (LBA28)
; 输入: AX=LBA, CX=扇区数, ES:BX=数据源
; 输出: CF=0成功
; ================================================================
disk_write_lba:
    pusha
.write_loop:
    push cx
    push ax

    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al

    mov dx, 0x1F2
    mov al, 1
    out dx, al

    mov dx, 0x1F3
    pop ax
    push ax
    out dx, al

    mov dx, 0x1F4
    mov al, ah
    out dx, al

    mov dx, 0x1F5
    xor al, al
    out dx, al

    mov dx, 0x1F7
    mov al, 0x30          ; 写命令
    out dx, al

.wait_ready_w:
    in al, dx
    test al, 0x08
    jz .wait_ready_w

    mov dx, 0x1F0
    mov cx, 256
    mov si, bx
    push ds
    push es
    pop ds                ; DS指向数据源 (rep outsw使用DS:SI)
    rep outsw
    pop ds

    mov dx, 0x1F7
    mov al, 0xE7          ; 缓存刷新
    out dx, al

.wait_flush:
    in al, dx
    test al, 0x80         ; 等待BSY=0
    jnz .wait_flush

    pop ax
    inc ax
    pop cx
    add bx, 512
    loop .write_loop

    popa
    clc
    ret

; 全局变量
boot_drive    db 0
msg_disk_r_err db "*** STOP: 0x00000013 (HDD_PIO_READ_FAULT)", 0
msg_disk_w_err db "*** STOP: 0x00000014 (HDD_PIO_WRITE_FAULT)", 0