start:
    mov ax, cs
    mov ds, ax
    mov ah, 0x00
    mov si, msg_start
    int 0x80
    mov ah, 0x21
    mov bx, 3000
    int 0x80
    mov ah, 0x00
    mov si, msg_end
    int 0x80
    mov ah, 0x04
    int 0x80
msg_start: db "Going to sleep for 3 seconds... (CPU is free now)", 13, 10, 0
msg_end:   db "I am awake!", 13, 10, 0
