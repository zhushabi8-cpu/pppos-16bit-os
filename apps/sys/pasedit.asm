[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov di, text_buffer
    mov cx, 1920
    mov al, ' '
    rep stosb

    mov ah, 0x16
    mov di, arg_buffer
    int 0x80

    cmp byte [arg_buffer], ' '
    je .load_default
    
    mov si, arg_buffer
    mov di, filename_buf
    mov cx, 8
.parse_name:
    lodsb
    cmp al, ' '
    je .skip_name_spaces
    stosb
.skip_name_spaces:
    loop .parse_name
    
    cmp byte [arg_buffer + 8], ' '
    je .parse_done
    
    mov al, '.'
    stosb
    mov cx, 3
.parse_ext:
    lodsb
    cmp al, ' '
    je .skip_ext_spaces
    stosb
.skip_ext_spaces:
    loop .parse_ext

.parse_done:
    xor al, al
    stosb
    jmp .try_load

.load_default:
    mov si, str_default
    mov di, filename_buf
    mov cx, 13
    rep movsb
    mov byte [cs:load_status], 0
    jmp .init_ui      

.try_load:
    mov ah, 0x02
    mov si, filename_buf    
    mov di, text_buffer
    int 0x80
    mov [cs:load_status], al    

.init_ui:
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    mov ah, 0x01
    mov cx, 0x0607
    int 0x10

    call draw_ui

    mov al, [cs:load_status]
    or al, al
    jz .new_file

    mov ax, 0xB800
    mov es, ax
    mov si, text_buffer
    mov di, 160          
    mov cx, 1920         
.load_scr:
    lodsb
    mov ah, 0x1F         
    stosw
    loop .load_scr

    mov di, 1919
.find_end:
    cmp byte [text_buffer + di], ' '
    jne .found_end
    or di, di
    jz .found_end
    dec di
    jmp .find_end
.found_end:
    inc di
    cmp di, 1920
    jne .calc_cursor
    dec di
.calc_cursor:
    mov ax, di
    mov bl, 80
    div bl
    mov byte [cs:cursor_x], ah
    inc al              
    mov byte [cs:cursor_y], al
    jmp .ready

.new_file:
    mov word [cs:cursor_x], 0
    mov word [cs:cursor_y], 1

.ready:
    call update_cursor

.edit_loop:
    push cs
    pop es

    mov ah, 0x01
    int 0x80
    
    cmp al, 27
    je .exit_app
    cmp ah, 0x3C
    je .handle_save      
    cmp ah, 0x3F
    je .handle_run
    
    cmp al, 8
    je .do_backspace
    cmp al, 13
    je .do_enter
    
    cmp al, 32           
    jb .edit_loop
    cmp al, 126
    ja .edit_loop

.do_type:
    call write_char
    inc word [cs:cursor_x]
    cmp word [cs:cursor_x], 80
    jb .skip_wrap
    mov word [cs:cursor_x], 0
    inc word [cs:cursor_y]
    cmp word [cs:cursor_y], 24
    jb .skip_wrap
    mov word [cs:cursor_y], 23
.skip_wrap:
    call update_cursor
    jmp .edit_loop

.do_backspace:
    cmp word [cs:cursor_x], 0
    jne .bs_same_line
    cmp word [cs:cursor_y], 1
    je .edit_loop        
    mov word [cs:cursor_x], 79
    dec word [cs:cursor_y]
    jmp .bs_erase
.bs_same_line:
    dec word [cs:cursor_x]
.bs_erase:
    mov al, ' '
    call write_char
    call update_cursor
    jmp .edit_loop

.do_enter:
    mov word [cs:cursor_x], 0
    inc word [cs:cursor_y]
    cmp word [cs:cursor_y], 24
    jb .ent_ok
    mov word [cs:cursor_y], 23
.ent_ok:
    call update_cursor
    jmp .edit_loop

.handle_run:
    call extract_and_save
    mov di, arg_buffer
    mov cx, 11
    mov al, ' '
    rep stosb
    mov si, filename_buf
    mov di, arg_buffer
    mov cx, 8
.conv_name:
    lodsb
    or al, al
    jz .do_exec
    cmp al, '.'
    je .conv_ext
    stosb
    loop .conv_name
    jmp .skip_to_ext
.conv_ext:
    mov di, arg_buffer + 8
    mov cx, 3
.conv_ext_loop:
    lodsb
    or al, al
    jz .do_exec
    stosb
    loop .conv_ext_loop
    jmp .do_exec
.skip_to_ext:
    lodsb
    cmp al, '.'
    je .conv_ext
    or al, al
    jnz .skip_to_ext

.do_exec:
    mov ax, 0x0003
    int 0x10

    mov ah, 0x0B
    mov si, str_pasic
    mov di, arg_buffer
    int 0x80

    mov si, msg_run_done
.print_done:
    lodsb
    or al, al
    jz .wait_key
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    jmp .print_done

.wait_key:
    mov ah, 0x01
    int 0x80
    jmp .init_ui
.handle_save:
    cmp byte [cs:load_status], 0
    jz .save_prompt      
    call extract_and_save
    jmp .show_saved

.save_prompt:
    mov ax, 0xB800
    mov es, ax
    mov di, 3840
    mov cx, 80
    mov ax, 0x7020
    rep stosw

    mov di, 3842
    mov ah, 0x70
    mov si, str_prompt
.p_loop:
    lodsb
    or al, al
    jz .input_start
    stosw
    jmp .p_loop

.input_start:
    push cs
    pop es                   
    mov di, custom_filename
    mov cx, 0
    mov bx, 3862          

.input_loop:
    mov ah, 0x01
    int 0x80
    cmp al, 27          
    je .cancel_save
    cmp al, 13          
    je .do_extract
    cmp al, 8           
    je .bs

    cmp al, ' '
    jb .input_loop
    cmp al, '~'
    ja .input_loop
    cmp al, 'a'
    jb .store_char
    cmp al, 'z'
    ja .store_char
    sub al, 32
.store_char:
    cmp cx, 12          
    jae .input_loop
    stosb               
    inc cx
    
    push es
    push di
    mov di, 0xB800
    mov es, di          
    mov di, bx
    mov byte [es:di], al
    add bx, 2
    pop di
    pop es              
    jmp .input_loop

.bs:
    or cx, cx
    jz .input_loop
    dec cx
    dec di
    sub bx, 2
    push es
    push di
    mov di, 0xB800
    mov es, di
    mov di, bx
    mov byte [es:di], ' '
    pop di
    pop es
    jmp .input_loop

.cancel_save:
    call draw_ui
    call update_cursor
    jmp .edit_loop

.do_extract:
    mov byte [di], 0
    mov si, custom_filename
    mov di, filename_buf
    push cx
    mov cx, 16
    rep movsb
    pop cx
    mov byte [cs:load_status], 1
    call extract_and_save

.show_saved:
    call draw_ui
    call update_cursor
    mov ax, 0xB800
    mov es, ax
    mov di, 136
    mov si, str_saved
    mov ah, 0x70
.show_ok:
    lodsb
    or al, al
    jz .back_to_edit
    stosw
    jmp .show_ok

.back_to_edit:
    jmp .edit_loop

.exit_app:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x04
    int 0x80

extract_and_save:
    pusha
    mov ax, 0xB800
    mov es, ax
    mov di, 160          
    mov cx, 1920         
    mov bx, text_buffer
.extract_loop:
    mov al, [es:di]      
    mov [cs:bx], al
    add di, 2
    inc bx
    loop .extract_loop

    push cs
    pop ds
    push cs
    pop es
    mov ah, 0x03
    mov si, filename_buf  
    mov di, text_buffer
    mov cx, 1920         
    int 0x80
    popa
    ret

draw_ui:
    pusha
    mov ax, 0xB800
    mov es, ax
    
    mov di, 0
    mov cx, 80
    mov ax, 0x7020       
    rep stosw

    mov di, 2
    mov ah, 0x70
    mov si, str_title1
    call .pt
    mov si, filename_buf
    call .pt

    mov di, 160
    mov cx, 1920
    mov ax, 0x1F20
    rep stosw

    mov di, 3840
    mov cx, 80
    mov ax, 0x7020
    rep stosw

    mov di, 3842
    mov ah, 0x70
    mov si, str_status
    call .pt

    popa
    ret
.pt:
    lodsb
    or al, al
    jz .pt_done
    stosw
    jmp .pt
.pt_done:
    ret

write_char:
    pusha
    mov ax, 0xB800
    mov es, ax
    mov ax, [cs:cursor_y]
    mov di, 80
    mul di
    add ax, [cs:cursor_x]
    shl ax, 1
    mov di, ax
    mov al, [esp + 16]   
    popa
    push es
    push di
    mov di, 0xB800
    mov es, di
    mov di, [cs:cursor_y]
    imul di, 80
    add di, [cs:cursor_x]
    shl di, 1
    mov [es:di], al
    pop di
    pop es
    ret

update_cursor:
    pusha
    mov ax, [cs:cursor_y]
    mov bx, 80
    mul bx
    add ax, [cs:cursor_x]
    mov bx, ax
    mov dx, 0x03D4
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    dec dx
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    popa
    ret

str_title1   db " PASIC IDE | File: ", 0
str_status   db " [F2] Save  [F5] Compile & Run  [ESC] Exit ", 0
str_default  db "UNTITLED.BAS", 0
str_prompt   db " Save as: ", 0
str_saved    db " [SAVED] ", 0
str_pasic    db "PASIC", 0
msg_run_done db 13, 10, 13, 10, "--- Program Finished. Press any key to return to IDE ---", 0

cursor_x     dw 0
cursor_y     dw 1
load_status  db 0
arg_buffer   times 11 db ' '
filename_buf times 16 db 0
custom_filename times 16 db 0

text_buffer  times 2000 db ' '