; ================================================================
; PPP OS 蓝屏
; ================================================================

; ----------------------------------------------------------------
; 初始化 CPU 异常拦截 (安装中断向量)
; ----------------------------------------------------------------
setup_exceptions:
    cli
    push es
    xor ax, ax
    mov es, ax

    ; 安装除零异常处理 (INT 0x00)
    mov word [es:0x00*4], isr_divide_zero
    mov word [es:0x00*4+2], cs

    ; 安装非法指令异常处理 (INT 0x06)
    mov word [es:0x06*4], isr_invalid_opcode
    mov word [es:0x06*4+2], cs

    ; 安装通用保护错误处理 (INT 0x0D)
    mov word [es:0x0D*4], isr_gpf
    mov word [es:0x0D*4+2], cs

    pop es
    sti
    ret

; ----------------------------------------------------------------
; 硬件异常中断服务程序
; 各异常统一跳转到 kernel_panic 显示蓝屏
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
; 内核恐慌 (蓝屏死机)
; 输入: BX = 错误信息字符串指针
; 清屏，切换到文本模式，显示蓝屏并挂起
; ----------------------------------------------------------------
kernel_panic:
    cli
    ; 切换到文本模式
    mov ax, 0x0003
    int 0x10
    ; 隐藏光标
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10

    ; 填充蓝色背景
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000
    mov ax, 0x1F20               ; 白字蓝底 + 空格
    rep stosw

    ; 显示标题 (第3行)
    mov si, msg_bsod_title
    mov di, 160 * 3 + 4
    call panic_print_vram

    ; 显示描述 (第5行)
    mov si, msg_bsod_desc
    mov di, 160 * 5 + 4
    call panic_print_vram

    ; 显示具体错误 (第8行)
    mov si, bx
    mov di, 160 * 8 + 4
    call panic_print_vram

    ; 显示页脚提示 (第12行)
    mov si, msg_bsod_footer
    mov di, 160 * 12 + 4
    call panic_print_vram

.die:
    hlt
    jmp .die

; ----------------------------------------------------------------
; 系统致命错误 (软件触发蓝屏)
; 输入: SI = 自定义错误描述字符串
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

    pop si
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
; 输入: DS:SI = 字符串, ES:DI = 显存目标偏移
; 输出: 白字蓝底 (0x1F) 写入显存
; ----------------------------------------------------------------
panic_print_vram:
.loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x1F                 ; 白字蓝底
    mov [es:di], ax
    add di, 2
    jmp .loop
.done:
    ret

; ----------------------------------------------------------------
; 蓝屏数据
; ----------------------------------------------------------------
msg_bsod_title  db "PPP OS - FATAL SYSTEM ERROR", 0
msg_bsod_desc   db "An unhandled CPU exception has occurred. The system has been halted", 0
msg_bsod_footer db "Please restart your computer manually.", 0

msg_err_div0    db "*** STOP: 0x00000000 (DIVIDE_BY_ZERO_EXCEPTION)", 0
msg_err_opcode  db "*** STOP: 0x00000006 (INVALID_OPCODE_EXCEPTION)", 0
msg_err_gpf     db "*** STOP: 0x0000000D (GENERAL_PROTECTION_FAULT)", 0