; ================================================================
; PPP OS 串口通信 (COM1, 中断 0x82)
; ================================================================

[BITS 16]
[ORG 0x0000]                     ; 必须从0偏移加载，配合内核段基址

; ----------------------------------------------------------------
; 驱动初始化入口
; 输出: AL=1 成功, 远返回 (retf) 给内核
; ----------------------------------------------------------------
driver_init:
    pusha
    push ds
    push es
    mov ax, cs
    mov ds, ax

    ; 注册串口API中断 (INT 0x82) 到中断向量表
    cli
    xor ax, ax
    mov es, ax
    mov word [es:0x82*4], serial_api_handler
    mov word [es:0x82*4+2], cs
    sti

    pop es
    pop ds
    popa
    mov al, 1                      ; 返回成功状态
    retf                           ; 远返回

; ----------------------------------------------------------------
; 串口API中断处理 (INT 0x82)
; 功能分发: AH=0x01 发送字符, AH=0x02 接收字符
; ----------------------------------------------------------------
serial_api_handler:
    cmp ah, 0x01
    je .send_char
    cmp ah, 0x02
    je .recv_char
    iret                           ; 未知功能则直接返回

; ---------- 发送字符 (AH=0x01) ----------
; 输入: AL = 要发送的字符
.send_char:
    pusha
    mov dx, 0x3F8                  ; COM1 数据端口
    out dx, al                     ; 直接发送
    popa
    iret

; ---------- 接收字符 (AH=0x02) ----------
; 输出: AL = 接收到的字符 (阻塞等待)
.recv_char:
    push dx
    mov dx, 0x3FD                  ; COM1 线路状态寄存器
.wait_rx:
    in al, dx
    test al, 0x01                  ; 检测数据就绪位 (DR)
    jz .wait_rx                    ; 无数据则等待
    mov dx, 0x3F8                  ; COM1 数据端口
    in al, dx                      ; 读取字符
    pop dx
    iret