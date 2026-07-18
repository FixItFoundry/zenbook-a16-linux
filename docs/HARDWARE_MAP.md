# ASUS Zenbook A16 (UX3607OA) — Snapdragon X2 Elite "Glymur" — Linux Hardware Map

Living reference for the A16 board device tree, built from the ACPI DSDT + a stock-Ubuntu-7.0 ACPI boot dmesg. Status legend: ✅ works (ACPI) · 🟨 driver binds, needs firmware/config · 🟥 DT-only, not yet up.

## Confirmed boot facts
- SoC: Snapdragon X2 Elite Extreme, **X2E-94-100**, codename **Glymur**, 18 Oryon-gen3 cores (MIDR 0x512f0021 / 0x511f0021).
- Two CPU clusters visible in redistributor spread: CPUs 0–5 vs 6–17 (0x512… vs 0x511… MIDR).
- Firmware: Insyde H2O, BIOS `UX3607OA.309` (2026-04-23). Secure Boot **off** confirmed in dmesg.
- Boots via **both** paths: ACPI (stock Ubuntu 7.0 → GNOME) and DT (our 7.1 + `glymur-crd.dtb` → early init, stalls pre-desktop).

## Subsystem status

| Subsystem | Device / ID | ACPI boot | DT path notes |
|---|---|---|---|
| CPU / GIC / SMMU | GICv3+ITS+GICv4.1, SMMUv2 ×2 + SMMUv3 | ✅ | In `glymur.dtsi` |
| **NVMe** | Samsung PM9C1a `144d:a80d`, domain 0005, ECAM `0x7a0000000`, IRQ 287 | ✅ `nvme0n1` (16 parts = Windows) | Needs A16 PCIe5 regulators/PHY in board DTS |
| **Wi‑Fi** | `17cb:1112` (QCC2072 / NCM820A), domain 0004, ECAM `0x780000000` | ✅ **WORKING** — associates + online with OEM firmware. Needs `iw reg set <country>` for 5 GHz TX | Same firmware works on DT path |
| **USB (xHCI)** | ACPI `QCOM0FEE`, io `0x0a400000`, IRQ 203 | ✅ hubs, HID kbd/mouse, USB‑Eth all enumerate | DT: dwc3-qcom + QMP PHY; suspect this is where DT boot stalls (boot USB not enumerating) |
| USB Ethernet | Realtek RTL8153 (dongle) | ✅ `carrier on` | n/a |
| **Internal keyboard** | `ECKB` `QTEC0001`, I2C‑HID @ **0x15** on **\_SB.I2C1**, GpioInt Level ActiveLow PullUp Wake, 400 kHz | 🟥 (GENI I2C not bound via ACPI) | Board DTS: enable geni-i2c bus1 + i2c-hid node |
| **Touchpad** | `ECAP` `QTEC0003`, I2C‑HID @ **0x17**, GpioInt Edge ActiveLow | 🟥 | Board DTS i2c-hid node |
| Touchscreen | `TSC1` `MSFT0001`, I2C‑HID @ **0x10**, GpioInt Level ActiveLow | 🟥 | Board DTS i2c-hid node |
| GENI I2C controllers | QUP I2C engines, HID `QCOM0F10` (multiple); HID-relevant buses **I2C1 / I2C6 / I2C9** | 🟥 | `i2c-qcom-geni` nodes in board DTS |
| **Battery / AC** | EC over ACPI **GenericSerialBus** (`_SB.CMPS._PSR`, `_SB.EC0`) — no Linux handler | 🟥 `AE_NOT_EXIST` | DT: `pmic_glink` + `qcom_battmgr` (SPMI PMIC already probes on DT — pwrkey/resin seen) |
| **GPU** | Adreno X2‑85 | 🟥 software `simpledrm`/llvmpipe only | DT: `msm` DRM + zap `qcdxkmsuc8480.mbn` (pulled) |
| **Audio** | Q6/ADSP AudioReach | 🟥 none | DT: `q6apm` + `qcadsp8480.mbn` (pulled) |
| Display panel / DPU | eDP panel | 🟥 framebuffer only (`180x56` console) | DT: DPU/DP patches (posted upstream, not merged) + panel node |
| Thermal | many TZ zones | 🟨 partial (TZ91 29°C, TZ33 32°C); most `_PSL`/`_TMP` fail via ACPI | DT: TSENS (works on CRD) |
| Lid switch | PNP0C0D | ✅ | — |

## Wi‑Fi — SOLVED (2026-07-09). Reproducible recipe
Internal Wi‑Fi (QCC2072 / FastConnect C7700) **works on Linux** with OEM firmware extracted from the Windows DriverStore. Confirmed: scan, auth, 4‑way handshake, DHCP, online. First known X2 Elite Wi‑Fi bring-up on Linux.

Place these in `/lib/firmware/ath12k/QCC2072/hw1.0/` (sources from Windows `qcwlancol8480` driver package):
- `amss.bin`      ← `wlanfw.bin`
- `aux_ucode.bin` ← `aux_ucode.elf`
- `board.bin`     ← `bdwlan_qcc2072_1p0_ncm820A.elf`
- `m3.bin`        ← `phy_ucode.elf`
- `regdb.bin`     ← as-is

Gotchas learned:
- **Do not `modprobe -r ath12k` after a failed init** — it hits a kernel oops in the unload path. Use blacklist-at-boot + a single clean `modprobe`.
- `failed to get ACPI BDF EXT: -22` + `Timeout while waiting for regulatory update` are expected under Linux (the country normally comes from a Windows-only ACPI `_DSM`). Fix: **`sudo iw reg set <CC>`** to give it a regulatory domain, which unlocks 5 GHz TX / association.
- Live-USB caveat: `/lib/firmware` is a RAM overlay — firmware + reg domain are lost on reboot. Persists once installed to disk.

## (historical) Wi‑Fi firmware — the concrete near-term experiment
ath12k requests, under `/lib/firmware/ath12k/QCC2072/hw1.0/`:
- `amss.bin`  ← candidate: **`wlanfw.bin`** (6.78 MB, from `qcwlancol` = qcc2072 folder)
- `board-2.bin` (container) or `board.bin` ← candidate: **`bdwlan_qcc2072_1p0_ncm820A.elf`**
- `regdb.bin` ← present as-is
- possibly `m3.bin` / `phy_ucode` ← `phy_ucode.elf` candidate

**Honest caveat:** these are ASUS/Windows FastConnect blobs. ath12k expects Linux-built firmware and a real `board-2.bin` container (raw `.elf` may be rejected). Worth trying (costs nothing), but the reliable fix may be waiting for QCC2072 firmware to land in `linux-firmware`, or repacking the board file with `ath12k-bdencoder`. USB Ethernet/Wi‑Fi dongle works meanwhile.

## Installed-system quirks (2026-07-09, Ubuntu 26.04 on NVMe)
- **EFI NVRAM unwritable from Linux** — installer dies at bootloader ("EFI variables are not supported"). Fix: `grub-install --no-nvram`, then register the boot entry from Windows: `bcdedit /copy {bootmgr} /d "Ubuntu"` + set path to `\EFI\ubuntu\grubaa64.efi`.
- **grub-install hostdisk bug** — errors with `disk 'hostdisk//dev/nvme0n1p12' not found` despite /dev/nvme0n1 being present (suspect PCIe-domain probing). Workaround = do its file copies by hand. **Final working layout (verified clean reboot 2026-07-09):** `/usr/lib/grub/arm64-efi-signed/grubaa64.efi.signed` copied to both `ESP/EFI/ubuntu/grubaa64.efi` and `ESP/EFI/Boot/bootaa64.efi`, plus 3-line stub at `ESP/EFI/ubuntu/grub.cfg` (search.fs_uuid <root-UUID> → set prefix → configfile). Use the signed package binary ONLY — it has part_gpt/ext2/search compiled in. Lessons burned: Windows-written stubs get CRLF (breaks GRUB quoting); grub-mkstandalone failed to embed its config AND standalone shells don't autoload part_gpt (disks appear partition-less — `insmod part_gpt` first when debugging); GRUB hdX numbering reshuffles between boots (never hardcode).
- **RTC not read** — kernel boots thinking it's a stale date (device nodes timestamped Apr 15); NTP corrects once online. PMIC RTC = DT-path item.
- **GRUB sees NVMe as hd1**, root = (hd1,gpt17); ESP = nvme0n1p12 (450MB).
- ESP is FAT32: always cleanly shut down before pulling power when it's been written; one corruption event already (fixed via Windows `chkdsk`).
- **NEVER `tar -C / -x` without `--keep-directory-symlink`** — GNU tar replaces the merged-usr `/lib` symlink with a real directory, orphaning the dynamic linker (`/lib/ld-linux-aarch64.so.1`) and slow-bricking the system ("No /sbin/init" on reboot). Happened 2026-07-09 installing kernel modules. Recovery from live USB: mv `/mnt/lib/modules/*` → `/mnt/usr/lib/modules/`, `rm -r /mnt/lib`, `ln -sr /mnt/usr/lib /mnt/lib`. Correct form: `sudo tar -C / --keep-directory-symlink -xzf modules.tar.gz` (or extract to a temp dir and mv the module tree).

## DT bring-up order (to reach a self-sufficient desktop)
1. **Fix boot-to-desktop**: get the A16 USB/PCIe + regulators right so the DT kernel reaches userspace (diagnose from earlycon tail — likely dwc3/PHY or PCIe regulator mismatch vs CRD).
2. **Internal input**: GENI I2C1/6/9 + i2c-hid nodes (addresses above) → keyboard + touchpad, no dongle.
3. **Battery/USB‑C**: pmic_glink + battmgr + Type-C.
4. **GPU**: msm + zap firmware → accel + panel backlight.
5. **Audio**: q6/ADSP + acdb.

Everything above the "boot-to-desktop" line is already sourced (addresses + firmware in hand). This is a tractable bring-up, not a research project.
