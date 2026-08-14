[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ah, 0x16
    mov di, target_file
    int 0x80
    cmp byte [target_file], ' '
    je .err_no_args
    mov ah, 0x02
    mov si, target_file
    mov di, img_buffer
    int 0x80
    or al, al
    jz .err_not_found
    mov si, img_buffer
    cmp word [si], 0x4D42
    jne .err_format
    cmp word [si + 28], 8
    jne .err_format_color
    mov ax, [si + 18]
    mov [cs:img_width], ax
    mov ax, [si + 22]
    mov [cs:img_height], ax
    mov ax, [si + 10]
    mov [cs:pixel_offset], ax
    mov ax, [si + 14]
    add ax, 14
    mov [cs:palette_offset], ax
    mov ah, 0x00
    mov al, 0x13
    int 0x10
    mov si, img_buffer
    add si, [cs:palette_offset]
    mov cx, 256
    mov dx, 0x03C8
    xor al, al
    out dx, al
    inc dx
.load_palette:
    mov bl, [si + 0]
    mov al, [si + 2]
    shr al, 2
    out dx, al
    mov al, [si + 1]
    shr al, 2
    out dx, al
    mov al, bl
    shr al, 2
    out dx, al
    add si, 4
    loop .load_palette
    mov ax, 320
    sub ax, [cs:img_width]
    jns .x_ok
    xor ax, ax
.x_ok:
    shr ax, 1
    mov [cs:screen_x], ax
    mov ax, 200
    sub ax, [cs:img_height]
    jns .y_ok
    xor ax, ax
.y_ok:
    shr ax, 1
    add ax, [cs:img_height]
    dec ax
    mov [cs:screen_y], ax
    mov ax, [cs:img_width]
    add ax, 3
    and ax, 0xFFFC
    mov [cs:padded_width], ax
    mov ax, 0xA000
    mov es, ax
    mov si, img_buffer
    add si, [cs:pixel_offset]
    mov cx, [cs:img_height]
.draw_row:
    push cx
    cmp word [cs:screen_y], 0
    jl .skip_draw
    mov ax, [cs:screen_y]
    mov bx, 320
    mul bx
    add ax, [cs:screen_x]
    mov di, ax
    mov cx, [cs:img_width]
    cmp cx, 320
    jbe .width_ok
    mov cx, 320
.width_ok:
    rep movsb
    mov ax, [cs:padded_width]
    sub ax, [cs:img_width]
    add si, ax
    dec word [cs:screen_y]
.skip_draw:
    pop cx
    loop .draw_row
.wait_exit:
    mov ah, 0x01
    int 0x80
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x04
    int 0x80
.err_no_args:
    mov si, msg_no_arg
    jmp .print_err
.err_not_found:
    mov si, msg_not_found
    jmp .print_err
.err_format:
    mov si, msg_format
    jmp .print_err
.err_format_color:
    mov si, msg_color
.print_err:
    mov ax, 0xB800
    mov es, ax
    mov di, 0
    mov ah, 0x0C
.e_loop:
    lodsb
    or al, al
    jz .e_done
    stosw
    jmp .e_loop
.e_done:
    jmp .wait_exit
msg_no_arg    db "Usage: PICVIEW <FILE.BMP>", 0
msg_not_found db "Error: File not found!", 0
msg_format    db "Error: Not a valid BMP file!", 0
msg_color     db "Error: MUST be 256-color (8-bit) BMP!", 0
target_file   times 11 db ' '
img_width     dw 0
img_height    dw 0
pixel_offset  dw 0
palette_offset dw 0
padded_width  dw 0
screen_x      dw 0
screen_y      dw 0
img_buffer    equ $
