#!/usr/bin/env bash
# Build the mainline release + qcom-next/qcom-topics bridge source as a
# versioned A16 kernel package managed via post-install hooks.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: build.sh [--resume] LINUX_GIT OUTPUT_DIR

LINUX_GIT must be a Linux kernel Git repository containing the recorded base
commit. OUTPUT_DIR must not already exist unless --resume is given. Resume
reuses a clean, fully patched worktree and its build objects after a build or
packaging failure. Use the same environment settings as the original build.
The script never changes your current kernel checkout.

Environment:
  JOBS=4          Parallel build jobs. Keep this moderate on the A16.
  BUILD_RPM=0     Build Fedora-installable RPMs (default: 0).
  BUILD_DEB=1     Build Ubuntu/Debian-installable DEBs (default: 1).
  STAGE_BUNDLE=1  Stage portable distro-agnostic bundle (default: 1).
  PACKAGE_REVISION=1  Positive revision; changes uname and package version.
  ARCH=arm64      Kernel architecture.
  CROSS_COMPILE=  Optional cross-compiler prefix.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi
resume=0
if [[ ${1:-} == --resume ]]; then
    resume=1
    shift
fi
[[ $# -eq 2 ]] || { usage >&2; exit 2; }

[[ -e "$1" ]] || {
    echo "error: Linux checkout does not exist: $1" >&2
    exit 1
}
linux_git=$(realpath "$1")
output=$2
project=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
meta="$project/kernel/rc5-qcom-bridge-20261018/build.json"
base_patch_dir="$project/patches/rc5-20261013"
bridge_patch_dir="$project/patches/qcom-glymur-bridge-20261018"
jobs=${JOBS:-4}
build_rpm=${BUILD_RPM:-0}
build_deb=${BUILD_DEB:-1}
stage_bundle=${STAGE_BUNDLE:-1}
revision=${PACKAGE_REVISION:-1}
local_version="-a16pkg${revision}+"
export ARCH=${ARCH:-arm64}
export CROSS_COMPILE=${CROSS_COMPILE:-}

if [[ "$(git -C "$linux_git" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]] \
    && [[ "$(git -C "$linux_git" rev-parse --is-bare-repository 2>/dev/null)" != true ]]; then
    echo "error: not a Git checkout or bare repository: $linux_git" >&2
    exit 1
fi
if [[ "$resume" == 1 ]]; then
    [[ -f "$output/source/.git" ]] || {
        echo "error: --resume requires an existing source worktree in $output/source" >&2
        exit 1
    }
else
    [[ ! -e "$output" ]] || {
        echo "error: output directory already exists: $output (use --resume to retry)" >&2
        exit 1
    }
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "error: JOBS must be a positive integer" >&2; exit 1; }
[[ "$build_rpm" == 0 || "$build_rpm" == 1 ]] || { echo "error: BUILD_RPM must be 0 or 1" >&2; exit 1; }
[[ "$build_deb" == 0 || "$build_deb" == 1 ]] || { echo "error: BUILD_DEB must be 0 or 1" >&2; exit 1; }
[[ "$stage_bundle" == 0 || "$stage_bundle" == 1 ]] || { echo "error: STAGE_BUNDLE must be 0 or 1" >&2; exit 1; }

[[ "$revision" =~ ^[1-9][0-9]*$ ]] || { echo "error: PACKAGE_REVISION must be a positive integer" >&2; exit 1; }

for command in git make python3 sha256sum dtc fdtget; do
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
    command -v dpkg-deb >/dev/null || { echo 'error: dpkg-deb is required' >&2; exit 1; }
fi

base=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["base"])' "$meta")
expected_tree=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_tree"])' "$meta")
baseline_release=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["release"])' "$meta")
expected_release="${baseline_release%+}${local_version}"

git -C "$linux_git" cat-file -e "$base^{commit}" 2>/dev/null || {
    echo "error: the Linux repository does not contain base commit $base" >&2
    exit 1
}
python3 "$project/kernel/rc5-qcom-bridge-20261018/verify.py" "$linux_git"

mkdir -p "$output"
output=$(realpath "$output")
source_tree="$output/source"
object_dir="$output/build"
bundle="$output/bundle"
payload="$bundle"
[[ "$stage_bundle" == 1 ]] || payload="$output/package-input"

if [[ "$resume" == 1 ]]; then
    [[ "$(git -C "$source_tree" rev-parse --path-format=absolute --git-common-dir)" == \
       "$(git -C "$linux_git" rev-parse --path-format=absolute --git-common-dir)" ]] || {
        echo "error: source worktree belongs to a different Linux repository" >&2
        exit 1
    }
    source_status=$(git -C "$source_tree" status --porcelain --untracked-files=all)
    [[ -z "$source_status" && \
       ! -d "$(git -C "$source_tree" rev-parse --git-path rebase-apply)" ]] || {
        echo "error: cannot resume a modified worktree or an unfinished git am" >&2
        exit 1
    }
    echo "Resuming with existing source and build objects..."
else
    echo "Creating an isolated source worktree..."
    git -C "$linux_git" worktree add --detach "$source_tree" "$base"
    git -C "$source_tree" config user.name "${GIT_COMMITTER_NAME:-Zenbook A16 Builder}"
    git -C "$source_tree" config user.email "${GIT_COMMITTER_EMAIL:-builder@localhost}"
    while IFS= read -r patch; do
        [[ -n "$patch" ]] || continue
        git -C "$source_tree" am "$base_patch_dir/$patch"
    done < "$base_patch_dir/series"
    while IFS= read -r patch; do
        [[ -n "$patch" ]] || continue
        git -C "$source_tree" am "$bridge_patch_dir/$patch"
    done < "$bridge_patch_dir/series"
fi

actual_tree=$(git -C "$source_tree" rev-parse 'HEAD^{tree}')
[[ "$actual_tree" == "$expected_tree" ]] || {
    echo "error: patched source tree is $actual_tree; expected $expected_tree (resume requires completed patch application)" >&2
    exit 1
}

mkdir -p "$object_dir"
if [[ "$resume" == 0 || ! -s "$object_dir/.config" ]]; then
    "$source_tree/scripts/kconfig/merge_config.sh" -m -O "$object_dir" \
        "$project/kernel/rc5-qcom-bridge-20261018/config" \
        "$project/kernel/qcom-glymur-bridge.config"
fi
make -C "$source_tree" O="$object_dir" LOCALVERSION="$local_version" olddefconfig
release=$(make -s -C "$source_tree" O="$object_dir" LOCALVERSION="$local_version" kernelrelease)
[[ "$release" == "$expected_release" ]] || {
    echo "error: kernel release is $release; expected $expected_release" >&2
    exit 1
}

echo "Building $release with $jobs jobs..."
make -C "$source_tree" O="$object_dir" LOCALVERSION="$local_version" -j"$jobs" Image modules dtbs

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

if [[ "$stage_bundle" == 1 || "$build_rpm" == 1 || "$build_deb" == 1 ]]; then
    echo "Staging versioned build at $payload..."
    mkdir -p "$payload"
    make -C "$source_tree" O="$object_dir" LOCALVERSION="$local_version" \
        INSTALL_MOD_PATH="$payload" modules_install
    install -Dm644 "$object_dir/arch/arm64/boot/Image" "$payload/vmlinuz-$release"
    install -Dm644 "$dtb_file" "$payload/glymur-asus-zenbook-a16-ux3607oa.dtb"
    ln -sf "glymur-asus-zenbook-a16-ux3607oa.dtb" "$payload/$release.dtb"
    install -Dm644 "$object_dir/.config" "$payload/config-$release"
    rm -f "$payload/lib/modules/$release/build" "$payload/lib/modules/$release/source"
    headers_arg=$(python3 -c 'import shlex,sys; print(shlex.quote(sys.argv[1]))' "$payload/lib/modules/$release/build")
    make -C "$source_tree" O="$object_dir" LOCALVERSION="$local_version" run-command \
        KBUILD_RUN_COMMAND="\$(srctree)/scripts/package/install-extmod-build $headers_arg"
    install -m644 "$object_dir/.config" "$object_dir/System.map" "$payload/lib/modules/$release/build/"
    python3 "$project/packaging/zenbook-a16-kernel/package.py" metadata "$payload" "$meta" "$revision"
    install -d "$payload/usr/share/doc/linux-zenbook-a16"
    printf '%s\n' "$release" > "$payload/usr/share/doc/linux-zenbook-a16/kernel-release"
    install -Dm755 "$project/iso/glymur-fetch-firmware.sh" "$payload/glymur-fetch-firmware.sh"
    cp -a "$project/packaging" "$project/tweaks" "$payload/"
    mkdir -p "$payload/modules"
    ln -sfn "../lib/modules/$release" "$payload/modules/$release"
fi

if [[ "$build_rpm" == 1 ]]; then
    python3 "$project/packaging/zenbook-a16-kernel/package.py" build fedora "$payload" "$bundle/rpms"
fi
if [[ "$build_deb" == 1 ]]; then
    python3 "$project/packaging/zenbook-a16-kernel/package.py" build ubuntu "$payload" "$bundle/debs"
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

Nothing was installed or selected for boot. Review packaging/zenbook-a16-kernel/README.md
before installing all three packages together. Post-install hooks manage initramfs, DTB,
and hardware activation upon installation.
EOF
