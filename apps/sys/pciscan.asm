[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ah, 0x00
    mov si, msg_title
    int 0x80
    mov byte [bus], 0
    mov byte [dev], 0
.scan_loop:
    mov eax, 0x80000000
    xor ebx, ebx
    mov bl, [bus]
    shl ebx, 16
    or eax, ebx
    xor ebx, ebx
    mov bl, [dev]
    shl ebx, 11
    or eax, ebx
    mov dx, 0x0CF8
    out dx, eax
    mov dx, 0x0CFC
    in eax, dx
    cmp ax, 0xFFFF
    je .next_dev
    push eax
    mov ah, 0x00
    mov si, msg_found
    int 0x80
    xor ah, ah
    mov al, [bus]
    call print_hex_byte
    mov ah, 0x00
    mov si, msg_colon
    int 0x80
    xor ah, ah
    mov al, [dev]
    call print_hex_byte
    mov ah, 0x00
    mov si, msg_vid
    int 0x80
    pop eax
    push eax
    call print_hex_word
    mov ah, 0x00
    mov si, msg_did
    int 0x80
    pop eax
    shr eax, 16
    call print_hex_word
    mov ah, 0x00
    mov si, msg_newline
    int 0x80
.next_dev:
    inc byte [dev]
    cmp byte [dev], 32
    jb .scan_loop
    mov ah, 0x00
    mov si, msg_done
    int 0x80
    mov ah, 0x01
    int 0x80
    mov ah, 0x04
    int 0x80
print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
    ret
print_hex_byte:
    pusha
    mov bl, al
    shr al, 4
    call .nibble
    mov al, bl
    and al, 0x0F
    call .nibble
    popa
    ret
.nibble:
    cmp al, 9
    ja .alpha
    add al, '0'
    jmp .print
.alpha:
    add al, 'A' - 10
.print:
    push ax
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    pop ax
    ret
bus db 0
dev db 0
msg_title   db "PPP OS PCI Bus Scanner v1.0", 13, 10
            db "Scanning Bus 0...", 13, 10
            db "--------------------------------", 13, 10, 0
msg_found   db "PCI Device at ", 0
msg_colon   db ":", 0
msg_vid     db "  Vendor: 0x", 0
msg_did     db "  Device: 0x", 0
msg_newline db 13, 10, 0
msg_done    db "--------------------------------", 13, 10
            db "Scan Complete. Press any key...", 0
