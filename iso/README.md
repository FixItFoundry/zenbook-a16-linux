# Distro images for the Zenbook A16 (aarch64)

Goal: bootable **Ubuntu**, **Fedora**, and **Arch** media for the A16 carrying the glymur
v7.1 kernel + the `test55-usb` DTB, so people can try the semi-working platform without
hand-building everything.

## Kernel artifacts (shared by all three)

You already have raw kernel artifacts in the project folder — **no repackaging needed** for
the Arch image, and they can be injected raw into the Ubuntu/Fedora images too:

- `vmlinuz-7.1.0-glymur-full-patched`
- `7.1.0-glymur-full-plus-modules.zip` (contains `lib/modules/7.1.0-glymur-full/`)
- `boot-kit/test55-usb.dtb` (the daily-driver device tree)

**Mandatory boot cmdline:** `efi=noruntime` (a missing one warm-resets early on this firmware).
Display comes up on **simplefb** (UEFI framebuffer) — no native panel / brightness yet.

## Boot-testing note

The glymur kernel targets `sm8750` hardware, so these images **only meaningfully boot on the
A16 itself** (USB stick). A generic `qemu-system-aarch64` VM can't exercise the glymur kernel —
it would only test the stock distro kernel. So: `dd` to USB, boot the A16.

Firmware (Wi-Fi/audio/etc.) is **not** bundled — supply it from your own device under
`/lib/firmware/qcom/glymur/` (see [`../firmware/README.md`](../firmware/README.md)).

---

## Ubuntu  — base you have: `ubuntu-26.04-desktop-arm64.iso`
Proper arm64 live ISO. `ubuntu/build-ubuntu-iso.sh` repacks it with the glymur kernel + DTB.
Cleanest if you package the kernel as a `.deb` (the A16 already runs Ubuntu, so you likely have
one); otherwise inject the raw `vmlinuz` + modules via the hook.

## Fedora — base you have: `Fedora-KDE-Desktop-Live-44-1.7.aarch64.iso`
Proper aarch64 live ISO. `fedora/build-fedora-iso.sh` uses `mkksiso` (arch-neutral — runs fine
on x86 Fedora WSL) to inject a custom kickstart + kernel + DTB. Needs the kernel as an aarch64
`.rpm`, **or** adapt the kickstart `%post` to drop the raw `vmlinuz` + `/lib/modules` you already
have.

## Arch — no aarch64 ISO exists; use Arch Linux ARM (ALARM)
> `cachyos-desktop-linux-*.iso` is **x86_64** — CachyOS has no ARM build, so it can't boot the
> A16. Don't use it.

Arch on ARM is a **rootfs tarball**, not an ISO. `arch/build-arch-image.sh` unpacks the ALARM
generic aarch64 rootfs, drops in your raw glymur `vmlinuz` + modules + DTB, builds a fat
(non-hostonly) initramfs, and writes a UEFI-bootable **`.img`** you `dd` to USB.

Download the ALARM base (pick one; verify current URL on the ALARM site):
- `http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-generic.tar.gz`

Run (in Fedora WSL, as root):
```bash
sudo ./arch/build-arch-image.sh \
   ArchLinuxARM-aarch64-generic.tar.gz \
   ../../vmlinuz-7.1.0-glymur-full-patched \
   ../../7.1.0-glymur-full-plus-modules.zip \
   ../../boot-kit/test55-usb.dtb
```
If your x86 WSL can't run `mkinitcpio` (no aarch64 binfmt), the script sets everything up and
tells you to generate the initramfs on the A16 after first boot:
`mkinitcpio -k 7.1.0-glymur-full -g /boot/initramfs-glymur.img --no-hostonly`.

---

## Suggested validation order
1. **Arch (ALARM .img)** — no packaging step, consumes your raw artifacts directly. Fastest to a
   testable image once the tarball finishes downloading.
2. **Ubuntu** — closest to the working system (Ubuntu + your kernel `.deb`).
3. **Fedora** — once you have (or generate) an aarch64 kernel RPM.

Once an image boots on the A16, attach it to a **GitHub Release** (≤2 GB/asset) — never commit
multi-GB images to the repo.
