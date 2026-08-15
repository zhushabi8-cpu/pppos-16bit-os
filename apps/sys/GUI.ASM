[BITS 16]
[ORG 0x0000]

%define MAX_LINES 250           
%define LINE_WIDTH 128          

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

.full_reset:
    ; 切换到文本模式，隐藏光标
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    
    mov ax, 0x1003
    mov bl, 0x00      ; 00h = 启用高亮背景（关闭闪烁）
    int 0x10

    mov ah, 0x01
    mov cx, 0x2000
    int 0x10
    ; 隐藏系统原生鼠标光标
    mov ah, 0x11
    int 0x80

.reload:
    call gui_load_files          ; 读取当前目录文件列表
    mov byte [gui_selected_idx], 0
    mov byte [gui_page], 0
    mov word [prev_mouse_x], 0xFFFF
    mov byte [mouse_btn], 0

    ; 清空多选标记
    pusha
    push es
    push cs
    pop es
    mov di, gui_multi_select
    mov cx, 224
    xor al, al
    rep stosb
    pop es
    popa

.gui_loop:
    call hide_mouse

    mov ah, 0x12
    int 0x80

    push es
    mov ah, 0x33
    int 0x80
    mov es, ax

    mov ah, 0x44
    int 0x80
    mov byte [str_gui_title + 19], al

    mov di, 0
    mov cx, 80
    mov ah, 0x1F
.title_bg:
    mov al, ' '
    stosw
    loop .title_bg
    mov si, str_gui_title
    mov di, 60
    mov ah, 0x1F
    call gui_draw_string

    mov di, 160
    mov cx, 80
    mov ah, 0xE0
.menu_bg:
    mov al, ' '
    stosw
    loop .menu_bg
    mov si, str_gui_menu
    mov di, 162
    mov ah, 0xE0
    call gui_draw_string

    mov di, 3840
    mov cx, 80
    mov ah, 0xA0
.bottom_bg:
    mov al, ' '
    stosw
    loop .bottom_bg
    mov si, str_gui_bottom
    mov di, 3842
    mov ah, 0xA0
    call gui_draw_string

    pop es

    call gui_render_files

    call gui_flip_screen
    call show_mouse

    mov ah, 0x13
    int 0x80

.wait_input:
    call gui_update_clock

    mov ah, 0x15
    int 0x80
    or ax, ax
    jnz .handle_key

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .mouse_moved
    cmp dx, [prev_mouse_y]
    jne .mouse_moved
    jmp .check_click

.mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call show_mouse             

.check_click:
    cmp bl, [mouse_btn]
    je .wait_input
    mov [mouse_btn], bl

    test bl, 1
    jnz .on_left_click

    jmp .wait_input

.on_left_click:
    cmp dx, 1
    jne .check_files
    cmp cx, 10
    jb .open_file_menu
    cmp cx, 20
    jb .do_open_with
    cmp cx, 32
    jb .open_spec_menu
    jmp .wait_input

.check_files:
    cmp dx, 3
    jb .wait_input
    cmp dx, 22
    ja .wait_input

    sub dx, 3
    mov ax, cx
    mov cl, 25
    div cl
    cmp al, 2
    ja .wait_input

    mov cl, 20
    mul cl
    add al, dl

    mov cl, al
    mov al, [gui_page]
    mov dl, 60
    mul dl
    add al, cl

    cmp al, [gui_file_count]
    jae .wait_input

    cmp al, [gui_selected_idx]
    je .execute_selected

    call hide_mouse
    mov [gui_selected_idx], al
    call gui_render_files
    call gui_flip_screen      
    call show_mouse
    jmp .wait_input

.handle_key:
    cmp al, 's'
    je .exit_gui
    cmp al, 'S'
    je .exit_gui
    cmp al, 'c'
    je .do_copy
    cmp al, 'C'
    je .do_copy
    cmp al, 'x'
    je .do_cut
    cmp al, 'X'
    je .do_cut
    cmp al, 'v'
    je .do_paste
    cmp al, 'V'
    je .do_paste
    cmp ah, 0x3B              ; F1 打开文件菜单
    je .open_file_menu
    cmp ah, 0x3C              ; F2 打开方式
    je .do_open_with
    cmp ah, 0x3D              ; F3 特殊功能
    je .open_spec_menu

    cmp al, 13                ; 回车执行
    je .execute_selected
    cmp al, 8                 ; 退格返回上级目录
    je .go_back
    cmp al, ' '               ; 空格多选标记
    je .toggle_select
    cmp ah, 0x48              ; 上箭头
    je .move_up
    cmp ah, 0x50              ; 下箭头
    je .move_down
    cmp ah, 0x4B              ; 左箭头
    je .move_left
    cmp ah, 0x4D              ; 右箭头
    je .move_right
    cmp ah, 0x49              ; Page Up
    je .page_up
    cmp ah, 0x51              ; Page Down
    je .page_down

    jmp .wait_input

.toggle_select:
    mov al, [gui_selected_idx]
    xor ah, ah
    push bx
    mov bx, ax
    xor byte [gui_multi_select + bx], 1
    pop bx

    mov al, [gui_selected_idx]
    inc al
    cmp al, [gui_file_count]
    jae .skip_auto_down
    mov [gui_selected_idx], al
.skip_auto_down:
    jmp .sync_page_and_render

.page_up:
    cmp byte [gui_page], 0
    je .wait_input
    dec byte [gui_page]
    mov al, [gui_page]
    mov bl, 60
    mul bl
    mov [gui_selected_idx], al
    call hide_mouse
    call gui_render_files
    call gui_flip_screen      
    call show_mouse
    jmp .wait_input

.page_down:
    mov al, [gui_page]
    inc al
    mov bl, 60
    mul bl
    cmp al, [gui_file_count]
    jae .wait_input
    mov al, [gui_page]
    inc al
    mov [gui_page], al
    mov bl, 60
    mul bl
    mov [gui_selected_idx], al
    call hide_mouse
    call gui_render_files
    call gui_flip_screen      
    call show_mouse
    jmp .wait_input

; ----- 方向键移动 -----
.move_up:
    cmp byte [gui_selected_idx], 0
    je .wait_input
    dec byte [gui_selected_idx]
    jmp .sync_page_and_render

.move_down:
    mov al, [gui_selected_idx]
    mov bl, [gui_file_count]
    dec bl
    cmp al, bl
    jae .wait_input
    inc byte [gui_selected_idx]
    jmp .sync_page_and_render

.move_left:
    mov al, [gui_selected_idx]
    cmp al, 20
    jb .wait_input
    sub al, 20
    mov [gui_selected_idx], al
    jmp .sync_page_and_render

.move_right:
    mov al, [gui_selected_idx]
    add al, 20
    cmp al, [gui_file_count]
    jae .wait_input
    mov [gui_selected_idx], al
    jmp .sync_page_and_render

; ----- 同步页码并重绘 -----
.sync_page_and_render:
    mov al, [gui_selected_idx]
    mov bl, 60
    xor ah, ah
    div bl
    mov [gui_page], al

    call hide_mouse
    call gui_render_files
    call gui_flip_screen      
    call show_mouse
    jmp .wait_input

; ----- 返回上级目录 (..) -----
.go_back:
    mov di, exec_cmd
    mov byte [di], '.'
    mov byte [di+1], '.'
    mov byte [di+2], 0
    mov ah, 0x0E
    mov si, exec_cmd
    int 0x80
    jmp .reload

; ----- 执行选中的文件或进入目录 -----
.execute_selected:
    mov al, [gui_file_count]
    or al, al
    jz .wait_input

    call get_selected_ptr

    mov al, [si+11]
    test al, 0x10
    jnz .enter_dir

    ; 向系统 SYSTEM.REG 查询关联程序
    push cs
    pop es
    mov di, reg_key_buf
    mov cx, 16
    mov al, ' '
    rep stosb
    
    call get_selected_ptr
    add si, 8
    mov di, reg_key_buf
    mov cx, 3
    rep movsb
    
    push cs
    pop es
    mov di, exec_cmd      
    mov si, reg_key_buf   
    mov ah, 0x42          
    int 0x80
    
    cmp al, 1
    je .do_exec_with_assoc  

.run_native:
    call get_selected_ptr
    mov di, exec_cmd
    mov cx, 8
.copy_cmd:
    mov al, [si]
    cmp al, ' '
    je .end_copy
    mov [di], al
    inc si
    inc di
    loop .copy_cmd
.end_copy:
    mov byte [di], 0
    mov di, exec_arg
    mov cx, 11
    mov al, ' '
    rep stosb
    jmp .do_exec
.do_exec_with_assoc:
    mov di, exec_cmd
.trim_cmd_spaces:
    cmp byte [di], ' '
    je .terminate_cmd
    cmp byte [di], 0
    je .terminate_cmd
    inc di
    jmp .trim_cmd_spaces
.terminate_cmd:
    mov byte [di], 0

    call get_selected_ptr
    mov di, exec_arg
    mov cx, 11
    rep movsb

.do_exec:
    call hide_mouse
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    mov ah, 0x0B
    mov si, exec_cmd
    mov di, exec_arg
    int 0x80

    mov ah, 0x00
    mov si, msg_pause
    int 0x80
    mov ah, 0x01
    int 0x80
    jmp .full_reset

.enter_dir:
    mov di, exec_cmd
    mov cx, 11
.copy_dir:
    mov al, [si]
    cmp al, ' '
    je .skip_dir_spc
    mov [di], al
    inc di
.skip_dir_spc:
    inc si
    loop .copy_dir
    mov byte [di], 0

    mov ah, 0x0E
    mov si, exec_cmd
    int 0x80
    jmp .reload

; ----- 打开文件菜单 (F1) -----
.open_file_menu:
    call hide_mouse
    mov byte [menu_selected_idx], 0
.menu_loop_start:
    call draw_file_menu
    call gui_flip_screen      
    call show_mouse
.menu_wait:
    mov ah, 0x15
    int 0x80
    or ax, ax
    jnz .menu_handle_key

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .menu_mouse_moved
    cmp dx, [prev_mouse_y]
    jne .menu_mouse_moved
    jmp .menu_check_click

.menu_mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call draw_file_menu
    call gui_flip_screen      
    call show_mouse

.menu_check_click:
    cmp bl, [mouse_btn]
    je .menu_wait
    mov [mouse_btn], bl
    test bl, 1
    jz .menu_wait

    cmp cx, 1
    jb .menu_cancel
    cmp cx, 13
    ja .menu_cancel
    cmp dx, 3
    jb .menu_cancel
    cmp dx, 9
    ja .menu_cancel

    mov ax, dx
    sub ax, 3
    mov [menu_selected_idx], al
    call hide_mouse
    jmp .menu_exec

.menu_handle_key:
    call hide_mouse
    cmp ah, 0x48
    je .menu_up
    cmp ah, 0x50
    je .menu_down
    cmp al, 13
    je .menu_exec
    cmp al, 27
    je .menu_cancel
    call show_mouse
    jmp .menu_wait

.menu_cancel:
    call hide_mouse
    jmp .gui_loop

.menu_up:
    cmp byte [menu_selected_idx], 0
    je .menu_loop_start
    dec byte [menu_selected_idx]
    jmp .menu_loop_start

.menu_down:
    cmp byte [menu_selected_idx], 6
    jae .menu_loop_start
    inc byte [menu_selected_idx]
    jmp .menu_loop_start

.menu_exec:
    cmp byte [menu_selected_idx], 0
    je .do_mkdir
    cmp byte [menu_selected_idx], 1
    je .do_rename
    cmp byte [menu_selected_idx], 2
    je .do_delete
    cmp byte [menu_selected_idx], 3
    je .do_cut
    cmp byte [menu_selected_idx], 4
    je .do_copy
    cmp byte [menu_selected_idx], 5
    je .do_paste
    jmp .gui_loop

; ----- 打开特殊功能菜单 (F3) -----
.open_spec_menu:
    call hide_mouse
    mov byte [menu3_selected_idx], 0
.menu3_loop_start:
    call draw_spec_menu
    call gui_flip_screen
    call show_mouse
.menu3_wait:
    mov ah, 0x15
    int 0x80
    or ax, ax
    jnz .menu3_handle_key

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .menu3_mouse_moved
    cmp dx, [prev_mouse_y]
    jne .menu3_mouse_moved
    jmp .menu3_check_click

.menu3_mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call draw_spec_menu
    call gui_flip_screen
    call show_mouse

.menu3_check_click:
    cmp bl, [mouse_btn]
    je .menu3_wait
    mov [mouse_btn], bl
    test bl, 1
    jz .menu3_wait

    cmp cx, 23
    jb .menu3_cancel
    cmp cx, 35
    ja .menu3_cancel
    cmp dx, 3
    jb .menu3_cancel
    cmp dx, 6                   
    ja .menu3_cancel

    mov ax, dx
    sub ax, 3
    mov [menu3_selected_idx], al
    call hide_mouse
    jmp .menu3_exec

.menu3_handle_key:
    call hide_mouse
    cmp ah, 0x48
    je .menu3_up
    cmp ah, 0x50
    je .menu3_down
    cmp al, 13
    je .menu3_exec
    cmp al, 27
    je .menu3_cancel
    call show_mouse
    jmp .menu3_wait

.menu3_cancel:
    call hide_mouse
    jmp .gui_loop

.menu3_up:
    cmp byte [menu3_selected_idx], 0
    je .menu3_loop_start
    dec byte [menu3_selected_idx]
    jmp .menu3_loop_start

.menu3_down:
    cmp byte [menu3_selected_idx], 3   
    jae .menu3_loop_start
    inc byte [menu3_selected_idx]
    jmp .menu3_loop_start

.menu3_exec:
    cmp byte [menu3_selected_idx], 0
    je .do_sysinfo
    cmp byte [menu3_selected_idx], 1
    je .do_switch_drv           
    cmp byte [menu3_selected_idx], 2
    je .do_reboot
    jmp .gui_loop

.do_switch_drv:
    push es
    mov ah, 0x33
    int 0x80
    mov es, ax
    mov di, 1640
    mov cx, 3
.drv_dlg_loop:
    push cx
    mov cx, 40
    mov ax, 0x4F20
    rep stosw
    add di, 80
    pop cx
    loop .drv_dlg_loop

    mov si, str_switch_drv
    mov di, 1804
    mov ah, 0x4F
    call gui_draw_string

    call gui_flip_screen
    call show_mouse

    mov di, input_buf
    mov bx, 1846
.drv_input:
    push bx
    push di

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .drv_mouse_moved
    cmp dx, [prev_mouse_y]
    jne .drv_mouse_moved
    jmp .drv_kb_check

.drv_mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call show_mouse

.drv_kb_check:
    mov ah, 0x15
    int 0x80

    pop di
    pop bx

    or ax, ax
    jz .drv_input

    cmp al, 27
    je .drv_abort
    cmp al, 13
    je .drv_done
    cmp al, 8
    je .drv_bs

    cmp al, 'A'
    jb .drv_check_lower
    cmp al, 'Z'
    ja .drv_check_lower
    jmp .drv_store
.drv_check_lower:
    cmp al, 'a'
    jb .drv_input
    cmp al, 'z'
    ja .drv_input
    sub al, 32

.drv_store:
    push ax
    mov ax, di
    sub ax, input_buf
    cmp ax, 1           ; 限定只能输入 1 个盘符字母
    pop ax
    jae .drv_input

    mov [di], al
    inc di

    call hide_mouse
    mov ah, 0x4F
    mov [es:bx], ax
    add bx, 2
    call gui_flip_screen
    call show_mouse
    jmp .drv_input

.drv_bs:
    cmp di, input_buf
    jbe .drv_input
    dec di
    sub bx, 2
    call hide_mouse
    mov word [es:bx], 0x4F20
    call gui_flip_screen
    call show_mouse
    jmp .drv_input

.drv_abort:
    pop es
    call hide_mouse
    jmp .reload

.drv_done:
    mov byte [di], 0
    pop es

    mov al, [input_buf]
    or al, al
    jz .drv_abort

    mov ah, 0x45                
    int 0x80
    
    cmp al, 1
    je .reload                  

    call gui_show_drv_err
    jmp .gui_loop               
; ================================================================

; ----- 系统信息 (查看 8 大物理 64KB 块占用) -----
.do_sysinfo:
    call gui_render_files       

    call get_kernel_mem_info    

    push es
    mov ah, 0x33
    int 0x80
    mov es, ax                  

    mov di, 160 * 4 + 36
    mov cx, 15
.si_box:
    push cx
    mov cx, 44
    mov ax, 0x1F20              
    rep stosw
    add di, 160 - 88
    pop cx
    loop .si_box

    mov di, 160 * 4 + 36
    mov cx, 44
    mov ax, 0x4F20              
    rep stosw
    mov si, str_sys_title
    mov di, 160 * 4 + 40
    mov ah, 0x4F
    call gui_draw_string

    mov si, str_sysinfo2
    mov di, 160 * 5 + 40
    mov ah, 0x1F
    call gui_draw_string

    int 0x12
    mov di, input_buf
    push es
    push ds
    pop es
    call itoa
    pop es

    mov si, input_buf
    mov di, 160 * 5 + 70
    mov ah, 0x1E
    call gui_draw_string

    mov si, str_sysinfo3
    mov ah, 0x1F
    call gui_draw_string

    mov si, str_mem_bmp_lbl
    mov di, 160 * 6 + 40
    mov ah, 0x1F
    call gui_draw_string

    mov di, 160 * 6 + 68
    xor bx, bx
.draw_bmp_blocks:
    mov al, [cs:cur_mem_bitmap]
    mov cl, bl
    shr al, cl
    test al, 1
    jz .bmp_free
    mov ax, 0x4FFE              
    jmp .bmp_put
.bmp_free:
    mov ax, 0x2FFE              
.bmp_put:
    stosw
    mov ax, 0x1F20              
    stosw
    inc bx
    cmp bx, 8
    jb .draw_bmp_blocks

    mov si, str_mem_line
    mov di, 160 * 7 + 40
    mov ah, 0x1F
    call gui_draw_string

    xor bx, bx
.draw_blk_loop:
    push bx
    mov ax, bx
    add ax, 8
    mov dx, 160
    mul dx
    add ax, 40
    mov di, ax

    mov si, str_blk_pre
    mov ah, 0x1F
    call gui_draw_string

    pop bx
    push bx
    mov al, bl
    add al, '0'
    mov ah, 0x1E
    stosw

    mov si, str_blk_mid
    mov ah, 0x1F
    call gui_draw_string

    pop bx
    push bx
    mov ax, bx
    add ax, 2
    add al, '0'
    mov ah, 0x1E
    stosw

    mov si, str_blk_seg_end
    mov ah, 0x1F
    call gui_draw_string

    pop bx
    push bx
    mov al, [cs:cur_mem_bitmap]
    mov cl, bl
    shr al, cl
    test al, 1
    jz .blk_is_free

.blk_is_used:
    mov si, str_status_used
    mov ah, 0x4F
    call gui_draw_string

    pop bx
    push bx
    mov al, [cs:cur_mem_sizes + bx]
    or al, al
    jz .blk_next_line

    push ax
    mov si, str_size_pre
    mov ah, 0x1F
    call gui_draw_string

    pop ax
    add al, '0'
    mov ah, 0x1E
    stosw

    mov si, str_size_post
    mov ah, 0x1F
    call gui_draw_string
    jmp .blk_next_line

.blk_is_free:
    mov si, str_status_free
    mov ah, 0x2F
    call gui_draw_string

.blk_next_line:
    pop bx
    inc bx
    cmp bx, 8
    jb .draw_blk_loop

    mov si, str_mem_line
    mov di, 160 * 16 + 40
    mov ah, 0x1F
    call gui_draw_string

    mov si, str_mem_footer
    mov di, 160 * 17 + 42
    mov ah, 0x1E
    call gui_draw_string

    call gui_flip_screen
    call show_mouse

.si_wait:
    mov ah, 0x15
    int 0x80
    or ax, ax
    jz .si_wait

    pop es
    jmp .gui_loop

; ----- 重启系统 -----
.do_reboot:
    mov ax, 0x0040
    mov ds, ax
    mov word [0x0072], 0x1234   
    jmp 0xFFFF:0000

; ----- F2: 选择打开方式 -----
.do_open_with:
    mov al, [gui_file_count]
    or al, al
    jz .gui_loop

    push es
    mov ah, 0x33              
    int 0x80
    mov es, ax
    mov di, 1640
    mov cx, 3
.ow_dlg_loop:
    push cx
    mov cx, 40
    mov ax, 0x4F20
    rep stosw
    add di, 80
    pop cx
    loop .ow_dlg_loop

    mov si, str_open_with
    mov di, 1804
    mov ah, 0x4F
    call gui_draw_string

    call gui_flip_screen
    call show_mouse

    mov di, input_buf
    mov bx, 1826
.ow_input:
    push bx
    push di

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .ow_mouse_moved
    cmp dx, [prev_mouse_y]
    jne .ow_mouse_moved
    jmp .ow_kb_check

.ow_mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call show_mouse

.ow_kb_check:
    mov ah, 0x15
    int 0x80

    pop di
    pop bx

    or ax, ax
    jz .ow_input

    cmp al, 27
    je .ow_abort
    cmp al, 13
    je .ow_done
    cmp al, 8
    je .ow_bs

    cmp al, ' '
    jb .ow_input
    cmp al, '~'
    ja .ow_input

    cmp al, 'a'
    jb .ow_store
    cmp al, 'z'
    ja .ow_store
    sub al, 32
.ow_store:
    push ax
    mov ax, di
    sub ax, input_buf
    cmp ax, 8
    pop ax
    jae .ow_input

    mov [di], al
    inc di

    call hide_mouse
    mov ah, 0x4F
    mov [es:bx], ax
    add bx, 2
    call gui_flip_screen
    call show_mouse
    jmp .ow_input

.ow_bs:
    cmp di, input_buf
    jbe .ow_input
    dec di
    sub bx, 2
    call hide_mouse
    mov word [es:bx], 0x4F20
    call gui_flip_screen
    call show_mouse
    jmp .ow_input

.ow_abort:
    pop es
    call hide_mouse
    jmp .reload

.ow_done:
    mov byte [di], 0
    pop es

    mov di, new_fat_name
    push cx
    mov cx, 8
    mov al, ' '
    rep stosb
    pop cx
    mov si, input_buf
    mov di, new_fat_name
.ow_fmt_loop:
    lodsb
    or al, al
    jz .ow_fmt_ok
    stosb
    jmp .ow_fmt_loop

.ow_fmt_ok:
    mov di, reg_key_buf
    push cx
    mov cx, 16
    mov al, ' '
    rep stosb
    pop cx

    call get_selected_ptr
    add si, 8
    mov di, reg_key_buf
    mov cx, 3
    rep movsb

    mov si, reg_key_buf
    mov dx, new_fat_name
    mov ah, 0x43
    int 0x80

    mov di, exec_cmd
    mov si, new_fat_name
    mov cx, 8
    rep movsb
    mov byte [exec_cmd+8], 0

    call get_selected_ptr
    mov di, exec_arg
    mov cx, 11
    rep movsb

    jmp .do_exec

; ----- 批量复制 -----
.do_copy:
    mov al, [gui_file_count]
    or al, al
    jz .gui_loop

    mov ah, 0x0F
    mov al, 0
    int 0x80

    xor bx, bx
    xor dx, dx
.cpy_multi_loop:
    cmp bx, 224
    jae .cpy_multi_done
    cmp byte [gui_multi_select + bx], 1
    jne .cpy_next

    mov [gui_selected_idx], bl
    call get_selected_ptr

    test byte [si+11], 0x10
    jnz .cpy_next

    push bx
    push dx
    mov ah, 0x0F
    mov al, 1
    int 0x80
    pop dx
    pop bx
    inc dx
.cpy_next:
    inc bx
    jmp .cpy_multi_loop

.cpy_multi_done:
    or dx, dx
    jnz .gui_loop

    call get_selected_ptr
    test byte [si+11], 0x10
    jnz .gui_loop

    mov ah, 0x0F
    mov al, 1
    int 0x80
    jmp .gui_loop

; ----- 批量剪切 -----
.do_cut:
    mov al, [gui_file_count]
    or al, al
    jz .gui_loop

    mov ah, 0x0F
    mov al, 0
    int 0x80

    xor bx, bx
    xor dx, dx
.cut_multi_loop:
    cmp bx, 224
    jae .cut_multi_done
    cmp byte [gui_multi_select + bx], 1
    jne .cut_next

    mov [gui_selected_idx], bl
    call get_selected_ptr

    test byte [si+11], 0x10
    jnz .cut_next

    push bx
    push dx
    mov ah, 0x0F
    mov al, 2
    int 0x80
    pop dx
    pop bx
    inc dx
.cut_next:
    inc bx
    jmp .cut_multi_loop

.cut_multi_done:
    or dx, dx
    jnz .gui_loop

    call get_selected_ptr
    test byte [si+11], 0x10
    jnz .gui_loop

    mov ah, 0x0F
    mov al, 2
    int 0x80
    jmp .gui_loop

; ----- 批量粘贴 -----
.do_paste:
    mov ah, 0x10
    int 0x80
    jmp .reload

; ----- 批量删除 -----
.do_delete:
    mov al, [gui_file_count]
    or al, al
    jz .gui_loop

    xor bx, bx
    xor dx, dx
.del_multi_loop:
    cmp bx, 224
    jae .del_multi_done
    cmp byte [gui_multi_select + bx], 1
    jne .del_next

    mov [gui_selected_idx], bl
    call get_selected_ptr
    push bx
    push dx
    mov ah, 0x0C
    int 0x80
    pop dx
    pop bx
    inc dx
.del_next:
    inc bx
    jmp .del_multi_loop

.del_multi_done:
    or dx, dx
    jnz .reload

    call get_selected_ptr
    mov ah, 0x0C
    int 0x80
    jmp .reload

; ----- 新建目录 -----
.do_mkdir:
    push es
    mov ah, 0x33
    int 0x80
    mov es, ax
    mov di, 1640
    mov cx, 3
.md_dlg_loop:
    push cx
    mov cx, 40
    mov ax, 0x4F20
    rep stosw
    add di, 80
    pop cx
    loop .md_dlg_loop

    mov si, str_mkdir
    mov di, 1804
    mov ah, 0x4F
    call gui_draw_string

    call gui_flip_screen
    call show_mouse

    mov di, input_buf
    mov bx, 1826
.md_input:
    push bx
    push di

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .md_mouse_moved
    cmp dx, [prev_mouse_y]
    jne .md_mouse_moved
    jmp .md_kb_check

.md_mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call show_mouse

.md_kb_check:
    mov ah, 0x15
    int 0x80

    pop di
    pop bx

    or ax, ax
    jz .md_input

    cmp al, 27
    je .md_abort
    cmp al, 13
    je .md_done
    cmp al, 8
    je .md_bs

    cmp al, ' '
    jb .md_input
    cmp al, '~'
    ja .md_input

    cmp al, 'a'
    jb .md_store
    cmp al, 'z'
    ja .md_store
    sub al, 32
.md_store:
    push ax
    mov ax, di
    sub ax, input_buf
    cmp ax, 8
    pop ax
    jae .md_input

    mov [di], al
    inc di

    call hide_mouse
    mov ah, 0x4F
    mov [es:bx], ax
    add bx, 2
    call gui_flip_screen
    call show_mouse
    jmp .md_input

.md_bs:
    cmp di, input_buf
    jbe .md_input
    dec di
    sub bx, 2
    call hide_mouse
    mov word [es:bx], 0x4F20
    call gui_flip_screen
    call show_mouse
    jmp .md_input

.md_abort:
    pop es
    call hide_mouse
    jmp .reload

.md_done:
    mov byte [di], 0
    pop es

    mov di, new_fat_name
    push cx
    mov cx, 11
    mov al, ' '
    rep stosb
    pop cx

    mov si, input_buf
    mov di, new_fat_name
.md_fmt_loop:
    lodsb
    or al, al
    jz .md_fmt_ok
    cmp al, '.'
    je .md_fmt_ext
    stosb
    jmp .md_fmt_loop
.md_fmt_ext:
    mov di, new_fat_name + 8
    jmp .md_fmt_loop
.md_fmt_ok:
    call hide_mouse
    mov byte [new_fat_name+11], 0
    push ds
    push es
    mov si, new_fat_name
    mov ah, 0x17
    int 0x80
    pop es
    pop ds
    sti
    jmp .reload

; ----- 重命名 -----
.do_rename:
    mov al, [gui_file_count]
    or al, al
    jz .gui_loop

    push es
    mov ah, 0x33
    int 0x80
    mov es, ax
    mov di, 1640
    mov cx, 3
.dlg_loop:
    push cx
    mov cx, 40
    mov ax, 0x4F20
    rep stosw
    add di, 80
    pop cx
    loop .dlg_loop

    mov si, str_rename
    mov di, 1804
    mov ah, 0x4F
    call gui_draw_string

    call gui_flip_screen
    call show_mouse

    mov di, input_buf
    mov bx, 1824
.ren_input:
    push bx
    push di

    mov ah, 0x14
    int 0x80
    cmp cx, [prev_mouse_x]
    jne .ren_mouse_moved
    cmp dx, [prev_mouse_y]
    jne .ren_mouse_moved
    jmp .ren_kb_check

.ren_mouse_moved:
    call hide_mouse
    mov [prev_mouse_x], cx
    mov [prev_mouse_y], dx
    call show_mouse

.ren_kb_check:
    mov ah, 0x15
    int 0x80

    pop di
    pop bx

    or ax, ax
    jz .ren_input

    cmp al, 27
    je .ren_abort
    cmp al, 13
    je .ren_done
    cmp al, 8
    je .ren_bs

    cmp al, ' '
    jb .ren_input
    cmp al, '~'
    ja .ren_input

    cmp al, 'a'
    jb .ren_store
    cmp al, 'z'
    ja .ren_store
    sub al, 32
.ren_store:
    push ax
    mov ax, di
    sub ax, input_buf
    cmp ax, 12
    pop ax
    jae .ren_input

    mov [di], al
    inc di

    call hide_mouse
    mov ah, 0x4F
    mov [es:bx], ax
    add bx, 2
    call gui_flip_screen
    call show_mouse
    jmp .ren_input

.ren_bs:
    cmp di, input_buf
    jbe .ren_input
    dec di
    sub bx, 2
    call hide_mouse
    mov word [es:bx], 0x4F20
    call gui_flip_screen
    call show_mouse
    jmp .ren_input

.ren_abort:
    pop es
    call hide_mouse
    jmp .reload

.ren_done:
    mov byte [di], 0
    pop es

    mov di, new_fat_name
    push cx
    mov cx, 11
    mov al, ' '
    rep stosb
    pop cx

    mov si, input_buf
    mov di, new_fat_name
.fmt_loop:
    lodsb
    or al, al
    jz .fmt_ok
    cmp al, '.'
    je .fmt_ext
    stosb
    jmp .fmt_loop
.fmt_ext:
    mov di, new_fat_name + 8
    jmp .fmt_loop
.fmt_ok:
    call hide_mouse
    mov byte [new_fat_name+11], 0
    call get_selected_ptr
    mov di, new_fat_name
    push ds
    push es
    mov ah, 0x0D
    int 0x80
    pop es
    pop ds
    sti
    jmp .reload

; ----- 退出 GUI -----
.exit_gui:
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    mov ah, 0x04
    int 0x80

; ==========================================
; GLOBAL SUBROUTINES (全局子程序区)
; ==========================================

gui_show_drv_err:
    pusha
    push es
    mov ah, 0x33
    int 0x80
    mov es, ax                  

    mov di, 160 * 10 + 36
    mov cx, 5
.err_box:
    push cx
    mov cx, 44
    mov ax, 0x4F20              
    rep stosw
    add di, 160 - 88
    pop cx
    loop .err_box

    mov si, str_drv_err
    mov di, 160 * 11 + 40
    mov ah, 0x4F
    call gui_draw_string

    mov si, str_drv_err2
    mov di, 160 * 13 + 64
    mov ah, 0x4E                
    call gui_draw_string

    call gui_flip_screen        
    call show_mouse

.wait_err:
    mov ah, 0x15                
    int 0x80
    or ax, ax
    jz .wait_err

    pop es
    popa
    ret

draw_spec_menu:
    pusha
    push es
    mov ah, 0x33
    int 0x80
    mov es, ax

    mov di, 160*2 + 46
    mov cx, 6                   
.box_loop3:
    push cx
    mov cx, 12
    mov ax, 0x7020
    rep stosw
    add di, 160 - 24
    pop cx
    loop .box_loop3

    mov si, str_menu3_mem
    mov di, 160*3 + 48
    mov ah, 0x70
    cmp byte [menu3_selected_idx], 0
    jne .p3_0
    mov ah, 0x1F
.p3_0: call gui_draw_string

    mov si, str_menu3_drv
    mov di, 160*4 + 48
    mov ah, 0x70
    cmp byte [menu3_selected_idx], 1
    jne .p3_1
    mov ah, 0x1F
.p3_1: call gui_draw_string

    mov si, str_menu3_reb
    mov di, 160*5 + 48        
    mov ah, 0x70
    cmp byte [menu3_selected_idx], 2
    jne .p3_2
    mov ah, 0x1F
.p3_2: call gui_draw_string

    mov si, str_menu3_can
    mov di, 160*6 + 48        
    mov ah, 0x70
    cmp byte [menu3_selected_idx], 3
    jne .p3_3
    mov ah, 0x1F
.p3_3: call gui_draw_string

    pop es
    popa
    ret

hide_mouse:
    pusha
    push es
    cmp word [prev_mouse_x], 0xFFFF
    je .skip
    mov ax, 0xB800
    mov es, ax
    mov ax, [prev_mouse_y]
    mov di, 80
    mul di
    add ax, [prev_mouse_x]
    shl ax, 1
    mov di, ax
    mov ax, [prev_mouse_attr]
    mov [es:di], ax             
.skip:
    pop es
    popa
    ret

show_mouse:
    pusha
    push es
    cmp word [prev_mouse_x], 0xFFFF
    je .skip
    mov ax, 0xB800
    mov es, ax
    mov ax, [prev_mouse_y]
    mov di, 80
    mul di
    add ax, [prev_mouse_x]
    shl ax, 1
    mov di, ax

    mov ax, [es:di]
    mov [prev_mouse_attr], ax   

    xor ah, 0x77                
    mov [es:di], ax
.skip:
    pop es
    popa
    ret

draw_file_menu:
    pusha
    push es
    mov ah, 0x33              
    int 0x80
    mov es, ax

    mov di, 160*2 + 2
    mov cx, 9
.box_loop:
    push cx
    mov cx, 12
    mov ax, 0x7020
    rep stosw
    add di, 160 - 24
    pop cx
    loop .box_loop

    mov si, str_menu_new
    mov di, 160*3 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 0
    jne .p_new
    mov ah, 0x1F
.p_new: call gui_draw_string

    mov si, str_menu_ren
    mov di, 160*4 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 1
    jne .p0
    mov ah, 0x1F
.p0: call gui_draw_string

    mov si, str_menu_del
    mov di, 160*5 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 2
    jne .p1
    mov ah, 0x1F
.p1: call gui_draw_string

    mov si, str_menu_cut
    mov di, 160*6 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 3
    jne .p2
    mov ah, 0x1F
.p2: call gui_draw_string

    mov si, str_menu_cpy
    mov di, 160*7 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 4
    jne .p3
    mov ah, 0x1F
.p3: call gui_draw_string

    mov si, str_menu_pst
    mov di, 160*8 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 5
    jne .p4
    mov ah, 0x1F
.p4: call gui_draw_string

    mov si, str_menu_can
    mov di, 160*9 + 4
    mov ah, 0x70
    cmp byte [menu_selected_idx], 6
    jne .p5
    mov ah, 0x1F
.p5: call gui_draw_string

    pop es
    popa
    ret

get_selected_ptr:
    push bx
    push dx
    xor ah, ah
    mov al, [gui_selected_idx]
    mov cx, 20
    mul cx
    mov si, gui_file_list
    add si, ax
    pop dx
    pop bx
    ret

gui_draw_string:
    lodsb
    or al, al
    jz .done_str
    stosw
    jmp gui_draw_string
.done_str:
    ret

gui_update_clock:
    pusha
    mov ah, 0x02
    int 0x1A
    cmp dh, [cs:prev_sec]
    je .done_clk
    mov [cs:prev_sec], dh

    call hide_mouse
    push es
    mov ah, 0x33              
    int 0x80
    mov es, ax
    mov di, 142
    mov al, ch
    call gui_draw_bcd
    mov ax, 0x1F3A
    stosw
    mov al, cl
    call gui_draw_bcd
    mov ax, 0x1F3A
    stosw
    mov al, dh
    call gui_draw_bcd
    pop es
    call gui_flip_screen        
    call show_mouse
.done_clk:
    popa
    ret

gui_draw_bcd:
    push ax
    push bx
    mov bl, al
    shr al, 4
    add al, '0'
    mov ah, 0x1F
    stosw
    mov al, bl
    and al, 0x0F
    add al, '0'
    mov ah, 0x1F
    stosw
    pop bx
    pop ax
    ret

gui_load_files:
    pusha
    mov byte [gui_file_count], 0

    mov di, gui_file_list
    mov ah, 0x0A
    mov al, 224
    int 0x80

    cmp cx, 224
    jbe .cx_ok
    mov cx, 224
.cx_ok:
    mov [gui_file_count], cl

    popa
    ret

gui_render_files:
    pusha
    push es
    mov ah, 0x33              
    int 0x80
    mov es, ax

    mov di, 320
    mov cx, 1760
    mov ah, 0xF0
    mov al, ' '
    rep stosw

    xor bx, bx
.r_loop:
    cmp bl, 60
    jae .r_done

    mov al, [gui_page]
    mov cl, 60
    mul cl
    add al, bl

    cmp al, [gui_file_count]
    jae .r_done

    push ax
    mov cx, 20
    mul cx
    mov si, gui_file_list
    add si, ax
    pop ax

    push ax
    mov ax, bx
    mov dl, 20
    div dl

    mov dl, ah
    add dl, 3

    push dx
    mov dl, 25
    mul dl
    add al, 2

    pop dx
    push ax
    mov al, dl
    mov dl, 160
    mul dl
    mov di, ax
    pop ax
    shl ax, 1
    add di, ax
    pop ax

    push di
    push bx
    mov bl, al
    xor bh, bh
    push di
    mov di, gui_multi_select
    add di, bx
    mov cl, [di]
    pop di
    pop bx
    pop di

    mov ah, 0xF0                 
    cmp cl, 1
    jne .check_cursor
    mov ah, 0xF4                 

.check_cursor:
    cmp al, [gui_selected_idx]
    jne .draw_item

    mov ah, 0x1F                 
    cmp cl, 1
    jne .draw_item
    mov ah, 0x1E                 

.draw_item:
    push cx
    push di
    mov cx, 14
    mov al, ' '
    rep stosw
    pop di

    mov cx, 11
    push si
.print_char:
    lodsb
    mov [es:di], ax
    add di, 2
    loop .print_char
    pop si

    mov al, [si+11]
    test al, 0x10
    jz .not_dir
    mov al, '\'
    mov [es:di], ax
    jmp .item_done

.not_dir:
    push ax                     
    
    mov ax, [si+12]
    mov dx, [si+14]
    add ax, 1023
    adc dx, 0
    mov cx, 10
.shr_kb:
    shr dx, 1
    rcr ax, 1
    loop .shr_kb

    push di
    push es
    push cs
    pop es
    mov di, num_buf
    call itoa
    pop es
    pop di

    pop ax                      
    push si
    mov si, num_buf
    add di, 2                   
.print_num:
    lodsb
    or al, al
    jz .print_kb
    mov [es:di], ax
    add di, 2
    jmp .print_num
.print_kb:
    mov al, 'K'                 
    mov [es:di], ax
    mov al, 'B'                 
    mov [es:di+2], ax
    pop si

.item_done:
    pop cx
    inc bx
    jmp .r_loop

.r_done:
    pop es
    popa
    ret

gui_flip_screen:
    pusha
    push ds
    push es
    mov ah, 0x33
    int 0x80
    mov ds, ax
    mov ax, 0xB800
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 2000                 
    cld
    rep movsw
    pop es
    pop ds
    popa
    ret

itoa:
    pusha
    mov cx, 0
    mov bx, 10
.i_loop1:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .i_loop1
.i_loop2:
    pop ax
    add al, '0'
    stosb
    loop .i_loop2
    mov byte [di], 0
    popa
    ret

get_kernel_mem_info:
    pusha
    push ds
    mov ax, 0x0800              
    mov ds, ax
    xor si, si                  
.scan_loop:
    cmp si, 0xFF00
    jae .scan_fail
    cmp word [si], 0x539C       ; pushf, push bx
    jne .next_b
    cmp byte [si+2], 0x52       ; push dx
    jne .next_b
    cmp byte [si+3], 0xFA       ; cli
    je .scan_found
.next_b:
    inc si
    jmp .scan_loop

.scan_fail:
    pop ds
    popa
    mov byte [cs:cur_mem_bitmap], 0x01  
    mov byte [cs:cur_mem_sizes], 1
    ret

.scan_found:
    mov al, [si - 9]
    mov [cs:cur_mem_bitmap], al
    
    sub si, 8
    mov di, cur_mem_sizes
    push cs
    pop es
    mov cx, 8
.copy_sizes:
    lodsb
    stosb
    loop .copy_sizes

    pop ds
    popa
    ret

; ==========================================
str_gui_title  db "PPP OS GUI - Drive C:\", 0    
str_gui_menu   db " F1:File   F2:View   F3:Special", 0
str_gui_bottom db "Arrows/Click: Select | Space: Mark | PgUp/PgDn: Page | RightClick: Menu", 0
str_rename     db " Rename to: ", 0
str_mkdir      db " Folder Name: ", 0
str_open_with  db " Open with: ", 0
str_switch_drv db " Drive Letter (A-Z): ", 0
msg_pause      db 13, 10, "--- App Terminated. Press any key ---", 0

str_menu_new   db " New Dir  ", 0
str_menu_ren   db " Rename   ", 0
str_menu_del   db " Delete   ", 0
str_menu_cut   db " Cut (X)  ", 0
str_menu_cpy   db " Copy (C) ", 0
str_menu_pst   db " Paste (V)", 0
str_menu_can   db " Cancel   ", 0

str_menu3_mem  db " Sys Info ", 0
str_menu3_drv  db " Sw Drive ", 0                
str_menu3_reb  db " Reboot   ", 0
str_menu3_can  db " Cancel   ", 0

str_drv_err      db " Drive not ready or invalid!       ", 0
str_drv_err2     db " Press Any Key... ", 0

str_sys_title    db "    ", 0
str_sysinfo2     db " Base Memory: ", 0
str_sysinfo3     db " KB", 0
str_mem_bmp_lbl  db "  ", 0
str_mem_line     db " ---------------------------------- ", 0
str_blk_pre      db " Block ", 0
str_blk_mid      db " [0x", 0
str_blk_seg_end  db "000]: ", 0
str_status_used  db "USED", 0
str_status_free  db "FREE        ", 0
str_size_pre     db " (Alloc: ", 0
str_size_post    db "x64KB)", 0
str_mem_footer   db "   Press Any Key to Close   ", 0

cur_mem_bitmap   db 0
cur_mem_sizes    times 8 db 0

reg_key_buf       times 16 db ' '

prev_mouse_x      dw 0xFFFF
prev_mouse_y      dw 12
prev_mouse_attr   dw 0
mouse_btn         db 0

prev_sec          db 0xFF
menu_selected_idx db 0
menu3_selected_idx db 0
gui_file_count    db 0
gui_selected_idx  db 0
gui_page          db 0
exec_cmd          times 20 db 0
exec_arg          times 11 db ' '
input_buf         times 16 db 0
new_fat_name      times 12 db 0
gui_file_list     times 224 * 20 db 0
gui_multi_select  times 224 db 0
num_buf           times 8 db 0