# Reproduce the RC3 source and configuration

This package records the promoted `7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+`
build. `build.json` identifies the base, integrated source and expected Git tree.
`config` exactly matches the installed `/boot/config-<release>` and original
build configuration. No private signing keys or firmware binaries are included.

## Verify without changing a kernel checkout

From this repository, with a Linux Git repository containing the base commit:

```sh
python3 kernel/rc3-20260919/verify.py /path/to/linux
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
JOBS=4 ./kernel/rc3-20260919/build.sh /path/to/linux /path/to/new-output
```

The script creates an isolated Git worktree, verifies every patch and the final
source tree, builds the Image/modules/DTB, and produces both a live-image bundle
and Fedora-installable RPMs. It never changes your current kernel checkout and
refuses to reuse an output directory. `JOBS=4` is deliberate: unexplained resets
under highly parallel builds are still being investigated.

The main RPM is the installed-system artifact. It keeps the Image, modules and
DTBs under one package transaction and calls Fedora's `kernel-install` hook.
The live USB's loose kernel files are boot media only; Anaconda does not install
them onto disk.

After Fedora is installed, copy the `bundle/rpms/` directory onto that system
and install the main package while keeping Fedora's working kernel as a fallback:

```sh
cd /path/to/bundle/rpms
sudo dnf install ./kernel-[0-9]*.rpm
```

## Manual build

Use a separate, clean Linux checkout and an empty output directory. Set absolute
paths for `project`, `linux_src` and `build_dir` first; install normal kernel build
dependencies through your distribution. Cross-compilation additionally needs
the appropriate ARCH/CROSS_COMPILE settings.

```sh
set -e
git -C "$linux_src" switch --detach fd73f4a6659897191fa0d40695fe370925dd3780
while IFS= read -r patch; do
    git -C "$linux_src" am "$project/patches/rc3-20260919/$patch"
done < "$project/patches/rc3-20260919/series"
# Stop on any apply failure; the tree must match before building.
test "$(git -C "$linux_src" rev-parse HEAD^{tree})" = e6659a96296be6a31eb45c69729a0320b12cd915
mkdir -p "$build_dir"
cp "$project/kernel/rc3-20260919/config" "$build_dir/.config"
make -C "$linux_src" O="$build_dir" LOCALVERSION=+ olddefconfig
make -C "$linux_src" O="$build_dir" LOCALVERSION=+ -j4 Image modules dtbs
```

Run as a fail-fast script (`set -e`) or check every exit status. `LOCALVERSION=+`
preserves the recorded release suffix independently of replayed commit IDs.
Use a NEW release name before installing a changed kernel; never shadow the
fallback's modules. High-parallelism build resets remain under investigation.

The matching board source is produced by this series at
`arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dts`.
Do not substitute the repository's historical merged DTS or prebuilt DTBs.
Matching Image/modules/DTB, board firmware and audio topology are all required.
Building does not install modules, regenerate an initramfs or select GRUB. Use
the packaged RPM from the recommended path for an installed Fedora system.

## Userspace and diagnostics

See [RC3 userspace changes](../../tweaks/rc3-housekeeping.md) for the configurations
that accompany the baseline, and [diagnostic tools](../../scripts/triage/README.md)
for the newly bounded collector. Kernel source remains unchanged by these
efficiency fixes; audio recovery is still unproven across the full test matrix.
