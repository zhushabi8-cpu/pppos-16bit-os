[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov di, text_buffer
    mov cx, 2000
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
.copy_name:
    lodsb
    cmp al, ' '
    je .skip_name_spaces
    stosb
    loop .copy_name
    jmp .check_ext
.skip_name_spaces:
    inc si
    loop .skip_name_spaces
.check_ext:
    mov al, '.'
    stosb
    mov cx, 3
.copy_ext:
    lodsb
    cmp al, ' '
    je .skip_ext_spaces
    stosb
    loop .copy_ext
    jmp .done_c_str
.skip_ext_spaces:
    inc si
    loop .skip_ext_spaces
.done_c_str:
    cmp byte [di-1], '.'
    jne .add_zero
    dec di
.add_zero:
    xor al, al
    stosb

    mov di, file_buffer
    mov cx, 8192
    xor al, al
    rep stosb

    mov ah, 0x02
    mov si, arg_buffer
    mov di, file_buffer
    int 0x80
    mov [cs:load_status], al    
    
    or al, al
    jz .init_ui

    mov si, file_buffer
    mov di, text_buffer
    mov cx, 0
    mov dx, 8192
.fmt_loop:
    lodsb
    or al, al
    jz .init_ui
    cmp al, 13
    je .fmt_next
    cmp al, 10
    je .fmt_newline
    
    stosb
    inc cx
    cmp cx, 80
    jae .fmt_newline
    jmp .fmt_next

.fmt_newline:
    mov ax, 80
    sub ax, cx
    add di, ax
    xor cx, cx
    
    mov ax, di
    sub ax, text_buffer
    cmp ax, 1920
    jae .init_ui

.fmt_next:
    dec dx
    jz .init_ui
    jmp .fmt_loop

.load_default:
    mov si, str_default
    mov di, filename_buf
    mov cx, 13
    rep movsb
    mov byte [cs:load_status], 0

.init_ui:
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    mov ah, 0x01
    mov cx, 0x0607
    int 0x10

    call draw_title

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
    mov ah, 0x07         
    stosw
    loop .load_scr

    mov di, 1919
.find_end:
    cmp byte [text_buffer + di], ' '
    jne .found_end
    or di, di
    jz .empty_file
    dec di
    jmp .find_end

.empty_file:
    jmp .new_file

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
    call update_cursor
    jmp .edit_loop

.handle_save:
    mov ax, 0xB800
    mov es, ax
    mov di, 0
    mov cx, 80
    mov ax, 0x7020
    rep stosw

    mov di, 2
    mov ah, 0x70
    mov si, str_choice
.c_loop:
    lodsb
    or al, al
    jz .wait_choice
    stosw
    jmp .c_loop

.wait_choice:
    mov ah, 0x01
    int 0x80            
    cmp al, 27          
    je .cancel_save
    cmp al, '1'         
    je .choice_save
    cmp al, '2'         
    je .save_prompt
    jmp .wait_choice

.choice_save:
    cmp byte [cs:load_status], 0
    jz .save_prompt      
    jmp .execute_save    

.save_prompt:
    mov ax, 0xB800
    mov es, ax
    mov di, 0
    mov cx, 80
    mov ax, 0x7020
    rep stosw

    mov di, 2
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
    mov bx, 22          

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
    call draw_title
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

.execute_save:           
    mov ax, 0xB800
    mov es, ax
    
    mov di, 160 + 1919 * 2
.trim_save:
    cmp di, 160
    jbe .trim_done
    mov al, [es:di]
    cmp al, ' '
    jne .trim_done
    sub di, 2
    jmp .trim_save
.trim_done:
    sub di, 160
    shr di, 1
    inc di
    mov cx, di
    or cx, cx
    jnz .do_extract_mem
    mov cx, 1
.do_extract_mem:
    push cx

    mov di, 160          
    mov bx, text_buffer
.extract_loop:
    mov al, [es:di]      
    mov [cs:bx], al
    add di, 2
    inc bx
    loop .extract_loop

    pop cx
    push cs
    pop ds
    push cs
    pop es
    mov ah, 0x03
    mov si, filename_buf  
    mov di, text_buffer
    int 0x80
    
    mov byte [cs:load_status], 1   

    call draw_title
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

draw_title:
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
    mov si, str_title2
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

str_title1   db " PPP NOTEPAD | File: ", 0
str_title2   db " | [F2] Save [ESC] Exit ", 0
str_default  db "UNTITLED.TXT", 0
str_choice   db " [1] Save  [2] Save As  [ESC] Cancel", 0 
str_prompt   db " Save as: ", 0
str_saved    db " [SAVED] ", 0

cursor_x     dw 0
cursor_y     dw 1
load_status  db 0
arg_buffer   times 11 db ' '
filename_buf times 16 db 0
custom_filename times 16 db 0

text_buffer  times 2000 db ' '
file_buffer  times 8192 db 0