;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; `ASM.ASM' -- Ported to PPP OS (.PEX Executable)
; Original 8086 Assembler Copyright (c) 2001 Stephen Duffy
; PPP OS Port: Replaced DOS INT 21h with PPP OS INT 0x80 VFS calls..
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[BITS 16]
[ORG 0x0000]

maxexplen   equ 80
maxsymlen   equ 30
symstack    equ 0b000h
buflen      equ 80

; Memory offsets for whole-file I/O buffering
INPUT_BUFFER_OFFSET  equ 0x4000
OUTPUT_BUFFER_OFFSET equ 0xA000

    jmp start   ; jump to main

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; data starts here
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

msg_banner: db "8086 Assembler for PPP OS",13,10
        db "Original by Stephen Duffy",13,10
        db "Ported to PPP OS .PEX format",13,10
        db 13,10,0
msg_pass:   db ">> Pass ",0
msg_started:    db " started",13,10,0
msg_finished:   db "<< Finished successfully",13,10,0
msg_linesproc:  db " lines processed",13,10,0
msg_byteswrit:  db " bytes written",13,10,0
msg_errline:    db "Error at line ",0
msg_colon:  db ": ",0
msg_tab:    db "  ",0
msg_crlf:   db 13,10,0

errmsg_strtoolong:  db   1,"String too long",13,10,0
errmsg_linetoolong: db   2,"Line too long",13,10,0
errmsg_unknownmne:  db   3,"Unknown mnemonic",13,10,0
errmsg_invparams:   db   4,"Illegal parameters",13,10,0
errmsg_illidir:     db   5,"Illegal expression",13,10,0
errmsg_ptrexp:      db   6,"`PTR' expected",13,10,0
errmsg_ptrtoolarge: db   7,"Pointer too large",13,10,0
errmsg_inviform:    db   8,"Invalid instruction format",13,10,0
errmsg_badregmix:   db   9,"Invalid register size",13,10,0
errmsg_invnumform:  db  10,"Bad literal",13,10,0
errmsg_littoolarge: db  11,"Literal too large",13,10,0
errmsg_offtoolarge: db  12,"Address too far",13,10,0
errmsg_toomanysym:  db  13,"Too many symbols",13,10,0
errmsg_invsymnam:   db  14,"Symbol name too long",13,10,0
errmsg_undefsym:    db  15,"Unknown symbol",13,10,0

errmsg_inferr:      db 201,"Input file error (Not found)",13,10,0
errmsg_ouferr:      db 202,"Output file error",13,10,0
errmsg_nofile:      db 203,"Usage: ASM <filename>",13,10,0

linestore:      times 80 dw 0
labelstore:     times 80 dw 0
mnemonicstore:  times 80 dw 0
expsetstore:    times 80 dw 0
exp1store:      times 80 dw 0
exp2store:      times 80 dw 0
codestore:      times 160 dw 0
tempbuffer:     times 160 dw 0
getsbuffer:     times 80 dw 0
___getsbuffer:

; PPP OS File I/O Variables
sys_arg_buf     times 12 db 0
in_filename     times 16 db 0
out_filename    times 16 db 0
in_buf_ptr      dw 0
out_buf_ptr     dw 0

digitlist:
    db "00112233445566778899aAbBcCdDeEfFgGhHiIjJkK"
    db "lLmMnNoOpPqQrRsStToOpPqQrRsStTuUvVwWxXyYzZ",0
destructivedl:
    db "00112233445566778899aAbBcCdDeEfFgGhHiIjJkK"
    db "lLmMnNoOpPqQrRsStToOpPqQrRsStTuUvVwWxXyYzZ",0
delimiters:
    db " `!",'"',"%^&*()-+=[{]};:'~,<.>/?",92,"|",0
indirectregs:
    db "bp",0,1
    db "bx",0,2
    db "di",0,4
    db "si",0,8
___indirectregs:
iregcomb: 
    db 10,6,9,5,8,4,0,2,1
    db 0,1,2,3,4,5,6,7,6
___iregcomb:
bptr:   db "byte",0
wptr:   db "word",0
dptr:   db "dword",0
qptr:   db "qword",0
aptr:   db "ptr",0
farstring:
    db "far",0
regnames:
    db "ah",0,32,4
    db "al",0,32,0
    db "ax",0,48,0
    db "bh",0,32,7
    db "bl",0,32,3
    db "bp",0,48,5
    db "bx",0,48,3
    db "ch",0,32,5
    db "cl",0,32,1
    db "cs",0,64,1
    db "cx",0,48,1
    db "dh",0,32,6
    db "di",0,48,7
    db "dl",0,32,2
    db "ds",0,64,3
    db "dx",0,48,2
    db "es",0,64,0
    db "si",0,48,6
    db "sp",0,48,4
    db "ss",0,64,2
___regnames:
segregs:
    db "cs",0
    db "ds",0
    db "es",0
    db "ss",0
___segregs:
mnemonics:
    db "aaa",0,0,0,0,    1ah
    db "aad",0,0,0,0,    1dh
    db "aam",0,0,0,0,    1ch
    db "aas",0,0,0,0,    1bh
    db "adc",0,0,0,0,    02h
    db "add",0,0,0,0,    00h
    db "and",0,0,0,0,    04h
    db "call",0,0,0,     3ah
    db "cbw",0,0,0,0,    64h
    db "clc",0,0,0,0,    88h
    db "cld",0,0,0,0,    8ch
    db "cli",0,0,0,0,    8ah
    db "cmc",0,0,0,0,    85h
    db "cmp",0,0,0,0,    07h
    db "cmpsb",0,0,      56h
    db "cmpsw",0,0,      57h
    db "cs:",0,0,0,0,    09h
    db "cwd",0,0,0,0,    65h
    db "daa",0,0,0,0,    18h
    db "das",0,0,0,0,    19h
    db "dec",0,0,0,0,    39h
    db "div",0,0,0,0,    36h
    db "ds:",0,0,0,0,    0bh
    db "es:",0,0,0,0,    08h
    db "hlt",0,0,0,0,    84h
    db "idiv",0,0,0,     37h
    db "imul",0,0,0,     35h
    db "in",0,0,0,0,0,   76h
    db "inc",0,0,0,0,    38h
    db "int",0,0,0,0,    6fh
    db "into",0,0,0,     70h
    db "iret",0,0,0,     71h
    db "ja",0,0,0,0,0,   47h
    db "jae",0,0,0,0,    43h
    db "jb",0,0,0,0,0,   42h
    db "jbe",0,0,0,0,    46h
    db "jc",0,0,0,0,0,   42h
    db "jcxz",0,0,0,     0e3h
    db "je",0,0,0,0,0,   44h
    db "jg",0,0,0,0,0,   4fh
    db "jge",0,0,0,0,    4dh
    db "jl",0,0,0,0,0,   4ch
    db "jle",0,0,0,0,    4eh
    db "jmp",0,0,0,0,    3ch
    db "jna",0,0,0,0,    46h
    db "jnae",0,0,0,     42h
    db "jnb",0,0,0,0,    43h
    db "jnbe",0,0,0,     47h
    db "jnc",0,0,0,0,    43h
    db "jne",0,0,0,0,    45h
    db "jng",0,0,0,0,    4eh
    db "jnge",0,0,0,     4ch
    db "jnl",0,0,0,0,    4dh
    db "jnle",0,0,0,     4fh
    db "jno",0,0,0,0,    41h
    db "jnp",0,0,0,0,    4bh
    db "jns",0,0,0,0,    49h
    db "jnz",0,0,0,0,    45h
    db "jo",0,0,0,0,0,   40h
    db "jp",0,0,0,0,0,   4ah
    db "jpe",0,0,0,0,    4ah
    db "jpo",0,0,0,0,    4bh
    db "js",0,0,0,0,0,   48h
    db "jz",0,0,0,0,0,   44h
    db "lahf",0,0,0,     6ah
    db "lds",0,0,0,0,    6dh
    db "lea",0,0,0,0,    62h
    db "les",0,0,0,0,    6ch
    db "lock",0,0,0,     80h
    db "lodsb",0,0,      5ch
    db "lodsw",0,0,      5dh
    db "loop",0,0,0,     0e2h
    db "loope",0,0,      0e1h
    db "loopne",0,       0e0h
    db "loopnz",0,       0e0h
    db "loopz",0,0,      0e1h
    db "mov",0,0,0,0,    61h
    db "movsb",0,0,      54h
    db "movsw",0,0,      55h
    db "mul",0,0,0,0,    34h
    db "neg",0,0,0,0,    33h
    db "nop",0,0,0,0,    63h
    db "not",0,0,0,0,    32h
    db "or",0,0,0,0,0,   01h
    db "out",0,0,0,0,    77h
    db "pop",0,0,0,0,    3fh
    db "popf",0,0,0,     68h
    db "push",0,0,0,     3eh
    db "pushf",0,0,      67h
    db "rcl",0,0,0,0,    12h
    db "rcr",0,0,0,0,    13h
    db "rep",0,0,0,0,    83h
    db "repe",0,0,0,     83h
    db "repne",0,0,      82h
    db "repnz",0,0,      82h
    db "repz",0,0,0,     83h
    db "ret",0,0,0,0,    6bh
    db "retf",0,0,0,     6eh
    db "rol",0,0,0,0,    10h
    db "ror",0,0,0,0,    11h
    db "sahf",0,0,0,     69h
    db "sar",0,0,0,0,    17h
    db "sbb",0,0,0,0,    03h
    db "scasb",0,0,      5eh
    db "scasw",0,0,      5fh
    db "shl",0,0,0,0,    14h
    db "shr",0,0,0,0,    15h
    db "ss:",0,0,0,0,    0ah
    db "stc",0,0,0,0,    89h
    db "std",0,0,0,0,    8dh
    db "sti",0,0,0,0,    8bh
    db "stosb",0,0,      5ah
    db "stosw",0,0,      5bh
    db "sub",0,0,0,0,    05h
    db "test",0,0,0,     30h
    db "wait",0,0,0,     66h
    db "xchg",0,0,0,     60h
    db "xlat",0,0,0,     72h
    db "xor",0,0,0,0,    06h
___mnemonics:
mnetranslate:
    db 01ah,037h,01dh,0d5h,01ch,0d4h,01bh,03fh,064h,098h,088h,0f8h,08ch,0fch
    db 08ah,0fah,085h,0f5h,056h,0a6h,057h,0a7h,009h,02eh,065h,099h,018h,027h
    db 019h,02eh,00bh,03eh,008h,026h,084h,0f4h,070h,0ceh,071h,0cfh,06ah,09fh
    db 080h,0f0h,05ch,0ach,05dh,0adh,054h,0a4h,055h,0a5h,063h,090h,068h,09dh
    db 067h,09ch,082h,0f2h,083h,0f3h,06bh,0c3h,06eh,0cbh,069h,09eh,05eh,0aeh
    db 05fh,0afh,00ah,036h,089h,0f9h,08dh,0fdh,08bh,0fbh,05ah,0aah,05bh,0abh
    db 066h,09bh,072h,0d7h
equalitytext:
    db "equ",0
pseudoops:
    db "db",0,0,0,0,0,0,0
    db "dw",0,0,0,0,0,0,1
    db "equ",0,0,0,0,0,2
    db "=",0,0,0,0,0,0,0,2
___pseudoops:

assumedbase:    dw 10
nextsymbol: dw symstack
symbolload: dw 0
curip:      dw 0
codebase:   dw 0        ; PPP OS PEX format starts code at 0
codelen:    dw 0
line:       dw 0
curpass:    db 1
addrspec:   dw 0
containslabel:  dw 0
eof:        dw 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; code starts here
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

strlen:
    push di
    push cx
    mov al,0
    mov cx,-1
    cmp cx,cx
    cld
    repnz
    scasb
    neg cx
    dec cx
    dec cx
    xchg ax,cx
    pop cx
    pop di
    ret
strpos:
    push di
    push cx
    push ax
    call strlen
    xchg cx,ax
    pop ax
    mov cx,-1
    cld
    repnz
    scasb
    neg cx
    dec cx
    dec cx
    xchg ax,cx
    pop cx
    pop di
    ret
strnpos:
    push di
    push cx
    push ax
    call strlen
    xchg cx,ax
    pop ax
    mov cx,-1
    cld
    repz
    scasb
    neg cx
    dec cx
    dec cx
    xchg ax,cx
    pop cx
    pop di
    ret
strrev:
    push si
    push di
    push ax
    mov si,di
    call strlen
    dec ax
    add si,ax
___strrev:
    mov al,[di]
    mov ah,[si]
    mov [si],al
    mov [di],ah
    inc di
    dec si
    cmp di,si
    jl ___strrev
    pop ax
    pop di
    pop si
    ret
strlwr:
    push ax
    push bx
    xor bx,bx
    xor ah,ah
    dec bx
___nextlwr:
    inc bx
    mov al,[bx+di]
    cmp al,0
    je ___strlwr
    cmp al,'"'
    je ___togq
    cmp al,'`'
    je ___togq
    cmp al,"'"
    je ___togq
    cmp al,'A'
    jl ___nextlwr
    cmp al,'Z'
    jg ___nextlwr
    test ah,1
    jnz ___nextlwr
    add al,32
    mov [bx+di],al
    jmp ___nextlwr
___togq:
    xor ah,1
    jmp ___nextlwr
___strlwr:
    pop bx
    pop ax
    ret
strcpy:
    push di
    push si
    push ax
    xchg si,di
    call strlen
    inc ax
    xchg si,di
    xchg ax,cx
    cmp di,si
    cld
    repnz
    movsb
    xchg ax,cx
    pop ax
    pop si
    pop di
    ret
strcmp:
    push bx
    push cx
    xor bx,bx
    call strlen
    xchg ax,cx
    xchg si,di
    call strlen
    xchg si,di
    cmp cx,ax
    je ___mainstrcmp
    jl ___dismall
    mov bx,-1
    xchg ax,cx
    jmp ___mainstrcmp
___dismall:
    mov bx,1
___mainstrcmp:
    push si
    push di
    cld
    repz
    cmpsb
    jl ___diless
    jg ___siless
    xchg ax,bx
    jmp ___strcmp
___diless:
    mov ax,-1
    jmp ___strcmp
___siless:
    mov ax,1
___strcmp:
    pop di
    pop si
    pop cx
    pop bx
    ret
replacetabs:
    push ax
    push bx
    mov ax,02009h
    mov bx,0
    dec bx
___replacetabs:
    inc bx
    cmp [di+bx],al
    jne ___nottab
    mov [di+bx],ah
___nottab:
    cmp byte [di+bx],0
    jne ___replacetabs
    pop bx
    pop ax
    ret
removetrails:
    push si
    push cx
    push ax
    xor ah,ah
    mov al,' '
    call strnpos
    mov si,di
    add si,ax
    call strcpy
    pop ax
    pop cx
    pop si
    ret
removeleads:
    call strrev
    call removetrails
    call strrev
    ret
removespaces:
    push si
    push di
    push ax
    push dx
    mov si,di
    call strlen
    xchg dx,ax
___nextspace:
    mov al,' '
    call strpos
    cmp ax,dx
    jge ___removespaces
    sub dx,ax
    add di,ax
    mov si,di
    inc si
    call strcpy
    cmp dx,0
    jne ___nextspace
___removespaces:
    pop dx
    pop ax
    pop di
    pop si
    ret
removecomment:
    push ax
    push bx
    mov al,';'
    call outofquote
    mov bx,ax
    mov byte [di+bx],0
    pop bx
    pop ax
    ret
unbracket:
    mov cx,1
    call removetrails
    cmp byte [di],'['
    je ___openpres
    xor cx,cx
___openpres:
    inc di
    call strrev
    call removetrails
    cmp byte [di],']'
    je ___closepres
    xor cx,cx
___closepres:
    inc di
    call strrev
    ret
ntos:
    push ax
    push bx
    push cx
    push dx
    push di
___ntos:
    xor dx,dx
    div bx
    xchg ax,cx
    mov al,dl
    cmp al,9
    jle ___notalpha
    add al,7
___notalpha:
    add al,48
    mov [di],al
    inc di
    xchg cx,ax
    cmp ax,0
    jne ___ntos
    mov [di],0
    pop di
    call strrev
    pop dx
    pop cx
    pop bx
    pop ax
    ret
ston:
    push cx
    push dx
    push si
    push di
    push bx
    mov si,1
    xor cx,cx
    call strlen
    xchg ax,bx
___decloop:
    dec bx
    mov al,[di+bx]
    cmp al,'a'
    jl  ___upperdigit
    sub al,32
___upperdigit:
    cmp al,'A'
    jl ___normdigit
    sub al,7
___normdigit:
    sub al,48
    xor ah,ah
    xor dx,dx
    mul si
    add cx,ax
    pop ax
    push ax
    xor dx,dx
    mul si
    xchg ax,si
    cmp bx,0
    jne ___decloop
    mov ax,cx
    pop bx
    pop di
    pop si
    pop dx
    pop cx
    ret
testdigits:
    push ax
    push dx
    push bx
    call strlen
    xchg dx,ax
    push si
    push di
    mov di,destructivedl
    mov si,digitlist
    call strcpy
    pop si
    mov ax,2
    push dx
    mul bx
    pop dx
    xchg bx,ax
    mov byte [di+bx],0
    call strlen
    xchg ax,cx
    xor bx,bx
___nextdigit:
    mov al,[si+bx]
    call strpos
    cmp ax,cx
    jl ___validdigit
    mov cx,0
    jmp ___testdigits
___validdigit:
    inc bx
    cmp bx,dx
    jl ___nextdigit
    mov cx,1
___testdigits:
    pop di
    xchg si,di
    pop bx
    pop dx
    pop ax
    ret
aton:
    push di
    push bx
    push dx
    push si
    mov bx,1
    cmp byte [di],'+'
    je ___signposi
    cmp byte [di],'-'
    jne ___nosign
    mov bx,-1
___signposi:
    inc di
___nosign:
    push bx
    mov ax,word [assumedbase]
    xchg ax,dx
    call strlen
    xchg cx,ax
    mov al,'x'
    call strpos
    cmp ax,cx
    jg ___noleadx
    add di,ax
    inc di
    mov dx,16
___noleadx:
    call strlen
    xchg ax,bx
    cmp bx,0
    jle ___atedge
    dec bx
___atedge:
    cmp byte [di+bx],'t'
    jne ___testhex
    mov si,[di+bx]
    mov byte [di+bx],0
    mov dx,10
    jmp ___notrailchar
___testhex:
    cmp byte [di+bx],'h'
    jne ___testoct
    mov si,[di+bx]
    mov byte [di+bx],0
    mov dx,10h
    jmp ___notrailchar
___testoct:
    cmp byte [di+bx],'o'
    jne ___testbin
    mov si,[di+bx]
    mov byte [di+bx],0
    mov dx,8h
    jmp ___notrailchar
___testbin:
    cmp byte [di+bx],'n'
    jne ___trailends
    mov si,[di+bx]
    mov byte [di+bx],0
    mov dx,2
    jmp ___notrailchar
___trailends:
    mov si,[di+bx]
___notrailchar:
    push bx
    mov bx,dx
    call testdigits
    cmp cx, 0
    je ___aton
    call ston
    mov cx,1
___aton:
    pop bx
    mov [di+bx],si
    pop bx
    mul bx
    pop si
    pop dx
    pop bx
    pop di
    ret
outofquote:
    push cx
    push bx
    push si
    push di
    xor cx,cx
    xor bx,bx
    dec bx
___nextqtest:
    inc bx
    cmp byte [bx+di],'"'
    je ___togdqte
    cmp byte [bx+di],"'"
    je ___togsqte
    cmp [bx+di],al
    je ___testqopen
    cmp byte [bx+di],0
    jne ___nextqtest
    call strlen
    jmp ___outofquote
___togdqte:
    cmp bx,0
    jle ___notlitdqte
    cmp byte [bx+di-1],92
    je ___nextqtest
___notlitdqte:
    test cx,1
    jnz ___nextqtest
    xor cx,2
    jmp ___nextqtest
___togsqte:
    cmp bx,0
    jle ___notlitsqte
    cmp byte [bx+di-1],92
    je ___nextqtest
___notlitsqte:
    test cx,2
    jnz ___nextqtest
    xor cx,1
    jmp ___nextqtest
___testqopen:
    test cx,3
    jnz ___nextqtest
    mov ax,bx
___outofquote:
    pop di
    pop si
    pop bx
    pop cx
    ret
qtostest:
    push dx
    push si
    push di
    mov si,di
    mov dh,[di]
    cmp dh,"'"
    je ___qtoscont
    cmp dh,"`"
    je ___qtoscont
    cmp dh,'"'
    je ___qtoscont
    xor cx,cx
    jmp ___qtostest
___qtoscont:
    inc di
___nextqtchar:
    mov al,[di]
    cmp al,92
    jne ___testqtquote
    inc di
    inc di
___testqtquote:
    cmp al,dh
    jne ___testqtend
    mov cx,1
    jmp ___qtostest
___testqtend:
    inc si
    inc di
    cmp byte [di],0
    jne ___nextqtchar
    xor cx,cx
___qtostest:
    mov ax,di
    pop di
    sub ax,di
    inc ax
    pop si
    pop dx
    ret
qtos:
    push ax
    push dx
    push si
    push di
    mov si,di
    mov dh,[di]
    xor cx,cx
    inc si
    call strcpy
    dec si
___nextchar:
    mov al,[di]
    cmp al,92
    jne ___testquote
    inc si
    mov al,[si]
    cmp al,'n'
    jne ___notnewline
    mov byte [si],10
    jmp ___delslash
___notnewline:
    cmp al,'t'
    jne ___nottabchar
    mov byte [si],9
    jmp ___delslash
___nottabchar:
    cmp al,'r'
    jne ___notreturn
    mov byte [si],13
    jmp ___delslash
___notreturn:
___delslash:
    call strcpy
    dec si
    jmp ___testend
___testquote:
    cmp al,dh
    jne ___testend
    mov [di],0
    mov cx,1
    jmp ___qtos
___testend:
    inc si
    inc di
    cmp byte [di],0
    jne ___nextchar
    xor cx,cx
___qtos:
    pop di
    pop si
    pop dx
    pop ax
    ret
btow:
    push ax
    push si
    push cx
    push di
    add cx,si
    xor ah,ah
___btow:
    mov al,[si]
    mov [di],ax
    inc di
    inc di
    inc si
    cmp si,cx
    jle ___btow
    pop di
    pop cx
    pop si
    pop ax
    ret
strtok:
    push bx
    push dx
    push ax
    call strlen
    mov dx,ax
    pop ax
    mov si,delimiters
    xor bx,bx
    cmp al,0
    je ___nodelim
    mov [di],al
___nodelim:
    call removetrails
    cld
    dec bx
___nextch:
    inc bx
    mov al,[bx+di]
    cmp al,0
    jz ___strtok
    xchg si,di
    push ax
    call strlen
    xchg cx,ax
    pop ax
    push di
    cld
    repnz
    scasb
    pop di
    xchg si,di
    cmp cx, 0
    je ___nextch
    cmp bx,0
    jg ___swapdelim
    inc bx
___swapdelim:
    mov al,byte [bx+di]
    mov byte [bx+di],0
___strtok:
    mov si,di
    add si,bx
    pop dx
    pop bx
    ret
unstrtok:
    push bx
    push ax
    call strlen
    pop bx
    xchg bx,ax
    mov [di+bx],al
    pop bx
    ret
chopsearch:
    push bx
    push cx
    push dx
    push di
    jmp chop
halfdiff:
    mov ax,bx
    sub ax,si
    div cx
    shr ax,1
    mul cx
    ret
comparemid:
    push si
    add si,ax
    add si,dx
    call strcmp
    pop si
    ret
chop:
    call halfdiff
    cmp ax,cx
    jl endchop
    call halfdiff
    call comparemid
    cmp al,0
    je endchop
    cmp al,-1
    je higher
    call halfdiff
    sub bx,ax
    jmp chop
higher:
    call halfdiff
    add si,ax
    jmp chop
endchop:
    call halfdiff
    add si,ax
    call strcmp
    xor ah,ah
    pop di
    pop dx
    pop cx
    pop bx
    ret
getsymbol:
    push si
    push dx
    push bx
    cmp word [symbolload],0
    jne ___pass2get
    call fetchsymbol
    jmp ___getsymbol
___pass2get:
    mov si,[nextsymbol]
    add si,32
    mov bx,symstack
    add bx,32
    mov cx,32
    mov dx,0
    call chopsearch
    cmp ax,0
    je ___symfound
    xor cx,cx
    xor ax,ax
    mov di,errmsg_undefsym
    jmp ___getsymbol
___symfound:
    mov cx,1
    mov ax,[si+30]
___getsymbol:
    pop bx
    pop dx
    pop si
    ret
fetchsymbol:
    push si
    mov cx,2
    mov si,[nextsymbol]
___nextsym:
    mov ax,07fffh
    cmp si,symstack
    je ___fetchsymbol
    add si,32
    call strcmp
    cmp ax,0
    jne ___nextsym
    mov ax,[si+30]
    mov cx,1
___fetchsymbol:
    pop si
    ret
addsymbol:
    push ax
    push dx
    push si
    mov cx,1
    cmp word [symbolload],0
    jne ___addsymbol
    mov dx,ax
    call strlen
    cmp ax,30
    jl ___symlenok
    xor cx,cx
    mov di,errmsg_invsymnam
    jmp ___addsymbol
___symlenok:
    mov si,[nextsymbol]
    cmp si,___endofcode
    jnb ___symnumok
    xor cx,cx
    mov di,errmsg_toomanysym
    jmp ___addsymbol
___symnumok:
    xchg si,di
    push si
    push di
    mov ax,0
    std
    mov cx,32
    cmp cx,cx
    repz
    stosb
    pop di
    pop si
    call strcpy
    mov [di+30],dx
    sub word [nextsymbol],32
    xchg si,di
    mov cx,1
___addsymbol:
    pop si
    pop dx
    pop ax
    ret
copysym:
    push di
    push si
    push cx
    mov cx,32
    cmp cx,cx
    cld
    repz
    movsb
    pop cx
    pop si
    pop di
    ret
swapsym:
    push di
    mov di,tempbuffer
    call copysym
    pop di
    xchg si,di
    call copysym
    xchg si,di
    push si
    mov si,tempbuffer
    call copysym
    pop si
    ret
sortsym:
    push ax
    push dx
    push bx
    push si
    push di
    mov bx,[nextsymbol]
    mov dx,symstack
    cmp bx,dx
    je ___sortsym
___rebubble:
    add bx,32
    cmp bx,dx
    je ___sortsym
    mov di,dx
    mov si,dx
    sub si,32
___bubbleup:
    call strcmp
    cmp ax,0
    jl ___noswapsym
    call swapsym
___noswapsym:
    sub di,32
    sub si,32
    cmp di,bx
    jne ___bubbleup
    jmp ___rebubble
___sortsym:
    pop di
    pop si
    pop bx
    pop dx
    pop ax
    ret
decodeindirect:
    mov word [containslabel],0
    mov word [addrspec],0
    push si
    push bx
    call unbracket
    cmp cx,0
    jne ___unbracketed
    mov di,errmsg_illidir
    jmp ___decodeindirect
___unbracketed:
    xor dx,dx
    or dl,10h
    mov ax,0
___nextparm:
    call strtok
    push si
    push ax
    mov si,indirectregs
    mov bx,___indirectregs
    mov cx,4
    push dx
    mov dx,0
    call chopsearch
    pop dx
    cmp al,0
    jne ___regnotfound
    mov al,byte [si+3]
    xor ah,ah
    test dl,al
    jz ___noteireg
___illidirexit:
    mov di,errmsg_illidir
    xor cx,cx
    pop ax
    pop si
    jmp ___decodeindirect
___noteireg:
    or dl,al
    jmp ___nextreg
___regnotfound:
    mov al,byte [di]
    cmp al,'-'
    jne ___testplus
    or dl,20h
    and dl,0efh
    jmp ___nextreg
___testplus:
    cmp al,'+'
    jne ___testnumber
    or dl,10h
    and dl,0dfh
    jmp ___nextreg
___testnumber:
    push ax
    call aton
    cmp cx,0
    je ___assumelabel
    pop cx
    xchg ax,cx
    push cx
    jmp ___test2address
___assumelabel:
    call getsymbol
    cmp cx,0
    je ___undeflabel
    pop cx
    xchg ax,cx
    push cx
___test2address:
    pop ax
    or dl,64
    test dl,20h
    jz ___logaddress
    neg ax
___logaddress:
    add word [addrspec],ax
    jmp ___nextreg
___undeflabel:
    pop ax
    mov di,errmsg_undefsym
    xor cx,cx
    pop ax
    pop si
    jmp ___decodeindirect
___nextreg:
    pop ax
    pop si
    mov di,si
    cmp al,0
    je ___idexpokay
    jmp ___nextparm
___idexpokay:
    mov dh,dl
    and dl,79
    cmp dl,1
    jne ___notbpalone
    mov di,errmsg_illidir
    xor cx,cx
    jmp ___decodeindirect
___notbpalone:
    mov dl,dh
    push bx
    push di
    mov di,iregcomb
    mov bx,0
    and dl,15
___nextconv:
    cmp byte [di+bx],dl
    je ___convert
    inc bx
    cmp bx,9
    jne ___nextconv
    pop di
    pop bx
    mov cx,0
    mov di,errmsg_illidir
    jmp ___decodeindirect
___convert:
    add bx,9
    mov dl,byte [di+bx]
    pop di
    pop bx
    test dh,64
    jz ___idcomplete
    and dh,15
    cmp dh,0
    jne ___notjustaddr
    and dl,15
    jmp ___idcomplete
___notjustaddr:
    mov ax,word [addrspec]
    cmp ax,-128
    jl ___wordaddr
    cmp ax,127
    jg ___wordaddr
    cmp word [containslabel],0
    jne ___wordaddr
    add dl,040h
    jmp ___idcomplete
___wordaddr:
    add dl,080h
___idcomplete:
    xchg ax,dx
    mov cx,1
___decodeindirect:
    mov dx,word [addrspec]
    pop bx
    pop si
    ret
testptr:
    push si
    mov ax,0
    call strtok
    push ax
    push si
    mov si,bptr
    call strcmp
    cmp al,0
    je ___bptr
    mov si,wptr
    call strcmp
    cmp al,0
    je ___wptr
    mov si,dptr
    call strcmp
    cmp al,0
    je ___dptr
    mov si,qptr
    call strcmp
    cmp al,0
    je ___qptr
    pop si
    pop ax
    call unstrtok
    mov ax,0
    mov cx,1
    jmp ___testptr
___delptr:
    call strtok
    push ax
    push si
    mov si,aptr
    call strcmp
    cmp al,0
    jne ___badptr
    pop si
    pop ax
    mov di,si
    call unstrtok
    ret
___badptr:
    pop si
    pop ax
    mov cx,0
    mov di,errmsg_ptrexp
    ret
___bptr:
    pop si
    pop ax
    call unstrtok
    mov di,si
    call ___delptr
    mov ax,1
    jmp ___testptr
___wptr:
    pop si
    pop ax
    call unstrtok
    mov di,si
    call ___delptr
    mov ax,2
    jmp ___testptr
___dptr:
    pop si
    pop ax
    call unstrtok
    mov di,si
    call ___delptr
    mov ax,4
    jmp ___testptr
___qptr:
    pop si
    pop ax
    call unstrtok
    mov di,si
    call ___delptr
    mov ax,8
    jmp ___testptr
___testptr:
    pop si
    ret
testfar:
    push si
    call strtok
    push ax
    push si
    mov si,farstring
    call strcmp
    pop si
    cmp al,0
    je ___farpresent
    pop ax
    call unstrtok
    mov ax,0
    jmp ___testfar
___farpresent:
    pop ax
    mov di,si
    inc di
    mov ax,128
___testfar:
    pop si
    ret
indirectcode:
    push bx
    push si
    push di
    xchg si,di
    mov di,tempbuffer
    call strcpy
    xor ax,ax
    call testfar
    push ax
    call testptr
    cmp cx,0
    jne ___notestptrerr
    pop ax
    jmp ___indirectcode
___notestptrerr:
    push ax
    call decodeindirect
    cmp cx,0
    jne ___nodcerr
    pop ax
    pop ax
    jmp ___indirectcode
___nodcerr:
    pop cx
    xor ah,ah
    or ah,cl
    pop cx
    or ah,cl
    mov cx,1
___indirectcode:
    pop di
    pop si
    pop bx
    ret
getexptype:
    push cx
    push si
    push di
    mov si,regnames
    mov bx,___regnames
    mov dx,0
    mov cx,5
    call chopsearch
    cmp al,0
    jne ___notreg
    mov al,[si+4]
    mov ah,[si+3]
    jmp ___getexptype
___notreg:
    call aton
    cmp cx,0
    je ___notnumber
    mov dx,ax
    and ax,0ff00h
    cmp ax,0
    jne ___numisword
    mov ah,0
    jmp ___getexptype
___numisword:
    mov ah,16
    jmp ___getexptype
___notnumber:
    push di
    mov ax,0
    call strtok
    push ax
    call aton
    cmp cx,0
    jne ___posssegaddr1
    pop ax
    call unstrtok
    jmp ___notsegaddr
___posssegaddr1:
    mov bx,ax
    pop ax
    mov di,si
    call strtok
    cmp byte [di],':'
    je ___posssegaddr2
    xor bx,bx
    jmp ___notsegaddr
___posssegaddr2:
    mov di,si
    call strtok
    push ax
    call aton
    cmp cx,0
    mov dx,ax
    pop ax
    je ___notsegaddr
    call unstrtok
    mov cx,1
    mov ah,80
    pop di
    jmp ___getexptype
___notsegaddr:
    pop di
    xor ah,ah
    call indirectcode
    cmp cx,0
    je ___notindirect
    or ah,96
    jmp ___getexptype
___notindirect:
    mov ah,112
    push ax
    call getsymbol
    mov dx,ax
    pop ax
___getexptype:
    pop di
    pop si
    pop cx
    ret
qstolw:
    push si
    push ax
    push bx
    mov si,tempbuffer
    xchg si,di
    call strcpy
    call qtos
    cmp cx,0
    je ___strtoolong
    call strlen
    cmp ax,2
    jg ___strtoolong
    cmp ax,0
    jne ___nuffspace
    mov byte [di+1],0
___nuffspace:
    mov ax,[di]
    mov byte [di],'0'
    mov byte [di+1],'x'
    inc di
    inc di
    mov bx,16
    call ntos
    dec di
    dec di
    xchg si,di
    call strcpy
    jmp ___qstolw
___strtoolong:
    xchg si,di
    mov di,errmsg_strtoolong
    xor cx,cx
___qstolw:
    pop ax
    pop bx
    pop si
    ret
convquotedwords:
    push ax
    mov di,exp1store
    call qtostest
    cmp cx,0
    je ___litexp2
    call qstolw
    cmp cx,0
    je ___convquotedwords
___litexp2:
    mov di,exp2store
    call qtostest
    cmp cx,0
    mov cx,1
    je ___convquotedwords
    call qstolw
___convquotedwords:
    pop ax
    ret
splitexpression:
    push ax
    push si
    push di
    push bx
    mov di,expsetstore
    call strlen
    mov bx,ax
    mov al,','
    call outofquote
    xchg si,di
    cmp ax,bx
    jge ___exp1only
    add si,ax
    inc si
    mov di,exp2store
    call strcpy
    dec si
    sub si,ax
___exp1only:
    mov bx,ax
    push word [si+bx]
    mov byte [si+bx],0
    mov di,exp1store
    call strcpy
    pop word [si+bx]
    xchg si,di
___splitexpression:
    pop bx
    pop di
    pop si
    pop ax
    ret
fetchparameters:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    call removecomment
    mov al,0
    call strtok
    cmp al,':'
    jne ___nolabel
    push ax
    push si
    mov si,segregs
    mov bx,___segregs
    mov cx,3
    mov dx,0
    call chopsearch
    cmp al,0
    jne ___labelfound
    pop si
    pop ax
    call unstrtok
    jmp ___mnefield
___nolabel:
    call unstrtok
    jmp ___mnefield
___labelfound:
    pop si
    pop ax
    push si
    mov si,labelstore
    xchg si,di
    call strcpy
    xchg si,di
    pop si
    mov di,si
    call strtok
    mov di,si
    call strtok
    call unstrtok
    call removetrails
___mnefield:
    mov ax,0
    call strtok
    cmp al,':'
    jne ___notsegmne
    push di
    mov di,si
    call strtok
    pop di
___notsegmne:
    push si
    mov si,mnemonicstore
    xchg si,di
    call strcpy
    xchg si,di
    pop si
    mov di,si
    call strtok
    call unstrtok
    mov si,expsetstore
    xchg si,di
    call strcpy
    xchg si,di
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
encodemnemonic:
    push di
    push si
    push dx
    push bx
    mov si,mnemonics
    mov bx,___mnemonics
    mov di,mnemonicstore
    call removetrails
    mov cx,8
    mov dx,0
    call chopsearch
    cmp al,0
    je ___mnefound
    xor cx,cx
    jmp ___encodemnemonic
___mnefound:
    mov cx,1
    mov al,byte [si+7]
___encodemnemonic:
    pop bx
    pop dx
    pop si
    pop di
    ret
indirectorder:
    push bx
    push dx
    xor cx,cx
    mov di,exp1store
    call getexptype
    and ah,240
    cmp ah,64
    je ___lthisisseg
    cmp ah,96
    je ___lthisisind
    cmp ah,32
    je ___lthisis8bit
    cmp ah,48
    jne ___nextexp
    mov ch,16
    jmp ___nextexp
___lthisisseg:
    mov ch,16
    jmp ___nextexp
___lthisisind:
    mov cl,1
    jmp ___nextexp
___lthisis8bit:
    mov ch,8
___nextexp:
    mov di,exp2store
    call getexptype
    and ah,240
    cmp ah,64
    je ___rthisisseg
    cmp ah,96
    je ___rthisisind
    cmp ah,32
    je ___rthisis8bit
    cmp ah,48
    jne ___expdone
    mov ch,16
    jmp ___expdone
___rthisisseg:
    mov ch,16
    jmp ___expdone
___rthisisind:
    mov cl,2
    jmp ___expdone
___rthisis8bit:
    mov ch,8
___expdone:
    cmp ch,8
    je ___sizeok
    cmp ch,16
    jne ___errexit
___sizeok:
    cmp cl,1
    je ___indok
    cmp cl,2
    je ___indok
___errexit:
    xor cx,cx
    mov di,errmsg_invparams
    jmp ___indirectorder
___indok:
    xor ax,ax
    mov al,cl
    mov cl,4
    shr ch,cl
    shr al,1
    mov ah,ch
___indirectorder:
    pop dx
    pop bx
    ret
checkexpression:
    push ax
    push bx
    push dx
    push si
    push di
    mov ax,0
___nextechk:
    call strtok
    push ax
    push si
    mov si,regnames
    mov bx,___regnames
    mov cx,5
    mov dx,0
    call chopsearch
    cmp cx,0
    je ___nextstrtok
    cmp al,0
    jne ___nextstrtok
    mov al,[si+3]
    cmp al,48
    jne ___defecerr
    mov al,[si+4]
    cmp al,3
    je ___nextstrtok
    cmp al,5
    jge ___nextstrtok
___defecerr:
    pop si
    pop ax
    call unstrtok
    pop di
    mov di,errmsg_illidir
    xor cx,cx
    jmp ___checkexpression
___nextstrtok:
    pop si
___nextstrtok2:
    pop ax
    mov di,si
    cmp ax,0
    jne ___nextechk
___endechk:
    pop di
    mov cx,1
___checkexpression:
    pop si
    pop dx
    pop bx
    pop ax
    ret
swapexpressions:
    push si
    push di
    push bx
    push ax
    mov si,exp1store
    mov di,exp2store
    xor bx,bx
___nextpibyte:
    mov al,[si+bx]
    mov ah,[di+bx]
    mov [si+bx],ah
    mov [di+bx],al
    inc bx
    cmp bx,maxexplen
    jne ___nextpibyte
    pop ax
    pop bx
    pop si
    pop di
    ret
getregtype:
    push dx
    push di
    call getexptype
    mov cl,4
    shr ah,cl
    cmp ah,2
    jne ___testreg16
    xor ah,ah
    xor bx,bx
    mov cx,1
    jmp ___getregtype
___testreg16:
    cmp ah,3
    jne ___testregseg
    mov ah,32
    xor bx,bx
    mov cx,1
    jmp ___getregtype
___testregseg:
    cmp ah,4
    jne ___testlit8
    mov ah,160
    xor bx,bx
    mov cx,1
    jmp ___getregtype
___testlit8:
    cmp ah,0
    jne ___testlit16
    mov ah,64
    mov bx,dx
    mov cx,1
    jmp ___getregtype
___testlit16:
    cmp ah,1
    jne ___testlabel
    mov ah,96
    mov bx,dx
    mov cx,1
    jmp ___getregtype
___testlabel:
    cmp ah,7
    jne ___badexp1
    mov ah,96
    mov bx,dx
    mov cx,1
    jmp ___getregtype
___badexp1:
    mov di,errmsg_invparams
    xor cx,cx
    jmp ___getregtype
___getregtype:
    pop di
    pop dx
    ret
encodetwoparam:
    mov ax,0
    call indirectorder
    cmp cx,0
    jne ___swapexp
    mov ax,0
    jmp ___noswap
___swapexp:
    cmp al,1
    jne ___noswap
    call swapexpressions
___noswap:
    push ax
    mov di,exp1store
    call getexptype
    push ax
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ah,1
    jle ___badlit2p
    cmp ah,7
    je ___badlit2p
    cmp ah,5
    je ___segadrnotalw
    cmp ah,6
    je ___isexp
    cmp ah,4
    je ___isegr
    cmp ah,3
    je ___iswordr
    pop ax
    pop cx
    or al,0c0h
    and ah,15
    jmp ___codepar2
___segadrnotalw:
    pop ax
    pop cx
    xor ax,ax
    xor cx,cx
    mov di,errmsg_invparams
    jmp ___encodetwoparam
___iswordr:
    pop ax
    pop cx
    or al,0c0h
    and ah,15
    or ah,32
    jmp ___codepar2
___isegr:
    pop ax
    pop cx
    or al,0c0h
    and ah,15
    or ah,176
    jmp ___codepar2
___badlit2p:
    pop ax
    pop cx
    xor cx,cx
    mov di,errmsg_invparams
    jmp ___encodetwoparam
___isexp:
    pop ax
    call checkexpression
    cmp cx,0
    jne ___expokay
    pop cx
    jmp ___encodetwoparam
___expokay:
    pop cx
    mov ch,cl
    mov cl,4
    shl ch,cl
    and ah,15
    mov cl,ah
    or ah,ch
    mov ch,cl
    cmp ch,2
    jg ___ptrtoobig
    and ch,1
    xor ch,1
    mov cl,5
    shl ch,cl
    or ah,ch
    jmp ___codepar2
___ptrtoobig:
    xor ax,ax
    xor cx,cx
    mov di,errmsg_ptrtoolarge
    jmp ___encodetwoparam
___codepar2:
    push ax
    mov di,exp2store
    push dx
    call getregtype
    pop dx
    cmp cx,0
    jne ___notbadpar2
    jmp ___badpar2
___notbadpar2:
    test ah,128
    jz ___notpar2seg
    jmp ___par2seg
___notpar2seg:
    test ah,64
    jz ___notpar2lit
    jmp ___par2lit
___notpar2lit:
    test ah,32
    jnz ___par2reg16
    mov cx,ax
    mov ch,al
    and ch,7
    mov cl,3
    shl ch,cl
    pop ax
    test ah,128
    jnz ___badregmix
    and al,199
    or al,ch
    push ax
    call indirectorder
    cmp cx,0
    je ___notexpression
    mov cx,ax
    pop ax
    mov cl,5
    shl ch,cl
    and ah,223
    or ah,ch
    mov cx,1
    jmp ___encodetwoparam
___notexpression:
    pop ax
    test ah,32
    jnz ___badreguse
    mov cx,1
    jmp ___encodetwoparam
___badreguse:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_badregmix
    jmp ___encodetwoparam
___par2reg16:
    push ax
    mov cx,ax
    mov ch,al
    and ch,7
    mov cl,3
    shl ch,cl
    pop ax
    mov cl,ah
    pop ax
    test ah,32
    jz ___badregmix
    and al,199
    or al,ch
    or ah,cl
    test ah,128
    jz ___notsegreg
    mov ch,al
    and ch,7
    mov cl,3
    shl ch,cl
    mov cl,al
    and al,0c0h
    or al,ch
    mov ch,cl
    and ch,56
    mov cl,3
    shr ch,cl
    or al,ch
___notsegreg:
    mov cx,1
    jmp ___encodetwoparam
___badregmix:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_badregmix
    jmp ___encodetwoparam
___par2seg:
    push ax
    mov cx,ax
    mov ch,al
    and ch,7
    mov cl,3
    shl ch,cl
    pop ax
    mov cl,ah
    pop ax
    test ah,128
    jnz ___twosegerr
    test ah,32
    jz ___badregmix
    and al,199
    or al,ch
    or ah,cl
    mov cx,1
    jmp ___encodetwoparam
___twosegerr:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
    jmp ___encodetwoparam
___par2lit:
    test ah,32
    jnz ___16bitlit
    xor bh,bh
    pop ax
    test ah,128
    jnz ___litsegerr
    and al,199
    or ah,64
    mov cx,1
    jmp ___encodetwoparam
___litsegerr:
    xor ax,ax
    xor cx,cx
    mov di,errmsg_inviform
    jmp ___encodetwoparam
___16bitlit:
    pop ax
    test ah,32
    jz ___par2littoolrg
    and al,199
    or ah,64
    mov cx,1
    jmp ___encodetwoparam
___par2littoolrg:
    cmp bh,0ffh
    jne ___litistoolrg
    xor bh,bh
    and al,199
    and ah,223
    or ah,64
    mov cx,1
    jmp ___encodetwoparam
___litistoolrg:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_littoolarge
    jmp ___encodetwoparam
___badpar2:
    pop ax
    xor cx,cx
    xor ax,ax
    mov di,errmsg_invparams
    jmp encodetwoparam
___encodetwoparam:
    ret
countparams:
    xor ax,ax
    cmp byte [exp2store],0
    je ___testp1
    inc ax
___testp1:
    cmp byte [exp1store],0
    je ___countparams
    inc ax
___countparams:
    ret
writeexpdata:
    push di
    xchg al,ah
    mov [codestore],ax
    and ah,0c7h
    cmp ah,06h
    je ___writeword
    and ah,0c0h
    xchg ch,cl
    mov cl,6
    shr ah,cl
    xchg ch,cl
    cmp ah,1
    je ___writebyte
    cmp ah,2
    je ___writeword
    mov ax,2
    jmp ___writelit
___writebyte:
    mov [codestore+2],dl
    mov ax,3
    jmp ___writelit
___writeword:
    mov [codestore+2],dx
    mov ax,4
    jmp ___writelit
___writelit:
    cmp cl,1
    je ___writelitbyte
    cmp cl,2
    je ___writelitword
    mov cx,1
    jmp ___writeexpdata
___writelitbyte:
    mov di,ax
    mov [di+codestore],bl
    inc ax
    mov cx,1
    jmp ___writeexpdata
___writelitword:
    mov di,ax
    mov [di+codestore],bx
    add ax,2
    mov cx,1
___writeexpdata:
    pop di
    ret
codealu0:
    push bx
    push dx
    push si
    call encodemnemonic
    mov cx,ax
    xchg ch,cl
    push cx
    call encodetwoparam
    cmp cx,0
    jne ___testseg
    pop cx
    mov cx,0
    jmp ___codealu0
___testseg:
    pop cx
    test ah,128
    jnz ___alu0segerr
    test ah,64
    jnz ___alu0literal
    push ax
    and ah,16
    mov cl,3
    shl ch,cl
    shr ah,cl
    or ch,ah
    pop ax
    and ah,32
    mov cl,5
    shr ah,cl
    or ah,ch
    mov cl,0
    call writeexpdata
    jmp ___codealu0
___alu0segerr:
    mov di,errmsg_inviform
    xor cx,cx
    mov ax,0
    jmp ___codealu0
___alu0literal:
    cmp al,0c0h
    jne ___notalu0acc
    mov cl,5
    shr ah,cl
    and ah,1
    mov cl,3
    shl ch,cl
    add ch,4
    or ch,ah
    mov [codestore],ch
    cmp ah,0
    jne ___aluaxlitwrite
    mov [codestore+1],bl
    mov ax,2
    mov cx,1
    jmp ___codealu0
___aluaxlitwrite:
    mov [codestore+1],bx
    mov ax,3
    mov cx,1
    jmp ___codealu0
___notalu0acc:
    and ch,7
    mov cl,3
    shl ch,cl
    or al,ch
    mov ch,ah
    and ch,1
    xor ch,1
    xchg ch,ah
    and ch,32
    mov cl,5
    shr ch,cl
    push ax
    and al,0c0h
    cmp al,0c0h
    pop ax
    jne ___addopval
    mov ah,ch
___addopval:
    add ah,80h
    mov cl,1
    test ah,1
    jz ___writealu0byte
    cmp bx,-128
    jl ___writealu0word
    cmp bx,127
    jg ___writealu0word
    dec cl
    mov ah,083h
___writealu0word:
    inc cl
___writealu0byte:
    call writeexpdata
    mov cx,1
___codealu0:
    pop si
    pop dx
    pop bx
    ret
codealu1:
    mov di,exp1store
    call getexptype
    push ax
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ah,6
    je ___exp1ind
    cmp ah,2
    je ___exp18
    cmp ah,3
    je ___exp116
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
    jmp ___codealu1
___exp18:
    pop ax
    or al,0c0h
    mov ah,0d0h
    jmp ___alu1par2
___exp116:  pop ax
    or al,0c0h
    mov ah,0d1h
    jmp ___alu1par2
___exp1ind:
    pop ax
    mov di,errmsg_inviform
    call checkexpression
    cmp cx,0
    jne ___codealu1ind
    xor ax,ax
    jmp ___codealu1
___alu1bigptr:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_ptrtoolarge
    jmp ___codealu1
___codealu1ind:
    mov cx,ax
    and ch,15
    cmp ch,2
    jg ___alu1bigptr
    and ch,1
    xor ch,1
    add ah,0d0h
    jmp ___alu1par2
___alu1par2err:
    pop ax
    xor cx,cx
    xor ax,ax
    jmp ___codealu1
___alu1par2:
    mov di,exp2store
    push ax
    call getregtype
    cmp cx,0
    je ___alu1par2err
    test ah,64
    jnz ___alu1par2lit
    test ah,32
    jz ___alu1par28
___badalu1par2:
    pop ax
    xor cx,cx
    xor ax,ax
    mov di,errmsg_badregmix
    jmp ___codealu1
___badalu1mne:
    pop ax
    xor cx,cx
    xor ax,ax
    mov di,errmsg_unknownmne
    jmp ___codealu1
___alu1par28:
    cmp al,1
    jne ___badalu1par2
    call encodemnemonic
    cmp cx,0
    je ___badalu1mne
    and al,7
    mov cl,3
    shl al,cl
    mov cl,al
    pop ax
    and al,199
    or al,cl
    add ah,2
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codealu1
___alu1par2lit:
    cmp bx,1
    jne ___badalu1par2
    call encodemnemonic
    cmp cx,0
    je ___badalu1mne
    and al,7
    mov cl,3
    shl al,cl
    mov cl,al
    pop ax
    and al,199
    or al,cl
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codealu1
___codealu1:
    ret
codeleadses:
    push bx
    push dx
    push si
    call encodetwoparam
    cmp cx,0
    jne ___testleadsesseg
    mov cx,0
    jmp ___codeleadses
___testleadsesseg:
    test ah,128
    jnz ___leadsessegerr
    test ah,64
    jnz ___leadsesformerr
    push ax
    and al,0c0h
    cmp al,0c0h
    pop ax
    je ___leadsesformerr
    test ah,32
    jz ___leadsesformerr
    test ah,16
    jnz ___leadsesformerr
    test ah,15
    jnz ___testptrword
    jmp ___leadsesformok
___testptrword:
    test ah,2
    jnz ___leadsesformok
___leadsesformerr:
    xor cx,cx
    mov ax,0
    mov di,errmsg_inviform
    jmp ___codeleadses
___leadsessegerr:
    mov di,errmsg_inviform
    xor cx,cx
    mov ax,0
    jmp ___codeleadses
___leadsesformok:
    xor ah,ah
    xchg cx,ax
    call encodemnemonic
    xchg ax,cx
    and cl,15
    add cl,0b8h
    cmp cl,0bah
    jne ___leaopcodeset
    mov cl,08dh
___leaopcodeset:
    mov ah,cl
    mov [codestore],ah
    mov [codestore+1],al
    and al,0c0h
    mov cl,6
    shr al,cl
    cmp al,1
    je ___writeleabyte
    cmp al,2
    je ___writeleaword
    mov ax,2
    mov cx,1
    jmp ___codeleadses
___writeleaword:
    mov [codestore+2],dx
    mov ax,4
    mov cx,1
    jmp ___codeleadses
___writeleabyte:
    mov [codestore+2],dl
    mov ax,3
    mov cx,1
    jmp ___codeleadses
___codeleadses:
    pop si
    pop dx
    pop bx
    ret
codexchg:
    push bx
    push dx
    push si
    call encodetwoparam
    cmp cx,0
    jne ___testxchgseg
    jmp ___codexchg
___testxchgseg:
    test ah,128
    jnz ___xchgsegerr
    push ax
    and al,0c0h
    cmp al,0c0h
    pop ax
    jne ___notxchgax
    test ah,32
    jz ___notxchgax
    push ax
    and al,7
    cmp al,0
    pop ax
    je ___regisax
    push ax
    and al,56
    mov cl,3
    shr al,cl
    and al,7
    cmp al,0
    pop ax
    jne ___notxchgax
    mov ch,al
    mov cl,3
    shr al,cl
    and al,7
    and ch,7
    shl ch,cl
    or al,ch
    or al,0c0h
___regisax:
    mov ah,90h
    mov cl,3
    shr al,cl
    and al,7
    add ah,al
    cmp ah,90h
    jne ___writexchgcode
    mov cx,0
    mov ax,0
    mov di,errmsg_inviform
    jmp ___codexchg
___writexchgcode:
    mov [codestore],ah
    mov ax,1
    mov cx,1
    jmp ___codexchg
___notxchgax:
    test ah,32
    jz ___8bitxchg
    mov ah,087h
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codexchg
___8bitxchg:
    mov ah,086h
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codexchg
___xchgsegerr:
    mov di,errmsg_inviform
    xor cx,cx
    mov ax,0
___codexchg:
    pop si
    pop dx
    pop bx
    ret
codetesti:
    push bx
    push dx
    push si
    call encodetwoparam
    cmp cx,0
    jne ___testtestiseg
    mov ax,0
    mov cx,0
    jmp ___codetesti
___testtestiseg:
    test ah,128
    jnz ___testisegerr
    test ah,64
    jnz ___testiliteral
    and ah,32
    mov cl,5
    shr ah,cl
    add ah,084h
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codetesti
___testisegerr:
    mov ax,0
    mov cx,0
    mov di,errmsg_inviform
    jmp ___codetesti
___testiliteral:
    push ax
    and al,7
    cmp al,0
    pop ax
    jne ___normtestlit
    test ah,32
    jz ___testax8bit
    mov byte [codestore],0a9h
    mov [codestore+1],bx
    mov ax,3
    mov cx,1
    jmp ___codetesti
___testax8bit:
    mov byte [codestore],0a8h
    mov [codestore+1],bl
    mov ax,2
    mov cx,1
    jmp ___codetesti
___normtestlit:
    and al,0c7h
    and ah,32
    mov cl,5
    shr ah,cl
    add ah,0f6h
    mov cl,ah
    and cl,1
    inc cl
    call writeexpdata
    mov cx,1
___codetesti:
    pop si
    pop dx
    pop bx
    ret
codemov:
    call encodetwoparam
    cmp cx,0
    jne ___movnoerr
    jmp ___codemov
___movnoerr:
    test ah,64
    jnz ___movlit
    test ah,128
    jnz ___movseg
    mov ch,ah
    and ch,32
    mov cl,5
    shr ch,cl
    and ah,16
    mov cl,3
    shr ah,cl
    or ah,ch
    add ah,88h
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codemov
___movseg:
    and ah,16
    mov cl,3
    shr ah,cl
    add ah,08ch
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codemov
___movlit:
    push ax
    and al,0c0h
    cmp al,0c0h
    pop ax
    jne ___movexpcode
    and al,7
    and ah,32
    mov cl,2
    shr ah,cl
    add al,ah
    add al,0b0h
    mov [codestore],al
    mov [codestore+1],bx
    mov cl,3
    shr ah,cl
    add ah,2
    xchg ah,al
    xor ah,ah
    mov cx,1
    jmp ___codemov
___movexpcode:
    test ah,32
    jz ___writemovlit
    push ax
    and ah,1
    cmp ah,1
    pop ax
    jne ___writemovlit
    mov cx,0
    mov ax,0
    mov di,errmsg_littoolarge
    jmp ___codemov
___writemovlit:
    and ah,1
    xor ah,1
    mov cl,ah
    inc cl
    add ah,0c6h
    call writeexpdata
    mov cx,1
    jmp ___codemov
___codemov:
    cmp byte [codestore+1],6
    jne ___notmovaxal
    cmp byte [codestore],88h
    jl ___notmovaxal
    cmp byte [codestore],8bh
    jg ___notmovaxal
    add byte [codestore],18h
    xor byte [codestore],2
    mov ax,word [codestore+2]
    mov word [codestore+1],ax
    mov ax,3
___notmovaxal:
    ret
codeport:
    mov di,exp2store
    call getregtype
    cmp cx,0
    jne ___noreg2err
    jmp ___codeport
___noreg2err:
    test ah,128
    jz ___notportseg
    xor cx,cx
    mov di,errmsg_inviform
    jmp codeport
___notportseg:
    test ah,64
    jz ___portreg
    jmp ___portlit
___portreg:
    cmp ax,8194
    je ___testinreg
    cmp al,0
    je ___portregok
    jmp ___badportreg
___portregok:
    push ax
    call encodemnemonic
    cmp al,077h
    pop ax
    je ___outportregok
    jmp ___badportreg
___outportregok:
    push ax
    mov di,exp1store
    call getregtype
    cmp cx,0
    jne ___reg1noerr
    jmp ___codeport
___reg1noerr:
    cmp ax,8194
    pop ax
    je ___inportaxok
    jmp ___badportreg
___inportaxok:
    and ah,32
    mov cl,5
    shr ah,cl
    add ah,0eeh
    mov byte [codestore],ah
    mov ax,1
    mov cx,1
    jmp ___codeport
___testinreg:
    call encodemnemonic
    cmp al,076h
    je ___inregmneok
    jmp ___badportreg
___inregmneok:
    mov di,exp1store
    call getregtype
    cmp al,0
    jne ___badportreg
    test ah,128
    jnz ___badportreg
    test ah,64
    jnz ___badplitpos
    and ah,32
    mov cl,5
    shr ah,cl
    add ah,0ech
    mov byte [codestore],ah
    mov ax,1
    mov cx,1
    jmp ___codeport
___portlit:
    test ah,32
    jz ___plitisbyte
    mov ax,0
    mov cx,0
    mov di,errmsg_littoolarge
    jmp ___codeport
___plitisbyte:
    mov [codestore+1],bl
    mov di,exp1store
    call getregtype
    cmp al,0
    jne ___badportreg
    test ah,128
    jnz ___badportreg
    test ah,64
    jnz ___badplitpos
    and ah,32
    mov cl,5
    shr ah,cl
    push ax
    call encodemnemonic
    pop cx
    and al,1
    shl al,1
    or al,ch
    add al,0e4h
    mov [codestore],al
    mov ax,2
    mov cx,1
    jmp ___codeport
___badplitpos:
    mov di,errmsg_invparams
    xor cx,cx
    xor ax,ax
    jmp ___codeport
___badportreg:
    mov di,errmsg_inviform
    xor cx,cx
    xor ax,ax
    jmp ___codeport
___codeport:
    ret
codetwoparam:
    call encodemnemonic
    mov cx,ax
    mov ax,cx
    and al,0f8h
    cmp al,0
    jne ___notalu0
    call codealu0
    jmp ___codetwoparam
___notalu0:
    mov ax,cx
    and al,0f8h
    cmp al,10h
    jne ___notalu1
    call codealu1
    jmp ___codetwoparam
___notalu1:
    mov ax,cx
    cmp al,62h
    je ___isleadses
    cmp al,6ch
    je ___isleadses
    cmp al,6dh
    jne ___notleadses
___isleadses:
    call codeleadses
    jmp ___codetwoparam
___notleadses:
    mov ax,cx
    cmp al,60h
    jne ___notxchg
    call codexchg
    jmp ___codetwoparam
___notxchg:
    mov ax,cx
    cmp al,30h
    jne ___nottest
    call codetesti
    jmp ___codetwoparam
___nottest:
    mov ax,cx
    cmp al,61h
    jne ___notmov
    call codemov
    jmp ___codetwoparam
___notmov:
    mov ax,cx
    and al,0feh
    cmp al,76h
    jne ___notport
    call codeport
    jmp ___codetwoparam
___notport:
    mov di,errmsg_inviform
    xor cx,cx
    xor ax,ax
___codetwoparam:
    ret
codepushpop:
    mov di,exp1store
    call getexptype
    push ax
    mov cl,4
    shr ah,cl
    cmp ah,6
    je ___testpope
    cmp ah,4
    je ___stackseg
    cmp ah,3
    je ___stackreg
    pop ax
    mov di,errmsg_inviform
    mov ax,0
    mov cx,0
    jmp ___codepushpop
___stackseg:
    call encodemnemonic
    and al,1
    pop cx
    xchg ch,cl
    and ch,3
    mov cl,3
    shl ch,cl
    or ch,al
    add ch,6
    mov [codestore],ch
    mov ax,1
    mov cx,1
    jmp ___codepushpop
___stackreg:
    call encodemnemonic
    and al,1
    pop cx
    xchg ch,cl
    mov cl,3
    shl al,cl
    and ch,7
    add ch,al
    add ch,050h
    mov [codestore],ch
    mov ax,1
    mov cx,1
    jmp ___codepushpop
___testpope:
    call encodemnemonic
    cmp al,03fh
    je ___popseg
    pop ax
    mov ax,0
    mov di,exp1store
    call checkexpression
    cmp cx, 0
    je ___codepushpop
    mov ah,0ffh
    and al,199
    or al,030h
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codepushpop
___popseg:
    pop ax
    mov ah,08fh
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codepushpop
___codepushpop:
    ret
codeincdec:
    mov di,exp1store
    call getexptype
    push ax
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ah,6
    je ___testide
    cmp ah,4
    je ___idseg
    cmp ah,3
    je ___idreg16
    cmp ah,2
    je ___idreg8
    pop ax
    mov di,errmsg_invparams
    mov ax,0
    mov cx,0
    jmp ___codeincdec
___idseg:
    pop ax
    mov di,errmsg_inviform
    mov ax,0
    mov cx,0
    jmp ___codeincdec
___idreg8:
    call encodemnemonic
    and al,1
    mov cl,3
    shl al,cl
    pop cx
    and ch,199
    or cl,0c0h
    or cl,al
    mov al,0feh
    mov ah,cl
    mov [codestore],ax
    mov ax,2
    mov cx,1
    jmp ___codeincdec
___idreg16:
    call encodemnemonic
    and al,1
    pop cx
    xchg ch,cl
    mov cl,3
    shl al,cl
    and ch,7
    add ch,al
    add ch,040h
    mov [codestore],ch
    mov ax,1
    mov cx,1
    jmp ___codeincdec
___testide:
    call encodemnemonic
    cmp al,038h
    je ___decseg
    pop ax
    mov ax,0
    mov di,exp1store
    call checkexpression
    cmp cx, 0
    je ___codeincdec
    mov ah,0ffh
    and al,199
    or al,8
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codeincdec
___decseg:
    pop ax
    mov ah,0ffh
    and al,199
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codeincdec
___codeincdec:
    ret
codealu2:
    mov di,exp1store
    call getexptype
    push ax
    call encodemnemonic
    and al,7
    mov cl,3
    shl al,cl
    pop cx
    or cl,al
    xchg ax,cx
    push ax
    mov cl,4
    shr ah,cl
    cmp ah,6
    je ___alu2exp
    cmp ah,2
    je ___alu2reg8
    cmp ah,3
    je ___alu2reg16
___badalu2:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
    jmp ___codealu2
___alu2exp:
    pop ax
    mov ax,0
    mov di,exp1store
    call checkexpression
    cmp cx, 0
    je ___codealu2
    and ah,15
    cmp ah,2
    jg ___badalu2
    and ah,1
    xor ah,1
    add ah,0f6h
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codealu2
___alu2reg8:
    pop ax
    mov ah,0f6h
    or al,0c0h
    xchg ah,al
    mov [codestore],ax
    mov ax,2
    mov cx,1
    jmp ___codealu2
___alu2reg16:
    pop ax
    mov ah,0f7h
    or al,0c0h
    xchg ah,al
    mov [codestore],ax
    mov ax,2
    mov cx,1
    jmp ___codealu2
___codealu2:
    ret
codeint:
    mov di,exp1store
    call getexptype
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ax,0
    jnz ___badintcall
    cmp dl,3
    je ___writeint3
    mov al,dl
    mov ah,0cdh
    xchg ah,al
    mov [codestore],ax
    mov ax,2
    mov cx,1
    jmp ___codeint
___writeint3:
    mov byte [codestore],0cch
    mov ax,1
    mov cx,1
    jmp ___codeint
___badintcall:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
    jmp ___codeint
___codeint:
    ret
codeascadj:
    mov di,exp1store
    call getexptype
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ax,0
    jnz ___badascadj
    mov al,dl
    mov ah,0d4h
    push ax
    call encodemnemonic
    and al,1
    xchg cx,ax
    pop ax
    or ah,cl
    xchg ah,al
    mov [codestore],ax
    mov ax,2
    mov cx,1
    jmp ___codeint
___badascadj:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
    jmp ___codeint
___codeascadj:
    ret
coderet1:
    mov di,exp1store
    call getexptype
    mov cl,4
    shr ah,cl
    and ah,6
    cmp ax,0
    jnz ___badret1
    mov al,dl
    mov ah,0c2h
    push ax
    call encodemnemonic
    cmp al,06bh
    jne ___mustberetf
    pop ax
    mov ah,0c2h
    jmp ___writeret1code
___mustberetf:
    pop ax
    mov ah,0cah
___writeret1code:
    xchg ah,al
    mov [codestore],al
    mov [codestore+1],dx
    mov ax,3
    mov cx,1
    jmp ___coderet1
___badret1:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
    jmp ___coderet1
___coderet1:
    ret
codejumpcall:
    mov di,exp1store
    call getexptype
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ah,5
    jne ___testindjump
    mov [codestore+1],dx
    mov [codestore+3],bx
    call encodemnemonic
    cmp al,03ah
    jne ___jmpsegadd
    mov byte [codestore],09ah
    mov ax,5
    mov cx,1
    jmp ___codejumpcall
___jmpsegadd:
    mov byte [codestore],0eah
    mov ax,5
    mov cx,1
    jmp ___codejumpcall
___testindjump:
    cmp ah,6
    jne ___testlabjump
    mov di,exp1store
    call checkexpression
    cmp cx,0
    jne ___cjcok
    jmp ___codejumpcall
___cjcok:
    call getexptype
    and al,199
    mov ch,ah
    and ch,128
    mov cl,4
    shr ch,cl
    or al,ch
    push ax
    call encodemnemonic
    mov cl,al
    and cl,2
    xor cl,2
    shr cl,1
    mov ch,1
    shl ch,cl
    mov cl,4
    shl ch,cl
    pop ax
    or al,ch
    and ah,15
    cmp ah,2
    jng ___goodjumpcall
    jmp ___badjumpcall
___goodjumpcall:
    and ah,1
    xor ah,1
    add ah,0feh
    mov cl,0
    call writeexpdata
    mov cx,1
    jmp ___codejumpcall
___testlabjump:
    cmp ah,7
    jne ___badjumpcall
    push ax
    call getsymbol
    mov dx,ax
    pop ax
    cmp cx,0
    je ___codejumpcall
    sub dx,[curip]
    sub dx,3
    push cx
    call encodemnemonic
    pop cx
    and al,2
    shr al,1
    xor al,1
    add al,0e8h
    mov [codestore],al
    test al,1
    jz ___wordjump
    cmp cx,1
    jne ___wordjump
    cmp dx,-1
    jg ___wordjump
    cmp dx,-129
    jl ___wordjump
    mov ax,2
    mov byte [codestore],0ebh
    inc dx
    mov [codestore+1],dl
    jmp ___skipwordjump
___wordjump:
    mov ax,3
    mov [codestore+1],dx
___skipwordjump:
    mov cx,1
    jmp ___codejumpcall
___badjumpcall:
    xor cx,cx
    xor ax,ax
    mov di,errmsg_inviform
___codejumpcall:
    ret
calc8off:
    sub dx,[curip]
    sub dx,2
    cmp dx,-128
    jl ___bad8off
    cmp dx,127
    jle ___offokay
___bad8off:
    mov di,errmsg_offtoolarge
    xor cx,cx
    jmp ___calc8off
___offokay:
    xor dh,dh
    mov cx,1
___calc8off:
    ret
codebranch:
    mov di,exp1store
    call getexptype
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ah,7
    je ___brokay
    cmp ah,1
    jle ___brokay
    mov cx,0
    mov ax,0
    mov di,errmsg_inviform
    jmp ___codebranch
___brokay:
    cmp word [symbolload],0
    je ___nocalc
    call calc8off
    cmp cx,0
    je ___codebranch
___nocalc:
    call encodemnemonic
    add al,30h
    mov ah,dl
    mov [codestore],ax
    mov ax,2
    mov cx,1
___codebranch:
    ret
codeloop:
    mov di,exp1store
    call getexptype
    mov cl,4
    shr ah,cl
    and ah,7
    cmp ah,7
    je ___loopokay
    cmp ah,1
    jle ___loopokay
    mov cx,0
    mov ax,0
    mov di,errmsg_inviform
    jmp ___codeloop
___loopokay:
    cmp word [symbolload],0
    je ___noloopcalc
    call calc8off
    cmp cx,0
    je ___codebranch
___noloopcalc:
    call encodemnemonic
    mov ah,dl
    mov [codestore],ax
    mov ax,2
    mov cx,1
___codeloop:
    ret
codeoneparam:
    call encodemnemonic
    cmp cx,0
    jne ___mne1pok
    jmp ___codeoneparam
___mne1pok:
    mov cx,ax
    and al,0feh
    cmp al,03eh
    jne ___notpushpop
    call codepushpop
    jmp ___codeoneparam
___notpushpop:
    mov ax,cx
    and al,0feh
    cmp al,038h
    jne ___notincdec
    call codeincdec
    jmp ___codeoneparam
___notincdec:
    mov ax,cx
    cmp al,032h
    jl ___notalu2
    cmp al,037h
    jg ___notalu2
    call codealu2
    jmp ___codeoneparam
___notalu2:
    mov ax,cx
    cmp al,06fh
    jne ___notint
    call codeint
    jmp ___codeoneparam
___notint:
    mov ax,cx
    and al,0feh
    cmp al,01ch
    jne ___notascadj
    call codeascadj
    jmp ___codeoneparam
___notascadj:
    mov ax,cx
    cmp al,06bh
    je ___isret1
    cmp al,06eh
    jne ___notret1
___isret1:
    call coderet1
    jmp ___codeoneparam
___notret1:
    mov ax,cx
    cmp al,03ah
    je ___isjumpcall
    cmp al,03ch
    jne ___notjumpcall
___isjumpcall:
    call codejumpcall
    jmp ___codeoneparam
___notjumpcall:
    mov ax,cx
    and al,0f0h
    cmp al,040h
    jne ___notbranch
    call codebranch
    jmp ___codeoneparam
___notbranch:
    mov ax,cx
    cmp al,0e0h
    jl ___notloopy
    cmp al,0e3h
    jg ___notloopy
    call codeloop
    jmp ___codeoneparam
___notloopy:
    mov di,errmsg_inviform
    xor cx,cx
    xor ax,ax
___codeoneparam:
    ret
codezeroparam:
    call encodemnemonic
    cmp cx,0
    je ___codezeroparam
    mov cx,ax
    mov di,mnetranslate
    dec di
    dec di
___nextoptest:
    inc di
    inc di
    mov ax,[di]
    cmp al,cl
    jne ___nextoptest
    mov [codestore],ah
    and ah,0feh
    cmp ah,0d4h
    jne ___notaamaad
    mov byte [codestore+1],0ah
    mov ax,2
    mov cx,1
    jmp ___codezeroparam
___notaamaad:
    mov ax,1
    mov cx,1
___codezeroparam:
    ret
mstob:
    push si
    push bx
    push dx
    mov dx,ax
    mov si,0
___nextq:
    call qtostest
    cmp cx,0
    jne ___quotedstring
    jmp ___numtest
___quotedstring:
    mov bx,ax
    push ax
    mov al,[di+bx]
    mov byte [di+bx],0
    push ax
    push si
    mov si,tempbuffer
    xchg si,di
    call strcpy
    call qtos
    cmp cx,0
    je ___badquotedstr
    xchg si,di
    pop si
    pop ax
    mov byte [di+bx],al
    pop ax
    add di,bx
    cmp dx,0
    je ___nowordconv
    push ax
    push di
    mov di,tempbuffer
    call strlen
    add si,codestore
    xchg si,di
    mov cx,ax
    call btow
    xchg si,di
    sub si,codestore
    add si,ax
    add si,ax
    pop di
    pop ax
    jmp ___testendq
___nowordconv:
    push ax
    push di
    mov di,tempbuffer
    add si,codestore
    xchg si,di
    call strcpy
    xchg si,di
    sub si,codestore
    call strlen
    add si,ax
    pop di
    pop ax
    jmp ___testendq
___badquotedstr:
    pop si
    pop ax
    pop ax
    xor ax,ax
    xor cx,cx
    mov di,errmsg_strtoolong
___numtest:
    mov ax,0
    push si
    call strtok
    push si
    push ax
    call aton
    cmp cx,0
    je ___numbad
    mov bx,ax
    pop ax
    pop si
    call unstrtok
    mov di,si
    pop si
    cmp dx,0
    jne ___writeqword
    cmp bh,0
    je ___writeqbyte
    mov di,errmsg_littoolarge
    xor cx,cx
    mov ax,0
    jmp ___mstob
___writeqbyte:
    mov byte [si+codestore],bl
    inc si
    jmp ___testendq
___writeqword:
    mov word [si+codestore],bx
    inc si
    inc si
    jmp ___testendq
___numbad:
    pop si
    pop si
    pop ax
    mov di,errmsg_invnumform
    mov ax,0
    xor cx,cx
    jmp ___mstob
___testendq:
    mov cx,1
    mov ax,si
    call removetrails
    cmp byte [di],0
    je ___mstob
    cmp byte [di],","
    jne ___stoberr
    inc di
    jmp ___nextq
___stoberr:
    mov di,errmsg_inviform
    mov ax,0
    xor cx,cx
    jmp ___mstob
___mstob:
    pop dx
    pop bx
    pop si
    ret
encodepseudo:
    mov si,pseudoops
    mov bx,___pseudoops
    mov di,mnemonicstore
    mov cx,9
    mov dx,0
    call chopsearch
    cmp al,0
    je ___testops
    mov di,expsetstore
    mov ax,0
    call strtok
    push si
    push ax
    mov si,equalitytext
    call strcmp
    cmp al,0
    je ___setequality
    cmp word [di],61
    je ___setequality
    pop ax
    pop si
    xor cx,cx
    mov ax,0
    mov di,errmsg_unknownmne
    jmp ___encodepseudo
___setequality:
    pop ax
    pop si
    mov di,si
    call strtok
    call unstrtok
    mov si,mnemonicstore
    xchg si,di
    jmp ___equality
___testops:
    mov al,[si+8]
    cmp al,0
    je ___defbyte
    cmp al,1
    je ___defword
    cmp al,2
    je ___equalityset
    xor cx,cx
    mov ax,0
    jmp ___encodepseudo
___equalityset:
    mov di,exp1store
    mov si,exp2store
___equality:
    call strlwr
    xchg si,di
    call removetrails
    call strlwr
    call aton
    cmp cx,0
    jne ___numchecks
    xchg si,di
    mov ax,0
    mov di,errmsg_invnumform
    jmp ___encodepseudo
___numchecks:
    mov di,mnemonicstore
    call addsymbol
    cmp cx,0
    je ___encodepseudo
    mov cx,1
    mov ax,0
    jmp ___encodepseudo
___defbyte:
    mov di,exp1store
    call qtostest
    cmp cx,0
    jne ___dbstr
    mov di,exp1store
    call aton
    cmp cx,0
    je ___dblabel
___dbstr:
    mov ax,0
    mov di,expsetstore
    call mstob
    jmp ___encodepseudo
___defword:
    mov di,exp1store
    call qtostest
    cmp cx,0
    jne ___dwstr
    mov di,exp1store
    call aton
    cmp cx,0
    je ___dwlabel
___dwstr:
    mov ax,1
    mov di,expsetstore
    call mstob
    jmp ___encodepseudo
___dblabel:
    mov cx,0
    mov di,errmsg_inviform
    mov ax,0
    jmp ___encodepseudo
___dwlabel:
    call getsymbol
    cmp cx,0
    je ___encodepseudo
    mov [codestore],ax
    mov ax,2
___encodepseudo:
    ret
encodeline:
    push ds
    push si
    push dx
    push bx
    mov word [mnemonicstore],0
    mov word [labelstore],0
    mov word [expsetstore],0
    mov word [exp1store],0
    mov word [exp2store],0
    mov word [linestore],0
    mov [symbolload],cx
    call strlen
    cmp ax,80
    jng ___linelenok
    push cs
    pop es
    mov di,errmsg_linetoolong
    xor cx,cx
    xor ax,ax
    jmp ___encodeline
___linelenok:
    mov si,linestore
    mov ax,es
    mov ds,ax
    xchg si,di
    push cs
    pop es
    call strcpy
    push cs
    pop ds
    mov byte [linestore+79],0
    call replacetabs
    mov ax,0
    mov cx,1
    call fetchparameters
    mov di,expsetstore
    call removetrails
    call removeleads
    mov di,labelstore
    call strlen
    cmp ax,0
    je ___emptylabel
    call strlwr
    mov ax,[curip]
    call addsymbol
    cmp cx,0
    jne ___emptylabel
    jmp ___encodeline
___emptylabel:
    mov ax,0
    mov di,mnemonicstore
    call removetrails
    call strlwr
    mov cx,1
    call strlen
    cmp ax,0
    je ___encodeline
    call splitexpression
    mov di,mnemonicstore
    call encodemnemonic
    cmp cx,0
    jne ___mneok
___badmne:
    call encodepseudo
    jmp ___encodeline
___mneok:
    call convquotedwords
    cmp cx,0
    jne ___qwok
    jmp ___encodeline
___qwok:
    mov di,exp1store
    call strlwr
    mov di,exp2store
    call strlwr
    call countparams
    cmp ax,2
    je ___twoparams
    jmp ___nottwoparams
___twoparams:
    call codetwoparam
    cmp cx,0
    jne ___encodeline
    mov ax,0
    jmp ___encodeline
___nottwoparams:
    cmp ax,0
    je ___zeroparams
___oneparam:
    call codeoneparam
    cmp cx,0
    jne ___encodeline
    mov ax,0
    jmp ___encodeline
___zeroparams:
    call codezeroparam
    cmp cx,0
    jne ___encodeline
    mov ax,0
    jmp ___encodeline
___encodeline:
    cmp cx,0
    je ___errcode
    mov di,codestore
___errcode:
    pop bx
    pop dx
    pop si
    pop ds
    ret
printnum:
    push di
    push bx
    mov di,tempbuffer
    mov bx,10
    call ntos
    call prints
    pop bx
    pop di
    ret
prints:
    pusha
    mov si, di
    mov ah, 0x00
    int 0x80
    popa
    ret

format_filenames:
    mov si, sys_arg_buf
    mov di, in_filename
    mov cx, 11
    rep movsb
    
    mov byte [in_filename + 8], 'A'
    mov byte [in_filename + 9], 'S'
    mov byte [in_filename + 10], 'M'

    mov si, sys_arg_buf
    mov di, out_filename
    mov cx, 8
.copy_out_name:
    lodsb
    cmp al, ' '
    je .done_out_name
    stosb
    loop .copy_out_name
.done_out_name:
    mov al, '.'
    stosb
    mov al, 'P'
    stosb
    mov al, 'E'
    stosb
    mov al, 'X'
    stosb
    xor al, al
    stosb
    ret

openfiles:
    mov ah, 0x02
    mov si, in_filename
    mov di, INPUT_BUFFER_OFFSET
    int 0x80
    or al, al
    jz .err
    mov word [in_buf_ptr], INPUT_BUFFER_OFFSET
    mov cx, 1
    ret
.err:
    mov di, errmsg_inferr
    xor cx, cx
    ret

rewind:
    mov word [in_buf_ptr], INPUT_BUFFER_OFFSET
    mov word [out_buf_ptr], OUTPUT_BUFFER_OFFSET + 16 
    mov word [eof], 0
    mov word [codelen], 0
    ret

closefiles:
    cmp byte [curpass], 3
    jne .skip
    mov cx, [codelen]
    or cx, cx
    jz .skip

    mov di, OUTPUT_BUFFER_OFFSET
    
    ; 1. 魔数 'PPP!' (4 bytes)
    mov byte [di], 'P'
    mov byte [di+1], 'P'
    mov byte [di+2], 'P'
    mov byte [di+3], '!'
    
    ; 2. 头部长度 = 16 (2 bytes)
    mov word [di+4], 16
    
    ; 3. 实际机器码长度 (2 bytes)
    mov ax, [codelen]
    mov word [di+6], ax
    
    ; 4. 初始栈指针 SP = 0xFFE0 (2 bytes)
    mov word [di+8], 0xFFE0
    
    ; 5. 保留字段 (6 bytes)
    mov word [di+10], 0
    mov word [di+12], 0
    mov word [di+14], 0

    mov cx, [codelen]
    add cx, 16                  ; 总写入长度 = 机器码长度 + 16字节头部
    mov ah, 0x03
    mov si, out_filename
    mov di, OUTPUT_BUFFER_OFFSET
    int 0x80
.skip:
    ret

readln:
    push ax
    push bx
    push dx
    push si
    mov si, [in_buf_ptr]
    mov di, getsbuffer
    xor cx, cx
.loop:
    mov al, [si]
    or al, al
    jz .eof
    inc si
    cmp al, 13
    je .loop
    cmp al, 10
    je .eol
    mov [di], al
    inc di
    inc cx
    cmp cx, 79
    jb .loop
.eol:
    mov byte [di], 0
    mov [in_buf_ptr], si
    mov cx, 1
    jmp .done
.eof:
    cmp cx, 0
    je .true_eof
    mov byte [di], 0
    mov [in_buf_ptr], si
    mov cx, 1
    jmp .done
.true_eof:
    mov word [eof], 2
    mov cx, 1
.done:
    pop si
    pop dx
    pop bx
    pop ax
    ret

pass:
    mov dx,cx
    mov word [line],1
    call rewind
    mov cx,[codebase]
    mov word [curip],cx
___repeat:
    call readln
    cmp word [eof],2
    je ___pass
    cmp cx,0
    je ___passerr
    
    ; FIX: Reset DI to the start of getsbuffer before calling encodeline
    mov di, getsbuffer
    
    mov cx,dx
    call encodeline
    cmp cx,0
    je ___passerr
    add [curip],ax
    cmp dx,0
    je ___nowrite
    cmp ax,0
    je ___nowrite
    
    ; Write output to memory buffer
    push cx
    push si
    push di
    mov cx, ax
    mov si, codestore
    mov di, [out_buf_ptr]
    push es
    push cs
    pop es
    rep movsb
    pop es
    mov [out_buf_ptr], di
    pop di
    pop si
    pop cx
    
    add [codelen],ax
___nowrite:
    inc word [line]
    jmp ___repeat
___pass:
    mov cx,1
___passerr:
    ret

printinst:
    push di
    mov di,msg_tab
    call prints
    mov di,labelstore
    call prints
    mov di,msg_tab
    call prints
    mov di,mnemonicstore
    call prints
    mov di,msg_tab
    call prints
    mov di,expsetstore
    call prints
    mov di,msg_crlf
    call prints
    pop di
    ret

start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov di, msg_banner
    call prints

    ; Get Arg 1 (Target ASM File) via PPP OS INT 0x80
    mov ah, 0x16
    mov di, sys_arg_buf
    int 0x80

    cmp byte [sys_arg_buf], ' '
    jne ___format_args
    
    mov di, errmsg_nofile
    call prints
    jmp ___start

___format_args:
    call format_filenames

___nextpass:
    mov di,msg_pass
    call prints
    mov al,[curpass]
    cbw
    call printnum
    mov di,msg_started
    call prints
    cmp byte [curpass],2
    je ___pass2
    call openfiles
    or cx,cx
    jz ___error
    xor cx,cx
    jz ___anypass
___pass2:
    call rewind
    call sortsym
    mov cx,1
___anypass:
    call pass
    or cx,cx
    jz ___error
    mov ax,[line]
    call printnum
    mov di,msg_linesproc
    call prints
    cmp byte [curpass],2
    jne ___notpass2
    mov ax,[codelen]
    call printnum
    mov di,msg_byteswrit
    call prints
___notpass2:
    mov di,msg_finished
    call prints
    mov al,[curpass]
    cmp al,1
    jne ___notpass1
    mov di,msg_crlf
    call prints
___notpass1:
    inc al
    mov [curpass],al
    cmp al,2
    jbe ___nextpass
    xor al,al
    jz ___start
___error:
    mov si,di
    mov di,msg_errline
    call prints
    mov ax,[line]
    call printnum
    mov di,msg_colon
    call prints
    cld
    lodsb
    mov di,si
    call prints
    cmp al,200
    ja ___start
    call printinst
___start:
    call closefiles
    ; Exit PPP OS Task
    mov ah, 0x04
    int 0x80
___endofcode: