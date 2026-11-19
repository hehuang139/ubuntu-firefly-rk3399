#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the actual partition geometry, loader and boot files of an image."""
import hashlib
import runpy
import re
import stat
import struct
import subprocess
import sys
from pathlib import Path

image, mode, loader, root = sys.argv[1:]
mode_id = {'sd': '22339001', 'emmc': '22339002'}[mode]
root = Path(root)
check_dtb = runpy.run_path(str(Path(__file__).resolve().parents[1] /
    'overlay/usr/local/lib/firefly-dtb.py'))['corrected']
image = Path(image)
if not stat.S_ISREG(image.stat().st_mode):
    raise SystemExit('Only an image file may be verified')
with image.open('rb') as f:
    table = f.read(512)
    assert table[510:512] == bytes.fromhex('55aa')
    assert struct.unpack_from('<I', table, 440)[0] == int(mode_id, 16)
    status, kind, start, count = struct.unpack_from('<B3xB3xII', table, 446)
    assert (status, kind, start) == (0x80, 0x83, 32768)
    assert table[462:510] == bytes(48)
    assert image.stat().st_size == (start + count) * 512 == 7168 * 1024**2
    payload = Path(loader).read_bytes()
    f.seek(64 * 512)
    assert f.read(len(payload)) == payload
    f.seek(start * 512)
    disk_partition = hashlib.sha256()
    with root.open('rb') as p:
        standalone = hashlib.sha256()
        for block in iter(lambda: p.read(4194304), b''):
            standalone.update(block)
            disk_partition.update(f.read(len(block)))
        assert not f.read(1) and standalone.digest() == disk_partition.digest()

def get(path):
    return subprocess.check_output(['debugfs', '-R', f'cat /{path}', str(root)],
                                   stderr=subprocess.DEVNULL)

conf = get('boot/extlinux/extlinux.conf').decode()
assert re.search(r'\broot=PARTUUID=' + mode_id + r'-01\b', conf)
assert get('etc/firefly-root-partuuid') == (mode_id + '-01\n').encode()
assert get('etc/fstab').startswith(b'PARTUUID=' + mode_id.encode() + b'-01 / ext4 ')
entries = re.split(r'^LABEL (\S+)\s*$', conf, flags=re.MULTILINE)
assert len(entries) >= 3 and entries[1] == 'ubuntu'
assert re.search(r'^DEFAULT ubuntu$', entries[0], re.MULTILINE)
for label, entry in zip(entries[1::2], entries[2::2]):
    paths = {}
    for key in ('LINUX', 'INITRD', 'FDT'):
        matches = re.findall(r'^\s+' + key + r' /(\S+)$', entry, re.MULTILINE)
        assert len(matches) == 1, (label, key)
        paths[key] = matches[0]
    fdt = paths['FDT']
    release = re.fullmatch(r'boot/firefly/([A-Za-z0-9][A-Za-z0-9.+_-]*)/rk3399-firefly\.dtb', fdt)[1]
    assert paths['LINUX'] == f'boot/firefly/{release}/Image'
    assert paths['INITRD'] == f'boot/initrd.img-{release}'
    assert f'root=PARTUUID={mode_id}-01 ' in entry
    assert get(paths['LINUX'])[56:60] == b'ARM\x64'
    assert get(paths['INITRD'])
    boot_dtb = get(fdt)
    check_dtb(boot_dtb)
    firmware = get(f'usr/lib/firmware/{release}/device-tree/rockchip/rk3399-firefly.dtb')
    check_dtb(firmware)
    assert boot_dtb == firmware, (label, 'boot and firmware DTBs differ')
    print(f'{mode}: {label} {release}, CPU/GPU banks 1/1, suspend-off preserved, DTB SHA256 {hashlib.sha256(boot_dtb).hexdigest()}')
assert b'GNOME' in get('usr/share/xsessions/gnome.desktop')
print(f'{mode}: loader offset, ext4 readback SHA256, PARTUUID, kernel, initrd, Firefly DTB and GNOME session check passed')
