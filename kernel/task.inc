%define TCB_STATE   0          ; 任务状态 (0空闲, 1就绪, 2僵尸, 3睡眠中)
%define TCB_SP      1          ; 栈指针 (2字节)
%define TCB_SS      3          ; 栈段 (2字节)
%define TCB_WAKE    5          ; 唤醒时间 (2字节，记录 sys_ticks)
%define TCB_SIZE    32         ; 每个TCB占用32字节
%define MAX_TASKS   4          ; 最大任务数

; IPC 消息队列内核存储 (4 任务 x 8 槽位 x 16 字节 = 512 字节)
%define IPC_MAX_MSG   8
%define IPC_MSG_SIZE  16

old_int08       dw 0, 0        ; 保存原BIOS时钟中断向量
sys_ticks       dw 0           ; 系统时钟滴答计数 (18.2 Hz)
current_task    db 0           ; 当前运行任务索引 (0~3)
tcb_array       times MAX_TASKS * TCB_SIZE db 0  ; TCB数组
ipc_head   times MAX_TASKS db 0     ; 写入位置索引 (0~7)
ipc_tail   times MAX_TASKS db 0     ; 读取位置索引 (0~7)
ipc_count  times MAX_TASKS db 0     ; 未读消息计数
ipc_mailboxes times (MAX_TASKS * IPC_MAX_MSG * IPC_MSG_SIZE) db 0

setup_task_manager:
    cli
    push es
    xor ax, ax
    mov es, ax

    mov ax, [es:0x20]
    mov [cs:old_int08], ax
    mov ax, [es:0x22]
    mov [cs:old_int08+2], ax

    mov word [es:0x20], timer_isr
    mov word [es:0x22], cs

    mov byte [tcb_array + TCB_STATE], 1

    pop es
    sti
    ret

timer_isr:
    pushf
    call far [cs:old_int08]

    pusha
    push ds
    push es

    mov ax, cs
    mov ds, ax

    ; 1. 保存当前任务现场
    mov al, [current_task]
    xor ah, ah
    mov bx, TCB_SIZE
    mul bx
    mov si, tcb_array
    add si, ax
    mov [si + TCB_SP], sp
    mov [si + TCB_SS], ss

    ; 2. 僵尸任务回收器
    pusha
    mov cx, MAX_TASKS
    mov si, tcb_array
.reap_loop:
    cmp byte [si + TCB_STATE], 2
    jne .next_reap
    mov ax, [si + TCB_SS]
    call kfree
    mov byte [si + TCB_STATE], 0

    push bx
    mov bx, si
    sub bx, tcb_array
    shr bx, 5                       ; BX = Task ID (0~3)
    mov byte [cs:ipc_head + bx], 0
    mov byte [cs:ipc_tail + bx], 0
    mov byte [cs:ipc_count + bx], 0
    pop bx

.next_reap:
    add si, TCB_SIZE
    loop .reap_loop
    popa

    ; 3. 轮转调度
.find_next:
    mov al, [current_task]
    inc al
    cmp al, MAX_TASKS
    jb .check_task
    xor al, al
.check_task:
    mov [current_task], al

    xor ah, ah
    mov bx, TCB_SIZE
    mul bx
    mov si, tcb_array
    add si, ax

    cmp byte [si + TCB_STATE], 3  ; 睡眠中
    jne .check_ready
    mov bx, [sys_ticks]
    cmp bx, [si + TCB_WAKE]
    jb .find_next
    mov byte [si + TCB_STATE], 1  ; 唤醒

.check_ready:
    cmp byte [si + TCB_STATE], 1
    jne .find_next

    ; 4. 切换到选中的任务
    mov ss, [si + TCB_SS]
    mov sp, [si + TCB_SP]

    inc word [sys_ticks]

    pop es
    pop ds
    popa
    iret

create_daemon_task:
    cli
    mov ax, ss
    mov bx, sp

    mov cx, [cs:seg_task_stk]      ; 使用动态分配的栈段
    mov ss, cx
    mov sp, 0x0400                 ; 栈顶设为 1KB

    pushf
    pop dx
    or dx, 0x0200
    push dx
    push cs
    mov dx, daemon_process
    push dx
    pusha
    push ds
    push ds

    mov si, tcb_array + 32
    mov [si + TCB_SP], sp
    mov [si + TCB_SS], ss
    mov byte [si + TCB_STATE], 1

    mov ss, ax
    mov sp, bx
    sti
    ret

daemon_process:
    mov ax, 0xB800
    mov es, ax
.refresh_loop:
    mov di, 3968
    mov si, msg_watermark
    mov ah, 0x1F
.draw:
    lodsb
    or al, al
    jz .wait_next
    stosw
    jmp .draw
.wait_next:
    hlt
    jmp .refresh_loop

msg_watermark db "PPPOS - REL ", 0