; ================================================================
; PPP OS PS/2 硬件鼠标驱动
; 通过 8042 键盘控制器与 PS/2 鼠标通信，处理 IRQ12 中断
; 维护鼠标坐标（0-639 x 0-199）和按键状态
; ================================================================

mouse_cycle db 0                    ; 数据包接收阶段（0=同步字节等待, 1=X字节, 2=Y字节）
mouse_byte  db 0, 0, 0              ; 3 字节鼠标数据包
mouse_x     dw 320                  ; X 坐标（范围 0-639）
mouse_y     dw 100                  ; Y 坐标（范围 0-199）
mouse_btn   db 0                    ; 按键状态（bit0=左键, bit1=右键, bit2=中键）

; ----------------------------------------------------------------
; 等待 8042 输出缓冲区有数据（可读）
; 检测 OBF（Output Buffer Full）位
; ----------------------------------------------------------------
mouse_wait_read:
    mov cx, 0xFFFF
.loop:
    in al, 0x64
    test al, 1                      ; OBF 位
    jnz .done
    loop .loop
.done:
    ret

; ----------------------------------------------------------------
; 等待 8042 输入缓冲区为空（可写）
; 检测 IBF（Input Buffer Full）位
; ----------------------------------------------------------------
mouse_wait_write:
    mov cx, 0xFFFF
.loop:
    in al, 0x64
    test al, 2                      ; IBF 位
    jz .done
    loop .loop
.done:
    ret

; ----------------------------------------------------------------
; 向鼠标发送命令（通过 8042 控制器）
; 输入: AL = 命令字节
; 协议: 向 0x64 写 0xD4，向 0x60 写命令，读取 ACK（0xFA）
; ----------------------------------------------------------------
mouse_write:
    push ax
    call mouse_wait_write
    mov al, 0xD4                    ; 0xD4: 下一个发送到 0x60 的字节转发给鼠标
    out 0x64, al
    call mouse_wait_write
    pop ax
    out 0x60, al                    ; 发送鼠标命令
    call mouse_wait_read
    in al, 0x60                     ; 读取 ACK（0xFA）并丢弃
    ret

; ----------------------------------------------------------------
; 初始化 PS/2 鼠标硬件
; 启用辅助设备、开启 IRQ12、设置默认值、启用数据报告
; ----------------------------------------------------------------
setup_mouse:
    pusha
    cli

    ; 1. 启用辅助设备（鼠标）
    call mouse_wait_write
    mov al, 0xA8
    out 0x64, al

    ; 2. 读取 8042 配置字节
    call mouse_wait_write
    mov al, 0x20
    out 0x64, al
    call mouse_wait_read
    in al, 0x60

    ; 3. 修改配置：开启 IRQ12
    or al, 2                        ; Bit 1 = 1（Enable IRQ12）
    mov bl, al

    ; 4. 写回配置字节
    call mouse_wait_write
    mov al, 0x60
    out 0x64, al
    call mouse_wait_write
    mov al, bl
    out 0x60, al

    ; 5. 设置默认值并启用数据报告
    mov al, 0xF6                    ; 重置为默认设置
    call mouse_write
    mov al, 0xF4                    ; 开启数据上报
    call mouse_write

    ; 6. 安装中断处理程序（IRQ12 -> INT 0x74）
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x74*4], mouse_isr
    mov word [es:0x74*4+2], cs
    pop es

    ; 7. 解除 IRQ12 屏蔽（从片 8259A）
    in al, 0xA1
    and al, 0xEF                    ; 清除 Bit 4（IRQ12 屏蔽位）
    out 0xA1, al

    sti
    popa
    ret

; ----------------------------------------------------------------
; PS/2 鼠标中断服务程序（IRQ12）
; 读取 3 字节数据包，解析坐标增量和按键状态
; 包含防卡死修复：当键盘数据卡在中断中时丢弃并继续
; ----------------------------------------------------------------
mouse_isr:
    pusha

.next_byte:
    ; 检查状态端口是否有数据
    in al, 0x64
    test al, 0x01                   ; OBF 位（Output Buffer Full）
    jz .end_isr                     ; 缓冲区为空，退出

    ; 检查是否为鼠标数据（AUX 端口）
    test al, 0x20                   ; Bit 5: 1=鼠标数据, 0=键盘数据
    jnz .read_mouse

    ; 键盘数据卡在中断中时，强行读取并丢弃，防止死锁
    in al, 0x60
    jmp .next_byte

.read_mouse:
    in al, 0x60                     ; 读取鼠标字节

    mov bl, [cs:mouse_cycle]
    cmp bl, 0
    je .cycle0
    cmp bl, 1
    je .cycle1
    cmp bl, 2
    je .cycle2
    jmp .next_byte                  ; 安全保护

.cycle0:
    test al, 0x08                   ; 检查同步位（Bit 3 必须为 1）
    jz .next_byte                   ; 同步失败，丢弃

    test al, 0xC0                   ; 检查溢出标志（Bit 6-7）
    jnz .next_byte                  ; 有溢出，丢弃

    mov [cs:mouse_byte], al
    inc byte [cs:mouse_cycle]
    jmp .next_byte

.cycle1:
    mov [cs:mouse_byte+1], al
    inc byte [cs:mouse_cycle]
    jmp .next_byte

.cycle2:
    mov [cs:mouse_byte+2], al
    mov byte [cs:mouse_cycle], 0

    ; --- 解析按键状态（低 3 位）---
    mov al, [cs:mouse_byte]
    and al, 0x07
    mov [cs:mouse_btn], al

    ; --- 解析 X 轴增量（符号扩展）---
    mov al, [cs:mouse_byte+1]
    cbw                             ; 符号扩展到 AX
    mov cx, [cs:mouse_x]
    add cx, ax

    ; X 边界限制（0-639）
    cmp cx, 0
    jge .check_x_max
    mov cx, 0
    jmp .do_y
.check_x_max:
    cmp cx, 639
    jle .do_y
    mov cx, 639

.do_y:
    mov [cs:mouse_x], cx

    ; --- 解析 Y 轴增量（PS/2 方向反向，取负）---
    mov al, [cs:mouse_byte+2]
    cbw
    mov cx, [cs:mouse_y]
    sub cx, ax                      ; Y 轴反向

    ; Y 边界限制（0-199）
    cmp cx, 0
    jge .check_y_max
    mov cx, 0
    jmp .save_y
.check_y_max:
    cmp cx, 199
    jle .save_y
    mov cx, 199

.save_y:
    mov [cs:mouse_y], cx
    jmp .next_byte                  ; 继续检查缓冲区（可能还有数据）

.end_isr:
    ; 发送 EOI 到主片和从片（先从片后主片）
    mov al, 0x20
    out 0xA0, al                    ; 从片 EOI
    out 0x20, al                    ; 主片 EOI

    popa
    iret