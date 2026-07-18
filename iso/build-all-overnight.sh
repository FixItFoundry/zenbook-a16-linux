#!/usr/bin/env bash
# ============================================================================
# Overnight builder — Arch, Fedora, Ubuntu aarch64 images for the Zenbook A16
# glymur clean kernel (7.1.0-glymur-clean+) + firmware + KDE + NetworkManager.
# Each distro is independent (continue on failure); successes are gzipped to
# Downloads immediately; progress is written to BUILD-STATUS.txt.
# Run detached:  setsid nohup bash build-all-overnight.sh >build-all.log 2>&1 </dev/null &
# ============================================================================
set -u
GB=/home/jesse/glymur-build
DL=/mnt/c/Users/jesse/Downloads
FW=/mnt/c/Users/jesse/Documents/Antigravity/Zenbook-A16-Linux-on-ARM/Linux-X2-Project/firmware-staging
KREL="7.1.0-glymur-clean+"
VM=$GB/vmlinuz-7.1.0-glymur-clean+
INITRD=$GB/initrd-clean.img
DTB=$GB/glymur-a16-test55.dtb
MODS=$GB/mod_clean/lib/modules
DTBNAME=glymur-a16-test55.dtb
ST=$GB/BUILD-STATUS.txt
CMDBASE="rw clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime arm64.nopauth console=tty0 ignore_loglevel modprobe.blacklist=msm rd.timeout=60 panic=10 softlockup_panic=1 kvm-arm.mode=protected systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device"
SIZE_GB=14

say(){ echo "[$(date '+%m-%d %H:%M:%S')] $*"; echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$ST"; }

# ---- generic: build a bootable .img from a prepared rootfs dir ----
# $1 = rootfs dir   $2 = image path   $3 = distro label
mkimg(){
  local RD="$1" IMG="$2" NAME="$3" LOOP MNT RUUID
  say "$NAME: creating image $IMG (${SIZE_GB}G)"
  rm -f "$IMG"; truncate -s ${SIZE_GB}G "$IMG"
  parted -s "$IMG" mklabel gpt mkpart ESP fat32 1MiB 1025MiB set 1 esp on mkpart root ext4 1025MiB 100%
  LOOP=$(losetup --find --show --partscan "$IMG")
  mkfs.vfat -F32 -n ESP "${LOOP}p1" >/dev/null
  mkfs.ext4 -F -L "${NAME}root" "${LOOP}p2" >/dev/null
  MNT=$(mktemp -d)
  mount "${LOOP}p2" "$MNT"; mkdir -p "$MNT/boot"; mount "${LOOP}p1" "$MNT/boot"
  say "$NAME: copying rootfs into image"
  cp -a "$RD"/. "$MNT"/
  # the ESP is mounted at /boot; wipe any distro boot files the rootfs shipped, we add ours
  rm -rf "$MNT/boot"/* 2>/dev/null || true
  mkdir -p "$MNT/boot"
  # kernel + modules (already in rootfs from prep, but ensure) + dtb + initrd + firmware
  cp -f "$VM" "$MNT/boot/vmlinuz-glymur"
  install -Dm644 "$DTB" "$MNT/boot/dtbs/glymur/$DTBNAME"
  cp -f "$INITRD" "$MNT/boot/initramfs-glymur.img"
  RUUID=$(blkid -s UUID -o value "${LOOP}p2")
  mkdir -p "$MNT/boot/loader/entries"
  printf 'default glymur.conf\ntimeout 3\n' > "$MNT/boot/loader/loader.conf"
  cat > "$MNT/boot/loader/entries/glymur.conf" <<EOF
title      $NAME (glymur A16)
linux      /vmlinuz-glymur
initrd     /initramfs-glymur.img
devicetree /dtbs/glymur/$DTBNAME
options    root=UUID=$RUUID $CMDBASE
EOF
  # systemd-boot EFI stub: prefer the rootfs's, else the staged one
  local SB="$MNT/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
  [ -f "$SB" ] || SB="$GB/systemd-bootaa64.efi"
  if [ -f "$SB" ]; then
    mkdir -p "$MNT/boot/EFI/BOOT" "$MNT/boot/EFI/systemd"
    cp "$SB" "$MNT/boot/EFI/systemd/systemd-bootaa64.efi"
    cp "$SB" "$MNT/boot/EFI/BOOT/BOOTAA64.EFI"
  else
    say "$NAME: WARN no systemd-bootaa64.efi available (may not boot)"
  fi
  # fresh fstab (overwrite any shipped one so it matches this image's UUIDs)
  printf '# glymur image\nUUID=%s / ext4 rw,relatime 0 1\n' "$RUUID" > "$MNT/etc/fstab"
  printf 'UUID=%s /boot vfat rw,relatime 0 2\n' "$(blkid -s UUID -o value ${LOOP}p1)" >> "$MNT/etc/fstab"
  sync
  umount "$MNT/boot" "$MNT" 2>/dev/null
  losetup -d "$LOOP" 2>/dev/null
  rmdir "$MNT" 2>/dev/null
  say "$NAME: image built; compressing"
  pigz -f "$IMG"
  cp -f "$IMG.gz" "$DL/" && say "$NAME: DONE -> Downloads/$(basename "$IMG").gz ($(du -h "$IMG.gz"|cut -f1))"
}

# ---- firmware into a rootfs dir ----
addfw(){ local RD="$1"; mkdir -p "$RD/lib/firmware"; cp -a "$FW"/ath12k "$FW"/qca "$FW"/qcom "$FW"/audio "$RD/lib/firmware/" 2>/dev/null; cp -a "$FW"/adsp_dtb* "$RD/lib/firmware/" 2>/dev/null; }

# ---- modules into a rootfs dir ----
addmods(){ local RD="$1"; mkdir -p "$RD/lib/modules"; cp -a "$MODS/$KREL" "$RD/lib/modules/" 2>/dev/null; rm -rf "$RD/lib/modules/$KREL/build" "$RD/lib/modules/$KREL/source"; }

# =========================== ARCH (Manjaro-KDE reuse) ===========================
# Reuse Manjaro ARM's prebuilt KDE rootfs (no emulated pacman install) + our kernel.
build_arch(){
  say "ARCH(Manjaro-KDE): === START ==="
  local RD=$GB/rd_arch XZ=$GB/manjaro-kde.img.xz IMG2=$GB/manjaro-kde.img URL LOOP MNT
  if [ -f "$IMG2" ] && [ "$(stat -c %s "$IMG2" 2>/dev/null || echo 0)" -gt 2000000000 ]; then
    say "ARCH: reusing already-decompressed $IMG2"
  else
    URL=$(curl -fsSL https://api.github.com/repos/manjaro-arm/generic-efi-images/releases 2>/dev/null | grep -oE 'https[^"]*kde-plasma[^"]*\.img\.xz' | sort | tail -1)
    [ -n "$URL" ] || { say "ARCH: FAIL could not find Manjaro KDE url"; return 1; }
    if [ ! -s "$XZ" ]; then say "ARCH: downloading $URL"; curl -fL -o "$XZ" "$URL" || { say "ARCH: FAIL download manjaro"; return 1; }; fi
    say "ARCH: decompressing"
    rm -f "$IMG2"; unxz -c "$XZ" > "$IMG2" || { say "ARCH: FAIL unxz"; return 1; }
  fi
  LOOP=$(losetup --find --show --partscan "$IMG2") || { say "ARCH: FAIL losetup"; return 1; }
  MNT=$(mktemp -d)
  # root partition is the last/largest; try p2 then p1
  mount "${LOOP}p2" "$MNT" 2>/dev/null || mount "${LOOP}p1" "$MNT" 2>/dev/null || { say "ARCH: FAIL mount manjaro root"; losetup -d "$LOOP"; return 1; }
  rm -rf "$RD"; mkdir -p "$RD"
  say "ARCH: extracting Manjaro KDE rootfs"
  cp -a "$MNT"/. "$RD"/ 2>/dev/null
  umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null
  [ -d "$RD/usr/bin" ] || { say "ARCH: FAIL manjaro rootfs looks empty"; rm -rf "$RD"; return 1; }
  addmods "$RD"; addfw "$RD"
  mkimg "$RD" "$GB/arch-manjaro-kde.img" "arch-manjaro"
  rm -rf "$RD" "$IMG2"
  say "ARCH(Manjaro-KDE): === END ==="
}

# =========================== FEDORA (KDE Live reuse) ===========================
build_fedora(){
  say "FEDORA(KDE-Live reuse): === START ==="
  local RD=$GB/rd_fedora ISO=/mnt/c/Users/jesse/Downloads/Fedora-KDE-Desktop-Live-44-1.7.aarch64.iso
  local EROFS=$GB/fed.erofs SQD=$GB/fed_sqroot MNT2 RIMG
  local TARBALL=$GB/fedora-rootfs.tar.gz
  # PREFERRED: rootfs extracted natively on the A16 (WSL can't read Fedora's EROFS)
  if [ -f "$TARBALL" ]; then
    say "FEDORA: using A16-extracted rootfs ($TARBALL)"
    rm -rf "$RD"; mkdir -p "$RD"
    tar -C "$RD" -xpf "$TARBALL" 2>/dev/null || { say "FEDORA: FAIL untar A16 rootfs"; return 1; }
    [ -d "$RD/usr/bin" ] || { say "FEDORA: FAIL A16 rootfs empty"; rm -rf "$RD"; return 1; }
    addmods "$RD"; addfw "$RD"
    mkimg "$RD" "$GB/fedora-glymur-kde.img" "fedora"
    rm -rf "$RD"
    say "FEDORA: === END (from A16 rootfs) ==="
    return 0
  fi
  [ -f "$ISO" ] || { say "FEDORA: FAIL iso not found"; return 1; }
  say "FEDORA: extracting LiveOS/squashfs.img (EROFS) from ISO"
  bsdtar -xOf "$ISO" LiveOS/squashfs.img > "$EROFS" 2>/dev/null && [ -s "$EROFS" ] || { say "FEDORA: FAIL extract erofs"; return 1; }
  rm -rf "$SQD"; mkdir -p "$SQD"
  say "FEDORA: fsck.erofs extract"
  fsck.erofs --extract="$SQD" "$EROFS" >/dev/null 2>&1 || { say "FEDORA: FAIL fsck.erofs"; return 1; }
  RIMG=$(find "$SQD" -name 'rootfs.img' | head -1)
  [ -n "$RIMG" ] || { say "FEDORA: FAIL no rootfs.img inside erofs"; return 1; }
  MNT2=$(mktemp -d)
  mount -o loop,ro "$RIMG" "$MNT2" || { say "FEDORA: FAIL mount rootfs.img"; return 1; }
  rm -rf "$RD"; mkdir -p "$RD"
  say "FEDORA: copying KDE rootfs"
  cp -a "$MNT2"/. "$RD"/ 2>/dev/null
  umount "$MNT2" 2>/dev/null; rmdir "$MNT2" 2>/dev/null
  [ -d "$RD/usr/bin" ] || { say "FEDORA: FAIL rootfs empty"; rm -rf "$RD" "$SQD" "$EROFS"; return 1; }
  addmods "$RD"; addfw "$RD"
  mkimg "$RD" "$GB/fedora-glymur-kde.img" "fedora"
  rm -rf "$RD" "$SQD" "$EROFS"
  say "FEDORA(KDE-Live reuse): === END ==="
}

# =========================== UBUNTU (desktop Live reuse) ===========================
build_ubuntu(){
  say "UBUNTU(desktop-Live reuse): === START ==="
  local RD=$GB/rd_ubuntu ISO=/mnt/c/Users/jesse/Downloads/ubuntu-26.04-desktop-arm64.iso
  local SMIN=$GB/u-min.squashfs SDE=$GB/u-de.squashfs
  [ -f "$ISO" ] || { say "UBUNTU: FAIL iso not found ($ISO)"; return 1; }
  say "UBUNTU: extracting casper squashfs layers from ISO"
  bsdtar -xOf "$ISO" casper/minimal.squashfs > "$SMIN" 2>/dev/null && [ -s "$SMIN" ] || { say "UBUNTU: FAIL extract minimal.squashfs"; return 1; }
  bsdtar -xOf "$ISO" casper/minimal.de.squashfs > "$SDE" 2>/dev/null && [ -s "$SDE" ] || say "UBUNTU: WARN no desktop layer (base only)"
  rm -rf "$RD"
  unsquashfs -f -d "$RD" "$SMIN" >/dev/null 2>&1 || { say "UBUNTU: FAIL unsquashfs minimal"; return 1; }
  [ -s "$SDE" ] && { say "UBUNTU: overlaying desktop (GNOME) layer"; unsquashfs -f -d "$RD" "$SDE" >/dev/null 2>&1; }
  [ -d "$RD/usr/bin" ] || { say "UBUNTU: FAIL rootfs empty"; rm -rf "$RD" "$SMIN" "$SDE"; return 1; }
  addmods "$RD"; addfw "$RD"
  mkimg "$RD" "$GB/ubuntu-glymur-gnome.img" "ubuntu"
  rm -rf "$RD" "$SMIN" "$SDE"
  say "UBUNTU(desktop-Live reuse): === END ==="
}

# ---- run selected targets (default all). Usage: build-all.sh [arch] [fedora] [ubuntu] ----
echo "======== RUN $(date) targets=[${*:-arch fedora ubuntu}] ========" >> "$ST"
say "kernel=$KREL  images -> $DL"
for t in ${*:-arch fedora ubuntu}; do
  case "$t" in
    arch)   build_arch   || say "ARCH: aborted" ;;
    fedora) build_fedora || say "FEDORA: aborted" ;;
    ubuntu) build_ubuntu || say "UBUNTU: aborted" ;;
    *) say "unknown target: $t" ;;
  esac
done
say "======== RUN DONE $(date) ========"
