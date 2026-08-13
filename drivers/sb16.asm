; =================================================================
; drivers/sb16.asm - PPP OS Sound Blaster 16 内核驱动 (止血版)
; =================================================================
[BITS 16]
[ORG 0x0000]

driver_init:
    pusha
    push ds
    push es
    mov ax, cs
    mov ds, ax

    call reset_dsp
    jc .fail

    mov dx, 0x224
    mov al, 0x22
    out dx, al
    mov dx, 0x225
    mov al, 0xFF
    out dx, al

    mov dx, 0x224
    mov al, 0x04
    out dx, al
    mov dx, 0x225
    mov al, 0xFF
    out dx, al

    cli
    xor ax, ax
    mov es, ax
    
    mov word [es:0x81*4], sb16_api_handler
    mov word [es:0x81*4+2], cs

    mov ax, [es:0x0D*4]
    mov [old_irq5], ax
    mov ax, [es:0x0D*4+2]
    mov [old_irq5+2], ax
    mov word [es:0x0D*4], irq5_handler
    mov word [es:0x0D*4+2], cs

    in al, 0x21
    and al, ~0x20
    out 0x21, al
    sti

    pop es
    pop ds
    popa
    mov al, 1           
    retf

.fail:
    pop es
    pop ds
    popa
    xor al, al          
    retf

sb16_api_handler:
    cmp ah, 0x05
    je .api_stream_start
    cmp ah, 0x06
    je .api_stream_status
    cmp ah, 0x07
    je .api_stream_stop
    iret

.api_stream_start:
    pusha
    cli
    mov byte [cs:play_state], 0
    mov byte [cs:needs_refill], 0
    mov [cs:tmp_sample_rate], dx

    mov ax, es
    mov dx, ax
    shr dx, 12              
    shl ax, 4               
    add ax, bx              
    adc dx, 0               
    
    push dx
    push ax
    mov al, 0x05            
    out 0x0A, al            
    out 0x0C, al            
    
    mov al, 0x59            
    out 0x0B, al
    
    pop ax
    out 0x02, al            
    mov al, ah
    out 0x02, al            
    pop dx
    mov al, dl
    out 0x83, al            
    mov ax, 32767           
    out 0x03, al            
    mov al, ah
    out 0x03, al            
    mov al, 0x01            
    out 0x0A, al            

    mov al, 0xD1
    call write_dsp

    mov al, 0x41            
    call write_dsp
    mov ax, [cs:tmp_sample_rate]
    push ax
    mov al, ah              
    call write_dsp
    pop ax
    call write_dsp          

    mov al, 0x48
    call write_dsp
    mov ax, 16383           
    push ax
    call write_dsp          
    pop ax
    mov al, ah
    call write_dsp          

    mov al, 0x1C            
    call write_dsp

    sti
    popa
    iret

.api_stream_status:
    cli
    mov al, [cs:needs_refill]
    mov byte [cs:needs_refill], 0
    sti
    iret                    

.api_stream_stop:
    pusha
    cli

    mov al, 0xDA            
    call write_dsp

    mov al, 0xD3            
    call write_dsp

    mov al, 0x05            
    out 0x0A, al

    mov byte [cs:needs_refill], 0
    mov byte [cs:play_state], 0
    sti
    popa
    iret

irq5_handler:
    pusha
    push ds
    mov ax, cs
    mov ds, ax
    mov dx, 0x22E
    in al, dx
    mov al, 0x20
    out 0x20, al
    xor byte [play_state], 1
    jz .was_A
    mov byte [needs_refill], 2
    jmp .irq_done
.was_A:
    mov byte [needs_refill], 1
.irq_done:
    pop ds
    popa
    iret

reset_dsp:
    mov dx, 0x226
    mov al, 1
    out dx, al
    mov cx, 0xFFFF
.d1: loop .d1
    mov al, 0
    out dx, al
    mov cx, 0xFFFF
.w1:
    mov dx, 0x22E
    in al, dx
    test al, 0x80
    jnz .r1
    loop .w1
    stc
    ret
.r1:
    mov dx, 0x22A
    in al, dx
    cmp al, 0xAA
    jne reset_dsp
    clc
    ret

write_dsp:
    push dx
    push ax
    push cx
    mov dx, 0x22C
    mov cx, 0xFFFF
.w2:
    in al, dx
    test al, 0x80
    jz .do_w
    loop .w2
    pop cx
    pop ax
    pop dx
    ret
.do_w:
    pop cx
    pop ax
    out dx, al
    pop dx
    ret

old_irq5        dw 0, 0
tmp_sample_rate dw 0
play_state      db 0       
needs_refill    db 0