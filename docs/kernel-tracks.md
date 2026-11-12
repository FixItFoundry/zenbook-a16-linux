# Stable and RC Kernel Tracks

Updated 2026-11-03. With Qualcomm actively developing Snapdragon X2 (`glymur`) laptop support upstream (`qcom-next`, `laptops-kernel/topic/glymur-laptops`, and LKML), this repository serves two connected roles:

1. **Packaging & Delivery Layer**: Turn validated kernel trees, board DTBs, early-DSP initramfs hooks, audio UCM2/WirePlumber routing, and owner-extracted firmware into safe, side-by-side installable packages (`RPM`, `DEB`, `PKGBUILD`, and portable bundles) for people running Linux on the **ASUS Zenbook A16 UX3607OA**.
2. **Two-Track Upstream Contributor & Testing Bridge**: Maintain a rock-solid **`stable` release track** (aligned with Linux `7.3` final and `linux-omarchy 7.3`) alongside an **`rc` development track** for testing LKML series, `qcom-next` / `linux-next` snapshots, and authoring upstream fixes (`Author:` / `Tested-by:` / `Reviewed-by:`), dropping local patches as mainline absorbs them.

## Track Layout

| Track | Recipe Directory | Patch Queue | Upstream Base | Replayed Source Tree | Role |
|---|---|---|---|---|---|
| **`stable`** | [`kernel/stable/`](../kernel/stable/README.md) | [`patches/stable/`](../patches/stable/README.md) (145 patches) | `v7.3` (`c03c1a14507dfaf8b856c2608f9ac216021fc222`) | `44195f01ab0d015144df468e500628b8cba81984` | Primary release and packaging target for Fedora, Ubuntu/Debian, and `linux-omarchy 7.3`. |
| **`rc`** | [`kernel/rc/`](../kernel/rc/README.md) | [`patches/rc/`](../patches/rc/README.md) (102 patches) | `next-20261103` (`d6bcfc94eb4da6e089c5473970cd96727292fd97`, `v7.4-rc1`) | `778e99957964e7549ecd0683065311df3db7961f` | Opt-in development, LKML patch validation, and upstream rebase staging (`7.4.0-rc1-next-20261103-zenbook-a16+`). |

Historical bringup recipes (`rc3-*`, `rc5-20261002`, `rc5-20261008`, `rc5-20261013`, `rc5-20261031`) and standalone diagnostic patches are archived under [`archive/`](../archive/README.md).

## Patch Lifecycle: From `rc` to `stable` to Mainline

1. **Stage & Test on `rc` / LKML**: New hardware fixes (authored locally or pulled from `lore.kernel.org/linux-arm-msm/`, `qcom-next`, or `laptops-kernel/topic/glymur-laptops`) are validated with original `From:`, `Date:`, `Signed-off-by:`, and `Link:` trailers intact.
2. **Promote to `stable` (`kernel/stable` + `patches/stable`)**: Once a patch series replays cleanly, compiles without regressions, and passes CI/hardware checks, it is cherry-picked into `patches/stable` (Linux `7.3` final). Because Omarchy also runs on a `7.3` release kernel (`linux-omarchy 7.3`), patches validated on `stable` transfer directly to Omarchy packaging.
3. **Retire When Merged Upstream**: During each rebase onto a newer `7.3.y` stable tag or `rc` / `linux-next` snapshot, [`patches/stable/port-map.json`](../patches/stable/port-map.json) records upstream equivalents and drops redundant local patches.

## Verification and Promotion Gates

1. **Deterministic Source Replay**:
   ```sh
   python3 scripts/ci.py --replay-only --track both --linux-git /path/to/linux.git
   ```
   Verifies every SHA256 checksum in `kernel/stable/SHA256SUMS` and `kernel/rc/SHA256SUMS`, replays all patches in a temporary Git index without modifying the checkout, and confirms reverse application back to the recorded upstream base.
2. **Hardware-Free CI & Package Contract Suite**:
   ```sh
   ./scripts/ci-vm.sh --linux-git /path/to/linux.git
   ```
   Runs all 9 unit test suites (125 tests across installer safety, Arch/Fedora/Ubuntu package staging, post-install hooks, boot verification, build resume, and diagnostics) inside a disposable Linux KVM guest.
3. **Full ARM64 Kernel, DTB & Package Build**:
   ```sh
   JOBS=4 PACKAGE_REVISION=1 ./kernel/stable/build.sh /path/to/linux.git /path/to/output
   ```
   Verifies `CONFIG_LOCALVERSION`, required Kconfig symbols (`kernel/stable/required.config`), `qcom,keep-runtime-active;` in the compiled `glymur-asus-zenbook-a16-ux3607oa.dtb`, external-module build headers, portable bundle metadata, and `aarch64` RPM/DEB packages.
4. **Hardware & Rollback Acceptance**:
   Every package revision uses a distinct `-a16pkgN+` release identity and preserves the previously booted kernel and Windows boot manager entry for rollback.
