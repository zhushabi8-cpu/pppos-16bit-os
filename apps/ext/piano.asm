[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov si, msg_title
    call print_str
.loop:
    mov ah, 0x01
    int 0x80
    cmp al, 27
    je .exit
    cmp al, 'a'
    je .play_do
    cmp al, 's'
    je .play_re
    cmp al, 'd'
    je .play_mi
    cmp al, 'f'
    je .play_fa
    cmp al, 'g'
    je .play_sol
    cmp al, 'h'
    je .play_la
    cmp al, 'j'
    je .play_si
    cmp al, 'k'
    je .play_do_high
    jmp .loop
.play_do:       mov bx, 262
                jmp .play
.play_re:       mov bx, 294
                jmp .play
.play_mi:       mov bx, 330
                jmp .play
.play_fa:       mov bx, 349
                jmp .play
.play_sol:      mov bx, 392
                jmp .play
.play_la:       mov bx, 440
                jmp .play
.play_si:       mov bx, 494
                jmp .play
.play_do_high:  mov bx, 523
                jmp .play
.play:
    mov ah, 0x19
    mov al, 1
    int 0x80
    mov cx, 0x03FF
.delay_outer:
    push cx
    mov cx, 0xFFFF
.delay_inner:
    nop
    nop
    loop .delay_inner
    pop cx
    loop .delay_outer
    mov ah, 0x19
    mov al, 0
    int 0x80
    jmp .loop
.exit:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x04
    int 0x80
print_str:
    mov ah, 0x0E
    mov bx, 0x000F
.p_loop:
    lodsb
    or al, al
    jz .p_done
    int 0x10
    jmp .p_loop
.p_done:
    ret
msg_title:
    db "========================================", 13, 10
    db "      PPP OS - PC Speaker Piano", 13, 10
    db "========================================", 13, 10
    db 13, 10
    db " Play the notes using keys:", 13, 10
    db " [A] Do   (C4)", 13, 10
    db " [S] Re   (D4)", 13, 10
    db " [D] Mi   (E4)", 13, 10
    db " [F] Fa   (F4)", 13, 10
    db " [G] Sol  (G4)", 13, 10
    db " [H] La   (A4) - 440Hz", 13, 10
    db " [J] Si   (B4)", 13, 10
    db " [K] Do+  (C5)", 13, 10
    db 13, 10
    db " Press [ESC] to Exit.", 13, 10, 0
