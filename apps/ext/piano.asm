; apps/piano.asm - PPP OS 实模式蜂鸣器电子琴
[BITS 16]
[ORG 0x0000]

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; 1. 清屏并绘制 UI
    mov ah, 0x00
    mov al, 0x03
    int 0x10

    mov si, msg_title
    call print_str

.loop:
    ; 2. 等待按键输入 (调用你系统的 AH=01 键盘读取)
    mov ah, 0x01
    int 0x80

    cmp al, 27          ; 如果按下 ESC 键
    je .exit

    ; 3. 音阶频率映射
    cmp al, 'a'
    je .play_do         ; C4
    cmp al, 's'
    je .play_re         ; D4
    cmp al, 'd'
    je .play_mi         ; E4
    cmp al, 'f'
    je .play_fa         ; F4
    cmp al, 'g'
    je .play_sol        ; G4
    cmp al, 'h'
    je .play_la         ; A4 (440Hz)
    cmp al, 'j'
    je .play_si         ; B4
    cmp al, 'k'
    je .play_do_high    ; C5

    jmp .loop           ; 如果按了其他键，忽略

; --- 音高频率定义 (单位: Hz) ---
.play_do:       mov bx, 262  ; C
                jmp .play
.play_re:       mov bx, 294  ; D
                jmp .play
.play_mi:       mov bx, 330  ; E
                jmp .play
.play_fa:       mov bx, 349  ; F
                jmp .play
.play_sol:      mov bx, 392  ; G
                jmp .play
.play_la:       mov bx, 440  ; A
                jmp .play
.play_si:       mov bx, 494  ; B
                jmp .play
.play_do_high:  mov bx, 523  ; C (高音)
                jmp .play

.play:
    ; 4. 发送“开启声音”系统调用 (AH=0x19, AL=1)
    mov ah, 0x19
    mov al, 1
    int 0x80

    ; 5. 发声延时 (忙等待循环，控制发声时长)
    ; 在真实的物理机和 QEMU 上速度不同，如果太短可以增加 cx 的初始值
    mov cx, 0x03FF
.delay_outer:
    push cx
    mov cx, 0xFFFF
.delay_inner:
    nop
    nop
    loop .delay_inner
    pop cx
    loop .delay_outer

    ; 6. 发送“关闭声音”系统调用 (AH=0x19, AL=0)
    mov ah, 0x19
    mov al, 0
    int 0x80

    jmp .loop

.exit:
    ; 恢复默认黑底白字并退出进程
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    
    mov ah, 0x04
    int 0x80

; --- 简单的字符串打印函数 ---
print_str:
    mov ah, 0x0E
    mov bx, 0x000F
.p_loop:
    lodsb
    or al, al
    jz .p_done
    int 0x10
    jmp .p_loop
.p_done:
    ret

; --- 数据区 ---
msg_title:
    db "========================================", 13, 10
    db "      PPP OS - PC Speaker Piano", 13, 10
    db "========================================", 13, 10
    db 13, 10
    db " Play the notes using keys:", 13, 10
    db " [A] Do   (C4)", 13, 10
    db " [S] Re   (D4)", 13, 10
    db " [D] Mi   (E4)", 13, 10
    db " [F] Fa   (F4)", 13, 10
    db " [G] Sol  (G4)", 13, 10
    db " [H] La   (A4) - 440Hz", 13, 10
    db " [J] Si   (B4)", 13, 10
    db " [K] Do+  (C5)", 13, 10
    db 13, 10
    db " Press [ESC] to Exit.", 13, 10, 0