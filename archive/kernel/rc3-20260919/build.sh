#!/usr/bin/env bash
# Reproduce the promoted RC3 kernel and build a Fedora-installable RPM.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: build.sh LINUX_GIT OUTPUT_DIR

LINUX_GIT must be a Linux kernel Git repository containing the recorded base
commit. OUTPUT_DIR must not already exist. The script uses a separate Git
worktree, so it never changes your current kernel checkout.

Environment:
  JOBS=4          Parallel build jobs. Keep this conservative on the A16.
  BUILD_RPM=1     Build Fedora-installable RPMs (set to 0 for a live bundle only).
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
meta="$project/kernel/rc3-20260919/build.json"
patch_dir="$project/patches/rc3-20260919"
jobs=${JOBS:-4}
build_rpm=${BUILD_RPM:-1}
export ARCH=${ARCH:-arm64}
export CROSS_COMPILE=${CROSS_COMPILE:-}

[[ -d "$linux_git/.git" || -f "$linux_git/.git" ]] || {
    echo "error: not a Git checkout: $linux_git" >&2
    exit 1
}
[[ ! -e "$output" ]] || {
    echo "error: output directory already exists: $output" >&2
    exit 1
}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "error: JOBS must be a positive integer" >&2; exit 1; }
[[ "$build_rpm" == 0 || "$build_rpm" == 1 ]] || { echo "error: BUILD_RPM must be 0 or 1" >&2; exit 1; }

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

base=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["base"])' "$meta")
expected_tree=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_tree"])' "$meta")
expected_release=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["release"])' "$meta")

git -C "$linux_git" cat-file -e "$base^{commit}" 2>/dev/null || {
    echo "error: the Linux repository does not contain base commit $base" >&2
    exit 1
}
python3 "$project/kernel/rc3-20260919/verify.py" "$linux_git"

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

mkdir -p "$object_dir" "$bundle/modules"
cp "$project/kernel/rc3-20260919/config" "$object_dir/.config"
make -C "$source_tree" O="$object_dir" LOCALVERSION=+ olddefconfig
release=$(make -s -C "$source_tree" O="$object_dir" LOCALVERSION=+ kernelrelease)
[[ "$release" == "$expected_release" ]] || {
    echo "error: kernel release is $release; expected $expected_release" >&2
    exit 1
}

echo "Building $release with $jobs jobs..."
make -C "$source_tree" O="$object_dir" LOCALVERSION=+ -j"$jobs" Image modules dtbs
make -C "$source_tree" O="$object_dir" LOCALVERSION=+ \
    INSTALL_MOD_PATH="$bundle" modules_install

install -Dm644 "$object_dir/arch/arm64/boot/Image" "$bundle/vmlinuz-$release"
install -Dm644 \
    "$object_dir/arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb" \
    "$bundle/$release.dtb"
install -Dm644 "$object_dir/.config" "$bundle/config-$release"
rm -f "$bundle/lib/modules/$release/build" "$bundle/lib/modules/$release/source"
mv "$bundle/lib/modules/$release" "$bundle/modules/"
rmdir "$bundle/lib/modules" "$bundle/lib"

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

(
    cd "$bundle"
    find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

rpm_summary="not requested (BUILD_RPM=0)"
[[ "$build_rpm" == 1 ]] && rpm_summary=$bundle/rpms
cat <<EOF

Build complete: $release
  Live-image inputs: $bundle
  Fedora RPMs:       $rpm_summary

The live initramfs is intentionally not built here. Build it from the matching
modules as described in iso/README.md. Install the kernel RPM on the target
Fedora system; loose files on a live USB are not copied by Anaconda.
EOF
