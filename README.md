# Surface LTE Switch

> **English** · [中文](README_zh.md)
<!-- 上传到 GitHub 后，可把上面的 README_zh.md 换成完整 URL（例如 .../blob/main/README_zh.md）。 -->

A self-contained Android app that brings the **Qualcomm Snapdragon X16 LTE modem** on a
**Surface Go 2 (and related Surface devices)** to life on **Android-x86 / BlissOS**, where
Android has **no RIL** and therefore no "mobile data" to speak of.

It presents the modem to Android as a regular **Ethernet network** and gives you a
**Quick Settings tile** and a small info screen to switch between **LTE** and **Wi‑Fi**.

> Tested on a Surface Go 2 LTE running BlissOS (Android 13,
> kernel `6.1.x-gloria-surface`), rooted with KernelSU.

---

## Features

- **Quick Settings tile** – tap to enable/disable LTE; while on, the tile label shows the
  live **signal percentage** and the subtitle shows RSRP / RSRQ / SNR / operator.
- **Info & control app** – Material‑You‑ish screen showing:
  - whether **root** is available,
  - modem / MBIM control node / data netdev / Ethernet interface,
  - Wi‑Fi, default route, WLAN & WWAN addresses, current APN,
  - signal & registration,
  - an **APN** field, and a toggle for the connectivity‑check workaround.
- **Self-contained** – bundles its own `qmicli`, `mbim-proxy`, a glibc loader and the
  required libraries, extracts them on first use and runs them as root:
  **no Termux, no proot, no KernelSU module**.
- **Auto-discovery** – finds the modem by USB VID:PID (`045e:09a5`), locates the matching
  `/dev/cdc-wdmX` and the `cdc_ncm` data netdev, and picks a free `ethN` name.
- **Configurable APN** (default `ctlte`, China Telecom).
- **English / Chinese** UI (English is the default; any non‑Chinese locale falls back to English).

---

## Requirements

| | |
|---|---|
| Device | Surface with the **Qualcomm Snapdragon X16** LTE modem (Surface Go 2 LTE, Surface Go 1 LTE, Surface Pro 2017 LTE, …) |
| OS | **Android-x86 / BlissOS** built **without RIL** (`ro.radio.noril=yes`), **x86_64** |
| Kernel | must provide `cdc_mbim` / `cdc_ncm` / `cdc_wdm` and network namespaces |
| Root | **KernelSU** (or compatible root) — the **default permission profile is enough** |
| SIM | a working SIM — note the modem may default to the **eSIM**; make sure the SIM you want is the active one |

### Root / KernelSU

Because every tool is **bundled inside the app**, KernelSU's **default App Profile works
as‑is** — no extra capabilities are needed. Just allow the app root access.

> If you use a hardened profile that drops capabilities and something fails, granting the
> list below also works:
> `CAP_DAC_OVERRIDE`, `CAP_DAC_READ_SEARCH`, `CAP_NET_ADMIN`, `CAP_NET_RAW`,
> `CAP_SYS_ADMIN`, `CAP_SETUID`, `CAP_SETGID`, `CAP_CHOWN`, `CAP_FOWNER`, `CAP_KILL`
> (or simply allow all capabilities).

---

## How it works

BlissOS/Android-x86 ships with `ro.radio.noril=yes`, so Android's telephony stack never
touches the modem. This app drives it directly:

1. **QMI over MBIM** – talks to `/dev/cdc-wdm0` using a bundled `qmicli`
   (a glibc binary executed through a bundled glibc loader — no proot required):
   - `--dms-set-operating-mode=online` (the modem otherwise sits in `shutting-down`),
   - `--wds-start-network=apn=<APN>,ip-type=4` to activate the PDP context,
   - `--wds-get-current-settings` to read the carrier IP / gateway / DNS,
   - `--nas-get-signal-info` / `--nas-get-serving-system` for the tile.
2. **`cdc_ncm` buffer quirk** – before opening the control channel the driver's NTB
   buffer sizes are written (`rx_max`/`tx_max` = 16383 → 16384); without this the modem's
   MBIM control interface refuses to answer.
3. **Expose as Ethernet** – the data netdev is renamed to `eth0` (via a network-namespace
   round-trip so Android's `EthernetTracker` registers a *new* interface) and a **static
   `IpConfiguration`** is pushed to the framework through the hidden
   `EthernetManager.setConfiguration()` API (see `assets/lte/ethcli.jar`). Android then
   treats it as a normal **Ethernet** network and apps can use it.
4. **Wi‑Fi ↔ LTE** – on this platform Ethernet and Wi‑Fi don't share the uplink, so
   enabling LTE disables Wi‑Fi (`cmd wifi set-wifi-enabled disabled`) and disabling LTE
   restores Wi‑Fi.

The app extracts its bundled tools from `assets/` into its private directory on first use
and runs them as root.

---

## Install

1. Download the APK from the **Releases** page of this repository and install it.
2. In **KernelSU → Superuser**, allow root for **LTE Switch** (`com.ltegopher.ltesolo`).
3. Open **Settings → Quick Settings → Edit** and add the **LTE** tile.
4. Open the **LTE Switch** app once to review status and set your **APN**.

## Usage

- **Tile**: tap to toggle. When on, the label shows `LTE 78%` (percentage derived from
  RSRP; −140 dBm = 0 %, −70 dBm = 100 %).
- **App**:
  - the **Enable LTE** switch turns LTE on/off,
  - **APN** – set your carrier's APN and press *Save APN*,
  - *Repoint system connectivity-check URLs* – optional; makes Android's validation use a
    China‑reachable endpoint (avoids a false “no internet” badge when Google is blocked),
  - **Refresh info** – updates everything.

---

## Building from source

The project builds with the Android SDK build‑tools directly (no Gradle):

```
build.bat        # aapt2 → javac → d8 → zipalign → apksigner → ltesolo.apk
```

Layout:

```
AndroidManifest.xml
assets/
  lte/lte-ctl.sh          # the root control script
  lte/ethcli.jar          # root helper calling hidden EthernetManager
  qmi/                    # ld-linux + qmicli + mbim-proxy + libs
res/values/strings.xml    # English (default)
res/values-zh[-rCN]/…     # Chinese
src/com/ltegopher/ltesolo/{MainActivity,LteTile,Extract}.java
```

`assets/qmi/` is populated from a Debian rootfs: copy
`ld-linux-x86-64.so.2`, `libqmi-glib`, `libmbim-glib`, `libglib-2.0`, `libgio-2.0`,
`libgobject-2.0`, `libgmodule-2.0`, `libqrtr-glib`, `libc`, `libpcre2-8`, `libz`, `libm`,
`libmount`, `libselinux`, `libffi`, `libblkid`, `qmicli` and `mbim-proxy` out of the
`libqmi-utils` / `libmbim-utils` packages.

---

## Troubleshooting

**Tile shows “Extract failed” / nothing happens**
Make sure the app has root, then reopen the tile (the first tap also extracts ~13 MB).

**`ERR: no IPv4 from modem` / LTE has no internet**
The QMI session was stale or wedged. The script re‑enumerates the modem once and retries;
if it still fails, toggle LTE off/on again. A stale session (IP present but no data) is
detected via a ping and re‑established automatically.

**Android shows “no internet” although data works**
The network is only *partially* validated because Google's probe endpoints are blocked.
Enable *Repoint system connectivity-check URLs* in the app.

**Turning LTE on drops Wi‑Fi — expected**
Ethernet and Wi‑Fi don't share the uplink here. Toggle back to restore Wi‑Fi.

---

## Limitations

- Only for devices with this **Qualcomm Snapdragon X16** modem and an **x86_64**
  Android‑x86/BlissOS build (no RIL). Other ROMs/ABIs need porting.
- Requires **root** (KernelSU).
- The bundled `qmicli` / `mbim-proxy` are **x86_64 glibc** binaries run through a shipped
  glibc loader.

---

## Credits & References

- [linux-surface – Surface Go 2 wiki](https://github.com/linux-surface/linux-surface/wiki/Surface-Go-2)
- [linux-surface issue #306 – LTE/4G/mobile support](https://github.com/jakeday/linux-surface/issues/306)
  (the `cdc_ncm` buffer-size fix)
- [kepi.cz – Surface Go 2 and LTE modem](https://kepi.cz/surface-go-2-lte-modem)

## License

The app's own source is released under the **MIT License** (see `LICENSE`).

> **Note on bundled binaries:** `assets/qmi/` contains `qmicli`, `mbim-proxy` and their
> dependencies from **libqmi** and **libmbim** (LGPL‑2.1+ / GPL‑2.0+), plus a glibc loader
> and runtime libraries from **glibc** (LGPL‑2.1+). If you redistribute the APK you must
> comply with those licenses (include the texts / offer sources as required).
