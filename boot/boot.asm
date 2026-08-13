[BITS 16]
[ORG 0x7C00]

jmp short start
nop

OEMName             db "PPPOS   "
BytesPerSector      dw 512
SectorsPerCluster   db 1
ReservedSectors     dw 1
TotalFATs           db 2
MaxRootEntries      dw 224
TotalSectorsSmall   dw 2880
MediaDescriptor     db 0xF0
SectorsPerFAT       dw 9
SectorsPerTrack     dw 18
NumHeads            dw 2
HiddenSectors       dd 0
TotalSectorsLarge   dd 0
DriveNumber         db 0x80
Flags               db 0
Signature           db 0x29
VolumeID            dd 0x12345678
VolumeLabel         db "PPPOS HDD  "
SystemID            db "FAT12   "

start:
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    
    mov sp, 0x7C00              

    mov [boot_drive], dl        

    mov dword [DAPack_LBA], 19
    mov word [DAPack_Seg], 0x0800
    mov cx, 14
.read_root:
    push cx
    mov si, DAPack
    mov dl, [boot_drive]
    mov ah, 0x42                
    int 0x13
    jc disk_error
    add word [DAPack_Seg], 0x0020
    add dword [DAPack_LBA], 1
    pop cx
    loop .read_root

    mov ax, 0x0800
    mov es, ax
    xor bx, bx                  
.search_loop:
    cmp bx, 224 * 32            
    jae not_found
    
    mov si, kernel_name
    mov di, bx
    mov cx, 11
    pusha                       
    repe cmpsb                  
    popa
    je .found                   
    
    add bx, 32                  
    jmp .search_loop

.found:
    mov ax, [es:bx + 26]        
    add ax, 31                  
    mov word [DAPack_LBA], ax   
    mov word [DAPack_LBA+2], 0
    mov word [DAPack_Seg], 0x0800
    mov cx, 96
.read_kernel:
    push cx
    mov si, DAPack
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error
    add word [DAPack_Seg], 0x0020
    add dword [DAPack_LBA], 1
    pop cx
    loop .read_kernel

    mov dl, [boot_drive]        
    jmp 0x0800:0000             

disk_error:
    mov al, 'E'
    jmp print_err
not_found:
    mov al, 'N'
print_err:
    mov ah, 0x0E
    mov bx, 0x000F
    int 0x10
    jmp $

kernel_name db "KERNEL  BIN"

align 4
DAPack:
    db 0x10                 
    db 0                    
    dw 1                    
    dw 0x0000               
DAPack_Seg:
    dw 0x0800               
DAPack_LBA:
    dd 0                    
DAPack_LBA_High:
    dd 0                    

boot_drive db 0

times 510-($-$$) db 0
dw 0xAA55