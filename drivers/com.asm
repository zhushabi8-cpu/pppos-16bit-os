[BITS 16]
[ORG 0x0000]

driver_init:
    pusha
    push ds
    push es
    mov ax, cs
    mov ds, ax

    cli
    xor ax, ax
    mov es, ax
    mov word [es:0x82*4], serial_api_handler
    mov word [es:0x82*4+2], cs
    
    mov dx, 0x3F9
    mov al, 0x00
    out dx, al

    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, 0x0C
    out dx, al
    mov dx, 0x3F9
    mov al, 0x00
    out dx, al

    mov dx, 0x3FB
    mov al, 0x03
    out dx, al

    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al

    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al
    
    sti

    pop es
    pop ds
    popa
    mov al, 1
    retf

serial_api_handler:
    cmp ah, 0x01
    je .send_char
    cmp ah, 0x02
    je .recv_char
    cmp ah, 0x03
    je .recv_char_noblk
    iret

.send_char:
    pusha
    mov bl, al
    mov dx, 0x3FD
.wait_tx:
    in al, dx
    test al, 0x20
    jz .wait_tx
    
    mov dx, 0x3F8
    mov al, bl
    out dx, al
    popa
    iret

.recv_char:
    push dx
    mov dx, 0x3FD
.wait_rx:
    in al, dx
    test al, 0x01
    jz .wait_rx
    
    mov dx, 0x3F8
    in al, dx
    pop dx
    iret

.recv_char_noblk:
    push dx
    mov dx, 0x3FD
    in al, dx
    test al, 0x01
    jz .no_data
    mov dx, 0x3F8
    in al, dx
    mov ah, 1
    jmp .done_noblk
.no_data:
    xor ah, ah
.done_noblk:
    pop dx
    iret