[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs
    mov ds, ax

    mov dx, 0x3F8
    mov al, 'B'
    out dx, al
    mov al, 'I'
    out dx, al
    mov al, 'N'
    out dx, al
    mov al, 'G'
    out dx, al
    mov al, 'O'
    out dx, al
    mov al, '!'
    out dx, al

    mov ah, 0x04
    int 0x80