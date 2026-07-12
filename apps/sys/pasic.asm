; apps/ext/pasic.asm - PPP BASIC 解释器
[BITS 16]
[ORG 0x0000]

%define MAX_LINES 512
%define LINE_SIZE 64

start:
    cld
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov ah, 0x00
    int 0x1A
    mov [cs:rnd_seed], dx

    mov ah, 0x00
    mov al, 0x03
    int 0x10

    mov si, msg_banner
    call print_str

    call do_new

    ; 获取命令行参数
    mov ah, 0x16
    mov di, arg_buffer
    int 0x80

    mov ah, 0x1D
    mov di, arg2_buffer
    int 0x80

    mov si, arg2_buffer
    cmp byte [si], ' '
    je .skip_arg2
    cmp byte [si], 0
    je .skip_arg2
    call atoi
    mov [vars], ax          ; 参数存入变量A
.skip_arg2:

    ; 有参数则加载脚本执行，否则进入REPL
    cmp byte [arg_buffer], ' '
    je repl
    cmp byte [arg_buffer], 0
    je repl

    mov ah, 0x02
    mov si, arg_buffer
    mov di, file_buffer
    int 0x80
    or al, al
    jz .err_not_found

    mov byte [loaded_from_file], 1
    call parse_script_buffer
    jmp do_run

.err_not_found:
    mov si, msg_not_found
    call print_str
    jmp repl

; 解析脚本缓冲区
parse_script_buffer:
    mov si, file_buffer
.parse_file_loop:
    mov di, input_buf
    mov cx, 80
.copy_line:
    lodsb
    or al, al
    jz .line_done_eof
    cmp al, 13
    je .skip_lf
    cmp al, 10
    je .line_done
    stosb
    dec cx
    jz .line_done
    jmp .copy_line

.skip_lf:
    cmp byte [si], 10
    jne .line_done
    inc si
    jmp .line_done

.line_done_eof:
    call rtrim_and_process
    ret

.line_done:
    push si
    call rtrim_and_process
    pop si
    jmp .parse_file_loop

; 去尾空格后处理行
rtrim_and_process:
.rtrim:
    cmp di, input_buf
    jbe .rtrim_end
    cmp byte [di-1], ' '
    jne .rtrim_end
    dec di
    jmp .rtrim
.rtrim_end:
    mov byte [di], 0
    call process_file_line
    ret

process_file_line:
    pusha
    mov si, input_buf
    call skip_spaces
    cmp byte [si], 0
    je .pf_done

    ; 带行号的行才存储
    mov al, [si]
    cmp al, '0'
    jb .pf_done
    cmp al, '9'
    ja .pf_done

    call atoi
    call skip_spaces
    call store_line
.pf_done:
    popa
    ret

; ==========================================
; REPL 主循环
; ==========================================
repl:
    mov si, msg_prompt
    call print_str

    mov di, input_buf
    call read_line

    mov si, input_buf
    call skip_spaces
    cmp byte [si], 0
    je repl

    mov al, [si]
    cmp al, '0'
    jb .immediate_mode
    cmp al, '9'
    ja .immediate_mode

    ; 行号开头 -> 存储行
    call atoi
    call skip_spaces
    call store_line
    jmp repl

.immediate_mode:
    call uppercase_str

    mov di, cmd_run
    call starts_with
    jc do_run
    mov di, cmd_list
    call starts_with
    jc do_list
    mov di, cmd_new
    call starts_with
    jc do_new_cmd
    mov di, cmd_exit
    call starts_with
    jc do_exit

    mov di, cmd_save
    call starts_with
    jc do_save
    mov di, cmd_load
    call starts_with
    jc do_load
    mov di, cmd_del
    call starts_with
    jc do_del
    mov di, cmd_md
    call starts_with
    jc do_md
    mov di, cmd_cd
    call starts_with
    jc do_cd

    mov si, msg_syn_err
    call print_str
    jmp repl

do_exit:
    mov ah, 0x04
    int 0x80

do_new_cmd:
    call do_new
    jmp repl

do_new:
    mov di, program_area
    mov cx, MAX_LINES * LINE_SIZE
    mov al, 0
    rep stosb
    mov di, vars
    mov cx, 52
    rep stosb
    mov di, user_array
    mov cx, 2048
    rep stosb
    mov di, str_vars
    mov cx, 640
    rep stosb
    mov word [stack_ptr], 0
    ret

do_list:
    mov bx, 0
.list_loop:
    cmp bx, MAX_LINES
    jae .list_done

    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax

    mov ax, [di]
    or ax, ax
    jz .next_line

    call print_int
    mov al, ' '
    call print_char
    mov si, di
    add si, 2
    call print_str
    mov al, 13
    call print_char
    mov al, 10
    call print_char

.next_line:
    inc bx
    jmp .list_loop
.list_done:
    jmp repl

; 文件操作命令封装
do_save:
    add si, 5
    call parse_string_arg
    jc .err
    call sys_save_file
    or al, al
    jz .io_err
    mov si, msg_saved
    call print_str
    jmp repl
.err:
    mov si, msg_syn_err
    call print_str
    jmp repl
.io_err:
    mov si, msg_io_err
    call print_str
    jmp repl

do_load:
    add si, 5
    call parse_string_arg
    jc do_save.err
    call sys_load_file
    or al, al
    jz do_save.io_err
    mov si, msg_ok
    call print_str
    jmp repl

do_del:
    add si, 4
    call parse_string_arg
    jc do_save.err
    mov ah, 0x0C
    mov si, filename_buf
    int 0x80
    or al, al
    jz do_save.io_err
    mov si, msg_ok
    call print_str
    jmp repl

do_md:
    add si, 3
    call parse_string_arg
    jc do_save.err
    mov ah, 0x17
    mov si, filename_buf
    int 0x80
    or al, al
    jz do_save.io_err
    mov si, msg_ok
    call print_str
    jmp repl

do_cd:
    add si, 3
    call parse_string_arg
    jc do_save.err
    mov ah, 0x0E
    mov si, filename_buf
    int 0x80
    or al, al
    jz do_save.io_err
    mov si, msg_ok
    call print_str
    jmp repl

; ==========================================
; 核心执行引擎
; ==========================================
do_run:
    mov word [current_idx], 0
    mov word [stack_ptr], 0

.exec_loop:
    mov bx, [current_idx]
    cmp bx, MAX_LINES
    jae .end_run

    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax

    mov ax, [di]
    or ax, ax
    jz .next_exec

    mov si, di
    add si, 2
    call uppercase_str

.dispatch_cmd:
    call skip_spaces

    mov di, cmd_print
    call starts_with
    jc .exec_print
    mov di, cmd_beep
    call starts_with
    jc .exec_beep
    mov di, cmd_goto
    call starts_with
    jc .exec_goto
    mov di, cmd_let
    call starts_with
    jc .exec_let
    mov di, cmd_add
    call starts_with
    jc .exec_add
    mov di, cmd_sub
    call starts_with
    jc .exec_sub
    mov di, cmd_mul
    call starts_with
    jc .exec_mul
    mov di, cmd_div
    call starts_with
    jc .exec_div
    mov di, cmd_mod
    call starts_with
    jc .exec_mod
    mov di, cmd_if
    call starts_with
    jc .exec_if
    mov di, cmd_mode
    call starts_with
    jc .exec_mode
    mov di, cmd_plot
    call starts_with
    jc .exec_plot
    mov di, cmd_input
    call starts_with
    jc .exec_input
    mov di, cmd_rnd
    call starts_with
    jc .exec_rnd
    mov di, cmd_delay
    call starts_with
    jc .exec_delay
    mov di, cmd_gosub
    call starts_with
    jc .exec_gosub
    mov di, cmd_return
    call starts_with
    jc .exec_return
    mov di, cmd_cls
    call starts_with
    jc .exec_cls
    mov di, cmd_cursor
    call starts_with
    jc .exec_cursor
    mov di, cmd_pchar
    call starts_with
    jc .exec_pchar

    mov di, cmd_mouse
    call starts_with
    jc .exec_mouse
    mov di, cmd_key
    call starts_with
    jc .exec_key
    mov di, cmd_panic
    call starts_with
    jc .exec_panic

    mov di, cmd_peek
    call starts_with
    jc .exec_peek
    mov di, cmd_poke
    call starts_with
    jc .exec_poke
    mov di, cmd_line
    call starts_with
    jc .exec_line
    mov di, cmd_rect
    call starts_with
    jc .exec_rect
    mov di, cmd_circle
    call starts_with
    jc .exec_circle

    mov di, cmd_aset
    call starts_with
    jc .exec_aset
    mov di, cmd_aget
    call starts_with
    jc .exec_aget

    mov di, cmd_fwrite
    call starts_with
    jc .exec_fwrite
    mov di, cmd_fread
    call starts_with
    jc .exec_fread

    mov di, cmd_save
    call starts_with
    jc .exec_save
    mov di, cmd_load
    call starts_with
    jc .exec_load
    mov di, cmd_del
    call starts_with
    jc .exec_del
    mov di, cmd_md
    call starts_with
    jc .exec_md
    mov di, cmd_cd
    call starts_with
    jc .exec_cd

    mov di, cmd_slet
    call starts_with
    jc .exec_slet
    mov di, cmd_sadd
    call starts_with
    jc .exec_sadd
    mov di, cmd_sif
    call starts_with
    jc .exec_sif
    mov di, cmd_inputs
    call starts_with
    jc .exec_inputs

    mov di, cmd_out
    call starts_with
    jc .exec_out
    mov di, cmd_inp
    call starts_with
    jc .exec_inp
    mov di, cmd_comw
    call starts_with
    jc .exec_comw
    mov di, cmd_comr
    call starts_with
    jc .exec_comr

    mov di, cmd_end
    call starts_with
    jc .end_run

.syn_err:
    mov si, msg_syn_err
    call print_str
    jmp .end_run

; ---------- 字符串命令 ----------
.exec_slet:
    add si, 5
    call skip_spaces
    call get_str_var_ptr
    push di
    call skip_spaces
    cmp byte [si], '='
    jne .syn_err
    inc si
    call skip_spaces
    pop di
    call copy_string_val
    jmp .next_exec

.exec_sadd:
    add si, 5
    call skip_spaces
    call get_str_var_ptr
.sadd_find:
    cmp byte [di], 0
    je .sadd_do
    inc di
    jmp .sadd_find
.sadd_do:
    call skip_spaces
    call copy_string_val
    jmp .next_exec

.exec_sif:
    add si, 4
    call skip_spaces
    call get_str_var_ptr
    push di
    call skip_spaces
    cmp byte [si], '='
    jne .syn_err
    inc si
    call skip_spaces
    mov di, tmp_str_buf
    call copy_string_val
    pop di

    push si
    mov si, tmp_str_buf
.sif_cmp:
    lodsb
    mov ah, [di]
    inc di
    cmp al, ah
    jne .sif_false
    or al, al
    jz .sif_true
    jmp .sif_cmp
.sif_false:
    pop si
    jmp .next_exec
.sif_true:
    pop si
    call skip_spaces
    cmp byte [si], 'T'
    jne .sif_disp
    add si, 5
.sif_disp:
    jmp .dispatch_cmd

.exec_inputs:
    add si, 7
    call skip_spaces
    call get_str_var_ptr
    push di
    mov al, '?'
    call print_char
    mov al, ' '
    call print_char
    mov di, input_buf
    call read_line
    pop di
    push si
    mov si, input_buf
.inps_loop:
    lodsb
    stosb
    or al, al
    jnz .inps_loop
    pop si
    jmp .next_exec

; ---------- 基础命令 ----------
.exec_print:
    add si, 5
    call skip_spaces
    cmp byte [si], '"'
    je .print_str_literal
    cmp byte [si], '$'
    je .print_str_var
    call eval_value
    call print_int
    jmp .print_nl
.print_str_literal:
    inc si
.psl_loop:
    lodsb
    cmp al, '"'
    je .print_nl
    or al, al
    jz .print_nl
    call print_char
    jmp .psl_loop
.print_str_var:
    call get_str_var_ptr
    pusha
    mov si, di
    call print_str
    popa
    jmp .print_nl
.print_nl:
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    jmp .next_exec

.exec_pchar:
    add si, 6
    call eval_value
    call print_char
    jmp .next_exec

.exec_beep:
    add si, 4
    call eval_value
    mov bx, ax
    mov ah, 0x19
    mov al, 1
    int 0x80
    mov ah, 0x86
    mov cx, 0x0001
    mov dx, 0x86A0
    int 0x15
    mov ah, 0x19
    mov al, 0
    int 0x80
    jmp .next_exec

.exec_goto:
    add si, 4
    call eval_value
    mov dx, ax
    xor bx, bx
.goto_search:
    cmp bx, MAX_LINES
    jae .goto_err
    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax
    mov ax, [di]
    cmp ax, dx
    je .goto_found
    inc bx
    jmp .goto_search
.goto_found:
    mov [current_idx], bx
    jmp .exec_loop
.goto_err:
    mov si, msg_goto_err
    call print_str
    jmp .end_run

; 变量运算
.exec_let:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call skip_spaces
    cmp byte [si], '='
    jne .syn_err
    inc si
    call eval_value
    call set_var
    jmp .next_exec

.exec_add:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    mov al, cl
    call get_var
    pop dx
    add ax, dx
    call set_var
    jmp .next_exec

.exec_sub:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    mov al, cl
    call get_var
    pop dx
    sub ax, dx
    call set_var
    jmp .next_exec

.exec_mul:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    mov al, cl
    call get_var
    pop bx
    mul bx
    call set_var
    jmp .next_exec

.exec_div:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    mov al, cl
    call get_var
    pop bx
    or bx, bx
    jz .div_zero_err
    xor dx, dx
    div bx
    call set_var
    jmp .next_exec

.exec_mod:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    mov al, cl
    call get_var
    pop bx
    or bx, bx
    jz .div_zero_err
    xor dx, dx
    div bx
    mov ax, dx
    call set_var
    jmp .next_exec
.div_zero_err:
    mov si, msg_div0
    call print_str
    jmp .end_run

.exec_if:
    add si, 3
    call eval_value
    push ax
    call skip_spaces
    mov bl, [si]
    inc si
    call eval_value
    mov dx, ax
    pop ax
    cmp ax, dx
    je .if_eq
    jb .if_lt
    ja .if_gt
    jmp .next_exec
.if_eq:
    cmp bl, '='
    je .if_true
    jmp .next_exec
.if_lt:
    cmp bl, '<'
    je .if_true
    jmp .next_exec
.if_gt:
    cmp bl, '>'
    je .if_true
    jmp .next_exec
.if_true:
    call skip_spaces
    cmp byte [si], 'T'
    jne .if_disp
    add si, 5
.if_disp:
    jmp .dispatch_cmd

; 图形命令
.exec_mode:
    add si, 5
    call eval_value
    
    cli                 
    mov ah, 0x00
    int 0x10
    sti                 
    
    jmp .next_exec

.exec_plot:
    add si, 5
    call eval_value
    push ax
    call eval_value
    push ax
    call eval_value
    mov cx, ax
    pop ax
    mov bx, 320
    mul bx
    pop dx
    add ax, dx
    mov bx, ax
    push es
    mov ax, 0xA000
    mov es, ax
    mov [es:bx], cl
    pop es
    jmp .next_exec

.exec_cls:
    mov ax, 0x0003
    int 0x10
    jmp .next_exec

.exec_cursor:
    add si, 7
    call eval_value
    push ax
    call eval_value
    mov dh, al
    pop ax
    mov dl, al
    mov ah, 0x02
    mov bh, 0
    int 0x10
    jmp .next_exec

.exec_line:
    add si, 5
    call eval_value
    mov [cs:line_x0], ax
    call eval_value
    mov [cs:line_y0], ax
    call eval_value
    mov [cs:line_x1], ax
    call eval_value
    mov [cs:line_y1], ax
    call eval_value
    mov [cs:line_c], al
    call draw_bresenham_line
    jmp .next_exec

.exec_rect:
    add si, 5
    call eval_value
    mov [cs:.rx], ax
    call eval_value
    mov [cs:.ry], ax
    call eval_value
    mov [cs:.rw], ax
    call eval_value
    mov [cs:.rh], ax
    call eval_value
    mov [cs:.rc], al

    pusha
    push es
    mov ax, 0xA000
    mov es, ax
    mov cx, [cs:.rh]
    mov bx, [cs:.ry]
.ry_loop:
    cmp cx, 0
    jle .rdone
    push cx
    mov ax, bx
    mov di, 320
    mul di
    add ax, [cs:.rx]
    mov di, ax
    mov cx, [cs:.rw]
    mov al, [cs:.rc]
    rep stosb
    pop cx
    inc bx
    dec cx
    jmp .ry_loop
.rdone:
    pop es
    popa
    jmp .next_exec

.rx dw 0
.ry dw 0
.rw dw 0
.rh dw 0
.rc db 0

.exec_circle:
    add si, 7
    call eval_value
    mov [cs:circ_x0], ax
    call eval_value
    mov [cs:circ_y0], ax
    call eval_value
    mov [cs:circ_r], ax
    call eval_value
    mov [cs:circ_c], al
    call draw_bresenham_circle
    jmp .next_exec

; I/O 命令
.exec_input:
    add si, 6
    call skip_spaces
    mov cl, [si]
    push cx
    mov al, '?'
    call print_char
    mov al, ' '
    call print_char
    mov di, input_buf
    call read_line
    mov si, input_buf
    call atoi
    pop cx
    call set_var
    jmp .next_exec

.exec_rnd:
    add si, 4
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    push cx
    mov ax, [cs:rnd_seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [cs:rnd_seed], ax
    pop cx
    pop bx
    or bx, bx
    jz .rnd_zero
    xor dx, dx
    div bx
    mov ax, dx
.rnd_zero:
    call set_var
    jmp .next_exec

.exec_delay:
    add si, 6
    call eval_value
    mov bx, 50000
    mul bx
    mov cx, dx
    mov dx, ax
    mov ah, 0x86
    int 0x15
    jmp .next_exec

.exec_gosub:
    add si, 6
    call eval_value
    mov dx, ax
    mov bx, [cs:stack_ptr]
    cmp bx, 32
    jae .stack_err
    mov cx, [cs:current_idx]
    shl bx, 1
    mov [cs:call_stack + bx], cx
    inc word [cs:stack_ptr]
    xor bx, bx
.gs_search:
    cmp bx, MAX_LINES
    jae .goto_err
    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax
    mov ax, [di]
    cmp ax, dx
    je .gs_found
    inc bx
    jmp .gs_search
.gs_found:
    mov [current_idx], bx
    jmp .exec_loop
.stack_err:
    mov si, msg_stack_off
    call print_str
    jmp .end_run

.exec_return:
    mov bx, [cs:stack_ptr]
    or bx, bx
    jz .ret_err
    dec bx
    mov [cs:stack_ptr], bx
    shl bx, 1
    mov cx, [cs:call_stack + bx]
    mov [cs:current_idx], cx
    jmp .next_exec
.ret_err:
    mov si, msg_ret_err
    call print_str
    jmp .end_run

; 硬件交互
.exec_mouse:
    add si, 6
    call skip_spaces
    mov al, [si]
    mov [cs:.var_x], al
    inc si
    call skip_spaces
    mov al, [si]
    mov [cs:.var_y], al
    inc si
    call skip_spaces
    mov al, [si]
    mov [cs:.var_b], al

    mov ah, 0x18
    int 0x80
    shr cx, 1

    mov ax, cx
    mov cl, [cs:.var_x]
    call set_var

    mov ax, dx
    mov cl, [cs:.var_y]
    call set_var

    xor ax, ax
    mov al, bl
    mov cl, [cs:.var_b]
    call set_var
    jmp .next_exec

.var_x db 0
.var_y db 0
.var_b db 0

.exec_key:
    add si, 4
    call skip_spaces
    mov cl, [si]
    push cx
    mov ah, 0x15
    int 0x80
    xor ah, ah
    pop cx
    call set_var
    jmp .next_exec

.exec_panic:
    mov ax, 1
    xor cx, cx
    div cx
    jmp .next_exec

; 内存操作
.exec_peek:
    add si, 5
    call skip_spaces
    mov cl, [si]
    inc si
    call eval_value
    push ax
    call eval_value
    pop dx
    push es
    mov es, dx
    mov bx, ax
    mov al, [es:bx]
    xor ah, ah
    call set_var
    pop es
    jmp .next_exec

.exec_poke:
    add si, 5
    call eval_value
    push ax
    call eval_value
    push ax
    call eval_value
    mov cx, ax
    pop bx
    pop dx
    push es
    mov es, dx
    mov [es:bx], cl
    pop es
    jmp .next_exec

; 数组
.exec_aset:
    add si, 5
    call eval_value
    push ax
    call eval_value
    pop bx
    shl bx, 1
    mov [cs:user_array + bx], ax
    jmp .next_exec

.exec_aget:
    add si, 5
    call eval_value
    push ax
    call skip_spaces
    mov cl, [si]
    pop bx
    shl bx, 1
    mov ax, [cs:user_array + bx]
    call set_var
    jmp .next_exec

; 文件 I/O
.exec_fwrite:
    add si, 7
    call parse_string_arg
    jc .syn_err
    call skip_spaces
    mov al, [si]
    call get_var
    mov [file_buffer], ax
    mov cx, 2
    mov ah, 0x03
    mov si, filename_buf
    mov di, file_buffer
    int 0x80
    jmp .next_exec

.exec_fread:
    add si, 6
    call parse_string_arg
    jc .syn_err
    call skip_spaces
    mov cl, [si]
    push cx
    mov ah, 0x02
    mov si, filename_buf
    mov di, file_buffer
    int 0x80
    pop cx
    mov ax, [file_buffer]
    call set_var
    jmp .next_exec

; 端口/串口
.exec_out:
    add si, 4
    call eval_value
    push ax
    call eval_value
    mov cx, ax
    pop dx
    mov al, cl
    out dx, al
    jmp .next_exec

.exec_inp:
    add si, 4
    call eval_value
    push ax
    call skip_spaces
    mov cl, [si]
    pop dx
    in al, dx
    xor ah, ah
    call set_var
    jmp .next_exec

.exec_comw:
    add si, 9
    call eval_value
    mov ah, 0x01
    int 0x82
    jmp .next_exec

.exec_comr:
    add si, 8
    call skip_spaces
    mov cl, [si]
    push cx
    mov ah, 0x02
    int 0x82
    xor ah, ah
    pop cx
    call set_var
    jmp .next_exec

.exec_save:
    add si, 5
    call parse_string_arg
    jc .syn_err
    call sys_save_file
    jmp .next_exec

.exec_load:
    add si, 5
    call parse_string_arg
    jc .syn_err
    call sys_load_file
    jmp do_run

.exec_del:
    add si, 4
    call parse_string_arg
    jc .syn_err
    mov ah, 0x0C
    mov si, filename_buf
    int 0x80
    jmp .next_exec

.exec_md:
    add si, 3
    call parse_string_arg
    jc .syn_err
    mov ah, 0x17
    mov si, filename_buf
    int 0x80
    jmp .next_exec

.exec_cd:
    add si, 3
    call parse_string_arg
    jc .syn_err
    mov ah, 0x0E
    mov si, filename_buf
    int 0x80
    jmp .next_exec

.next_exec:
    inc word [current_idx]
    jmp .exec_loop

.end_run:
    cmp byte [loaded_from_file], 1
    je do_exit
    jmp repl

; ==========================================
; Bresenham 画线
; ==========================================
draw_bresenham_line:
    pusha
    push es
    mov di, 0xA000
    mov es, di

    mov ax, [cs:line_x1]
    sub ax, [cs:line_x0]
    mov word [cs:line_sx], 1
    cmp ax, 0
    jge .dx_ok
    neg ax
    mov word [cs:line_sx], -1
.dx_ok:
    mov [cs:line_dx], ax

    mov ax, [cs:line_y1]
    sub ax, [cs:line_y0]
    mov word [cs:line_sy], 1
    cmp ax, 0
    jge .dy_ok
    neg ax
    mov word [cs:line_sy], -1
.dy_ok:
    mov [cs:line_dy], ax

    mov ax, [cs:line_dx]
    sub ax, [cs:line_dy]
    mov [cs:line_err], ax

.b_loop:
    mov ax, [cs:line_y0]
    mov bx, 320
    mul bx
    add ax, [cs:line_x0]
    mov bx, ax
    mov al, [cs:line_c]
    mov [es:bx], al

    mov ax, [cs:line_x0]
    cmp ax, [cs:line_x1]
    jne .b_cont
    mov ax, [cs:line_y0]
    cmp ax, [cs:line_y1]
    je .b_done

.b_cont:
    mov ax, [cs:line_err]
    shl ax, 1
    mov bp, ax

    mov ax, [cs:line_dy]
    neg ax
    cmp bp, ax
    jle .b_check_y
    mov ax, [cs:line_err]
    sub ax, [cs:line_dy]
    mov [cs:line_err], ax
    mov ax, [cs:line_x0]
    add ax, [cs:line_sx]
    mov [cs:line_x0], ax

.b_check_y:
    mov ax, [cs:line_dx]
    cmp bp, ax
    jge .b_loop
    mov ax, [cs:line_err]
    add ax, [cs:line_dx]
    mov [cs:line_err], ax
    mov ax, [cs:line_y0]
    add ax, [cs:line_sy]
    mov [cs:line_y0], ax
    jmp .b_loop

.b_done:
    pop es
    popa
    ret

line_x0 dw 0
line_y0 dw 0
line_x1 dw 0
line_y1 dw 0
line_dx dw 0
line_dy dw 0
line_sx dw 0
line_sy dw 0
line_err dw 0
line_c  db 0

; ==========================================
; Bresenham 画圆
; ==========================================
draw_bresenham_circle:
    pusha
    push es
    mov ax, 0xA000
    mov es, ax

    mov ax, [cs:circ_r]
    mov [cs:circ_x], ax
    mov word [cs:circ_y], 0
    mov word [cs:circ_err], 0

.circ_loop:
    mov ax, [cs:circ_x]
    cmp ax, [cs:circ_y]
    jl .circ_done

    call .draw_circ_pixels

    cmp word [cs:circ_err], 0
    jg .circ_check_err_gt
    inc word [cs:circ_y]
    mov ax, [cs:circ_y]
    shl ax, 1
    inc ax
    add [cs:circ_err], ax

.circ_check_err_gt:
    cmp word [cs:circ_err], 0
    jle .circ_loop
    dec word [cs:circ_x]
    mov ax, [cs:circ_x]
    shl ax, 1
    inc ax
    sub [cs:circ_err], ax
    jmp .circ_loop

.circ_done:
    pop es
    popa
    ret

.draw_circ_pixels:
    mov ax, [cs:circ_x]
    mov bx, [cs:circ_y]
    call .plot_pt_sym
    mov ax, [cs:circ_y]
    mov bx, [cs:circ_x]
    call .plot_pt_sym
    ret

.plot_pt_sym:
    pusha
    mov cx, ax
    mov dx, bx
    mov ax, [cs:circ_x0]
    add ax, cx
    mov bx, [cs:circ_y0]
    add bx, dx
    call .put_pixel_safe
    mov ax, [cs:circ_x0]
    sub ax, cx
    mov bx, [cs:circ_y0]
    add bx, dx
    call .put_pixel_safe
    mov ax, [cs:circ_x0]
    add ax, cx
    mov bx, [cs:circ_y0]
    sub bx, dx
    call .put_pixel_safe
    mov ax, [cs:circ_x0]
    sub ax, cx
    mov bx, [cs:circ_y0]
    sub bx, dx
    call .put_pixel_safe
    popa
    ret

.put_pixel_safe:
    cmp ax, 0
    jl .ret
    cmp ax, 319
    jg .ret
    cmp bx, 0
    jl .ret
    cmp bx, 199
    jg .ret
    push ax
    push dx
    mov dx, 320
    xchg ax, bx
    mul dx
    add bx, ax
    mov al, [cs:circ_c]
    mov [es:bx], al
    pop dx
    pop ax
.ret:
    ret

circ_x0 dw 0
circ_y0 dw 0
circ_r  dw 0
circ_c  db 0
circ_x  dw 0
circ_y  dw 0
circ_err dw 0

; ==========================================
; 字符串与变量辅助
; ==========================================
get_str_var_ptr:
    inc si
    mov al, [si]
    inc si
    sub al, '0'
    xor ah, ah
    shl ax, 6
    mov di, str_vars
    add di, ax
    ret

copy_string_val:
    cmp byte [si], '"'
    je .copy_lit
    cmp byte [si], '$'
    je .copy_var
    ret
.copy_lit:
    inc si
.cl_loop:
    lodsb
    cmp al, '"'
    je .cl_done
    or al, al
    jz .cl_done
    stosb
    jmp .cl_loop
.cl_done:
    mov byte [di], 0
    ret
.copy_var:
    inc si
    mov al, [si]
    inc si
    sub al, '0'
    xor ah, ah
    shl ax, 6
    push si
    mov si, str_vars
    add si, ax
.cv_loop:
    lodsb
    or al, al
    jz .cv_done
    stosb
    jmp .cv_loop
.cv_done:
    mov byte [di], 0
    pop si
    ret

eval_value:
    call skip_spaces
    mov al, [si]
    cmp al, 'A'
    jb .is_num
    cmp al, 'Z'
    ja .is_num
    call get_var
    inc si
    ret
.is_num:
    call atoi
    ret

get_var:
    push bx
    sub al, 'A'
    xor ah, ah
    shl ax, 1
    mov bx, vars
    add bx, ax
    mov ax, [bx]
    pop bx
    ret

set_var:
    push bx
    push ax
    mov al, cl
    sub al, 'A'
    xor ah, ah
    shl ax, 1
    mov bx, vars
    add bx, ax
    pop ax
    mov [bx], ax
    pop bx
    ret

store_line:
    pusha
    mov dx, ax
    cmp byte [si], 0
    je .do_delete

    xor bx, bx
.find_exist:
    cmp bx, MAX_LINES
    jae .find_empty
    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax
    cmp [di], dx
    je .do_copy
    inc bx
    jmp .find_exist

.find_empty:
    xor bx, bx
.find_empty_loop:
    cmp bx, MAX_LINES
    jae .mem_full
    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax
    cmp word [di], 0
    je .do_copy
    inc bx
    jmp .find_empty_loop

.do_copy:
    mov [di], dx
    add di, 2
    mov cx, LINE_SIZE - 3
.copy_char:
    lodsb
    stosb
    or al, al
    jz .sort_array
    loop .copy_char
    mov byte [di], 0
    jmp .sort_array

.do_delete:
    xor bx, bx
.del_loop:
    cmp bx, MAX_LINES
    jae .sort_array
    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax
    cmp [di], dx
    jne .del_next
    mov word [di], 0
.del_next:
    inc bx
    jmp .del_loop

.mem_full:
    mov si, msg_mem_err
    call print_str
    popa
    ret

.sort_array:
    mov cx, MAX_LINES - 1
.sort_outer:
    push cx
    xor bx, bx
.sort_inner:
    mov ax, bx
    shl ax, 6
    mov di, program_area
    add di, ax
    mov si, di
    add si, LINE_SIZE

    mov ax, [di]
    mov dx, [si]
    or ax, ax
    jz .swap
    or dx, dx
    jz .no_swap
    cmp ax, dx
    jbe .no_swap

.swap:
    push cx
    mov cx, LINE_SIZE
    mov bp, di
.swap_bytes:
    mov al, [bp]
    mov ah, [si]
    mov [bp], ah
    mov [si], al
    inc bp
    inc si
    loop .swap_bytes
    pop cx

.no_swap:
    inc bx
    loop .sort_inner
    pop cx
    loop .sort_outer
    popa
    ret

parse_string_arg:
    call skip_spaces
    cmp byte [si], '"'
    jne .ps_err
    inc si
    mov di, filename_buf
.ps_loop:
    lodsb
    cmp al, '"'
    je .ps_done
    or al, al
    jz .ps_err
    stosb
    jmp .ps_loop
.ps_done:
    xor al, al
    stosb
    clc
    ret
.ps_err:
    stc
    ret

sys_save_file:
    mov di, file_buffer
    mov bx, 0
.sf_loop:
    cmp bx, MAX_LINES
    jae .sf_done
    mov ax, bx
    shl ax, 6
    mov bp, program_area
    add bp, ax
    mov ax, [bp]
    or ax, ax
    jz .sf_next

    call int_to_str_di
    mov al, ' '
    stosb
    push si
    mov si, bp
    add si, 2
.sf_copy:
    lodsb
    or al, al
    jz .sf_copy_end
    stosb
    jmp .sf_copy
.sf_copy_end:
    pop si
    mov ax, 0x0A0D
    stosw
.sf_next:
    inc bx
    jmp .sf_loop
.sf_done:
    mov byte [di], 0
    mov cx, di
    sub cx, file_buffer
    mov ah, 0x03
    mov si, filename_buf
    mov di, file_buffer
    int 0x80
    ret

sys_load_file:
    pusha
    mov di, file_buffer
    mov cx, 8192
    xor al, al
    rep stosb
    popa

    mov ah, 0x02
    mov si, filename_buf
    mov di, file_buffer
    int 0x80
    or al, al
    jz .load_fail

    call do_new
    call parse_script_buffer
    mov al, 1
    ret
.load_fail:
    xor al, al
    ret

int_to_str_di:
    pusha
    mov cx, 0
    mov bx, 10
.pi_loop1:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .pi_loop1
.pi_loop2:
    pop ax
    add al, '0'
    mov [di], al
    inc di
    loop .pi_loop2
    mov bp, sp
    mov [bp], di
    popa
    ret

read_line:
    pusha
    mov bx, di
.rl_loop:
    mov ah, 0x01
    int 0x80
    cmp al, 13
    je .rl_done
    cmp al, 8
    je .rl_bs
    cmp al, ' '
    jb .rl_loop
    cmp al, '~'
    ja .rl_loop
    stosb
    mov ah, 0x0E
    int 0x10
    jmp .rl_loop
.rl_bs:
    cmp di, bx
    jbe .rl_loop
    dec di
    mov ah, 0x0E
    mov al, 8
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 8
    int 0x10
    jmp .rl_loop
.rl_done:
    mov byte [di], 0
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    popa
    ret

print_str:
    pusha
.ps_loop:
    lodsb
    or al, al
    jz .ps_done
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    jmp .ps_loop
.ps_done:
    popa
    ret

print_char:
    pusha
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    popa
    ret

skip_spaces:
.sl:
    cmp byte [si], ' '
    jne .sd
    inc si
    jmp .sl
.sd:ret

starts_with:
    pusha
.sw_loop:
    mov al, [di]
    or al, al
    jz .sw_match
    mov ah, [si]
    cmp al, ah
    jne .sw_fail
    inc si
    inc di
    jmp .sw_loop
.sw_match:
    popa
    stc
    ret
.sw_fail:
    popa
    clc
    ret

uppercase_str:
    pusha
    mov di, si
.up_loop:
    mov al, [di]
    or al, al
    jz .up_done
    cmp al, 'a'
    jb .up_next
    cmp al, 'z'
    ja .up_next
    sub al, 32
    mov [di], al
.up_next:
    inc di
    jmp .up_loop
.up_done:
    popa
    ret

atoi:
    push bx
    push cx
    xor ax, ax
    xor cx, cx
.at_loop:
    mov cl, [si]
    cmp cl, '0'
    jb .at_done
    cmp cl, '9'
    ja .at_done
    sub cl, '0'
    mov bx, 10
    mul bx
    add ax, cx
    inc si
    jmp .at_loop
.at_done:
    pop cx
    pop bx
    ret

print_int:
    pusha
    mov cx, 0
    mov bx, 10
.pi_loop1:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .pi_loop1
.pi_loop2:
    pop ax
    add al, '0'
    call print_char
    loop .pi_loop2
    popa
    ret

; ==========================================
; 消息与常量
; ==========================================
msg_banner    db "PASIC V1.5 BETA", 13, 10, "Ready.", 13, 10, 0
msg_prompt    db "> ", 0
msg_syn_err   db "Syntax Error", 13, 10, 0
msg_goto_err  db "Error: Line not found!", 13, 10, 0
msg_mem_err   db "Out of Memory", 13, 10, 0
msg_not_found db "Error: Script file not found!", 13, 10, 0
msg_div0      db "Math Error: Divide by zero!", 13, 10, 0
msg_stack_off db "Stack Error: GOSUB overflow!", 13, 10, 0
msg_ret_err   db "Stack Error: RETURN without GOSUB!", 13, 10, 0
msg_ok        db "OK.", 13, 10, 0
msg_io_err    db "I/O Error: Operation Failed!", 13, 10, 0
msg_saved     db "Program successfully saved to disk.", 13, 10, 0

cmd_run     db "RUN", 0
cmd_list    db "LIST", 0
cmd_new     db "NEW", 0
cmd_exit    db "EXIT", 0

cmd_print   db "PRINT ", 0
cmd_beep    db "BEEP ", 0
cmd_goto    db "GOTO ", 0
cmd_let     db "LET ", 0
cmd_add     db "ADD ", 0
cmd_sub     db "SUB ", 0
cmd_mul     db "MUL ", 0
cmd_div     db "DIV ", 0
cmd_mod     db "MOD ", 0
cmd_if      db "IF ", 0
cmd_mode    db "MODE ", 0
cmd_plot    db "PLOT ", 0
cmd_input   db "INPUT ", 0
cmd_rnd     db "RND ", 0
cmd_delay   db "DELAY ", 0
cmd_gosub   db "GOSUB ", 0
cmd_return  db "RETURN", 0
cmd_cls     db "CLS", 0
cmd_cursor  db "CURSOR ", 0
cmd_pchar   db "PCHAR ", 0
cmd_end     db "END", 0

cmd_mouse   db "MOUSE ", 0
cmd_key     db "KEY ", 0
cmd_panic   db "PANIC", 0
cmd_save    db "SAVE ", 0
cmd_load    db "LOAD ", 0
cmd_del     db "DEL ", 0
cmd_md      db "MD ", 0
cmd_cd      db "CD ", 0

cmd_peek    db "PEEK ", 0
cmd_poke    db "POKE ", 0
cmd_line    db "LINE ", 0
cmd_rect    db "RECT ", 0
cmd_circle  db "CIRCLE ", 0
cmd_fwrite  db "FWRITE ", 0
cmd_fread   db "FREAD ", 0
cmd_aset    db "ASET ", 0
cmd_aget    db "AGET ", 0

cmd_slet    db "SLET ", 0
cmd_sadd    db "SADD ", 0
cmd_sif     db "SIF ", 0
cmd_inputs  db "INPUT$ ", 0

cmd_out     db "OUT ", 0
cmd_inp     db "INP ", 0
cmd_comw    db "COMWRITE ", 0
cmd_comr    db "COMREAD ", 0

rnd_seed         dw 0
loaded_from_file db 0
current_idx      dw 0
stack_ptr        dw 0
call_stack       times 32 dw 0
vars             times 26 dw 0
arg_buffer       times 11 db ' '
arg2_buffer      times 11 db ' '
filename_buf     times 16 db 0
input_buf        times 128 db 0
program_area     times MAX_LINES * LINE_SIZE db 0

user_array       times 1024 dw 0
str_vars         times 10 * 64 db 0
tmp_str_buf      times 64 db 0
file_buffer      equ $