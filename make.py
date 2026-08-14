import os, subprocess, struct, shutil

BOOT_SRC, KERNEL_SRC = "boot/boot.asm", "kernel/kernel.asm"
SYS_DIR, EXT_DIR, GUI_DIR, DRIVER_DIR = "apps/sys", "apps/ext", "apps/gui", "drivers"
INCLUDE_PATHS = ["kernel/", "apps/", "drivers/", "./"]
HDD_IMAGE, FDD_IMAGE = "ppp_os.img", "floppy.img"

def print_step(msg): print(f"\n[*] {msg}")
def print_ok(msg): print(f"[+] {msg}")
def print_err(msg): print(f"[!] {msg}")

def find_qemu():
    qemu = shutil.which("qemu-system-i386") or shutil.which("qemu-system-i386w")
    return qemu if qemu else r"C:\Program Files\qemu\qemu-system-i386w.exe"

def run_compile(src, dest):
    print(f"  -> 编译: {src} => {dest}")
    cmd = ["nasm", "-f", "bin", src, "-o", dest]
    for p in INCLUDE_PATHS: cmd.extend(["-i", p])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print_err(f"编译错误 {src}:\n{result.stderr}")
        return False
    return True

def compile_apps(app_dir, ext=".PEX"):
    app_bins = []
    if os.path.exists(app_dir):
        for file in os.listdir(app_dir):
            if file.lower() in ("ppp_lib.inc", "pppgui.inc"): continue
            if file.lower().endswith((".bin", ".pex", ".pge", ".pdr")): continue
            if file.lower().endswith(".asm"):
                name = file[:file.rfind('.')].upper()
                raw_bin = os.path.join(app_dir, name + ".BIN")
                out_path = os.path.join(app_dir, name + ext)
                if run_compile(os.path.join(app_dir, file), raw_bin):
                    with open(raw_bin, "rb") as f: raw_data = f.read()
                    with open(out_path, "wb") as f:
                        if ext == ".PEX":

                            if raw_data.startswith(b'PPP!'):
                                f.write(raw_data)
                            else:
                                f.write(struct.pack('<4sHHHHI', b'PPP!', 16, len(raw_data), 0xFFE0, 0, 0) + raw_data)
                        elif ext == ".PGE":
                            if raw_data.startswith(b'PGE!'):
                                f.write(raw_data)
                            else:
                                f.write(struct.pack('<4sHHHHI', b'PGE!', 16, len(raw_data), 0xFFE0, 0, 0) + raw_data)
                        elif ext == ".PDR": 
                            f.write(b'PDR\x01'.ljust(16, b'\x00') + raw_data)
                        else: 
                            f.write(raw_data)
                    app_bins.append((name, out_path))
                    os.remove(raw_bin) 
            else:
                app_bins.append((file.upper()[:15], os.path.join(app_dir, file)))
    return app_bins

def generate_registry():
    print_step("生成系统注册表 (SYSTEM.REG)...")
    reg_data = bytearray(2048)
    for i, (k, v) in enumerate([("SYS", "GUI"), ("PAS", "PASIC"), ("PPC", "EXTRACT"), ("TXT", "EDIT"), ("BMP", "BMP")]):
        reg_data[i*32 : i*32+32] = k.ljust(16, ' ').encode('ascii') + v.ljust(8, ' ').encode('ascii') + (b'\x00' * 8)
    with open("SYSTEM.REG", "wb") as f: f.write(reg_data)

def create_floppy_image():
    print_step("生成 1.44MB FAT12 软盘镜像 (floppy.img)...")
    img = bytearray(1440 * 1024)
    bpb = b'\xeb\x3c\x90' + b'PPPOS1.2' + b'\x00\x02\x01\x01\x00\x02\xe0\x00\x40\x0b\xf0\x09\x00\x12\x00\x02\x00\x00\x00\x00\x00'
    img[0:len(bpb)] = bpb
    img[510:512] = b'\x55\xAA'
    img[512:515], img[512 + 9*512 : 515 + 9*512] = b'\xF0\xFF\xFF', b'\xF0\xFF\xFF'
    with open(FDD_IMAGE, "wb") as f: f.write(img)

def build_hdd_image(app_bins):
    print_step(f"打包 32MB 分区硬盘镜像 ({HDD_IMAGE})...")
    img = bytearray(32 * 1024 * 1024)
    
    mbr_code = b'\x33\xC0\x8E\xD8\x8E\xC0\xBE\x00\x7C\xBF\x00\x06\xB9\x00\x01\xF3\xA5\xEA\x16\x06\x00\x00\xB4\x42\xBE\x26\x06\xCD\x13\xEA\x00\x7C\x00\x00'
    dapack = b'\x10\x00\x01\x00\x00\x7C\x00\x00\x3F\x00\x00\x00\x00\x00\x00\x00'
    img[0:len(mbr_code)] = mbr_code
    img[0x26:0x26+len(dapack)] = dapack
    img[0x1BE:0x1CE] = struct.pack('<B3sB3sII', 0x80, b'\x00\x01\x01', 0x06, b'\xFE\x3F\x40', 63, 32705)
    img[0x1CE:0x1DE] = struct.pack('<B3sB3sII', 0x00, b'\x00\x41\x41', 0x06, b'\xFE\x7F\x80', 32768, 32768)
    img[510:512] = b'\x55\xAA'

    def init_partition(start_lba, sectors, label):
        bpb = struct.pack('<3s8sHBHBHHBHHHII', b'\xeb\x3c\x90', label.encode().ljust(8, b' '), 512, 1, 1, 2, 512, 0, 0xF8, 256, 63, 255, start_lba, sectors)
        with open("BOOT.BIN", "rb") as bf: boot_code = bf.read()
        offset = start_lba * 512
        img[offset:offset+len(bpb)] = bpb
        img[offset+len(bpb):offset+512] = boot_code[len(bpb):512].ljust(512-len(bpb), b'\x00')
        img[offset+510:offset+512] = b'\x55\xAA'
        img[offset+512:offset+516], img[offset+512+256*512:offset+516+256*512] = b'\xF8\xFF\xFF\xFF', b'\xF8\xFF\xFF\xFF'

    init_partition(63, 32705, "PPPOS_C")
    init_partition(32768, 32768, "PPPOS_D")

    current_cluster = 2
    root_dir_idx = 0
    def pack_file(filename, filepath):
        nonlocal current_cluster, root_dir_idx
        with open(filepath, "rb") as f: data = f.read()
        
        size = len(data)
        sectors = max(1, (size + 511) // 512)
        
        start_c = current_cluster
        for i in range(sectors):
            img[(63 + 545 + current_cluster - 2) * 512 : (63 + 545 + current_cluster - 2) * 512 + 512] = data[i*512 : (i+1)*512].ljust(512, b'\x00')
            fat_val = current_cluster + 1 if i < sectors - 1 else 0xFFFF
            struct.pack_into('<H', img, (63 + 1) * 512 + current_cluster * 2, fat_val)
            struct.pack_into('<H', img, (63 + 257) * 512 + current_cluster * 2, fat_val)
            current_cluster += 1
        name_ext = filename.upper().split('.')
        entry = struct.pack("<8s3sB10sHHHI", name_ext[0].ljust(8, ' ')[:8].encode(), (name_ext[1] if len(name_ext)>1 else '').ljust(3, ' ')[:3].encode(), 0x20, b'\x00'*10, 0, 0, start_c, size)
        img[(63 + 513) * 512 + root_dir_idx * 32 : (63 + 513) * 512 + root_dir_idx * 32 + 32] = entry
        root_dir_idx += 1

    pack_file("KERNEL.BIN", "KERNEL.BIN")
    pack_file("SYSTEM.REG", "SYSTEM.REG")
    for name, path in app_bins: pack_file(os.path.basename(path), path)
        
    with open(HDD_IMAGE, "wb") as f: f.write(img)
    print_ok(f"32MB 硬盘镜像打包完毕！")

def start_qemu():
    cmd = [find_qemu(), "-hda", HDD_IMAGE, "-fda", FDD_IMAGE, "-m", "32M", "-audiodev", "dsound,id=snd0", "-machine", "pcspk-audiodev=snd0", "-device", "sb16,iobase=0x220,irq=5,dma=1,audiodev=snd0", "-serial", "tcp:127.0.0.1:8888,server,nowait"]
    try: subprocess.Popen(cmd)
    except Exception as e: print_err(f"QEMU 启动失败: {e}")

if __name__ == "__main__":
    for d in [SYS_DIR, EXT_DIR, GUI_DIR, DRIVER_DIR]: os.makedirs(d, exist_ok=True)
    if not run_compile(BOOT_SRC, "BOOT.BIN") or not run_compile(KERNEL_SRC, "KERNEL.BIN"): exit()
    app_bins = compile_apps(SYS_DIR, ".PEX") + compile_apps(EXT_DIR, ".PEX") + compile_apps(GUI_DIR, ".PGE") + compile_apps(DRIVER_DIR, ".PDR")
    generate_registry()
    build_hdd_image(app_bins)
    create_floppy_image()
    if input("\n[?] 是否立即启动 QEMU 虚拟机? (y/n): ").strip().lower() == 'y': start_qemu()
