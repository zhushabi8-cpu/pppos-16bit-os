start:
    mov ax, cs
    mov ds, ax
    mov ah, 0x00
    mov si, msg_alloc
    int 0x80
    mov ah, 0x40
    int 0x80
    cmp ax, 0
    je alloc_fail
    mov es, ax
    mov bx, ax
    mov di, 0
    mov al, 'H'
    mov [es:di], al
    mov al, 'E'
    mov [es:di+1], al
    mov al, 'A'
    mov [es:di+2], al
    mov al, 'P'
    mov [es:di+3], al
    mov al, ' '
    mov [es:di+4], al
    mov al, 'O'
    mov [es:di+5], al
    mov al, 'K'
    mov [es:di+6], al
    mov al, '!'
    mov [es:di+7], al
    mov al, 0
    mov [es:di+8], al
    push ds
    mov ds, bx
    mov si, 0
    mov ah, 0x00
    int 0x80
    pop ds
    mov ah, 0x41
    int 0x80
    mov ah, 0x00
    mov si, msg_free
    int 0x80
    mov ah, 0x04
    int 0x80
alloc_fail:
    mov ah, 0x00
    mov si, msg_fail
    int 0x80
    mov ah, 0x04
    int 0x80
msg_alloc: db "Allocating 64KB dynamic memory...", 13, 10, 0
msg_free:  db 13, 10, "Memory freed successfully!", 13, 10, 0
msg_fail:  db "Malloc Failed! Out of memory.", 13, 10, 0
