import os
import subprocess
import struct
import shutil
import sys
from datetime import datetime

BOOT_SRC = "boot/boot.asm"
KERNEL_SRC = "kernel/kernel.asm"
SYS_DIR = "apps/sys"
EXT_DIR = "apps/ext"
DRIVER_DIR = "drivers"
INCLUDE_PATHS = ["kernel/", "apps/", "drivers/", "./"]
IMAGE_NAME = "ppp_os.img"

def log(msg):
    print(msg)

def run_compile(src, dest):
    log(f"[*] 编译: {src} -> {dest}")
    cmd = ["nasm", "-f", "bin", src, "-o", dest]
    for p in INCLUDE_PATHS:
        cmd.extend(["-i", p])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log(f"[!] 编译错误 {src}:\n{result.stderr}")
        return False
    return True

def compile_apps(app_dir, ext=".PEX"):
    """编译应用程序/驱动，并自动注入文件头"""
    app_bins = []
    if not os.path.exists(app_dir):
        return app_bins
    for file in os.listdir(app_dir):
        if file.lower() == "ppp_lib.inc" or file.lower().endswith((".bin", ".pex", ".dri")):
            continue
        if file.lower().endswith(".asm"):
            name = file[:file.rfind('.')].upper()
            raw_bin_path = os.path.join(app_dir, name + ".BIN")
            out_path = os.path.join(app_dir, name + ext)
            if run_compile(os.path.join(app_dir, file), raw_bin_path):
                with open(raw_bin_path, "rb") as f:
                    raw_data = f.read()
                code_size = len(raw_data)
                header = struct.pack('<4sHHHHI', b'PPP!', 16, code_size, 0xFFE0, 0, 0)
                with open(out_path, "wb") as f:
                    f.write(header + raw_data)
                app_bins.append((name, out_path))
                os.remove(raw_bin_path)
        else:
            app_bins.append((file.upper()[:15], os.path.join(app_dir, file)))
    return app_bins

def do_build():
    log("\n" + "="*50)
    log("PPP OS - 32MB LBA 硬盘镜像构建开始...")
    if not run_compile(BOOT_SRC, "BOOT.BIN") or not run_compile(KERNEL_SRC, "KERNEL.BIN"):
        log("[!] 核心组件编译失败，构建终止！")
        return False

    app_bins = []
    app_bins.extend(compile_apps(SYS_DIR, ext=".PEX"))
    app_bins.extend(compile_apps(EXT_DIR, ext=".PEX"))
    app_bins.extend(compile_apps(DRIVER_DIR, ext=".DRI"))

    try:
        log("[*] 正在格式化 32MB 硬盘镜像...")
        img = bytearray(32 * 1024 * 1024)

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
            ext = name_ext[1].ljust(3, ' ')[:3] if len(name_ext) > 1 else '   '
            entry = struct.pack("<8s3sB10sHHHI",
                                name.encode('ascii'),
                                ext.encode('ascii'),
                                0x20,
                                b'\x00'*10,
                                0, 0, start_c, size)
            dir_offset = 9728 + root_dir_idx * 32
            img[dir_offset : dir_offset+32] = entry
            root_dir_idx += 1
            log(f"  -> 注入: {name.strip()}.{ext.strip()} (簇: {start_c}, {size}B)")

        pack_file("KERNEL.BIN", "KERNEL.BIN")
        for name, path in app_bins:
            pack_file(os.path.basename(path), path)

        with open(IMAGE_NAME, "wb") as f:
            f.write(img)

        for f in ["BOOT.BIN", "KERNEL.BIN"]:
            if os.path.exists(f):
                os.remove(f)
        for root, _, files in os.walk("."):
            for fn in files:
                if fn.upper().endswith(".BIN") and fn not in ["BOOT.BIN", "KERNEL.BIN"]:
                    os.remove(os.path.join(root, fn))

        log(f"构建成功! 生成: {IMAGE_NAME} (32MB HDD)")
        return True
    except Exception as e:
        log(f"[!] 镜像打包失败: {e}")
        return False

def run_qemu():
    if not os.path.exists(IMAGE_NAME):
        log("[!] 找不到镜像，请先构建！")
        return
    qemu = shutil.which("qemu-system-i386") or shutil.which("qemu-system-i386w")
    if not qemu:
        qemu = r"C:\Program Files\qemu\qemu-system-i386w.exe"
        if not os.path.exists(qemu):
            log("[!] 找不到 QEMU，请检查安装")
            return
    log("[*] 正在启动 QEMU...")
    cmd = [
        qemu,
        "-hda", IMAGE_NAME,
        "-m", "32M",
        "-audiodev", "dsound,id=snd0",
        "-machine", "pcspk-audiodev=snd0",
        "-device", "sb16,iobase=0x220,irq=5,dma=1,audiodev=snd0",
        "-serial", "tcp:127.0.0.1:8888,server,nowait"
    ]
    try:
        subprocess.Popen(cmd)
        log("[+] 虚拟机运行中...")
    except Exception as e:
        log(f"[!] QEMU 启动失败: {e}")

if __name__ == "__main__":
    os.makedirs(SYS_DIR, exist_ok=True)
    os.makedirs(EXT_DIR, exist_ok=True)
    os.makedirs(DRIVER_DIR, exist_ok=True)

    if len(sys.argv) > 1:
        if sys.argv[1] == "--build":
            do_build()
        elif sys.argv[1] == "--run":
            run_qemu()
        elif sys.argv[1] == "--all":
            if do_build():
                run_qemu()
        else:
            print("用法: python make.py [--build | --run | --all]")
    else:
        if do_build():
            run_qemu()
