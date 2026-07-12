; =======================================================
; com.asm - PPP OS 的 16 位 DOS .COM 文件加载器
; 外部打包器会添加 16 字节 PEX 头，此文件为载荷主体
; =======================================================
[BITS 16]
[ORG 0x0000]

start:
    push cs
    pop ds
    push cs
    pop es

    ; 在 PSP 起始处写入 INT 0x20 指令，使 RET 可正常退出
    mov word [0x0000], 0x20CD

    jmp real_start

; ---- 静态数据区固定在 PSP 保留区（0x002E~0x005B），不覆盖 0x0080 命令行区 ----
TIMES 0x002E - ($ - $$) db 0
target_file times 16 db 0           ; 待加载的 .COM 文件名（0x002E）
arg_buf     times 12 db 0           ; 参数2缓冲区（0x003E）

TIMES 0x004A - ($ - $$) db 0

real_start:
    ; 获取参数1（目标程序名）
    mov ah, 0x16
    mov di, target_file
    int 0x80
    cmp byte [target_file], ' '
    jbe .abort_exit

    ; 设置 DOS 版本为 6.22
    mov ah, 0xFF
    mov bh, 6
    mov bl, 22
    int 0x21

    ; 读取目标 .COM 到 0x0100（标准 DOS 入口）
    mov ah, 0x02
    mov si, target_file
    mov di, 0x0100
    int 0x80
    or al, al
    jz .abort_exit

    ; 伪装 PSP 字段
    mov word [0x0002], 0x9FFF       ; 内存顶端
    mov word [0x002C], 0x0000       ; 环境块

    ; 参数2 填入 0x0080 命令行区
    mov ah, 0x1D
    mov di, arg_buf
    int 0x80
    mov si, arg_buf
    mov di, 0x0081
    mov byte [0x0081], ' '
    inc di
    xor cx, cx
.copy_arg:
    lodsb
    cmp al, ' '
    jbe .copy_done
    stosb
    inc cx
    jmp .copy_arg
.copy_done:
    mov al, 0x0D
    stosb
    inc cx
    mov byte [0x0080], cl

    ; 清空 FCB 区
    mov di, 0x005C
    mov cx, 16
    xor ax, ax
    rep stosw

    ; 设置栈为 CS:0xFFFE，保证 RET 返回时能回到 0x0000 执行 INT 0x20
    cli
    mov ax, cs
    mov ss, ax
    mov sp, 0xFFFE
    sti

    push word 0x0000                ; 返回地址

    jmp 0x0100                      ; 跳转到加载的程序

.abort_exit:
    mov ah, 0x04
    int 0x80