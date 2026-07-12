; apps/ext/gui.asm - PPP OS 图形化文件管理器 (鼠标+键盘双控)
[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; 尝试打开关联文件 (ASSOC.PFI)
    mov ah, 0x05
    mov si, str_assoc
    int 0x80
    cmp ax, 0xFFFF
    je .full_reset
    mov bx, ax
    mov ah, 0x07
    mov di, assoc_buffer
    int 0x80
    mov ah, 0x06
    int 0x80

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
    ; 隐藏鼠标初始光标（调用系统API）
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
    ; 绘制主界面（标题栏、菜单栏、文件列表区、底部状态栏）
    mov ah, 0x12
    int 0x80

    push es
    mov ax, 0xB800
    mov es, ax

    ; 标题栏 (第0行)
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

    ; 菜单栏 (第1行)
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

    ; 文件列表背景 (第2~22行)
    mov di, 320
    mov cx, 1760
    mov ah, 0xF0
.body_bg:
    mov al, ' '
    stosw
    loop .body_bg

    ; 底部状态栏 (第24行)
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

    call gui_render_files       ; 渲染当前页文件图标

    mov ah, 0x13
    int 0x80

.wait_input:
    call gui_update_clock       ; 更新时钟显示

    ; 检测键盘
    mov ah, 0x15
    int 0x80
    or ax, ax
    jnz .handle_key

    ; 检测鼠标移动
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

    test bl, 1                ; 左键点击
    jnz .on_left_click

    jmp .wait_input

.on_left_click:
    ; 点击菜单栏区域（F1文件菜单）
    cmp dx, 1
    jne .check_files
    jmp .open_file_menu

.check_files:
    ; 点击文件列表区 (第3~22行)
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
    add al, dl               ; al = 当前页屏幕索引 (0~59)

    ; 加上页码偏移得到绝对索引
    mov cl, al
    mov al, [gui_page]
    mov dl, 60
    mul dl
    add al, cl

    cmp al, [gui_file_count]
    jae .wait_input

    cmp al, [gui_selected_idx]
    je .execute_selected      ; 双击选中项（或再次点击同一项）执行

    call hide_mouse
    mov [gui_selected_idx], al
    call gui_render_files
    call show_mouse
    jmp .wait_input

.handle_key:
    ; 键盘快捷键
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

; ----- 多选切换 -----
.toggle_select:
    mov al, [gui_selected_idx]
    xor ah, ah
    push bx
    mov bx, ax
    xor byte [gui_multi_select + bx], 1
    pop bx

    ; 自动下移一格 (类似 Norton Commander)
    mov al, [gui_selected_idx]
    inc al
    cmp al, [gui_file_count]
    jae .skip_auto_down
    mov [gui_selected_idx], al
.skip_auto_down:
    jmp .sync_page_and_render

; ----- 翻页 -----
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

    ; 尝试用关联文件(ASSOC.PFI)打开
    mov bx, assoc_buffer

.parse_line_start:
    mov al, [bx]
    or al, al
    jz .run_native
    cmp al, 13
    je .next_line
    cmp al, 10
    je .next_line_direct
    cmp al, ' '
    je .next_char

    push bx
    mov di, si
    add di, 8
    mov cx, 3
.check_ext_loop:
    mov al, [bx]
    mov ah, [di]
    cmp al, ah
    jne .line_mismatch
    inc bx
    inc di
    loop .check_ext_loop

    pop ax

.find_equal:
    mov al, [bx]
    or al, al
    jz .run_native
    cmp al, 13
    je .next_line
    cmp al, '='
    je .found_equal
    inc bx
    jmp .find_equal

.found_equal:
    inc bx
.skip_spaces:
    mov al, [bx]
    cmp al, ' '
    jne .extract_app_start
    inc bx
    jmp .skip_spaces

.extract_app_start:
    mov di, exec_cmd
    mov cx, 8
.copy_app_loop:
    mov al, [bx]
    cmp al, ' '
    je .app_copy_done
    cmp al, '.'
    je .app_copy_done
    cmp al, 13
    je .app_copy_done
    cmp al, 10
    je .app_copy_done
    or al, al
    jz .app_copy_done
    stosb
    inc bx
    loop .copy_app_loop

.app_copy_done:
    mov byte [di], 0

    call get_selected_ptr
    mov di, exec_arg
    mov cx, 11
    rep movsb
    jmp .do_exec

.next_char:
    inc bx
    jmp .parse_line_start

.line_mismatch:
    pop bx

.next_line:
    mov al, [bx]
    or al, al
    jz .run_native
    inc bx
    cmp al, 10
    je .parse_line_start
    jmp .next_line

.next_line_direct:
    inc bx
    jmp .parse_line_start

.run_native:
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

; ----- 批量复制 -----
.do_copy:
    mov al, [gui_file_count]
    or al, al
    jz .gui_loop

    ; 清空剪贴板
    mov ah, 0x0F
    mov al, 0
    int 0x80

    ; 遍历多选标记
    xor bx, bx
    xor dx, dx
.cpy_multi_loop:
    cmp bx, 224
    jae .cpy_multi_done
    cmp byte [gui_multi_select + bx], 1
    jne .cpy_next

    mov [gui_selected_idx], bl
    call get_selected_ptr
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

    ; 降级为单文件复制
    call get_selected_ptr
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
    mov ax, 0xB800
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
    call show_mouse
    jmp .md_input

.md_bs:
    cmp di, input_buf
    jbe .md_input
    dec di
    sub bx, 2
    call hide_mouse
    mov word [es:bx], 0x4F20
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
    stosb
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
    mov ax, 0xB800
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
    call show_mouse
    jmp .ren_input

.ren_bs:
    cmp di, input_buf
    jbe .ren_input
    dec di
    sub bx, 2
    call hide_mouse
    mov word [es:bx], 0x4F20
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

; ----- 鼠标光标隐藏与显示 -----
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
    pop es
    popa
    ret

; ----- 绘制文件菜单 (弹出框) -----
draw_file_menu:
    pusha
    push es
    mov ax, 0xB800
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

; ----- 获取选中文件指针 -----
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

; ----- 绘制字符串到显存 (带颜色) -----
gui_draw_string:
    lodsb
    or al, al
    jz .done_str
    stosw
    jmp gui_draw_string
.done_str:
    ret

; ----- 更新时钟显示 (每秒一次) -----
gui_update_clock:
    pusha
    mov ah, 0x02
    int 0x1A
    cmp dh, [cs:prev_sec]
    je .done_clk
    mov [cs:prev_sec], dh

    call hide_mouse
    push es
    mov ax, 0xB800
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

; ----- 加载文件列表 (通过系统调用) -----
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

; ----- 渲染文件图标 (分页显示) -----
gui_render_files:
    pusha
    push es
    mov ax, 0xB800
    mov es, ax

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

    ; 计算屏幕坐标 (每行20个，每列25字符)
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

    ; 多选颜色判定
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

    mov ah, 0xF0                 ; 白底黑字 (未选中)
    cmp cl, 1
    jne .check_cursor
    mov ah, 0xF4                 ; 白底红字 (已选中)

.check_cursor:
    cmp al, [gui_selected_idx]
    jne .draw_item

    mov ah, 0x1F                 ; 蓝底白字 (光标)
    cmp cl, 1
    jne .draw_item
    mov ah, 0x1E                 ; 蓝底黄字 (光标+选中)

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

    ; 目录加 '\' 标记
    mov al, [si+11]
    test al, 0x10
    jz .not_dir
    mov al, '\'
    mov [es:di], ax
.not_dir:

    pop cx
    inc bx
    jmp .r_loop

.r_done:
    pop es
    popa
    ret

; ===== 数据 =====
str_gui_title  db "PPP OS GUI", 0
str_gui_menu   db " F1:File   F2:View   F3:Special", 0
str_gui_bottom db "Arrows/Click: Select | Space: Mark | PgUp/PgDn: Page | RightClick: Menu", 0
str_rename     db " Rename to: ", 0
str_mkdir      db " Folder Name: ", 0
msg_pause      db 13, 10, "--- App Terminated. Press any key ---", 0

str_menu_new   db " New Dir  ", 0
str_menu_ren   db " Rename   ", 0
str_menu_del   db " Delete   ", 0
str_menu_cut   db " Cut (X)  ", 0
str_menu_cpy   db " Copy (C) ", 0
str_menu_pst   db " Paste (V)", 0
str_menu_can   db " Cancel   ", 0

str_assoc      db "ASSOC.PFI", 0

prev_mouse_x      dw 40
prev_mouse_y      dw 12
prev_mouse_attr   dw 0
mouse_btn         db 0

prev_sec          db 0xFF
menu_selected_idx db 0
gui_file_count    db 0
gui_selected_idx  db 0
gui_page          db 0
exec_cmd          times 20 db 0
exec_arg          times 11 db ' '
input_buf         times 16 db 0
new_fat_name      times 12 db 0
gui_file_list     times 224 * 20 db 0
assoc_buffer      times 512 db 0
gui_multi_select  times 224 db 0