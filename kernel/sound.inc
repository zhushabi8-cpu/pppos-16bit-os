pc_beep_on:
    pusha
    
    or bx, bx           
    jz .done

    mov ax, 0x34DC
    mov dx, 0x0012
    div bx              
    mov bx, ax          

    mov al, 0xB6        
    out 0x43, al        

    mov al, bl          
    out 0x42, al
    mov al, bh          
    out 0x42, al

    in al, 0x61         
    or al, 0x03         
    out 0x61, al        

.done:
    popa
    ret

pc_beep_off:
    push ax
    in al, 0x61
    and al, 0xFC        
    out 0x61, al
    pop ax
    ret