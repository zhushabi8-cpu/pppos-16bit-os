; ================================================================
; PPP OS 任务调度器与后台守护进程
; 基于时钟中断的轮转调度，支持最多 4 个任务
; ================================================================

; ---------- 任务控制块 (TCB) 偏移量 ----------
%define TCB_STATE   0          ; 任务状态（0=空闲, 1=就绪, 2=僵尸）
%define TCB_SP      1          ; 栈指针（2 字节）
%define TCB_SS      3          ; 栈段（2 字节）
%define TCB_SIZE    32         ; 每个 TCB 占用 32 字节
%define MAX_TASKS   4          ; 最大任务数

; ---------- 全局变量 ----------
old_int08       dw 0, 0        ; 保存原 BIOS 时钟中断向量（INT 0x08）
sys_ticks       dw 0           ; 系统时钟滴答计数（每次中断递增）
current_task    db 0           ; 当前运行任务的索引（0~3）
tcb_array       times MAX_TASKS * TCB_SIZE db 0   ; TCB 数组，共 128 字节

; ----------------------------------------------------------------
; 初始化任务管理器
; 安装自定义时钟中断处理程序，标记空闲任务为就绪
; ----------------------------------------------------------------
setup_task_manager:
    cli
    push es
    xor ax, ax
    mov es, ax

    ; 保存原 INT 0x08 向量（BIOS 时钟中断）
    mov ax, [es:0x20]
    mov [cs:old_int08], ax
    mov ax, [es:0x22]
    mov [cs:old_int08+2], ax

    ; 安装自定义时钟中断处理程序
    mov word [es:0x20], timer_isr
    mov word [es:0x22], cs

    ; 标记任务 0 为就绪（空闲任务）
    mov byte [tcb_array + TCB_STATE], 1

    pop es
    sti
    ret

; ----------------------------------------------------------------
; 时钟中断服务程序（约 18.2 Hz）
; 保存当前任务现场，执行任务切换，回收僵尸任务
; ----------------------------------------------------------------
timer_isr:
    pushf
    call far [cs:old_int08]          ; 调用原 BIOS 中断处理，维持系统时钟功能

    ; 保存当前任务的通用寄存器和段寄存器
    pusha
    push ds
    push es

    mov ax, cs
    mov ds, ax

    ; 将当前任务的 SP 和 SS 存入对应的 TCB
    mov al, [current_task]
    xor ah, ah
    mov bx, TCB_SIZE
    mul bx
    mov si, tcb_array
    add si, ax
    mov [si + TCB_SP], sp
    mov [si + TCB_SS], ss

    ; ---------- 僵尸任务回收器 ----------
    ; 扫描所有 TCB，释放处于僵尸状态（状态=2）的任务内存
    pusha
    mov cx, MAX_TASKS
    mov si, tcb_array
.reap_loop:
    cmp byte [si + TCB_STATE], 2
    jne .next_reap
    mov ax, [si + TCB_SS]            ; 获取任务占用的内存段
    call kfree                       ; 释放物理内存
    mov byte [si + TCB_STATE], 0     ; 清空 TCB 状态
.next_reap:
    add si, TCB_SIZE
    loop .reap_loop
    popa

    ; ---------- 轮转调度 ----------
    ; 从下一个任务开始，查找第一个就绪的任务
.find_next:
    mov al, [current_task]
    inc al
    cmp al, MAX_TASKS
    jb .check_task
    xor al, al                       ; 回绕到任务 0
.check_task:
    mov [current_task], al

    xor ah, ah
    mov bx, TCB_SIZE
    mul bx
    mov si, tcb_array
    add si, ax

    cmp byte [si + TCB_STATE], 1     ; 检查是否为就绪状态
    jne .find_next                   ; 非就绪则继续查找

    ; 切换到选中的任务：恢复其 SP 和 SS
    mov sp, [si + TCB_SP]
    mov ss, [si + TCB_SS]

    inc word [sys_ticks]             ; 更新系统时钟滴答计数

    ; 恢复任务现场并返回
    pop es
    pop ds
    popa
    iret

; ----------------------------------------------------------------
; 创建守护任务（空闲任务）
; 分配独立的栈空间（段 0x4000），注册到 TCB 索引 1
; ----------------------------------------------------------------
create_daemon_task:
    cli
    mov ax, ss
    mov bx, sp

    ; 切换到新栈段（0x4000），栈顶设为 0xFFFE
    mov cx, 0x4000
    mov ss, cx
    mov sp, 0xFFFE

    ; 构造初始栈帧，模拟中断返回时的状态
    pushf
    pop dx
    or dx, 0x0200                    ; 设置中断标志（IF=1）
    push dx                          ; FLAGS
    push cs                          ; CS
    mov dx, daemon_process
    push dx                          ; IP（入口地址）
    pusha                            ; 通用寄存器（初始为 0）
    push ds                          ; DS
    push ds                          ; ES

    ; 将构造的栈指针存入 TCB[1]
    mov si, tcb_array + 32           ; TCB 索引 1（偏移 32 字节）
    mov [si + TCB_SP], sp
    mov [si + TCB_SS], ss
    mov byte [si + TCB_STATE], 1     ; 标记为就绪

    ; 恢复原栈
    mov ss, ax
    mov sp, bx
    sti
    ret

; ----------------------------------------------------------------
; 守护任务主循环
; 在屏幕右下角持续显示水印字符串，每次被调度时刷新
; ----------------------------------------------------------------
daemon_process:
    mov ax, 0xB800
    mov es, ax

.refresh_loop:
    ; 显示位置：第 24 行，第 68 列（偏移 = (24*80+68)*2 = 3968）
    mov di, 3968
    mov si, msg_watermark
    mov ah, 0x1F                     ; 蓝底白字

.draw:
    lodsb
    or al, al
    jz .wait_next
    stosw
    jmp .draw

.wait_next:
    hlt                              ; 暂停 CPU，等待下一次时钟中断唤醒
    jmp .refresh_loop

.daemon_loop:
    inc byte [es:di]                 ; 备用（未使用）
    jmp .daemon_loop

msg_watermark db "PPPOS - BETA", 0