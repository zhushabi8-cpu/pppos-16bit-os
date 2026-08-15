; PPP OS 内核
[BITS 16]
[ORG 0x0000]

    jmp kernel_start

; 分配系统缓冲区
setup_buffers:
    pusha
    mov cx, 2
    call drv_malloc
    mov [cs:seg_fat_buf], ax

    mov cx, 32
    call drv_malloc
    mov [cs:seg_dir_buf], ax

    mov cx, 2
    call drv_malloc
    mov [cs:seg_clip_buf], ax

    mov cx, 2
    call drv_malloc
    mov [cs:seg_task_stk], ax

    mov cx, 4
    call drv_malloc
    mov [cs:seg_reg_buf], ax

    mov cx, 16
    call kmalloc
    mov [cs:seg_gfx_buf], ax
    popa
    ret

; 内核入口点
kernel_start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    
    ; 确保引导盘号合法
    cmp dl, 0x80
    jae .boot_dl_ok
    mov dl, 0x80
.boot_dl_ok:
    mov [boot_drive], dl          
    mov [current_drive], dl
    mov byte [current_part], 0
    mov byte [active_letter], 'C'

    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x81*4], dummy_iret
    mov word [es:0x81*4+2], cs
    pop es
    sti

    call setup_exceptions          
    call setup_keyboard            
    call setup_mouse               
    call setup_disk                
    call setup_syscalls            
    call setup_dos_compat          
    call setup_task_manager        
    call setup_buffers             
    
    call fat_init_drive            

    call create_daemon_task        
    call run_shell                 
    jmp $                          

; 初始化 ATA 中断机制
setup_disk:
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x76*4], ata_isr       
    mov word [es:0x76*4+2], cs
    pop es
    in al, 0xA1
    and al, 0xBF                        
    out 0xA1, al
    sti
    ret

ata_isr:
    pusha
    mov dx, 0x1F7
    in al, dx                           
    mov byte [cs:disk_irq_fired], 1     
    mov al, 0x20
    out 0xA0, al                        
    out 0x20, al                        
    popa
    iret

dummy_iret:
    iret

print_char:
    push bx
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    pop bx
    ret

print_string:
    pusha
.loop:
    lodsb
    or al, al
    jz .done
    call print_char
    jmp .loop
.done:
    popa
    ret

%include "memory.inc"       ; 1. 内存管理器 (kmalloc / kfree)
%include "task.inc"         ; 2. 任务与 IPC 宏定义 (MAX_TASKS / IPC_*)
%include "keyboard.inc"     ; 3. 键盘驱动
%include "mouse.inc"        ; 4. 鼠标驱动
%include "sound.inc"        ; 5. 声音驱动
%include "panic.inc"        ; 6. 异常拦截与蓝屏
%include "fat.inc"          ; 7. FAT 文件系统引擎
%include "vfs.inc"          ; 8. VFS 虚拟文件系统
%include "syscall.inc"      ; 9. 系统调用 (依赖 task/memory/vfs)
%include "comcall.inc"      ; 10. DOS 兼容层 (依赖 syscall/vfs)
%include "shell.inc"        ; 11. 外壳交互

; 磁盘 LBA 读写分发接口
disk_read_lba:
    cmp byte [cs:current_drive], 0x80
    jae ata_read_lba
    jmp floppy_read_lba

disk_write_lba:
    cmp byte [cs:current_drive], 0x80
    jae ata_write_lba
    jmp floppy_write_lba

lba_to_chs:
    push bx
    push ax
    mov bx, 18
    xor dx, dx
    div bx
    inc dx
    mov cl, dl
    xor dx, dx
    mov bx, 2
    div bx
    mov ch, al
    mov dh, dl
    pop ax
    pop bx
    ret

; 软盘驱动 (INT 13h)
floppy_read_lba:
    pusha
.read_loop:
    push cx
    push ax
.retry:
    call lba_to_chs
    mov dl, [cs:current_drive]
    mov ah, 0x02
    mov al, 1
    push bx
    int 0x13
    pop bx
    jnc .read_ok

    push ax
    mov ah, 0x00
    mov dl, [cs:current_drive]
    int 0x13
    pop ax

    call prompt_insert_floppy
    jc .floppy_err              
    jmp .retry                  

.read_ok:
    pop ax
    inc ax
    pop cx
    add bx, 512
    jnc .skip_seg
    mov dx, es
    add dx, 0x1000
    mov es, dx
.skip_seg:
    loop .read_loop
    popa
    clc
    ret
.floppy_err:
    pop ax
    pop cx
    popa
    stc
    ret

floppy_write_lba:
    pusha
.write_loop:
    push cx
    push ax
.retry_w:
    call lba_to_chs
    mov dl, [cs:current_drive]
    mov ah, 0x03
    mov al, 1
    push bx
    int 0x13
    pop bx
    jnc .write_ok

    push ax
    mov ah, 0x00
    mov dl, [cs:current_drive]
    int 0x13
    pop ax

    call prompt_insert_floppy
    jc .floppy_w_err            
    jmp .retry_w                

.write_ok:
    pop ax
    inc ax
    pop cx
    add bx, 512
    jnc .skip_seg_w
    mov dx, es
    add dx, 0x1000
    mov es, dx
.skip_seg_w:
    loop .write_loop
    popa
    clc
    ret
.floppy_w_err:
    pop ax
    pop cx
    popa
    stc
    ret

prompt_insert_floppy:
    pusha
    mov si, msg_insert_disk
    call print_string
.wait_key:
    call kb_get_key             
    cmp al, 27                  
    je .cancel
    cmp al, 13                  
    je .retry_prompt
    jmp .wait_key
.cancel:
    mov si, msg_crlf
    call print_string
    popa
    stc                         
    ret
.retry_prompt:
    mov si, msg_crlf
    call print_string
    popa
    clc                         
    ret

; ATA PIO 硬盘读取
ata_read_lba:
    pusha

    mov dl, [cs:current_drive]
    cmp dl, 0x80
    jb .ata_err_out
    cmp dl, 0x81
    ja .ata_err_out

.read_loop:
    push cx
    push ax

    ; 1. 选中驱动器
    mov al, 0xE0
    cmp byte [cs:current_drive], 0x81
    jne .set_master
    mov al, 0xF0
.set_master:
    mov dx, 0x1F6
    out dx, al

    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    cmp al, 0xFF
    je .ata_err

    mov cx, 0xFFFF
.wait_rdy:
    in al, dx
    test al, 0x80           ; BSY ?
    jnz .rdy_retry
    test al, 0x40           ; RDY ?
    jnz .rdy_ok
.rdy_retry:
    dec cx
    jnz .wait_rdy
    jmp .ata_err            ; 超时退出
.rdy_ok:

    ; 4. 发送参数
    mov dx, 0x1F2
    mov al, 1
    out dx, al

    mov dx, 0x1F3
    pop ax
    push ax
    out dx, al

    mov dx, 0x1F4
    mov al, ah
    out dx, al

    mov dx, 0x1F5
    xor al, al
    out dx, al

    mov dx, 0x1F7
    mov al, 0x20
    out dx, al                      

    mov cx, 0xFFFF
.wait_drq:
    in al, dx
    test al, 0x21           ; 检查 ERR(bit 0) 或 DF(bit 5) 硬件故障
    jnz .ata_err
    test al, 0x80           ; BSY ?
    jnz .drq_retry
    test al, 0x08           ; DRQ ?
    jnz .drq_ok
.drq_retry:
    dec cx
    jnz .wait_drq
    jmp .ata_err            ; 超时退出
.drq_ok:
    mov dx, 0x1F0
    mov cx, 256
    mov di, bx
    cld
    rep insw

    pop ax
    inc ax
    pop cx
    add bx, 512
    jnc .skip_seg                   
    mov dx, es
    add dx, 0x1000                  
    mov es, dx
.skip_seg:
    dec cx
    jz .read_done
    jmp .read_loop

.read_done:
    popa
    clc
    ret

.ata_err:
    pop ax
    pop cx
.ata_err_out:
    popa
    stc
    ret

; ATA PIO 硬盘写入
ata_write_lba:
    pusha

    mov dl, [cs:current_drive]
    cmp dl, 0x80
    jb .ata_w_err_out
    cmp dl, 0x81
    ja .ata_w_err_out

.write_loop:
    push cx
    push ax

    mov al, 0xE0
    cmp byte [cs:current_drive], 0x81
    jne .set_master_w
    mov al, 0xF0
.set_master_w:
    mov dx, 0x1F6
    out dx, al

    mov dx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    cmp al, 0xFF
    je .ata_w_err

    mov cx, 0xFFFF
.wait_rdy_w:
    in al, dx
    test al, 0x80
    jnz .rdy_w_retry
    test al, 0x40
    jnz .rdy_w_ok
.rdy_w_retry:
    dec cx
    jnz .wait_rdy_w
    jmp .ata_w_err
.rdy_w_ok:

    mov dx, 0x1F2
    mov al, 1
    out dx, al

    mov dx, 0x1F3
    pop ax
    push ax
    out dx, al

    mov dx, 0x1F4
    mov al, ah
    out dx, al

    mov dx, 0x1F5
    xor al, al
    out dx, al

    mov dx, 0x1F7
    mov al, 0x30
    out dx, al                      

    mov cx, 0xFFFF
.wait_drq_w:
    in al, dx
    test al, 0x21           ; 检查 ERR 或 DF
    jnz .ata_w_err
    test al, 0x80
    jnz .drq_w_retry
    test al, 0x08
    jnz .drq_w_ok
.drq_w_retry:
    dec cx
    jnz .wait_drq_w
    jmp .ata_w_err
.drq_w_ok:

    mov dx, 0x1F0
    mov cx, 256
    mov si, bx
    push ds
    push es
    pop ds
    cld
    rep outsw                       
    pop ds

    mov dx, 0x1F7
    mov al, 0xE7
    out dx, al
    mov cx, 0xFFFF
.wait_flush:
    in al, dx
    test al, 0x80
    jz .flush_ok
    dec cx
    jnz .wait_flush
    jmp .ata_w_err
.flush_ok:
    pop ax
    inc ax
    pop cx
    add bx, 512
    jnc .skip_seg_w             
    mov dx, es
    add dx, 0x1000
    mov es, dx
.skip_seg_w:
    dec cx
    jz .write_done
    jmp .write_loop

.write_done:
    popa
    clc
    ret

.ata_w_err:
    pop ax
    pop cx
.ata_w_err_out:
    popa
    stc
    ret

; ================================================================
boot_drive     db 0                     
current_drive  db 0x80
current_part   db 0     
active_letter  db 'C'   

msg_disk_r_err db "*** STOP: 0x00000013 (HDD_PIO_READ_FAULT)", 0
msg_disk_w_err db "*** STOP: 0x00000014 (HDD_PIO_WRITE_FAULT)", 0
disk_irq_fired db 0                     

msg_insert_disk db 13, 10, "Drive A: is not ready. Insert a disk and press ENTER to retry, or ESC to cancel.", 0
msg_crlf        db 13, 10, 0

seg_fat_buf   dw 0      
seg_dir_buf   dw 0      
seg_clip_buf  dw 0      
seg_task_stk  dw 0      
seg_reg_buf   dw 0      
seg_gfx_buf   dw 0