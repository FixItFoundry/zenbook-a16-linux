# boot-kit

Scripts and a sample GRUB config for building, patching, and deploying glymur DTBs and the
kernel onto the Zenbook A16.

## Scripts (`scripts/`)
- `build-kernel-native-full.sh` — build v7.1 `.deb`s **on the A16 itself**, starting from the
  distro config + the glymur enable-list. Produces installable packages + `dtbs`.
- `build-kernel-wsl.sh` — cross-build variant for WSL.
- `patch_dt.py` — decompile → edit → recompile a DTB (the workhorse for DT experiments).
- `build_test55_usb.py`, `build_test55_msm.py` — build the **diagnostic** variants `test55-usb`
  (USB/battery focus, MDSS off) and `test55-msm` (display/`msm` diagnostic). The **daily driver is
  `test55`**, shipped prebuilt in [`../prebuilt/`](../prebuilt/) (or patch it from `dts/` with
  `patch_dt.py`).
- `install-dt-kernel.sh` — install a built kernel + DTB and register a GRUB entry.
- `install-battery-modules.sh` — install the out-of-tree battery/SOCCP-glink + audio modules.
- `collect-acpi-hw.sh` — helper to dump ACPI + hardware identity. (The project's RE actually
  started from ACPI/hardware dumps the maintainer had already produced beforehand; this just
  reproduces that kind of capture.)
- `deploy-dtb.sh` — scp a DTB to the box and point GRUB at it (edit the host/user first).

## GRUB
`grub.cfg.laptop.example` is a sanitized sample of the on-box GRUB config.

**Rules that bit us (don't skip):**
- **Required boot cmdline** — every `dt-*` entry needs the full working `dt-clean` arg set:
  ```
  root=UUID=<your-root> rw clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime
  arm64.nopauth console=tty0 ignore_loglevel modprobe.blacklist=msm rd.timeout=60
  panic=10 softlockup_panic=1 kvm-arm.mode=protected
  systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device
  ```
  The load-bearing ones: **`modprobe.blacklist=msm`** (the display driver kills Wi-Fi on this
  older 7.1-era baseline) and the **`systemd.mask=dev-tpm*.device`** masks (skip a ~90 s
  TPM-probe boot stall).

  ⚠️ **`efi=noruntime` above is historical.** It was retired on 2026-07-30: the
  "a missing one warm-resets early on this firmware" claim was never reproducible on a
  clean tree, and dropping it changes no capability (efivars are unreachable either way —
  this firmware reports EFI *variable* services as `EFI_UNSUPPORTED`). Harmless to leave in an old entry, but do not treat it as required. See
  [`../docs/DTB_CHANGELOG.md`](../docs/DTB_CHANGELOG.md).
- The safe daily default points at `glymur-a16-test55.dtb` (MDSS disabled, simplefb).
- Display-enabled entries (`msm` loaded) are **diagnostic only** — they currently kill Wi-Fi.
- `update-grub` will overwrite hand-edited entries; keep the source of truth in
  `/etc/grub.d/40_custom` and re-generate deliberately.

## Boot chain
UEFI → GRUB → `dtbloader.efi` (loads the selected DTB) → kernel. The prebuilt daily DTB is in
[`../prebuilt/`](../prebuilt/).
