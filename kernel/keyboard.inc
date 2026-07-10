; ================================================================
; PPP OS PS/2 键盘驱动
; ================================================================

kb_head   dw 0                     ; 环形缓冲区头指针 (当前填入位置)
kb_tail   dw 0                     ; 环形缓冲区尾指针 (当前取出位置)
kb_shift  db 0                     ; Shift 状态标志 (0=关闭, 1=按下)
kb_buf    times 32 dw 0            ; 环形缓冲区 (32个按键值)

; ----------------------------------------------------------------
; 安装键盘中断处理程序 (IRQ1, INT 0x09)
; ----------------------------------------------------------------
setup_keyboard:
    cli
    push es
    xor ax, ax
    mov es, ax
    mov word [es:0x09*4], keyboard_isr
    mov word [es:0x09*4+2], cs
    pop es
    sti
    ret

; ----------------------------------------------------------------
; 键盘中断服务程序 (IRQ1)
; 读取扫描码，处理 Shift 键，将 ASCII 码存入缓冲区
; ----------------------------------------------------------------
keyboard_isr:
    pusha
    in al, 0x60                    ; 读取扫描码

    cmp al, 0xE0                   ; 扩展码前缀 (忽略)
    je .end_isr

    test al, 0x80                  ; 断码检测 (释放键)
    jnz .break_code

    ; 通码处理 (键按下)
    mov ah, al                     ; 保存原始扫描码

    cmp al, 0x2A                   ; 左 Shift 通码
    je .set_shift
    cmp al, 0x36                   ; 右 Shift 通码
    je .set_shift

    ; 根据 Shift 状态选择键映射表
    mov bx, keymap_normal
    cmp byte [cs:kb_shift], 1
    jne .lookup
    mov bx, keymap_shift
.lookup:
    push ax
    xor ah, ah
    add bx, ax                     ; BX = 映射表基址 + 扫描码
    mov al, [cs:bx]                ; 获取 ASCII 码
    pop dx
    mov ah, dh                     ; 高字节保留扫描码 (用于扩展)

    ; 存入缓冲区
    mov bx, [cs:kb_head]
    mov di, bx
    shl di, 1
    mov [cs:kb_buf + di], ax
    inc bx
    and bx, 15                     ; 缓冲区大小 16 (0~15)
    cmp bx, [cs:kb_tail]           ; 检查是否满
    je .end_isr
    mov [cs:kb_head], bx
    jmp .end_isr

.break_code:                       ; 断码 (键释放)
    and al, 0x7F                   ; 去掉释放位
    cmp al, 0x2A
    je .clr_shift
    cmp al, 0x36
    je .clr_shift
    jmp .end_isr

.set_shift:
    mov byte [cs:kb_shift], 1
    jmp .end_isr
.clr_shift:
    mov byte [cs:kb_shift], 0

.end_isr:
    mov al, 0x20                   ; 发送 EOI 到 PIC
    out 0x20, al
    popa
    iret

; ----------------------------------------------------------------
; 从键盘缓冲区获取按键 (阻塞)
; 输出: AX = 按键值 (高字节=扫描码, 低字节=ASCII)
; ----------------------------------------------------------------
kb_get_key:
.wait:
    sti                            ; 允许中断，防止死锁
    mov ax, [cs:kb_head]
    cmp ax, [cs:kb_tail]
    jne .pop_key
    hlt                            ; 等待中断唤醒
    jmp .wait
.pop_key:
    push bx
    mov bx, [cs:kb_tail]
    push bx
    shl bx, 1
    mov ax, [cs:kb_buf + bx]       ; 读取按键值
    pop bx
    inc bx
    and bx, 15
    mov [cs:kb_tail], bx
    pop bx
    ret

; ----------------------------------------------------------------
; 非阻塞按键检测
; 输出: AX = 按键值 (若有), 否则 AX = 0
; ----------------------------------------------------------------
kb_check_key:
    mov ax, [cs:kb_head]
    cmp ax, [cs:kb_tail]
    jne kb_get_key                 ; 有按键则直接取走
    xor ax, ax
    ret

; ----------------------------------------------------------------
; 从键盘读取一行文本 (支持退格)
; 输入: ES:DI = 缓冲区地址
; 输出: 以 0 结尾的字符串
; ----------------------------------------------------------------
read_line:
    pusha
    mov dx, di                     ; 保存起始地址
.loop:
    call kb_get_key

    cmp al, 0x0D                   ; 回车键
    je .done
    cmp al, 0x08                   ; 退格键
    je .backspace
    cmp al, ' '                    ; 过滤控制字符
    jb .loop
    cmp al, '~'
    ja .loop

    stosb                          ; 存入缓冲区
    mov ah, 0x0E
    int 0x10                       ; 回显字符
    jmp .loop

.backspace:
    cmp di, dx                     ; 防止删到起始位置之前
    je .loop
    dec di
    mov al, 0x08
    call .print_char
    mov al, ' '
    call .print_char
    mov al, 0x08
    call .print_char
    jmp .loop

.print_char:
    mov ah, 0x0E
    int 0x10
    ret

.done:
    mov al, 0
    stosb                          ; 字符串结束符
    popa
    ret

; ----------------------------------------------------------------
; 获取单个字符 (阻塞)
; 输出: AL = ASCII 码
; ----------------------------------------------------------------
get_char:
    call kb_get_key
    ret

; ----------------------------------------------------------------
; 键盘映射表
; ----------------------------------------------------------------
keymap_normal db 0, 27, '1','2','3','4','5','6','7','8','9','0','-','=', 8, 9
              db 'q','w','e','r','t','y','u','i','o','p','[',']', 13, 0
              db 'a','s','d','f','g','h','j','k','l',';',"'",'`', 0, '\'
              db 'z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' '
              times 128-58 db 0

keymap_shift  db 0, 27, '!','@','#','$','%','^','&','*','(',')','_','+', 8, 9
              db 'Q','W','E','R','T','Y','U','I','O','P','{','}', 13, 0
              db 'A','S','D','F','G','H','J','K','L',':','"','~', 0, '|'
              db 'Z','X','C','V','B','N','M','<','>','?', 0, '*', 0, ' '
              times 128-58 db 0