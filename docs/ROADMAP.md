# Roadmap & known-not-working

This is a **semi-working** bring-up of Linux on the ASUS Zenbook A16 (UX3607OA, Snapdragon
X2 Elite / `glymur` / sm8750). Lots works; several things don't yet. Contributions and expert
eyes are very welcome — see `CONTRIBUTING.md` and open an Issue/Discussion.

## Working
- Boot to desktop (systemd-boot, raw arm64 Image + DTB) on Arch/Manjaro-KDE, Ubuntu, Fedora.
- Keyboard, trackpad, touchpad, keyboard backlight (steady, via `asus-kbd-init`).
- USB-C + USB-A (incl. USB NIC), USB storage, RTC.
- Wi-Fi 7 (Qualcomm QCC2072, ath12k) — with correct firmware + a forced regdomain.
- Battery percentage + USB-PD charging (`soccp_glink` + `ps883x`).
- Audio: speakers (4.0, woofers + tweeters via AudioReach topology + WirePlumber upmix) and
  the internal DMIC. See `../LOCAL-TWEAKS.md`.

## Not working yet / help wanted

### CPU frequency scaling (SCMI) — HIGH IMPACT
`scmi-cpufreq` fails to probe (`-110`, SCMI perf protocol timeout); cores run at the boot
clock, which is a major cause of UI sluggishness (on top of software rendering). The SCMI perf
handshake with firmware times out on the 7.1 tree. **Newer in-kernel SCMI work (7.x) may help
— worth investigating a backport or a fresher SCMI stack.** Tracked for post-launch.

### PMIC temperature alarm (SPMI) — `spmi-temp-alarm`
`qcom-spmi-temp-alarm` bring-up is outstanding (thermal/temperature alarm via the SPMI PMIC).
Related to the SPMI PMIC-arb transaction warnings seen at boot. Also likely has relevant
in-kernel 7.x support to pull in. Tracked for post-launch.

### GPU / display acceleration
Still on software rendering (simpledrm/efifb). Adreno X2 + DPU bring-up is a separate, larger
effort (the `docs/gpu-re/` notes cover the VMID/SMMU/ACPI investigation). The eDP regulator is
likely blocked by the same over-reserved TLMM gpio-range pattern used to free the USB pins.
Unlocks DP / USB-C display **and** DisplayPort audio.

### Charging negotiation (UCSI/PD)
`ucsi_glink … PPM init failed` — the UCSI/PD power-management handshake has a firmware-response
gap. Battery % + basic charging work; full PD negotiation does not.

### Headphone jack / DisplayPort audio
Jack detect exists but there's no rx-macro/WCD9395 codec in the DT yet; DP audio backends exist
but are gated on GPU/DRM.

## Notes for contributors
- The kernel is pinned to **v7.1** + local patches; 7.2/linux-next broke the bring-up chain.
- `soccp_glink` is a custom (out-of-tree-origin) battery driver, now built in-tree.
- Firmware is **not** shipped here — pull it from your own device's Windows/WoA install
  (`ath12k`, `qcom/glymur`, regulatory.db). See `../LOCAL-TWEAKS.md` §1.
- This project was developed with heavy AI assistance; the maintainer is not a kernel dev by
  trade. Treat findings as field notes, verify before relying on them.
