# RK3399 发布物稳压器审计 · 2026-11-20

现场基线为原版 Firefly-RK3399 **DDR3，Rev 1.0，2 GiB**。下文 `CPU/GPU` 指按供电 phandle 对应到 I²C `0x40`（SYR827）/ `0x41`（SYR828）的 `fcs,suspend-voltage-selector`。`off/off` 表示两路都设有 `regulator-state-mem/regulator-off-in-suspend`。先确认实际启动文件，再比较驱动和接线。审计范围是此工作区、服务器上保留的构建物以及该账户对应的 Firefly GitHub 项目。

| 系统、板型 | 内核 / 介质 / 实际 DTB | CPU/GPU；休眠 | 证据与结论 |
| --- | --- | --- | --- |
| Ubuntu 22.04.5 GNOME test1，原版 DDR3 Rev 1.0 2 GiB | 6.8.0-149-generic，fan53555；eMMC；extlinux `/boot/firefly/6.8.0-149-generic/rk3399-firefly.dtb` | `0/1`；off/off | **实板复现/修复**：旧盘 7 GiB 全量回读吻合；单独加载 fan53555 复现。板主改启动 DTB 与相同内核的固件原件后，`1/1` 到达串口登录和 HDMI GNOME。见[复盘](vsel.md)。 |
| Ubuntu test1，原版 DDR3 | 同一内核；TF；同一 extlinux DTB | `0/1`；off/off | **产物有同样配置但未实测**：TF 和 eMMC 的原版 DTB 字节一致，均与 Ubuntu 内核模块包原件相符。 |
| [Ubuntu VSEL1 test2](https://github.com/hehuang139/ubuntu-firefly-rk3399/releases/tag/v22.04.5-vsel1-test2)，原版 DDR3 | 6.8.0-149-generic；TF/eMMC；两种介质最终 extlinux、固件目录副本和内核更新钩子 | `1/1`；off/off | **无此配置/不适用**（错误已修正）：两份媒体 DTB 与现场启动成功的修订 DTB 字节一致。全盘分区读回；用升级夹具验证真正的安装和 initramfs 钩子。新 eMMC 整盘在 2 GiB QEMU 进串口，实板的实测对象为修订过的 test1 eMMC。 |
| [OpenWrt 25.12.6 test1](https://github.com/hehuang139/openwrt-firefly-rk3399/releases/tag/v25.12.6-firefly-test1)，原版 DDR3 | 6.12.112，`CONFIG_REGULATOR_FAN53555=y`；TF/eMMC、两种 sysupgrade；p1 `/boot.scr` → `bootm /kernel.img` → 默认 `config-1/fdt-1` | `0/1`；off/off | **产物有同样配置但未实测**：四个文件 SHA 与 GitHub 一致，从产物核对 FIT 哈希、默认配置和节点；Linux DTB `6c49750c84089def462b8d01479eae9789277941d05c5a8fb49b5cd3cc62ea40`。 |
| [OpenWrt VSEL1 test2](https://github.com/hehuang139/openwrt-firefly-rk3399/releases/tag/v25.12.6-firefly-vsel1-test2)，原版 DDR3 | 同一内核；两种工厂镜像和两种 sysupgrade，走同一 FIT 入口 | `1/1`；off/off | **无此配置/不适用**（错误已修正）：重新离线构建，四份产物通过成品检查；旧 TF 用同一检查器被判为 CPU bank 0。Linux DTB `f7491b136b13f57315263b9393595046df08d7d3ca00220644d77c1342a00178`。 |
| [Batocera 43.1 test1](https://github.com/hehuang139/batocera-firefly-rk3399/releases/tag/v43.1-firefly-emmc-test1)，原版 DDR3 | Linux 6.6.27 与其模块取自 Batocera 40 RockPro64 基座，`CONFIG_REGULATOR_FAN53555=y`；43.1 用户态；直刷 eMMC、TF 安装卡、TF 内嵌 eMMC。extlinux `/boot/rk3399-firefly-batocera-emmc.dtb`（eMMC `mmcblk2p1`，TF `mmcblk1p1`） | `0/1`；off/off | **产物有同样配置但未实测**：检查发布件 FAT 中的 DTB（`136f55b02480b046bb1d76f6757a46614bb81e5c975ee25ba273062e0a199598`）；发布验证还逐字节对比了 TF 内置与外部 eMMC gzip 和整盘。 |
| Batocera 43.1 eMMC 直刷替代件，原版 DDR3 | 6.6.27，直刷 eMMC；同一 extlinux 路径和原启动器 | `1/1`；off/off | **无此配置/不适用**（错误已修正）：从已核对的原版分卷生成，FAT 读回已修正 DTB，两个整盘对比只差偏移 `427277359` 的一字节。新整盘 SHA-256 `92a916225d2b9239f0ca8e4570c316b55a914332f52c2cefa76dd36f370dc598`。见[修复 PR](https://github.com/hehuang139/batocera-firefly-rk3399/pull/1)。原 TF 安装卡不可作为替代。 |
| Batocera 40 TF test1，原版 DDR3 | 6.6.27，内建 fan53555；TF；extlinux `/boot/rk3399-firefly-batocera-sd.dtb` | `0/1`；off/off | **产物有同样配置但未实测**（编译 DTB，旧整盘未取回）：固定 boot-assets DTB `72b0af6f24ebec0334888b5e6b223390fddb657abe23fb13e1a7cd39314b6446`。 |
| Batocera 40 eMMC test1 / Select 热键 test2，原版 DDR3 | 同一内核；直刷 eMMC、TF 安装卡和其中内嵌 eMMC。固定来源为 `source/emmc/boot-assets` 与 `source/emmc/installer-assets`，Select 版复用这条链 | `0/1`；off/off | **产物有同样配置但未实测**（编译 DTB，旧整盘未取回）：与 43.1 使用同一 eMMC DTB 哈希。 |
| Android TV 17 eMMC 候选记录，标识原版 Firefly-RK3399，硬件版本未证实 | 记录未提供可追到内核的镜像、启动文件及 `boot`/`resource`/FIT 选择链 | 台账 `0/1`；off/off | **缺少产物或证据待查**：只有工作区电源审计表和 DTB 摘要 `63fcdbad6b63735634c7b253f636bf026d48f5bc957171f7d7a646a0a29b6dff`，未定位到对应二进制、内核或发布链接。不能从该记录推定实板故障。 |
| 当贝桌面 / Android TV 应用集成 | Android TV 7.1 x86 模拟器，没有 Firefly DTB；待选 Android eMMC 基座 | — | **无此配置/不适用**（模拟器和 APK）；**缺少产物或证据待查**（成品）。当贝 5.0.1 通过安装、首启、D-pad；硬解检测工具用模拟器的软件 AVC/HEVC 解码跑完样本。没有可刷的电视整盘。 |
| Firefly 官方 Android 8.1 SDK，原版 `rk3399_firefly_mid`（外部参考） | 4.4.126，内建 fan53555；文档编译 `rk3399-firefly.img`，交付 DTB 位于 `resource.img`；本次从固定提交编译 `rk3399-firefly.dts` | `1/1`；off/off | **无此配置/不适用**（SDK 参考 DTB），用实际编译的 DTB 回读 phandle 和 selector；**缺少产物或证据待查**（出厂烧录包）。供应商 DTS 还定义了 `vsel-gpios`，与主线绑定有差别。 |
| Firefly 官方 Android 7.1 Box/Industry 及其他厂商固件（外部参考） | 下载页有旧 7.1 项；未拿到可核验的 `update.img`、选中 DTB 或准确驱动版本 | — | **缺少产物或证据待查**；不从 8.1 源码反推 7.1。 |
| Firefly RK3399 QEMU 与通用 ARM64 virt | Ubuntu 6.8、OpenWrt 6.12；模型直接启动外部 DTB，或使用 `virt` 生成树；模拟 eMMC/虚拟磁盘 | 无这两颗稳压器 | **无此配置/不适用**：CPU、根分区、服务和桌面可测，不能测本板电气接线。 |
| Ubuntu、OpenWrt、Batocera 的 U-Boot 控制树 | DDR3 引导件 U-Boot 2025.10（Ubuntu/OpenWrt）、2024.01（Batocera）；TF 与 eMMC；二者都和 Linux 选中的树独立 | `0/1`；off/off | **无此配置/不适用**（Linux 注册时故障）：从 U-Boot DTB/FIT 验证；构建配置均未开启 `CONFIG_DM_PMIC_FAN53555`，没有复用这里的控制树当 Linux DTB。 |
| RK3288 Android 17/电视、Ubuntu 和 Batocera | 不同 SoC，属于另一个构建目标 | — | **无此配置/不适用**。 |

Linux [6.6.27](https://github.com/gregkh/linux/blob/v6.6.27/drivers/regulator/of_regulator.c#L305-L318) 和 [6.12.112](https://github.com/gregkh/linux/blob/v6.12.112/drivers/regulator/of_regulator.c#L314-L328) 的绑定都把 `regulator-state-mem` 设为初始状态，注册约束可调用对应内核的 `fan53555_set_suspend_disable`，清除被选择的休眠寄存器的 BUCK_EN。该机制和现场电平使 40/43.1 与 OpenWrt 的原版 DTB 值需要处理；现场故障只在 Ubuntu 复现过。休眠和唤醒要作为独立板测项目。

Firefly Android 来源：[8.1 构建文档](https://community.t-firefly.com/en/docs/products/motherboard/Firefly-RK3399/compile-android8-1-firmware) · [固定 4.4.126 板级源码](https://gitlab.com/TeeFirefly/firenow-oreo-rk3399/-/blob/7068beb623481797a8d9ecba8f1eca99c3b6b8f6/kernel/arch/arm64/boot/dts/rockchip/rk3399-firefly-core.dtsi) · [7.1 下载列表](https://community.t-firefly.com/en/doc/download/3)。

其他 DDR/PCB 修订、ROC-RK3399、Core-3399、通用 RK3399 和厂商机顶盒不是本项目的目标。上游发行版自有镜像及其其他板型不在本服务器维护范围；要分别按原理图、已选 DTB 与该内核驱动解析。
