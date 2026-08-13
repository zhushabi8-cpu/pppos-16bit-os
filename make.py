import os
import subprocess
import struct
import shutil

BOOT_SRC = "boot/boot.asm"
KERNEL_SRC = "kernel/kernel.asm"
SYS_DIR = "apps/sys"
EXT_DIR = "apps/ext"
GUI_DIR = "apps/gui"        
DRIVER_DIR = "drivers"      
INCLUDE_PATHS = ["kernel/", "apps/", "drivers/", "./"]

HDD_IMAGE = "ppp_os.img"
FDD_IMAGE = "floppy.img"

def print_step(msg):
    print(f"\n[*] {msg}")

def print_ok(msg):
    print(f"[+] {msg}")

def print_err(msg):
    print(f"[!] {msg}")

def find_qemu():
    qemu = shutil.which("qemu-system-i386") or shutil.which("qemu-system-i386w")
    if qemu: 
        return qemu
    fallback = r"C:\Program Files\qemu\qemu-system-i386w.exe"
    return fallback if os.path.exists(fallback) else "qemu-system-i386"

def run_compile(src, dest):
    print(f"  -> 编译: {src} => {dest}")
    cmd = ["nasm", "-f", "bin", src, "-o", dest]
    for p in INCLUDE_PATHS: 
        cmd.extend(["-i", p])
        
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print_err(f"编译错误 {src}:\n{result.stderr}")
        return False
    return True

def compile_apps(app_dir, ext=".PEX"):
    app_bins = []
    if os.path.exists(app_dir):
        for file in os.listdir(app_dir):
            if file.lower() in ("ppp_lib.inc", "pppgui.inc"): 
                continue
            if file.lower().endswith((".bin", ".pex", ".pge", ".pdr")): 
                continue
                
            if file.lower().endswith(".asm"):
                name = file[:file.rfind('.')].upper()
                raw_bin_path = os.path.join(app_dir, name + ".BIN")
                out_path = os.path.join(app_dir, name + ext)
                
                if run_compile(os.path.join(app_dir, file), raw_bin_path):
                    with open(raw_bin_path, "rb") as f:
                        raw_data = f.read()
                    
                    with open(out_path, "wb") as f:
                        if ext == ".PEX":
                            code_size = len(raw_data)
                            header = struct.pack('<4sHHHHI', b'PPP!', 16, code_size, 0xFFE0, 0, 0)
                            f.write(header + raw_data)
                        elif ext == ".PGE":
                            code_size = len(raw_data)
                            header = struct.pack('<4sHHHHI', b'PGE!', 16, code_size, 0xFFE0, 0, 0)
                            f.write(header + raw_data)
                        elif ext == ".PDR":
                            header = b'PDR\x01'.ljust(16, b'\x00')
                            f.write(header + raw_data)
                        else:
                            f.write(raw_data)
                        
                    app_bins.append((name, out_path))
                    os.remove(raw_bin_path) 
            else:
                app_bins.append((file.upper()[:15], os.path.join(app_dir, file)))
    return app_bins

def generate_registry():
    print_step("生成系统注册表 (SYSTEM.REG)...")
    reg_data = bytearray(2048)
    
    default_registry = [
        ("PAS", "PASIC"),     
        ("PPC", "EXTRACT"),   
        ("TXT", "EDIT"),      
        ("BMP", "BMP"),     
    ]
    
    for i, (k, v) in enumerate(default_registry):
        key_bytes = k.ljust(16, ' ').encode('ascii')
        val_bytes = v.ljust(8, ' ').encode('ascii')
        record = key_bytes + val_bytes + (b'\x00' * 8)
        reg_data[i*32 : i*32+32] = record
    
    with open("SYSTEM.REG", "wb") as f:
        f.write(reg_data)
    print_ok("SYSTEM.REG 已生成。")

def create_floppy_image():
    """生成 1.44MB 标准 FAT12 软盘镜像"""
    print_step("生成 1.44MB 软盘镜像 (floppy.img)...")
    img = bytearray(1440 * 1024)
    
    bpb = b'\xeb\x3c\x90' + b'MSDOS5.0' + \
          b'\x00\x02\x01\x01\x00\x02\xe0\x00\x40\x0b\xf0\x09\x00\x12\x00\x02\x00\x00\x00\x00\x00'
    img[0:len(bpb)] = bpb
    img[510:512] = b'\x55\xAA'
    
    img[512:515] = b'\xF0\xFF\xFF'
    img[512 + 9*512 : 515 + 9*512] = b'\xF0\xFF\xFF'
    
    with open(FDD_IMAGE, "wb") as f:
        f.write(img)
    print_ok("1.44MB 软盘空白镜像生成完毕。")

def build_hdd_image(app_bins):
    """打包 32MB 硬盘镜像，直接写入所有文件"""
    print_step(f"打包 32MB 硬盘镜像 ({HDD_IMAGE})...")
    
    img = bytearray(32 * 1024 * 1024)
    
    # 写入 Bootloader
    with open("BOOT.BIN", "rb") as bf: 
        img[0:512] = bf.read().ljust(512, b'\x00')
        
    img[512:515] = b'\xF0\xFF\xFF'
    img[512 + 9*512 : 515 + 9*512] = b'\xF0\xFF\xFF'
    
    current_cluster = 2
    root_dir_idx = 0
    
    def set_fat(cluster, next_cluster):
        offset = 512 + (cluster * 3) // 2
        if cluster % 2 == 0:
            img[offset] = next_cluster & 0xFF
            img[offset+1] = (img[offset+1] & 0xF0) | ((next_cluster >> 8) & 0x0F)
        else:
            img[offset] = (img[offset] & 0x0F) | ((next_cluster & 0x0F) << 4)
            img[offset+1] = (next_cluster >> 4) & 0xFF
        img[512 + 9*512 : 512 + 18*512] = img[512 : 512 + 9*512]
        
    def pack_file(filename, filepath):
        nonlocal current_cluster, root_dir_idx
        with open(filepath, "rb") as f: 
            data = f.read()
            
        size = len(data)
        sectors = max(1, (size + 511) // 512)
        start_c = current_cluster
        
        for i in range(sectors):
            chunk = data[i*512 : (i+1)*512].ljust(512, b'\x00')
            data_offset = 16896 + (current_cluster - 2) * 512
            img[data_offset : data_offset+512] = chunk
            set_fat(current_cluster, current_cluster + 1 if i < sectors - 1 else 0xFFF)
            current_cluster += 1
            
        name_ext = filename.upper().split('.')
        name = name_ext[0].ljust(8, ' ')[:8]
        ext = (name_ext[1] if len(name_ext) > 1 else '').ljust(3, ' ')[:3]
        
        entry = struct.pack("<8s3sB10sHHHI", name.encode('ascii'), ext.encode('ascii'), 0x20, b'\x00'*10, 0, 0, start_c, size)
        dir_offset = 9728 + root_dir_idx * 32
        img[dir_offset : dir_offset+32] = entry
        root_dir_idx += 1
        print(f"  -> 写入磁盘: {name.strip()}.{ext.strip()} (簇: {start_c}, 大小: {size}B)")

    pack_file("KERNEL.BIN", "KERNEL.BIN")
    pack_file("SYSTEM.REG", "SYSTEM.REG")
    
    for name, path in app_bins:
        pack_file(os.path.basename(path), path)
        
    with open(HDD_IMAGE, "wb") as f: 
        f.write(img)
        
    print_ok(f"32MB 硬盘镜像 {HDD_IMAGE} 打包完毕！")

def start_qemu():
    qemu_path = find_qemu()
    cmd = [
        qemu_path, 
        "-hda", HDD_IMAGE,                 
        "-fda", FDD_IMAGE,
        "-m", "32M",
        "-audiodev", "dsound,id=snd0",      
        "-machine", "pcspk-audiodev=snd0",  
        "-device", "sb16,iobase=0x220,irq=5,dma=1,audiodev=snd0", 
        "-serial", "tcp:127.0.0.1:8888,server,nowait"
    ]
    print_step("正在启动 QEMU...")
    print(f"  -> 执行命令: {' '.join(cmd)}")
    try:
        subprocess.Popen(cmd)
        print_ok("虚拟机已启动！")
    except Exception as e:
        print_err(f"QEMU 启动失败，请检查环境变量: {e}")

def main():
    for d in [SYS_DIR, EXT_DIR, GUI_DIR, DRIVER_DIR]:
        os.makedirs(d, exist_ok=True)

    print_step("编译核心组件...")
    if not run_compile(BOOT_SRC, "BOOT.BIN") or not run_compile(KERNEL_SRC, "KERNEL.BIN"):
        print_err("核心组件编译失败，构建终止！")
        return

    print_step("编译应用程序与驱动...")
    app_bins = []
    app_bins.extend(compile_apps(SYS_DIR, ext=".PEX"))
    app_bins.extend(compile_apps(EXT_DIR, ext=".PEX"))
    app_bins.extend(compile_apps(GUI_DIR, ext=".PGE"))
    app_bins.extend(compile_apps(DRIVER_DIR, ext=".PDR"))

    generate_registry()

    build_hdd_image(app_bins)

    create_floppy_image()

    print("构建完成！")
    
    choice = input("\n[?] 是否立即启动 QEMU 虚拟机? (y/n): ").strip().lower()
    if choice == 'y':
        start_qemu()
    else:
        print("[-] 取消启动。")

if __name__ == "__main__":
    main()
