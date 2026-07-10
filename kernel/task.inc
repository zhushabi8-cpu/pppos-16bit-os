; ================================================================
; PPP OS 任务调度器与后台守护进程
; ================================================================

; ---------- 任务控制块 (TCB) 偏移量 ----------
%define TCB_STATE   0          ; 任务状态 (0空闲,1就绪,2僵尸)
%define TCB_SP      1          ; 栈指针 (2字节)
%define TCB_SS      3          ; 栈段 (2字节)
%define TCB_SIZE    32         ; 每个TCB占用32字节
%define MAX_TASKS   4          ; 最大任务数

; ---------- 全局变量 ----------
old_int08       dw 0, 0        ; 保存原BIOS时钟中断向量
sys_ticks       dw 0           ; 系统时钟滴答计数
current_task    db 0           ; 当前运行任务索引 (0~3)
tcb_array       times MAX_TASKS * TCB_SIZE db 0  ; TCB数组

; ----------------------------------------------------------------
; 初始化任务管理器 (安装时钟中断处理程序)
; ----------------------------------------------------------------
setup_task_manager:
    cli
    push es
    xor ax, ax
    mov es, ax

    ; 保存原 INT 0x08 向量
    mov ax, [es:0x20]
    mov [cs:old_int08], ax
    mov ax, [es:0x22]
    mov [cs:old_int08+2], ax

    ; 安装自定义时钟中断
    mov word [es:0x20], timer_isr
    mov word [es:0x22], cs

    ; 标记任务0为就绪 (空闲任务)
    mov byte [tcb_array + TCB_STATE], 1

    pop es
    sti
    ret

; ----------------------------------------------------------------
; 时钟中断服务程序 (每秒约18.2次)
; 执行任务切换和僵尸回收
; ----------------------------------------------------------------
timer_isr:
    pushf
    call far [cs:old_int08]     ; 调用原BIOS中断，维持系统功能

    ; 保存当前任务现场
    pusha
    push ds
    push es

    mov ax, cs
    mov ds, ax

    ; 将当前任务的SP/SS存入TCB
    mov al, [current_task]
    xor ah, ah
    mov bx, TCB_SIZE
    mul bx
    mov si, tcb_array
    add si, ax
    mov [si + TCB_SP], sp
    mov [si + TCB_SS], ss

    ; ---------- 僵尸任务回收器 (防止UAF) ----------
    pusha
    mov cx, MAX_TASKS
    mov si, tcb_array
.reap_loop:
    cmp byte [si + TCB_STATE], 2   ; 检测僵尸状态
    jne .next_reap
    mov ax, [si + TCB_SS]          ; 获取任务内存段
    call kfree                     ; 释放物理内存
    mov byte [si + TCB_STATE], 0   ; 清空TCB
.next_reap:
    add si, TCB_SIZE
    loop .reap_loop
    popa
    ; ------------------------------------------

    ; 轮转调度：寻找下一个就绪任务
.find_next:
    mov al, [current_task]
    inc al
    cmp al, MAX_TASKS
    jb .check_task
    xor al, al                    ; 回绕到0
.check_task:
    mov [current_task], al

    xor ah, ah
    mov bx, TCB_SIZE
    mul bx
    mov si, tcb_array
    add si, ax

    cmp byte [si + TCB_STATE], 1  ; 检查是否就绪
    jne .find_next                ; 若非就绪继续查找

    ; 切换到选中的任务
    mov sp, [si + TCB_SP]
    mov ss, [si + TCB_SS]

    inc word [sys_ticks]          ; 更新系统时钟

    ; 恢复任务现场并返回
    pop es
    pop ds
    popa
    iret

; ----------------------------------------------------------------
; 创建守护任务 (空闲任务，显示水印)
; 分配独立栈 (0x4000段) 并将该任务注册到TCB索引1
; ----------------------------------------------------------------
create_daemon_task:
    cli
    mov ax, ss
    mov bx, sp

    ; 为守护任务分配新栈 (段0x4000，栈底0xFFFE)
    mov cx, 0x4000
    mov ss, cx
    mov sp, 0xFFFE

    ; 构造初始栈帧 (模拟中断返回)
    pushf
    pop dx
    or dx, 0x0200                 ; 设置中断标志 (IF=1)
    push dx                       ; FLAGS
    push cs                       ; CS
    mov dx, daemon_process
    push dx                       ; IP
    pusha                         ; 通用寄存器
    push ds                       ; DS
    push ds                       ; ES

    ; 将构造的栈指针存入TCB[1]
    mov si, tcb_array + 32        ; TCB索引1
    mov [si + TCB_SP], sp
    mov [si + TCB_SS], ss
    mov byte [si + TCB_STATE], 1  ; 标记为就绪

    ; 恢复原栈
    mov ss, ax
    mov sp, bx
    sti
    ret

; ----------------------------------------------------------------
; 守护任务主循环 (空闲时运行，显示水印)
; 每次被调度时刷新屏幕右下角的标志
; ----------------------------------------------------------------
daemon_process:
    mov ax, 0xB800
    mov es, ax

.refresh_loop:
    ; 显示位置：第24行，第68列 (偏移 = (24*80+68)*2 = 3968)
    mov di, 3968
    mov si, msg_watermark
    mov ah, 0x1F                  ; 蓝底白字

.draw:
    lodsb
    or al, al
    jz .wait_next
    stosw
    jmp .draw

.wait_next:
    hlt                           ; 等待下一次时钟中断
    jmp .refresh_loop

.daemon_loop:
    inc byte [es:di]              ; 备用闪烁效果 (未使用)
    jmp .daemon_loop

msg_watermark db "PPPOS - BETA", 0