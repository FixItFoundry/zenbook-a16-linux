# boot-kit

Scripts and a sample GRUB config for building, patching, and deploying glymur DTBs and the
kernel onto the Zenbook A16.

## Scripts (`scripts/`)
- `build-kernel-native-full.sh` — build v7.1 `.deb`s **on the A16 itself**, starting from the
  distro config + the glymur enable-list. Produces installable packages + `dtbs`.
- `build-kernel-wsl.sh` — cross-build variant for WSL.
- `patch_dt.py` — decompile → edit → recompile a DTB (the workhorse for DT experiments).
- `build_test55_usb.py`, `build_test55_msm.py` — reproduce the daily-driver / msm-diagnostic DTBs.
- `install-dt-kernel.sh` — install a built kernel + DTB and register a GRUB entry.
- `install-battery-modules.sh` — install the out-of-tree battery/SOCCP-glink + audio modules.
- `collect-acpi-hw.sh` — dump ACPI + hardware identity (how the RE data was gathered).
- `deploy-dtb.sh` — scp a DTB to the box and point GRUB at it (edit the host/user first).

## GRUB
`grub.cfg.laptop.example` is a sanitized sample of the on-box GRUB config.

**Rules that bit us (don't skip):**
- **Every** `dt-*` boot entry MUST carry `efi=noruntime`. A missing one causes an intermittent
  early-boot warm reset during simpledrm/fbcon init on this firmware — easily misdiagnosed as
  a display/XPU problem.
- The safe daily default points at `glymur-a16-test55.dtb` (MDSS disabled, simplefb).
- Display-enabled entries (`msm` loaded) are **diagnostic only** — they currently kill Wi-Fi.
- `update-grub` will overwrite hand-edited entries; keep the source of truth in
  `/etc/grub.d/40_custom` and re-generate deliberately.

## Boot chain
UEFI → GRUB → `dtbloader.efi` (loads the selected DTB) → kernel. The prebuilt daily DTB is in
[`../prebuilt/`](../prebuilt/).
