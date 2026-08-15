; PPP OS 内存管理器（位图） - 4KB 粒度版本
; 物理内存映射区：0x20000 ~ 0x9FFFF (512KB)
; 1 块 = 4KB (0x0100 段)
; 总容量 = 128 块 (128 bits = 16 bytes)

mem_bitmap times 16 db 0        ; 16 字节 = 128 位
mem_sizes  times 128 db 0       ; 记录每个起始块分配了多少个连续块

kmalloc:
    pushf
    push bx
    push cx
    push dx
    push si
    push di
    cli
    
    or cx, cx
    jnz .start_scan
    mov cx, 1                   ; 默认分配 1 块 (4KB)
    
.start_scan:
    mov bx, 0                   ; BX = 起始位索引 (0~127)
.check_window:
    mov ax, bx
    add ax, cx
    cmp ax, 128
    ja .fail                    ; 剩余连续空间不足

    mov dx, cx                  ; DX = 需要检查的位数
    mov si, bx                  ; SI = 当前位索引
.test_loop:
    mov di, si
    shr di, 3                   ; DI = 字节索引 (SI / 8)
    push cx
    mov cx, si                  ; 【修复】将 SI 传给 CX，CL 自动获得低 8 位
    and cl, 7                   ; CL = 位偏移 (SI % 8)
    mov al, 1
    shl al, cl
    pop cx
    test [cs:mem_bitmap + di], al
    jnz .window_failed          ; 发现被占用的位，窗口匹配失败
    inc si
    dec dx
    jnz .test_loop

    ; 找到连续的空闲块，标记为已占用
    mov dx, cx
    mov si, bx
.set_loop:
    mov di, si
    shr di, 3
    push cx
    mov cx, si
    and cl, 7
    mov al, 1
    shl al, cl
    pop cx
    or [cs:mem_bitmap + di], al
    inc si
    dec dx
    jnz .set_loop

    mov [cs:mem_sizes + bx], cl ; 记录分配的块数 (CX 的低8位)
    
    ; 计算起始段地址: AX = BX * 0x0100 + 0x2000
    mov ax, bx
    mov dx, 0x0100              ; 4KB = 0x0100 段
    mul dx
    add ax, 0x2000

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    popf
    clc
    ret

.window_failed:
    inc bx                      ; 滑动窗口，找下一个起始位
    jmp .check_window

.fail:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    popf
    stc
    ret

kfree:
    pushf
    pusha
    cli
    sub ax, 0x2000
    xor dx, dx
    mov bx, 0x0100
    div bx                      ; AX = 起始块索引 (0~127)

    mov bx, ax
    mov cl, [cs:mem_sizes + bx] ; 获取分配的块数
    xor ch, ch
    or cx, cx
    jnz .start_free
    mov cx, 1                   ; 兼容保护
.start_free:
    mov byte [cs:mem_sizes + bx], 0 ; 清除记录

    mov si, bx                  ; SI = 当前位索引
.clear_loop:
    mov di, si
    shr di, 3
    push cx
    mov cx, si
    and cl, 7
    mov al, 1
    shl al, cl
    not al                      ; 取反用于清除位
    pop cx
    and [cs:mem_bitmap + di], al
    inc si
    loop .clear_loop

.safe_exit:
    popa
    popf
    ret

drv_heap_seg dw 0x1000

drv_malloc:
    push bx
    cli
    mov ax, [cs:drv_heap_seg]
    mov bx, cx
    shl bx, 5
    push ax
    add ax, bx
    cmp ax, 0x2000
    jae .drv_oom
    mov [cs:drv_heap_seg], ax
    pop ax
    sti
    pop bx
    clc
    ret
.drv_oom:
    pop ax
    sti
    pop bx
    stc
    ret