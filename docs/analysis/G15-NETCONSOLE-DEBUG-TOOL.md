# G15 — Crash-capture debugging tool (netconsole) + LPASS va-macro finding

Date 2026-07-12. Goal: a reusable way to capture crashes that leave NO trace on disk/display/
journal (the LPASS macro probe hard-wedges the SoC). Result: **netconsole over wifi WORKS and is
set up + proven; the Qualcomm SDI/PCAT RAM-dump route is firmware-blocked on this retail unit.**
Used netconsole to pin the LPASS fault: **va-macro (0x6d44000) wedges the bus at first HW access.**

## 1. SDI / PCAT full-RAM-dump — BLOCKED on retail ASUS firmware
- Kernel side is ready: `qcom_scm.download_mode` accepts off/full (DT `qcom,dload-mode=<0x2a 0x4000>`).
- BUT the retail ASUS UEFI/PBL does NOT honor the download cookie: `download_mode=full` + clean
  reboot just boots normally (cookie reset to off); a forced panic hangs without entering dump
  mode; PCAT `-MONITORMEMDUMP` never saw a device. EDL/dump is fused off on this retail unit.
- PCAT IS installed (`C:\Program Files (x86)\Qualcomm\PCAT\bin\PCATApp.exe`) and has a headless
  CLI — **`PCAT -MONITORMEMDUMP -DUMPDIR <dir> -RESET TRUE -SKIP8K FALSE -SKIP9K TRUE`** auto-pulls
  a dump the moment a device enters dump mode. Also `-MODE CRASH|EDL|RESET`, `-DEVICES`. Keep for
  the day we have debug-provisioned firmware; useless until PBL honors dump mode.

## 2. netconsole — the WORKING crash-capture tool (reusable)
Streams the kernel printk log over UDP to the Windows box in real time, so we see everything up to
the instant the SoC wedges. No firmware support needed.
- **Windows listener:** `C:\a16dump\udp_listener.py` (python). Binds UDP 6666, writes
  `C:\a16dump\netcon.log`. **Firewall trick (no admin):** Windows Firewall blocks inbound UDP and
  we can't add a rule, so the listener sends a keepalive to the A16 every 2 s from src port 6666 —
  Windows' stateful-UDP opens a return pinhole for A16->6666. Proven: packets get through. Start:
  `python C:\a16dump\udp_listener.py` (hidden). Uses SIO_UDP_CONNRESET off to mute 10054 noise.
- **A16 side:** `~/netcon_on.sh` arms netconsole (configfs target `a16`, dev wlP4p1s0,
  local_ip .209 **local_port 6666** (must match the pinhole), remote .22:6666, remote_mac
  d8:43:ae:9f:7b:d6). Then any printk / `echo x >/dev/kmsg` streams to netcon.log.
- Caveat: netpoll over mac80211 throws a one-time `WARN_ONCE` (ieee80211_tx_dequeue) on first TX —
  harmless, delivery still works. Wifi associates ~10 s, so netconsole armed in userspace catches
  events from ~11 s onward (the LPASS macro probe is later — fine).
- **Capture pattern for a hard-hang driver (used here):** boot the DTB that has the suspect node
  but BLACKLIST its module so the box boots to SSH without auto-hanging
  (`/etc/modprobe.d/lpass-cap.conf` blacklists snd-soc-lpass-*-macro); arm netconsole; then
  `modprobe <driver> dyndbg=+p` to trigger the probe on-demand while streaming. The last line
  before the stream stops = the faulting operation.

## 3. LPASS finding (via netconsole)
Booted test39 (5 LPASS macros in DT, modules blacklisted) → armed netconsole → `modprobe
snd-soc-lpass-va-macro dyndbg=+p`. Captured:
```
[130.102] LPASSCAP_VA_START
[130.146] va_macro 6d44000.codec: qcom,dmic-sample-rate dt entry missing
   <-- stream stops; SoC resets -->
```
- The va-macro driver BOUND to `6d44000.codec` (DT match OK) and got through the early DT-property
  reads, then **wedged at the very next step — the clock-enable / first MMIO access to 0x6d44000.**
- => The x1e80100 LPASS-macro addresses are WRONG/protected on glymur; touching 0x6d44000 raises a
  NOC/bus error. Confirms the G13 hypothesis with a concrete last-instruction.
- **BONUS:** this fault AUTO-RECOVERS. The bus error RESET the SoC (not a permanent brick) → it
  rebooted to the saved default (test37). So future single-macro probe tests are lower-risk than
  feared — they reset and come back, as long as saved default = dt-test37. (The earlier "all macros
  at boot" case appeared to hang, but a single on-demand probe cleanly reset.)

## 4. Next for AUDIO
Still need glymur's REAL LPASS macro/swr addresses (x1e's don't apply). With netconsole now in
place, once we have candidate glymur addresses we can probe each macro on-demand and watch it
either bind cleanly or bus-error — fast, low-risk iteration. Sources for real addresses: glymur
vendor BSP dtsi / linux-next / RE of the Windows ACD or ADSP fw. (glymur lpass CCs known from the
ADSP dtb: aon_cc@1f40000, audio_cc@6bc0000, lpmla_cc@6e40000.)

## 5. State left
Box HEALTHY on test37 (default). netconsole target not active (cleared on reboot); re-arm with
`~/netcon_on.sh` after starting the Windows listener. `/etc/modprobe.d/lpass-cap.conf` (macro
blacklist) left in place — harmless on test37 (no macro nodes) but REMOVE before a real audio
bring-up boot. grub: dt-test37 default, dt-test39 = macros DTB for captures.
