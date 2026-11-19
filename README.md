# Firefly RK3399 · Ubuntu 22.04 LTS GNOME

适用于**原版 Firefly-RK3399 DDR3**。系统为 Ubuntu 22.04.5 ARM64，带 GNOME、中文界面、文件管理器、终端、浏览器、文档查看器、计算器和系统工具。镜像内的 Firefly 设备树取自 Ubuntu 的 6.8 HWE ARM64 内核包，组装和内核更新时修正本板的 CPU 大核稳压器休眠 bank。引导件使用本型号的原生 U-Boot 2025.10 和 TF-A 2.13，适配 TF 和 eMMC 两种启动介质。

## 镜像与首启

从 [v22.04.5-vsel1-test2](https://github.com/hehuang139/ubuntu-firefly-rk3399/releases/tag/v22.04.5-vsel1-test2) 下载。`*-sd-vsel1-test2.img.gz` 写入 TF 卡，`*-emmc-vsel1-test2.img.gz` 写入 eMMC 用户区。旧 test1 的两版镜像都含有错误的 CPU 休眠 bank；请改用 test2。详见[故障复盘与内核更新测试](docs/vsel.md)。两者都是 raw 镜像，单份解压后为 7 GiB。先用容量 16 GB 或更大的 TF 卡验证 HDMI 和基本外设，再考虑覆盖原 eMMC。eMMC 容量必须大于等于 7 GiB；写入前备份原系统。镜像包含分区表和启动区，不能写到 eMMC 上的某一个分区，不能当成 Rockchip 的 `update.img`。

1. 在下载文件所在目录核验压缩镜像：`grep '\.gz$' SHA256SUMS.vsel1-test2 | sha256sum --ignore-missing -c -`。
2. 用支持 gzip 的镜像工具（如 balenaEtcher）把 `sd` 版写到 TF，等待读回校验。断电，先接 HDMI 和 USB 键鼠，再插卡开机。
3. 在 GNOME 首次设置中创建自己的账号、密码。镜像中没有预设的可登录用户；root 被锁定，SSH 默认关闭。以后如需 SSH，在桌面终端运行 `sudo systemctl enable --now ssh`，用 `hostname -I` 找到当前 IP，再用自己建立的用户登录。
4. 验证画面、USB、网线和音频后，再按下文安装 eMMC。

板上 UART2 的参数是 `1500000 8N1`，仅使用 3.3 V 电平的 USB 转 TTL，接 GND/RX/TX，不接 VCC。若 HDMI 没画面，串口有助于分清引导、内核和图形启动阶段。

## 从 TF 安装到 eMMC

在已从 TF 启动的 Ubuntu 上，用 `findmnt -no SOURCE /` 和 `lsblk -o PATH,SIZE,TYPE,MOUNTPOINTS` 核对当前根分区和目标盘。逐个查看 `/sys/block/mmcblk*/device/type`，并通过 `readlink -f /sys/block/mmcblkN` 确认 eMMC 为 `MMC`、设备路径经过 `fe330000`；TF 则为 `SD`、路径经过 `fe320000`。实际编号以 sysfs 为准。不要选择 TF、eMMC 的子分区或 `mmcblkNboot0/1`。

把 `emmc` 版解压到空间足够的外置存储。先备份原 eMMC，卸载其分区并关闭上面的 swap。打开 GNOME「磁盘」，选中前面确认的 eMMC 整盘，打开右上角菜单，选择「恢复磁盘镜像」，再选解压后的 `.img` 文件。如果工具不会清理旧分区表，在写新镜像前先清理**已确认的 eMMC** 上残留的 GPT 主、备表；7 GiB 镜像可能不覆盖物理盘最后几个扇区。写后读回镜像覆盖的 7 GiB，对比 `SHA256SUMS.vsel1-test2` 中 `.img` 对应的 SHA256。关机断电，取出 TF，再测试 eMMC。保持 TF 作为恢复介质。不要复用 OpenWrt 专用安装器。

## 构建与验证

```sh
docker build -t firefly-ubuntu22-builder:local .
FIREFLY_BUILDER=firefly-ubuntu22-builder:local ./rebuild.sh all
```

可单独执行 `fetch`、`rootfs`、`finalize`、`image`、`compress`。`bootloader/` 使用早先 Firefly RK3399 OpenWrt 项目的分介质引导产物；`upstream-manifest.json` 记录了源版本、源包 SHA256 及对应引导件 SHA256。Ubuntu Base 由 Ubuntu CD Image 的签名验证，APT 从 Ubuntu ARM64 仓库获取签名索引。`records/packages.tsv` 记录本次安装的包版本。重跑时若 APT 仓库有更新，包版本会随仓库变化。

约定的布局是 MBR、LBA 64 引导件和 LBA 32768 起的 ext4 根分区。两种介质使用不同的 PARTUUID。首启会在后台确认根分区及分区表，并尝试用剩余容量扩展；内核更新时同步刷新 extlinux 启动菜单。组装脚本在普通文件上验证扇区、引导件、分区 SHA256、ext4、内核、initrd 和设备树。

`scripts/qemu-smoke.py` 在已有 Firefly RK3399 QEMU 模型上用整盘镜像验证虚拟 eMMC、ARM64 内核及 Ubuntu 启动。它使用模拟设备树直接启动 Linux，实板仍要通过 HDMI、eMMC 引导、以太网及外设的首板检查。

test1 的验证记录见 `records/boot-validation.txt`：该版 eMMC 镜像在 Firefly QEMU 模型中到达多用户目标和串口登录；在通用 ARM64 QEMU（4 GiB、VirtIO 显卡）中，中文 GNOME 欢迎页打开，并可进入键盘布局设置。
