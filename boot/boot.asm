[BITS 16]
[ORG 0x7C00]

jmp short start
nop

OEMName             db "PPPOS1.6"
BytesPerSector      dw 512
SectorsPerCluster   db 1
ReservedSectors     dw 1
TotalFATs           db 2
MaxRootEntries      dw 512        
TotalSectorsSmall   dw 0
MediaDescriptor     db 0xF8
SectorsPerFAT       dw 256        
SectorsPerTrack     dw 63
NumHeads            dw 255
HiddenSectors       dd 0          
TotalSectorsLarge   dd 65536      
DriveNumber         db 0x80
Flags               db 0
Signature           db 0x29
VolumeID            dd 0x12345678
VolumeLabel         db "PPPOS HDD  "
SystemID            db "FAT16   "

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00              
    sti

    mov [boot_drive], dl        

    mov al, [TotalFATs]
    cbw
    mul word [SectorsPerFAT]
    add ax, [ReservedSectors]
    add ax, word [HiddenSectors]
    mov word [DAPack_LBA], ax
    mov dx, word [HiddenSectors+2]
    adc dx, 0
    mov word [DAPack_LBA+2], dx
    mov [root_start_lba], ax
    mov ax, [MaxRootEntries]
    mov cx, 32
    mul cx
    add ax, 511
    shr ax, 9
    mov [root_sectors], ax

    mov ax, [root_start_lba]
    add ax, [root_sectors]
    sub ax, 2
    mov [cluster_offset], ax

    mov cx, [root_sectors]
    mov word [DAPack_Seg], 0x0800
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
    
    mov ax, [root_sectors]
    shl ax, 9
    mov [max_root_bytes], ax
    
.search_loop:
    cmp bx, [max_root_bytes]
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
    add ax, [cluster_offset]
    mov word [DAPack_LBA], ax   
    mov dx, word [HiddenSectors+2]
    adc dx, 0
    mov word [DAPack_LBA+2], dx
    
    mov word [DAPack_Seg], 0x0800
    
    mov ax, [es:bx + 28]
    or ax, ax
    jz disk_error               
    add ax, 511
    shr ax, 9                   
    mov cx, ax

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

root_start_lba dw 0
root_sectors   dw 0
cluster_offset dw 0
max_root_bytes dw 0

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