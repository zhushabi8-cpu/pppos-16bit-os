; ================================================================
; PPP OS 虚拟文件系统抽象层 (VFS)
; ================================================================

%define MAX_FDS     16              
%define FD_SIZE     14              

%define FD_STATE    0               
%define FD_TYPE     1               
%define FD_LBA      2               
%define FD_LENGTH   4               
%define FD_OFFSET   6               
%define FD_EXACT_SZ 10              

fd_table times MAX_FDS * FD_SIZE db 0   

init_vfs:
    ret

vfs_write:
    pusha
    cmp bx, 1
    je .do_stdout
    cmp bx, 2
    jb .error
    cmp bx, MAX_FDS
    jae .error

    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    cmp byte [cs:di + FD_STATE], 0     
    je .error
    mov al, [cs:di + FD_TYPE]
    cmp al, 3                          
    je .do_disk_write
    jmp .error

.do_stdout:
    call print_string                  
    jmp .success

.do_disk_write:
    push es
    mov ax, [cs:di + FD_LBA]           
    mov cx, [cs:di + FD_LENGTH]        
    push ds
    pop es                             
    mov bx, si                         
    call disk_write_lba
    pop es
    jmp .success

.success:
    popa
    clc
    ret

.error:
    popa
    stc
    ret

vfs_read:
    cmp bx, 0
    je .do_stdin
    cmp bx, 2
    jb .error
    cmp bx, MAX_FDS
    jae .error

    push di
    push bx
    push ax
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    pop ax
    pop bx
    cmp byte [cs:di + FD_STATE], 0     
    je .error_pop
    mov cl, [cs:di + FD_TYPE]
    cmp cl, 3                          
    je .do_disk_read

.error_pop:
    pop di
    stc
    ret

.do_stdin:
    call get_char                      
    clc
    ret

.do_disk_read:
    mov ax, [cs:di + FD_LBA]           
    mov cx, [cs:di + FD_LENGTH]        
    pop di                             
    mov bx, di
    call disk_read_lba
    clc
    ret

.error:
    stc
    ret

vfs_open:
    pusha
    cld
    push ds
    push si

    lodsb
    cmp al, 0
    je .not_found_pop
    cmp al, ' '
    je .not_found_pop
    cmp al, 13
    je .not_found_pop
    dec si

    push cs
    pop es
    mov di, vfs_fat_name
    mov cx, 11
    mov al, ' '
    rep stosb
    pop si
    pop ds
    push cs
    pop es
    mov di, vfs_fat_name

.copy_name:
    lodsb
    or al, al
    jz .done_copy
    cmp al, '.'
    je .copy_ext
    stosb
    jmp .copy_name

.copy_ext:
    mov di, vfs_fat_name + 8            
    jmp .copy_name

.done_copy:
    push cs
    pop ds
    mov si, vfs_fat_name
    call fat12_find_file                
    jc .not_found

    mov [cs:.tmp_exact_sz_l], cx          
    mov [cs:.tmp_exact_sz_h], dx          

    add ax, [cs:cluster_lba_offset]
    mov [cs:.tmp_lba], ax

    mov ax, cx
    add ax, 511
    mov bx, dx
    adc bx, 0
    shl bx, 7
    shr ax, 9
    or ax, bx
    mov [cs:.tmp_sec], ax

    mov bx, 2
.find_fd:
    cmp bx, MAX_FDS
    jae .not_found
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    cmp byte [cs:di + FD_STATE], 0
    je .found_fd
    inc bx
    jmp .find_fd

.found_fd:
    mov byte [cs:di + FD_STATE], 1
    mov byte [cs:di + FD_TYPE], 3       
    mov ax, [cs:.tmp_lba]
    mov [cs:di + FD_LBA], ax
    mov ax, [cs:.tmp_sec]
    mov [cs:di + FD_LENGTH], ax
    mov word [cs:di + FD_OFFSET], 0
    mov word [cs:di + FD_OFFSET + 2], 0
    mov ax, [cs:.tmp_exact_sz_l]
    mov [cs:di + FD_EXACT_SZ], ax       
    mov ax, [cs:.tmp_exact_sz_h]
    mov [cs:di + FD_EXACT_SZ + 2], ax   

    mov [cs:.tmp_fd], bx

    popa
    mov ax, [cs:.tmp_fd]
    clc
    ret

.not_found_pop:
    pop si
    pop ds
.not_found:
    popa
    stc
    ret

.tmp_lba dw 0
.tmp_sec dw 0
.tmp_fd  dw 0
.tmp_exact_sz_l dw 0
.tmp_exact_sz_h dw 0
vfs_fat_name times 11 db ' '

vfs_close:
    pusha
    cmp bx, 2
    jb .done
    cmp bx, MAX_FDS
    jae .done
    mov ax, FD_SIZE
    mul bx
    mov di, fd_table
    add di, ax
    mov byte [cs:di + FD_STATE], 0      
.done:
    popa
    ret

vfs_read_dir:
    pusha
    cld
    push es

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .read_subdir

    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    mov bx, [cs:seg_dir_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov dx, [cs:root_sectors]
    shl dx, 4                          
    jmp .scan_start

.read_subdir:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    mov bx, [cs:seg_dir_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov dx, 16                         

.scan_start:
    pop es                             
    push ds
    mov ax, [cs:seg_dir_buf]
    mov ds, ax                         
    xor si, si

    xor cx, cx
    mov [cs:vfs_tmp_count], cx

.scan_loop:
    mov al, [si]
    or al, al
    jz .done

    cmp al, 0xE5                        
    je .next_entry

    mov bl, [si + 11]                   
    test bl, 0x08                       
    jnz .next_entry

    push si
    push cx
    mov cx, 11
    rep movsb                           
    pop cx
    pop si

    mov al, bl
    stosb

    mov ax, [si + 28]
    stosw
    mov ax, [si + 30]
    stosw

    mov ax, [si + 26]
    stosw

    xor ax, ax
    stosw

    inc word [cs:vfs_tmp_count]

.next_entry:
    add si, 32                          
    dec dx
    jnz .scan_loop

.done:
    pop ds
    popa
    mov cx, [cs:vfs_tmp_count]
    clc
    ret

vfs_tmp_count dw 0