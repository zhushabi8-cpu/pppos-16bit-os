[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ah, 0x16
    mov di, filename
    int 0x80
    cmp byte [filename], ' '
    je no_file
    mov cx, 1
    mov ah, 0x40
    int 0x80
    or ax, ax
    jz load_failed
    mov [file_seg], ax
    mov es, ax
    xor di, di
    mov si, filename
    mov ah, 0x02
    int 0x80
    or al, al
    jz load_failed
    mov ah, 0x05
    mov si, filename
    int 0x80
    mov bx, ax
    mov ah, 0x09
    int 0x80
    mov [file_size], ax
    mov ah, 0x06
    int 0x80
    mov ax, [file_seg]
    mov word [cur_seg], ax
    mov word [cur_off], 0x0000
    mov byte [is_file_mode], 1
    jmp init_ui
load_failed:
no_file:
    mov word [cur_seg], 0x0000
    mov word [cur_off], 0x0000
    mov byte [is_file_mode], 0
init_ui:
    mov ax, 0x0003
    int 0x10
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10
main_loop:
    call draw_ui
    mov ah, 0x01
    int 0x80
    cmp al, 27
    je exit_app
    cmp al, '+'
    je inc_byte
    cmp al, '='
    je inc_byte
    cmp al, '-'
    je dec_byte
    cmp al, '['
    je dec_seg
    cmp al, ']'
    je inc_seg
    cmp ah, 0x3C
    je save_file
    cmp ah, 0x48
    je move_up
    cmp ah, 0x50
    je move_down
    cmp ah, 0x4B
    je move_left
    cmp ah, 0x4D
    je move_right
    cmp ah, 0x49
    je page_up
    cmp ah, 0x51
    je page_down
    jmp main_loop
exit_app:
    cmp byte [is_file_mode], 1
    jne .do_exit
    mov bx, [file_seg]
    mov ah, 0x41
    int 0x80
.do_exit:
    mov ax, 0x0003
    int 0x10
    mov ah, 0x04
    int 0x80
inc_byte:
    call get_cursor_ptr
    mov al, [es:bx]
    inc al
    mov [es:bx], al
    jmp main_loop
dec_byte:
    call get_cursor_ptr
    mov al, [es:bx]
    dec al
    mov [es:bx], al
    jmp main_loop
dec_seg:
    mov ax, [cur_seg]
    sub ax, 0x1000
    mov [cur_seg], ax
    jmp main_loop
inc_seg:
    mov ax, [cur_seg]
    add ax, 0x1000
    mov [cur_seg], ax
    jmp main_loop
move_up:
    mov al, [cursor_y]
    cmp al, 0
    je .scroll_up
    dec al
    mov [cursor_y], al
    jmp main_loop
.scroll_up:
    mov ax, [cur_off]
    sub ax, 16
    mov [cur_off], ax
    jmp main_loop
move_down:
    mov al, [cursor_y]
    cmp al, 15
    je .scroll_down
    inc al
    mov [cursor_y], al
    jmp main_loop
.scroll_down:
    mov ax, [cur_off]
    add ax, 16
    mov [cur_off], ax
    jmp main_loop
move_left:
    mov al, [cursor_x]
    cmp al, 0
    je main_loop
    dec al
    mov [cursor_x], al
    jmp main_loop
move_right:
    mov al, [cursor_x]
    cmp al, 15
    je main_loop
    inc al
    mov [cursor_x], al
    jmp main_loop
page_up:
    mov ax, [cur_off]
    sub ax, 256
    mov [cur_off], ax
    jmp main_loop
page_down:
    mov ax, [cur_off]
    add ax, 256
    mov [cur_off], ax
    jmp main_loop
save_file:
    cmp byte [is_file_mode], 1
    jne main_loop
    mov ax, [file_seg]
    mov es, ax
    xor di, di
    mov cx, [file_size]
    mov si, filename
    mov ah, 0x03
    int 0x80
    mov ax, 0xB800
    mov es, ax
    mov di, 140
    mov si, msg_saved
    mov ah, 0x4F
    call print_vram
    mov ah, 0x21
    mov bx, 1000
    int 0x80
    jmp main_loop
get_cursor_ptr:
    mov ax, [cur_seg]
    mov es, ax
    mov bx, [cur_off]
    xor ax, ax
    mov al, [cursor_y]
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    add bx, ax
    xor ax, ax
    mov al, [cursor_x]
    add bx, ax
    ret
draw_ui:
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 80
    mov ax, 0x1F20
    rep stosw
    mov di, 2
    mov si, msg_title
    mov ah, 0x1F
    call print_vram
    mov di, 160
    mov word [row_idx], 0
draw_rows:
    mov ax, [row_idx]
    cmp ax, 16
    jge draw_footer
    mov byte [cur_color], 0x07
    mov ax, [cur_seg]
    call print_hex_word_vram
    mov al, ':'
    mov ah, 0x07
    stosw
    mov ax, [row_idx]
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    add ax, [cur_off]
    call print_hex_word_vram
    mov al, ' '
    mov ah, 0x07
    stosw
    stosw
    mov word [col_idx], 0
draw_cols:
    mov ax, [col_idx]
    cmp ax, 16
    jge draw_ascii
    mov byte [cur_color], 0x07
    mov ax, [row_idx]
    cmp al, [cursor_y]
    jne get_byte
    mov ax, [col_idx]
    cmp al, [cursor_x]
    jne get_byte
    mov byte [cur_color], 0x70
get_byte:
    push es
    mov ax, [cur_seg]
    mov es, ax
    mov bx, [cur_off]
    mov ax, [row_idx]
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    add bx, ax
    mov ax, [col_idx]
    add bx, ax
    mov al, [es:bx]
    pop es
    call print_hex_byte_vram
    mov al, ' '
    mov ah, 0x07
    stosw
    inc word [col_idx]
    jmp draw_cols
draw_ascii:
    mov al, '|'
    mov ah, 0x07
    stosw
    mov word [col_idx], 0
draw_ascii_cols:
    mov ax, [col_idx]
    cmp ax, 16
    jge next_row
    push es
    mov ax, [cur_seg]
    mov es, ax
    mov bx, [cur_off]
    mov ax, [row_idx]
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    add bx, ax
    mov ax, [col_idx]
    add bx, ax
    mov al, [es:bx]
    pop es
    cmp al, 32
    jb non_printable
    cmp al, 126
    ja non_printable
    jmp print_char
non_printable:
    mov al, '.'
print_char:
    mov ah, 0x07
    stosw
    inc word [col_idx]
    jmp draw_ascii_cols
next_row:
    mov cx, 4
    mov ax, 0x0720
    rep stosw
    inc word [row_idx]
    jmp draw_rows
draw_footer:
    mov cx, 80 * 8
    mov ax, 0x0720
    rep stosw
    mov di, 160 * 24
    mov cx, 80
    mov ax, 0x3020
    rep stosw
    mov di, 160 * 24 + 2
    mov si, msg_footer
    mov ah, 0x30
    call print_vram
    ret
print_vram:
pv_loop:
    lodsb
    or al, al
    jz pv_done
    stosw
    jmp pv_loop
pv_done:
    ret
print_hex_byte_vram:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call hex_to_ascii
    mov ah, [cur_color]
    stosw
    pop ax
    and al, 0x0F
    call hex_to_ascii
    mov ah, [cur_color]
    stosw
    ret
print_hex_word_vram:
    push ax
    mov al, ah
    call print_hex_byte_vram
    pop ax
    call print_hex_byte_vram
    ret
hex_to_ascii:
    cmp al, 9
    jg hex_alpha
    add al, '0'
    ret
hex_alpha:
    add al, 'A' - 10
    ret
cur_seg      dw 0x0000
cur_off      dw 0x0000
cursor_x     db 0
cursor_y     db 0
row_idx      dw 0
col_idx      dw 0
cur_color    db 0
is_file_mode db 0
file_size    dw 0
file_seg     dw 0
filename     times 12 db 0
msg_title    db "PPP OS Hex Editor [Mem & Disk]", 0
msg_footer   db "Arrows:Move  PgUp/Dn:Scroll  [/]:Seg  +/-:Edit Byte  F2:Save  ESC:Quit", 0
msg_saved    db " SAVED! ", 0
