; ================================================================
; PPP OS - DOS 兼容子系统 (comcall.inc)
; ================================================================

; ----------------------------------------------------------------
; 初始化 DOS 兼容层
; ----------------------------------------------------------------
setup_dos_compat:
    cli
    push    es
    xor     ax, ax
    mov     es, ax
    mov     word [es:0x20*4], isr_dos_exit
    mov     word [es:0x20*4+2], cs
    mov     word [es:0x21*4], dos_api_translator
    mov     word [es:0x21*4+2], cs
    pop     es
    sti
    ret

; ----------------------------------------------------------------
; DOS 兼容退出处理 (INT 0x20)
; ----------------------------------------------------------------
isr_dos_exit:
    mov     ah, 0x04
    jmp     sys_exit_task

; ----------------------------------------------------------------
; DOS API 转译总线 (INT 0x21)
; ----------------------------------------------------------------
dos_api_translator:
    pusha

    cmp     ah, 0x01            ; DOS: 有回显按键
    je      .dos_read_key
    cmp     ah, 0x02            ; 打印单字符
    je      .dos_print_char
    cmp     ah, 0x06            ; DOS: 直接控制台 I/O
    je      .dos_direct_io
    cmp     ah, 0x07            ; DOS: 无回显按键
    je      .dos_read_key
    cmp     ah, 0x08            ; DOS: 无回显按键
    je      .dos_read_key
    cmp     ah, 0x09            ; 打印字符串
    je      .dos_print_string
    cmp     ah, 0x0B            ; DOS: 非阻塞键盘检测 (kbhit)
    je      .dos_kbhit
    cmp     ah, 0x0C            ; DOS: 清空键盘缓冲区并读取
    je      .dos_clear_kb
    cmp     ah, 0x0E            ; DOS: 设置当前驱动器
    je      .dos_set_drive
    cmp     ah, 0x19            ; DOS: 获取当前驱动器
    je      .dos_get_drive
    cmp     ah, 0x1A            ; DOS: 设置 DTA (磁盘传输区)
    je      .dos_set_dta
    cmp     ah, 0x25            ; DOS: 设置中断向量 (保护拦截)
    je      .dos_set_vect
    cmp     ah, 0x2A            ; DOS: 获取系统日期
    je      .dos_get_date
    cmp     ah, 0x2C            ; DOS: 获取系统时间
    je      .dos_get_time
    cmp     ah, 0x30            ; DOS: 获取 DOS 版本 (动态读取)
    je      .dos_get_version
    cmp     ah, 0x33            ; DOS: Ctrl-Break 状态检查
    je      .dos_ctrl_break
    cmp     ah, 0x35            ; DOS: 获取中断向量 (保护拦截)
    je      .dos_get_vect
    cmp     ah, 0x36            ; DOS: 获取磁盘空闲空间
    je      .dos_disk_free
    cmp     ah, 0x3C            ; 创建文件 (接入VFS)
    je      .dos_create_file
    cmp     ah, 0x3D            ; 打开文件
    je      .dos_open_file
    cmp     ah, 0x3E            ; 关闭文件
    je      .dos_close_file
    cmp     ah, 0x3F            ; 读取文件 (适配 10 字节 VFS)
    je      .dos_read_file
    cmp     ah, 0x40            ; 写入文件
    je      .dos_write_file
    cmp     ah, 0x41            ; DOS: 删除文件
    je      .dos_delete_file
    cmp     ah, 0x42            ; DOS: 移动文件指针 (Lseek, 适配 10 字节 VFS)
    je      .dos_lseek
    cmp     ah, 0x43            ; DOS: 获取/设置文件属性
    je      .dos_file_attr
    cmp     ah, 0x48            ; DOS: 分配内存 (拦截并拒绝)
    je      .dos_alloc_mem
    cmp     ah, 0x49            ; DOS: 释放内存 (假装成功)
    je      .dos_free_mem
    cmp     ah, 0x4A            ; 调整内存块大小
    je      .dos_resize_mem
    cmp     ah, 0x4C            ; 带返回码退出
    je      .dos_exit_4C
    
    cmp     ah, 0xFF            ; 动态调节模拟版本
    je      .dos_set_sim_ver
    
    jmp     .unsupported_api


; ---------- 06h: 直接控制台 I/O ----------
.dos_direct_io:
    cmp     dl, 0xFF
    je      .dio_read
.dio_write:
    mov     al, dl          
    mov     ah, 0x0E
    mov     bx, 0x000F
    int     0x10
    jmp     .api_done_success
.dio_read:
    call    kb_check_key
    or      ax, ax
    jz      .dio_no_key
    mov     bp, sp
    mov     [bp + 14], al
    and     word [bp + 20], 0xFFBF 
    jmp     .api_done_success
.dio_no_key:
    mov     bp, sp
    or      word [bp + 20], 0x0040 
    jmp     .api_done_success

; ---------- 基础输入输出 ----------
.dos_print_char:
    mov     al, dl          
    mov     ah, 0x0E
    mov     bx, 0x000F
    int     0x10
    jmp     .api_done

.dos_print_string:
    mov     si, dx          
.dos_str_loop:
    lodsb               
    cmp     al, '$'         
    je      .api_done
    mov     ah, 0x0E
    mov     bx, 0x000F
    int     0x10
    jmp     .dos_str_loop

.dos_read_key:
    push    ax
    mov     ah, 0x01
    int     0x80
    pop     cx
    cmp     ch, 0x01
    jne     .save_key_to_al
    push    ax
    mov     ah, 0x0E
    mov     bx, 0x000F
    int     0x10
    pop     ax
.save_key_to_al:
    mov     bp, sp
    mov     [bp + 14], al
    jmp     .api_done

.dos_exit_4C:
    add     sp, 16
    mov     ah, 0x04
    jmp     sys_exit_task

; ---------- 0Bh: 非阻塞键盘检测 kbhit ----------
.dos_kbhit:
    mov     bx, [cs:kb_head]
    cmp     bx, [cs:kb_tail]
    jne     .kbhit_true
    mov     ax, 0x0000
    jmp     .api_done_success
.kbhit_true:
    mov     ax, 0x00FF
    jmp     .api_done_success

; ---------- 0Ch: 清空键盘缓冲区并读取 ----------
.dos_clear_kb:
    mov     bx, [cs:kb_head]
    mov     [cs:kb_tail], bx
    mov     ah, al
    cmp     ah, 0x01
    je      .dos_read_key
    cmp     ah, 0x07
    je      .dos_read_key
    cmp     ah, 0x08
    je      .dos_read_key
    cmp     ah, 0x06
    je      .dos_direct_io
    jmp     .api_done_success

; ---------- 0Eh: 设置当前驱动器 (DOS API) ----------
.dos_set_drive:
    ; DOS 传入 DL: 0=A:, 1=B:, 2=C:
    cmp dl, 0
    je .set_dos_a
    cmp dl, 1
    je .set_dos_a
    ; 默认为 C 盘
    mov byte [cs:current_drive], 0x80
    jmp .set_drive_done
.set_dos_a:
    mov byte [cs:current_drive], 0x00
.set_drive_done:
    mov word [cs:cwd_cluster], 0
    mov al, 3
    mov bp, sp
    mov [bp + 14], al
    jmp .api_done_success

; ---------- 19h: 获取当前驱动器 (DOS API) ----------
.dos_get_drive:
    mov al, [cs:current_drive]
    cmp al, 0x80
    je .is_dos_c
    mov al, 0                       ; 0 = A:
    jmp .get_drive_done
.is_dos_c:
    mov al, 2                       ; 2 = C:
.get_drive_done:
    mov bp, sp
    mov [bp + 14], al
    jmp .api_done_success

; ---------- 36h: 获取磁盘空闲空间 ----------
.dos_disk_free:
    mov     ax, 1
    mov     bx, 1000
    mov     cx, 512
    mov     dx, 2848
    mov     bp, sp
    mov     [bp + 14], ax
    mov     [bp + 8], bx
    mov     [bp + 12], cx
    mov     [bp + 10], dx
    jmp     .api_done_success

; ---------- 1Ah: 设置 DTA (磁盘传输区) ----------
.dos_set_dta:
    mov     [cs:dos_dta_seg], ds
    mov     [cs:dos_dta_off], dx
    jmp     .api_done_success

; ---------- 25h/35h: 中断向量保护 ----------
.dos_set_vect:
    jmp     .api_done_success

.dos_get_vect:
    mov     ax, cs
    mov     es, ax
    mov     bx, dummy_iret
    mov     bp, sp
    mov     [bp + 8], bx        
    jmp     .api_done_success

; ---------- 2Ah: 获取系统日期 ----------
.dos_get_date:
    push    ax
    mov     ah, 0x04
    int     0x1A
    
    push    dx                  
    mov     al, ch
    call    .bcd_to_bin
    mov     ch, 0
    mov     bx, 100
    mul     bx
    pop     dx                  
    
    push    ax               
    mov     al, cl
    call    .bcd_to_bin
    xor     ah, ah
    pop     bx
    add     ax, bx
    mov     cx, ax
    mov     al, dh
    call    .bcd_to_bin
    mov     dh, al
    mov     al, dl
    call    .bcd_to_bin
    mov     dl, al
    pop     ax
    mov     al, 0
    mov     bp, sp
    mov     [bp + 14], ax       
    mov     [bp + 12], cx       
    mov     [bp + 10], dx     
    jmp     .api_done_success

; ---------- 2Ch: 获取系统时间 ----------
.dos_get_time:
    push    ax
    mov     ah, 0x02
    int     0x1A                
    mov     al, ch
    call    .bcd_to_bin
    mov     ch, al
    mov     al, cl
    call    .bcd_to_bin
    mov     cl, al
    mov     al, dh
    call    .bcd_to_bin
    mov     dh, al
    mov     dl, 0               
    pop     ax
    mov     bp, sp
    mov     [bp + 12], cx       
    mov     [bp + 10], dx       
    jmp     .api_done

; ---------- 30h: 获取 DOS 版本 (动态读取) ----------
.dos_get_version:
    mov     al, [cs:dos_ver_major]      
    mov     ah, [cs:dos_ver_minor]      
    mov     bx, 0x00FF
    mov     cx, 0x0000
    mov     bp, sp
    mov     [bp + 8], bx        
    mov     [bp + 12], cx       
    jmp     .api_done_success

; ---------- 33h: Ctrl-Break 状态检查 ----------
.dos_ctrl_break:
    cmp     al, 0x00
    jne     .ctrl_break_done
    mov     dl, 0x00
    mov     bp, sp
    mov     [bp + 10], dx       
.ctrl_break_done:
    jmp     .api_done_success

; ---------- FFh: 动态调节模拟版本 ----------
.dos_set_sim_ver:
    mov     [cs:dos_ver_major], bh      
    mov     [cs:dos_ver_minor], bl      
    jmp     .api_done_success

; ---------- 3Ch: 创建文件 ----------
.dos_create_file:
    push    es
    push    cs
    pop     es
    mov     di, dos_file_name_buf
    push    cx
    mov     cx, 11
    mov     al, ' '
    rep     stosb
    pop     cx
    
    mov     si, dx
    mov     di, dos_file_name_buf
    mov     cx, 8
.c_name_loop:
    lodsb
    or      al, al
    jz      .c_name_done
    cmp     al, '.'
    je      .c_name_ext
    stosb
    loop    .c_name_loop
    jmp     .c_skip_to_ext
.c_skip_to_ext:
    lodsb
    or      al, al
    jz      .c_name_done
    cmp     al, '.'
    je      .c_name_ext
    jmp     .c_skip_to_ext
.c_name_ext:
    mov     di, dos_file_name_buf + 8
    mov     cx, 3
.c_ext_loop:
    lodsb
    or      al, al
    jz      .c_name_done
    stosb
    loop    .c_ext_loop
.c_name_done:
    pop     es
    
    push    ds
    push    cs
    pop     ds
    mov     si, dos_file_name_buf
    mov     cx, 0               
    call    fat12_write_file    
    pop     ds
    jc      .file_op_err        

    mov     si, dx    
    call    vfs_open
    jc      .file_op_err
    jmp     .api_done_success   

; ---------- 3Dh: 打开已有文件 ----------
.dos_open_file:
    mov     si, dx
    call    vfs_open
    jc      .file_op_err
    jmp     .api_done_success

; ---------- 3Eh: 关闭文件 ----------
.dos_close_file:
    call    vfs_close
    jc      .file_op_err        
    jmp     .api_done_success

; ---------- 3Fh: 读取文件 (适配 10 字节 VFS) ----------
.dos_read_file:
    cmp     bx, 2
    jb      .read_console

    push    dx
    push    ax
    mov     ax, 14
    mul     bx
    mov     si, fd_table
    add     si, ax
    pop     ax
    pop     dx
    
    cmp     byte [cs:si], 0
    je      .file_op_err

    mov     ax, [cs:si + 10]    ; FD_EXACT_SZ 低 16 位
    mov     dx, [cs:si + 12]    ; FD_EXACT_SZ 高 16 位
    sub     ax, [cs:si + 6]     ; 减去 FD_OFFSET 低 16 位
    sbb     dx, [cs:si + 8]     ; 减去 FD_OFFSET 高 16 位 (带借位)
    jc      .read_eof_zero      ; 如果结果为负 (偏移越界)，直接 EOF
    jnz     .len_ok             ; 如果高 16 位不为0 (剩余>=64KB)，无需截断 (CX 本身就 <= 64KB)
    cmp     cx, ax              ; 如果剩余不足 64KB，比较 CX 与剩余字节数
    jbe     .len_ok
    mov     cx, ax              ; 截断 CX 为实际剩余大小
.len_ok:

    ; 读取文件整扇区到内核缓存区 ([cs:seg_gfx_buf]:0000)
    push    es                  ; 保护 DOS 程序的原 ES
    pusha
    mov     ax, [cs:seg_gfx_buf]
    mov     es, ax
    xor     di, di
    mov     ax, [cs:si + 2]     ; FD_LBA
    mov     cx, [cs:si + 4]     ; FD_LENGTH (占用的扇区数)
    mov     bx, di
    call    disk_read_lba
    popa
    pop     es                  ; 完美恢复 DOS 程序的原 ES
    jc      .file_op_err

    ; 从内核缓存区复制数据到用户程序
    mov     ax, [cs:si + 6]     ; 当前 FD_OFFSET

    push    ds
    push    es
    push    cx
    push    si

    push    ds
    pop     es                  ; ES = DOS 程序的段
    mov     di, dx              ; DI = DOS 程序的缓冲偏移

    mov     dx, [cs:seg_gfx_buf]
    mov     ds, dx              ; DS = 内核缓存
    mov     si, ax              ; SI = 偏移量

    rep movsb                   ; 复制

    pop     si
    pop     cx
    pop     es
    pop     ds

    add     word [cs:si + 6], cx

    mov     ax, cx
    jmp     .api_done_success

.read_console:
    push    ds
    pop     es
    mov     di, dx
    call    vfs_read
    jc      .file_op_err
    mov     ax, 1
    jmp     .api_done_success

.read_eof_zero:
    xor     ax, ax
    jmp     .api_done_success

; ---------- 40h: 写入文件 ----------
.dos_write_file:
    cmp     bx, 1               
    je      .dos_write_con
    cmp     bx, 2               
    je      .dos_write_con

    mov     si, dx
    call    vfs_write
    jc      .file_op_err
    mov     ax, cx
    jmp     .api_done_success

.dos_write_con:
    mov     si, dx
    push    cx
    jcxz    .con_done
.con_loop:
    lodsb
    mov     ah, 0x0E
    push    bx
    mov     bx, 0x000F
    int     0x10
    pop     bx
    loop    .con_loop
.con_done:
    pop     ax
    jmp     .api_done_success

; ---------- 41h: 删除文件 ----------
.dos_delete_file:
    push    es
    push    cs
    pop     es
    mov     di, dos_file_name_buf
    push    cx
    mov     cx, 11
    mov     al, ' '
    rep     stosb
    pop     cx
    
    mov     si, dx
    mov     di, dos_file_name_buf
    mov     cx, 8
.d_name_loop:
    lodsb
    or      al, al
    jz      .d_name_done
    cmp     al, '.'
    je      .d_name_ext
    stosb
    loop    .d_name_loop
    jmp     .d_skip_to_ext
.d_skip_to_ext:
    lodsb
    or      al, al
    jz      .d_name_done
    cmp     al, '.'
    je      .d_name_ext
    jmp     .d_skip_to_ext
.d_name_ext:
    mov     di, dos_file_name_buf + 8
    mov     cx, 3
.d_ext_loop:
    lodsb
    or      al, al
    jz      .d_name_done
    stosb
    loop    .d_ext_loop
.d_name_done:
    pop     es
    
    push    ds
    push    cs
    pop     ds
    mov     si, dos_file_name_buf
    call    fat12_delete_file
    pop     ds
    jc      .file_op_err        
    jmp     .api_done_success

; ---------- 42h: 移动文件指针 (Lseek, 适配 10 字节 VFS) ----------
.dos_lseek:
    push    dx                  ; 保护偏移量低 16 位
    push    ax
    mov     ax, 14
    mul     bx
    mov     di, fd_table
    add     di, ax              
    pop     ax
    pop     dx                  ; 恢复偏移量低 16 位

    cmp     al, 0
    je      .seek_set
    cmp     al, 1
    je      .seek_cur
    cmp     al, 2
    je      .seek_end

.seek_set:
    mov     [cs:di + 6], dx     
    mov     ax, dx
    xor     dx, dx
    mov     bp, sp
    mov     [bp + 10], dx       ; 同步 DX 返回值到调用栈
    jmp     .api_done_success

.seek_cur:
    add     dx, [cs:di + 6]     
    mov     [cs:di + 6], dx
    mov     ax, dx
    xor     dx, dx
    mov     bp, sp
    mov     [bp + 10], dx       ; 同步 DX 返回值到调用栈
    jmp     .api_done_success

.seek_end:
    mov     ax, [cs:di + 10]     ; 获取精确的文件字节大小
    add     dx, ax              
    mov     [cs:di + 6], dx
    mov     ax, dx
    xor     dx, dx
    mov     bp, sp
    mov     [bp + 10], dx       ; 同步 DX 返回值到调用栈
    jmp     .api_done_success

; ---------- 43h: 获取/设置文件属性 ----------
.dos_file_attr:
    cmp     al, 0x00            
    jne     .attr_fail
    
    push    es
    push    cs
    pop     es
    mov     di, dos_file_name_buf
    push    cx
    mov     cx, 11
    mov     al, ' '
    rep     stosb
    pop     cx
    
    mov     si, dx
    mov     di, dos_file_name_buf
    mov     cx, 8
.a_name_loop:
    lodsb
    or      al, al
    jz      .a_name_done
    cmp     al, '.'
    je      .a_name_ext
    stosb
    loop    .a_name_loop
    jmp     .a_skip_to_ext
.a_skip_to_ext:
    lodsb
    or      al, al
    jz      .a_name_done
    cmp     al, '.'
    je      .a_name_ext
    jmp     .a_skip_to_ext
.a_name_ext:
    mov     di, dos_file_name_buf + 8
    mov     cx, 3
.a_ext_loop:
    lodsb
    or      al, al
    jz      .a_name_done
    stosb
    loop    .a_ext_loop
.a_name_done:
    pop     es

    push    ds
    push    cs
    pop     ds
    mov     si, dos_file_name_buf
    call    fat12_find_file
    pop     ds
    jc      .attr_fail          

    mov     cx, 0x0020          
    test    bl, 0x10
    jz      .attr_ok
    mov     cx, 0x0010          
.attr_ok:
    mov     bp, sp
    mov     [bp + 12], cx       
    jmp     .api_done_success
.attr_fail:
    mov     ax, 0x02            
    jmp     .api_done_fail

; ---------- 内存分配与管理拦截 ----------
.dos_alloc_mem:
    mov     ax, 0x0008          
    mov     bx, 0x0000          
    mov     bp, sp
    mov     [bp + 8], bx        
    jmp     .api_done_fail

.dos_free_mem:
    jmp     .api_done_success

.dos_resize_mem:
    jmp     .api_done_success

; --- 辅助函数 ---
.bcd_to_bin:
    push    bx
    mov     bl, al
    and     al, 0x0F            
    shr     bl, 4               
    mov     bh, 10
    xchg    al, bl              
    mul     bh                  
    add     al, bl              
    pop     bx
    ret

; ---------- 错误处理与返回 ----------
.file_op_err:
    mov     ax, 0x0002          ; 错误码: 02h (操作失败)

.api_done_fail:
    mov     bp, sp
    mov     [bp + 14], ax       
    or      word [bp + 20], 0x0001 ; 置 CF=1 (失败)
    popa
    iret

.api_done_success:
    mov     bp, sp
    mov     [bp + 14], ax       
    and     word [bp + 20], 0xFFFE ; 清 CF=0 (成功)
    popa
    iret

.unsupported_api:
    mov     ax, 0x0001          ; 拦截任何不支持的 API
    jmp     .api_done_fail

.api_done:
    popa                
    iret

; 静态分配区
dos_file_name_buf times 11 db ' '
dos_dta_seg       dw 0
dos_dta_off       dw 0x0080

; 内核默认不配置版本，由外壳载入
dos_ver_major     db 0
dos_ver_minor     db 0