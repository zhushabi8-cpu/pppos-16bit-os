[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ax, 0x0003
    int 0x10
    mov ax, 0x1003
    mov bl, 0
    int 0x10
    mov ah, 0x01
    mov cx, 0x2000
    int 0x10
    mov ah, 0x33
    int 0x80
    mov [gfx_seg], ax
.welcome_screen:
    call clear_blue
    mov di, 0
    mov cx, 80
    mov ax, 0x7020
    rep stosw
    mov di, 2
    mov si, msg_title
    mov ah, 0x70
    call print_vram
    mov di, 160 * 5 + 10 * 2
    mov si, msg_welcome1
    mov ah, 0x1F
    call print_vram
    mov di, 160 * 7 + 10 * 2
    mov si, msg_welcome2
    mov ah, 0x1F
    call print_vram
    mov di, 160 * 24
    mov cx, 80
    mov ax, 0x7020
    rep stosw
    mov di, 160 * 24 + 2
    mov si, msg_footer1
    mov ah, 0x70
    call print_vram
.wait_enter:
    mov ah, 0x01
    int 0x80
    cmp al, 13
    je .install_progress
    cmp al, 27
    je .abort
    jmp .wait_enter
.install_progress:
    call clear_blue
    mov di, 0
    mov cx, 80
    mov ax, 0x7020
    rep stosw
    mov di, 2
    mov si, msg_title
    mov ah, 0x70
    call print_vram
    mov di, 160 * 10 + 20 * 2
    mov si, msg_installing
    mov ah, 0x1F
    call print_vram
    mov byte [ppc_filename + 3], '1'
.extract_ppc_loop:
    mov ah, 0x02
    mov si, ppc_filename
    mov es, [gfx_seg]
    xor di, di
    int 0x80
    cmp al, 1
    jne .config_screen
    mov ax, [gfx_seg]
    mov ds, ax
    xor si, si
.parse_entry:
    mov al, [ds:si]
    or al, al
    jz .ppc_done
    push cs
    pop es
    mov di, ext_filename
    mov cx, 11
    rep movsb
    lodsw
    mov [cs:ext_filesize], ax
    mov bp, si
    push ds
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov si, ext_filename
    mov di, c_filename
    mov cx, 8
.cpy_name:
    lodsb
    cmp al, ' '
    je .skip_name
    stosb
    loop .cpy_name
.skip_name:
    mov si, ext_filename + 8
    cmp byte [si], ' '
    je .done_name
    mov al, '.'
    stosb
    mov cx, 3
.cpy_ext:
    lodsb
    cmp al, ' '
    je .done_name
    stosb
    loop .cpy_ext
.done_name:
    xor al, al
    stosb
    pop ds
    pusha
    push ds
    push cs
    pop ds
    mov ax, 0xB800
    mov es, ax
    mov di, 160 * 12 + 20 * 2
    mov cx, 40
    mov ax, 0x1F20
    rep stosw
    mov di, 160 * 12 + 20 * 2
    mov si, msg_ext_file
    mov ah, 0x1F
    call print_vram
    mov si, c_filename
.pr_c_name:
    lodsb
    or al, al
    jz .pr_c_done
    stosw
    jmp .pr_c_name
.pr_c_done:
    mov ah, 0x21
    mov bx, 5
    int 0x80
    pop ds
    popa
    push ds
    mov ax, cs
    mov ds, ax
    mov si, c_filename
    mov ax, [cs:gfx_seg]
    mov es, ax
    mov di, bp
    mov cx, [cs:ext_filesize]
    mov ah, 0x03
    int 0x80
    pop ds
    mov si, bp
    add si, [cs:ext_filesize]
    jmp .parse_entry
.ppc_done:
    push cs
    pop ds
    mov ah, 0x0C
    mov si, ppc_filename
    int 0x80
    inc byte [ppc_filename + 3]
    jmp .extract_ppc_loop
.config_screen:
    push cs
    pop ds
    push cs
    pop es
    call clear_blue
    mov di, 0
    mov cx, 80
    mov ax, 0x7020
    rep stosw
    mov di, 2
    mov si, msg_title
    mov ah, 0x70
    call print_vram
    mov di, 160 * 5 + 10 * 2
    mov si, msg_config1
    mov ah, 0x1F
    call print_vram
    mov di, 160 * 8 + 15 * 2
    mov si, msg_opt1
    mov ah, 0x1F
    call print_vram
    mov di, 160 * 10 + 15 * 2
    mov si, msg_opt2
    mov ah, 0x1F
    call print_vram
    mov di, 160 * 24
    mov cx, 80
    mov ax, 0x7020
    rep stosw
    mov di, 160 * 24 + 2
    mov si, msg_footer2
    mov ah, 0x70
    call print_vram
.wait_opt:
    mov ah, 0x01
    int 0x80
    cmp al, '1'
    je .set_gui
    cmp al, '2'
    je .set_cli
    jmp .wait_opt
.set_gui:
    mov si, key_sys
    mov dx, val_gui
    mov ah, 0x43
    int 0x80
    jmp .done
.set_cli:
    mov si, key_sys
    mov dx, val_cli
    mov ah, 0x43
    int 0x80
    jmp .done
.done:
    call clear_blue
    mov di, 160 * 10 + 20 * 2
    mov si, msg_done
    mov ah, 0x1F
    call print_vram
    mov di, 160 * 12 + 20 * 2
    mov si, msg_reboot
    mov ah, 0x1F
    call print_vram
.wait_reboot:
    mov ah, 0x01
    int 0x80
    mov ax, 0x0040
    mov ds, ax
    mov word [0x0072], 0x1234
    jmp 0xFFFF:0000
.abort:
    mov ah, 0x04
    int 0x80
clear_blue:
    pusha
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000
    mov ax, 0x1F20
    rep stosw
    popa
    ret
print_vram:
.loop:
    lodsb
    or al, al
    jz .done_print
    stosw
    jmp .loop
.done_print:
    ret
gfx_seg        dw 0
ext_filesize   dw 0
ppc_filename   db "PPC1    PPC", 0
ext_filename   times 11 db ' '
c_filename     times 16 db 0
msg_title      db " PPP OS Setup ", 0
msg_welcome1   db "Welcome to PPP OS Setup.", 0
msg_welcome2   db "Press ENTER to install the OS components.", 0
msg_footer1    db " ENTER=Install  ESC=Cancel ", 0
msg_footer2    db " 1=GUI Desktop  2=Command Line ", 0
msg_installing db "Please wait... Extracting archives:", 0
msg_ext_file   db " -> ", 0
msg_config1    db "Installation Complete! Select default mode:", 0
msg_opt1       db "[1] Boot directly to GUI Desktop (Recommended)", 0
msg_opt2       db "[2] Boot to Command Line Interface", 0
msg_done       db "PPP OS has been successfully configured!", 0
msg_reboot     db "Press any key to restart your computer.", 0
key_sys        db "SYS             "
val_gui        db "GUI     "
val_cli        db "        "
