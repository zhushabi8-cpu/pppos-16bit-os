; ================================================================
; PPP OS - DOS 兼容子系统 (comcall.inc)
; 适配 10 字节新版 vfs.inc (FD_SIZE = 10)
; ================================================================

; ----------------------------------------------------------------
; 初始化 DOS 兼容层
; 设置 INT 0x20（退出）和 INT 0x21（DOS API）的中断向量
; ----------------------------------------------------------------
setup_dos_compat:
    cli
    push    es
    xor     ax, ax
    mov     es, ax
    mov     word [es:0x20*4], isr_dos_exit      ; INT 0x20 入口
    mov     word [es:0x20*4+2], cs
    mov     word [es:0x21*4], dos_api_translator ; INT 0x21 入口
    mov     word [es:0x21*4+2], cs
    pop     es
    sti
    ret

; ----------------------------------------------------------------
; DOS 兼容退出处理 (INT 0x20)
; 转换为系统调用退出 (AH=0x04)
; ----------------------------------------------------------------
isr_dos_exit:
    mov     ah, 0x04
    jmp     syscall_handler.h_exit

; ----------------------------------------------------------------
; DOS API 转译总线 (INT 0x21)
; 根据 AH 分发到各子功能，未实现的返回错误
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
; DL=0xFF 时读取按键（无阻塞），否则输出 DL 中的字符
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
    and     word [bp + 20], 0xFFBF  ; 清 ZF (表示有键)
    jmp     .api_done_success
.dio_no_key:
    mov     bp, sp
    or      word [bp + 20], 0x0040  ; 置 ZF (表示无键)
    jmp     .api_done_success

; ---------- 基础输入输出 ----------
; 02h: 输出 DL 中的字符到屏幕
.dos_print_char:
    mov     al, dl          
    mov     ah, 0x0E
    mov     bx, 0x000F
    int     0x10
    jmp     .api_done

; 09h: 输出 DS:DX 指向的 '$' 结尾字符串
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

; 01h/07h/08h: 读取一个按键（带或不带回显）
.dos_read_key:
    push    ax
    mov     ah, 0x01
    int     0x80            ; 调用系统键盘读取 (返回 AL=键码, CH=1表示带回显)
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

; 4Ch: 带返回码退出 (AL=返回码)
.dos_exit_4C:
    add     sp, 16          ; 调整堆栈以跳过 pusha
    mov     ah, 0x04
    jmp     syscall_handler.h_exit

; ---------- 0Bh: 非阻塞键盘检测 (kbhit) ----------
; 检查键盘缓冲区是否有未读取的键，有则 AX=0x00FF，否则 AX=0x0000
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
; 清空缓冲区，若 AL 指定了读取功能号（01/06/07/08），则执行对应的读取
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

; ---------- 0Eh/19h/36h: 驱动器与磁盘环境伪装 ----------
; 返回固定值以模拟 DOS 环境
.dos_set_drive:
    mov     al, 0x02        ; 总是返回成功，设置驱动器号为 2
    mov     bp, sp
    mov     [bp + 14], al
    jmp     .api_done_success

.dos_get_drive:
    mov     ax, 0x0000      ; 返回当前驱动器 A:
    mov     bp, sp
    mov     [bp + 14], al
    jmp     .api_done_success

.dos_disk_free:
    ; 返回固定空闲空间数据 (1 簇，每簇 1000 扇区，每扇区 512 字节，总共 2848 簇)
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
; 保存用户指定的段地址和偏移
.dos_set_dta:
    mov     [cs:dos_dta_seg], ds
    mov     [cs:dos_dta_off], dx
    jmp     .api_done_success

; ---------- 25h/35h: 中断向量保护 ----------
; 设置向量（25h）忽略，获取向量（35h）返回 dummy_iret 的地址
.dos_set_vect:
    jmp     .api_done_success

.dos_get_vect:
    mov     ax, cs
    mov     es, ax
    mov     bx, dummy_iret
    mov     bp, sp
    mov     [bp + 8], bx        ; ES:BX 返回
    jmp     .api_done_success

; ---------- 2Ah: 获取系统日期 ----------
; 通过 INT 1Ah AH=04h 获取 RTC 日期，将 BCD 转换为二进制并组装成 CX=年, DX=月日
.dos_get_date:
    push    ax
    mov     ah, 0x04
    int     0x1A
    
    push    dx                  ; 保存 DH=月, DL=日
    mov     al, ch              ; CH=世纪 BCD
    call    .bcd_to_bin
    mov     ch, 0
    mov     bx, 100
    mul     bx
    pop     dx                  ; 恢复月日
    
    push    ax                  ; 暂存世纪*100
    mov     al, cl              ; CL=年 BCD
    call    .bcd_to_bin
    xor     ah, ah
    pop     bx
    add     ax, bx              ; AX = 完整年份
    mov     cx, ax              ; CX = 年
    mov     al, dh              ; DH=月 BCD
    call    .bcd_to_bin
    mov     dh, al
    mov     al, dl              ; DL=日 BCD
    call    .bcd_to_bin
    mov     dl, al
    pop     ax
    mov     al, 0               ; 星期几固定为 0
    mov     bp, sp
    mov     [bp + 14], ax       ; AL=星期
    mov     [bp + 12], cx       ; CX=年
    mov     [bp + 10], dx       ; DH=月, DL=日
    jmp     .api_done_success

; ---------- 2Ch: 获取系统时间 ----------
; 通过 INT 1Ah AH=02h 获取 RTC 时间，BCD 转二进制，返回 CH=时, CL=分, DH=秒, DL=0
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
    mov     dl, 0               ; 百分秒固定为 0
    pop     ax
    mov     bp, sp
    mov     [bp + 12], cx       ; CX=时:分
    mov     [bp + 10], dx       ; DH=秒, DL=百分秒
    jmp     .api_done

; ---------- 30h: 获取 DOS 版本 ----------
; 返回 dos_ver_major 和 dos_ver_minor 中存储的值，BX=0x00FF, CX=0
.dos_get_version:
    mov     al, [cs:dos_ver_major]      
    mov     ah, [cs:dos_ver_minor]      
    mov     bx, 0x00FF
    mov     cx, 0x0000
    mov     bp, sp
    mov     [bp + 8], bx        ; BX 返回
    mov     [bp + 12], cx       ; CX 返回
    jmp     .api_done_success

; ---------- 33h: Ctrl-Break 状态检查 ----------
; AL=00 时返回 DL=00 (禁用 Ctrl-Break 检查)
.dos_ctrl_break:
    cmp     al, 0x00
    jne     .ctrl_break_done
    mov     dl, 0x00
    mov     bp, sp
    mov     [bp + 10], dx       ; DL 返回
.ctrl_break_done:
    jmp     .api_done_success

; ---------- FFh: 动态调节模拟版本 (PPP OS 后门) ----------
; BH=主版本, BL=次版本，保存到 dos_ver_major/minor
.dos_set_sim_ver:
    mov     [cs:dos_ver_major], bh      
    mov     [cs:dos_ver_minor], bl      
    jmp     .api_done_success

; ================= 文件系统 API (适配 10 字节 VFS) =================

; ---------- 3Ch: 创建文件 ----------
; 将 DS:DX 的 ASCIIZ 文件名转换为 11 字节的 FAT 名称（8+3），调用 fat12_write_file 创建
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
    mov     cx, 0               ; 属性 0
    call    fat12_write_file    ; 创建或覆写文件
    pop     ds
    jc      .file_op_err        

    mov     si, dx              ; 重新打开文件以获取句柄
    call    vfs_open
    jc      .file_op_err
    jmp     .api_done_success   

; ---------- 3Dh: 打开已有文件 ----------
; 调用 vfs_open，返回文件句柄在 AX
.dos_open_file:
    mov     si, dx
    call    vfs_open
    jc      .file_op_err
    jmp     .api_done_success

; ---------- 3Eh: 关闭文件 ----------
; BX=句柄，调用 vfs_close
.dos_close_file:
    call    vfs_close
    jc      .file_op_err        
    jmp     .api_done_success

; ---------- 3Fh: 读取文件 (适配 10 字节 VFS) ----------
; BX=句柄，CX=请求字节数，DX=缓冲区偏移
; 支持从标准输入 (BX<2) 读取一个字符
; 采用 10 字节 FD 结构，利用 FD_EXACT_SZ 进行截断，防止读出垃圾
.dos_read_file:
    cmp     bx, 2
    jb      .read_console

    ; 通过 FD_SIZE=10 计算 FD 表项偏移
    push    dx                  
    push    ax
    mov     ax, 10              ; FD_SIZE
    mul     bx
    mov     si, fd_table
    add     si, ax
    pop     ax
    pop     dx                  
    
    cmp     byte [cs:si], 0
    je      .file_op_err

    ; 根据文件精确大小计算实际可读字节
    mov     ax, [cs:si + 8]     ; FD_EXACT_SZ
    sub     ax, [cs:si + 6]     ; 当前偏移
    jbe     .read_eof_zero      ; 已达文件尾
    cmp     cx, ax
    jbe     .len_ok
    mov     cx, ax              ; 截断至剩余大小
.len_ok:

    ; 读取整个文件数据到内核缓存 (0x8000:0000)
    push    es
    pusha
    mov     ax, 0x8000
    mov     es, ax
    xor     di, di
    mov     ax, [cs:si + 2]     ; FD_LBA
    mov     cx, [cs:si + 4]     ; FD_LENGTH (扇区数)
    mov     bx, di
    call    disk_read_lba
    popa
    pop     es
    jc      .file_op_err

    ; 从内核缓存复制到用户缓冲区
    mov     ax, [cs:si + 6]     ; 当前偏移

    push    ds
    push    es
    push    cx
    push    si

    push    ds
    pop     es                  ; ES = 用户 DS
    mov     di, dx              ; 用户缓冲区偏移

    mov     dx, 0x8000
    mov     ds, dx              ; DS = 内核缓存段
    mov     si, ax              ; 缓存内偏移

    rep movsb

    pop     si
    pop     cx
    pop     es
    pop     ds

    ; 更新文件偏移
    add     word [cs:si + 6], cx

    mov     ax, cx              ; 实际读取字节数
    jmp     .api_done_success

.read_console:
    ; 从控制台读取一个字符 (模拟 stdin)
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
; BX=句柄，CX=字节数，DX=缓冲区偏移
; 句柄 1/2 为控制台输出（打印到屏幕）
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

; ---------- 屏幕终端打印拦截器 ----------
; 将 CX 字节从 DS:DX 输出到屏幕 (BIOS INT 10h AH=0Eh)
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
    pop     ax                  ; 恢复 CX 到 AX 作为写入字节数
    jmp     .api_done_success

; ---------- 41h: 删除文件 ----------
; 将 DS:DX 的 ASCIIZ 文件名转为 FAT 名，调用 fat12_delete_file
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
; AL=移动方式 (0:绝对, 1:相对, 2:末尾), BX=句柄, CX:DX=偏移量 (仅 DX 低16位使用)
; 返回新偏移在 DX:AX
.dos_lseek:
    push    dx                  
    push    ax
    mov     ax, 10              ; FD_SIZE
    mul     bx
    mov     di, fd_table
    add     di, ax              
    pop     ax
    pop     dx                  

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
    mov     [bp + 10], dx       ; DX 返回高16位 (0)
    jmp     .api_done_success

.seek_cur:
    add     dx, [cs:di + 6]     
    mov     [cs:di + 6], dx
    mov     ax, dx
    xor     dx, dx
    mov     bp, sp
    mov     [bp + 10], dx
    jmp     .api_done_success

.seek_end:
    ; 使用 FD_EXACT_SZ (偏移量8) 作为文件大小
    mov     ax, [cs:di + 8]     
    add     dx, ax              
    mov     [cs:di + 6], dx
    mov     ax, dx
    xor     dx, dx
    mov     bp, sp
    mov     [bp + 10], dx
    jmp     .api_done_success

; ---------- 43h: 获取/设置文件属性 ----------
; AL=0 获取属性，返回 CX 中；AL 非0 返回失败
; 仅支持识别目录属性 (0x10)
.dos_file_attr:
    cmp     al, 0x00            
    jne     .attr_fail
    
    ; 转换文件名
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

    ; 查找文件
    push    ds
    push    cs
    pop     ds
    mov     si, dos_file_name_buf
    call    fat12_find_file
    pop     ds
    jc      .attr_fail          

    ; 返回属性：普通文件 0x20，目录 0x10
    mov     cx, 0x0020          
    test    dl, 0x10            ; 假设 fat12_find_file 在 DL 中返回属性
    jz      .attr_ok
    mov     cx, 0x0010          
.attr_ok:
    mov     bp, sp
    mov     [bp + 12], cx       ; CX 返回属性
    jmp     .api_done_success
.attr_fail:
    mov     ax, 0x02            ; 错误码 02h (文件未找到)
    jmp     .api_done_fail

; ---------- 内存分配与管理拦截 ----------
; 48h: 分配内存 (始终返回失败，错误 08h)
.dos_alloc_mem:
    mov     ax, 0x0008          ; 错误码 08h (内存不足)
    mov     bx, 0x0000          
    mov     bp, sp
    mov     [bp + 8], bx        ; BX 返回 0
    jmp     .api_done_fail

; 49h: 释放内存 (假装成功)
.dos_free_mem:
    jmp     .api_done_success

; 4Ah: 调整内存块大小 (假装成功)
.dos_resize_mem:
    jmp     .api_done_success

; --- 辅助函数 ---
; 将 BCD 码 (AL) 转换为二进制数
.bcd_to_bin:
    push    bx
    mov     bl, al
    and     al, 0x0F            ; 低位
    shr     bl, 4               ; 高位
    mov     bh, 10
    xchg    al, bl              ; AL=高位, BL=低位
    mul     bh                  ; 高位*10
    add     al, bl              ; +低位
    pop     bx
    ret

; ---------- 统一的错误处理与返回 ----------
.file_op_err:
    mov     ax, 0x0002          ; 错误码: 02h (文件未找到或操作失败)

.api_done_fail:
    mov     bp, sp
    mov     [bp + 14], ax       ; AX 返回错误码
    or      word [bp + 20], 0x0001 ; 置 CF=1
    popa
    iret

.api_done_success:
    mov     bp, sp
    mov     [bp + 14], ax       ; AX 返回结果
    and     word [bp + 20], 0xFFFE ; 清 CF=0
    popa
    iret

.unsupported_api:
    mov     ax, 0x0001          ; 错误码 01h (无效功能)
    jmp     .api_done_fail

.api_done:
    popa                
    iret

; 静态分配区
dos_file_name_buf times 11 db ' '   ; 临时文件名缓冲区
dos_dta_seg       dw 0              ; DTA 段
dos_dta_off       dw 0x0080         ; DTA 偏移 (默认 PSP 区域)

; DOS 版本控制 (默认由外层设置)
dos_ver_major     db 0
dos_ver_minor     db 0