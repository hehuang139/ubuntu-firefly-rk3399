#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Boot the built Ubuntu image on the synthetic Firefly RK3399 eMMC model."""
import argparse
import json
import os
import re
import selectors
import subprocess
import time
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--qemu', type=Path, required=True)
p.add_argument('--model-dtb', type=Path, required=True)
p.add_argument('--image', type=Path, required=True)
p.add_argument('--work', type=Path, required=True)
p.add_argument('--kernel-release', required=True)
p.add_argument('--timeout', type=int, default=180)
a = p.parse_args()
if not re.fullmatch(r'[0-9A-Za-z.+_-]+', a.kernel_release):
    p.error('invalid kernel release')
work = a.work.resolve()
work.mkdir(mode=0o700)
source = work / 'root.ext4'
subprocess.run(['dd', f'if={a.image.resolve()}', f'of={source}', 'bs=1M', 'skip=16',
                'conv=sparse', 'status=none'], check=True)
conf = subprocess.check_output(['debugfs', '-R', 'cat /boot/extlinux/extlinux.conf', str(source)],
                               text=True, stderr=subprocess.DEVNULL)
root = re.search(r'\broot=PARTUUID=(22339002-01)\b', conf)[1]
for key, target in [('LINUX', 'Image'), ('INITRD', 'initrd.img')]:
    disk_path = re.search(r'^\s+' + key + r' (/\S+)', conf, flags=re.MULTILINE)[1]
    subprocess.run(['debugfs', '-R', f'dump {disk_path} {work / target}', str(source)],
                   check=True, stderr=subprocess.DEVNULL)
    if (work / target).stat().st_size == 0:
        raise SystemExit(f'File not extracted: {disk_path}')
source.unlink()
disk = work / 'virtual-emmc.img'
subprocess.run(['cp', '--reflink=auto', '--sparse=always', str(a.image.resolve()), str(disk)], check=True)
# The SDHCI model asks for a power of two chip size, not the actual image size.
with disk.open('r+b') as f:
    f.truncate(8 * 1024**3)
cmd = [str(a.qemu.resolve()), '-machine', 'firefly-rk3399,accel=tcg', '-m', '2G',
       '-display', 'none', '-serial', 'stdio', '-monitor', 'none', '-no-reboot', '-snapshot',
       '-kernel', str(work / 'Image'), '-dtb', str(a.model_dtb.resolve()), '-initrd', str(work / 'initrd.img'),
       '-append', f'console=ttyS0,1500000n8 root=PARTUUID={root} rootfstype=ext4 rw rootwait systemd.unit=multi-user.target systemd.mask=serial-getty@ttyS2.service',
       '-drive', f'file={disk},if=none,format=raw,id=disk', '-device', 'emmc,drive=disk']
checks = {
    'ubuntu_kernel_loaded': rb'Linux version ' + re.escape(a.kernel_release.encode()),
    'all_six_cores_online': rb'SMP: Total of 6 processors activated',
    'virtual_mmc_partition': rb'mmcblk0: p1',
    'ext4_root_mounted': rb'EXT4-fs \(mmcblk0p1\): mounted filesystem',
    'systemd_multi_user_target': rb'Reached target .*Multi-User System',
    'ubuntu_serial_login': rb'Ubuntu 22\.04.*\bttyS0.*\bfirefly-rk3399 login:',
}
begin = time.monotonic()
log = work / 'serial.log'
data = bytearray()
with subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as vm, \
     selectors.DefaultSelector() as selector, log.open('wb') as trace:
    selector.register(vm.stdout, selectors.EVENT_READ)
    passed = {k: False for k in checks}
    try:
        while time.monotonic() < begin + a.timeout:
            if not selector.select(timeout=1):
                continue
            block = os.read(vm.stdout.fileno(), 65536)
            if not block:
                break
            trace.write(block)
            trace.flush()
            data.extend(block)
            for key, signature in checks.items():
                if not passed[key] and re.search(signature, data, re.S):
                    passed[key] = True
                    print(f'PASS {key}', flush=True)
            if all(passed.values()) or b'Kernel panic - not syncing' in data:
                break
    finally:
        if vm.poll() is None:
            vm.terminate()
            try:
                vm.wait(timeout=5)
            except subprocess.TimeoutExpired:
                vm.kill()
report = {'model': 'firefly-rk3399', 'media': 'virtual eMMC, direct Linux with QEMU DTB',
          'target': 'multi-user.target', 'root_partuuid': root, 'kernel_release': a.kernel_release,
          'duration_seconds': round(time.monotonic() - begin, 2), 'checks': passed}
(work / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
if not all(passed.values()):
    p.exit(1, f'Boot check failed: {report}; see {log}\n')
