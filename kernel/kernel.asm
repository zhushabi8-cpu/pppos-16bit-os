; PPP OS 内核主程序
; 16位实模式，由引导程序加载至 0x0000:0x0000
[BITS 16]
[ORG 0x0000]

    jmp kernel_start

; ----------------------------------------------------------------
; 动态分配系统核心缓冲区
; ----------------------------------------------------------------
setup_buffers:
    pusha
    ; 1. 分配 FAT 表缓存 (9扇区 = 4.5KB)
    mov cx, 9
    call drv_malloc
    mov [cs:seg_fat_buf], ax

    ; 2. 分配 目录表缓存 (14扇区 = 7KB)
    mov cx, 14
    call drv_malloc
    mov [cs:seg_dir_buf], ax

    ; 3. 分配 剪贴板缓存 (2扇区 = 1KB，足够存64个文件名)
    mov cx, 2
    call drv_malloc
    mov [cs:seg_clip_buf], ax

    ; 4. 分配 守护进程栈 (2扇区 = 1KB)
    mov cx, 2
    call drv_malloc
    mov [cs:seg_task_stk], ax

    ; 5. 分配 注册表缓存 (4扇区 = 2KB，可存64条系统配置)
    mov cx, 4
    call drv_malloc
    mov [cs:seg_reg_buf], ax

    ; 6. 分配 64KB 缓冲 (图形双缓冲/大文件暂存)
    mov cx, 1
    call kmalloc
    mov [cs:seg_gfx_buf], ax
    popa
    ret

; ----------------------------------------------------------------
; 内核入口点
; ----------------------------------------------------------------
kernel_start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    
    ; 保存引导盘号，并将其设置为当前活动盘符
    mov [boot_drive], dl          
    mov [current_drive], dl

    ; 注册驱动通信中断 (INT 0x81)
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x81*4], dummy_iret
    mov word [es:0x81*4+2], cs
    pop es
    sti

    ; 初始化各子系统
    call setup_exceptions          
    call setup_keyboard            
    call setup_mouse               
    call setup_disk                
    call setup_syscalls            
    call setup_dos_compat          
    call setup_task_manager        
    call setup_buffers             
    call create_daemon_task        
    call run_shell                 
    jmp $                          

; ----------------------------------------------------------------
; 初始化 ATA 中断机制
; ----------------------------------------------------------------
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

; ----------------------------------------------------------------
; ATA 硬盘中断服务程序 (IRQ14)
; ----------------------------------------------------------------
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

; ----------------------------------------------------------------
; BIOS 字符与字符串输出
; ----------------------------------------------------------------
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

; ----------------------------------------------------------------
; 包含各功能模块
; ----------------------------------------------------------------
%include "keyboard.inc"
%include "syscall.inc"
%include "comcall.inc"
%include "fat12.inc"
%include "vfs.inc"
%include "memory.inc"
%include "shell.inc"
%include "task.inc"
%include "panic.inc"
%include "mouse.inc"
%include "sound.inc"

; 磁盘读取分发器
disk_read_lba:
    cmp byte [cs:current_drive], 0x80
    jae ata_read_lba
    jmp floppy_read_lba

disk_write_lba:
    cmp byte [cs:current_drive], 0x80
    jae ata_write_lba
    jmp floppy_write_lba

; ----------------------------------------------------------------
; LBA 转 CHS 算法 (供 1.44MB 软盘使用)
; 输入: AX = LBA
; 输出: CH=柱面, DH=磁头, CL=扇区
; ----------------------------------------------------------------
lba_to_chs:
    push bx
    push ax
    mov bx, 18
    xor dx, dx
    div bx
    inc dx
    mov cl, dl          ; CL = 扇区号 (1-18)
    xor dx, dx
    mov bx, 2
    div bx
    mov ch, al          ; CH = 柱面号
    mov dh, dl          ; DH = 磁头号
    pop ax
    pop bx
    ret

; ----------------------------------------------------------------
; BIOS 软盘读取驱动 (INT 0x13)
; ----------------------------------------------------------------
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

    ; 软盘读取失败 (无磁盘/未就绪)，复位控制器并提示
    push ax
    mov ah, 0x00
    mov dl, [cs:current_drive]
    int 0x13
    pop ax

    call prompt_insert_floppy
    jc .floppy_err              ; 用户按 ESC 取消
    jmp .retry                  ; 用户按 ENTER 重试

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

; ----------------------------------------------------------------
; BIOS 软盘写入驱动 (INT 0x13)
; ----------------------------------------------------------------
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

    ; 软盘写入失败，复位控制器并提示
    push ax
    mov ah, 0x00
    mov dl, [cs:current_drive]
    int 0x13
    pop ax

    call prompt_insert_floppy
    jc .floppy_w_err            ; 用户按 ESC 取消
    jmp .retry_w                ; 用户按 ENTER 重试

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

; ----------------------------------------------------------------
; 软盘未就绪提示交互 (Abort, Retry, Fail?)
; ----------------------------------------------------------------
prompt_insert_floppy:
    pusha
    mov si, msg_insert_disk
    call print_string
.wait_key:
    call kb_get_key             ; 阻塞等待键盘输入
    cmp al, 27                  ; ESC 键
    je .cancel
    cmp al, 13                  ; ENTER 键
    je .retry_prompt
    jmp .wait_key
.cancel:
    mov si, msg_crlf
    call print_string
    popa
    stc                         ; 设置 CF=1 表示取消 (Abort)
    ret
.retry_prompt:
    mov si, msg_crlf
    call print_string
    popa
    clc                         ; 清除 CF=0 表示重试 (Retry)
    ret

; ================================================================
; ATA PIO 硬盘读取（LBA28 模式 + IRQ14 中断驱动）
; ================================================================
ata_read_lba:
    pusha
.read_loop:
    push cx
    push ax

    mov byte [cs:disk_irq_fired], 0

    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al
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

.wait_irq:
    cli                             
    cmp byte [cs:disk_irq_fired], 1
    je .irq_received                
    sti
    hlt                             
    jmp .wait_irq

.irq_received:
    sti                             
    mov dx, 0x1F0
    mov cx, 256
    mov di, bx
    push ds
    push es
    pop ds
    rep insw
    pop ds

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

; ================================================================
; ATA PIO 硬盘写入（LBA28 模式 + IRQ14 中断驱动）
; ================================================================
ata_write_lba:
    pusha
.write_loop:
    push cx
    push ax

    mov byte [cs:disk_irq_fired], 0

    mov dx, 0x1F6
    mov al, 0xE0
    out dx, al
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

.wait_drq:
    in al, dx
    test al, 0x08
    jz .wait_drq                    

    mov dx, 0x1F0
    mov cx, 256
    mov si, bx
    push ds
    push es
    pop ds
    rep outsw                       
    pop ds

.wait_irq_w:
    cli
    cmp byte [cs:disk_irq_fired], 1
    je .irq_w_received
    sti
    hlt                             
    jmp .wait_irq_w

.irq_w_received:
    sti
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

    mov dx, 0x1F7
    mov al, 0xE7
    out dx, al
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush

    popa
    clc
    ret

; ================================================================
boot_drive     db 0                     
current_drive  db 0x80

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