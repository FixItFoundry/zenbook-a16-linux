# boot-kit

Scripts and a sample GRUB config for building, patching, and deploying glymur DTBs and the
kernel onto the Zenbook A16.

## Scripts (`scripts/`)
- `build-kernel-native-full.sh` — build v7.1 `.deb`s **on the A16 itself**, starting from the
  distro config + the glymur enable-list. Produces installable packages + `dtbs`.
- `build-kernel-wsl.sh` — cross-build variant for WSL.
- `patch_dt.py` — decompile → edit → recompile a DTB (the workhorse for DT experiments).
- `build_test55_usb.py`, `build_test55_msm.py` — build the **diagnostic** variants `test55-usb`
  (USB/battery focus, MDSS off) and `test55-msm` (display/`msm` diagnostic).
  ⚠️ **Historical.** `test55` was the daily driver in the v7.1 vendor-lineage era and is no
  longer. The **current daily driver is
  `glymur-asus-zenbook-a16-ux3607oa-merged-gpu.dts` built on 7.2-rc3, plus the one-line
  `arm,no-completion-irq` property** from
  [`../patches/glymur-scmi-no-completion-irq-CONFIRMED.patch`](../patches/) — installed on the
  box as `glymur-a16-merged-gpu-scmipoll.dtb`. Without that property the CPUs stay pinned at
  boot clock.
- `install-dt-kernel.sh` — install a built kernel + DTB and register a GRUB entry.
- `install-battery-modules.sh` — install the out-of-tree battery/SOCCP-glink + audio modules.
- `collect-acpi-hw.sh` — helper to dump ACPI + hardware identity. (The project's RE actually
  started from ACPI/hardware dumps the maintainer had already produced beforehand; this just
  reproduces that kind of capture.)
- `deploy-dtb.sh` — scp a DTB to the box and point GRUB at it (edit the host/user first).

## GRUB
`grub.cfg.laptop.example` is a sanitized sample of the on-box GRUB config.

★★ **CHANGED 2026-07-31 — `/boot/grub/grub.cfg` is GENERATED now, not hand-written.**
`/etc/grub.d/40_custom` is the source of truth (sanitized sample: `40_custom.laptop.example`).
Edit that, then `sudo grub2-mkconfig -o /boot/grub/grub.cfg`. Hand-patching `grub.cfg`
no longer survives — the next mkconfig discards it. Default is `GRUB_DEFAULT` in
`/etc/default/grub`.

Two things that will silently ruin a regeneration:

- **`insmod fdt` must be emitted at top level from `40_custom`.** Fedora's `00_header` does
  not load it, and without it every `devicetree` line fails *silently* — the machine boots
  on the firmware DT instead of ours, which looks like a device-tree regression.
- **`grub2-mkconfig` executes EVERY executable file in `/etc/grub.d/`, whatever it is
  named.** Three `40_custom.bak-*` files were sitting there executable on 2026-07-31 and
  would have injected 14 stale entries carrying retired tokens *and duplicate `--id`
  values*, which makes `set default` ambiguous. They now live in `/root/grub.d-retired/`.
  **Never leave a backup of a grub.d script inside `/etc/grub.d/`.**

- **`/etc/grub.d/30_uefi-firmware` is disabled (`chmod -x`).** Left enabled it emits a
  "UEFI Firmware Settings" entry that renders *above* the baseline, because `30_*` runs
  before `40_custom`. Harmless to booting (`set default` matches by id, not index) but it
  puts Fedora boilerplate at the top of the menu. Firmware setup is still reachable with
  `systemctl reboot --firmware-setup`.
- **`08_fallback_counting` emits `set default=1` on a failed-boot countdown.** Inert here —
  it is guarded by `boot_counter`, which only OSTree systems set — but if it ever fired,
  index 1 is `Windows Boot Manager`.

Same trap, different directory: a stale `hid-asus.ko.bak-pre-kbdbl` is sitting in
`/lib/modules/7.2.0-rc3-konrad1/kernel/drivers/hid/` and dracut copies it into every
initrd. Harmless today (`depmod` will not index it) but it is the same pattern — keep
backups out of directories that get scanned.

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

  ★★ **UPDATED 2026-07-31 — the block above is the 7.1-era set and is NOT the current
  cmdline.** Three tokens in it were retired after an audit; the current baseline is:

  ```
  root=UUID=<your-root> rw clk_ignore_unused pd_ignore_unused cma=128M console=tty0
  ignore_loglevel rd.timeout=60 panic=10
  systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device glymur_pci_skip=5
  ```

  | retired | why |
  |---|---|
  | `softlockup_panic=1` | added early to diagnose kernels that would not boot. Long obsolete — and it turned any stall into an automatic reboot, indistinguishable from the external SoC reset that was hunted for weeks. |
  | `arm64.nopauth` | obsolete; no recorded justification ever existed for it. |
  | `kvm-arm.mode=protected` | genuinely needed during eDP testing; the konrad1 tree fixed the underlying issue. |

  ⚠️ **`arm64.nopauth` and `kvm-arm.mode=protected` are still carried on the `legacy 7.1`
  recovery entry**, which predates konrad1 and therefore does not contain the fix.
  ⚠️ **The TPM masks are NOT optional** — they are the ~90 s boot stall above. They were
  briefly mislabelled "benign" during the 07-31 audit; Jesse caught it. Keep them.
  ⏭️ **Still unjustified and worth a single-variable retest:** `clk_ignore_unused` and
  `pd_ignore_unused`. They mask missing clock/genpd references in our DT — the exact bug
  class this tree keeps finding — and they already invalidated one experiment (the
  2026-07-27 gcc `state_synced` write was a silent no-op because of them).

  ⚠️ **`efi=noruntime` above is historical.** It was retired on 2026-07-30: the
  "a missing one warm-resets early on this firmware" claim was never reproducible on a
  clean tree, and dropping it changes no capability (efivars are unreachable either way —
  this firmware reports EFI *variable* services as `EFI_UNSUPPORTED`). Harmless to leave in an old entry, but do not treat it as required. See


⚠️ **Correction (2026-07-30, later the same day):** do not treat "this firmware does not support EFI variable services" as settled. Two archived `efi_pstore` crash dumps prove variable services **worked** on this same machine and firmware under 7.1 kernels. The `EFI_UNSUPPORTED` result above is real but is specific to our 7.2-rc3 build, and the cause is **unresolved**. See [`../docs/hardware.md`](../docs/hardware.md).
  [`../docs/modifications.md`](../docs/modifications.md).
- The safe daily default points at `glymur-a16-test55.dtb` (MDSS disabled, simplefb).
- Display-enabled entries (`msm` loaded) are **diagnostic only** — they currently kill Wi-Fi.
- `update-grub` will overwrite hand-edited entries; keep the source of truth in
  `/etc/grub.d/40_custom` and re-generate deliberately.

## Boot chain
UEFI → GRUB → `dtbloader.efi` (loads the selected DTB) → kernel. The prebuilt daily DTB is in
[`../prebuilt/`](../prebuilt/).
