[BITS 16]
[ORG 0x0000]

start:
    ; 1. 打印欢迎信息
    mov si, msg_start
    mov ah, 0x00
    int 0x80

    ; ==========================================
    ; 测试 1: 申请 1 个 4KB 块 (新接口 AH=0x46)
    ; ==========================================
    mov si, msg_alloc1
    mov ah, 0x00
    int 0x80

    mov ah, 0x46
    mov cx, 1               ; 申请 1 个 4KB
    int 0x80
    or ax, ax
    jz test_fail
    mov [seg_4k], ax        ; 保存段地址
    call print_hex_ax       ; 打印分配到的段地址

    ; ==========================================
    ; 测试 2: 申请 3 个 4KB 块 = 12KB (新接口 AH=0x46)
    ; ==========================================
    mov si, msg_alloc3
    mov ah, 0x00
    int 0x80

    mov ah, 0x46
    mov cx, 3               ; 申请 3 个 4KB
    int 0x80
    or ax, ax
    jz test_fail
    mov [seg_12k], ax
    call print_hex_ax

    ; ==========================================
    ; 测试 3: 申请 1 个 64KB 块 (旧接口 AH=0x40)
    ; ==========================================
    mov si, msg_alloc64
    mov ah, 0x00
    int 0x80

    mov ah, 0x40
    mov cx, 1               ; 申请 1 个 64KB (内核会转为 16 个 4KB)
    int 0x80
    or ax, ax
    jz test_fail
    mov [seg_64k], ax
    call print_hex_ax

    ; ==========================================
    ; 测试 4: 内存读写测试
    ; ==========================================
    mov si, msg_rw
    mov ah, 0x00
    int 0x80

    ; 测试 4KB 段
    mov es, [seg_4k]
    mov word [es:0x0000], 0xAA55
    mov ax, [es:0x0000]
    cmp ax, 0xAA55
    jne test_fail

    ; 测试 12KB 段的末尾 (由于段地址是起始地址，12KB = 0x3000 字节)
    mov es, [seg_12k]
    mov word [es:0x2FFE], 0x1234
    mov ax, [es:0x2FFE]
    cmp ax, 0x1234
    jne test_fail

    mov si, msg_ok
    mov ah, 0x00
    int 0x80

    ; ==========================================
    ; 测试 5: 释放内存 (统一接口 AH=0x41)
    ; ==========================================
    mov si, msg_free
    mov ah, 0x00
    int 0x80

    mov ah, 0x41
    mov bx, [seg_4k]
    int 0x80

    mov ah, 0x41
    mov bx, [seg_12k]
    int 0x80

    mov ah, 0x41
    mov bx, [seg_64k]
    int 0x80

    ; ==========================================
    ; 测试完成
    ; ==========================================
    mov si, msg_done
    mov ah, 0x00
    int 0x80
    jmp exit_app

test_fail:
    mov si, msg_fail
    mov ah, 0x00
    int 0x80

exit_app:
    ; 等待用户按任意键退出
    mov ah, 0x01
    int 0x80

    ; 退出任务
    mov ah, 0x04
    int 0x80

; ------------------------------------------------
; 辅助函数: 打印 AX 寄存器中的 16 位十六进制数
; ------------------------------------------------
print_hex_ax:
    pusha
    mov di, hex_buf
    mov cx, 4
.hex_loop:
    rol ax, 4
    mov bx, ax
    and bx, 0x0F
    mov dl, [hex_chars + bx]
    mov [di], dl
    inc di
    loop .hex_loop
    
    mov si, hex_buf
    mov ah, 0x00
    int 0x80
    popa
    ret

; ------------------------------------------------
; 数据区
; ------------------------------------------------
msg_start   db "=== PPP OS Memory Allocator Test ===", 13, 10, 0
msg_alloc1  db "Allocating 1x 4KB block... Seg: ", 0
msg_alloc3  db "Allocating 3x 4KB blocks.. Seg: ", 0
msg_alloc64 db "Allocating 1x 64KB block.. Seg: ", 0
msg_rw      db "Testing Memory R/W... ", 0
msg_ok      db "OK!", 13, 10, 0
msg_free    db "Freeing all allocated memory...", 13, 10, 0
msg_done    db "Test complete! Press any key to exit.", 13, 10, 0
msg_fail    db "FAILED!", 13, 10, 0

hex_chars   db "0123456789ABCDEF"
hex_buf     db "0000h", 13, 10, 0

seg_4k      dw 0
seg_12k     dw 0
seg_64k     dw 0