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
.choose_algo:
    mov ah, 0x01
    int 0x80
    cmp al, '1'
    je .algo_rle
    cmp al, '2'
    je .algo_lz77
    jmp .choose_algo
.algo_rle:
    mov byte [algo_id], 1
    mov si, msg_rle
    call print_str
    jmp .get_files
.algo_lz77:
    mov byte [algo_id], 2
    mov si, msg_lz77
    call print_str
.get_files:
    mov si, msg_in_file
    call print_str
    mov di, input_buf
    call read_line
    mov si, input_buf
    mov di, file_in
    call copy_str
    mov si, msg_out_file
    call print_str
    mov di, input_buf
    call read_line
    mov si, input_buf
    mov di, file_out
    call copy_str
    mov si, msg_working
    call print_str
    mov ah, 0x05
    mov si, file_in
    int 0x80
    cmp ax, 0xFFFF
    je .err_file
    mov [fd], ax
    mov bx, ax
    mov ah, 0x09
    int 0x80
    mov [file_size], ax
    mov cx, 1
    mov ah, 0x40
    int 0x80
    or ax, ax
    jz .err_mem
    mov [seg_in], ax
    call clear_mem
    mov cx, 1
    mov ah, 0x40
    int 0x80
    or ax, ax
    jz .err_mem
    mov [seg_out], ax
    call clear_mem
    mov ah, 0x07
    mov bx, [fd]
    mov cx, [file_size]
    mov es, [seg_in]
    xor di, di
    int 0x80
    mov ah, 0x06
    mov bx, [fd]
    int 0x80
    mov es, [seg_out]
    mov byte [es:0], 'P'
    mov byte [es:1], 'P'
    mov byte [es:2], 'C'
    mov al, [algo_id]
    mov [es:3], al
    mov ax, [file_size]
    mov [es:4], ax
    mov word [out_ptr], 6
    cmp byte [algo_id], 1
    je .do_rle
    call comp_lz77
    jmp .write_out
.do_rle:
    call comp_rle
.write_out:
    mov ax, cs
    mov ds, ax
    mov ah, 0x03
    mov si, file_out
    mov es, [seg_out]
    xor di, di
    mov cx, [out_ptr]
    int 0x80
    mov ah, 0x41
    mov bx, [seg_in]
    int 0x80
    mov ah, 0x41
    mov bx, [seg_out]
    int 0x80
    mov si, msg_ok
    call print_str
    mov ah, 0x04
    int 0x80
.err_file:
    mov si, msg_err_file
    call print_str
    mov ah, 0x04
    int 0x80
.err_mem:
    mov si, msg_err_mem
    call print_str
    mov ah, 0x04
    int 0x80
clear_mem:
    pusha
    mov es, ax
    xor di, di
    mov cx, 32768
    xor ax, ax
    rep stosw
    popa
    ret
comp_rle:
    mov ds, [cs:seg_in]
    mov es, [cs:seg_out]
    xor si, si
    mov di, [cs:out_ptr]
    mov dx, [cs:file_size]
.rle_loop:
    cmp si, dx
    jae .rle_done
    mov al, [ds:si]
    mov cx, 1
.rle_cnt:
    mov bx, si
    add bx, cx
    cmp bx, dx
    jae .rle_write
    mov ah, [ds:bx]
    cmp ah, al
    jne .rle_write
    inc cx
    cmp cx, 63
    jb .rle_cnt
.rle_write:
    cmp cx, 1
    ja .rle_run
    cmp al, 0xC0
    jae .rle_run
    mov [es:di], al
    inc di
    inc si
    jmp .rle_loop
.rle_run:
    mov ah, cl
    or ah, 0xC0
    mov [es:di], ah
    mov [es:di+1], al
    add di, 2
    add si, cx
    jmp .rle_loop
.rle_done:
    mov [cs:out_ptr], di
    ret
comp_lz77:
    mov ds, [cs:seg_in]
    mov es, [cs:seg_out]
    xor si, si
    mov bp, si
    xor cx, cx
.lz_loop:
    cmp si, [cs:file_size]
    jae .lz_end
    call search_match
    cmp ax, 3
    jae .lz_match
    inc cx
    inc si
    cmp cx, 127
    je .lz_flush
    jmp .lz_loop
.lz_match:
    or cx, cx
    jz .lz_write_match
.lz_flush:
    call flush_literals
    cmp si, [cs:file_size]
    jae .lz_end
    cmp ax, 3
    jb .lz_loop
.lz_write_match:
    mov di, [cs:out_ptr]
    push ax
    sub al, 3
    or al, 0x80
    mov [es:di], al
    mov [es:di+1], bl
    add di, 2
    mov [cs:out_ptr], di
    pop ax
    add si, ax
    mov bp, si
    jmp .lz_loop
.lz_end:
    or cx, cx
    jz .lz_ret
    call flush_literals
.lz_ret:
    ret
search_match:
    push cx
    push dx
    push si
    push di
    mov word [cs:max_len], 0
    mov word [cs:best_off], 0
    mov ax, si
    dec ax
.s_loop:
    or ax, ax
    jl .s_done
    mov bx, si
    sub bx, ax
    cmp bx, 255
    ja .s_done
    push ax
    push si
    xor cx, cx
.c_loop:
    push bx
    mov bx, ax
    mov dl, [ds:bx]
    mov bx, si
    mov dh, [ds:bx]
    pop bx
    cmp dl, dh
    jne .c_end
    inc cx
    inc ax
    inc si
    cmp cx, 130
    jae .c_end
    cmp si, [cs:file_size]
    jae .c_end
    jmp .c_loop
.c_end:
    pop si
    pop ax
    cmp cx, [cs:max_len]
    jbe .s_next
    mov [cs:max_len], cx
    mov [cs:best_off], bx
.s_next:
    dec ax
    jmp .s_loop
.s_done:
    pop di
    pop si
    pop dx
    pop cx
    mov ax, [cs:max_len]
    mov bx, [cs:best_off]
    ret
flush_literals:
    pusha
    mov di, [cs:out_ptr]
    mov al, cl
    mov [es:di], al
    inc di
    mov si, bp
    rep movsb
    mov [cs:out_ptr], di
    popa
    xor cx, cx
    mov bp, si
    ret
read_line:
    pusha
    mov bx, di
.rl_loop:
    mov ah, 0x01
    int 0x80
    cmp al, 13
    je .rl_done
    cmp al, 8
    je .rl_bs
    cmp al, ' '
    jb .rl_loop
    cmp al, '~'
    ja .rl_loop
    stosb
    mov ah, 0x0E
    int 0x10
    jmp .rl_loop
.rl_bs:
    cmp di, bx
    jbe .rl_loop
    dec di
    mov ah, 0x0E
    mov al, 8
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 8
    int 0x10
    jmp .rl_loop
.rl_done:
    mov byte [di], 0
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    popa
    ret
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
copy_str:
    pusha
.cpy_loop:
    lodsb
    or al, al
    jz .cpy_done
    cmp al, 'a'
    jb .not_lower
    cmp al, 'z'
    ja .not_lower
    sub al, 32
.not_lower:
    stosb
    jmp .cpy_loop
.cpy_done:
    stosb
    popa
    ret
msg_title    db "======================================", 13, 10
             db "   PPP OS Compression Utility v2.0", 13, 10
             db "======================================", 13, 10
             db " Select Algorithm:", 13, 10
             db " [1] PCX-RLE (Fast, Best for Bitmaps)", 13, 10
             db " [2] LZ77    (Strong, Best for Code)", 13, 10
             db " > ", 0
msg_rle      db "RLE Selected.", 13, 10, 0
msg_lz77     db "LZ77 Selected.", 13, 10, 0
msg_in_file  db " Input File: ", 0
msg_out_file db " Output File: ", 0
msg_working  db " Compressing... Please wait.", 13, 10, 0
msg_err_file db " Error: File not found!", 13, 10, 0
msg_err_mem  db " Error: Out of memory!", 13, 10, 0
msg_ok       db " Done! File compressed successfully.", 13, 10, 0
input_buf    times 32 db 0
file_in      times 16 db 0
file_out     times 16 db 0
fd           dw 0
file_size    dw 0
seg_in       dw 0
seg_out      dw 0
out_ptr      dw 0
algo_id      db 0
max_len      dw 0
best_off     dw 0
