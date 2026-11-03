# Reproduce the RC5 source and configuration

This package records the integrated `7.3.0-rc5-ZenbookA16-20261002-rc5-integrated1+`
build. `build.json` identifies the base, prior base and expected Git tree.
`config` is the RC3 baseline config plus the EC v3 module; it is regenerated and
re-verified after every build. No private signing keys or firmware binaries are
included.

## Verify without changing a kernel checkout

From this repository, with a Linux Git repository containing the base commit:

```sh
python3 kernel/rc5-20261002/verify.py /path/to/linux
```

The verifier checks package hashes, applies all patches to a temporary index,
and compares the resulting tree with the original build's tree. It does not
change HEAD, the normal index or working files. Git may store reconstructed
objects in the supplied repository.

## Build on Fedora (recommended)

On Fedora, install the build tools, then run from the project root:

```sh
sudo dnf install bc bison dwarves elfutils-libelf-devel flex gcc git make \
  openssl-devel perl python3 rpm-build rsync
```

```sh
JOBS=8 ./kernel/rc5-20261002/build.sh /path/to/linux /path/to/new-output
```

The script creates an isolated Git worktree, verifies every patch and the final
source tree, builds the Image/modules/DTB, and produces both a live-image bundle
and Fedora-installable RPMs. It never changes your current kernel checkout and
refuses to reuse an output directory. `LINUX_GIT` may be a normal checkout or a
bare repository; the worktree is created from the recorded base commit, not
from `HEAD`.

`JOBS=8` is a deliberate compromise. Unexplained resets under high-parallelism
builds are still being investigated; `JOBS=4` is the value with the most
history behind it.

## Manual build

Use a separate, clean Linux checkout and an empty output directory. Set absolute
paths for `project`, `linux_src` and `build_dir` first; install normal kernel build
dependencies through your distribution. Cross-compilation additionally needs
the appropriate ARCH/CROSS_COMPILE settings.

```sh
set -e
git -C "$linux_src" switch --detach 72d3fcf802c45d00b300f25b848a93c3a2bd7c7e
while IFS= read -r patch; do
    git -C "$linux_src" am "$project/patches/rc5-20261002/$patch"
done < "$project/patches/rc5-20261002/series"
# Stop on any apply failure; the tree must match before building.
test "$(git -C "$linux_src" rev-parse HEAD^{tree})" = a3327a6d526503774e01b3bb15841883da87a180
mkdir -p "$build_dir"
cp "$project/kernel/rc5-20261002/config" "$build_dir/.config"
make -C "$linux_src" O="$build_dir" LOCALVERSION=+ olddefconfig
make -C "$linux_src" O="$build_dir" LOCALVERSION=+ -j8 Image modules dtbs
```

Run as a fail-fast script (`set -e`) or check every exit status. `LOCALVERSION=+`
preserves the recorded release suffix independently of replayed commit IDs.
Use a NEW release name before installing a changed kernel; never shadow the
fallback's modules.

The matching board source is produced by this series at
`arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb`.
Do not substitute the repository's historical merged DTS or prebuilt DTBs.
Matching Image/modules/DTB, board firmware and audio topology are all required.
Building does not install modules, regenerate an initramfs or select GRUB. Use
the packaged RPM from the recommended path for an installed Fedora system.

## What changed from RC3

| | RC3 (`rc3-20260919`) | RC5 (`rc5-20261002`) |
|---|---|---|
| Base | `v7.3-rc3` `fd73f4a66598` | `v7.3-rc5` `72d3fcf802c4` |
| Patches | 24 | 28 |
| Source tree | `e6659a96296b` | `a3327a6d5265` |
| Retired | — | `drm/msm/dp` PUSH_IDLE guard, now upstream as `e249a6e2a130` |
| Added | — | ASUS EC v3 driver + DT (4), PMH0104 camera LDOs (1) |
| Config delta | — | `CONFIG_EC_ASUS_GLYMUR=m`, retargeted `LOCALVERSION` |

The older RC3 package stays in place: it is the reproduction path for the
kernel that was actually booting as the known-good baseline, and it remains
the fallback entry. See [current-build.md](../../docs/current-build.md).

## Userspace and diagnostics

See [RC3 userspace changes](../../tweaks/rc3-housekeeping.md) for the
configurations that accompany the baseline, and [diagnostic
tools](../../scripts/triage/README.md) for the bounded collector. Kernel
source is unchanged by those efficiency fixes; audio recovery is still
unproven across the full test matrix.