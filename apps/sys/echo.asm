[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs      
    mov ds, ax
    mov es, ax

    mov ah, 0x00
    mov si, msg_prompt
    int 0x80

.loop:
    mov ah, 0x01
    int 0x80        

    cmp al, 13      
    je .done

    mov [char_buf], al
    mov ah, 0x00
    mov si, char_buf
    int 0x80
    
    jmp .loop       

.done:
    mov ah, 0x00
    mov si, msg_newline
    int 0x80
    mov ah, 0x04   
    int 0x80

msg_prompt  db "Type anything (Press ENTER to quit): ", 0
msg_newline db 13, 10, 0
char_buf    db 0, 0