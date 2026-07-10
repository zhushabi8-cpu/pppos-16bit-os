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
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [boot_drive], dl

    mov si, DAPack
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    jmp 0x0800:0000

disk_error:
    mov al, 'E'
    mov ah, 0x0E
    int 0x10
    jmp $

DAPack:
    db 0x10
    db 0
    dw 19
    dw 0x0000
    dw 0x0800
    dd 33
    dd 0

boot_drive db 0

times 510-($-$$) db 0
dw 0xAA55