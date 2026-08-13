[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov si, msg_banner
    call print_str
main_menu:
    mov si, msg_menu
    call print_str
    mov ah, 0x01
    int 0x80
    cmp al, '1'
    je run_cpu_mem
    cmp al, '2'
    je run_fpu
    cmp al, 27
    je exit_app
    jmp main_menu
run_cpu_mem:
    mov si, msg_running_cpu
    call print_str
    call get_ticks
    mov [cs:start_tick], ax
    mov dx, 5000
.cpu_outer:
    push dx
    mov cx, 0xFFFF
    mov ax, 1
    mov bx, 0x55AA
.alu_inner:
    add ax, bx
    xor ax, 0xAAAA
    rol ax, 1
    inc bx
    loop .alu_inner
    mov cx, 8
.mem_loop:
    push cx
    push ds
    push es
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov si, tmp_buffer
    mov di, tmp_buffer + 2048
    mov cx, 1024
    cld
    rep movsw
    pop es
    pop ds
    pop cx
    loop .mem_loop
    pop dx
    dec dx
    jnz .cpu_outer
    call get_ticks
    sub ax, [cs:start_tick]
    jnz .calc_cpu
    mov ax, 1
.calc_cpu:
    mov [cs:elapsed_ticks], ax
    mov cx, 0x0098
    mov ax, 0x9680
    jmp calc_and_print
run_fpu:
    mov si, msg_running_fpu
    call print_str
    fninit
    call get_ticks
    mov [cs:start_tick], ax
    mov dx, 5000
.fpu_outer:
    push dx
    mov cx, 0xFFFF
.fpu_inner:
    fldpi
    fsqrt
    fld st0
    fmul st1
    fstp st0
    fstp st0
    loop .fpu_inner
    pop dx
    dec dx
    jnz .fpu_outer
    call get_ticks
    sub ax, [cs:start_tick]
    jnz .calc_fpu
    mov ax, 1
.calc_fpu:
    mov [cs:elapsed_ticks], ax
    mov cx, 0x00E4
    mov ax, 0xE1C0
    jmp calc_and_print
calc_and_print:
    mov bx, [cs:elapsed_ticks]
    push ax
    mov ax, cx
    xor dx, dx
    div bx
    mov cx, ax
    pop ax
    div bx
    mov bx, 1000
    push ax
    mov ax, cx
    xor dx, dx
    div bx
    mov cx, ax
    pop ax
    div bx
    push dx
    mov si, msg_score
    call print_str
    mov di, num_buf
    call itoa32_16bit
    mov si, num_buf
    call print_str
    mov al, '.'
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    pop ax
    mov di, num_buf
    call itoa_pad3
    mov si, num_buf
    call print_str
    mov si, msg_crlf
    call print_str
    jmp main_menu
get_ticks:
    push ds
    mov ax, 0x0040
    mov ds, ax
    cli
    mov ax, [0x006C]
    sti
    pop ds
    ret
exit_app:
    mov ah, 0x04
    int 0x80
print_str:
    pusha
.p_loop:
    lodsb
    or al, al
    jz .p_done
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    jmp .p_loop
.p_done:
    popa
    ret
itoa32_16bit:
    pusha
    mov bp, 0
    mov bx, 10
.loop1:
    push ax
    mov ax, cx
    xor dx, dx
    div bx
    mov cx, ax
    pop ax
    div bx
    push dx
    inc bp
    mov dx, ax
    or dx, cx
    jnz .loop1
    mov cx, bp
.loop2:
    pop ax
    add al, '0'
    stosb
    loop .loop2
    mov byte [di], 0
    popa
    ret
itoa_pad3:
    pusha
    mov cx, 3
    mov bx, 10
.pad_loop:
    xor dx, dx
    div bx
    push dx
    loop .pad_loop
    mov cx, 3
.pop_loop:
    pop ax
    add al, '0'
    stosb
    loop .pop_loop
    mov byte [di], 0
    popa
    ret
msg_banner      db "=====================================", 13, 10
                db "    PPP-Bench v1.3 Pure 16-bit Edition", 13, 10
                db "    Baseline: Intel 80386 @ 33MHz = 1.000", 13, 10
                db "=====================================", 13, 10, 0
msg_menu        db 13, 10, "Select Benchmark:", 13, 10
                db "[1] CPU Integer & Memory Bandwidth", 13, 10
                db "[2] FPU Math (Requires x87 Co-processor)", 13, 10
                db "[ESC] Exit", 13, 10
                db " > ", 0
msg_running_cpu db 13, 10, "Running ALU & MEM test (10x Load)...", 13, 10, 0
msg_running_fpu db 13, 10, "Running FPU Math test (10x Load)...", 13, 10, 0
msg_score       db "Benchmark Score: ", 0
msg_crlf        db 13, 10, 0
start_tick      dw 0
elapsed_ticks   dw 0
num_buf         times 16 db 0
tmp_buffer      times 4096 db 0
