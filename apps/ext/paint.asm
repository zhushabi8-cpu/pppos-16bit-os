[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov ah, 0x00
    mov al, 0x13
    int 0x10

    call draw_main_ui

    mov byte [cs:cur_color], 10    
    call update_color_box          

    mov byte [cs:cursor_drawn], 0  
    mov word [cs:cursor_x], 160
    mov word [cs:cursor_y], 100

main_loop:
    mov ah, 0x15
    int 0x80
    or ax, ax
    jz .check_mouse
    
    cmp al, 27          
    je exit_app         
    cmp al, 's'
    je save_bmp         
    cmp al, 'S'
    je save_bmp

.check_mouse:
    mov ah, 0x18        
    int 0x80            
    shr cx, 1           

    cmp byte [cs:cursor_drawn], 1
    jne .skip_erase
    call xor_cursor
    mov byte [cs:cursor_drawn], 0
.skip_erase:

    mov [cs:cursor_x], cx
    mov [cs:cursor_y], dx

    cmp dx, 20
    jge .in_canvas

.in_ui_area:
    test bl, 1
    jz .done_mouse
    cmp dx, 10
    jl .done_mouse
    cmp dx, 17
    jg .done_mouse
    cmp cx, 10
    jl .done_mouse
    cmp cx, 265
    jg .done_mouse
    
    mov ax, cx
    sub ax, 10
    mov [cs:cur_color], al
    call update_color_box
    jmp .done_mouse

.in_canvas:
    test bl, 1          
    jz .check_erase
    mov al, [cs:cur_color]
    mov [cs:brush_color], al
    call draw_brush
    jmp .done_mouse

.check_erase:
    test bl, 2          
    jz .done_mouse
    mov byte [cs:brush_color], 0
    call draw_brush

.done_mouse:
    call xor_cursor
    mov byte [cs:cursor_drawn], 1
    jmp main_loop       

draw_main_ui:
    push es
    mov ah, 0x02
    mov bh, 0
    mov dx, 0x0000
    int 0x10
    mov si, str_toolbar
    call print_ui_str

    mov ax, 0xA000
    mov es, ax
    mov cx, 256
    mov di, 320 * 10 + 10
    xor al, al          
.pal_loop:
    mov bx, 0
.pal_h:
    mov [es:di+bx], al
    add bx, 320
    cmp bx, 320 * 8     
    jl .pal_h
    inc al
    inc di
    loop .pal_loop
    pop es
    ret

draw_brush:
    pusha
    push es
    mov cx, [cs:cursor_x]
    mov dx, [cs:cursor_y]
    mov ax, 0xA000
    mov es, ax

    mov si, -2          
.brush_y:
    mov di, -2          
.brush_x:
    mov ax, cx
    add ax, di
    cmp ax, 0
    jl .skip_px         
    cmp ax, 319
    jg .skip_px         

    mov bx, dx
    add bx, si
    cmp bx, 20
    jl .skip_px         
    cmp bx, 199
    jg .skip_px         

    push dx
    push ax
    mov ax, bx
    mov bx, 320
    mul bx
    pop bx
    add ax, bx
    mov bp, ax
    pop dx

    mov al, [cs:brush_color] 
    mov [es:bp], al     

.skip_px:
    inc di
    cmp di, 3
    jne .brush_x
    inc si
    cmp si, 3
    jne .brush_y

    pop es
    popa
    ret
xor_cursor:
    pusha
    push es
    mov ax, 0xA000
    mov es, ax
    mov cx, [cs:cursor_x]
    mov dx, [cs:cursor_y]

    mov si, -4
.cur_h:
    mov ax, cx
    add ax, si
    cmp ax, 0
    jl .skip_h
    cmp ax, 319
    jg .skip_h
    
    push dx
    mov bx, ax
    mov ax, dx
    mov di, 320
    mul di
    add ax, bx
    mov di, ax
    pop dx
    
    xor byte [es:di], 0x0F    
.skip_h:
    inc si
    cmp si, 5
    jne .cur_h

    mov si, -4
.cur_v:
    or si, si
    jz .skip_v          
    mov ax, dx
    add ax, si
    cmp ax, 20
    jl .skip_v          
    cmp ax, 199
    jg .skip_v
    
    mov bx, cx
    mov di, 320
    mul di
    add ax, bx
    mov di, ax
    
    xor byte [es:di], 0x0F
.skip_v:
    inc si
    cmp si, 5
    jne .cur_v

    pop es
    popa
    ret
update_color_box:
    pusha
    push es
    mov ax, 0xA000
    mov es, ax
    mov al, [cs:cur_color]
    mov di, 320 * 10 + 280    
    mov cx, 8
.box_y:
    push cx
    mov cx, 16               
    rep stosb
    add di, 320 - 16
    pop cx
    loop .box_y
    pop es
    popa
    ret

save_bmp:
    cmp byte [cs:cursor_drawn], 1
    jne .do_prompt
    call xor_cursor
    mov byte [cs:cursor_drawn], 0

.do_prompt:
    mov ah, 0x02
    mov bh, 0
    mov dx, 0x0000
    int 0x10
    mov cx, 40
    mov ah, 0x09
    mov al, ' '
    mov bx, 0x000F
    int 0x10

    mov ah, 0x02
    mov dx, 0x0000
    int 0x10
    mov si, str_prompt
    call print_ui_str

    push cs
    pop es

    mov di, custom_filename
    mov cx, 0

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
    mov ah, 0x0E
    int 0x10
    jmp .input_loop

.bs:
    or cx, cx
    jz .input_loop
    dec cx
    dec di
    mov ah, 0x0E
    mov al, 8
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 8
    int 0x10
    jmp .input_loop

.cancel_save:
    call draw_main_ui
    jmp main_loop

.do_extract:
    mov byte [di], 0    
    mov dx, 0x03C7
    xor al, al
    out dx, al          
    mov dx, 0x03C9
    mov di, palette_buf
    mov cx, 256
.pal_loop:
    in al, dx
    shl al, 2           
    mov ah, al          
    in al, dx
    shl al, 2
    mov bl, al          
    in al, dx
    shl al, 2           
    mov [di+0], al      
    mov [di+1], bl      
    mov [di+2], ah      
    mov byte [di+3], 0
    add di, 4
    loop .pal_loop

    mov ax, 199
    mov di, pixel_buf
.y_loop:
    push ax
    mov bx, 320
    mul bx
    mov si, ax          
    push ds
    mov ax, 0xA000      
    mov ds, ax
    push cs
    pop es
    mov cx, 320
    rep movsb           
    pop ds
    pop ax
    dec ax
    cmp ax, 19          
    jg .y_loop
    push cs
    pop es
    mov ah, 0x03
    mov si, custom_filename
    mov di, bmp_header
    mov cx, 58678
    int 0x80

    call draw_main_ui
    jmp main_loop       

print_ui_str:
.pu_loop:
    lodsb
    or al, al
    jz .pu_done
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    jmp .pu_loop
.pu_done:
    ret

exit_app:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x04
    int 0x80

str_toolbar db " PPP PAINT  [S]ave [ESC]  ", 0
str_prompt  db " Save as: ", 0
custom_filename times 16 db 0

cur_color    db 0
brush_color  db 0
cursor_x     dw 0
cursor_y     dw 0
cursor_drawn db 0

bmp_header:
    db 'B', 'M'
    dw 0xE536, 0x0000   
    dw 0, 0
    dw 1078, 0          
    dw 40, 0            
    dw 320, 0           
    dw 180, 0           
    dw 1                
    dw 8                
    dw 0, 0             
    dw 0xE100, 0x0000   
    dw 0, 0
    dw 0, 0
    dw 256, 0
    dw 256, 0

palette_buf equ $
pixel_buf   equ palette_buf + 1024