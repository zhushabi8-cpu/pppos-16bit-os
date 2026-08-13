[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ah, 0x00
    mov si, msg_hello
    int 0x80
    mov ah, 0x04
    int 0x80
msg_hello db "Hello，Welcome", 13, 10, 0
