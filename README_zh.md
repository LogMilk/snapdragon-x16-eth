# Surface LTE Switch

> [English](README.md) · **中文**

一个**自包含**的 Android 应用，让 **Surface Go 2（及同模组的 Surface 设备）** 的
**Qualcomm Snapdragon X16 LTE 调制解调器** 在 **Android-x86 / BlissOS** 上可用
—— 这类系统**没有 RIL**，也就没有"移动数据"。

它把调制解调器以 Android **以太网**的形式呈现，并提供**快捷设置磁贴**与一个信息界面，
用于在 **LTE / Wi‑Fi** 之间切换。

> 测试环境：Surface Go 2 LTE + BlissOS（Android 13，内核 `6.1.x-gloria-surface`），
> 使用 KernelSU root。

---

## 功能

- **快捷设置磁贴**：点按开关 LTE；开启时磁贴标题显示**信号百分比**，副标题显示
  RSRP / RSRQ / SNR / 运营商。
- **信息与控制界面**（Material‑You 风格）：
  - 是否拥有 **root**，
  - 调制解调器 / MBIM 控制节点 / 数据网卡 / 以太网接口，
  - Wi‑Fi、默认接口、WLAN 与 WWAN 地址、当前 APN，
  - 信号与注册状态，
  - **APN** 输入框，以及"改可达校验地址"开关。
- **自包含**：内置 `qmicli`、`mbim-proxy`、glibc 加载器与所需库，首次使用自动解包并以 root 运行：
  **不需要 Termux / proot / KernelSU 模块**。
- **自动发现**：按 USB VID:PID（`045e:09a5`）找到调制解调器，定位对应的 `/dev/cdc-wdmX`
  与 `cdc_ncm` 数据网卡，并自动选择空闲的 `ethN` 名称。
- **APN 可配置**（默认 `ctlte`，中国电信）。
- **中英双语界面**（默认英文；非中文系统回退英文）。

---

## 运行要求

| | |
|---|---|
| 设备 | 搭载 **Qualcomm Snapdragon X16** 调制解调器的 Surface（Surface Go 2 LTE、Surface Go 1 LTE、Surface Pro 2017 LTE 等） |
| 系统 | **Android-x86 / BlissOS**，**无 RIL**（`ro.radio.noril=yes`），**x86_64** |
| 内核 | 需要 `cdc_mbim` / `cdc_ncm` / `cdc_wdm` 与网络命名空间（netns） |
| Root | **KernelSU**（或等价 root）—— **默认权限配置即可** |
| SIM | 可用的 SIM 卡 —— 注意该调制解调器可能默认使用 **eSIM**，请确认目标 SIM 是"当前激活"的那张 |

### Root / KernelSU

因为所有工具都**打包在 App 内**，KernelSU 的**默认 App Profile 即可运行**，无需额外 capability，
只要给该应用 root 权限即可。

> 若你用了会剥离 capability 的加固配置且出现失败，额外授予下面这些也可以：
> `CAP_DAC_OVERRIDE`、`CAP_DAC_READ_SEARCH`、`CAP_NET_ADMIN`、`CAP_NET_RAW`、
> `CAP_SYS_ADMIN`、`CAP_SETUID`、`CAP_SETGID`、`CAP_CHOWN`、`CAP_FOWNER`、`CAP_KILL`
> （或直接放开"全部能力"）。

---

## 原理

BlissOS/Android-x86 带 `ro.radio.noril=yes`，Android 电话栈完全不碰这个调制解调器。本应用直接驱动它：

1. **QMI over MBIM**：用内置的 `qmicli`（glibc 二进制，经内置 glibc 加载器执行，**无需 proot**）
   访问 `/dev/cdc-wdm0`：
   - `--dms-set-operating-mode=online`（否则调制解调器停在 `shutting-down`），
   - `--wds-start-network=apn=<APN>,ip-type=4` 激活 PDP，
   - `--wds-get-current-settings` 读取运营商分配的 IP / 网关 / DNS，
   - `--nas-get-signal-info` / `--nas-get-serving-system` 供磁贴显示。
2. **`cdc_ncm` 缓冲修复**：打开控制通道前先写入驱动 NTB 缓冲大小（`rx_max`/`tx_max` = 16383 → 16384）；
   不做这一步，调制解调器的 MBIM 控制口会不应答。
3. **呈现为以太网**：把数据网卡改名为 `eth0`（用网络命名空间往返触发 Android `EthernetTracker`
   注册为**新**接口），并通过隐藏 API `EthernetManager.setConfiguration()` 下发**静态
   `IpConfiguration`**（见 `assets/lte/ethcli.jar`）。之后 Android 把它当作普通**以太网**，应用即可使用。
4. **Wi‑Fi ↔ LTE**：本平台以太网与 Wi‑Fi 不共用上行，所以开启 LTE 会关闭 Wi‑Fi
   （`cmd wifi set-wifi-enabled disabled`），关闭 LTE 会恢复 Wi‑Fi。

App 首次使用时把内置工具从 `assets/` 解包到私有目录，再以 root 运行。

---

## 安装

1. 从本仓库的 **Releases** 页面下载 APK 并安装。
2. 在 **KernelSU → 超级用户** 中允许 **LTE Switch**（`com.logmilk.lteswitch`）获取 root。
3. **设置 → 快捷设置 → 编辑**，把 **LTE** 磁贴拖入面板。
4. 打开一次 **LTE Switch** 查看状态并设置 **APN**。

## 使用

- **磁贴**：点按开关。开启时标题显示 `LTE 78%`（由 RSRP 换算；−140 dBm = 0%，−70 dBm = 100%）。
- **App**：
  - 「**启用 LTE**」开关：开/关 LTE；
  - **APN**：填入运营商 APN，点「保存 APN」；
  - *把系统校验地址改为国内可达*：可选；让 Android 的连通性校验走国内可达端点（避免 Google
    被墙时出现"无网络"误报）；
  - **刷新信息**：刷新全部信息。

---

## 从源码构建

直接用 Android SDK build‑tools 构建（不需要 Gradle）：

需要 JDK 11+ 与 Android SDK build-tools。`build.bat` 以自身所在目录定位项目，并自动探测
SDK / JDK；可用 `ANDROID_HOME`、`JAVA_HOME`、`BUILD_TOOLS`、`ANDROID_JAR` 覆盖。

```
build.bat        # aapt2 → javac → d8 → zipalign → apksigner → lteswitch.apk
```

目录结构：

```
AndroidManifest.xml
assets/
  lte/lte-ctl.sh          # root 控制脚本
  lte/ethcli.jar          # 调用隐藏 EthernetManager 的 root 辅助
  qmi/                    # ld-linux + qmicli + mbim-proxy + 依赖库
res/values/strings.xml    # 英文（默认）
res/values-zh[-rCN]/…     # 中文
src/com/logmilk/lteswitch/{MainActivity,LteTile,Extract}.java
```

`assets/qmi/` 取自一个 Debian rootfs：从 `libqmi-utils` / `libmbim-utils` 包里取出
`ld-linux-x86-64.so.2`、`libqmi-glib`、`libmbim-glib`、`libglib-2.0`、`libgio-2.0`、
`libgobject-2.0`、`libgmodule-2.0`、`libqrtr-glib`、`libc`、`libpcre2-8`、`libz`、`libm`、
`libmount`、`libselinux`、`libffi`、`libblkid`、`qmicli`、`mbim-proxy`。

---

## 常见问题

**磁贴显示"解包失败"/点了没反应**
确认 App 已获得 root，然后重开一次磁贴（首次点按会解包约 13 MB）。

**`ERR: no IPv4 from modem` / LTE 没有网络**
QMI 会话失效或卡死。脚本会自动重枚举调制解调器并重试；仍失败就关/开一次 LTE。
若出现"有 IP 但没数据"的失效会话，脚本会用 ping 检测并自动重建。

**数据可用但 Android 仍显示"无网络"**
因为 Google 的探测端点被墙，网络只被判为 *partial*。在 App 里打开
*把系统校验地址改为国内可达* 即可。

**开启 LTE 后 Wi‑Fi 断了 —— 正常现象**
本平台以太网与 Wi‑Fi 不共用上行。再关掉 LTE 就会恢复 Wi‑Fi。

---

## 限制

- 仅适用于搭载该 **Qualcomm Snapdragon X16** 调制解调器、且为 **x86_64** 的 Android‑x86/BlissOS
  （无 RIL）系统。其它 ROM/ABI 需要移植。
- 需要 **root**（KernelSU）。
- 内置的 `qmicli` / `mbim-proxy` 是 **x86_64 glibc** 二进制，通过随附的 glibc 加载器运行。

---

## 致谢与参考

- [linux-surface – Surface Go 2 wiki](https://github.com/linux-surface/linux-surface/wiki/Surface-Go-2)
- [linux-surface issue #306 – LTE/4G/mobile support](https://github.com/jakeday/linux-surface/issues/306)
  （`cdc_ncm` 缓冲大小修复）
- [kepi.cz – Surface Go 2 and LTE modem](https://kepi.cz/surface-go-2-lte-modem)

## 许可

本应用自身源码采用 **MIT License** 发布（见 `LICENSE`）。

> **关于内置二进制**：`assets/qmi/` 包含来自 **libqmi** 与 **libmbim** 的 `qmicli`、`mbim-proxy`
> 及其依赖（LGPL‑2.1+ / GPL‑2.0+），以及 **glibc** 的加载器与运行库（LGPL‑2.1+）。
> 分发 APK 时请遵守相应许可（附上协议文本 / 按要求提供源码）。
