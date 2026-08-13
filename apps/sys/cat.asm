[BITS 16]
[ORG 0x0000]
start:
.read_loop:
    mov ah, 0x01
    int 0x80
    cmp ax, 0xFFFF
    je .end_of_pipe
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    jmp .read_loop
.end_of_pipe:
    mov ah, 0x00
    mov si, msg_eof
    int 0x80
    mov ah, 0x04
    int 0x80
msg_eof db 13, 10, "--- END OF PIPE ---", 13, 10, 0
