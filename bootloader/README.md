# RK3399 bootloader provenance

The two `u-boot-rockchip.bin` files are from the Firefly-RK3399 DDR3 native boot builds in the `openwrt-firefly-rk3399` project ([`source/boot`, Git commit `f486575`](https://github.com/hehuang139/openwrt-firefly-rk3399/tree/f486575d9b4ffb8be310487e8c123b569d03af00/source/boot)). `upstream-manifest.json` pins the source versions, archives and final hashes, and captures the DDR3 and boot policy changes. Use `source/boot/rebuild.sh` from that project to reproduce the binaries. The OpenWrt kernel, rootfs, and boot script are not part of these binaries.

U-Boot 2025.10 is licensed GPL-2.0-or-later and includes components under their file-specific licenses. Trusted Firmware-A 2.13 uses BSD-3-Clause and file-specific terms. Ubuntu archive components retain their upstream terms; the package manifest identifies the actual versions in the image.
