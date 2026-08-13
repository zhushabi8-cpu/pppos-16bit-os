[BITS 16]
[ORG 0x0000]
%define MAX_LINES 250
%define LINE_WIDTH 128
%define TEXT_BUF_OFS 0x2000
%define FILE_BUF_OFS 0x9D00
    jmp start
msg_title    db " PPP Studio | F2: Save | F3: Run | F5: Save As | F4: Exit ", 0
msg_status   db " Line: 000 Col: 000 | File: ", 0
msg_comp_ok  db 13, 10, "--- Execution Finished. Press any key to return ---", 0
msg_unsup    db 13, 10, "Cannot Build/Run this file type! Supported: .ASM, .BAS, .PAS", 13, 10, 0
msg_prompt   db " Save As: ", 0
cmd_asm      db "ASM", 0
cmd_pasic    db "PASIC", 0
sys_arg_buf  times 12 db ' '
fat_filename times 12 db ' '
c_filename   times 16 db 0
cursor_x     dw 0
cursor_y     dw 0
scroll_x     dw 0
scroll_y     dw 0
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    cld
    mov di, TEXT_BUF_OFS
    mov cx, MAX_LINES * LINE_WIDTH
    mov al, ' '
    rep stosb
    mov ah, 0x16
    mov di, sys_arg_buf
    int 0x80
    cmp byte [sys_arg_buf], ' '
    je .no_file
    call format_filenames
    call load_file
.no_file:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10
main_loop:
    call draw_screen
    call draw_cursor
.wait_input:
    mov ah, 0x01
    int 0x80
    cmp ah, 0x3C
    jne .check_f3
    call do_save
    jmp main_loop
.check_f3:
    cmp ah, 0x3D
    jne .check_f5
    jmp do_compile
.check_f5:
    cmp ah, 0x3F
    jne .check_f4
    call do_save_as_prompt
    cmp byte [sys_arg_buf], ' '
    je main_loop
    call do_save_disk
    jmp main_loop
.check_f4:
    cmp ah, 0x3E
    je do_exit
    cmp ah, 0x48
    je .move_up
    cmp ah, 0x50
    je .move_down
    cmp ah, 0x4B
    je .move_left
    cmp ah, 0x4D
    je .move_right
    cmp ah, 0x49
    je .page_up
    cmp ah, 0x51
    je .page_down
    cmp ah, 0x47
    je .move_home
    cmp ah, 0x4F
    je .move_end
    cmp al, 8
    je do_backspace
    cmp al, 13
    je do_enter
    cmp al, 32
    jb main_loop
    cmp al, 126
    ja main_loop
    jmp do_type
.move_up:
    cmp word [cursor_y], 0
    je main_loop
    dec word [cursor_y]
    call adjust_scroll
    jmp main_loop
.move_down:
    cmp word [cursor_y], MAX_LINES - 1
    je main_loop
    inc word [cursor_y]
    call adjust_scroll
    jmp main_loop
.move_left:
    cmp word [cursor_x], 0
    jne .ml_ok
    cmp word [cursor_y], 0
    je main_loop
    mov word [cursor_x], LINE_WIDTH - 1
    dec word [cursor_y]
    call adjust_scroll
    jmp main_loop
.ml_ok:
    dec word [cursor_x]
    call adjust_scroll
    jmp main_loop
.move_right:
    cmp word [cursor_x], LINE_WIDTH - 1
    jne .mr_ok
    cmp word [cursor_y], MAX_LINES - 1
    je main_loop
    mov word [cursor_x], 0
    inc word [cursor_y]
    call adjust_scroll
    jmp main_loop
.mr_ok:
    inc word [cursor_x]
    call adjust_scroll
    jmp main_loop
.move_home:
    mov word [cursor_x], 0
    call adjust_scroll
    jmp main_loop
.move_end:
    mov ax, [cursor_y]
    mov bx, LINE_WIDTH
    mul bx
    add ax, TEXT_BUF_OFS
    mov si, ax
    mov bx, LINE_WIDTH - 1
.me_find:
    cmp byte [si+bx], ' '
    jne .me_found
    dec bx
    jns .me_find
    mov bx, -1
.me_found:
    inc bx
    cmp bx, LINE_WIDTH
    jb .me_set
    mov bx, LINE_WIDTH - 1
.me_set:
    mov [cursor_x], bx
    call adjust_scroll
    jmp main_loop
.page_up:
    sub word [cursor_y], 23
    jns .pu_ok
    mov word [cursor_y], 0
.pu_ok:
    sub word [scroll_y], 23
    jns .pu_sok
    mov word [scroll_y], 0
.pu_sok:
    call adjust_scroll
    jmp main_loop
.page_down:
    add word [cursor_y], 23
    cmp word [cursor_y], MAX_LINES
    jb .pd_ok
    mov word [cursor_y], MAX_LINES - 1
.pd_ok:
    add word [scroll_y], 23
    cmp word [scroll_y], MAX_LINES - 23
    jb .pd_sok
    mov word [scroll_y], MAX_LINES - 23
.pd_sok:
    call adjust_scroll
    jmp main_loop
do_type:
    push ax
    mov ax, [cursor_y]
    mov bx, LINE_WIDTH
    mul bx
    add ax, TEXT_BUF_OFS
    mov di, ax
    mov si, di
    add si, LINE_WIDTH - 2
    mov di, si
    inc di
    mov cx, LINE_WIDTH - 1
    sub cx, [cursor_x]
    std
    rep movsb
    cld
    mov ax, [cursor_y]
    mov bx, LINE_WIDTH
    mul bx
    add ax, TEXT_BUF_OFS
    add ax, [cursor_x]
    mov di, ax
    pop ax
    mov [di], al
    cmp word [cursor_x], LINE_WIDTH - 1
    je main_loop
    inc word [cursor_x]
    call adjust_scroll
    jmp main_loop
do_backspace:
    cmp word [cursor_x], 0
    jne .bs_same_line
    cmp word [cursor_y], 0
    je main_loop
    mov word [cursor_x], LINE_WIDTH - 1
    dec word [cursor_y]
    call adjust_scroll
    jmp .bs_erase
.bs_same_line:
    dec word [cursor_x]
.bs_erase:
    mov ax, [cursor_y]
    mov bx, LINE_WIDTH
    mul bx
    add ax, TEXT_BUF_OFS
    mov di, ax
    add di, [cursor_x]
    mov si, di
    inc si
    mov cx, LINE_WIDTH - 1
    sub cx, [cursor_x]
    cld
    rep movsb
    mov byte [di], ' '
    call adjust_scroll
    jmp main_loop
do_enter:
    cmp word [cursor_y], MAX_LINES - 1
    je main_loop
    inc word [cursor_y]
    mov word [cursor_x], 0
    call adjust_scroll
    jmp main_loop
adjust_scroll:
    mov ax, [cursor_y]
    cmp ax, [scroll_y]
    jge .check_bottom
    mov [scroll_y], ax
    jmp .check_x
.check_bottom:
    mov bx, [scroll_y]
    add bx, 22
    cmp ax, bx
    jle .check_x
    sub ax, 22
    mov [scroll_y], ax
.check_x:
    mov ax, [cursor_x]
    cmp ax, [scroll_x]
    jge .check_right
    mov [scroll_x], ax
    ret
.check_right:
    mov bx, [scroll_x]
    add bx, 79
    cmp ax, bx
    jle .done
    sub ax, 79
    mov [scroll_x], ax
.done:
    ret
update_status_numbers:
    pusha
    mov ax, [cursor_y]
    inc ax
    mov bl, 100
    div bl
    add al, '0'
    mov [msg_status + 7], al
    mov al, ah
    xor ah, ah
    mov bl, 10
    div bl
    add al, '0'
    mov [msg_status + 8], al
    add ah, '0'
    mov [msg_status + 9], ah
    mov ax, [cursor_x]
    inc ax
    mov bl, 100
    div bl
    add al, '0'
    mov [msg_status + 16], al
    mov al, ah
    xor ah, ah
    mov bl, 10
    div bl
    add al, '0'
    mov [msg_status + 17], al
    add ah, '0'
    mov [msg_status + 18], ah
    popa
    ret
draw_screen:
    pusha
    push es
    call update_status_numbers
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov ah, 0x1F
    mov si, msg_title
.draw_title:
    lodsb
    or al, al
    jz .fill_title
    stosw
    jmp .draw_title
.fill_title:
    mov al, ' '
    mov cx, 80
    sub cx, 60
    rep stosw
    mov ax, [scroll_y]
    mov bx, LINE_WIDTH
    mul bx
    add ax, [scroll_x]
    add ax, TEXT_BUF_OFS
    mov si, ax
    mov di, 160
    mov cx, 23
.draw_text_lines:
    push cx
    mov cx, 80
    mov ah, 0x07
.draw_char:
    lodsb
    stosw
    loop .draw_char
    mov ax, si
    add ax, LINE_WIDTH - 80
    mov si, ax
    pop cx
    loop .draw_text_lines
    mov di, 24 * 160
    mov ah, 0x30
    mov si, msg_status
.draw_status:
    lodsb
    or al, al
    jz .draw_status_vars
    stosw
    jmp .draw_status
.draw_status_vars:
    mov al, ' '
    mov cx, 80 - 28
    rep stosw
    mov di, 24 * 160 + 56
    mov ah, 0x30
    mov si, sys_arg_buf
    mov cx, 8
.print_fname1:
    lodsb
    cmp al, ' '
    je .skip_fname1
    stosw
    jmp .next_fname1
.skip_fname1:
.next_fname1:
    loop .print_fname1
    mov al, '.'
    stosw
    mov cx, 3
.print_fname2:
    lodsb
    cmp al, ' '
    je .skip_fname2
    stosw
.skip_fname2:
    loop .print_fname2
    pop es
    popa
    ret
draw_cursor:
    pusha
    push es
    mov ax, 0xB800
    mov es, ax
    mov ax, [cursor_y]
    sub ax, [scroll_y]
    inc ax
    mov bx, 80
    mul bx
    mov cx, [cursor_x]
    sub cx, [scroll_x]
    add ax, cx
    shl ax, 1
    mov di, ax
    mov ah, 0x70
    mov al, [es:di]
    mov [es:di], ax
    pop es
    popa
    ret
format_filenames:
    pusha
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb
    mov di, c_filename
    mov cx, 16
    xor al, al
    rep stosb
    mov si, sys_arg_buf
    mov di, fat_filename
    mov bx, c_filename
    mov cx, 8
.f_name:
    lodsb
    cmp al, ' '
    je .f_check_ext
    cmp al, '.'
    je .f_ext
    or al, al
    jz .f_done
    stosb
    mov [bx], al
    inc bx
    loop .f_name
.f_skip:
    lodsb
    cmp al, '.'
    je .f_ext
    cmp al, ' '
    je .f_check_ext
    or al, al
    jz .f_done
    jmp .f_skip
.f_check_ext:
    mov al, [sys_arg_buf + 8]
    cmp al, ' '
    jne .f_shell_ext
    jmp .f_done
.f_shell_ext:
    mov byte [bx], '.'
    inc bx
    mov si, sys_arg_buf + 8
    mov di, fat_filename + 8
    mov cx, 3
.f_shell_ext_loop:
    lodsb
    cmp al, ' '
    je .f_done
    or al, al
    jz .f_done
    stosb
    mov [bx], al
    inc bx
    loop .f_shell_ext_loop
    jmp .f_done
.f_ext:
    mov byte [bx], '.'
    inc bx
    mov di, fat_filename + 8
    mov cx, 3
.f_ext_loop:
    lodsb
    cmp al, ' '
    je .f_done
    or al, al
    jz .f_done
    stosb
    mov [bx], al
    inc bx
    loop .f_ext_loop
.f_done:
    mov byte [bx], 0
    popa
    ret
load_file:
    mov ah, 0x02
    mov si, fat_filename
    mov di, FILE_BUF_OFS
    int 0x80
    or al, al
    jz .done
    mov si, FILE_BUF_OFS
    xor cx, cx
    xor dx, dx
.parse_loop:
    lodsb
    or al, al
    jz .done
    cmp al, 13
    je .parse_loop
    cmp al, 10
    je .parse_nl
    cmp cx, LINE_WIDTH
    jae .parse_loop
    push ax
    mov ax, dx
    mov bx, LINE_WIDTH
    push dx
    mul bx
    pop dx
    add ax, cx
    add ax, TEXT_BUF_OFS
    mov bx, ax
    pop ax
    mov [bx], al
    inc cx
    jmp .parse_loop
.parse_nl:
    inc dx
    xor cx, cx
    cmp dx, MAX_LINES
    jae .done
    jmp .parse_loop
.done:
    ret
do_save:
    cmp byte [sys_arg_buf], ' '
    jne do_save_disk
    call do_save_as_prompt
    cmp byte [sys_arg_buf], ' '
    je do_save_abort
do_save_disk:
    mov si, TEXT_BUF_OFS
    mov di, FILE_BUF_OFS
    mov dx, 0
.save_loop:
    cmp dx, MAX_LINES
    jae .save_end
    mov bx, LINE_WIDTH - 1
.find_end:
    mov al, [si+bx]
    cmp al, ' '
    jne .found
    dec bx
    jns .find_end
    jmp .write_nl
.found:
    mov cx, bx
    inc cx
    rep movsb
.write_nl:
    mov al, 13
    stosb
    mov al, 10
    stosb
    mov ax, dx
    inc ax
    mov bx, LINE_WIDTH
    push dx
    mul bx
    pop dx
    add ax, TEXT_BUF_OFS
    mov si, ax
    inc dx
    jmp .save_loop
.save_end:
    mov byte [di], 0
    mov cx, di
    sub cx, FILE_BUF_OFS
    mov ah, 0x03
    mov si, c_filename
    mov di, FILE_BUF_OFS
    int 0x80
do_save_abort:
    ret
do_save_as_prompt:
    pusha
    mov ax, 0xB800
    mov es, ax
    mov di, 24 * 160
    mov cx, 80
    mov ax, 0x4F20
    rep stosw
    mov si, msg_prompt
    mov di, 24 * 160 + 2
    mov ah, 0x4F
.draw_p:
    lodsb
    or al, al
    jz .input_start
    stosw
    jmp .draw_p
.input_start:
    push ds
    pop es
    mov di, sys_arg_buf
    mov cx, 12
    mov al, ' '
    push di
    rep stosb
    pop di
    mov cx, 0
    mov bx, 24 * 160 + 22
.in_loop:
    mov ah, 0x01
    int 0x80
    cmp al, 27
    je .cancel
    cmp al, 13
    je .done
    cmp al, 8
    je .bs
    cmp al, ' '
    jb .in_loop
    cmp al, '~'
    ja .in_loop
    cmp al, 'a'
    jb .store
    cmp al, 'z'
    ja .store
    sub al, 32
.store:
    cmp cx, 11
    jae .in_loop
    mov [di], al
    inc di
    inc cx
    push es
    mov dx, 0xB800
    mov es, dx
    mov ah, 0x4F
    mov [es:bx], ax
    pop es
    add bx, 2
    jmp .in_loop
.bs:
    or cx, cx
    jz .in_loop
    dec cx
    dec di
    mov byte [di], ' '
    sub bx, 2
    push es
    mov dx, 0xB800
    mov es, dx
    mov word [es:bx], 0x4F20
    pop es
    jmp .in_loop
.done:
    popa
    call format_filenames
    ret
.cancel:
    push ds
    pop es
    mov di, sys_arg_buf
    mov cx, 12
    mov al, ' '
    rep stosb
    popa
    ret
do_compile:
    call do_save
    cmp byte [sys_arg_buf], ' '
    je main_loop
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov si, sys_arg_buf + 8
    cmp byte [si], 'A'
    jne .check_bas
    cmp byte [si+1], 'S'
    jne .check_bas
    cmp byte [si+2], 'M'
    jne .check_bas
    mov si, cmd_asm
    jmp .run_tool
.check_bas:
    cmp byte [si], 'B'
    jne .check_pas
    cmp byte [si+1], 'A'
    jne .check_pas
    cmp byte [si+2], 'S'
    jne .check_pas
    mov si, cmd_pasic
    jmp .run_tool
.check_pas:
    cmp byte [si], 'P'
    jne .unsupported
    cmp byte [si+1], 'A'
    jne .unsupported
    cmp byte [si+2], 'S'
    jne .unsupported
    mov si, cmd_pasic
    jmp .run_tool
.unsupported:
    mov ah, 0x00
    mov si, msg_unsup
    int 0x80
    jmp .wait_ret
.run_tool:
    mov ah, 0x0B
    mov di, sys_arg_buf
    int 0x80
.wait_ret:
    mov ah, 0x00
    mov si, msg_comp_ok
    int 0x80
    mov ah, 0x01
    int 0x80
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10
    jmp main_loop
do_exit:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x04
    int 0x80
