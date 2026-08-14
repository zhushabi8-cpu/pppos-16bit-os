; PPP OS FAT12/FAT16/MBR 文件系统

cwd_cluster        dw 0     ; 当前目录簇号（0=根目录）
vol_start_lba      dw 0     ; 逻辑分区的绝对 LBA 起点（由 MBR 解析得出）

fs_type            db 12    ; 文件系统类型 (12 或 16)
fat_start_lba      dw 1     ; FAT 表起始 LBA
fat_sectors        dw 9     ; 单个 FAT 表占据的扇区数
root_start_lba     dw 19    ; 根目录起始 LBA
root_sectors       dw 14    ; 根目录占据的扇区数
data_start_lba     dw 33    ; 数据区起始 LBA
cluster_lba_offset dw 31    ; 簇号到 LBA 的快速换算偏差

; 挂载驱动器并探测文件系统 (支持 MBR 穿透)
fat_init_drive:
    pusha
    push es
    
    mov ax, cs
    mov es, ax
    
    ; 1. 读取绝对 LBA 0 (可能是 MBR，也可能是软盘 BPB)
    mov bx, fat_bpb_buffer
    mov ax, 0
    mov cx, 1
    call disk_read_lba
    jc .init_err

    ; 2. 检查是否为 MBR
    mov al, [es:fat_bpb_buffer]
    cmp al, 0xEB
    je .no_mbr
    cmp al, 0xE9
    je .no_mbr
    
    ; 存在 MBR，解析对应分区表 (0x1BE)
    mov al, [cs:current_part]     ; 0~3 (C, D, E, F)
    xor ah, ah
    shl ax, 4                     ; 每个表项占 16 字节
    add ax, 0x1BE                 
    mov bx, ax
    
    ; 检查分区类型是否有效
    cmp byte [es:fat_bpb_buffer + bx + 4], 0
    je .init_err                  

    ; 提取该分区起始 LBA
    mov ax, [es:fat_bpb_buffer + bx + 8]
    mov [cs:vol_start_lba], ax
    
    ; 读取该分区真正的 VBR 引导扇区 (BPB)
    mov bx, fat_bpb_buffer
    mov cx, 1
    call disk_read_lba
    jc .init_err
    jmp .parse_bpb

.no_mbr:
    mov word [cs:vol_start_lba], 0  

.parse_bpb:
    ; 1. 解析保留扇区 -> FAT 起始 LBA
    mov ax, [es:fat_bpb_buffer + 14]
    add ax, [cs:vol_start_lba]       
    mov [cs:fat_start_lba], ax

    ; 2. 解析每 FAT 扇区数
    mov ax, [es:fat_bpb_buffer + 22]
    mov [cs:fat_sectors], ax

    ; 3. 计算根目录起始 LBA
    xor cx, cx
    mov cl, [es:fat_bpb_buffer + 16]                 
    mul cx
    add ax, [cs:fat_start_lba]
    mov [cs:root_start_lba], ax

    ; 4. 计算根目录大小 (扇区数)
    mov ax, [es:fat_bpb_buffer + 17]
    mov cx, 32
    mul cx
    add ax, 511
    shr ax, 9
    mov [cs:root_sectors], ax

    ; 5. 计算数据区起始 LBA 与快速换算偏移
    add ax, [cs:root_start_lba]
    mov [cs:data_start_lba], ax
    sub ax, 2
    mov [cs:cluster_lba_offset], ax 

    ; 6. 判定 FAT12 / FAT16
    mov ax, [es:fat_bpb_buffer + 19]                 
    or ax, ax
    jnz .calc_clusters
    mov byte [cs:fs_type], 16
    jmp .init_ok

.calc_clusters:
    sub ax, [cs:data_start_lba]
    add ax, [cs:vol_start_lba]
    xor ch, ch
    mov cl, [es:fat_bpb_buffer + 13]                 
    xor dx, dx
    div cx                           
    
    cmp ax, 4085                     
    jb .is_fat12
    mov byte [cs:fs_type], 16
    jmp .init_ok
.is_fat12:
    mov byte [cs:fs_type], 12
.init_ok:
    pop es
    popa
    clc
    ret
.init_err:
    pop es
    popa
    stc
    ret

fat_read_entry:
    push bx
    push cx
    push dx
    push es

    cmp byte [cs:fs_type], 16
    je .read_fat16

.read_fat12:
    push ax
    mov bx, ax
    shr bx, 1
    add bx, ax
    mov dx, bx
    shr dx, 9                   
    and bx, 511                 
    
    mov ax, [cs:fat_start_lba]
    add ax, dx
    mov cx, 2                   
    mov dx, [cs:seg_fat_buf]
    mov es, dx
    push bx
    xor bx, bx
    call disk_read_lba
    pop bx
    
    mov ax, [es:bx]             
    pop dx                      
    test dx, 1
    jnz .r12_odd
.r12_even:
    and ax, 0x0FFF
    jmp .r_done
.r12_odd:
    shr ax, 4
    jmp .r_done

.read_fat16:
    mov bx, ax
    shl bx, 1
    mov dx, bx
    shr dx, 9
    and bx, 511
    
    mov ax, [cs:fat_start_lba]
    add ax, dx
    mov cx, 1                   
    mov dx, [cs:seg_fat_buf]
    mov es, dx
    push bx
    xor bx, bx
    call disk_read_lba
    pop bx
    mov ax, [es:bx]

.r_done:
    pop es
    pop dx
    pop cx
    pop bx
    ret

fat_write_entry:
    pusha
    push es

    cmp byte [cs:fs_type], 16
    je .w16

.w12:
    push ax                     

    mov bx, ax
    shr bx, 1
    add bx, ax
    mov cx, bx
    shr cx, 9                   
    and bx, 511                 
    
    mov ax, [cs:fat_start_lba]
    add ax, cx                  
    push ax                     
    
    mov di, [cs:seg_fat_buf]
    mov es, di
    push bx                     
    mov cx, 2
    xor bx, bx
    call disk_read_lba
    pop bx                      
    
    mov ax, [es:bx]
    
    mov bp, sp
    mov di, [bp+2]              ; DI = 原始簇号
    
    test di, 1
    jnz .w12_odd
.w12_even:
    and ax, 0xF000
    and dx, 0x0FFF
    or ax, dx
    jmp .w12_do_write
.w12_odd:
    and ax, 0x000F
    shl dx, 4
    or ax, dx
.w12_do_write:
    mov [es:bx], ax
    
    pop ax                      ; 弹出绝对 LBA
    mov cx, 2
    xor bx, bx
    call disk_write_lba
    add ax, [cs:fat_sectors]
    call disk_write_lba
    
    pop ax                      ; 弹出原始簇号
    jmp .w_done

.w16:
    mov bx, ax
    shl bx, 1
    mov cx, bx
    shr cx, 9
    and bx, 511
    
    mov ax, [cs:fat_start_lba]
    add ax, cx
    push ax
    
    mov di, [cs:seg_fat_buf]
    mov es, di
    push bx
    mov cx, 1
    xor bx, bx
    call disk_read_lba
    pop bx
    
    mov [es:bx], dx
    
    pop ax
    mov cx, 1
    xor bx, bx
    call disk_write_lba
    add ax, [cs:fat_sectors]
    call disk_write_lba

.w_done:
    pop es
    popa
    ret

; 查找文件/目录
fat12_find_file:
    push bx
    push es
    cld

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .search_subdir

.search_root:
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    mov bx, [cs:seg_dir_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov cx, [cs:root_sectors]
    shl cx, 4                       
    jmp .do_search

.search_subdir:
    push ax
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    mov bx, [cs:seg_dir_buf]
    mov es, bx
    xor bx, bx
    call disk_read_lba
    mov cx, 16

.do_search:
    xor bx, bx
.search_loop:
    mov al, [es:bx]
    cmp al, 0x00
    je .check_next_cluster
    cmp al, 0xE5
    je .next_entry
    
    mov dl, [es:bx+11]
    test dl, 0x08
    jnz .next_entry

    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb
    pop di
    pop si
    pop cx
    je .found
.next_entry:
    add bx, 32
    loop .search_loop

.check_next_cluster:
    cmp word [cs:cwd_cluster], 0
    je .not_found
    pop ax
    call fat_read_entry
    
    cmp byte [cs:fs_type], 16
    je .chk_eof_16
.chk_eof_12:
    cmp ax, 0x0FF8
    jae .not_found
    jmp .sub_continue
.chk_eof_16:
    cmp ax, 0xFFF8
    jae .not_found
.sub_continue:
    or ax, ax
    jz .not_found
    jmp .search_subdir

.not_found:
    pop es
    pop bx
    stc
    ret

.found:
    cmp word [cs:cwd_cluster], 0
    je .get_info
    pop dx
.get_info:
    mov ax, [es:bx + 26]
    mov cx, [es:bx + 28]
    mov dx, [es:bx + 30]
    push dx
    mov dl, [es:bx + 11]
    mov [cs:.tmp_attr], dl
    pop dx
    
    pop es
    pop bx
    mov bl, [cs:.tmp_attr]
    clc
    ret
.tmp_attr db 0

; 切换工作目录
fat12_change_dir:
    pusha
    call fat12_find_file
    jc .cd_fail
    test bl, 0x10
    jz .cd_fail
    mov [cs:cwd_cluster], ax
    popa
    clc
    ret
.cd_fail:
    popa
    stc
    ret

; 写入文件
fat12_write_file:
    pusha
    cld
    mov [cs:.data_ptr_off], di
    mov [cs:.data_ptr_seg], es
    mov [cs:.file_size], cx
    
    call fat12_delete_file

    mov ax, [cs:.file_size]
    add ax, 511
    shr ax, 9
    or ax, ax
    jnz .save_sec
    inc ax
.save_sec:
    mov [cs:.sectors_left], ax

    mov dx, 2
.scan_fat:
    mov bx, 4080
    cmp byte [cs:fs_type], 16
    jne .chk_limit
    mov bx, 65520
.chk_limit:
    cmp dx, bx
    jae .disk_full

    mov cx, [cs:.sectors_left]
    mov di, dx
.check_seq:
    mov ax, di
    call fat_read_entry
    or ax, ax
    jnz .seq_broken
    inc di
    loop .check_seq
    jmp .found_cluster
.seq_broken:
    inc dx
    jmp .scan_fat

.found_cluster:
    mov [cs:.new_cluster], dx
    mov cx, [cs:.sectors_left]
    mov di, dx
    
.link_loop:
    push cx
    cmp cx, 1
    je .write_eof
    mov dx, di
    inc dx
    jmp .do_fat_write
.write_eof:
    mov dx, 0x0FFF
    cmp byte [cs:fs_type], 16
    jne .do_fat_write
    mov dx, 0xFFFF
.do_fat_write:
    mov ax, di
    call fat_write_entry
    pop cx
    dec cx
    jz .link_done
    inc di
    jmp .link_loop

.link_done:
    push es
    mov ax, [cs:seg_dir_buf]
    mov es, ax
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_read_sub
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    mov dx, cx
    shl dx, 4
    jmp .w_do_read
.w_read_sub:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    mov dx, 16
.w_do_read:
    xor bx, bx
    call disk_read_lba

    xor bx, bx
    mov cx, dx
.scan_dir:
    mov al, [es:bx]
    cmp al, 0x00
    je .found_dir_entry
    cmp al, 0xE5
    je .found_dir_entry
    add bx, 32
    loop .scan_dir
    pop es
    jmp .disk_full

.found_dir_entry:
    push di
    push si
    push cx
    mov di, bx
    mov cx, 11
    rep movsb
    mov cx, 21
    xor al, al
    rep stosb
    mov byte [es:bx+11], 0x20
    mov ax, [cs:.new_cluster]
    mov [es:bx+26], ax
    mov ax, [cs:.file_size]
    mov [es:bx+28], ax
    mov word [es:bx+30], 0
    pop cx
    pop si
    pop di

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_write_sub
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    jmp .w_do_write
.w_write_sub:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
.w_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop es

    mov ax, [cs:.sectors_left]
    mov cx, ax
    mov ax, [cs:.new_cluster]
    add ax, [cs:cluster_lba_offset]
    mov es, [cs:.data_ptr_seg]
    mov bx, [cs:.data_ptr_off]
    call disk_write_lba

    popa
    clc
    ret
.disk_full:
    popa
    stc
    ret
.new_cluster  dw 0
.file_size    dw 0
.data_ptr_off dw 0
.data_ptr_seg dw 0
.sectors_left dw 0

; 删除文件/释放簇
fat12_delete_file:
    pusha
    cld
    push es
    mov ax, [cs:seg_dir_buf]
    mov es, ax
    
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .d_read_sub
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    mov dx, cx
    shl dx, 4
    jmp .d_do_read
.d_read_sub:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    mov dx, 16
.d_do_read:
    xor bx, bx
    call disk_read_lba

    mov cx, dx
    xor bx, bx
.del_search:
    mov al, [es:bx]
    cmp al, 0
    je .del_fail
    cmp al, 0xE5
    je .del_next
    mov al, [es:bx+11]
    test al, 0x08
    jnz .del_next

    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb
    pop di
    pop si
    pop cx
    je .del_found
.del_next:
    add bx, 32
    loop .del_search
.del_fail:
    pop es
    popa
    stc
    ret

.del_found:
    mov byte [es:bx], 0xE5
    mov dx, [es:bx+26]
    push dx
    
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .d_write_sub
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    jmp .d_do_write
.d_write_sub:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
.d_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop dx
    cmp dx, 2
    jb .del_done

.free_loop:
    mov ax, dx
    call fat_read_entry
    push ax
    mov ax, dx
    mov dx, 0               
    call fat_write_entry
    pop dx                  
    
    cmp byte [cs:fs_type], 16
    je .chk_free_16
.chk_free_12:
    cmp dx, 0x0FF8
    jae .del_done
    jmp .free_cont
.chk_free_16:
    cmp dx, 0xFFF8
    jae .del_done
.free_cont:
    or dx, dx
    jz .del_done
    jmp .free_loop

.del_done:
    pop es
    popa
    clc
    ret

; 重命名文件
fat12_rename_file:
    pusha
    cld
    push es
    mov ax, [cs:seg_dir_buf]
    mov es, ax
    
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .r_read_sub
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    mov dx, cx
    shl dx, 4
    jmp .r_do_read
.r_read_sub:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    mov dx, 16
.r_do_read:
    xor bx, bx
    call disk_read_lba

    mov cx, dx
    xor bx, bx
.ren_search:
    mov al, [es:bx]
    cmp al, 0
    je .ren_fail
    cmp al, 0xE5
    je .ren_next
    mov al, [es:bx+11]
    test al, 0x08
    jnz .ren_next

    push cx
    push si
    push di
    mov di, bx
    mov cx, 11
    repe cmpsb
    pop di
    pop si
    pop cx
    je .ren_found
.ren_next:
    add bx, 32
    loop .ren_search
.ren_fail:
    pop es
    popa
    stc
    ret

.ren_found:
    push cx
    push si
    push di
    mov si, di                      
    mov di, bx                      
    mov cx, 11
    rep movsb
    pop di
    pop si
    pop cx

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .r_write_sub
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    jmp .r_do_write
.r_write_sub:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
.r_do_write:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop es
    popa
    clc
    ret

; 创建目录
fat12_make_dir:
    pusha
    cld

    mov dx, 2
.scan_fat_md:
    mov bx, 4080
    cmp byte [cs:fs_type], 16
    jne .chk_limit_md
    mov bx, 65520
.chk_limit_md:
    cmp dx, bx
    jae .disk_full_md

    mov ax, dx
    call fat_read_entry
    or ax, ax
    jz .found_cluster_md
    inc dx
    jmp .scan_fat_md

.found_cluster_md:
    mov [cs:.new_cluster_md], dx

    mov ax, dx
    mov dx, 0x0FFF
    cmp byte [cs:fs_type], 16
    jne .do_mark_eof
    mov dx, 0xFFFF
.do_mark_eof:
    call fat_write_entry

    push es
    mov ax, [cs:seg_gfx_buf]
    mov es, ax
    mov cx, 256
    xor di, di
    xor ax, ax
    rep stosw

    mov di, 0
    mov al, '.'
    mov [es:di], al
    mov al, ' '
    mov cx, 10
    inc di
    rep stosb
    mov byte [es:11], 0x10
    mov ax, [cs:.new_cluster_md]
    mov [es:26], ax

    mov di, 32
    mov al, '.'
    mov [es:di], al
    mov [es:di+1], al
    mov al, ' '
    mov cx, 9
    add di, 2
    rep stosb
    mov byte [es:32+11], 0x10
    mov ax, [cs:cwd_cluster]
    mov [es:32+26], ax

    mov ax, [cs:.new_cluster_md]
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    xor bx, bx
    call disk_write_lba
    pop es

    push es
    mov ax, [cs:seg_dir_buf]
    mov es, ax
    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_read_sub_md
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    mov dx, cx
    shl dx, 4
    jmp .w_do_read_md
.w_read_sub_md:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
    mov dx, 16
.w_do_read_md:
    xor bx, bx
    call disk_read_lba

    mov cx, dx
    xor bx, bx
.scan_dir_md:
    mov al, [es:bx]
    cmp al, 0
    je .found_dir_entry_md
    cmp al, 0xE5
    je .found_dir_entry_md
    add bx, 32
    loop .scan_dir_md
    pop es
    jmp .disk_full_md

.found_dir_entry_md:
    push di
    push si
    push cx
    mov di, bx
    mov cx, 11
    rep movsb                      
    mov cx, 21
    xor al, al
    rep stosb
    mov byte [es:bx+11], 0x10      
    mov ax, [cs:.new_cluster_md]
    mov [es:bx+26], ax
    mov word [es:bx+28], 0
    mov word [es:bx+30], 0
    pop cx
    pop si
    pop di

    mov ax, [cs:cwd_cluster]
    or ax, ax
    jnz .w_write_sub_md
    mov ax, [cs:root_start_lba]
    mov cx, [cs:root_sectors]
    jmp .w_do_write_md
.w_write_sub_md:
    add ax, [cs:cluster_lba_offset]
    mov cx, 1
.w_do_write_md:
    push bx
    xor bx, bx
    call disk_write_lba
    pop bx
    pop es

    popa
    clc
    ret

.disk_full_md:
    popa
    stc
    ret

.new_cluster_md dw 0
fat_bpb_buffer times 512 db 0