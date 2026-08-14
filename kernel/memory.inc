; PPP OS 内存管理器（位图）

mem_bitmap db 0
mem_sizes  times 8 db 0             ; 记录每个起始块分配了多少个连续块

kmalloc:
    pushf
    push bx
    push dx
    cli
    or cx, cx
    jnz .start_scan
    mov cx, 1                   ; 默认分配 1 块 (64KB)
.start_scan:
    mov dl, [cs:mem_bitmap]
    mov bx, 0
.check_window:
    mov ax, bx
    add ax, cx
    cmp ax, 8
    ja .fail                    ; 连续空间不足

    push cx
    push bx
    mov ah, 0
.build_mask:
    mov al, 1
    push cx
    mov cl, bl
    shl al, cl
    pop cx
    or ah, al
    inc bx
    loop .build_mask
    pop bx
    pop cx

    test dl, ah
    jz .found                   ; 找到连续的 0

    inc bx
    jmp .check_window

.found:
    or [cs:mem_bitmap], ah      ; 标记为占用
    mov [cs:mem_sizes + bx], cl ; 记录分配的块数
    mov ax, bx
    mov dx, 0x1000
    mul dx
    add ax, 0x2000              ; 计算起始段地址
    pop dx
    pop bx
    popf
    clc
    ret
.fail:
    pop dx
    pop bx
    popf
    stc
    ret

kfree:
    pushf
    pusha
    cli
    sub ax, 0x2000
    mov dx, 0
    mov bx, 0x1000
    div bx                      ; AX = 起始块索引

    mov bx, ax
    mov cl, [cs:mem_sizes + bx] ; 获取分配的块数
    xor ch, ch
    or cx, cx
    jnz .start_free
    mov cx, 1                   ; 兼容保护
.start_free:
    mov byte [cs:mem_sizes + bx], 0 ; 清除记录

    mov ah, 0
.build_free_mask:
    mov bl, 1
    push cx
    mov cl, al
    shl bl, cl
    pop cx
    or ah, bl
    inc ax
    loop .build_free_mask

    not ah
    and [cs:mem_bitmap], ah     ; 清除位图占用
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