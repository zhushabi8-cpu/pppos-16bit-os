[BITS 16]
[ORG 0x0000]
%define IN_BUF  0x4000
%define OUT_BUF 0x8000
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov si, msg_banner
    call print_str
    mov ah, 0x16
    mov di, in_filename
    int 0x80
    cmp byte [in_filename], ' '
    jbe .usage
    mov si, in_filename
    mov di, out_filename
.copy_name:
    lodsb
    cmp al, '.'
    je .ext_found
    cmp al, ' '
    je .ext_found
    or al, al
    jz .ext_found
    stosb
    jmp .copy_name
.ext_found:
    mov al, '.'
    stosb
    mov al, 'A'
    stosb
    mov al, 'S'
    stosb
    mov al, 'M'
    stosb
    xor al, al
    stosb
    mov ah, 0x02
    mov si, in_filename
    mov di, IN_BUF
    int 0x80
    or al, al
    jz .err_read
    mov word [out_ptr], OUT_BUF
    mov word [str_cnt], 0
    mov si, asm_header
    call write_out_str
    mov si, asm_start_lbl
    call write_out_str
    mov si, asm_lib_all
    call write_out_str
    mov si, asm_real_start_lbl
    call write_out_str
    mov si, IN_BUF
.parse_loop:
    call skip_spaces
    lodsb
    or al, al
    jz .parse_done
    cmp al, 13
    je .parse_loop
    cmp al, 10
    je .parse_loop
    dec si
    mov di, tmp_line
    call read_token
    mov al, 'l'
    call write_out_char
    mov al, '_'
    call write_out_char
    push si
    mov si, tmp_line
    call write_out_str
    pop si
    mov al, ':'
    call write_out_char
    call write_out_nl
    call skip_spaces
    mov di, tmp_cmd
    call read_token
    mov al, [tmp_cmd]
    cmp al, 'A'
    je .r_A
    cmp al, 'B'
    je .r_B
    cmp al, 'C'
    je .r_C
    cmp al, 'D'
    je .r_D
    cmp al, 'E'
    je .r_E
    cmp al, 'F'
    je .r_F
    cmp al, 'G'
    je .r_G
    cmp al, 'I'
    je .r_I
    cmp al, 'K'
    je .r_K
    cmp al, 'L'
    je .r_L
    cmp al, 'M'
    je .r_M
    cmp al, 'O'
    je .r_O
    cmp al, 'P'
    je .r_P
    cmp al, 'R'
    je .r_R
    cmp al, 'S'
    je .r_S
    cmp al, 'T'
    je .r_T
    cmp al, 'Y'
    je .r_Y
    jmp .skip_line
.r_A:
    mov di, cmd_add
    call match_cmd
    jc .do_add
    mov di, cmd_aset
    call match_cmd
    jc .do_aset
    mov di, cmd_aget
    call match_cmd
    jc .do_aget
    jmp .skip_line
.r_B:
    mov di, cmd_beep
    call match_cmd
    jc .do_beep
    mov di, cmd_buffer
    call match_cmd
    jc .do_buffer
    jmp .skip_line
.r_C:
    mov di, cmd_cls
    call match_cmd
    jc .do_cls
    mov di, cmd_circle
    call match_cmd
    jc .do_circle
    mov di, cmd_cursor
    call match_cmd
    jc .do_cursor
    mov di, cmd_cd
    call match_cmd
    jc .do_cd
    mov di, cmd_comw
    call match_cmd
    jc .do_comw
    mov di, cmd_comr
    call match_cmd
    jc .do_comr
    jmp .skip_line
.r_D:
    mov di, cmd_div
    call match_cmd
    jc .do_div
    mov di, cmd_delay
    call match_cmd
    jc .do_delay
    mov di, cmd_del
    call match_cmd
    jc .do_del
    jmp .skip_line
.r_E:
    mov di, cmd_end
    call match_cmd
    jc .do_end
    jmp .skip_line
.r_F:
    mov di, cmd_frect
    call match_cmd
    jc .do_frect
    mov di, cmd_flip
    call match_cmd
    jc .do_flip
    mov di, cmd_fread
    call match_cmd
    jc .do_fread
    mov di, cmd_fwrite
    call match_cmd
    jc .do_fwrite
    jmp .skip_line
.r_G:
    mov di, cmd_goto
    call match_cmd
    jc .do_goto
    mov di, cmd_gosub
    call match_cmd
    jc .do_gosub
    jmp .skip_line
.r_I:
    mov di, cmd_inputs
    call match_cmd
    jc .do_inputs
    mov di, cmd_input
    call match_cmd
    jc .do_input
    mov di, cmd_if
    call match_cmd
    jc .do_if
    mov di, cmd_inp
    call match_cmd
    jc .do_inp
    mov di, cmd_insmod
    call match_cmd
    jc .do_insmod
    jmp .skip_line
.r_K:
    mov di, cmd_key
    call match_cmd
    jc .do_key
    jmp .skip_line
.r_L:
    mov di, cmd_let
    call match_cmd
    jc .do_let
    mov di, cmd_line
    call match_cmd
    jc .do_line
    jmp .skip_line
.r_M:
    mov di, cmd_mul
    call match_cmd
    jc .do_mul
    mov di, cmd_mod
    call match_cmd
    jc .do_mod
    mov di, cmd_mode
    call match_cmd
    jc .do_mode
    mov di, cmd_mouse
    call match_cmd
    jc .do_mouse
    mov di, cmd_md
    call match_cmd
    jc .do_md
    jmp .skip_line
.r_O:
    mov di, cmd_out
    call match_cmd
    jc .do_out
    jmp .skip_line
.r_P:
    mov di, cmd_print
    call match_cmd
    jc .do_print
    mov di, cmd_plot
    call match_cmd
    jc .do_plot
    mov di, cmd_pchar
    call match_cmd
    jc .do_pchar
    mov di, cmd_panic
    call match_cmd
    jc .do_panic
    mov di, cmd_peek
    call match_cmd
    jc .do_peek
    mov di, cmd_poke
    call match_cmd
    jc .do_poke
    jmp .skip_line
.r_R:
    mov di, cmd_return
    call match_cmd
    jc .do_return
    mov di, cmd_rect
    call match_cmd
    jc .do_rect
    mov di, cmd_rnd
    call match_cmd
    jc .do_rnd
    jmp .skip_line
.r_S:
    mov di, cmd_sub
    call match_cmd
    jc .do_sub
    mov di, cmd_slet
    call match_cmd
    jc .do_slet
    mov di, cmd_sadd
    call match_cmd
    jc .do_sadd
    mov di, cmd_sif
    call match_cmd
    jc .do_sif
    mov di, cmd_sleep
    call match_cmd
    jc .do_sleep
    jmp .skip_line
.r_T:
    mov di, cmd_ticks
    call match_cmd
    jc .do_ticks
    jmp .skip_line
.r_Y:
    mov di, cmd_yield
    call match_cmd
    jc .do_yield
    jmp .skip_line
.skip_line:
    lodsb
    or al, al
    jz .parse_done
    cmp al, 10
    jne .skip_line
    jmp .parse_loop
.do_end:
    push si
    mov si, asm_end
    call write_out_str
    pop si
    jmp .skip_line
.do_yield:
    push si
    mov si, asm_call_yield
    call write_out_str
    pop si
    jmp .skip_line
.do_return:
    push si
    mov si, asm_ret
    call write_out_str
    pop si
    jmp .skip_line
.do_gosub:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_call_lbl
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    call write_out_nl
    pop si
    jmp .skip_line
.do_goto:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_goto_pre
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    call write_out_nl
    pop si
    jmp .skip_line
.do_sleep:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_bx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_sleep
    call write_out_str
    pop si
    jmp .skip_line
.do_ticks:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_call_ticks
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_panic:
    push si
    mov si, asm_call_panic
    call write_out_str
    pop si
    jmp .skip_line
.do_aset:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    call skip_spaces
    mov di, tmp_arg2
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_add_ax_ax
    call write_out_str
    mov si, asm_mov_bx_ax
    call write_out_str
    mov si, asm_mov_di_arr
    call write_out_str
    mov si, asm_add_di_bx
    call write_out_str
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg2
    call write_arg
    call write_out_nl
    mov si, asm_mov_di_mem_ax
    call write_out_str
    pop si
    jmp .skip_line
.do_aget:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_add_ax_ax
    call write_out_str
    mov si, asm_mov_bx_ax
    call write_out_str
    mov si, asm_mov_di_arr
    call write_out_str
    mov si, asm_add_di_bx
    call write_out_str
    mov si, asm_mov_ax_di_mem
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_slet:
    call skip_spaces
    lodsb
    lodsb
    mov [tmp_var], al
    call skip_spaces
    cmp byte [si], '='
    jne .slet_chk_quote
    inc si
    call skip_spaces
.slet_chk_quote:
    cmp byte [si], '"'
    je .slet_str_lit
    lodsb
    lodsb
    mov [tmp_var2], al
    push si
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var2]
    call write_out_char
    call write_out_nl
    mov si, asm_call_get_str
    call write_out_str
    mov si, asm_mov_si_di
    call write_out_str
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_slet
    call write_out_str
    pop si
    jmp .skip_line
.slet_str_lit:
    inc si
    mov di, tmp_arg1
.slet_lp:
    lodsb
    cmp al, '"'
    je .slet_dn
    cmp al, 13
    je .slet_dn
    or al, al
    jz .slet_dn
    stosb
    jmp .slet_lp
.slet_dn:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_slet
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_sadd:
    call skip_spaces
    lodsb
    lodsb
    mov [tmp_var], al
    call skip_spaces
    cmp byte [si], '='
    jne .sadd_chk_quote
    inc si
    call skip_spaces
.sadd_chk_quote:
    cmp byte [si], '"'
    je .sadd_str_lit
    lodsb
    lodsb
    mov [tmp_var2], al
    push si
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var2]
    call write_out_char
    call write_out_nl
    mov si, asm_call_get_str
    call write_out_str
    mov si, asm_mov_si_di
    call write_out_str
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_sadd
    call write_out_str
    pop si
    jmp .skip_line
.sadd_str_lit:
    inc si
    mov di, tmp_arg1
.sadd_lp:
    lodsb
    cmp al, '"'
    je .sadd_dn
    cmp al, 13
    je .sadd_dn
    or al, al
    jz .sadd_dn
    stosb
    jmp .sadd_lp
.sadd_dn:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_sadd
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_sif:
    call skip_spaces
    lodsb
    lodsb
    mov [tmp_var], al
    call skip_spaces
    lodsb
    call skip_spaces
    inc si
    mov di, tmp_arg1
.sif_lp:
    lodsb
    cmp al, '"'
    je .sif_dn
    cmp al, 13
    je .sif_dn
    or al, al
    jz .sif_dn
    stosb
    jmp .sif_lp
.sif_dn:
    mov byte [di], 0
    call skip_spaces
    mov di, tmp_arg2
    call read_token
    cmp byte [tmp_arg2], 'T'
    jne .sif_got
    call skip_spaces
    mov di, tmp_arg2
    call read_token
.sif_got:
    call skip_spaces
    mov di, tmp_arg2
    call read_token
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_scmp
    call write_out_str
    mov si, asm_je
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_jmp_iff
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_ift_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_goto_pre
    call write_out_str
    mov si, tmp_arg2
    call write_out_str
    call write_out_nl
    mov si, asm_iff_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_inputs:
    call skip_spaces
    lodsb
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_inputs
    call write_out_str
    pop si
    jmp .skip_line
.do_mode:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_mode
    call write_out_str
    pop si
    jmp .skip_line
.do_buffer:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    cmp byte [tmp_arg1], '1'
    jne .b_off
    mov si, asm_buf_1
    call write_out_str
    pop si
    jmp .skip_line
.b_off:
    mov si, asm_buf_0
    call write_out_str
    pop si
    jmp .skip_line
.do_flip:
    push si
    mov si, asm_call_flip
    call write_out_str
    pop si
    jmp .skip_line
.do_delay:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    cmp byte [tmp_arg1], 0
    jne .d_has_arg
    mov byte [tmp_arg1], '1'
    mov byte [tmp_arg1+1], 0
.d_has_arg:
    mov si, asm_mov_bx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_delay
    call write_out_str
    pop si
    jmp .skip_line
.do_beep:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    cmp byte [tmp_arg1], 0
    jne .b_has_arg
    mov byte [tmp_arg1], '1'
    mov byte [tmp_arg1+1], '0'
    mov byte [tmp_arg1+2], '0'
    mov byte [tmp_arg1+3], '0'
    mov byte [tmp_arg1+4], 0
.b_has_arg:
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_beep
    call write_out_str
    pop si
    jmp .skip_line
.do_cls:
    push si
    mov si, asm_call_cls
    call write_out_str
    pop si
    jmp .skip_line
.do_cursor:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    call skip_spaces
    mov di, tmp_arg2
    call read_token
    push si
    mov si, asm_mov_dx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg2
    call write_arg
    call write_out_nl
    mov si, asm_call_cursor
    call write_out_str
    pop si
    jmp .skip_line
.do_pchar:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_pchar
    call write_out_str
    pop si
    jmp .skip_line
.do_mouse:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    lodsb
    mov [tmp_var2], al
    call skip_spaces
    lodsb
    mov [tmp_op], al
    push si
    mov si, asm_call_mouse
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post_cx
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var2]
    call write_var_addr
    mov si, asm_mov_var_post_dx
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_op]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_key:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_call_key
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_plot:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_push_ax
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_push_ax
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_plot
    call write_out_str
    pop si
    jmp .skip_line
.do_frect:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_cx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_dx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_si
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_di
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_frect
    call write_out_str
    pop si
    jmp .skip_line
.do_rect:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_sq_u
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_sq_v
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_sq_w
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_sq_z
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_sq_c
    call write_out_str
    mov si, asm_call_sqr
    call write_out_str
    pop si
    jmp .skip_line
.do_line:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_line_u0
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_line_v0
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_line_u1
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_line_v1
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_line_c
    call write_out_str
    mov si, asm_call_line
    call write_out_str
    pop si
    jmp .skip_line
.do_circle:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_circ_u0
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_circ_v0
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_circ_r
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_circ_c
    call write_out_str
    mov si, asm_call_circle
    call write_out_str
    pop si
    jmp .skip_line
.do_let:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    lodsb
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    call skip_spaces
    mov al, [si]
    cmp al, 13
    je .let_simple
    cmp al, 10
    je .let_simple
    cmp al, 0
    je .let_simple
    lodsb
    mov [tmp_op], al
    call skip_spaces
    push si
    mov si, tmp_arg1
    mov di, tmp_arg2
.cpy_a1: lodsb
    stosb
    or al, al
    jnz .cpy_a1
    pop si
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg2
    call write_arg
    call write_out_nl
    cmp byte [tmp_op], '+'
    jne .let_sub
    mov si, asm_add_ax
    jmp .let_wop
.let_sub:
    mov si, asm_sub_ax
.let_wop:
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    jmp .let_save
.let_simple:
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
.let_save:
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_add:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax_var
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    call write_out_nl
    mov si, asm_add_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_sub:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax_var
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    call write_out_nl
    mov si, asm_sub_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_mul:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax_var
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    call write_out_nl
    mov si, asm_mov_bx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_mul_bx
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_div:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax_var
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    call write_out_nl
    mov si, asm_mov_bx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_xor_dx
    call write_out_str
    mov si, asm_div_bx
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_mod:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax_var
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    call write_out_nl
    mov si, asm_mov_bx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_xor_dx
    call write_out_str
    mov si, asm_div_bx
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post_dx
    call write_out_str
    pop si
    jmp .skip_line
.do_rnd:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_bx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_rnd
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_out:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_dx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_out
    call write_out_str
    pop si
    jmp .skip_line
.do_inp:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_mov_dx
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_inp
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_peek:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_push_ax
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_peek
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_poke:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_push_ax
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_push_ax
    call write_out_str
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_poke
    call write_out_str
    pop si
    jmp .skip_line
.do_print:
    call skip_spaces
    cmp byte [si], '"'
    je .pr_str_lit
    cmp byte [si], '$'
    je .pr_str_var
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_print_call
    call write_out_str
    pop si
    jmp .skip_line
.pr_str_lit:
    inc si
    mov di, tmp_arg1
.pr_s_loop:
    lodsb
    cmp al, '"'
    je .pr_s_dn
    cmp al, 13
    je .pr_s_dn
    or al, al
    jz .pr_s_dn
    stosb
    jmp .pr_s_loop
.pr_s_dn:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_nl_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_print_int80
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.pr_str_var:
    inc si
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_mov_al
    call write_out_str
    mov al, [tmp_var]
    call write_out_char
    call write_out_nl
    mov si, asm_call_get_str
    call write_out_str
    mov si, asm_mov_si_di
    call write_out_str
    mov si, asm_print_int80
    call write_out_str
    pop si
    jmp .skip_line
.do_input:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_call_input
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.do_if:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    lodsb
    mov [tmp_op], al
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_cmp_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    pop si
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    cmp byte [tmp_arg1], 'T'
    jne .if_got
    call skip_spaces
    mov di, tmp_arg1
    call read_token
.if_got:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov al, [tmp_op]
    cmp al, '='
    je .if_e
    cmp al, '<'
    je .if_l
    mov si, asm_jg
    jmp .if_w
.if_e: mov si, asm_je
    jmp .if_w
.if_l: mov si, asm_jl
.if_w: call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_jmp_iff
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_ift_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_goto_pre
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    call write_out_nl
    mov si, asm_iff_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_fread:
    call skip_spaces
    cmp byte [si], '"'
    jne .skip_line
    inc si
    mov di, tmp_arg1
.fread_str:
    lodsb
    cmp al, '"'
    je .fread_var
    or al, al
    jz .skip_line
    stosb
    jmp .fread_str
.fread_var:
    mov byte [di], 0
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_call_fread
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_fwrite:
    call skip_spaces
    cmp byte [si], '"'
    jne .skip_line
    inc si
    mov di, tmp_arg1
.fwrite_str:
    lodsb
    cmp al, '"'
    je .fwrite_var
    or al, al
    jz .skip_line
    stosb
    jmp .fwrite_str
.fwrite_var:
    mov byte [di], 0
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_mov_ax_var
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    call write_out_nl
    mov si, asm_call_fwrite
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_insmod:
    call skip_spaces
    cmp byte [si], '"'
    jne .skip_line
    inc si
    mov di, tmp_arg1
.insmod_str:
    lodsb
    cmp al, '"'
    je .insmod_gen
    or al, al
    jz .skip_line
    stosb
    jmp .insmod_str
.insmod_gen:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_call_insmod
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_cd:
    call skip_spaces
    cmp byte [si], '"'
    jne .skip_line
    inc si
    mov di, tmp_arg1
.cd_str:
    lodsb
    cmp al, '"'
    je .cd_gen
    or al, al
    jz .skip_line
    stosb
    jmp .cd_str
.cd_gen:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_call_cd
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_md:
    call skip_spaces
    cmp byte [si], '"'
    jne .skip_line
    inc si
    mov di, tmp_arg1
.md_str:
    lodsb
    cmp al, '"'
    je .md_gen
    or al, al
    jz .skip_line
    stosb
    jmp .md_str
.md_gen:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_call_md
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_del:
    call skip_spaces
    cmp byte [si], '"'
    jne .skip_line
    inc si
    mov di, tmp_arg1
.del_str:
    lodsb
    cmp al, '"'
    je .del_gen
    or al, al
    jz .skip_line
    stosb
    jmp .del_str
.del_gen:
    mov byte [di], 0
    push si
    mov si, asm_jmp_skip
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_str_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_db_quote
    call write_out_str
    mov si, tmp_arg1
    call write_out_str
    mov si, asm_quote_0
    call write_out_str
    mov si, asm_skip_lbl
    call write_out_str
    call write_str_cnt
    mov si, asm_colon_nl
    call write_out_str
    mov si, asm_mov_si_str
    call write_out_str
    call write_str_cnt
    call write_out_nl
    mov si, asm_call_del
    call write_out_str
    inc word [str_cnt]
    pop si
    jmp .skip_line
.do_comw:
    call skip_spaces
    mov di, tmp_arg1
    call read_token
    push si
    mov si, asm_mov_ax
    call write_out_str
    mov si, tmp_arg1
    call write_arg
    call write_out_nl
    mov si, asm_call_comw
    call write_out_str
    pop si
    jmp .skip_line
.do_comr:
    call skip_spaces
    lodsb
    mov [tmp_var], al
    push si
    mov si, asm_call_comr
    call write_out_str
    mov si, asm_mov_var_pre
    call write_out_str
    mov al, [tmp_var]
    call write_var_addr
    mov si, asm_mov_var_post
    call write_out_str
    pop si
    jmp .skip_line
.parse_done:
    mov cx, [out_ptr]
    sub cx, OUT_BUF
    mov ah, 0x03
    mov si, out_filename
    mov di, OUT_BUF
    int 0x80
    mov si, msg_ok
    call print_str
    mov si, out_filename
    call print_str
    mov si, msg_nl
    call print_str
    mov ah, 0x04
    int 0x80
.usage:
    mov si, msg_usage
    call print_str
    mov ah, 0x04
    int 0x80
.err_read:
    mov si, msg_err
    call print_str
    mov ah, 0x04
    int 0x80
write_var_addr:
    pusha
    sub al, 'A'
    xor ah, ah
    shl ax, 1
    add ax, 32256
    mov cx, 0
    mov bx, 10
.l1: xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .l1
.l2: pop ax
    add al, 48
    call write_out_char
    loop .l2
    popa
    ret
write_arg:
    mov di, si
    cmp byte [di], 0
    je .is_empty
    cmp byte [di+1], 0
    jne .is_num
    mov al, [di]
    cmp al, 'A'
    jb .is_num
    cmp al, 'Z'
    ja .is_num
    mov si, asm_bracket_var
    call write_out_str
    mov al, [di]
    call write_var_addr
    mov si, asm_close_bracket
    call write_out_str
    ret
.is_empty:
    mov al, '0'
    call write_out_char
    ret
.is_num:
    mov si, di
    call write_out_str
    ret
write_str_cnt:
    pusha
    mov ax, [str_cnt]
    mov cx, 0
    mov bx, 10
.l1: xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .l1
.l2: pop ax
    add al, 48
    call write_out_char
    loop .l2
    popa
    ret
skip_spaces:
    mov al, [si]
    cmp al, ' '
    je .do_skip
    cmp al, 9
    je .do_skip
    ret
.do_skip: inc si
    jmp skip_spaces
read_token:
.rt_loop:
    lodsb
    cmp al, ' '
    jbe .rt_done
    stosb
    jmp .rt_loop
.rt_done:
    dec si
    mov byte [di], 0
    ret
match_cmd:
    pusha
    mov si, tmp_cmd
.mc_loop:
    mov al, [di]
    or al, al
    jz .mc_chk_end
    mov ah, [si]
    cmp al, ah
    jne .mc_fail
    inc si
    inc di
    jmp .mc_loop
.mc_chk_end:
    mov ah, [si]
    or ah, ah
    jz .mc_ok
.mc_fail: popa
    clc
    ret
.mc_ok: popa
    stc
    ret
write_out_str:
    push ax
    push di
    mov di, [out_ptr]
.ws_loop:
    lodsb
    or al, al
    jz .ws_done
    stosb
    jmp .ws_loop
.ws_done:
    mov [out_ptr], di
    pop di
    pop ax
    ret
write_out_char:
    push di
    mov di, [out_ptr]
    stosb
    mov [out_ptr], di
    pop di
    ret
write_out_nl:
    mov al, 13
    call write_out_char
    mov al, 10
    call write_out_char
    ret
print_str:
    pusha
    mov ah, 0x00
    int 0x80
    popa
    ret
msg_banner  db "PAS2ASM Native AOT", 13, 10, 0
msg_usage   db "Usage: PAS2ASM <file.pas>", 13, 10, 0
msg_err     db "Error reading file!", 13, 10, 0
msg_ok      db "Successfully compiled to: ", 0
msg_nl      db 13, 10, 0
cmd_let     db "LET", 0
cmd_add     db "ADD", 0
cmd_sub     db "SUB", 0
cmd_mul     db "MUL", 0
cmd_div     db "DIV", 0
cmd_mod     db "MOD", 0
cmd_aset    db "ASET", 0
cmd_aget    db "AGET", 0
cmd_slet    db "SLET", 0
cmd_sadd    db "SADD", 0
cmd_sif     db "SIF", 0
cmd_inputs  db "INPUT$", 0
cmd_print   db "PRINT", 0
cmd_goto    db "GOTO", 0
cmd_gosub   db "GOSUB", 0
cmd_return  db "RETURN", 0
cmd_end     db "END", 0
cmd_input   db "INPUT", 0
cmd_if      db "IF", 0
cmd_mode    db "MODE", 0
cmd_buffer  db "BUFFER", 0
cmd_flip    db "FLIP", 0
cmd_frect   db "FRECT", 0
cmd_circle  db "CIRCLE", 0
cmd_delay   db "DELAY", 0
cmd_sleep   db "SLEEP", 0
cmd_yield   db "YIELD", 0
cmd_beep    db "BEEP", 0
cmd_cls     db "CLS", 0
cmd_plot    db "PLOT", 0
cmd_line    db "LINE", 0
cmd_rect    db "RECT", 0
cmd_key     db "KEY", 0
cmd_mouse   db "MOUSE", 0
cmd_ticks   db "TICKS", 0
cmd_cursor  db "CURSOR", 0
cmd_pchar   db "PCHAR", 0
cmd_out     db "OUT", 0
cmd_inp     db "INP", 0
cmd_rnd     db "RND", 0
cmd_peek    db "PEEK", 0
cmd_poke    db "POKE", 0
cmd_panic   db "PANIC", 0
cmd_fread   db "FREAD", 0
cmd_fwrite  db "FWRITE", 0
cmd_del     db "DEL", 0
cmd_md      db "MD", 0
cmd_cd      db "CD", 0
cmd_comw    db "COMWRITE", 0
cmd_comr    db "COMREAD", 0
cmd_insmod  db "INSMOD", 0
in_filename  times 16 db 0
out_filename times 16 db 0
out_ptr      dw 0
str_cnt      dw 0
tmp_line     times 16 db 0
tmp_cmd      times 16 db 0
tmp_arg1     times 32 db 0
tmp_arg2     times 32 db 0
tmp_var      db 0
tmp_var2     db 0
tmp_op       db 0
asm_header           db "jmp ppp_start", 13, 10, "draw_seg: dw 0xA000", 13, 10, 0
asm_start_lbl        db "ppp_start:", 13, 10, "  jmp real_start", 13, 10, 0
asm_real_start_lbl   db "real_start:", 13, 10, "  push cs", 13, 10, "  pop ds", 13, 10, "  push cs", 13, 10, "  pop es", 13, 10, 0
asm_bracket_var      db "[", 0
asm_close_bracket    db "]", 0
asm_mov_ax        db "  mov ax,", 0
asm_mov_bx        db "  mov bx,", 0
asm_mov_cx        db "  mov cx,", 0
asm_mov_dx        db "  mov dx,", 0
asm_mov_si        db "  mov si,", 0
asm_mov_di        db "  mov di,", 0
asm_mov_al        db "  mov al,", 0
asm_mov_si_di     db "  mov si,di", 13, 10, 0
asm_mov_var_pre   db "  mov [", 0
asm_mov_var_post  db "],ax", 13, 10, 0
asm_mov_var_post_cx db "],cx", 13, 10, 0
asm_mov_var_post_dx db "],dx", 13, 10, 0
asm_mov_ax_var    db "  mov ax,[", 0
asm_add_ax        db "  add ax,", 0
asm_sub_ax        db "  sub ax,", 0
asm_mul_bx        db "  mul bx", 13, 10, 0
asm_div_bx        db "  div bx", 13, 10, 0
asm_xor_dx        db "  xor dx,dx", 13, 10, 0
asm_cmp_ax        db "  cmp ax,", 0
asm_je            db "  je ift_", 0
asm_jl            db "  jl ift_", 0
asm_jg            db "  jg ift_", 0
asm_ift_lbl       db "ift_", 0
asm_iff_lbl       db "iff_", 0
asm_jmp_iff       db "  jmp iff_", 0
asm_goto_pre      db "  jmp l_", 0
asm_call_lbl      db "  call l_", 0
asm_ret           db "  ret", 13, 10, 0
asm_push_ax       db "  push ax", 13, 10, 0
asm_add_ax_ax     db "  add ax,ax", 13, 10, 0
asm_mov_bx_ax     db "  mov bx,ax", 13, 10, 0
asm_mov_di_arr    db "  mov di,28000", 13, 10, 0
asm_add_di_bx     db "  add di,bx", 13, 10, 0
asm_mov_di_mem_ax db "  mov [di],ax", 13, 10, 0
asm_mov_ax_di_mem db "  mov ax,[di]", 13, 10, 0
asm_call_get_str  db "  call lib_get_str_ptr", 13, 10, 0
asm_call_slet     db "  call lib_sled", 13, 10, 0
asm_call_sadd     db "  call lib_sadd", 13, 10, 0
asm_call_scmp     db "  call lib_scmp", 13, 10, 0
asm_call_inputs   db "  call lib_inputs", 13, 10, 0
asm_print_call    db "  call lib_print", 13, 10, 0
asm_call_input    db "  call lib_input", 13, 10, 0
asm_call_mode     db "  call lib_mode", 13, 10, 0
asm_buf_1         db "  mov ah,0x33", 13, 10, "  int 0x80", 13, 10, "  mov [draw_seg],ax", 13, 10, 0
asm_buf_0         db "  mov ax,0xA000", 13, 10, "  mov [draw_seg],ax", 13, 10, 0
asm_call_flip     db "  mov ah,0x31", 13, 10, "  int 0x80", 13, 10, 0
asm_call_frect    db "  mov ah,0x32", 13, 10, "  int 0x80", 13, 10, 0
asm_call_delay    db "  mov ah,0x21", 13, 10, "  int 0x80", 13, 10, 0
asm_call_sleep    db "  mov ah,0x21", 13, 10, "  int 0x80", 13, 10, 0
asm_call_yield    db "  mov ah,0x22", 13, 10, "  int 0x80", 13, 10, 0
asm_call_beep     db "  call lib_beep", 13, 10, 0
asm_call_cls      db "  mov ah,0x0F", 13, 10, "  int 0x10", 13, 10, "  mov ah,0x00", 13, 10, "  int 0x10", 13, 10, 0
asm_circ_u0       db "  mov [circ_u0],ax", 13, 10, 0
asm_circ_v0       db "  mov [circ_v0],ax", 13, 10, 0
asm_circ_r        db "  mov [circ_r],ax", 13, 10, 0
asm_circ_c        db "  mov [circ_c],ax", 13, 10, 0
asm_call_circle   db "  call lib_circle", 13, 10, 0
asm_call_plot     db "  call lib_plot", 13, 10, 0
asm_call_pchar    db "  mov ah,0x0E", 13, 10, "  mov bx,0x000F", 13, 10, "  int 0x10", 13, 10, 0
asm_call_cursor   db "  mov dh,al", 13, 10, "  mov ax,dx", 13, 10, "  mov dl,al", 13, 10, "  mov ah,0x02", 13, 10, "  mov bh,0", 13, 10, "  int 0x10", 13, 10, 0
asm_call_key      db "  mov ah,0x15", 13, 10, "  int 0x80", 13, 10, "  xor ah,ah", 13, 10, 0
asm_call_mouse    db "  mov ah,0x18", 13, 10, "  int 0x80", 13, 10, "  shr cx,1", 13, 10, "  push ax", 13, 10, "  xor ax,ax", 13, 10, "  mov al,bl", 13, 10, "  mov bx,ax", 13, 10, "  pop ax", 13, 10, "  xchg ax,bx", 13, 10, 0
asm_call_ticks    db "  mov ah,0x20", 13, 10, "  int 0x80", 13, 10, 0
asm_call_out      db "  out dx,al", 13, 10, 0
asm_call_inp      db "  in al,dx", 13, 10, "  xor ah,ah", 13, 10, 0
asm_call_rnd      db "  call lib_rnd", 13, 10, 0
asm_call_peek     db "  pop dx", 13, 10, "  push es", 13, 10, "  mov es,dx", 13, 10, "  mov bx,ax", 13, 10, "  db 0x26,0x8A,0x07", 13, 10, "  xor ah,ah", 13, 10, "  pop es", 13, 10, 0
asm_call_poke     db "  mov cx,ax", 13, 10, "  pop bx", 13, 10, "  pop dx", 13, 10, "  push es", 13, 10, "  mov es,dx", 13, 10, "  db 0x26,0x88,0x0F", 13, 10, "  pop es", 13, 10, 0
asm_call_panic    db "  mov ax,1", 13, 10, "  xor cx,cx", 13, 10, "  div cx", 13, 10, 0
asm_line_u0       db "  mov [ln_u0],ax", 13, 10, 0
asm_line_v0       db "  mov [ln_v0],ax", 13, 10, 0
asm_line_u1       db "  mov [ln_u1],ax", 13, 10, 0
asm_line_v1       db "  mov [ln_v1],ax", 13, 10, 0
asm_line_c        db "  mov [ln_c],ax", 13, 10, 0
asm_call_line     db "  call lib_line", 13, 10, 0
asm_jmp_skip      db "  jmp skip_", 0
asm_str_lbl       db "str_", 0
asm_skip_lbl      db "skip_", 0
asm_db_quote      db ': db "', 0
asm_quote_nl_0    db '", 13, 10, 0', 13, 10, 0
asm_quote_0       db '", 0', 13, 10, 0
asm_colon_nl      db ":", 13, 10, 0
asm_mov_si_str    db "  mov si,str_", 0
asm_print_int80   db "  mov ah,0x00", 13, 10, "  int 0x80", 13, 10, 0
asm_end           db "  mov ah,0x04", 13, 10, "  int 0x80", 13, 10, 0
asm_sq_u          db "  mov [ru],ax", 13, 10, 0
asm_sq_v          db "  mov [rv],ax", 13, 10, 0
asm_sq_w          db "  mov [rw],ax", 13, 10, 0
asm_sq_z          db "  mov [rz],ax", 13, 10, 0
asm_sq_c          db "  mov [rc],ax", 13, 10, 0
asm_call_sqr      db "  call lib_sqr", 13, 10, 0
asm_call_fread    db "  call lib_rd", 13, 10, 0
asm_call_fwrite   db "  call lib_wr", 13, 10, 0
asm_call_del      db "  call lib_dl", 13, 10, 0
asm_call_md       db "  call lib_md", 13, 10, 0
asm_call_cd       db "  call lib_cd", 13, 10, 0
asm_call_comw     db "  call lib_cmw", 13, 10, 0
asm_call_comr     db "  call lib_cmr", 13, 10, 0
asm_call_insmod   db "  call lib_ins", 13, 10, 0
asm_lib_all:
  db "  mov ah,0x04", 13, 10, "  int 0x80", 13, 10
  db "lib_get_str_ptr: xor ah,ah", 13, 10
  db "  add ax,ax", 13, 10, "  add ax,ax", 13, 10, "  add ax,ax", 13, 10
  db "  add ax,ax", 13, 10, "  add ax,ax", 13, 10, "  add ax,ax", 13, 10
  db "  add ax,30080", 13, 10, "  mov di,ax", 13, 10, "  ret", 13, 10
  db "lib_sled: call lib_get_str_ptr", 13, 10
  db "sl_lp: lodsb", 13, 10, "  stosb", 13, 10, "  or al,al", 13, 10, "  jnz sl_lp", 13, 10, "  ret", 13, 10
  db "lib_sadd: call lib_get_str_ptr", 13, 10
  db "sa_fd: mov al,[di]", 13, 10, "  cmp al,0", 13, 10, "  je sa_lp", 13, 10
  db "  inc di", 13, 10, "  jmp sa_fd", 13, 10
  db "sa_lp: lodsb", 13, 10, "  stosb", 13, 10, "  or al,al", 13, 10, "  jnz sa_lp", 13, 10, "  ret", 13, 10
  db "lib_scmp: call lib_get_str_ptr", 13, 10
  db "sc_lp: lodsb", 13, 10, "  mov ah,[di]", 13, 10, "  inc di", 13, 10
  db "  cmp al,ah", 13, 10, "  jne sc_df", 13, 10, "  or al,al", 13, 10
  db "  jz sc_eq", 13, 10, "  jmp sc_lp", 13, 10
  db "sc_df: ret", 13, 10
  db "sc_eq: xor ax,ax", 13, 10, "  ret", 13, 10
  db "lib_inputs: call lib_get_str_ptr", 13, 10, "  push di", 13, 10, "  mov si,str_pmc", 13, 10
  db "  mov ah,0x00", 13, 10, "  int 0x80", 13, 10, "  mov di,30720", 13, 10
  db "  call lib_read_line", 13, 10, "  pop di", 13, 10, "  mov si,30720", 13, 10
  db "in_cp: lodsb", 13, 10, "  stosb", 13, 10, "  or al,al", 13, 10, "  jnz in_cp", 13, 10, "  ret", 13, 10
  db "str_pmc: db 63,32,0", 13, 10
  db "lib_read_line: mov [30850],di", 13, 10
  db "rl_lp: mov ah,0x01", 13, 10, "  int 0x80", 13, 10, "  cmp al,13", 13, 10, "  je rl_dn", 13, 10
  db "  cmp al,8", 13, 10, "  je rl_bs", 13, 10, "  cmp al,32", 13, 10, "  jb rl_lp", 13, 10
  db "  cmp al,126", 13, 10, "  ja rl_lp", 13, 10, "  stosb", 13, 10
  db "  mov ah,0x0E", 13, 10, "  int 0x10", 13, 10, "  jmp rl_lp", 13, 10
  db "rl_bs: cmp di,[30850]", 13, 10, "  jbe rl_lp", 13, 10, "  dec di", 13, 10
  db "  mov ah,0x0E", 13, 10, "  mov al,8", 13, 10, "  int 0x10", 13, 10
  db "  mov al,32", 13, 10, "  int 0x10", 13, 10, "  mov al,8", 13, 10, "  int 0x10", 13, 10, "  jmp rl_lp", 13, 10
  db "rl_dn: mov al,0", 13, 10, "  mov [di],al", 13, 10, "  mov ah,0x0E", 13, 10
  db "  mov al,13", 13, 10, "  int 0x10", 13, 10, "  mov al,10", 13, 10, "  int 0x10", 13, 10, "  ret", 13, 10
  db "lib_print:", 13, 10
  db "  push ax", 13, 10, "  push bx", 13, 10, "  push cx", 13, 10, "  push dx", 13, 10
  db "  mov cx,0", 13, 10, "  mov bx,10", 13, 10
  db "ll1: xor dx,dx", 13, 10, "  div bx", 13, 10, "  push dx", 13, 10
  db "  inc cx", 13, 10, "  or ax,ax", 13, 10, "  jnz ll1", 13, 10
  db "ll2: pop ax", 13, 10, "  add al,48", 13, 10, "  mov ah,0x0E", 13, 10
  db "  int 0x10", 13, 10, "  loop ll2", 13, 10
  db "  mov ah,0x0E", 13, 10, "  mov al,13", 13, 10, "  int 0x10", 13, 10
  db "  mov al,10", 13, 10, "  int 0x10", 13, 10
  db "  pop dx", 13, 10, "  pop cx", 13, 10, "  pop bx", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "lib_input:", 13, 10
  db "  push bx", 13, 10, "  push cx", 13, 10, "  push dx", 13, 10
  db "  mov ah,0x0E", 13, 10
  db "  mov al,63", 13, 10
  db "  int 0x10", 13, 10
  db "  mov al,32", 13, 10
  db "  int 0x10", 13, 10
  db "  xor bx,bx", 13, 10
  db "in_lp: mov ah,0x01", 13, 10, "  int 0x80", 13, 10, "  cmp al,13", 13, 10, "  je in_dn", 13, 10
  db "  cmp al,48", 13, 10, "  jb in_lp", 13, 10, "  cmp al,57", 13, 10, "  ja in_lp", 13, 10
  db "  mov ah,0x0E", 13, 10, "  push bx", 13, 10, "  mov bx,0x000F", 13, 10, "  int 0x10", 13, 10, "  pop bx", 13, 10
  db "  sub al,48", 13, 10, "  xor ah,ah", 13, 10, "  push ax", 13, 10, "  mov ax,bx", 13, 10
  db "  mov cx,10", 13, 10, "  mul cx", 13, 10, "  pop dx", 13, 10, "  add ax,dx", 13, 10
  db "  mov bx,ax", 13, 10, "  jmp in_lp", 13, 10
  db "in_dn: mov ah,0x0E", 13, 10, "  mov al,13", 13, 10, "  int 0x10", 13, 10
  db "  mov al,10", 13, 10, "  int 0x10", 13, 10
  db "  mov ax,bx", 13, 10, "  pop dx", 13, 10, "  pop cx", 13, 10, "  pop bx", 13, 10, "  ret", 13, 10
  db "lib_cmw: mov ah,0x01", 13, 10, "  int 0x82", 13, 10, "  ret", 13, 10
  db "lib_cmr: mov ah,0x02", 13, 10, "  int 0x82", 13, 10, "  xor ah,ah", 13, 10, "  ret", 13, 10
  db "lib_wr: mov [31000],ax", 13, 10, "  mov ah,0x03", 13, 10, "  mov cx,2", 13, 10, "  mov di,31000", 13, 10, "  int 0x80", 13, 10, "  ret", 13, 10
  db "lib_cd: mov ah,0x0E", 13, 10, "  int 0x80", 13, 10, "  ret", 13, 10
  db "lib_ins: mov ah,0x1E", 13, 10, "  int 0x80", 13, 10, "  ret", 13, 10
  db "fat_buf: db 32,32,32,32,32,32,32,32,32,32,32", 13, 10
  db "lib_fmt: push ax", 13, 10, "  push cx", 13, 10, "  push si", 13, 10, "  push di", 13, 10
  db "  mov di,fat_buf", 13, 10, "  mov cx,11", 13, 10, "  mov al,32", 13, 10
  db "fmt_c: stosb", 13, 10, "  loop fmt_c", 13, 10
  db "  mov di,fat_buf", 13, 10, "  mov cx,8", 13, 10
  db "f_lp: lodsb", 13, 10, "  or al,al", 13, 10, "  jz f_dn", 13, 10, "  cmp al,46", 13, 10, "  je f_suf", 13, 10, "  stosb", 13, 10, "  loop f_lp", 13, 10
  db "f_sk: lodsb", 13, 10, "  or al,al", 13, 10, "  jz f_dn", 13, 10, "  cmp al,46", 13, 10, "  je f_suf", 13, 10, "  jmp f_sk", 13, 10
  db "f_suf: mov di,fat_buf", 13, 10, "  add di,8", 13, 10, "  mov cx,3", 13, 10
  db "f_el: lodsb", 13, 10, "  or al,al", 13, 10, "  jz f_dn", 13, 10, "  stosb", 13, 10, "  loop f_el", 13, 10
  db "f_dn: pop di", 13, 10, "  pop si", 13, 10, "  pop cx", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "lib_rd: call lib_fmt", 13, 10, "  mov ah,0x02", 13, 10, "  mov si,fat_buf", 13, 10, "  mov di,31000", 13, 10, "  int 0x80", 13, 10, "  mov ax,[31000]", 13, 10, "  ret", 13, 10
  db "lib_dl: call lib_fmt", 13, 10, "  mov ah,0x0C", 13, 10, "  mov si,fat_buf", 13, 10, "  int 0x80", 13, 10, "  ret", 13, 10
  db "lib_md: call lib_fmt", 13, 10, "  mov ah,0x17", 13, 10, "  mov si,fat_buf", 13, 10, "  int 0x80", 13, 10, "  ret", 13, 10
  db "ru: dw 0", 13, 10, "rv: dw 0", 13, 10, "rw: dw 0", 13, 10, "rz: dw 0", 13, 10, "rc: dw 0", 13, 10
  db "lib_sqr: push ax", 13, 10, "  push bx", 13, 10, "  push cx", 13, 10, "  push dx", 13, 10, "  push di", 13, 10, "  push es", 13, 10
  db "  mov ax,[draw_seg]", 13, 10, "  mov es,ax", 13, 10
  db "  mov cx,[rz]", 13, 10, "  mov bx,[rv]", 13, 10
  db "sq_lr: call sq_v", 13, 10, "  inc bx", 13, 10, "  loop sq_lr", 13, 10
  db "  mov cx,[rw]", 13, 10, "  mov ax,[ru]", 13, 10
  db "sq_tb: call sq_u", 13, 10, "  inc ax", 13, 10, "  loop sq_tb", 13, 10
  db "  pop es", 13, 10, "  pop di", 13, 10, "  pop dx", 13, 10, "  pop cx", 13, 10, "  pop bx", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "sq_v: push ax", 13, 10, "  mov ax,[ru]", 13, 10, "  call sq_p", 13, 10, "  add ax,[rw]", 13, 10, "  dec ax", 13, 10, "  call sq_p", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "sq_u: push bx", 13, 10, "  mov bx,[rv]", 13, 10, "  call sq_p", 13, 10, "  add bx,[rz]", 13, 10, "  dec bx", 13, 10, "  call sq_p", 13, 10, "  pop bx", 13, 10, "  ret", 13, 10
  db "sq_p: cmp ax,0", 13, 10, "  jl sq_e", 13, 10, "  cmp ax,319", 13, 10, "  jg sq_e", 13, 10, "  cmp bx,0", 13, 10, "  jl sq_e", 13, 10, "  cmp bx,199", 13, 10, "  jg sq_e", 13, 10
  db "  push ax", 13, 10, "  push dx", 13, 10, "  mov dx,320", 13, 10, "  push ax", 13, 10, "  mov ax,bx", 13, 10, "  mul dx", 13, 10, "  pop dx", 13, 10, "  add ax,dx", 13, 10
  db "  mov di,ax", 13, 10, "  mov al,[rc]", 13, 10
  db "  db 0x26,0x88,0x05", 13, 10
  db "  pop dx", 13, 10, "  pop ax", 13, 10, "sq_e: ret", 13, 10
  db "circ_u0: dw 0", 13, 10, "circ_v0: dw 0", 13, 10, "circ_r: dw 0", 13, 10
  db "circ_c: dw 0", 13, 10, "circ_u: dw 0", 13, 10, "circ_v: dw 0", 13, 10, "circ_err: dw 0", 13, 10
  db "lib_circle:", 13, 10
  db "  push ax", 13, 10, "  push bx", 13, 10, "  push cx", 13, 10, "  push dx", 13, 10, "  push di", 13, 10
  db "  mov ax,[circ_r]", 13, 10, "  mov [circ_u],ax", 13, 10
  db "  xor ax,ax", 13, 10, "  mov [circ_v],ax", 13, 10, "  mov [circ_err],ax", 13, 10
  db "c_lp: mov ax,[circ_u]", 13, 10, "  cmp ax,[circ_v]", 13, 10, "  jl c_dn", 13, 10, "  call d_pu", 13, 10
  db "  mov ax,[circ_err]", 13, 10, "  cmp ax,0", 13, 10, "  jg chk_e", 13, 10
  db "  mov ax,[circ_v]", 13, 10, "  inc ax", 13, 10, "  mov [circ_v],ax", 13, 10
  db "  add ax,ax", 13, 10, "  inc ax", 13, 10, "  add [circ_err],ax", 13, 10
  db "chk_e: mov ax,[circ_err]", 13, 10, "  cmp ax,0", 13, 10, "  jle c_lp", 13, 10
  db "  mov ax,[circ_u]", 13, 10, "  dec ax", 13, 10, "  mov [circ_u],ax", 13, 10
  db "  add ax,ax", 13, 10, "  inc ax", 13, 10, "  sub [circ_err],ax", 13, 10, "  jmp c_lp", 13, 10
  db "c_dn: pop di", 13, 10, "  pop dx", 13, 10, "  pop cx", 13, 10, "  pop bx", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "d_pu: mov ax,[circ_u]", 13, 10, "  mov bx,[circ_v]", 13, 10, "  call p_sy", 13, 10
  db "  mov ax,[circ_v]", 13, 10, "  mov bx,[circ_u]", 13, 10, "  call p_sy", 13, 10, "  ret", 13, 10
  db "p_sy: push ax", 13, 10, "  push bx", 13, 10, "  push cx", 13, 10, "  push dx", 13, 10
  db "  mov cx,ax", 13, 10, "  mov dx,bx", 13, 10
  db "  mov ax,[circ_u0]", 13, 10, "  add ax,cx", 13, 10, "  mov bx,[circ_v0]", 13, 10, "  add bx,dx", 13, 10, "  call p_ptc", 13, 10
  db "  mov ax,[circ_u0]", 13, 10, "  sub ax,cx", 13, 10, "  mov bx,[circ_v0]", 13, 10, "  add bx,dx", 13, 10, "  call p_ptc", 13, 10
  db "  mov ax,[circ_u0]", 13, 10, "  add ax,cx", 13, 10, "  mov bx,[circ_v0]", 13, 10, "  sub bx,dx", 13, 10, "  call p_ptc", 13, 10
  db "  mov ax,[circ_u0]", 13, 10, "  sub ax,cx", 13, 10, "  mov bx,[circ_v0]", 13, 10, "  sub bx,dx", 13, 10, "  call p_ptc", 13, 10
  db "  pop dx", 13, 10, "  pop cx", 13, 10, "  pop bx", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "p_ptc: cmp ax,0", 13, 10, "  jl p_rtc", 13, 10, "  cmp ax,319", 13, 10, "  jg p_rtc", 13, 10
  db "  cmp bx,0", 13, 10, "  jl p_rtc", 13, 10, "  cmp bx,199", 13, 10, "  jg p_rtc", 13, 10
  db "  push ax", 13, 10, "  push dx", 13, 10, "  push es", 13, 10
  db "  mov dx,[draw_seg]", 13, 10, "  mov es,dx", 13, 10, "  mov dx,320", 13, 10
  db "  xchg ax,bx", 13, 10, "  mul dx", 13, 10, "  add bx,ax", 13, 10, "  mov ax,[circ_c]", 13, 10
  db "  db 0x26,0x88,0x07", 13, 10
  db "  pop es", 13, 10, "  pop dx", 13, 10, "  pop ax", 13, 10
  db "p_rtc: ret", 13, 10
  db "lib_beep: push ax", 13, 10, "  push bx", 13, 10
  db "  cmp ax,20", 13, 10, "  jge b_ok", 13, 10, "  mov ax,1000", 13, 10
  db "b_ok: mov bx,ax", 13, 10, "  mov ah,25", 13, 10, "  mov al,1", 13, 10, "  int 128", 13, 10
  db "  mov ah,33", 13, 10, "  mov bx,3", 13, 10, "  int 128", 13, 10
  db "  mov ah,25", 13, 10, "  mov al,0", 13, 10, "  int 128", 13, 10
  db "  pop bx", 13, 10, "  pop ax", 13, 10, "  ret", 13, 10
  db "lib_mode: cmp ax,19", 13, 10, "  jne m_chr", 13, 10
  db "  mov ax,1", 13, 10, "  mov ah,48", 13, 10, "  int 128", 13, 10, "  ret", 13, 10
  db "m_chr: mov ax,0", 13, 10, "  mov ah,48", 13, 10, "  int 128", 13, 10, "  ret", 13, 10
  db "lib_plot: mov cx,ax", 13, 10, "  pop dx", 13, 10, "  pop bx", 13, 10, "  pop ax", 13, 10
  db "  push dx", 13, 10, "  push cx", 13, 10, "  push ax", 13, 10
  db "  mov ax,320", 13, 10, "  mul bx", 13, 10, "  pop bx", 13, 10, "  add bx,ax", 13, 10
  db "  pop cx", 13, 10, "  push es", 13, 10, "  mov ax,[draw_seg]", 13, 10, "  mov es,ax", 13, 10
  db "  db 0x26,0x88,0x0F", 13, 10
  db "  pop es", 13, 10, "  ret", 13, 10
  db "lib_rnd: mov ax,[32766]", 13, 10, "  mov cx,25173", 13, 10, "  mul cx", 13, 10
  db "  add ax,13849", 13, 10, "  mov [32766],ax", 13, 10
  db "  or bx,bx", 13, 10, "  jz lr_z", 13, 10, "  xor dx,dx", 13, 10, "  div bx", 13, 10
  db "  mov ax,dx", 13, 10, "  ret", 13, 10
  db "lr_z: xor ax,ax", 13, 10, "  ret", 13, 10
  db "ln_u0: dw 0", 13, 10
  db "ln_v0: dw 0", 13, 10
  db "ln_u1: dw 0", 13, 10
  db "ln_v1: dw 0", 13, 10
  db "ln_c:  dw 0", 13, 10
  db "lib_line: mov bx, ln_u0", 13, 10
  db "  db 0x50, 0x53, 0x51, 0x52, 0x56, 0x57, 0x55, 0x06", 13, 10
  db "  db 0x8B, 0x37, 0x8B, 0x7F, 0x02, 0x8B, 0x47, 0x04", 13, 10
  db "  db 0x2B, 0xC6, 0xB9, 0x01, 0x00, 0x79, 0x05, 0xF7", 13, 10
  db "  db 0xD8, 0xB9, 0xFF, 0xFF, 0x50, 0x51, 0x8B, 0x47", 13, 10
  db "  db 0x06, 0x2B, 0xC7, 0xB9, 0x01, 0x00, 0x79, 0x05", 13, 10
  db "  db 0xF7, 0xD8, 0xB9, 0xFF, 0xFF, 0x50, 0x51, 0x8B", 13, 10
  db "  db 0xEC, 0x8B, 0x46, 0x06, 0x2B, 0x46, 0x02, 0x8B", 13, 10
  db "  db 0xD0, 0x8B, 0x4E, 0x06, 0x3B, 0x4E, 0x02, 0x7D", 13, 10
  db "  db 0x03, 0x8B, 0x4E, 0x02, 0x41, 0x83, 0xFE, 0x00", 13, 10
  db "  db 0x7C, 0x29, 0x81, 0xFE, 0x3F, 0x01, 0x7F, 0x23", 13, 10
  db "  db 0x83, 0xFF, 0x00, 0x7C, 0x1E, 0x81, 0xFF, 0xC7", 13, 10
  db "  db 0x00, 0x7F, 0x18, 0xA1, 0x03, 0x00, 0x8E, 0xC0", 13, 10
  db "  db 0xB8, 0x40, 0x01, 0x52, 0xF7, 0xE7, 0x5A, 0x03", 13, 10
  db "  db 0xC6, 0x57, 0x8B, 0xF8, 0x8A, 0x47, 0x08, 0x26", 13, 10
  db "  db 0x88, 0x05, 0x5F, 0x8B, 0xC2, 0xD1, 0xE0, 0x52", 13, 10
  db "  db 0x8B, 0x56, 0x02, 0xF7, 0xDA, 0x3B, 0xC2, 0x5A", 13, 10
  db "  db 0x7C, 0x06, 0x2B, 0x56, 0x02, 0x03, 0x76, 0x04", 13, 10
  db "  db 0x3B, 0x46, 0x06, 0x7F, 0x06, 0x03, 0x56, 0x06", 13, 10
  db "  db 0x03, 0x7E, 0x00, 0x49, 0x75, 0xAF, 0x83, 0xC4", 13, 10
  db "  db 0x08, 0x07, 0x5D, 0x5F, 0x5E, 0x5A, 0x59, 0x5B", 13, 10
  db "  db 0x58, 0xC3", 13, 10, 0
