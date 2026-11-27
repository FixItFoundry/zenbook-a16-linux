# Linux 7.3.6 A16/Qualcomm candidate

Local source port of the full A16 stack to **Linux v7.3.6**. The current
183-patch queue (`a25b51b1ceda`, target **package revision 14**) retires
`0012` (`glymur_pci_skip`), drops `clk_ignore_unused`/`pd_ignore_unused`/
`glymur_pci_skip=5` from packaged cmdline defaults, and adds the GMU driver +
crypto-disable `sync_state` fixes (`0207`–`0213`) that unlocked full
`APSS + CXSD + AOSD + DDR` `s2idle` collapse on the A16. Native package
transactions and long-term stability acceptance remain open; nothing here
installs or selects a kernel.

| Identity | Value |
|---|---|
| Upstream base | `v7.3.6`, commit `1a0388846138eda9f6eb4258ff227a223afc2f52` |
| Ordered residual queue | [183 patches](../../patches/stable/README.md) |
| Patched source tree | `a25b51b1ceda63f568d36f0dd4847c0787dfcfaa` |
| Recorded release | `7.3.6-ZenbookA16-20261022-final1+` |
| Package revision 6 | `7.3.0-ZenbookA16-20261022-final1-a16pkg6+` (`bd1327aac6e1`, prior to `0156`–`0158`) |
| Package revision 7 | `7.3.0-ZenbookA16-20261022-final1-a16pkg7+` (`f5b887e39ef7`) |
| Package revision 8 | `7.3.0-ZenbookA16-20261022-final1-a16pkg8+` (`e6413608c546`) |
| Package revision 12 | `7.3.0-ZenbookA16-20261022-final1-a16pkg12+` (`c9073bc3daaf`, current default) |
| Package revision 13 | `7.3.6-ZenbookA16-20261022-final1-a16pkg13+` (`91e3f1250937`, one-shot verified; `0207`–`0213` tested live on boot `6c95f197`) |
| Package revision 14 (candidate) | `7.3.6-ZenbookA16-20261022-final1-a16pkg14+` (`a25b51b1ceda`, `0012` dropped, clean cmdline) |

The queue retains the 64-patch A16 baseline, 40-patch Qualcomm bridge and
10-patch camera/microphone overlay (minus three complete patches already in
7.3), plus 32 patches (`0112`–`0143`) integrating the local GDSC unwind RFC,
genpd/AudioReach/Q6DMA overlays, and reviewed LKML / `qcom-next` /
`glymur-laptops` fixes through 2026-11-03 (including Konrad Dybcio's Glymur USB3
QMP PHY settings update as `0143`). Original authors and trailers are preserved;
see [upstream credits](../../UPSTREAM-CREDITS.md).

## Verify without making commits

```sh
python3 kernel/stable/replay.py /path/to/linux-git
```

The verifier checks the manifest and applies all 183 patches in a temporary Git
index, requiring the exact source tree above. It leaves HEAD, the normal index
and working files alone. It creates Git tree/blob objects, not commits.

## Build after reviewing the port

Use the existing [native Linux build prerequisites and package contract](../../packaging/zenbook-a16-kernel/README.md).
Supply a Linux Git repository containing the pinned base and a new output path:

```sh
# Fedora RPMs and portable bundle:
JOBS=4 PACKAGE_REVISION=6 \
  ./kernel/stable/build.sh /path/to/linux-git /path/to/final-output

# Ubuntu/Debian packages instead:
JOBS=4 PACKAGE_REVISION=6 BUILD_RPM=0 BUILD_DEB=1 \
  ./kernel/stable/build.sh /path/to/linux-git /path/to/final-deb-output
```

The build helper uses an isolated worktree and `git apply --index` so both mail
patches and the raw camera diffs apply without making commits. HEAD stays on
the pinned upstream base; the staged index records the complete source tree.
The helper checks that tree, runs `olddefconfig`, requires every setting in [required.config](required.config),
checks the release, and builds Image, modules, headers and the matching A16 DTB.
Retry a failed build with `--resume` and the same environment/output directory;
changes relative to the expected staged tree and incomplete patch application
are rejected.

[config](config) is the actual compiled rc5 camera pkg3 configuration with a new
local release. It is an input for 7.3 `olddefconfig`, not a claim that Kconfig has
been resolved on the new base. The manifest's `promotion_date` supplies the
existing package version format; it does not record hardware promotion.

`camera_enabled: true` makes the shared packager omit its legacy camera
blacklist and tells boot hooks to remove those camera modules from inherited
blacklists, preserving other blocked modules. Older recipes retain their command
line and inherited blacklist behavior. DSP policy, sleep restrictions and development boot settings
are retained, including `selinux=0`; this is not a production security sign-off.

## Validation and limits

Source replay and local package/build-helper regression checks pass. The real
AudioReach helper's shrinking-channel-map self-check passes on the ported source.
Camera/DMIC source and board settings are unchanged from the rc5 pkg3 candidate.
The 4 mA/pull-down/slew-1 pin setting remains experimental while its cold-boot
and simultaneous camera/microphone recording tests are pending.

Package revision 6 was compiled, staged by hand and booted on the A16; see the
November 12 carry-forward section below. Native RPM/DEB transactions, external-module headers, physical update/rollback
and hardware acceptance remain open. See the [transition checklist](../../docs/kernel-tracks.md).

## RPMh and RTC additions, November 12

Preserve a mode already applied by regulator registration. Fixed/legacy/fixed
diagnostic boots retained FAST; the legacy overwrite did not reproduce because
ENABLE was zero at inference. Host tests cover the overwrite branch. No physical
rail or audio-quality improvement is established.

Release the RTC parent wake source when the timer worker cannot read time.
The GLINK read timeout remains unresolved; this balances the wake-source lifetime.

Select RTC ops without set_time unless allow-set-time is enabled. This stops NTP
retrying unsupported writes and preserves the existing writable opt-in.
The failed GLINK v2 diagnostic driver is excluded.

Both tracks pass source replay and host checks. Hardware observations cover
only the A16; other machines using these shared drivers were not tested.
The successful attended sleep trials used
the diagnostic image described in [the hardware record](../../docs/hardware.md).

## Display, wireless and camera carry-forward, November 12

Patches `0147`–`0155` add eDP rate-set corrections, the pending QCC2072 Bluetooth and M.2 power-sequencing patches, mainline M.2 Wi-Fi/Bluetooth wiring, and RGB camera MCLK4 at 6 mA. They are the nine
changes the working revision-2 build already carried, placed after the RPMh/RTC
fixes.

Built as package revision 6 on November 12. It boots on the A16 with the display and Wi-Fi working; an unexplained reset between two boots is unresolved, so stability is not accepted.
The camera clock change was checked separately on revision 1: microphone-triggered
banding disappeared at 6 mA and returned at 2 mA. That does not establish IR
capture or microphone audio quality.

## HM1092 7.3 pad format and PMH0101 IR emitter, November 14

Patches `0156`–`0157` wire `.set_fmt = v4l2_subdev_get_fmt` on `hm1092` (`v7.3` lacks `v7.4-rc1`'s `48d8b2418f55` core fallback) and enable ganged PMH0101 MVFLASH channels 1+4 (`ir_led`, 350 mA torch / 700 mA flash) plus `vreg_bob1_e0` parent supplies for PMH0101 L6–L9 and PM8010 L3/L4/L7. Verified on the A16 running revision 6 via runtime module/DT overlay (`cam`, PipeWire, and dark-room locked-exposure IR illumination A/B/A); a full packaged image from `68c6fb5921f9` has not yet been installed.

## eDP link training fallback, November 14

Patch `0158` keeps `msm_dp_ctrl_on_link()` from falling back to a lane count or rate that can't carry the eDP mode; it retries at the previous parameters instead. On revision 6, 6 of 100 Hyprland DPMS wakes left the panel dark after channel equalisation failed at 4 lanes × HBR2 and training fell back to 2 lanes (once 1). With the patched `msm.ko` on revision 6, 100 wakes produced 7 equalisation failures, each recovered on the first retry at 4 lanes. Sent upstream as [20261115000021.78869-1-jesse.casco@gmail.com](https://lore.kernel.org/r/20261115000021.78869-1-jesse.casco@gmail.com). Package revision 7, built from `f5b887e39ef7`, is installed as the default; on it, 100 wakes all trained at 4 lanes (12 retried after an equalisation failure).

## CAMSS lite CSID paths, November 21

Patch `0159` is 1/2 of the X1E80100 lite CSID series ([v1](https://lore.kernel.org/r/cover.1795196107.git.jesse.casco@gmail.com)): the lite CSIDs get the `vfe_lite_csid`/`vfe_lite_cphy_rx` clocks. Patch `0160` drops CSID2, which has no VFE, so each CSID sits at the index of the VFE it feeds; it is now Bryan O'Donoghue's [routing fix 1/3](https://lore.kernel.org/all/20261122-camss-routing-fixes-v1-1-0deeeaca2622@kernel.org/), which replaced our unsent v2 2/2 with the same change. The lite CSID entities become `msm_csid2` and `msm_csid3`. The local `0161` lifts `0107`'s CSID0/VFE0 limit and registers the full X1E80100 TPG, CSID and VFE tables on Glymur. On revision 7 with the resulting `camss.c` loaded as a module, the HM1092 IR sensor streamed through all four CSID/VFE pairs and the OV02C10 RGB sensor through LITE1, and libcamera captured from both cameras. Package revision 8, built from `e6413608c546`, is installed as the default; on its first boot the same camera checks passed, and the display, Wi-Fi, Bluetooth and 20 DPMS cycles came up as on revision 7.

## M.2 Bluetooth v9 and the CSID2 patch swap, November 23

Patch `0153` is now [monza-wireless v9 1/8](https://lore.kernel.org/all/20261123-monza-wireless-v9-1-450d7d764aea@oss.qualcomm.com/) (code unchanged since v8). It resolves the UART's OF graph remote endpoint to detect the M.2 connector and ties the `uart` pwrseq descriptor to the Bluetooth serdev device instead of the UART controller. `0160` is Bryan O'Donoghue's CSID2 removal; the tree is unchanged by that swap. Only `drivers/bluetooth/hci_qca.c` differs from `e6413608c546`. On revision 8, an `hci_uart.ko` built with v9 1/8 was swapped in at runtime: the QCC2072 probed and scanned, and 10 power off/on and 10 serdev unbind/bind cycles all came back, with the connector's `uart-enable` count returning to 1 and Wi-Fi staying up. No package has been built from this tree yet.

## External displays, openSUSE carry-overs, and `iris` video, November 27

Legacy `0062` is dropped (`0120` context refreshed) and replaced by Ritesh Kumar's Glymur DP PHY v8 series (`0162`–`0169`), HDMI HPD pinctrl on `&mdss_dp2` (`0170`), 27 patches from Michi (`@scalpel4k`)'s openSUSE `kernel-qcom-laptops` queue (`0171`–`0197`), the Glymur DPU `LM_4`–`LM_7` → `DSPP_4`–`DSPP_7` mapping (`0198`), and four `iris` fixes (`0199`–`0202`: suspend deadlock, driver-removal work cancel, firmware reload on session command timeout, and firmware-reported output buffer count). Kconfig adds `CONFIG_CLK_GLYMUR_VIDEOCC=m`, `CONFIG_QCOM_SCMI_GENERIC_EXT=m`, `CONFIG_DEVFREQ_GOV_REMOTE=m`, `CONFIG_SCMI_QCOM_MEMLAT_DEVFREQ=m`, `CONFIG_QCOM_SPEL=m`, `CONFIG_NETCONSOLE_EXTENDED_LOG=y`, and the buddy hardlockup detector; `required.config` adds `CONFIG_CLK_GLYMUR_VIDEOCC=m` and `CONFIG_VIDEO_QCOM_IRIS=m`.

Package revision 12 (`7.3.0-ZenbookA16-20261022-final1-a16pkg12+`, tree `c9073bc3daaf`) passed full `ci.py`, clean build (0 AER), full hardware validation on boot `f3bdc616` (3 simultaneous displays with user-confirmed picture, DPMS cycles, USB3 read without `0062`, `iris` 60/60 GStreamer decode + 5/5 hang recovery + 20/20 H264 encode, Wi-Fi, BT, upstream `MM1`/`MM2` audio, cameras, `memlat`, `SPEL`), and a 24-round load/idle soak (12 balanced + 12 boost, 0 resets, 0/0 PCIe AER, `taint=0`). It is promoted as the default boot entry on the test A16. Load-correlated VIA USB-C PD-hub resets, physical hotplug, 4K60, suspend/resume, and long-term reset stability remain open; see [`docs/current-build.md`](../../docs/current-build.md).

## Linux 7.3.6 fast-forward, HDMI/DP audio, and power/deep-sleep fixes, November 27

Rebased the stable base from `v7.3` (`c03c1a14507d`) to **`v7.3.6`** (`1a0388846138`), dropping 28 patches already merged in `7.3.1`–`7.3.6` (`0006`, `0008`, `0010`, `0015`, `0018`, `0029`–`0033`, `0037`–`0038`, `0043`, `0081`, `0122`–`0130`, `0133`–`0134`, `0137`–`0138`, `0200`) and refreshing five overlapping patches (`0028`, `0078`, `0152`, `0178`, `0184`).

Added four patches on top:
- `0203`: HDMI/DisplayPort audio DAI links (`dp0`/`dp1`/`dp2-dai-link`) in the A16 board DTS, paired with UCM `HDMI0`/`HDMI1`/`HDMI2` devices (`tweaks/usr/share/alsa/ucm2/Qualcomm/glymur/HiFi.conf`) and scoped WirePlumber rules (`51-glymur-ucm.conf`).
- `0204` (from `omacom/omarchy-pkgs#3689`): set `scmi-qcom-memlat-devfreq` `profile->polling_ms = 0` to stop the 1,500 Hz SCMI mailbox polling storm.
- `0205` (from `omacom/omarchy-pkgs#3738`): raise `cluster_cl5` `min-residency-us` to `1000000000` (1000 s) in `glymur.dtsi` so runtime cpuidle avoids `cluster_cl5` while `s2idle` still enters `domain_ss3` cleanly.
- `0206` (from `omacom/omarchy-pkgs#3738`): drop `wakeup-event-action = <EV_ACT_DEASSERTED>` on `switch-lid` to prevent open-lid `s2idle` abort after CX collapse.

Matching userspace power management and sleep hooks (`tweaks/etc/udev/rules.d/90-asus-zenbook-a16-power.rules` and `tweaks/usr/lib/systemd/system-sleep/zenbook-a16-sleep`, adapted from `omacom/omarchy-pkgs#3690`, `#3738`, `#3740`) are staged by `install-hooks.sh` and model-gated by `activate-hardware.sh`.

Package revision 13 (`7.3.6-ZenbookA16-20261022-final1-a16pkg13+`, tree `91e3f1250937`) passed full `ci.py` + replay and booted cleanly on the A16 (boot `e1814992`, `taint=0`, 0 failed units, `btrfs_errors=0`, 0/0 NVMe AER, `scmi_err=0`): 3 displays active from boot (`dpu_refusals=0`, `phy_poweron_err=0`), `HDMI0`/`HDMI2`/`Speaker` PipeWire playback verified (`audio_dsp_errors=0`; `Mic` capture verified on prior `7.3.6` boot `71d0f0a1`), `scmi-qcom-memlat-devfreq` at `polling_interval=0` with `0` `apss_cpucp_mbox` IRQs over 3 s, `cluster_cl5` `min-residency-us = 1000000000` with `Usage=0, Rejected=0` across all three clusters, `switch-lid` without `wakeup-event-action`, and `90-asus-zenbook-a16-power.rules` active (`0004:00:00.0`/`0004:01:00.0` `wakeup=disabled`, idle USB controllers and SD reader autosuspended, SD poll `15000 ms`).

## Full `s2idle` deep sleep (`APSS + CXSD + AOSD + DDR`), November 27

Added seven `sync_state` fixes (`0207`–`0213`, adapted from `omacom/omarchy-pkgs` `2170`–`2174`, `2178`, `2210`):
- `0207`–`0212`: attach a platform driver (`adreno_gmu`) to `3d6c000.gmu` so `gcc`, `gxclkctl`, and `gpucc` reach `state_synced=1` and power down unused `cx` GDSCs.
- `0213`: disable broken QCE `crypto@1dfa000` in `glymur.dtsi`/`hamoa.dtsi` so `aggre1_noc`/`mc_virt` reach `state_synced=1` and drop the boot-time DDR/CX interconnect floor vote.
- Retired `0012` (`glymur_pci_skip`), dropped `clk_ignore_unused`, `pd_ignore_unused`, and `glymur_pci_skip=5` from `packaging/zenbook-a16-kernel/package.py` `CMDLINE`, and updated `51-glymur-ucm.conf` `*Speaker*` `session.suspend-timeout-seconds` from `0` → `2` so PipeWire closes `pcm0p` when idle and `zenbook-a16-sleep` can runtime-suspend SoundWire across `s2idle` (while `0058` keeps SoundWire `power/control=on` while awake).

Verified on `loazen` (boot `6c95f197`, `pkg13` + signed `msm.ko`/DTB from `0207`–`0213`, `glymur_pci_skip=0`, no `clk_ignore_unused`/`pd_ignore_unused`): `unsynced_count=0`, 258 s open-lid `systemctl suspend` achieved **97.7% `APSS`/`CXSD`/`AOSD`/`DDR` residency** (`252.06 s` each, `Count: 3`), with clean resume of PCIe5 NVMe (`Gen.4 x4`, `btrfs_err=0`, `nvme_aer=0/0`), PCIe4 Wi-Fi (`Gen.3 x1`, `ath12k` MHI → connected), Bluetooth (`Powered: yes`), and SoundWire speakers (`SPEAKER_RESUME_PW=PASS`, `tainted=0`). Clean `pkg14` package build from `a25b51b1ceda` and closed-lid wake / 10-minute wattage tests remain open.
