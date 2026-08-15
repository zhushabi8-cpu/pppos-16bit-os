; ================================================================
; PPP OS 命令行外壳 (Shell)
; ================================================================

%define KERNEL_LOCK 0x04F0        

run_shell:
    mov si, msg_ready
    call print_string

    ; 自动加载 DRV0 ~ DRV9 驱动
    mov cl, '0'                 
.drv_loop:
    push cx                     
    mov [cs:sys_drv_key + 3], cl 

    push cs
    pop es
    mov di, cmd_buffer          
    
    push cs
    pop ds
    mov si, sys_drv_key
    mov ah, 0x42                
    int 0x80
    
    cmp al, 1
    jne .drv_next               

    mov si, cmd_buffer
    mov di, fat_filename
    mov cx, 8
.fmt_drv_name:
    lodsb
    cmp al, ' '
    je .append_pdr              
    stosb
    loop .fmt_drv_name
.append_pdr:
    mov al, '.'
    stosb
    mov al, 'P'
    stosb
    mov al, 'D'
    stosb
    mov al, 'R'
    stosb
    xor al, al
    stosb

    mov si, msg_auto_drv
    call print_string
    mov si, fat_filename
    call print_string

    mov si, fat_filename
    mov ah, 0x1E
    int 0x80

    cmp al, 1
    je .drv_ok
    mov si, msg_auto_fail       
    call print_string
    jmp .drv_next

.drv_ok:
    mov si, msg_auto_ok         
    call print_string

.drv_next:
    pop cx                      
    inc cl
    cmp cl, '9'
    jbe .drv_loop               

    ; 查询开机自启配置
    push cs
    pop es
    mov di, cmd_buffer
    
    push cs
    pop ds
    mov si, sys_boot_key        
    mov ah, 0x42
    int 0x80
    cmp al, 1
    jne prompt_loop             

    mov byte [cmd_buffer+8], 0  
    mov si, msg_autorun
    call print_string
    mov si, cmd_buffer
    call print_string
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    
    pusha
    mov di, sys_app_arg
    mov cx, 11
    mov al, ' '
    rep stosb
    mov di, sys_app_arg2
    mov cx, 11
    rep stosb
    popa

    call uppercase_cmd
    call find_and_execute

prompt_loop:
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov al, 13
    call print_char
    mov al, 10
    call print_char

    ; 动态提示符 C:\>
    mov al, [cs:active_letter]  
    call print_char
    mov al, ':'                 
    call print_char
    mov si, sys_path            
    call print_string
    mov al, '>'                 
    call print_char
    mov al, ' '                 
    call print_char
    
    mov di, cmd_buffer
    call read_line               

    mov al, 13
    call print_char
    mov al, 10
    call print_char

    mov si, cmd_buffer
    lodsb
    or al, al
    jz prompt_loop

    pusha
    mov di, sys_app_arg
    mov cx, 22
    mov al, ' '
    rep stosb
    popa

    call uppercase_cmd

    ; 检查 BG 指令
    mov byte [cs:is_bg_task], 0
    cmp word [cmd_buffer], 0x4742   
    jne .not_bg
    cmp byte [cmd_buffer + 2], ' '
    jne .not_bg
    
    mov byte [cs:is_bg_task], 1
    mov si, cmd_buffer + 3
    mov di, cmd_buffer
.copy_bg:
    lodsb
    stosb
    or al, al
    jnz .copy_bg

.not_bg:
    call check_exit_cmd
    jc .handle_exit
    
    mov ax, cs
    cmp ax, 0x0800
    jne .kernel_locked

    call check_drive_cmd
    jc .run_drive_mode
    call check_cd_cmd
    jc .run_cd_mode
    call check_md_cmd
    jc .run_md_mode
    call check_dir_cmd
    jc .run_dir_mode
    call check_time_cmd
    jc .run_time_mode
    call check_reboot_cmd
    jc .run_reboot
    call check_shutdown_cmd
    jc .run_shutdown
    call check_insmod_cmd
    jc .run_insmod

    call find_and_execute
    jmp prompt_loop

.run_drive_mode:
    mov al, [cmd_buffer]
    cmp al, 'A'
    je .switch_ab
    cmp al, 'B'
    je .switch_ab
    
    cmp al, 'C'
    jb prompt_loop
    cmp al, 'Z'
    ja prompt_loop

    mov dl, [cs:current_drive]
    mov dh, [cs:current_part]
    push dx

    ; 动态数学映射
    push ax
    sub al, 'C'                     
    xor ah, ah
    mov cl, 4
    div cl                          
    add al, 0x80                    
    mov [cs:current_drive], al
    mov [cs:current_part], ah       
    
    pop ax
    mov bl, al
    jmp .do_drv_switch

.switch_ab:
    mov dl, [cs:current_drive]
    mov dh, [cs:current_part]
    push dx

    mov byte [cs:current_drive], 0x00
    mov byte [cs:current_part], 0
    mov bl, al                      

.do_drv_switch:
    call fat_init_drive             
    jc .drv_fail

    pop dx
    mov [cs:active_letter], bl
    mov word [cs:cwd_cluster], 0        
    mov byte [cs:sys_path + 1], 0       
    jmp prompt_loop

.drv_fail:
    pop dx
    mov [cs:current_drive], dl
    mov [cs:current_part], dh
    call fat_init_drive             

    mov si, msg_mount_err
    call print_string
    jmp prompt_loop

.run_insmod:
    mov si, cmd_buffer + 7
    mov ah, 0x1E
    int 0x80
    or al, al
    jz .insmod_fail
    mov si, msg_drv_ok
    call print_string
    jmp prompt_loop
.insmod_fail:
    mov si, msg_drv_err
    call print_string
    jmp prompt_loop

.run_cd_mode:
    cmp byte [cmd_buffer + 3], '\'
    jne .check_dotdot
    mov word [cs:cwd_cluster], 0
    mov byte [cs:sys_path + 1], 0
    jmp prompt_loop

.check_dotdot:
    mov si, cmd_buffer + 3
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb
    cmp word [cmd_buffer + 3], 0x2E2E
    jne .fmt_cd
    mov byte [fat_filename], '.'
    mov byte [fat_filename+1], '.'
    jmp .do_cd
.fmt_cd:
    mov si, cmd_buffer + 3
    mov di, fat_filename
.cd_copy:
    lodsb
    or al, al
    jz .do_cd
    cmp al, ' '
    je .do_cd
    stosb
    jmp .cd_copy
.do_cd:
    mov si, fat_filename
    call fat12_change_dir
    jc .cd_err
    call update_sys_path                
    jmp prompt_loop
.cd_err:
    mov si, msg_cd_err
    call print_string
    jmp prompt_loop

.run_md_mode:
    mov si, cmd_buffer + 3
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb
.fmt_md:
    mov si, cmd_buffer + 3
    mov di, fat_filename
.md_copy:
    lodsb
    or al, al
    jz .do_md
    cmp al, ' '
    je .do_md
    stosb
    jmp .md_copy
.do_md:
    mov si, fat_filename
    call fat12_make_dir
    jnc .md_ok
    mov si, msg_err
    call print_string
.md_ok:
    mov si, msg_md_ok
    call print_string
    jmp prompt_loop

.run_dir_mode:
    call print_dir_table
    jmp prompt_loop

.run_time_mode:
    mov si, msg_time
    call print_string
    mov ah, 0x02
    int 0x1A
    mov al, ch
    call print_bcd_cli
    mov al, ':'
    call print_char
    mov al, cl
    call print_bcd_cli
    mov al, ':'
    call print_char
    mov al, dh
    call print_bcd_cli
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    jmp prompt_loop

.run_reboot:
    mov si, msg_rebooting
    call print_string
    mov ax, 0x0040
    mov ds, ax
    mov word [0x0072], 0x1234
    jmp 0xFFFF:0000

.run_shutdown:
    mov si, msg_shutdown
    call print_string
    mov ax, 0x5301
    xor bx, bx
    int 0x15
    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15
    cli
    hlt

.kernel_locked:
    mov si, msg_locked_err
    call print_string
    jmp prompt_loop

.handle_exit:
    mov ax, cs
    cmp ax, 0x0800
    je .is_primary_shell
    mov si, msg_exit
    call print_string
    xor ax, ax
    mov gs, ax
    mov byte [gs:KERNEL_LOCK], 0
    retf
.is_primary_shell:
    mov si, msg_no_exit
    call print_string
    jmp prompt_loop

update_sys_path:
    pusha
    cmp word [cmd_buffer + 3], 0x2E2E  
    je .go_up

    mov di, sys_path
.find_end:
    cmp byte [di], 0
    je .found_end
    inc di
    jmp .find_end
.found_end:
    cmp di, sys_path + 1
    je .append_name
    mov byte [di], '\'
    inc di
.append_name:
    mov si, cmd_buffer + 3
.copy_name:
    lodsb
    or al, al
    jz .done_copy
    cmp al, ' '
    je .done_copy
    stosb
    jmp .copy_name
.done_copy:
    mov byte [di], 0
    jmp .done

.go_up:
    mov di, sys_path
.find_end2:
    cmp byte [di], 0
    je .found_end2
    inc di
    jmp .find_end2
.found_end2:
.backtrack:
    cmp di, sys_path + 1            
    jbe .done_up
    dec di
    cmp byte [di], '\'              
    je .done_up
    mov byte [di], 0
    jmp .backtrack
.done_up:
    mov byte [di], 0                
.done:
    popa
    ret

check_drive_cmd:
    pusha
    mov al, [cmd_buffer]
    cmp al, 'A'
    jb .not_drive                   
    cmp al, 'Z'
    ja .not_drive                   
.check_colon:
    cmp byte [cmd_buffer+1], ':'    
    jne .not_drive
    cmp byte [cmd_buffer+2], 0      
    jne .not_drive
    popa
    stc
    ret
.not_drive:
    popa
    clc
    ret

check_insmod_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_insmod
    mov cx, 7
    repe cmpsb
    jne .not_ins
    popa
    stc
    ret
.not_ins: popa
    clc
    ret

check_cd_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_cd
    mov cx, 3
    repe cmpsb
    jne .not_cd
    popa
    stc
    ret
.not_cd: popa
    clc
    ret

check_md_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_md
    mov cx, 3
    repe cmpsb
    jne .not_md
    popa
    stc
    ret
.not_md: popa
    clc
    ret

check_reboot_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_reboot
    mov cx, 6
    repe cmpsb
    jne .not_r
    lodsb
    or al, al
    jnz .not_r
    popa
    stc
    ret
.not_r: popa
    clc
    ret

check_shutdown_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_shutdown
    mov cx, 8
    repe cmpsb
    jne .not_s
    lodsb
    or al, al
    jnz .not_s
    popa
    stc
    ret
.not_s: popa
    clc
    ret

check_time_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_time
    mov cx, 4
    repe cmpsb
    jne .not_t
    lodsb
    or al, al
    jnz .not_t
    popa
    stc
    ret
.not_t: popa
    clc
    ret

check_dir_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_dir
    mov cx, 3
    repe cmpsb
    jne .not_d
    lodsb
    or al, al
    jnz .not_d
    popa
    stc
    ret
.not_d: popa
    clc
    ret

check_exit_cmd:
    pusha
    cld
    mov si, cmd_buffer
    mov di, str_exit
    mov cx, 4
    repe cmpsb
    jne .not_e
    lodsb
    or al, al
    jnz .not_e
    popa
    stc
    ret
.not_e: popa
    clc
    ret

print_dir_table:
    pusha
    mov si, msg_sys_dir
    call print_string
    mov ax, [cs:seg_gfx_buf]
    mov es, ax
    xor di, di
    mov al, 20                      
    call vfs_read_dir               
    or cx, cx
    jz .p_empty
    mov dx, cx
    push ds
    mov ax, [cs:seg_gfx_buf]
    mov ds, ax
    xor si, si
    mov bp, 0                       
.p_loop:
    push dx
    push si
    mov ax, cs
    mov ds, ax
    mov si, msg_item_pre
    call print_string
    pop si
    push si
    mov ax, [cs:seg_gfx_buf]
    mov ds, ax
    mov cx, 11                      
.p_char:
    lodsb
    cmp al, ' '
    je .p_next
    push ax
    mov ax, cs
    mov ds, ax
    pop ax
    call print_char
    mov ax, [cs:seg_gfx_buf]
    mov ds, ax
.p_next:
    loop .p_char
    pop si
    push si
    mov ax, [cs:seg_gfx_buf]
    mov ds, ax
    mov al, [si + 11]               
    test al, 0x10
    jz .print_size
    mov ax, cs
    mov ds, ax
    mov si, msg_dir_tag
    call print_string
    jmp .print_nl
.print_size:
    mov ax, [si + 12]
    mov dx, [si + 14]
    add ax, 1023
    adc dx, 0
    mov cx, 10
.shr_loop:
    shr dx, 1
    rcr ax, 1
    loop .shr_loop
    push ax
    mov ax, cs
    mov ds, ax
    mov si, msg_space
    call print_string
    pop ax
    call print_uint16               
    mov si, msg_kb
    call print_string
.print_nl:
    mov ax, cs
    mov ds, ax
    mov al, 13
    call print_char
    mov al, 10
    call print_char
.no_pause:
    pop si
    add si, 20                      
    pop dx
    mov ax, [cs:seg_gfx_buf]
    mov ds, ax
    dec dx
    jnz .p_loop
    pop ds
    popa
    ret
.p_empty:
    mov si, msg_no_files
    call print_string
    popa
    ret

; 查找并执行程序
find_and_execute:
    pusha
    push ds
    push es
    cld
    mov si, cmd_buffer
    mov di, fat_filename
    mov cx, 11
    mov al, ' '
    rep stosb
    
    mov si, cmd_buffer
    mov di, fat_filename
.copy_name:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .parse_arg
    cmp al, '.'
    je .next_part
    stosb
    jmp .copy_name
.next_part:
    mov di, fat_filename + 8        
    jmp .copy_name

.parse_arg:
    ; 命令行有空格传参时才重写参数区
    push di
    mov di, sys_app_arg
    mov cx, 11
    mov al, ' '
    rep stosb
    pop di

    mov cx, 11
.skip_spaces:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .skip_spaces
    dec si
    mov di, sys_app_arg
.arg_copy:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .parse_arg2
    cmp al, '.'
    je .arg_ext
    jcxz .arg_skip                 
    stosb
    dec cx
.arg_skip:
    jmp .arg_copy
.arg_ext:
    mov di, sys_app_arg + 8
    mov cx, 3                      
    jmp .arg_copy

.parse_arg2:
    mov cx, 11
.skip_spaces2:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .skip_spaces2
    dec si
    mov di, sys_app_arg2
.arg2_copy:
    lodsb
    or al, al
    jz .add_ext
    cmp al, ' '
    je .add_ext
    cmp al, '-'                    
    je .arg2_copy
    jcxz .arg2_skip
    stosb
    dec cx
.arg2_skip:
    jmp .arg2_copy

.add_ext:
    cmp byte [fat_filename + 8], ' '
    jne .do_search
    mov di, fat_filename + 8
    mov al, 'P'
    stosb
    mov al, 'E'
    stosb
    mov al, 'X'
    stosb

.do_search:
    mov si, fat_filename
    call fat12_find_file
    jc .not_found

    test bl, 0x10                  
    jnz .not_found

    push ax                        
    mov ax, cx
    or ax, dx
    pop ax
    jz .invalid_format_no_free

    add ax, [cs:cluster_lba_offset] 
    mov bp, ax          
    
    mov ax, cx
    add ax, 511
    mov bx, dx
    adc bx, 0
    shl bx, 7
    shr ax, 9
    or ax, bx
    mov [cs:sys_tmp_cx], ax 

    xor ax, ax
    mov gs, ax
    mov byte [gs:KERNEL_LOCK], 1

    ; 查找空闲 TCB 槽位
    mov cx, 4
    mov si, tcb_array
    xor bx, bx
.find_slot:
    cmp byte [si], 0
    je .slot_found
    add si, 32
    inc bx
    loop .find_slot
    jmp .release_lock

.slot_found:
    ; --------------------------------------------------------
    ; 1. 先读取文件的第一个扇区，解析文件头获取 SP
    ; --------------------------------------------------------
    pusha
    mov ax, [cs:seg_dir_buf]        ; 借用目录缓冲区作为临时读取区
    mov es, ax
    xor bx, bx
    mov ax, bp                      ; BP 存的是文件起始 LBA
    mov cx, 1                       ; 只读 1 个扇区
    call disk_read_lba
    popa

    ; --------------------------------------------------------
    ; 2. 提取 SP 并严格按 SP 计算需要的 4KB 块数
    ; --------------------------------------------------------
    push es
    mov ax, [cs:seg_dir_buf]
    mov es, ax
    mov dx, [es:8]                  ; 读取文件头 8 字节处的初始 SP
    pop es

    ; 将 SP 转换为需要的 4KB 块数: blocks = (SP - 1) / 4096 + 1
    ; 【关键修复】防止 16 位加法溢出！
    mov ax, dx
    dec ax                          ; SP - 1
    shr ax, 12                      ; / 4096
    inc ax                          ; + 1
    mov cx, ax

    or cx, cx
    jnz .call_kmalloc
    mov cx, 1                       ; 至少分配 1 块 (4KB) 防御性保护

.call_kmalloc:
    call kmalloc
    jc .out_of_memory
    
    ; --------------------------------------------------------
    ; 3. 分配成功，正式将整个文件读入分配好的段中
    ; --------------------------------------------------------
    mov es, ax                      ; ES = 分配到的 4KB 粒度段基址
    push ax
    xor bx, bx
    mov ax, bp
    mov cx, [cs:sys_tmp_cx]        
    call disk_read_lba             
    
    pop dx
    push ds
    mov ds, dx
    
    ; 检查 PGE! 或 PPP! 标头
    cmp word [0], 0x4750           ; "PG"
    je .check_pge
    cmp word [0], 0x5050           ; "PP"
    jne .invalid_format_pop
    cmp word [2], 0x2150           ; "P!"
    jne .invalid_format_pop
    jmp .valid_header
    
.check_pge:
    cmp word [2], 0x2145           ; "E!"
    jne .invalid_format_pop
    
.valid_header:
    mov bp, [8]                    ; 初始 SP (从文件头提取)
    pop ds
    
    inc dx                         

    cli
    mov [si + 3], dx                ; 保存任务段基址
    mov ax, ss
    mov cx, sp
    mov ss, dx
    mov sp, bp                      ; 设置程序的栈顶

    pushf
    pop bx
    or bx, 0x0200                   ; 启用 IF
    push bx                         ; FLAGS
    push dx                         ; CS
    push word 0x0000                ; IP 从 0x0000 起始执行
    pusha                           
    push dx                         ; DS
    push dx                         ; ES

    mov [si + 1], sp                
    mov byte [si + 0], 1            

    mov ss, ax
    mov sp, cx
    sti

    cmp byte [cs:is_bg_task], 1
    je .release_lock

.wait_for_child:
    cmp byte [si + 0], 0
    je .child_exited
    hlt
    jmp .wait_for_child
.child_exited:
    jmp .release_lock

.invalid_format_pop:
    pop ds
    mov ax, dx
    call kfree                     
.invalid_format_no_free:
    mov si, msg_bad_format
    call print_string
    jmp .release_lock

.not_found:
    mov si, msg_unknown
    call print_string
    jmp .release_lock
    
.out_of_memory:
    mov si, msg_oom
    call print_string

.release_lock:
    xor ax, ax
    mov gs, ax
    mov byte [gs:KERNEL_LOCK], 0

.done:
    pop es
    pop ds
    popa
    ret

uppercase_cmd:
    pusha
    mov si, cmd_buffer
.up:
    lodsb
    or al, al
    jz .ok
    cmp al, 'a'
    jb .up
    cmp al, 'z'
    ja .up
    sub al, 32                      
    mov [si-1], al
    jmp .up
.ok:
    popa
    ret

print_bcd_cli:
    push ax
    push bx
    mov bl, al
    shr al, 4                       
    add al, '0'
    call print_char
    mov al, bl
    and al, 0x0F                    
    add al, '0'
    call print_char
    pop bx
    pop ax
    ret

print_uint16:
    pusha
    mov cx, 0
    mov bx, 10
.loop1:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .loop1
.loop2:
    pop ax
    add al, '0'
    call print_char
    loop .loop2
    popa
    ret

msg_ready      db 13, 10, "PPP OS 1.3.B Ready.", 0
msg_unknown    db 13, 10, "Bad command or file name", 0
msg_locked_err db 13, 10, "LOCKDOWN: Nested loading forbidden!", 0
msg_exit       db 13, 10, "Exiting...", 0
msg_no_exit    db 13, 10, "Primary shell cannot exit!", 0
msg_sys_dir    db 13, 10, " Directory of current folder:", 13, 10, 0
msg_item_pre   db "  - ", 0
msg_dir_tag    db "  <DIR>", 0
msg_no_files   db "  File Not Found", 13, 10, 0
msg_oom        db 13, 10, "System Error: Out of Memory!", 0
msg_time       db 13, 10, "Current time is ", 0
msg_rebooting  db 13, 10, "System is rebooting...", 13, 10, 0
msg_shutdown   db 13, 10, "System is shutting down... Good bye!", 13, 10, 0
msg_err        db 13, 10, "Directory Operation Failed!", 13, 10, 0
msg_md_ok      db 13, 10, "Directory Created successfully.", 13, 10, 0
msg_pause_dir  db "--- Press any key to continue ---", 0
msg_bad_format db 13, 10, "Execution Error: Invalid Executable Format!", 13, 10, 0
msg_cd_err     db 13, 10, "Path not found or not a directory.", 13, 10, 0
msg_drv_err    db 13, 10, "Failed to load driver module!", 0
msg_mount_err  db 13, 10, "Drive not ready or invalid partition!", 0
msg_drv_ok     db 13, 10, "Driver loaded successfully.", 0
msg_space      db "  ", 0
msg_kb         db " KB", 0

str_exit       db "EXIT", 0
str_dir        db "DIR", 0
str_time       db "TIME", 0
str_reboot     db "REBOOT", 0
str_shutdown   db "SHUTDOWN", 0
str_cd         db "CD ", 0
str_md         db "MD ", 0
str_insmod     db "INSMOD ", 0

sys_boot_key   db "SYS             "
msg_autorun    db 13, 10, "[System Autorun] Starting: ", 0

sys_drv_key    db "DRV0            "
msg_auto_drv   db 13, 10, "[System] Loading Driver: ", 0
msg_auto_ok    db " -> OK", 0
msg_auto_fail  db " -> FAILED!", 0

is_bg_task     db 0                

fat_filename   times 11 db ' '     
cmd_buffer     times 64 db 0

sys_path       db "\", 0
               times 64 db 0