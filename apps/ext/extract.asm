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
    mov ds, [seg_in]
    cmp byte [0], 'P'
    jne .err_fmt
    cmp byte [1], 'P'
    jne .err_fmt
    cmp byte [2], 'C'
    jne .err_fmt
    mov al, [3]
    mov [cs:algo_id], al
    mov ax, [4]
    mov [cs:orig_size], ax
    cmp byte [cs:algo_id], 1
    je .do_rle
    cmp byte [cs:algo_id], 2
    je .do_lz77
    jmp .err_fmt
.do_rle:
    call decomp_rle
    jmp .write_out
.do_lz77:
    call decomp_lz77
.write_out:
    mov ax, cs
    mov ds, ax
    mov ah, 0x03
    mov si, file_out
    mov es, [seg_out]
    xor di, di
    mov cx, [orig_size]
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
.err_fmt:
    mov ax, cs
    mov ds, ax
    mov si, msg_err_fmt
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
decomp_rle:
    mov ds, [cs:seg_in]
    mov es, [cs:seg_out]
    mov si, 6
    xor di, di
.d_loop_rle:
    cmp si, [cs:file_size]
    jae .d_end_rle
    mov al, [ds:si]
    inc si
    mov ah, al
    and ah, 0xC0
    cmp ah, 0xC0
    je .d_run_rle
    mov [es:di], al
    inc di
    jmp .d_loop_rle
.d_run_rle:
    xor cx, cx
    mov cl, al
    and cl, 0x3F
    mov al, [ds:si]
    inc si
    rep stosb
    jmp .d_loop_rle
.d_end_rle:
    ret
decomp_lz77:
    mov ds, [cs:seg_in]
    mov es, [cs:seg_out]
    mov si, 6
    xor di, di
.d_loop_lz:
    cmp si, [cs:file_size]
    jae .d_end_lz
    cmp di, [cs:orig_size]
    jae .d_end_lz
    mov al, [ds:si]
    inc si
    test al, 0x80
    jnz .d_match_lz
    xor ah, ah
    mov cx, ax
    rep movsb
    jmp .d_loop_lz
.d_match_lz:
    and al, 0x7F
    xor ah, ah
    mov cx, ax
    add cx, 3
    xor bh, bh
    mov bl, [ds:si]
    inc si
    push si
    mov si, di
    sub si, bx
.d_copy_lz:
    mov al, [es:si]
    mov [es:di], al
    inc si
    inc di
    loop .d_copy_lz
    pop si
    jmp .d_loop_lz
.d_end_lz:
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
             db "   PPP OS Smart Extraction Utility", 13, 10
             db "======================================", 13, 10, 0
msg_in_file  db " Input File (.PPC): ", 0
msg_out_file db " Extract To: ", 0
msg_working  db " Extracting... Please wait.", 13, 10, 0
msg_err_file db " Error: File not found!", 13, 10, 0
msg_err_mem  db " Error: Out of memory!", 13, 10, 0
msg_err_fmt  db " Error: Invalid PPC archive format!", 13, 10, 0
msg_ok       db " Done! File extracted successfully.", 13, 10, 0
input_buf    times 32 db 0
file_in      times 16 db 0
file_out     times 16 db 0
fd           dw 0
file_size    dw 0
orig_size    dw 0
seg_in       dw 0
seg_out      dw 0
algo_id      db 0
