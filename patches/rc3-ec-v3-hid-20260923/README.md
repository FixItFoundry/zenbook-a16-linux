# A16 EC v3 + HID keyboard integration

Base: `ecb5f3d03d5b` in the RC3 integrated kernel tree. This base already
contains the local HID keyboard patch (`0167d2d43218`). Apply `series` in
order. Patches 1-3 are Konrad Dybcio's v3 EC series, downloaded from
https://patchew.org/linux/20260923-topic-asus._5Fec-v3-0-2bf3bb9da879@oss.qualcomm.com/.
Patch 4 keeps the existing HID driver as the sole owner of
`asus::kbd_backlight`, removing the EC LED endpoint.

Source branch: `codex/rc3-ec-v3-hid-20260923` at `2e201e42529f` in
`/home/jcasco/kernel-build/wt-rc3-ec-v3-hid-20260923`.
Build config: `/home/jcasco/kernel-build/obj-rc3-ec-v3-hid-20260923/.config`,
release suffix `-ZenbookA16-20260923-ecv3hid1`.

Verified: both modified driver objects compile, the A16 DTB compiles and
contains `embedded-controller@76`, and the integration diff passes
`git diff --check`. This is source and targeted-build validation only. No
kernel Image or modules were built or installed; no GRUB entry was added;
the branch has not been booted. EC probe, fan RPM, warm reboot, suspend,
and keyboard LED behavior need physical validation before replacing a
working boot entry. The v3 EC driver reports fan speed but has no PWM fan
control interface.
