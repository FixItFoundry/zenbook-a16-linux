#!/usr/bin/env bash
# assemble.sh — copy the source docs/DTS/scripts from the working project folder into this
# repo, then initialize git. Run this ONCE from the repo root.
#
#   cd "zenbook-a16-linux"
#   bash assemble.sh
#
# In Fedora WSL the project folder is under /mnt/c/... ; this script auto-detects it as the
# parent of the repo. Override with:  SRC=/path/to/"Zenbook A16 Linux on ARM" bash assemble.sh
#
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$(dirname "$REPO")}"                 # parent = "Zenbook A16 Linux on ARM"
PROJ="$SRC/Linux-X2-Project"
BK="$PROJ/boot-kit"

echo "Repo : $REPO"
echo "Src  : $SRC"
[ -d "$PROJ" ] || { echo "ERROR: can't find Linux-X2-Project under $SRC. Set SRC=... and retry."; exit 1; }

cp_ () { [ -f "$1" ] && cp -f "$1" "$2" && echo "  + $(basename "$1")" || echo "  ! missing: $1"; }

echo "== docs =="
cp_ "$PROJ/07_DTB_CHANGELOG.md"        "$REPO/docs/DTB_CHANGELOG.md"
cp_ "$PROJ/03_HARDWARE_MAP.md"         "$REPO/docs/HARDWARE_MAP.md"
cp_ "$PROJ/05_DT_BRINGUP_NOTES.md"     "$REPO/docs/DT_BRINGUP_NOTES.md"
cp_ "$PROJ/7-15-2026_STATUS.md"        "$REPO/docs/STATUS_2026-07-15.md"
cp_ "$PROJ/DISPLAY-BRINGUP-FINDINGS.md" "$REPO/docs/display-bringup-findings.md"
cp_ "$SRC/EDP_ENABLE_FINDINGS.md"      "$REPO/docs/edp-enable-findings.md"
cp_ "$SRC/EDP_ENABLE_PLAN.md"          "$REPO/docs/edp-enable-plan.md"

echo "== docs/gpu-re =="
cp_ "$SRC/gpu_smmu_routing_from_WoA_ACPI.md" "$REPO/docs/gpu-re/gpu-smmu-routing-from-woa-acpi.md"
cp_ "$SRC/gunyah_dpu_path_scope.md"    "$REPO/docs/gpu-re/gunyah-dpu-path-scope.md"
cp_ "$SRC/pkvm_smmu_findings.md"       "$REPO/docs/gpu-re/pkvm-smmu-findings.md"
cp_ "$PROJ/GPU_Investigation_Summary.md" "$REPO/docs/gpu-re/gpu-investigation-summary.md"
cp_ "$PROJ/GPU_Reverse_Engineering_Plan.md" "$REPO/docs/gpu-re/gpu-reverse-engineering-plan.md"
cp_ "$PROJ/gpucc_clock_registers.md"   "$REPO/docs/gpu-re/gpucc-clock-registers.md"

echo "== docs/analysis (G-series + build plans) =="
mkdir -p "$REPO/docs/analysis"
for f in "$PROJ"/G0*-*.md "$PROJ"/G1*-*.md "$PROJ/BUILD-PLAN-A-GUNYAH-PRIMARY-VM.md" "$PROJ/BUILD-PLAN-B-KVM-PKVM-SELFHOST.md"; do
  [ -f "$f" ] && cp -f "$f" "$REPO/docs/analysis/" && echo "  + $(basename "$f")"
done

echo "== dts =="
cp_ "$BK/test47.dts"       "$REPO/dts/glymur-a16-test47.dts"
cp_ "$BK/test55-usb.dts"   "$REPO/dts/glymur-a16-test55-usb.dts"
cp_ "$PROJ/test58.dts"     "$REPO/dts/glymur-a16-test58.dts"
cp_ "$BK/glymur-crd.dts"   "$REPO/dts/glymur-crd-base.dts"
cp_ "$BK/glymur-gpu.dtsi"  "$REPO/dts/glymur-gpu.dtsi"

echo "== prebuilt =="
cp_ "$BK/test55-usb.dtb"   "$REPO/prebuilt/glymur-a16-test55-usb.dtb"

echo "== boot-kit/scripts =="
for f in patch_dt.py build_test55_usb.py build_test55_msm.py \
         build-kernel-native-full.sh build-kernel-wsl.sh install-dt-kernel.sh \
         install-battery-modules.sh collect-acpi-hw.sh stage-test-dtbs.sh; do
  cp_ "$BK/$f" "$REPO/boot-kit/scripts/"
done
cp_ "$PROJ/deploy-dtb.sh"  "$REPO/boot-kit/scripts/deploy-dtb.sh"
cp_ "$BK/grub.cfg.laptop"  "$REPO/boot-kit/grub.cfg.laptop.example"

echo "== kernel =="
cp_ "$BK/night_diff.patch" "$REPO/kernel/patches/night_diff.patch"
cp_ "$PROJ/gpucc-x2.c"     "$REPO/kernel/gpucc-x2.c"

echo "== git init =="
cd "$REPO"
if [ ! -d .git ]; then git init -b main; fi
git add -A
git status --short | head -40
echo
echo "Review the staged files above (confirm NO blobs/large binaries slipped past .gitignore),"
echo "then:   git commit -m 'Initial public release: Zenbook A16 (glymur) Linux bring-up'"
echo "See PUSH_INSTRUCTIONS.md for creating + pushing the GitHub repo."
