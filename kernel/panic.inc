; ================================================================
; PPP OS 蓝屏（内核恐慌）模块
; 处理 CPU 异常，显示蓝屏错误信息并挂起系统
; ================================================================

; ----------------------------------------------------------------
; 初始化 CPU 异常拦截
; 安装除零、非法指令、通用保护错误的中断向量
; ----------------------------------------------------------------
setup_exceptions:
    cli
    push es
    xor ax, ax
    mov es, ax

    ; 安装除零异常处理（INT 0x00）
    mov word [es:0x00*4], isr_divide_zero
    mov word [es:0x00*4+2], cs

    ; 安装非法指令异常处理（INT 0x06）
    mov word [es:0x06*4], isr_invalid_opcode
    mov word [es:0x06*4+2], cs

    ; 安装通用保护错误处理（INT 0x0D）
    mov word [es:0x0D*4], isr_gpf
    mov word [es:0x0D*4+2], cs

    pop es
    sti
    ret

; ----------------------------------------------------------------
; 硬件异常中断服务程序
; 各异常统一跳转到 kernel_panic，传递对应的错误信息
; ----------------------------------------------------------------
isr_divide_zero:
    mov ax, cs
    mov ds, ax
    mov bx, msg_err_div0
    jmp kernel_panic

isr_invalid_opcode:
    mov ax, cs
    mov ds, ax
    mov bx, msg_err_opcode
    jmp kernel_panic

isr_gpf:
    mov ax, cs
    mov ds, ax
    mov bx, msg_err_gpf
    jmp kernel_panic

; ----------------------------------------------------------------
; 内核恐慌（蓝屏死机）
; 输入: BX = 错误信息字符串指针（DS 需指向 CS）
; 操作: 切换到文本模式，填充蓝色背景，在指定位置显示标题、描述、错误信息和页脚
; 输出: 系统挂起，不再返回
; ----------------------------------------------------------------
kernel_panic:
    cli
    ; 切换到标准 80x25 文本模式
    mov ax, 0x0003
    int 0x10
    ; 隐藏光标
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10

    ; 填充整个屏幕为蓝色背景（白字蓝底空格）
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000                   ; 80*25 = 2000 个字符位置
    mov ax, 0x1F20                 ; 0x1F = 白字蓝底，0x20 = 空格
    rep stosw

    ; 显示标题（第 3 行，第 4 列）
    mov si, msg_bsod_title
    mov di, 160 * 3 + 4            ; 每行 160 字节（80 字符 * 2 字节）
    call panic_print_vram

    ; 显示描述（第 5 行）
    mov si, msg_bsod_desc
    mov di, 160 * 5 + 4
    call panic_print_vram

    ; 显示具体错误信息（第 8 行）
    mov si, bx
    mov di, 160 * 8 + 4
    call panic_print_vram

    ; 显示页脚提示（第 12 行）
    mov si, msg_bsod_footer
    mov di, 160 * 12 + 4
    call panic_print_vram

.die:
    hlt
    jmp .die

; ----------------------------------------------------------------
; 系统致命错误（软件触发蓝屏）
; 输入: SI = 自定义错误描述字符串
; 功能: 与 kernel_panic 类似，但错误信息来自调用方
; ----------------------------------------------------------------
sys_fatal_error:
    cli
    mov ax, 0x0003
    int 0x10
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10

    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000
    mov ax, 0x1F20
    rep stosw

    push si
    mov si, msg_bsod_title
    mov di, 160 * 3 + 4
    call panic_print_vram

    mov si, msg_bsod_desc
    mov di, 160 * 5 + 4
    call panic_print_vram

    pop si                          ; 恢复自定义错误字符串指针
    mov di, 160 * 8 + 4
    call panic_print_vram

    mov si, msg_bsod_footer
    mov di, 160 * 12 + 4
    call panic_print_vram

.die_sys:
    hlt
    jmp .die_sys

; ----------------------------------------------------------------
; 显存直写打印函数
; 输入: DS:SI = 以零结尾的字符串，ES:DI = 显存目标偏移
; 输出: 以白字蓝底（0x1F 属性）写入显存
; 说明: 每写入一个字符占 2 字节（字符 + 属性）
; ----------------------------------------------------------------
panic_print_vram:
.loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x1F                   ; 白字蓝底
    mov [es:di], ax
    add di, 2
    jmp .loop
.done:
    ret

; ----------------------------------------------------------------
; 蓝屏常量数据
; ----------------------------------------------------------------
msg_bsod_title  db "PPP OS - FATAL SYSTEM ERROR", 0
msg_bsod_desc   db "An unhandled CPU exception has occurred. The system has been halted", 0
msg_bsod_footer db "Please restart your computer manually.", 0

msg_err_div0    db "*** STOP: 0x00000000 (DIVIDE_BY_ZERO_EXCEPTION)", 0
msg_err_opcode  db "*** STOP: 0x00000006 (INVALID_OPCODE_EXCEPTION)", 0
msg_err_gpf     db "*** STOP: 0x0000000D (GENERAL_PROTECTION_FAULT)", 0