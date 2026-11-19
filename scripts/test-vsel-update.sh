#!/bin/bash
# SPDX-License-Identifier: MIT
# Exercise the installed kernel and initramfs hooks against both media layouts.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
overlay="$PWD/overlay"
old=${1:?usage: test-vsel-update.sh OLD_FIRELY_DTB KERNEL INITRD}
kernel=${2:?kernel image required}
initrd=${3:?initrd required}
helper="$overlay/usr/local/lib/firefly-dtb.py"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
if python3 "$helper" check "$old"; then
    printf 'Expected a 0/1 DTB as the regression fixture.\n' >&2
    exit 1
fi
python3 "$helper" fix "$old" "$work/fixed.dtb"
python3 - "$old" "$work/fixed.dtb" <<'PY'
from pathlib import Path
import sys
old, fixed = (Path(path).read_bytes() for path in sys.argv[1:])
assert len(old) == len(fixed)
assert [(a, b) for a, b in zip(old, fixed) if a != b] == [(0, 1)]
PY
# Use the real hook files, with only their executable path redirected to this checkout.
for hook in etc/kernel/postinst.d/zz-firefly-extlinux etc/initramfs/post-update.d/zz-firefly-extlinux; do
    sed "s|^exec /usr/local/sbin/firefly-update-boot|exec \"\$FIREFLY_TEST_HELPER\"|" "$overlay/$hook" > "$work/$(dirname "$hook" | tr / _)"
done
export FIREFLY_TEST_HELPER="$overlay/usr/local/sbin/firefly-update-boot"
for uuid in 22339001-01 22339002-01; do
    export FIREFLY_ROOTFS="$work/$uuid"
    r="$FIREFLY_ROOTFS"
    mkdir -p "$r/etc" "$r/boot" "$r/usr/local/lib"
    cp "$helper" "$r/usr/local/lib/"
    printf '%s\n' "$uuid" > "$r/etc/firefly-root-partuuid"
    for v in 6.8.0-149-fixture 6.8.0-150-fixture 6.8.0-151-fixture; do
        firmware="$r/lib/firmware/$v/device-tree/rockchip/rk3399-firefly.dtb"
        mkdir -p -- "$(dirname -- "$firmware")"
        cp "$old" "$firmware"
        ln -s -- "$(realpath "$kernel")" "$r/boot/vmlinuz-$v"
        case $v in
            *-149-*)
                ln -s -- "$(realpath "$initrd")" "$r/boot/initrd.img-$v"
                sh "$work/etc_kernel_postinst.d" "$v" ;;
            *-150-*)
                sh "$work/etc_kernel_postinst.d" "$v" # No initrd yet; keep previous default.
                grep -Fq '/6.8.0-149-fixture/rk3399-firefly.dtb' "$r/boot/extlinux/extlinux.conf"
                ln -s -- "$(realpath "$initrd")" "$r/boot/initrd.img-$v"
                sh "$work/etc_initramfs_post-update.d" "$v" ;;
            *-151-*)
                ln -s -- "$(realpath "$initrd")" "$r/boot/initrd.img-$v"
                # Simulate an unrecognized future regulator configuration.
                sed -i 's/silergy,syr828/silergy,syr829/g' "$firmware"
                cp "$r/boot/extlinux/extlinux.conf" "$work/before"
                if sh "$work/etc_initramfs_post-update.d" "$v"; then exit 1; fi
                cmp "$work/before" "$r/boot/extlinux/extlinux.conf"
                [[ ! -e $r/boot/firefly/$v/rk3399-firefly.dtb ]]
                continue ;;
        esac
        cmp "$work/fixed.dtb" "$firmware"
        cmp "$firmware" "$r/boot/firefly/$v/rk3399-firefly.dtb"
        grep -Fq "/$v/rk3399-firefly.dtb" "$r/boot/extlinux/extlinux.conf"
    done
    grep -Fq 'LABEL previous' "$r/boot/extlinux/extlinux.conf"
    [[ $(awk '/ FDT / { print $2; exit }' "$r/boot/extlinux/extlinux.conf") == /boot/firefly/6.8.0-150-fixture/rk3399-firefly.dtb ]]
    printf '%s: kernel post-install, initramfs post-update, fallback, and rejection passed\n' "$uuid"
done
