[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
.main_menu:
    mov ah, 0x00
    mov si, msg_menu
    int 0x80
.wait_cmd:
    mov ah, 0x00
    mov si, msg_prompt
    int 0x80
    mov di, input_buf
    call read_string
    mov al, [input_buf]
    cmp al, 0
    je .wait_cmd
    cmp al, '1'
    je .do_read
    cmp al, '2'
    je .do_write
    cmp al, '3'
    je .exit
    jmp .wait_cmd
.do_read:
    mov ah, 0x00
    mov si, msg_enter_key
    int 0x80
    mov di, input_buf
    call read_string
    cmp byte [input_buf], 0
    je .main_menu
    mov si, input_buf
    call uppercase_str
    mov si, input_buf
    mov di, key_buf
    mov cx, 16
    call format_str
    mov si, key_buf
    mov di, val_buf
    mov ah, 0x42
    int 0x80
    cmp al, 1
    je .read_found
    mov ah, 0x00
    mov si, msg_not_found
    int 0x80
    jmp .main_menu
.read_found:
    mov byte [val_buf + 8], 0
    mov ah, 0x00
    mov si, msg_val_is
    int 0x80
    mov ah, 0x00
    mov si, val_buf
    int 0x80
    mov ah, 0x00
    mov si, msg_crlf
    int 0x80
    jmp .main_menu
.do_write:
    mov ah, 0x00
    mov si, msg_enter_key
    int 0x80
    mov di, input_buf
    call read_string
    cmp byte [input_buf], 0
    je .main_menu
    mov si, input_buf
    call uppercase_str
    mov si, input_buf
    mov di, key_buf
    mov cx, 16
    call format_str
    mov ah, 0x00
    mov si, msg_enter_val
    int 0x80
    mov di, input_buf
    call read_string
    mov si, input_buf
    call uppercase_str
    mov si, input_buf
    mov di, val_buf
    mov cx, 8
    call format_str
    mov si, key_buf
    mov dx, val_buf
    mov ah, 0x43
    int 0x80
    mov ah, 0x00
    mov si, msg_saved
    int 0x80
    jmp .main_menu
.exit:
    mov ah, 0x04
    int 0x80
uppercase_str:
    pusha
    mov di, si
.up_loop:
    mov al, [di]
    or al, al
    jz .up_done
    cmp al, 'a'
    jb .up_next
    cmp al, 'z'
    ja .up_next
    sub al, 32
    mov [di], al
.up_next:
    inc di
    jmp .up_loop
.up_done:
    popa
    ret
read_string:
    pusha
    mov bx, di
.rl_loop:
    mov ah, 0x01
    int 0x80
    cmp al, 13
    je .rl_done
    cmp al, 8
    je .rl_bs
    cmp al, 32
    jb .rl_loop
    cmp al, 126
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
    mov al, 32
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
format_str:
    pusha
    push di
    push cx
    mov al, ' '
    rep stosb
    pop cx
    pop di
.fmt_loop:
    lodsb
    or al, al
    jz .fmt_done
    stosb
    loop .fmt_loop
.fmt_done:
    popa
    ret
msg_menu      db 13, 10, "=== PPP OS Registry Tester ===", 13, 10
              db "1. Read Key (GET)", 13, 10
              db "2. Write Key (SET)", 13, 10
              db "3. Exit", 13, 10, 0
msg_prompt    db "> ", 0
msg_enter_key db "Enter Key Name (Max 16 chars): ", 0
msg_enter_val db "Enter Value (Max 8 chars): ", 0
msg_not_found db "[-] Key not found in Registry.", 13, 10, 0
msg_val_is    db "[+] Value is: [", 0
msg_crlf      db "]", 13, 10, 0
msg_saved     db "[+] Successfully saved to SYSTEM.REG!", 13, 10, 0
input_buf     times 32 db 0
key_buf       times 16 db ' '
val_buf       times 9  db ' '
