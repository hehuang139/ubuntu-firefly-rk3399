#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=/build/work/rootfs
[[ -s /build/records/packages.tsv ]]
[[ -f $root/etc/os-release ]]
if [[ ! -e /proc/sys/fs/binfmt_misc/register ]]; then
  mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
fi
registered=0
if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
  update-binfmts --enable qemu-aarch64
  registered=1
fi
cleanup() {
  umount "$root/proc" 2>/dev/null || true
  umount "$root/sys" 2>/dev/null || true
  umount -R "$root/dev" 2>/dev/null || true
  if (( registered )); then update-binfmts --disable qemu-aarch64 || true; fi
}
trap cleanup EXIT
mount --rbind /dev "$root/dev"
mount --make-rslave "$root/dev"
mount -t proc proc "$root/proc"
mount -t sysfs sysfs "$root/sys"
printf 'MODULES=most\nCOMPRESS=gzip\nFSTYPE=ext4\n' > "$root/etc/initramfs-tools/conf.d/20-firefly"
chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get -y upgrade
chroot "$root" apt-get check
[[ -z $(chroot "$root" dpkg --audit) ]]
chroot "$root" dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' > /build/records/packages.tsv
rsync -a --chown=0:0 --chmod=go-w /build/overlay/ "$root/"
chmod 0600 "$root/etc/netplan/01-network-manager.yaml"
printf 'firefly-rk3399\n' > "$root/etc/hostname"
cat > "$root/etc/hosts" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 firefly-rk3399
::1 localhost ip6-localhost ip6-loopback
HOSTS
ln -sfn /usr/share/zoneinfo/Asia/Shanghai "$root/etc/localtime"
printf 'Asia/Shanghai\n' > "$root/etc/timezone"
printf '/usr/sbin/gdm3\n' > "$root/etc/X11/default-display-manager"
chroot "$root" /usr/bin/dconf update
chroot "$root" systemctl --root=/ enable firefly-grow-root.timer NetworkManager.service systemd-resolved.service systemd-timesyncd.service serial-getty@ttyS2.service
ln -sfn /lib/systemd/system/gdm3.service "$root/etc/systemd/system/display-manager.service"
chroot "$root" systemctl --root=/ set-default graphical.target
for unit in ssh.service ssh.socket; do
  if [[ -f "$root/lib/systemd/system/$unit" ]]; then
    chroot "$root" systemctl --root=/ disable "$unit"
  fi
done
chroot "$root" apt-get clean
release=$(find "$root/boot" -maxdepth 1 -type f -name 'vmlinuz-*' -printf '%f\n' | sed 's/^vmlinuz-//' | sort -V | tail -1)
[[ -n $release && -s $root/boot/initrd.img-$release && -s $root/lib/firmware/$release/device-tree/rockchip/rk3399-firefly.dtb ]]
list_initrd() { chroot "$root" lsinitramfs "/boot/initrd.img-$release" > /build/records/initramfs.list; }
module_list=()
list_initrd
for driver in 'sdhci-of-arasan' 'dw_mmc-rockchip' 'phy-rockchip-emmc' 'io-domain' 'rk8xx-i2c' 'rk808-regulator' 'i2c-rk3x' 'mmc_block' 'ext4'; do
    case $driver in
      sdhci-of-arasan) option=MMC_SDHCI_OF_ARASAN ;;
      dw_mmc-rockchip) option=MMC_DW_ROCKCHIP ;;
      phy-rockchip-emmc) option=PHY_ROCKCHIP_EMMC ;;
      io-domain) option=ROCKCHIP_IODOMAIN ;;
      rk8xx-i2c) option=MFD_RK8XX_I2C ;;
      rk808-regulator) option=REGULATOR_RK808 ;;
      i2c-rk3x) option=I2C_RK3X ;;
      mmc_block) option=MMC_BLOCK ;;
      ext4) option=EXT4_FS ;;
    esac
    if ! grep -qx "CONFIG_${option}=y" "$root/boot/config-$release"; then
      grep -qx "CONFIG_${option}=m" "$root/boot/config-$release"
      module_list+=("$driver")
    fi
done
regenerate=0
grep -q '/fsck.ext4$' /build/records/initramfs.list || regenerate=1
for driver in "${module_list[@]}"; do
  if ! grep -q "/${driver}\\.ko" /build/records/initramfs.list; then
    grep -Fqx "$driver" "$root/etc/initramfs-tools/modules" || printf '%s\n' "$driver" >> "$root/etc/initramfs-tools/modules"
    regenerate=1
  fi
done
if (( regenerate )); then
  chroot "$root" update-initramfs -u -k "$release"
  list_initrd
fi
grep -q '/fsck.ext4$' /build/records/initramfs.list
for driver in "${module_list[@]}"; do
  grep -q "/${driver}\\.ko" /build/records/initramfs.list
done
if awk -F: '$3 >= 1000 && $3 < 65534 { found=1 } END { exit !found }' "$root/etc/passwd"; then
  printf 'Unexpected regular user in image\n' >&2; exit 1
fi
awk -F: '$1 == "root" && $2 ~ /^[!*]/ { good=1 } END { exit !good }' "$root/etc/shadow"
# Reset values and keys specific to the container used to build this rootfs.
find "$root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete
for path in etc/resolv.conf etc/machine-id var/lib/dbus/machine-id \
  usr/bin/qemu-aarch64-static usr/sbin/policy-rc.d etc/apt/apt.conf.d/90firefly-build \
  root/.bash_history var/lib/systemd/random-seed; do
  if [[ -e $root/$path || -L $root/$path ]]; then unlink "$root/$path"; fi
done
ln -s /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
install -m 0444 /dev/null "$root/etc/machine-id"
install -d "$root/var/lib/dbus"
ln -s /etc/machine-id "$root/var/lib/dbus/machine-id"
find "$root/var/lib/apt/lists" -type f -delete
find "$root/var/cache/apt/archives" -type f \( -name '*.deb' -o -name '*.prefetch' \) -delete
find "$root/var/log" -type f -exec truncate -s0 {} +
printf '%s\n' "$release" > /build/records/kernel-release.txt
printf 'Ubuntu ARM64 rootfs, GNOME initial setup, and Firefly MMC boot drivers are ready (%s).\n' "$release"
