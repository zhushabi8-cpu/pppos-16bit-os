[BITS 16]
[ORG 0x0000]
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ah, 0x16
    mov di, arg_buf
    int 0x80
    cmp byte [arg_buf], ' '
    je err_usage
    mov si, arg_buf
    mov di, filename
    call fat_to_str
    mov cx, 1
    mov ah, 0x40
    int 0x80
    or ax, ax
    jz err_mem
    mov [file_seg], ax
    mov cx, 1
    mov ah, 0x40
    int 0x80
    or ax, ax
    jz err_mem
    mov [audio_seg], ax
    mov si, arg_buf
    mov es, [file_seg]
    mov ah, 0x02
    int 0x80
    or al, al
    jz err_file
    mov word [sample_rate], 22050
    mov word [data_offset], 44
    mov word [data_len], 60000
    push ds
    mov ds, [file_seg]
    mov si, 12
    mov cx, 512
.find_fmt:
    cmp word [si], 0x6D66
    jne .next_fmt
    cmp word [si+2], 0x2074
    je .found_fmt
.next_fmt:
    inc si
    loop .find_fmt
    jmp .scan_data
.found_fmt:
    mov ax, [si+12]
    or ax, ax
    jz .scan_data
    mov [cs:sample_rate], ax
.scan_data:
    mov si, 12
    mov cx, 1024
.find_data:
    cmp word [si], 0x6164
    jne .next_data
    cmp word [si+2], 0x6174
    je .found_data
.next_data:
    inc si
    loop .find_data
    jmp .parse_done
.found_data:
    mov ax, [si+4]
    or ax, ax
    jz .set_offset
    mov [cs:data_len], ax
.set_offset:
    add si, 8
    mov [cs:data_offset], si
.parse_done:
    pop ds
    mov ax, [data_offset]
    mov [cur_file_pos], ax
    call fill_16k_A
    call fill_16k_B
    mov si, msg_playing
    call print_str
    mov si, filename
    call print_str
    mov si, msg_crlf
    call print_str
    mov ah, 0x05
    mov es, [audio_seg]
    xor bx, bx
    mov dx, [sample_rate]
    int 0x81
.stream_loop:
    mov ah, 0x15
    int 0x80
    cmp al, 27
    je .stop_stream
    cmp byte [cs:is_eof], 1
    je .wait_finish
    mov ah, 0x06
    int 0x81
    cmp al, 1
    je .do_refill_A
    cmp al, 2
    je .do_refill_B
    mov ah, 0x22
    int 0x80
    jmp .stream_loop
.do_refill_A:
    call fill_16k_A
    jmp .stream_loop
.do_refill_B:
    call fill_16k_B
    jmp .stream_loop
.wait_finish:
    mov ax, 16384
    mov bx, 1000
    mul bx
    mov bx, [sample_rate]
    div bx
    mov bx, ax
    mov ah, 0x21
    int 0x80
.stop_stream:
    mov ah, 0x07
    int 0x81
    mov ah, 0x41
    mov bx, [file_seg]
    int 0x80
    mov ah, 0x41
    mov bx, [audio_seg]
    int 0x80
    mov si, msg_done
    call print_str
exit:
    mov ah, 0x04
    int 0x80
fill_16k_A:
    pusha
    mov es, [cs:audio_seg]
    mov di, 0x0000
    call copy_ram_bytes
    popa
    ret
fill_16k_B:
    pusha
    mov es, [cs:audio_seg]
    mov di, 0x4000
    call copy_ram_bytes
    popa
    ret
copy_ram_bytes:
    mov si, [cs:cur_file_pos]
    mov ax, [cs:data_offset]
    add ax, [cs:data_len]
    mov cx, 16384
.c_loop:
    cmp si, ax
    jae .eof_pad
    push ds
    mov dx, [cs:file_seg]
    mov ds, dx
    mov dl, [si]
    pop ds
    mov [es:di], dl
    inc si
    inc di
    loop .c_loop
    mov [cs:cur_file_pos], si
    ret
.eof_pad:
    mov byte [cs:is_eof], 1
    mov al, 0x80
    rep stosb
    mov [cs:cur_file_pos], si
    ret
err_usage:
    mov si, msg_usage
    jmp exit_err
err_file:
    mov si, msg_err_file
    jmp exit_err
err_mem:
    mov si, msg_err_mem
exit_err:
    call print_str
    jmp exit
fat_to_str:
    mov cx, 8
.loop1:
    lodsb
    cmp al, ' '
    je .skip1
    stosb
    loop .loop1
    jmp .do_ext
.skip1:
    add si, cx
    dec si
.do_ext:
    mov al, [si]
    cmp al, ' '
    je .done
    mov al, '.'
    stosb
    mov cx, 3
.loop2:
    lodsb
    cmp al, ' '
    je .done
    stosb
    loop .loop2
.done:
    xor al, al
    stosb
    ret
print_str:
    mov ah, 0x0E
    mov bx, 0x000F
.p: lodsb
    or al, al
    jz .pd
    int 0x10
    jmp .p
.pd: ret
arg_buf      times 12 db 0
filename     times 16 db 0
file_seg     dw 0
audio_seg    dw 0
sample_rate  dw 22050
data_offset  dw 44
data_len     dw 60000
cur_file_pos dw 0
is_eof       db 0
msg_usage    db "Usage: PLAYWAV <FILE.WAV>", 13, 10, 0
msg_playing  db "Streaming WAV via SB16 DMA... Press ESC to Stop.", 13, 10, "File: ", 0
msg_crlf     db 13, 10, 0
msg_done     db "Playback finished successfully.", 13, 10, 0
msg_err_file db "Error: File not found!", 13, 10, 0
msg_err_mem  db "Error: Out of memory!", 13, 10, 0
