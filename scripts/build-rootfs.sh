#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
BASE=downloads/ubuntu-base-22.04.5-base-arm64.tar.gz
RFS=/build/work/rootfs
ROOT_STORE=/build/work
mkdir -p "$RFS"
if [[ ! -f $RFS/etc/os-release ]]; then
  printf '%s  %s\n' 075d4abd2817a5023ab0a82f5cb314c5ec0aa64a9c0b40fd3154ca3bfdae979f "$BASE" | sha256sum -c -
  tar --numeric-owner --xattrs -xpf "$BASE" -C "$RFS"
fi
if [[ ! -e /proc/sys/fs/binfmt_misc/register ]]; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
REGISTERED=0
if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
  update-binfmts --enable qemu-aarch64
  REGISTERED=1
fi
cleanup() {
  umount "$RFS/proc" 2>/dev/null || true
  umount "$RFS/sys" 2>/dev/null || true
  umount -R "$RFS/dev" 2>/dev/null || true
  if (( REGISTERED )); then update-binfmts --disable qemu-aarch64 || true; fi
}
trap cleanup EXIT
install -m 0755 /usr/bin/qemu-aarch64-static "$RFS/usr/bin/qemu-aarch64-static"
mount --rbind /dev "$RFS/dev"
mount --make-rslave "$RFS/dev"
mount -t proc proc "$RFS/proc"
mount -t sysfs sysfs "$RFS/sys"
unlink "$RFS/etc/resolv.conf" 2>/dev/null || true
cp /etc/resolv.conf "$RFS/etc/resolv.conf"
install -Dm 0644 /etc/ssl/certs/ca-certificates.crt "$RFS/etc/ssl/certs/ca-certificates.crt"
printf '#!/bin/sh\nexit 101\n' > "$RFS/usr/sbin/policy-rc.d"
chmod +x "$RFS/usr/sbin/policy-rc.d"
cat > "$RFS/etc/apt/sources.list" <<'SOURCES'
deb https://ports.ubuntu.com/ubuntu-ports/ jammy main restricted universe multiverse
deb https://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
SOURCES
cat > "$RFS/etc/apt/apt.conf.d/90firefly-build" <<'APT'
Acquire::Retries "5";
Acquire::Languages "none";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT
# Always retain a serial getty in addition to HDMI. The drivers can be modular.
install -d "$RFS/etc/initramfs-tools/conf.d" "$RFS/etc/initramfs-tools"
install -Dm 0755 /build/overlay/etc/initramfs-tools/hooks/firefly-storage "$RFS/etc/initramfs-tools/hooks/firefly-storage"
printf 'MODULES=most\nCOMPRESS=gzip\nFSTYPE=ext4\n' > "$RFS/etc/initramfs-tools/conf.d/20-firefly"
chroot "$RFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C FIREFLY_SKIP_UPDATE="${FIREFLY_SKIP_UPDATE:-0}" /bin/bash -eux <<'CHROOT'
dpkg --print-architecture
if [[ ${FIREFLY_SKIP_UPDATE:-0} != 1 ]]; then apt-get update; fi
apt-get install -y --no-install-recommends \
  linux-image-generic-hwe-22.04 linux-firmware initramfs-tools \
  ubuntu-minimal systemd-sysv systemd-timesyncd udev dbus-user-session \
  network-manager netplan.io wpasupplicant wireless-regdb \
  gdm3 gnome-initial-setup gnome-shell gnome-session gnome-control-center \
  gnome-terminal nautilus gnome-system-monitor gnome-disk-utility gnome-keyring \
  dconf-cli gedit evince file-roller gnome-calculator eog epiphany-browser \
  gvfs-backends adwaita-icon-theme-full ubuntu-wallpapers-jammy \
  libgl1-mesa-dri mesa-utils xserver-xorg-core xserver-xorg-input-libinput \
  xwayland pulseaudio alsa-utils pavucontrol bluez \
  locales language-pack-zh-hans language-pack-gnome-zh-hans tzdata \
  fonts-noto-cjk fonts-noto-core ibus-libpinyin \
  openssh-server sudo ca-certificates curl ethtool zram-tools cloud-guest-utils
locale-gen en_US.UTF-8 zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8
apt-get check
test -z "$(dpkg --audit)"
gnome-shell --version
passwd -l root
CHROOT
test -n "$(find "$RFS/lib/firmware" "$RFS/boot" -name rk3399-firefly.dtb -print -quit)"
chroot "$RFS" dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' > /build/records/packages.tsv
printf 'Installed signed Ubuntu ARM64 packages and located the Firefly RK3399 device tree.\n'
