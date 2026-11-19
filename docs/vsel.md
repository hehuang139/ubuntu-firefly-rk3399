# 原版 Firefly-RK3399 DDR3 Rev 1.0 启动修复

现场板为 2 GiB DDR3，Linux 版本 `6.8.0-149-generic`。烧录的 test1 eMMC 整盘（7 GiB）回读 SHA-256 `4e234a878f5a48c0f349d63e5590a9887bf739ba1b5c0e960224771255baeb50` 与发布文件解压后相同。启动约 8.6 秒时，I²C 上两颗稳压器报告 `Detected!` 后停止。在 initramfs 可以单独挂载 eMMC；禁用 CPU 调频并且不加载 RK808、图形和 PCIe 驱动时，单独加载 fan53555 仍复现。

## 两个不同的环节

- **配置来源。** Linux [首次加入该板的提交（2017）](https://github.com/torvalds/linux/blob/171582e00db1d2dc1ca98ba6b3bd58e0cef20aea/arch/arm64/boot/dts/rockchip/rk3399-firefly.dts#L436-L468) 已写入 CPU `0x40` 为 0、GPU `0x41` 为 1，并给两路加了 `regulator-off-in-suspend`。[v6.8](https://github.com/torvalds/linux/blob/v6.8/arch/arm64/boot/dts/rockchip/rk3399-firefly.dts#L504-L535) 仍如此。测试时再次下载并解包 Ubuntu ARM64 的 `linux-modules-6.8.0-149-generic` `6.8.0-149.149~22.04.1`，其源包为 `linux-hwe-6.8`。该 DEB 的 SHA-256 为 `a1772abaa44146530264995f2236f336e1d29b80ac2e20ca0cbf6b02063591e7`。包内 `/lib/firmware/6.8.0-149-generic/device-tree/rockchip/rk3399-firefly.dtb` 与 test1 两种介质的 DTB 哈希一致：`10689de9a3d85bf59f94ce325f0c5c9d2781d2cd51af483515b315012f4f0ca8`。
- **编入镜像。** 当时 `scripts/assemble.sh` 执行 `firefly-update-boot`，后者原样复制包里的 DTB 到 `/boot/firefly/6.8.0-149-generic/rk3399-firefly.dtb`，并在 `/boot/extlinux/extlinux.conf` 的 `FDT` 指向它。板上的 U-Boot 控制树与 Linux 通过该 `FDT` 加载的树是两份文件。测试版的内核更新也会走同一个复制流程。
- **未挡住故障。** 当时的 `verify.py` 验证了分区回读、extlinux、内核、initrd、DTB 魔数和板型 compatible，没有检查 CPU/GPU 电源节点。2 GiB QEMU 冒烟直接用外部模型 DTB 启动 Linux；GNOME 验证用 4 GiB ARM64 `virt` 及 virtio-gpu。两者都没有本板的两颗电源芯片和 VSEL 接线。见 [test1 的验证记录](../records/boot-validation.txt)。

## 板上机制与修复结果

Rev 1.0 原理图第 14 页和 GPIO 测量对照：`CPU_B_SLEEP_H`（GPIO1_C2）和 `GPU_SLEEP_H`（GPIO1_B6）在运行时均为低电平，两颗芯片使用 VSEL0。Linux [读取休眠配置](https://github.com/torvalds/linux/blob/v6.8/drivers/regulator/of_regulator.c#L323-L324)，并在[注册时应用初始约束](https://github.com/torvalds/linux/blob/v6.8/drivers/regulator/core.c#L1489-L1492)；[fan53555 按选择器指定休眠寄存器](https://github.com/torvalds/linux/blob/v6.8/drivers/regulator/fan53555.c#L442-L455)，休眠禁用操作会[清除该寄存器的 BUCK_EN](https://github.com/torvalds/linux/blob/v6.8/drivers/regulator/fan53555.c#L182-L188)。旧配置因此在注册时把 CPU 当前供电关掉。

现场只把 `0x40` 的 selector 从 0 改为 1；`0x41` 仍为 1，两颗芯片的休眠关闭子节点保持原样。相同内核、相同启动参数下，两路稳压器完成绑定，两组 CPU 调频建立，6 核在线；9.430203 秒挂载 eMMC 根分区，串口出现登录提示，HDMI 进入 GNOME。现场修订后的 DTB SHA-256 为 `7ce435751d1b2cb337301edfe991e2af012a0b38870048177092521f03664e97`。测试覆盖了冷启动，休眠唤醒尚待板测。

## test2 构建、回归和迁移

- 两种介质从同一 Ubuntu 22.04.5 暂存根文件系统重新组装。检查从整盘回读 ext4，逐条解析 extlinux 的 `FDT` 和固件原件，比对两者，并验证两路 regulator、供电 phandle、selector `1/1` 和原有的 suspend-off；两种介质中的 DTB 都与现场冷启动验证的 DTB 字节一致。
- `scripts/test-vsel-update.sh` 以原包 DTB 和两种介质的 PARTUUID，对真实 kernel postinst 和 initramfs post-update 钩子执行升级夹具：未齐全的启动文件不会覆盖菜单；完整文件可生成修正后的首选项和回退项；改变稳压器定义时拒绝覆盖旧菜单。脚本用法见其头部。
- 有数据且能启动的 test1 安装可先备份 `/boot/extlinux`、`/boot/firefly` 和当前内核的固件 DTB，再从本项目检出与发布匹配的版本，在**目标 Firefly-RK3399 的 Ubuntu 系统里**执行：

  ```sh
  sudo install -D -m 0644 overlay/usr/local/lib/firefly-dtb.py /usr/local/lib/firefly-dtb.py
  sudo install -D -m 0755 overlay/usr/local/sbin/firefly-update-boot /usr/local/sbin/firefly-update-boot
  sudo /usr/local/sbin/firefly-update-boot "$(uname -r)"
  python3 /usr/local/lib/firefly-dtb.py check "/boot/firefly/$(uname -r)/rk3399-firefly.dtb"
  ```

  如果还安装了其他新版内核，对每个已完整安装的内核版本再运行一次更新脚本。确认 extlinux 的启动项指向通过检查的 DTB，再重启。若 test1 无法启动，从 test2 TF 卡启动，备份旧 eMMC 后按 README 处理。
