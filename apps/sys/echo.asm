[BITS 16]
[ORG 0x0000]
start:
    mov ah, 0x00
    mov si, msg
    int 0x80
    mov ah, 0x04
    int 0x80
msg db "PPP OS PIPES ARE AWESOME!", 13, 10
    db "HELLO WORLD FROM PURE ASM ECHO!", 13, 10, 0
