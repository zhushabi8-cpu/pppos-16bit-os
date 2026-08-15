; ================================================================
; PPP OS PS/2 键盘驱动
; 提供环形缓冲区、Shift 键状态管理、阻塞/非阻塞读取
; ================================================================

kb_head   dw 0                     ; 环形缓冲区头指针（写入位置）
kb_tail   dw 0                     ; 环形缓冲区尾指针（读取位置）
kb_shift  db 0                     ; Shift 状态标志（0=释放，1=按下）
kb_buf    times 32 dw 0            ; 环形缓冲区，容量 32 个按键值（每项 16 位）

; ----------------------------------------------------------------
; 安装键盘中断处理程序
; 设置 IRQ1 的中断向量（INT 0x09）指向 keyboard_isr
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
; 键盘中断服务程序（IRQ1）
; 读取 PS/2 扫描码，识别通码/断码，处理 Shift 键状态，
; 将可打印字符的 ASCII 码存入环形缓冲区
; ----------------------------------------------------------------
keyboard_isr:
    pusha
    in al, 0x60                    ; 读取扫描码

    cmp al, 0xE0                   ; 扩展码前缀（如方向键），忽略
    je .end_isr

    test al, 0x80                  ; 检测断码（最高位为 1）
    jnz .break_code

    ; ---- 通码处理（键按下） ----
    mov ah, al                     ; 保存扫描码（高字节）

    cmp al, 0x2A                   ; 左 Shift 通码
    je .set_shift
    cmp al, 0x36                   ; 右 Shift 通码
    je .set_shift

    ; 根据 Shift 状态选择映射表
    mov bx, keymap_normal
    cmp byte [cs:kb_shift], 1
    jne .lookup
    mov bx, keymap_shift
.lookup:
    push ax
    xor ah, ah
    add bx, ax                     ; BX = 映射表起始 + 扫描码
    mov al, [cs:bx]                ; 获取 ASCII 码
    pop dx
    mov ah, dh                     ; 高字节保留扫描码（供扩展键使用）

    ; 写入环形缓冲区
    mov bx, [cs:kb_head]
    mov di, bx
    shl di, 1                      ; 转换为字偏移（*2）
    mov [cs:kb_buf + di], ax
    inc bx
    and bx, 31                     ; 掩码容量（32 项，0-31）
    cmp bx, [cs:kb_tail]           ; 检查缓冲区是否已满
    je .end_isr
    mov [cs:kb_head], bx
    jmp .end_isr

.break_code:                       ; ---- 断码处理（键释放） ----
    and al, 0x7F                   ; 清除释放位（高位置 0）
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
    mov al, 0x20                   ; 发送 EOI 给主 PIC
    out 0x20, al
    popa
    iret

; ----------------------------------------------------------------
; 从键盘缓冲区阻塞式获取按键
; 输出: AX = 按键值（AH=扫描码, AL=ASCII 码）
; 若无按键则 HLT 等待中断唤醒
; ----------------------------------------------------------------
kb_get_key:
.wait:
    sti                            ; 允许中断，防止死锁
    mov ax, [cs:kb_head]
    cmp ax, [cs:kb_tail]
    jne .pop_key
    hlt                            ; 暂停 CPU，等待中断唤醒
    jmp .wait
.pop_key:
    push bx
    mov bx, [cs:kb_tail]
    push bx
    shl bx, 1                      ; 字偏移
    mov ax, [cs:kb_buf + bx]       ; 读取按键值
    pop bx
    inc bx
    and bx, 31                     ; 回绕
    mov [cs:kb_tail], bx
    pop bx
    ret

; ----------------------------------------------------------------
; 非阻塞按键检测
; 输出: AX = 按键值（若有），AX = 0（若无按键）
; ----------------------------------------------------------------
kb_check_key:
    mov ax, [cs:kb_head]
    cmp ax, [cs:kb_tail]
    jne kb_get_key                 ; 有按键则直接取走
    xor ax, ax
    ret

; ----------------------------------------------------------------
; 从键盘读取一行文本（支持退格编辑）
; 输入: ES:DI = 缓冲区起始地址
; 输出: 以零结尾的字符串存入缓冲区，无回显
; ----------------------------------------------------------------
read_line:
    pusha
    mov dx, di                     ; 保存缓冲区起始地址
.loop:
    call kb_get_key

    cmp al, 0x0D                   ; 回车键，结束输入
    je .done
    cmp al, 0x08                   ; 退格键
    je .backspace
    cmp al, ' '                    ; 过滤不可打印字符（小于空格）
    jb .loop
    cmp al, '~'                    ; 过滤 DEL 及之后
    ja .loop

    stosb                          ; 存入缓冲区
    mov ah, 0x0E
    int 0x10                       ; 回显字符
    jmp .loop

.backspace:
    cmp di, dx                     ; 检查是否已回到行首
    je .loop
    dec di                         ; 删除缓冲区末尾
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
    stosb                          ; 添加字符串结束符
    popa
    ret

; ----------------------------------------------------------------
; 获取单个字符（阻塞，简化接口）
; 输出: AL = ASCII 码
; ----------------------------------------------------------------
get_char:
    call kb_get_key
    ret

; ----------------------------------------------------------------
; 键盘映射表（扫描码转 ASCII）
; 索引为扫描码，值为 ASCII 码。未定义键填 0
; ----------------------------------------------------------------
; 普通键映射（无 Shift）
keymap_normal db 0, 27, '1','2','3','4','5','6','7','8','9','0','-','=', 8, 9
              db 'q','w','e','r','t','y','u','i','o','p','[',']', 13, 0
              db 'a','s','d','f','g','h','j','k','l',';',"'",'`', 0, '\'
              db 'z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' '
              times 128-58 db 0

; Shift 键映射（按住 Shift 时）
keymap_shift  db 0, 27, '!','@','#','$','%','^','&','*','(',')','_','+', 8, 9
              db 'Q','W','E','R','T','Y','U','I','O','P','{','}', 13, 0
              db 'A','S','D','F','G','H','J','K','L',':','"','~', 0, '|'
              db 'Z','X','C','V','B','N','M','<','>','?', 0, '*', 0, ' '
              times 128-58 db 0