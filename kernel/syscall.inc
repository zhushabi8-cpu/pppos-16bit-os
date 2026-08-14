; ================================================================
; PPP OS 系统调用 (INT 0x80)
; ================================================================

setup_syscalls:
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x80*4], syscall_handler
    mov word [es:0x80*4+2], cs
    pop es
    sti
    ret

syscall_handler:
    push ds
    push es
    pusha

    cmp ah, 0x00
    je sys_print
    cmp ah, 0x01
    je sys_getkey
    cmp ah, 0x02
    je sys_read
    cmp ah, 0x03
    je sys_write
    cmp ah, 0x04
    je sys_exit_task
    cmp ah, 0x05
    je sys_open
    cmp ah, 0x06
    je sys_close
    cmp ah, 0x07
    je sys_vfs_read
    cmp ah, 0x08
    je sys_lseek
    cmp ah, 0x09
    je sys_file_size
    cmp ah, 0x0A
    je sys_read_dir
    cmp ah, 0x0B
    je sys_exec
    cmp ah, 0x0C
    je sys_delete
    cmp ah, 0x0D
    je sys_rename
    cmp ah, 0x0E
    je sys_chdir
    cmp ah, 0x0F
    je sys_clip_set
    cmp ah, 0x10
    je sys_clip_paste
    cmp ah, 0x14
    je sys_mouse_get
    cmp ah, 0x15
    je sys_check_key
    cmp ah, 0x16
    je sys_get_arg
    cmp ah, 0x17
    je sys_mkdir
    cmp ah, 0x18
    je sys_mouse_raw
    cmp ah, 0x19
    je sys_sound
    cmp ah, 0x1A
    je sys_play_wav
    cmp ah, 0x1D
    je sys_get_arg2
    cmp ah, 0x1E
    je sys_insmod
    cmp ah, 0x20
    je sys_get_ticks
    cmp ah, 0x21
    je sys_sleep
    cmp ah, 0x22
    je sys_yield
    cmp ah, 0x25
    je sys_serial_write
    cmp ah, 0x26
    je sys_serial_read_blk
    cmp ah, 0x27
    je sys_serial_read_noblk
    cmp ah, 0x30
    je sys_gfx_mode
    cmp ah, 0x31
    je sys_gfx_flip
    cmp ah, 0x32
    je sys_gfx_rect
    cmp ah, 0x33
    je sys_get_gfx_buf  
    cmp ah, 0x40
    je sys_malloc
    cmp ah, 0x41
    je sys_free
    cmp ah, 0x42
    je sys_reg_read
    cmp ah, 0x43
    je sys_reg_write
    cmp ah, 0x44
    je sys_get_drive
    cmp ah, 0x45
    je sys_set_drive

    jmp sys_exit

; ================================================================
; 基础 I/O 
; ================================================================

sys_print:
    mov bx, 1
    call vfs_write
    jmp sys_exit

sys_getkey:
    call kb_get_key
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit

sys_check_key:
    call kb_check_key
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit

sys_exit_task:
    cli
    mov ax, cs
    mov ds, ax
    xor ah, ah
    mov al, [current_task]
    mov bx, 32
    mul bx
    mov si, tcb_array
    add si, ax
    mov byte [si], 2
    sti
.die_loop:
    hlt
    jmp .die_loop

; ================================================================
; 文件系统 API 
; ================================================================

sys_read:
    call fat12_find_file
    jc .read_err
    push ax
    mov ax, cx
    or ax, dx
    pop ax
    jz .read_empty
    add ax, [cs:cluster_lba_offset] 
    push cx
    push ax
    mov ax, cx
    add ax, 511
    mov bx, dx
    adc bx, 0
    shl bx, 7
    shr ax, 9
    or ax, bx
    mov cx, ax
    pop ax
    mov bx, di
    call disk_read_lba
    pop cx
    mov bx, di
    add bx, cx
    mov byte [es:bx], 0
    mov al, 1
    jmp .read_done
.read_empty:
    mov al, 1
    jmp .read_done
.read_err:
    xor al, al
.read_done:
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_write:
    mov [cs:sys_tmp_cx], cx
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    push cx
    mov cx, 11
    mov al, ' '
    cld
    rep stosb
    pop cx
    mov di, sys_fat_name_buf
    mov cx, 8
.w_name_loop:
    lodsb
    or al, al
    jz .w_name_ok
    cmp al, '.'
    je .w_name_ext
    or cx, cx
    jz .w_name_loop
    stosb
    dec cx
    jmp .w_name_loop
.w_name_ext:
    mov di, sys_fat_name_buf + 8
    mov cx, 3
.w_ext_loop:
    lodsb
    or al, al
    jz .w_name_ok
    or cx, cx
    jz .w_ext_loop
    stosb
    dec cx
    jmp .w_ext_loop
.w_name_ok:
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    mov cx, [cs:sys_tmp_cx]
    call fat12_write_file
    pop ds
    jc .write_err
    mov al, 1
    jmp .write_done
.write_err:
    xor al, al
.write_done:
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_open:
    call vfs_open
    jc .open_err
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit
.open_err:
    mov bp, sp
    mov word [bp + 14], 0xFFFF
    jmp sys_exit

sys_close:
    call vfs_close
    jmp sys_exit

sys_vfs_read:
    call vfs_read
    jc .vr_err
    mov bp, sp
    mov byte [bp + 14], 1
    jmp sys_exit
.vr_err:
    mov bp, sp
    mov byte [bp + 14], 0
    jmp sys_exit

sys_lseek:
    cmp bx, 2
    jb .lseek_err
    cmp bx, 16
    jae .lseek_err
    push dx
    push ax
    mov ax, 14
    mul bx
    mov di, fd_table
    add di, ax
    pop ax
    pop dx
    cmp byte [cs:di + 0], 0
    je .lseek_err
    cmp al, 0
    je .ls_set
    cmp al, 1
    je .ls_cur
    cmp al, 2
    je .ls_end
    jmp .lseek_err
.ls_set:
    mov [cs:di + 6], dx
    mov word [cs:di + 8], 0
    jmp .ls_done
.ls_cur:
    add dx, [cs:di + 6]
    mov [cs:di + 6], dx
    adc word [cs:di + 8], 0
    jmp .ls_done
.ls_end:
    mov dx, [cs:di + 10]
    mov [cs:di + 6], dx
    mov cx, [cs:di + 12]
    mov [cs:di + 8], cx
.ls_done:
    mov ax, dx
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit
.lseek_err:
    mov bp, sp
    mov word [bp + 14], 0xFFFF
    jmp sys_exit

sys_file_size:
    cmp bx, 2
    jb .fsz_err
    cmp bx, 16
    jae .fsz_err
    mov ax, 14
    mul bx
    mov di, fd_table
    add di, ax
    cmp byte [cs:di + 0], 0
    je .fsz_err
    mov ax, [cs:di + 10]
    mov dx, [cs:di + 12]
    mov bp, sp
    mov [bp + 14], ax
    mov [bp + 10], dx
    jmp sys_exit
.fsz_err:
    mov bp, sp
    mov word [bp + 14], 0xFFFF
    jmp sys_exit

sys_read_dir:
    call vfs_read_dir
    mov bp, sp
    mov [bp + 12], cx
    jmp sys_exit

sys_exec:
    sti
    cld
    push ds
    push es
    push di
    push si

    mov ax, cs
    mov es, ax
    mov di, cmd_buffer
.copy_cmd:
    lodsb
    stosb
    or al, al
    jnz .copy_cmd

    mov bp, sp
    mov si, [bp + 2]                ; 获取调用者传入的 DI
    mov ds, [bp + 4]                ; 获取调用者传入的 ES
    mov ax, cs
    mov es, ax
    mov di, sys_app_arg
    mov cx, 11
    rep movsb

    mov di, sys_app_arg2
    mov cx, 11
    mov al, ' '
    rep stosb

    pop si
    pop di
    pop es
    pop ds
    mov ax, cs
    mov ds, ax
    mov es, ax
    call find_and_execute
    jmp sys_exit

sys_delete:
    call fat12_delete_file
    jc .del_err
    mov al, 1
    jmp .del_done
.del_err:
    xor al, al
.del_done:
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_rename:
    call fat12_rename_file
    jc .ren_err
    mov al, 1
    jmp .ren_done
.ren_err:
    xor al, al
.ren_done:
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_chdir:
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    push cx
    mov cx, 11
    mov al, ' '
    cld
    rep stosb
    pop cx
    cmp word [si], 0x2E2E
    jne .cd_fmt
    mov byte [cs:sys_fat_name_buf], '.'
    mov byte [cs:sys_fat_name_buf+1], '.'
    jmp .cd_do
.cd_fmt:
    mov di, sys_fat_name_buf
    mov cx, 8
.cd_loop:
    lodsb
    or al, al
    jz .cd_do
    cmp al, ' '
    je .cd_do
    cmp al, '.'
    je .cd_ext
    or cx, cx
    jz .cd_loop
    stosb
    dec cx
    jmp .cd_loop
.cd_ext:
    mov di, sys_fat_name_buf + 8
    mov cx, 3
.cd_ext_loop:
    lodsb
    or al, al
    jz .cd_do
    cmp al, ' '
    je .cd_do
    or cx, cx
    jz .cd_ext_loop
    stosb
    dec cx
    jmp .cd_ext_loop
.cd_do:
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_change_dir
    pop ds
    jc .cd_err
    mov al, 1
    jmp .cd_done
.cd_err:
    xor al, al
.cd_done:
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_mkdir:
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    mov cx, 11
    cld
    rep movsb
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_make_dir
    pop ds
    jc .md_err
    mov al, 1
    jmp .md_done
.md_err:
    xor al, al
.md_done:
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

; ================================================================
; 剪贴板
; ================================================================
sys_clip_set:
    cmp al, 0
    jne .append_clip
    mov byte [cs:clip_count], 0
    mov byte [cs:clip_op], 0
    jmp .clip_set_ok
.append_clip:
    cmp byte [cs:clip_count], 64
    jae .clip_set_fail
    mov [cs:clip_op], al

    mov bx, [cs:cwd_cluster]
    mov [cs:clip_dir], bx
    mov al, [cs:current_drive]
    mov [cs:clip_drive], al
    mov al, [cs:current_part]      
    mov [cs:clip_part], al         

    xor ah, ah
    mov al, [cs:clip_count]
    mov cx, 11
    mul cx
    mov di, ax
    push es
    mov bx, [cs:seg_clip_buf]
    mov es, bx
    mov cx, 11
    cld
    rep movsb
    pop es
    inc byte [cs:clip_count]
.clip_set_ok:
    mov al, 1
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit
.clip_set_fail:
    xor al, al
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_clip_paste:
    cmp byte [cs:clip_op], 0
    je .paste_fail
    cmp byte [cs:clip_count], 0
    je .paste_fail

    mov bx, [cs:cwd_cluster]
    mov [cs:paste_dest_dir], bx
    mov al, [cs:current_drive]
    mov [cs:paste_dest_drive], al
    mov al, [cs:current_part]
    mov [cs:paste_dest_part], al   

    mov byte [cs:.paste_idx], 0
.paste_loop:
    mov al, [cs:.paste_idx]
    cmp al, [cs:clip_count]
    jae .paste_done
    xor ah, ah
    mov cx, 11
    mul cx
    mov si, ax
    push ds
    push es
    mov bx, [cs:seg_clip_buf]
    mov ds, bx
    push cs
    pop es
    mov di, sys_fat_name_buf
    mov cx, 11
    cld
    rep movsb
    pop es
    pop ds

    ; 1. 切换到源盘读取
    mov bx, [cs:clip_dir]
    mov [cs:cwd_cluster], bx
    mov al, [cs:clip_drive]
    mov [cs:current_drive], al
    mov al, [cs:clip_part]         
    mov [cs:current_part], al      
    call fat_init_drive            

    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_find_file
    jc .paste_next_restore

    mov [cs:paste_size], cx
    or cx, cx
    jz .do_write
    push ax
    push cx
    add ax, [cs:cluster_lba_offset]
    pop cx
    add cx, 511
    shr cx, 9
    mov bx, [cs:seg_gfx_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    pop ax

    cmp byte [cs:clip_op], 2
    jne .do_write
    mov si, sys_fat_name_buf
    call fat12_delete_file

.do_write:
    ; 2. 切换回目标盘写入
    mov bx, [cs:paste_dest_dir]
    mov [cs:cwd_cluster], bx
    mov al, [cs:paste_dest_drive]
    mov [cs:current_drive], al
    mov al, [cs:paste_dest_part]   
    mov [cs:current_part], al      
    call fat_init_drive            

    mov si, sys_fat_name_buf
    mov cx, [cs:paste_size]
    mov ax, [cs:seg_gfx_buf]
    mov es, ax
    xor di, di
    call fat12_write_file

.paste_next:
    inc byte [cs:.paste_idx]
    jmp .paste_loop

.paste_next_restore:
    mov bx, [cs:paste_dest_dir]
    mov [cs:cwd_cluster], bx
    mov al, [cs:paste_dest_drive]
    mov [cs:current_drive], al
    mov al, [cs:paste_dest_part]   
    mov [cs:current_part], al      
    call fat_init_drive            
    jmp .paste_next

.paste_done:
    cmp byte [cs:clip_op], 2
    jne .paste_exit_ok
    mov byte [cs:clip_count], 0
    mov byte [cs:clip_op], 0
.paste_exit_ok:
    mov al, 1
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit
.paste_fail:
    xor al, al
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit
.paste_idx db 0

sys_mouse_get:
    mov cx, [cs:mouse_x]
    shr cx, 3
    mov dx, [cs:mouse_y]
    shr dx, 3
    mov bl, [cs:mouse_btn]
    xor bh, bh
    mov bp, sp
    mov [bp + 12], cx
    mov [bp + 10], dx
    mov [bp + 8], bx
    jmp sys_exit

sys_mouse_raw:
    mov cx, [cs:mouse_x]
    mov dx, [cs:mouse_y]
    mov bl, [cs:mouse_btn]
    xor bh, bh
    mov bp, sp
    mov [bp + 12], cx
    mov [bp + 10], dx
    mov [bp + 8], bx
    jmp sys_exit

sys_get_arg:
    push ds
    push cs
    pop ds
    mov si, sys_app_arg
    mov cx, 11
    rep movsb
    pop ds
    jmp sys_exit

sys_get_arg2:
    push ds
    push cs
    pop ds
    mov si, sys_app_arg2
    mov cx, 11
    rep movsb
    pop ds
    jmp sys_exit

sys_sound:
    cmp al, 1
    je .sound_on
    cmp al, 0
    je .sound_off
    jmp sys_exit
.sound_on:
    call pc_beep_on
    jmp sys_exit
.sound_off:
    call pc_beep_off
    jmp sys_exit

sys_play_wav:
    mov ah, 0x02
    int 0x81
    jmp sys_exit

sys_insmod:
    push es
    push di
    push cs
    pop es
    mov di, sys_fat_name_buf
    push cx
    mov cx, 11
    mov al, ' '
    cld
    rep stosb
    pop cx
    mov di, sys_fat_name_buf
    mov cx, 8
.ins_name_loop:
    lodsb
    cmp al, '.'
    je .ins_ext
    cmp al, ' '
    je .ins_do
    or al, al
    jz .ins_do
    stosb
    loop .ins_name_loop
    jmp .ins_skip_to_ext
.ins_skip_to_ext:
    lodsb
    cmp al, '.'
    je .ins_ext
    or al, al
    jz .ins_do
    jmp .ins_skip_to_ext
.ins_ext:
    mov di, sys_fat_name_buf + 8
    mov cx, 3
.ins_ext_loop:
    lodsb
    cmp al, ' '
    je .ins_do
    or al, al
    jz .ins_do
    stosb
    loop .ins_ext_loop
.ins_do:
    pop di
    pop es
    push ds
    push cs
    pop ds
    mov si, sys_fat_name_buf
    call fat12_find_file
    pop ds
    jc .insmod_err
    add ax, [cs:cluster_lba_offset] 
    mov bp, ax
    mov ax, cx
    add ax, 511
    shr ax, 9
    mov cx, ax
    pusha
    call drv_malloc             
    mov [cs:.tmp_seg], ax       
    popa
    jc .insmod_err              
    push es
    mov ax, [cs:.tmp_seg]
    mov es, ax
    xor bx, bx
    mov ax, bp
    call disk_read_lba
    pop es
    jc .insmod_err
    push ds
    mov ax, [cs:.tmp_seg]
    mov ds, ax
    cmp byte [0], 'P'
    jne .invalid_drv
    cmp byte [1], 'D'
    jne .invalid_drv
    cmp byte [2], 'R'
    jne .invalid_drv
    pop ds
    mov ax, [cs:.tmp_seg]
    inc ax                          
    mov word [cs:.drv_ptr+2], ax    
    mov word [cs:.drv_ptr], 0x0000  
    call far [cs:.drv_ptr]
    cmp al, 1
    je .insmod_ok
    jmp .insmod_err
.invalid_drv:
    pop ds
    jmp .insmod_err
.insmod_ok:
    mov al, 1
    jmp .insmod_exit
.insmod_err:
    xor al, al
.insmod_exit:
    mov bp, sp
    mov [bp+14], al
    jmp sys_exit
.drv_ptr dd 0
.tmp_seg dw 0

sys_get_ticks:
    mov ax, [cs:sys_ticks]
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit

sys_sleep:
    mov ax, bx
    mov cx, 55
    xor dx, dx
    div cx
    or ax, ax
    jnz .s_do
    inc ax
.s_do:
    add ax, [cs:sys_ticks]
    cli
    push ax
    mov al, [cs:current_task]
    xor ah, ah
    mov bx, 32
    mul bx
    mov si, tcb_array
    add si, ax
    pop ax
    mov [cs:si + 5], ax
    mov byte [cs:si + 0], 3
    sti
    hlt
    jmp sys_exit

sys_yield:
    sti
    hlt
    jmp sys_exit

sys_serial_write:
    mov ah, 0x01
    int 0x82
    jmp sys_exit

sys_serial_read_blk:
    mov ah, 0x02
    int 0x82
    mov bp, sp
    mov [bp + 14], al
    jmp sys_exit

sys_serial_read_noblk:
    mov ah, 0x03
    int 0x82
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit

sys_gfx_mode:
    cmp al, 1
    je .set_vga
    mov ax, 0x0003
    int 0x10
    jmp sys_exit
.set_vga:
    mov ax, 0x0013
    int 0x10
    push es
    mov ax, [cs:seg_gfx_buf]
    mov es, ax
    xor di, di
    mov cx, 32000
    xor ax, ax
    rep stosw
    pop es
    jmp sys_exit

sys_gfx_flip:
    push ds
    push es
    mov ax, [cs:seg_gfx_buf]
    mov ds, ax
    mov ax, 0xA000
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 32000
    cld
    rep movsw
    pop es
    pop ds
    jmp sys_exit

sys_gfx_rect:
    pusha
    push es
    mov bp, [cs:seg_gfx_buf]
    mov es, bp
    mov [cs:.color], al
    mov [cs:.w], si
    mov [cs:.h], di
    mov ax, dx
    mov bx, 320
    push dx
    mul bx                      
    pop dx
    add ax, cx
    mov di, ax
.row_loop:
    cmp word [cs:.h], 0
    je .rect_done
    mov cx, [cs:.w]
    mov al, [cs:.color]
    push di
    rep stosb
    pop di
    add di, 320
    dec word [cs:.h]
    jmp .row_loop
.rect_done:
    pop es
    popa
    jmp sys_exit
.color db 0
.w     dw 0
.h     dw 0

sys_get_gfx_buf:
    mov ax, [cs:seg_gfx_buf]
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit

sys_malloc:
    call kmalloc
    jc .malloc_err
    mov bp, sp
    mov [bp + 14], ax
    jmp sys_exit
.malloc_err:
    mov bp, sp
    mov word [bp + 14], 0
    jmp sys_exit

sys_free:
    mov ax, bx
    call kfree
    jmp sys_exit

load_registry:
    cmp byte [cs:reg_loaded], 1
    je .lr_ret
    pusha
    push ds
    push es
    mov ax, [cs:seg_reg_buf]
    mov es, ax
    xor di, di
    mov cx, 1024
    xor ax, ax
    rep stosw

    push cs
    pop ds
    mov si, reg_filename
    call fat12_find_file
    jc .lr_done

    add ax, [cs:cluster_lba_offset] 
    mov cx, 4
    mov bx, 0
    mov dx, [cs:seg_reg_buf]
    mov es, dx
    call disk_read_lba

.lr_done:
    mov byte [cs:reg_loaded], 1
    pop es
    pop ds
    popa
.lr_ret:
    ret

sys_reg_read:
    call load_registry
    push di
    push ds
    push es
    mov ax, [cs:seg_reg_buf]
    mov es, ax
    xor bx, bx
.rd_loop:
    cmp bx, 2048                
    jae .rd_fail
    mov al, [es:bx]
    or al, al
    jz .rd_fail                 

    mov cx, 16                  
    mov di, bx                  
    push si
    repe cmpsb
    pop si
    je .rd_found

    add bx, 32                  
    jmp .rd_loop

.rd_found:
    pop es
    pop ds
    pop di                      
    push ds
    push si
    mov ax, [cs:seg_reg_buf]
    mov ds, ax
    mov si, bx
    add si, 16
    mov cx, 8                   
    rep movsb
    pop si
    pop ds
    mov al, 1
    jmp .rd_exit

.rd_fail:
    pop es
    pop ds
    pop di                      
    xor al, al
.rd_exit:
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

sys_reg_write:
    call load_registry
    push ds
    push es
    mov ax, [cs:seg_reg_buf]
    mov es, ax
    xor bx, bx
.wr_loop:
    cmp bx, 2048
    jae .wr_fail
    mov al, [es:bx]
    or al, al
    jz .wr_do_write

    mov cx, 16                  
    mov di, bx
    push si
    repe cmpsb
    pop si
    je .wr_do_write             

    add bx, 32
    jmp .wr_loop

.wr_do_write:
    mov cx, 16
    mov di, bx
    rep movsb

    mov si, dx
    mov cx, 8
    rep movsb

    xor al, al
    mov cx, 8
    rep stosb

    push cs
    pop ds
    mov si, reg_filename
    mov ax, [cs:seg_reg_buf]
    mov es, ax
    xor di, di
    mov cx, 2048
    mov [cs:sys_tmp_cx], cx
    call fat12_write_file

    pop es
    pop ds
    mov ax, 1
    jmp .wr_exit

.wr_fail:
    pop es
    pop ds
    xor ax, ax
.wr_exit:
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

sys_get_drive:
    mov al, [cs:active_letter]      
    xor ah, ah
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

sys_set_drive:
    pusha
    push es
    
    mov bl, al                  
    cmp bl, 'a'
    jb .check_letter
    cmp bl, 'z'
    ja .check_letter
    sub bl, 32                  ; 统一转大写
    
.check_letter:
    cmp bl, 'A'
    je .set_floppy
    cmp bl, 'B'
    je .set_floppy
    
    cmp bl, 'C'
    jb .invalid_drv
    cmp bl, 'Z'
    ja .invalid_drv
    
    mov al, bl
    sub al, 'C'
    xor ah, ah
    mov cl, 4
    div cl                      ; AL = 物理硬盘偏移 (0=0x80, 1=0x81...), AH = 分区号 (0~3)
    add al, 0x80
    mov dl, al                  ; DL = 物理硬盘号
    mov dh, ah                  ; DH = MBR 分区索引
    jmp .set_hdd_ok
    
.set_floppy:
    mov dl, 0x00                ; 软盘 0 = A:
    mov dh, 0                   
    
    mov cx, [cs:seg_gfx_buf]
    mov es, cx
    xor bx, bx
    
    mov ah, 0x02                
    mov al, 1                   
    mov ch, 0                   
    mov cl, 1                   
    push dx
    int 0x13
    pop dx
    jc .ping_fail
    
.set_hdd_ok:
    pop es
    
    ; 备份当前驱动器状态
    mov al, [cs:current_drive]
    mov ah, [cs:current_part]
    push ax
    mov al, [cs:active_letter]
    push ax
    mov ax, [cs:cwd_cluster]
    push ax

    mov [cs:current_drive], dl
    mov [cs:current_part], dh
    
    call fat_init_drive             
    jc .ping_fail_post          ; 分区未格式化/物理盘不存在时，自动回滚
    
    add sp, 6                   ; 成功：销毁备份栈
    
    mov [cs:active_letter], bl      
    mov word [cs:cwd_cluster], 0    
    
    popa
    mov ax, 1                       
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

.ping_fail_post:
    pop ax
    mov [cs:cwd_cluster], ax
    pop ax
    mov [cs:active_letter], al
    pop ax
    mov [cs:current_part], ah
    mov [cs:current_drive], al
    
    call fat_init_drive             

    popa
    xor ax, ax                      
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

.ping_fail:
    xor ax, ax
    int 0x13                        
    pop es
    popa
    xor ax, ax                      
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

.invalid_drv:
    pop es
    popa
    xor ax, ax
    mov bp, sp
    mov [bp+14], ax
    jmp sys_exit

sys_exit:
    popa
    pop es
    pop ds
    iret

; ================================================================
sys_fat_name_buf times 11 db ' '
clip_op         db 0
clip_dir        dw 0
clip_drive      db 0
clip_part       db 0      
clip_count      db 0
paste_dest_dir  dw 0
paste_dest_drive db 0
paste_dest_part  db 0     
paste_size      dw 0
sys_app_arg     times 11 db ' '
sys_app_arg2    times 11 db ' '
sys_tmp_cx      dw 0

reg_filename    db "SYSTEM  REG"
reg_loaded      db 0