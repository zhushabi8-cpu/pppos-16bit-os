[BITS 16]
[ORG 0x0000]
TARGET_FILE equ 0xFE00
ARG_BUF     equ 0xFE20
start:
    push cs
    pop ds
    push cs
    pop es
    mov si, loader_payload
    mov di, 0xF000
    mov cx, loader_end - loader_payload
    rep movsb
    mov ax, 0xF000
    jmp ax
loader_payload:
    xor di, di
    mov cx, 128
    xor ax, ax
    rep stosw
    mov word [0x0000], 0x20CD
    mov word [0x0002], 0x9FFF
    mov word [0x002C], 0x0000
    mov ah, 0x16
    mov di, TARGET_FILE
    int 0x80
    cmp byte [TARGET_FILE], ' '
    jbe .abort_exit
    mov ah, 0x1D
    mov di, ARG_BUF
    int 0x80
    mov si, ARG_BUF
    mov di, 0x0081
    mov byte [0x0081], ' '
    inc di
    xor cx, cx
.copy_arg:
    lodsb
    cmp al, ' '
    jbe .copy_done
    stosb
    inc cx
    jmp .copy_arg
.copy_done:
    mov al, 0x0D
    stosb
    mov byte [0x0080], cl
    mov ah, 0xFF
    mov bh, 6
    mov bl, 22
    int 0x21
    mov ah, 0x02
    mov si, TARGET_FILE
    mov di, 0x0100
    int 0x80
    or al, al
    jz .abort_exit
    cli
    mov ax, cs
    mov ss, ax
    mov sp, 0xFFFE
    sti
    push word 0x0000
    mov ax, 0x0100
    jmp ax
.abort_exit:
    mov ah, 0x04
    int 0x80
loader_end:
