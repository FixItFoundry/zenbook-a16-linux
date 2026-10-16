#!/usr/bin/env bash
# Reproduce the RC5 soc2 baseline kernel and build a Fedora-installable RPM.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: build.sh LINUX_GIT OUTPUT_DIR

LINUX_GIT must be a Linux kernel Git repository containing the recorded base
commit. OUTPUT_DIR must not already exist. The script uses a separate Git
worktree, so it never changes your current kernel checkout.

Environment:
  JOBS=4          Parallel build jobs. Keep this moderate on the A16.
  BUILD_RPM=1     Build Fedora-installable RPMs (default: 1).
  BUILD_DEB=0     Build Ubuntu/Debian-installable DEBs (default: 0).
  STAGE_BUNDLE=1  Stage portable distro-agnostic bundle (default: 1).
  ARCH=arm64      Kernel architecture.
  CROSS_COMPILE=  Optional cross-compiler prefix.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi
[[ $# -eq 2 ]] || { usage >&2; exit 2; }

[[ -e "$1" ]] || {
    echo "error: Linux checkout does not exist: $1" >&2
    exit 1
}
linux_git=$(realpath "$1")
output=$2
project=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
meta="$project/kernel/rc5-20261013/build.json"
patch_dir="$project/patches/rc5-20261013"
jobs=${JOBS:-4}
build_rpm=${BUILD_RPM:-1}
build_deb=${BUILD_DEB:-0}
stage_bundle=${STAGE_BUNDLE:-1}
export ARCH=${ARCH:-arm64}
export CROSS_COMPILE=${CROSS_COMPILE:-}

# Accept a non-bare checkout or a bare repository; both are valid inputs
# because the worktree is created from the recorded base commit, not HEAD.
if [[ "$(git -C "$linux_git" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]] \
    && [[ "$(git -C "$linux_git" rev-parse --is-bare-repository 2>/dev/null)" != true ]]; then
    echo "error: not a Git checkout or bare repository: $linux_git" >&2
    exit 1
fi
[[ ! -e "$output" ]] || {
    echo "error: output directory already exists: $output" >&2
    exit 1
}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "error: JOBS must be a positive integer" >&2; exit 1; }
[[ "$build_rpm" == 0 || "$build_rpm" == 1 ]] || { echo "error: BUILD_RPM must be 0 or 1" >&2; exit 1; }
[[ "$build_deb" == 0 || "$build_deb" == 1 ]] || { echo "error: BUILD_DEB must be 0 or 1" >&2; exit 1; }
[[ "$stage_bundle" == 0 || "$stage_bundle" == 1 ]] || { echo "error: STAGE_BUNDLE must be 0 or 1" >&2; exit 1; }

for command in git make python3 sha256sum; do
    command -v "$command" >/dev/null || { echo "error: missing command: $command" >&2; exit 1; }
done
if [[ "$build_rpm" == 1 ]]; then
    for command in rpmbuild rpm; do
        command -v "$command" >/dev/null || {
            echo "error: $command is required (Fedora: sudo dnf install rpm-build rpm)" >&2
            exit 1
        }
    done
fi
if [[ "$build_deb" == 1 ]]; then
    for command in dpkg-buildpackage dpkg-deb; do
        command -v "$command" >/dev/null || {
            echo "error: $command is required (Debian/Ubuntu: sudo apt-get install dpkg-dev)" >&2
            exit 1
        }
    done
fi

base=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["base"])' "$meta")
expected_tree=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_tree"])' "$meta")
expected_release=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["release"])' "$meta")

git -C "$linux_git" cat-file -e "$base^{commit}" 2>/dev/null || {
    echo "error: the Linux repository does not contain base commit $base" >&2
    exit 1
}
python3 "$project/kernel/rc5-20261013/verify.py" "$linux_git"

mkdir -p "$output"
output=$(realpath "$output")
source_tree="$output/source"
object_dir="$output/build"
bundle="$output/bundle"

echo "Creating an isolated source worktree..."
git -C "$linux_git" worktree add --detach "$source_tree" "$base"
while IFS= read -r patch; do
    [[ -n "$patch" ]] || continue
    git -C "$source_tree" am "$patch_dir/$patch"
done < "$patch_dir/series"

actual_tree=$(git -C "$source_tree" rev-parse 'HEAD^{tree}')
[[ "$actual_tree" == "$expected_tree" ]] || {
    echo "error: patched source tree is $actual_tree; expected $expected_tree" >&2
    exit 1
}

mkdir -p "$object_dir"
cp "$project/kernel/rc5-20261013/config" "$object_dir/.config"
make -C "$source_tree" O="$object_dir" LOCALVERSION=+ olddefconfig
release=$(make -s -C "$source_tree" O="$object_dir" LOCALVERSION=+ kernelrelease)
[[ "$release" == "$expected_release" ]] || {
    echo "error: kernel release is $release; expected $expected_release" >&2
    exit 1
}

echo "Building $release with $jobs jobs..."
make -C "$source_tree" O="$object_dir" LOCALVERSION=+ -j"$jobs" Image modules dtbs

echo "Verifying built device tree..."
dtb_file="$object_dir/arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb"
[[ -s "$dtb_file" ]] || {
    echo "error: built DTB not found: $dtb_file" >&2
    exit 1
}
dtc_bin="dtc"
if [[ -x "$object_dir/scripts/dtc/dtc" ]]; then
    dtc_bin="$object_dir/scripts/dtc/dtc"
fi
dt_source=$("$dtc_bin" -I dtb -O dts "$dtb_file" 2>/dev/null) || {
    echo "error: failed to decompile built DTB with $dtc_bin: $dtb_file" >&2
    exit 1
}
grep -q 'qcom,keep-runtime-active;' <<< "$dt_source" || {
    echo "error: built DTB is missing required 'qcom,keep-runtime-active;' property" >&2
    exit 1
}
echo "Verified: DTB contains qcom,keep-runtime-active;"

if [[ "$stage_bundle" == 1 ]]; then
    echo "Staging portable distro-agnostic bundle at $bundle..."
    mkdir -p "$bundle"
    make -C "$source_tree" O="$object_dir" LOCALVERSION=+ \
        INSTALL_MOD_PATH="$bundle" modules_install

    install -Dm644 "$object_dir/arch/arm64/boot/Image" "$bundle/vmlinuz-$release"
    install -Dm644 "$dtb_file" "$bundle/glymur-asus-zenbook-a16-ux3607oa.dtb"
    ln -sf "glymur-asus-zenbook-a16-ux3607oa.dtb" "$bundle/$release.dtb"
    install -Dm644 "$object_dir/.config" "$bundle/config-$release"

    rm -f "$bundle/lib/modules/$release/build" "$bundle/lib/modules/$release/source"

    # Distro ABI and identification markers
    printf '1\n' > "$bundle/lib/modules/$release/omarchy-a16-dsp-abi"
    printf '1\n' > "$bundle/lib/modules/$release/zenbook-a16-dsp-abi"
    install -d "$bundle/usr/share/doc/linux-zenbook-a16"
    printf '%s\n' "$release" > "$bundle/usr/share/doc/linux-zenbook-a16/kernel-release"

    # Compatibility symlink for tools expecting $bundle/modules/$release
    mkdir -p "$bundle/modules"
    ln -sfn "../lib/modules/$release" "$bundle/modules/$release"
fi

if [[ "$build_rpm" == 1 ]]; then
    echo "Building the installed-system RPM..."
    make -C "$source_tree" O="$object_dir" LOCALVERSION=+ -j"$jobs" binrpm-pkg
    mkdir -p "$bundle/rpms"
    find "$object_dir/rpmbuild/RPMS" -type f -name '*.rpm' -exec cp -t "$bundle/rpms" {} +
    kernel_rpm=
    while IFS= read -r candidate; do
        [[ $(rpm -qp --queryformat '%{NAME}' "$candidate") == kernel ]] || continue
        kernel_rpm=$candidate
        break
    done < <(find "$bundle/rpms" -type f -name '*.rpm' -print | sort)
    [[ -n "$kernel_rpm" ]] || {
        echo "error: kernel RPM was not produced" >&2
        exit 1
    }
    rpm_contents=$(rpm -qlp "$kernel_rpm")
    grep -Fxq "/lib/modules/$release/vmlinuz" <<<"$rpm_contents" || {
        echo "error: kernel RPM does not contain its Image" >&2
        exit 1
    }
    grep -Fxq "/lib/modules/$release/dtb/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb" \
        <<<"$rpm_contents" || {
        echo "error: kernel RPM does not contain the A16 DTB" >&2
        exit 1
    }
fi

if [[ "$build_deb" == 1 ]]; then
    echo "Building Debian/Ubuntu packages (bindeb-pkg)..."
    make -C "$source_tree" O="$object_dir" LOCALVERSION=+ -j"$jobs" bindeb-pkg
    mkdir -p "$bundle/debs"
    find "$output" -maxdepth 1 -type f -name '*.deb' -exec cp -t "$bundle/debs" {} + 2>/dev/null || \
    find "$output" -type f -name '*.deb' ! -path "$bundle/*" -exec cp -t "$bundle/debs" {} + 2>/dev/null || true
    kernel_deb=
    while IFS= read -r candidate; do
        [[ $(dpkg-deb -f "$candidate" Package 2>/dev/null) =~ ^linux-image ]] || continue
        kernel_deb=$candidate
        break
    done < <(find "$bundle/debs" -type f -name '*.deb' -print | sort)
    [[ -n "$kernel_deb" ]] || {
        echo "error: kernel DEB was not produced" >&2
        exit 1
    }
fi

if [[ -d "$bundle" ]]; then
    (
        cd "$bundle"
        find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
    )
fi

rpm_summary="not requested (BUILD_RPM=0)"
[[ "$build_rpm" == 1 ]] && rpm_summary=$bundle/rpms
deb_summary="not requested (BUILD_DEB=0)"
[[ "$build_deb" == 1 ]] && deb_summary=$bundle/debs
bundle_summary="not staged (STAGE_BUNDLE=0)"
[[ "$stage_bundle" == 1 ]] && bundle_summary=$bundle
cat <<EOF

Build complete: $release
  Portable bundle:    $bundle_summary
  Fedora RPMs:        $rpm_summary
  Ubuntu/Debian DEBs: $deb_summary

The live initramfs is intentionally not built here. Build it from the matching
modules as described in iso/README.md. Install the kernel packages on the target
system; loose files on a live USB are not copied by Anaconda/Subiquity.
EOF
