#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# This assembler operates exclusively on files in the project directory.
set -euo pipefail
mode=${1:?usage: assemble.sh sd|emmc}
case $mode in
  sd) signature=22339001; label=FF3399-TF; expected=074afaeec584916a1d7d939b4d46a328c804c5e0754e81207ed656874f48c23c ;;
  emmc) signature=22339002; label=FF3399-EMMC; expected=cb2c57287af28b1abc4cb93be985a9c0afff1d6b9553429c2b9392f4b1577e8f ;;
  *) exit 2 ;;
esac
cd /build
root=/build/work/rootfs
loader="/build/bootloader/$mode/u-boot-rockchip.bin"
read -r release < records/kernel-release.txt
printf '%s  %s\n' "$expected" "$loader" | sha256sum -c -
out="outputs/firefly-rk3399-ubuntu-22.04-gnome-arm64-${mode}-vsel1-test2.img"
[[ ! -e $out && ! -L $out ]]
tmp=$(mktemp -d "work/assemble-$mode.XXXXXX")
size_mib=7168
root_mib=16
partuuid="$signature-01"
printf '%s\n' "$partuuid" > "$root/etc/firefly-root-partuuid"
printf 'PARTUUID=%s / ext4 defaults,noatime 0 1\n' "$partuuid" > "$root/etc/fstab"
FIREFLY_ROOTFS="$root" bash "$root/usr/local/sbin/firefly-update-boot" "$release"
grep -q "APPEND root=PARTUUID=$partuuid " "$root/boot/extlinux/extlinux.conf"
[[ -s $root/boot/firefly/$release/Image ]]
[[ -s $root/boot/firefly/$release/rk3399-firefly.dtb ]]
[[ -s $root/boot/initrd.img-$release ]]
# MBR fits systems containing a stock Rockchip loader at sector 64.
truncate -s "${size_mib}M" "$tmp/disk.img"
sectors=$(( (size_mib - root_mib) * 2048 ))
start=$(( root_mib * 2048 ))
printf 'label: dos\nlabel-id: 0x%s\nunit: sectors\n\nstart=%s, size=%s, type=83, bootable\n' "$signature" "$start" "$sectors" |
    sfdisk --no-reread "$tmp/disk.img"
[[ $(stat -c %s "$loader") -le $(( root_mib * 1048576 - 32768 )) ]]
dd if="$loader" of="$tmp/disk.img" bs=512 seek=64 conv=notrunc status=none
truncate -s "$(( size_mib - root_mib ))M" "$tmp/root.ext4"
mkfs.ext4 -q -F -L "$label" -O '^64bit,^metadata_csum' \
    -E lazy_itable_init=0,lazy_journal_init=0 -m 1 -d "$root" "$tmp/root.ext4"
e2fsck -f -n "$tmp/root.ext4"
dd if="$tmp/root.ext4" of="$tmp/disk.img" bs=1M seek="$root_mib" conv=notrunc,sparse status=none
python3 scripts/verify.py "$tmp/disk.img" "$mode" "$loader" "$tmp/root.ext4"
mv -- "$tmp/disk.img" "$out"
unlink "$tmp/root.ext4"
rmdir "$tmp"
printf 'Raw image ready: %s\n' "$out"
