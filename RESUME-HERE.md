# RESUME HERE — Zenbook A16, as of 2026-07-27

New session? Read this file first. `HANDOFF.md` has the full history; this is the live
state and what to do next. **The live section is the LAST one in the file** (2026-07-27);
everything above it is history, in reverse-chronological blocks.

---

# ▶ CURRENT STATE (2026-07-27 06:10) — START AT THE BOTTOM OF THIS FILE

**Jump to the LAST section, `2026-07-27 (later) — MASK 2 RAN AND DIED. FIRST PON DIFF IS
IN.`** It is the live state. The section before it (`mask 2 ARMED, qcom-pon reason dump
LANDED`) is the same day's earlier half and is still accurate background. The
`WHEN YOU GET BACK` section above both is the 2026-07-25 version and is superseded — but
its "what is genuinely settled" list is still valid and is not repeated.

**Headline: every bisect mask has now been run. The PON result is INCONCLUSIVE — the
control test ran and killed both the lead and the strong claim.** Three PON reads (clean
shutdown / post-crash / clean reboot) are byte-identical in the reason registers, which
cannot distinguish "PMIC uninvolved" from "these bytes never move". **Do not repeat
"PMIC eliminated" as fact.** Next step is a positive control: force a PMIC-level reset
(long power-button hold) and re-read. The one bit that moved (PBS +0x15/+0x16) is
one-way drift — **closed**.

Two things from 07-27 that change how you read the rest of this file:

- **The screen-blank guard's documented `setsid nohup` form does not work.** It dies with
  the shell. Use the systemd user unit in the last section instead.
- **`qcom_pon` is a loadable module with refcount 0 — the PON reason read never needed a
  reboot.** It was parked for two days as a build-and-reboot job on that mistaken premise.
  It is now built, loaded, and has produced a clean-shutdown baseline.
(Every earlier bisect section above it is superseded — the full result table is in that
last section.) Everything between here and there is history and contains at least three claims
that were later retracted. Two corrections that matter for reading the older text:

- **idle-PC is REVERTED.** `.has_idle_pc` is back at upstream `true`. The paragraph
  below saying "the running msm has idle-PC disabled" is **stale** — it was true at
  07:12, it is not true now. Idle-PC is *tested and not the fix*.
- **The hunt for a call trace is CLOSED.** Linux emits no fault at all. netconsole with
  a provably empty queue and ramoops on a genuine test69 cycle both came back blank, so
  `kmsg_dump` never ran. The SoC is reset externally (TZ / secure watchdog / hardware).
  Do not spend another boot trying to capture an Oops — there isn't one. The `Internal
  error: synchronous external abort 0x96001610` documented below is a *different*
  failure mode (it followed an ADSP watchdog) and is not the screen-off crash.

GRUB default is now **`fedora-glymur-test69`** (= test68 + a ramoops node), not test68.

---

# ⚠️ CORRECTION FIRST — read this before the block below

**The "root cause found: idle power collapse" claim below is NOT established. Do not act
on it as fact.** `.has_idle_pc = false` was built, installed and booted at 07:12 on
2026-07-25, and **the box still died on `kscreen-doctor --dpms off`** at 07:15:43.
Disabling idle-PC did not fix it.

The 58 ms `IDLE_TIMEOUT` match in that block is arithmetically real, but it never proved
causation: journald's 1 s sync window swallowed everything after the last line, and the
ADSP→abort sequence now known to follow (below) takes ~0.8 s — so it could have been
happening at 06:53 too, invisibly. Treat idle-PC as **tested and not the fix**.

**The running msm right now (`54594C3A39F83EAAD4C51A2`) HAS idle-PC disabled.** That is an
extra variable in every result from here until it is reverted. Revert with
`git -C ~/kernel-build/linux-src checkout drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_12_2_glymur.h`,
rebuild, reinstall, **and re-run `dracut --force /boot/initrd.img-$(uname -r) $(uname -r)`**
— msm.ko IS in the initrd (confirmed), so `cp` + `depmod` alone silently boots the old one.
Old module saved as `msm.ko.pre-idlepc` in the session scratchpad;
`/boot/initrd.img-7.1.0-glymur-gdsc1.bak-pre-idlepc` is the matching initrd.

## What the 07:15 crash actually showed — better evidence than we have ever had

```
07:15:42.401  qcom_q6v5_pas 6800000.remoteproc: watchdog received:
              sys_m_smsm.c:783:err fatal notification received from TZ
07:15:42.406  remoteproc remoteproc0: crash detected in adsp: type watchdog
07:15:42.406  remoteproc remoteproc0: recovering adsp
07:15:43.226  Internal error: synchronous external abort: 0000000096001610 [#1] SMP
```

- **ESR `0x96001610`** → EC `0x25` (data abort, same EL), DFSC `0x10` = *synchronous
  external abort, not on translation table walk*, on a **read**. On Qualcomm this is the
  classic signature of **touching a register whose clock or power domain is gone**, or of
  an **XPU/TrustZone access violation**. This revives the archive's old "TrustZone XPU
  wall" note that had been marked superseded.
- **TZ saw it first.** The `fatal notification received from TZ` is what killed the ADSP;
  the ADSP watchdog is a *symptom*, not the cause. Do not go chase the ADSP for this.
- **`kernel.panic_on_oops = 0`** — so the abort did NOT reboot the box. The kernel printed
  the Oops and kept running; something else (qcom_wdt or a TZ-driven reset) took the SoC
  down within ~1 s. That is why the register dump and call trace never reach disk.

⚠️ The three `Call trace`s at `Jun 26 20:00:01` in every boot are **unrelated pre-existing
noise** — `pmic_arb_wait_for_done` SPMI probe warnings (`spmi-pmic-arb.c:340`), plus
`pmic-spmi 0-07: probe ... failed with error -5`. They appear in every boot. Not the crash.

## Capture that finally works: `/dev/kmsg` with fsync per line

journald cannot win this race and netconsole needs a receiver box. Installed instead:

- `/usr/local/bin/glymur-kmsg-logger.py` → appends `/dev/kmsg` to
  **`/var/log/glymur-kmsg.log`**, `os.fsync()` **after every line**.
- **`glymur-kmsg.service` is enabled and starts at boot** (`WantedBy=sysinit.target`,
  `Restart=always`). Disable with `sudo systemctl disable --now glymur-kmsg`.
- **After any crash, read `/var/log/glymur-kmsg.log` FIRST, before `journalctl -b -1`.**

⚠️ **Known limit of this logger, hit on the very first crash it caught:** it is a
*userspace* reader. It captured the entire display teardown but **NOT** the
`Internal error:` Oops itself — once the abort happens in kernel context the SoC resets
before our process is scheduled again. Getting the PC / register dump / call trace needs a
kernel-side sink. Both were attempted:

### ✅ netconsole over Wi-Fi WORKS — verified end to end 2026-07-25 07:46

**This machine is `loazen` = 192.168.8.60, MAC `52:df:6e:55:14:44`** (wlP4p1s0). The
receiver is **192.168.8.22** (`d8:43:ae:9f:7b:d6`) — Jesse's other machine, where he opens
an ssh tab. (`izombie` = 192.168.8.21 also pings but SSH there needs a key we do not have.)

```bash
# on the laptop:
sudo modprobe netconsole netconsole="6666@192.168.8.60/wlP4p1s0,6666@192.168.8.22/d8:43:ae:9f:7b:d6"
# on 192.168.8.22:
nc -ul 6666 | tee ~/glymur-netconsole.log     # or: ncat -ul 6666 / socat -u UDP-RECV:6666 -
```

Confirmed receiving live kernel output. **Does not survive a reboot — re-run the modprobe
every boot.**

⚠️ **Two traps that made this look broken at first — do not repeat the diagnosis:**
1. `WARNING: net/mac80211/tx.c:3867 at ieee80211_tx_dequeue` fires on load. It is only
   `WARN_ON_ONCE(softirq_count() == 0)` — a **context assertion, not a failure**. TX
   continues normally. Ignore it.
2. **`tcpdump` on the sending interface shows ZERO packets** even while netconsole is
   working, because netpoll bypasses the packet-socket tap (`dev_queue_xmit_nit`). Do not
   conclude anything from that. Use the interface counters instead:
   `cat /sys/class/net/wlP4p1s0/statistics/tx_packets` before/after — 30 kmsg lines
   produced a delta of 47 packets / 8301 bytes.

Still unproven: whether Wi-Fi netconsole survives *into* the abort context. That is what
ramoops (test69) is the backstop for.

### ⚠️⚠️ TWO ramoops TRAPS — both hit, both now fixed. Read before touching pstore.

**Trap 1: `efi_pstore` steals the backend and ramoops is silently ignored.**
pstore accepts exactly ONE backend and efi_pstore wins the race at boot:
```
pstore: Registered efi_pstore as persistent store backend
pstore: backend 'efi_pstore' already loaded: ignoring 'ramoops'
ramoops: registering with pstore failed
ramoops 94000000.ramoops: probe with driver ramoops failed with error -16
```
The DT node and address were fine — ramoops was evicted. efi_pstore loads even with
`efi=noruntime` because `qcom_qseecom`/uefisecapp registers efivars operations, and it is
useless here. **Fixed** on the test69 cmdline:
`modprobe.blacklist=gpucc_glymur,efi_pstore pstore.backend=ramoops`.
Live fix without a reboot: `sudo rmmod efi_pstore && sudo modprobe ramoops` → expect
`pstore: Registered ramoops as persistent store backend` + `ramoops: using 0x100000@0x94000000`.

**Trap 2 (worse): booting test68 after a crash DESTROYS the ramoops dump.**
test68 does **not** reserve `0x94000000` — that address is ordinary System RAM there, so
the kernel allocates over it. The GRUB default used to be test68, which meant every crash
auto-booted the one kernel that erased its own evidence. This already cost one capture
(2026-07-25 07:55 crash: dump lost because the box came back on test68).

**→ `set default=` is now `fedora-glymur-test69`** (backup:
`/boot/grub/grub.cfg.bak-pre-default-test69`). `timeout=10`, test68 is one keypress away
and is **byte-identical to before** — verified by diffing its menuentry block against
`grub.cfg.bak-pre-test69`. Revert the default by editing line 1 back to test68.
⚠️ When grepping the menu, note the test69 *title* contains the string "test68", so
`awk '/test68/'` matches both entries — anchor on `--id fedora-glymur-test68`.

### Capture-channel scoreboard (measured, same crash)

| channel | reached | verdict |
|---|---|---|
| netconsole → .22 | t=245.358 | **best**, kernel-side |
| `/dev/kmsg` fsync logger | t=245.315 | ~43 ms behind |
| ramoops | — | untested; dump was destroyed by trap 2 |

**Neither live channel reaches the Oops.** The last ~100 ms before reset is still dark, so
ramoops is not optional — it is the only remaining way to see the actual fault.

### Crash reconfirmed on test69, and it is fast

Fired 07:55:25, boot ended 07:55:28 — **~3 s**, and only ~40 ms after `dpms off returned
rc=0`. Deepest sequence captured (netconsole):
```
245.321367 drm_atomic_helper_commit_encoder_bridge_disable disabling [ENCODER:40:TMDS-40]
245.346044 msm_dp_ctrl_isr idle_patterns_sent
245.346133 msm_dp_ctrl_push_idle mainlink off
245.346309 dpu_encoder_resource_control enc40 sw_event:3, work cancelled
245.346343 dpu_encoder_helper_wait_for_irq ... pending_cnt=1
245.355378 _dpu_encoder_irq_disable enc40
245.355601 msm_dp_ctrl_mainlink_disable disable
245.356760 msm_dp_ctrl_link_clk_disable disabled link clocks
245.356792 stream_clks:off link_clks:off core_clks:on
245.356826 msm_dp_display_host_phy_exit core_init=1 phy_init=1
245.357982 msm_dp_bridge_atomic_post_disable sink count: 1     <- last line out
```
Consistent with the earlier fsync capture, which continued past this point to
`dpu_core_perf_crtc_update crtc=111 disable`. So the true death is still further on.

### ✅ ramoops — built and staged as `test69`

New GRUB entry **`fedora-glymur-test69`** = test68 + one `reserved-memory` node. **Default
is still test68 and test68 is untouched** — pick test69 by hand at the menu (`timeout=10`).

| | |
|---|---|
| DTS | `dts/test69.dts` (from `dts/test68.dts`) |
| DTB | `/boot/glymur/glymur-a16-test69.dtb` |
| Diff vs installed test68 DTB | **exactly the ramoops node, nothing else** (verified by decompiling both and diffing) |
| GRUB backup | `/boot/grub/grub.cfg.bak-pre-test69` |
| Kernel / initrd | unchanged, shared with test68 |

```
ramoops@94000000 {
        compatible = "ramoops";
        reg = <0x00 0x94000000 0x00 0x100000>;
        record-size = <0x20000>;
        ecc-size = <0x10>;
        max-reason = <0x02>;          /* KMSG_DUMP_OOPS - covers oops AND panic */
};
```

⚠️ **The address was NOT taken from the DT reserved-memory list, and you must not do that
either.** The low band is fragmented by UEFI reservations that do not appear as
reserved-memory nodes: `0x93500000` looks like a free hole between `video@92900000` and
the next node, but `/proc/iomem` shows it is **not System RAM** — System RAM only resumes
at `0x93f00000`. Putting ramoops there would have landed it in a firmware hole, which on
this machine is how you earn an XPU violation. **Always cross-check candidate addresses
against `/proc/iomem`, not just the DT.** `0x94000000` is inside `93f00000-a8efffff`.

Other notes:
- Module is **`ramoops.ko`**, not `pstore_ram`. `/etc/modules-load.d/glymur-ramoops.conf`
  now loads it at boot — it must be resident *before* the crash or nothing is recorded.
- `CONFIG_PSTORE_CONSOLE/PMSG/FTRACE` are all **=n**, so only the dmesg-on-oops backend
  exists. That is enough here because the event *is* an Oops (`Internal error … [#1]`).
- After a crash on test69: `sudo ls -la /sys/fs/pstore/` then read `dmesg-ramoops-0`.
- Unproven: whether this SoC's warm reset preserves DRAM. If pstore is empty after a
  confirmed crash, that is the answer, and netconsole-over-USB-Ethernet is the fallback.

# ★ WHAT THE CRASH ACTUALLY IS — captured 2026-07-25 ~07:26 (first ever full teardown)

Jesse left the box idle (breakfast); the screen went off and it died. The fsync logger
caught the **entire display disable path**. This supersedes both earlier theories.

```
487399284  [drm:_dpu_encoder_irq_disable] enc40
487399308  [drm:dpu_encoder_virt_atomic_disable] enc40 encoder disabled
487399370  [drm:msm_dp_ctrl_mainlink_disable] disable
487400509  [drm:msm_dp_ctrl_link_clk_disable] disabled link clocks
487400527  stream_clks:off link_clks:off core_clks:on
487400547  [drm:msm_dp_display_host_phy_exit] core_init=1 phy_init=1
487401729  [drm:msm_dp_bridge_atomic_post_disable] type=14 Done
487521524  [drm:drm_atomic_helper_commit_crtc_disable] disabling [CRTC:108]   <- 120ms gap
487521668  [drm:msm_dp_pm_runtime_suspend] type=14 core_init=1 phy_init=0
487522861  [drm:msm_dp_ctrl_core_clk_disable] stream:off link:off core:OFF
487523818  [drm:dpu_core_perf_crtc_update] update clk rate = 0 HZ
487524165  crtc:108 enabled:0 core_clk:0  ->  crtc=108 disable
487633896  clk:0 / update clk rate = 0 HZ            (110 ms later!)
   ... same for crtc 109, 110 ...
487635037  [drm:dpu_core_perf_crtc_update] crtc=111 disable       <- LAST LINE. dead.
```

**Where it dies:** between the `crtc=%d disable` print (`dpu_core_perf.c:368`) and the
`clk:%llu` print (`:393`). The only thing in between is
`_dpu_core_perf_crtc_update_bus()` (`:378`) → `dpu_core_perf_aggregate()` +
**`icc_set_bw(kms->path[i], avg_bw, peak_bw)`** (`:247`).

So it aborts on the **interconnect bandwidth vote, after the DP core clocks are already
off and the DPU core clock is already 0 Hz**. That is a coherent story for
`synchronous external abort` — the block is unclocked/unpowered by then.

Also note the **~110 ms stall per CRTC** inside the clock/OPP step, and that CRTCs
108/109/110 complete the same sequence fine — only the 4th dies. Consistent with a
cumulative power-domain collapse rather than anything specific to crtc 111.

### ⚠️ `srcversion` CANNOT verify catalog-only changes — new trap, cost real confusion

`.has_idle_pc = true` and `= false` builds produce **byte-different `msm.ko` files with
the IDENTICAL `srcversion` `54594C3A39F83EAAD4C51A2`.** The project's standing rule
("diff the srcversion to prove the right module is live") is **not sufficient** for
changes confined to `catalog/*.h`. Verify with `cmp` against a known-good copy instead:

```bash
cmp /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/msm/msm.ko <known-good>.ko
```

(The idle-PC experiment *was* valid — confirmed by `cmp`, the two .ko differ at byte
1400811. But srcversion alone would never have told you.)

### Current installed state (verified by `cmp`, not srcversion)

`.has_idle_pc` is **reverted to upstream `true`**. Build tree, `/lib/modules`, and
`/boot/initrd.img-7.1.0-glymur-gdsc1` all byte-match the reverted build. Reference copies
in the session scratchpad: `msm.ko.idlepc-TRUE` (installed) and `msm.ko.idlepc-FALSE`.

### 🔒 Screen kept on so the box stays usable

`kscreen-doctor --dpms off` / any screen-off = instant death, and powerdevil's 99999 s
timeouts did **not** prevent it firing. Current guard is a **runtime inhibition, and it
does NOT survive a reboot**:

```bash
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
setsid nohup kde-inhibit --screenSaver --power sleep 86400 >/dev/null 2>&1 &
```

Verify with
`qdbus-qt6 --literal org.kde.Solid.PowerManagement.PolicyAgent /org/kde/Solid/PowerManagement/PolicyAgent ListInhibitions`
(expect two `{"Running Script", "sleep"}` entries). `setterm --blank 0 --powerdown 0` on
tty1 and `consoleblank` = 0 are the second layer.

---

# ⛔ SUPERSEDED BY THE CORRECTION ABOVE — 2026-07-25 06:53 analysis, kept for the reasoning

**This block's headline claim is wrong** (idle-PC was disabled and the crash persisted).
The timing measurements and the source chain are still accurate and worth keeping; only
the causal conclusion is retracted.

## The proof (deterministic, reproduced on demand)

`kscreen-doctor --dpms off` kills the box in **under a second, every time**. Full chain,
all timestamps from `journalctl -b -1` on the 06:53 crash boot:

```
06:53:06.695143  GLYMUR-DPMS-TEST: dpms off returned rc=0
06:53:06.717-.718  normal atomic commit: crtc108 / plane48 / enc40, 2880x1800 AR30
06:53:06.722517  [drm:dpu_crtc_frame_event_work] crtc108 event:1     <- LAST FRAME DONE
06:53:06.780958  [drm:_dpu_encoder_irq_disable [msm]] enc40          <- LAST LINE ON DISK
                 (dead here or within the next second)
```

**58.4 ms between last frame-done and `_dpu_encoder_irq_disable`.**
`dpu_encoder.h:20` — `#define IDLE_TIMEOUT (66 - 16/2)` = **58 ms**. Exact match.

Source chain, all verified in `~/kernel-build/linux-src`:
- `dpu_encoder.c:987` — on `FRAME_DONE`, queues `delayed_off_work` at `idle_timeout`.
- `dpu_encoder.c:1058` — that work fires `DPU_ENC_RC_EVENT_ENTER_IDLE`.
- `dpu_encoder.c:1079-1080` — `if (is_vid_mode) _dpu_encoder_irq_disable(drm_enc);`
  eDP is video mode, so this is the branch taken. **This is the last thing that runs.**
- `dpu_encoder.c:2653` — `idle_pc_supported = dpu_kms->catalog->caps->has_idle_pc`
- `catalog/dpu_12_2_glymur.h:14` — `.has_idle_pc = true`

**Why the old evidence pointed at "30s after dim":** the dim itself was a commit. Death
follows whenever composition actually *stops*, which after DPMS-off is 58 ms, not 30 s.
The "screen-off → msm disable path" hypothesis was close but wrong in a way that matters:
**there is no disable modeset in the log at all** — no `dpu_encoder_virt_atomic_disable`,
no `msm_dp_display_disable`, no bridge disable. Do not instrument the disable path.

⚠️ **Honest limit on the evidence:** journald syncs at 1 s, so death could be up to ~1 s
after that last line with messages lost. What is *certain* is that ENTER_IDLE fired at
exactly `IDLE_TIMEOUT` and is the last thing that reached disk. If you want the true last
gasp (to learn *why* idle-PC kills it — SMMU fault? GDSC timeout? IRQ storm?), wire
**netconsole** and re-fire; the trigger is now instant and reliable, which is what made
netconsole impractical before.

## ⏭️ STAGED AND READY — reboot and run the test

A one-line single-variable change is **built, installed, and in the initrd**. It has not
been booted yet.

| | |
|---|---|
| Change | `catalog/dpu_12_2_glymur.h`: `.has_idle_pc = true` → **`false`** (+ comment) |
| Why it is decisive | `dpu_encoder.c:916-920` — with `idle_pc_supported = false`, every event except `KICKOFF`/`STOP`/`PRE_STOP` returns early, so the off-work is **never queued** and `ENTER_IDLE` can never fire. |
| msm srcversion | `1C80A42BB7CB9BA0ADF0956` → **`54594C3A39F83EAAD4C51A2`** |
| Initrd | **regenerated** (`/boot/initrd.img-7.1.0-glymur-gdsc1`), verified to carry `54594C3A…`, ADSP firmware confirmed still inside |
| Backups | `/boot/initrd.img-…gdsc1.bak-pre-idlepc`, old `msm.ko` in the session scratchpad |
| Kernel / DTB / GRUB | **unchanged** — still `7.1.0-glymur-gdsc1` / test68. Just reboot normally. |

⚠️ **`msm.ko` is in the initrd** (confirmed — it was the stale-module trap waiting to
happen). `cp` + `depmod` alone would have booted the OLD module and faked a result. The
`dracut --force` has been done. **Re-verify after boot anyway:**

```bash
cat /sys/module/msm/srcversion    # must be 54594C3A39F83EAAD4C51A2
```

Then re-run the trigger (script in the session scratchpad, or inline):

```bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0
kscreen-doctor --dpms off && sleep 120 && kscreen-doctor --dpms on && echo SURVIVED
```

- **Survives 120 s** → idle-PC confirmed as the cause. The machine becomes usable: unmask
  the sleep targets, restore `powerdevilrc`/`kscreenlockerrc`/logind, drop `consoleblank=0`.
- **Still dies** → idle-PC is not it (or not all of it). Next suspect is DPU/MDSS runtime
  PM below the encoder, and it is worth wiring netconsole before the next shot.

⚠️ **Syntax trap that already burned one run:** dpms is a **global flag**, not a
per-output setting. `kscreen-doctor output.eDP-1.dpms.off` is rejected with
`Unable to parse arguments` and **silently leaves the screen on** — the first run
"survived 90 s" and meant nothing. Always check the rc and grep the output for
`unable to parse`. It is `kscreen-doctor --dpms off`.

## Changes made this session (both no-reboot, both reversible)

1. **`/etc/systemd/journald.conf.d/99-glymur-crashcapture.conf`** — `SyncIntervalSec=1s`,
   `Storage=persistent`, rate-limiting off. **This is why `-b -1` may finally have content.**
   The default `SyncIntervalSec=5m` is the likely reason the 01:18:15 crash log just "ended":
   the kernel wasn't silent, the last messages never reached disk. Delete the file to revert.
2. `drm.debug` set to `0x116` at runtime by the test script (cleared on the survive path).

## Corrections to the notes below

- **The claim "the running msm already has hand-added `XXX: msm_dp_display_enable` printks"
  is only half true.** `msm.ko` (srcversion `1C80A42BB7CB9BA0ADF0956`, same in `gdsc1` as in
  `edp1`) carries **10** `XXX` strings and **all ten are on the ENABLE path**
  (`msm_dp_ctrl_phy_init`, `msm_dp_ctrl_on_link`, `msm_dp_ctrl_on_stream`,
  `msm_dp_display_enable`). **There is nothing on the disable path.** Note 8 of the 10 are
  `drm_dbg_dp`, so they need `drm.debug=0x100` to print at all; only the
  `msm_dp_display_enable` pair are bare `pr_info`.
- **ramoops is not as close as it looks.** `CONFIG_PSTORE=y` and `CONFIG_PSTORE_RAM=m` are
  set, but **`CONFIG_PSTORE_CONSOLE is not set`** — so even with a `reserved-memory` node in
  the DTB, ramoops would only capture a *panic*, not a plain hard reset. A hard reset leaves
  it empty and you have spent a DTB build to learn nothing. (`softlockup_panic=1 panic=10`
  are on the cmdline, so a panic is plausible — but unproven.) Continuous capture needs
  `PSTORE_CONSOLE=y`, i.e. a kernel rebuild.
- **The Fedora WoA wiki (`fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install`) does not
  help here** — checked 2026-07-25. X1E/X1P/8cx Gen 3 only, no glymur, and nothing on
  suspend, DPMS, display PM, pstore, or panic debugging. One item worth keeping for the
  *audio* thread: it blacklists `qcom_q6v5_pas` at boot outright and loads ADSP firmware
  from userspace via `qcom-firmware-extract` — a different ordering from our initramfs
  `install_items+=` fix. Probably not the audio fix (moving ADSP later is measured not to
  help), but it is the upstream-blessed shape.
- **Audio confirmed still broken by Jesse on this boot**, and it was a **cold** boot — so
  the failure is not leftover state from a previous session. `Built-in Audio
  (MultiMedia2 Playback)` does exist and is the default sink; dmesg shows the
  `DSP returned error[1001006] 9` (GRAPH_OPEN refused) storm at t+19s. ADSP itself is
  `running`, so this is the first-DSP-interaction race, not the firmware-ordering bug.

---

# ⏸️ SESSION STATE — 2026-07-25 ~01:30, stopped for the night

**`fedora-glymur-test68` is the BASELINE and the GRUB default** (set 2026-07-25;
kernel `7.1.0-glymur-gdsc1`, DTB `glymur-a16-test68.dtb`). `timeout=10`, so fallbacks are
one keypress away: `test67` → `test65` → `gdsc1` → `edp1` → `clean2`.
**Do NOT boot `test66`** — it is a regression (breaks Wi-Fi and audio).

⚠️ **`grubby` / BLS is vestigial on this box — do not use it.** The active bootloader is
`\EFI\ubuntu\grubaa64.efi` reading the hand-written `/boot/grub/grub.cfg`. The Fedora BLS
entries under `/boot/loader/entries/` and anything `grubby` reports are ignored at boot
(`grubby --default-kernel` still claims `clean2`). To change the default, edit the
`set default=` line at the top of `/boot/grub/grub.cfg`.

Jesse's call on 2026-07-25: baseline is test68 even with audio and the panel/display
idle-power issue outstanding — those get fixed *on top of* test68, not by reverting.

Environment: Fedora 44 KDE, **Plasma 6.7**, Wayland.

## ✅ Landed this session (all pushed)

| Win | Detail |
|---|---|
| **gdsc genpd teardown fix** | Real upstream bug. `gdsc_init()` calls `pm_genpd_init()` but nothing called `pm_genpd_remove()`, so unloading any qcom clock controller left the global `gpd_list` pointing into freed module memory. Fixed + 2 error paths. Pushed to `linux-glymur-a16@glymur-edp-hbr3`. Patch: `patches/glymur-gdsc-genpd-teardown-UPSTREAM.patch` |
| **gpucc CONFIRMED on hardware** | 25 `gpu_cc` clocks, `gpu_cc_pll0` = 1149999902 Hz. Registration only — no GPU rendering. Corrects the old "gpucc missing from mainline" claim: the driver exists in v7.1. |
| **ADSP firmware boot fix** | `install_items+=` ships ADSP firmware in the initramfs so `qcom_q6v5_pas` finds it at t+1.5s. ADSP now boots every time. |
| **Lid switch** | TLMM GPIO 92, recovered from the WoA ACPI DSDT. `SW_LID` registers, logind reads it. (Currently ignored on purpose — see below.) |
| **UCSI / Type-C** | Was **never** working. One DT property: `usb@a600000` declared `usb-role-switch` with `dr_mode="host"`. Deleted it (test68) → `/sys/class/typec/` populates, PD negotiates, orientation detects. |
| **USB-C DisplayPort alt-mode** | **Working on BOTH USB-C ports.** External monitor confirmed. `docs/usb-c-ucsi-dp-altmode.md` |
| **Repo consolidated** | One repo (`~/Projects/zenbook-a16-linux`), `-public` clone retired. Internal notes (`memory-archive/`, `HANDOFF.md`, `RESUME-HERE.md`, `CLAUDE.md`) are gitignored — they carry home-LAN/host details. Verified by scan before pushing. |

## 🔴 OPEN — in priority order

### 1. Idle crash = the DISPLAY power-down path in msm (NOT suspend)
**This is the big one.** The machine hard-reboots when left idle. It is **not** systemd
suspend: after masking every sleep target (`CanSuspend` = `no`) it *still* died, and
`journalctl -b -1` has **no `PM: suspend entry` line at all**. What it has:
```
01:17:32  Started dbus-...org.kde.powerdevil.backlighthelper   <- idle dimming
01:17:44  ...backlighthelper Deactivated
01:18:15  <log ends, hard reboot>
```
Dim → ~30s → death, exactly where screen-off/DPMS follows. **Root cause is msm's
display idle/disable path.** Matches Jesse's long-held hypothesis.

**All idle paths are currently blocked** (so the machine is usable):
sleep/suspend/hibernate targets masked; `/etc/systemd/logind.conf.d/99-glymur-no-suspend.conf`
(lid + keys ignored, `IdleAction=ignore`); `~/.config/powerdevilrc` DPMS/dim = 99999;
`~/.config/kscreenlockerrc` `Autolock=false`; `consoleblank=0`.

**NEXT STEP:** confirm the block holds over a long idle. Then instrument msm's *disable*
path — the running msm already has hand-added `XXX: msm_dp_display_enable START/END`
printks, so extend the same treatment to `msm_dp_display_disable` / DPU runtime PM.
Evidence capture is blocked (`efi=noruntime` is mandatory → pstore always empty), so use
**ramoops in the DTB** or **netconsole** before deliberately triggering it.

### 2. Audio — intermittent, NOT solved
Card, sink, 4× WSA884x amps and UCM all come up. Failures cluster in the first ~20s and
always on the *first* DSP interaction. One boot captured both:
- `t+11.79s MultiMedia1: no backend DAIs enabled` — login sound firing 0.8s after card
  registration, before WirePlumber applied UCM routing.
- `t+18.40s MultiMedia2: CMD timeout [1001002]` (`APM_CMD_GRAPH_START`) `-110`, then
  repeated `DSP returned error[1001006] 9` (GRAPH_OPEN refused).

⚠️ **`speaker-test` is not a reliable oracle** — it produced clean 4-ch output with PCM
`RUNNING` on one boot and hung on "Front Left" on another. Use **Jesse's procedure**
(in `docs/audio-adsp-boot-ordering.md`): boot → wait for Wi-Fi → change volume → if
silent, toggle Built-in Audio off/3s/on → retry → settings test button → capture dmesg.

**Known contributing factor:** msm autoloading costs ~1s (card at 9.34s when msm was
blacklisted vs 10.36s now) against PipeWire starting at 10.4–12.2s. Thin race.
**Candidate fix (unproven):** `q6apm_get_apm_state()` blocks one 5s `wait_event_timeout`;
the DSP never answers the first query but answers the next immediately. Short-timeout
retries would pull card registration from ~10.4s to ~6s. Needs a kernel rebuild, and it
is NOT certain it fixes the 18.4s graph refusal. **Do not** simply delete the blocking
call — `prm_probe()` depends on the same readiness gate.

### 3. Smaller open items
- **HDMI port not wired** — no HDMI node anywhere in DT. All three DP controllers are
  used (eDP-1 + DP-1 + DP-2 for the two USB-C ports). Needs a DP→HDMI bridge node.
- **USB4** — blocked upstream. Binding is an unmerged **RFC** (Konrad Dybcio, 2025-09-16).
  We now have the Type-C half of the pipeline (UCSI → typec_mux → QMP PHY); the host
  router/NHI does not exist in any in-tree qcom DT. Do not hand-write against the RFC.
- **cpufreq dead** — `scmi-cpufreq -110`. `glymur-thermal-guard.sh` is spamming the
  journal every 2s with `scaling_max_freq: No such file` because of it.
- **`plasmashell --version` core-dumps** — noticed 2026-07-25, uninvestigated.
- **GPU** — still the top long-term gap; needs `gpu`/`gmu`/`adreno_smmu` DT nodes.

## ⚠️ Don't repeat these
- **test66** freed TLMM 94/246 → unblocked `wcn7850-pmu` and `1c00000.pci`, which then
  failed on pins 116/150 (still reserved) → Wi-Fi dead. **Deferred is better than broken.**
- **test67** (`dr_mode="otg"`) is a no-op: `CONFIG_USB_DWC3_HOST=y`, so the kernel logs
  `Configuration mismatch. dr_mode forced to host`.
- **Moving the ADSP later does not help audio** — measured: ADSP at 5.3s vs 1.41s both
  land card registration at ~10.36s.

---

## 🟢 RESULT (2026-07-24 19:57) — `hbr3` WORKED. THE PANEL LINKS UP.

**First successful native eDP link training on this machine.** HBR3 was the answer.

```
link training #1 on phy 0 successful
link training #2 on phy 0 successful          <-- never happened before
EQ-check  0x202=0x77 0x203=0x77 ALIGN=1 | L0:CR EQ SYM L1:CR EQ SYM L2:CR EQ SYM L3:CR EQ SYM
SET NEW RESOLUTION: 2880x1800@120fps  pixel clock 709633 KHz  bpp=30
dp_video_ready  /  mainlink READY
fb0: msmdrmfb frame buffer device
```

Negotiated **HBR3 / 810000 / 4 lanes**, via `DPCD 0x00100 <- 0x1e`, no `0x00115` write.
All three PHY kretprobes return `0x0`. `card1-eDP-1` connected+enabled, `fb0` is
`msmdrmfb` on the real DPU (not simplefb), `dp_aux_backlight` live at 206/2047.

Logs: `logs/edp-hbr3-RESULT.log`, `logs/edp-hbr3-bind.log`.

**→ Full write-up: [`docs/edp-hbr3-linkup-2026-07-24.md`](docs/edp-hbr3-linkup-2026-07-24.md)**
**→ Reproduction / required settings: [`docs/edp-enable-howto.md`](docs/edp-enable-howto.md)**

Correction to the pre-run prediction below: the "WANT `0x00100 <- 14`" line was wrong.
810000 encodes as **`0x1e`**, which is what was written. Everything else predicted held.

### ✅ CONFIRMATION RUN PASSED (2026-07-24 20:28) — the result is clean

Ran with the **stock** swing table (`phy_qcom_edp` srcversion `36C471B8B711AB40B549DED`),
HBR3 `msm` unchanged, nothing else touched. `logs/edp-hbr3-stockphy-RESULT.log`:

```
XXX setvolt: is_edp=1 rate=8100 lanes=4 v=0 p=1 -> swing=0x11 emph=0x15   <-- STOCK cell
EQ-check  0x202=0x77 0x203=0x77 ALIGN=1 | L0:CR EQ SYM L1:CR EQ SYM L2:CR EQ SYM L3:CR EQ SYM
```

**The link rate alone was the fix.** Drive levels were never involved, and the eDP PHY
driver needs no patches — `phy-qcom-edp.c` is back to pristine v7.1. The 200 ms C_READY
bump is not needed either: at 8.1 G C_READY asserts in ~1 ms (`phyv8 @46.249096 ->
phyrsm @46.250164`), well inside the stock 10 ms timeout.

### ⚠️ CORRECTION — the "firmware selected HBR3" story was wrong

The in-tree comment on the HBR3 force argued that the UEFI's leftover
`LINK_BW_SET = 0x14` meant the firmware's known-good link was HBR3 and that we had been
reading the wrong byte of the `0x100`/`0x115` pair. **`0x14` is `DP_LINK_BW_5_4`; HBR3
is `0x1e`** (`include/drm/display/drm_dp.h:583-584`). The firmware selects 5.4 G — the
rate that fails for us. Fixed in `linux-glymur-a16` commit `b4c376a41`.

What is actually true: the panel advertises 5.4 G max everywhere it is asked, the
firmware trains it at 5.4 G, we cannot, and 8.1 G — never advertised — trains first try.
Unexplained. **The one lead:** between 5.4 G and 8.1 G exactly one register differs in
the whole PHY sequence, `DP_PHY_VCO_DIV` (`edp_phy_vco_div_cfg_v8[2]`=`0x02` vs
`[3]`=`0x01`); both rates share a PLL entry and both land on the same 1.35 GHz divided
VCO. See `docs/edp-hbr3-linkup-2026-07-24.md` §2 Bug 3.

### ✅ VERIFIED (2026-07-24) — `7.1.0-glymur-edp1` boots clean, `msm` autoloads

The last gate is closed. Booted the GRUB default `fedora-glymur-edp1`: no
`modprobe.blacklist=` on the command line, `msm` loads and binds on its own, and the
panel comes up unattended with **no hand-binding and no probe script**.

```
uname -r                        7.1.0-glymur-edp1
/sys/class/graphics/fb0/name    msmdrmfb
card1-eDP-1                     connected / enabled
/sys/class/backlight/           dp_aux_backlight
msm srcversion                  1C80A42BB7CB9BA0ADF0956
phy_qcom_edp srcversion         D981A7A0AE1ECDA17C26A43   (stock)
dmesg | grep -E "Oops|panic"    nothing
```

Note: `link training … successful` / `mainlink READY` do **not** appear on this boot —
those are `drm.debug` prints and this command line carries no `drm.debug=0x100`. Their
absence is expected; `fb0 = msmdrmfb` plus a connected+enabled `eDP-1` is the proof.

test55 (known-good) and test62 (eDP, `msm` hand-bound) remain as fallbacks at
`timeout=10`.

The check that was run (kept for the next kernel bump):

```bash
uname -r                                    # 7.1.0-glymur-edp1
cat /sys/class/graphics/fb0/name            # msmdrmfb
cat /sys/class/drm/card*-eDP-1/status       # connected
sudo dmesg | grep -E "link training|mainlink|msm_dpu|Oops|panic"
cat /sys/module/msm/srcversion               # 1C80A42BB7CB9BA0ADF0956
cat /sys/module/phy_qcom_edp/srcversion      # D981A7A0AE1ECDA17C26A43 (stock)
```

Note the `XXX setvolt` markers are **gone** — that instrumentation lived in
`phy-qcom-edp.c`, which is now pristine. `scripts/edp-train-probe.sh` greps for them and
will report less than it used to; it is also no longer the way to bring the display up.

Remaining gaps after this: suspend/resume untested, and `link_info->rate = 810000` is
still an unconditional constant rather than a general rule, so it is not upstreamable as
written (the rate-set plumbing fix beside it is).

**Pushed 2026-07-24:** `linux-glymur-a16` branches `glymur-edp-hbr3` +
`glymur-asus-wmi-arm64`, and `zenbook-a16-linux` `main` @ `cae7a89`.

---

## The run that produced it (2026-07-24 19:45, staged) — kept for the reasoning

```bash
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh hbr3
```

- **Experiment — single variable: the link rate. 5.4G → 8.1G.** `dp_panel.c`
  `msm_dp_panel_read_sink_caps()`, right after the `use_rate_set = true` line, now forces
  `rate = 810000, rate_set = 0, use_rate_set = false` — the legacy `LINK_BW_SET` path.
  msm built + installed, **disk `C465A0BA58D609FD12ACF42`**, previous module backed up at
  `~/kernel-build/msm.ko.pre-hbr3` (`D6A11734121A8C98FE13237`). No initramfs rebuild needed
  (msm is blacklisted at boot and loaded from `/lib/modules` by the script).
- **Why HBR3 — ⚠️ THIS REASONING WAS WRONG, see the correction above.** The argument at
  the time was: UEFI leaves both `LINK_BW_SET = 0x14` and `LINK_RATE_SET = 0x02` behind,
  eDP 1.4b consults `LINK_RATE_SET` only when `LINK_BW_SET` is 00h, therefore the
  firmware's known-good link is 8.1G and we had been reading the wrong byte. **`0x14` is
  5.4G, not 8.1G** — the firmware picked the rate that fails for us. The part that does
  hold: 8.1G was the only untried rate, since 2.7G and 1.62G are dead on this PHY (stale
  v6-copied v8 PLL constants). The experiment was right for the wrong reason.
- **Why it is low risk.** `phy-qcom-edp.c:1171` is `case 5400: case 8100:` — one shared PLL
  entry, same VCO / lock / cal codes. Only `edp_phy_vco_div_cfg_v8[3] = 0x01` and the post-
  divide differ (`qcom_edp_set_vco_div:631`), and 5400 provably locks. The dtsi already
  permits it: `link-frequencies` last entry `8100000000` → `max_link_rate=810000`.
  `rate_set = 0` keeps `msm_dp_ctrl_link_rate_down_shift()` on its legacy switch, so a
  train_1 failure falls back 810000 → 540000 rather than into the broken low-rate entries.
- **Success looks like:** `use_rate_set=0`, `link_rate=810000`, `0x00100 <- 14`, **no**
  `0x00115` write, and `XXX setvolt ... rate=8100`.
- **If EQ still fails,** next single-variable test is forcing **TPS2** in
  `msm_dp_ctrl_link_train_2` (`dp_ctrl.c:1575-1581`). A pass pins it on TPS3 generation; a
  fail is ambiguous, since DP 1.2 wants TPS3 at HBR2.

⚠️ The running `phy_qcom_edp` (`F83AD312`) still carries the diagnostic `[0][1] = 0x1f/0x1f`
swing cell and the 200ms C_READY bump. Left in deliberately — that cell is proven inert at
5.4G, so restoring it would be a second variable. Restore before anything goes upstream.

### Prior run: `rateset3` (2026-07-24 19:25) — fix works, is not the bug

The LINK_RATE_SET fix landed correctly (`0x00100 <- 00`, then `0x00115 <- 02`) and EQ failed
byte-identically to every previous run. Raw status decode from
`logs/edp-rateset3-bind.log:1376,1382`, bytes `0x202..0x207`:

| phase | bytes | meaning |
|---|---|---|
| CR (TPS1) | `11 11 80 04 22 22` | CR done on all 4 lanes; sink requests swing 2 |
| EQ (TPS3) | `11 11 80 04 44 44` | sink requests v=0 / p=1 — and never moves off it |

Standing facts: **CR passes at 4, 2 and 1 lanes and at every drive level; EQ never sets at
any of them.** The sink was told 8.1G (pre-fix) and then correctly told 5.4G (rateset3) with
identical results, so **rate mismatch is eliminated as the mechanism** — 5.4G just is not a
working operating point. Everything else checks out symmetric and spec-correct: ASSR both
sides, enhanced framing, ANSI 8B10B, SSC advertised, TPS3 correctly chosen, MAINLINK_READY
asserts, `DP_CONFIGURATION_CTRL = 0x45f7` decodes clean.

**Panel identified from EDID:** Samsung/SDC **ATNA60HR07-0**. Range limits 30–120 Hz, max
pixel clock 710 MHz; timings live in a DisplayID extension block (the base block has no
DTDs). HBR2 ×4 = 17.28 Gbps effective vs ~15.7 Gbps for 2880x1800@120 8bpc — so 5.4G is
*sufficient* for the mode, but 10bpc would need HBR3.

⚠️ `rmmod msm` **hard-freezes this box**. Every msm-side experiment costs a reboot; only
`phy_qcom_edp` can be hot-swapped, and only before msm loads.

---

## SESSION 2026-07-24 (latest) — drive levels are FULLY ruled out; firmware RE done

**→ Full write-up: `docs/edp-firmware-re-2026-07-24.md`. Read it before proposing anything
about swing/pre-emphasis — that avenue is closed with evidence from vendor firmware.**

Three results, newest last:

1. **`muxen` run** (`logs/edp-muxen-*`) — built the PHY with `swing |= 0x20` / `emph |= 0x20`
   (the `DP_PHY_TXn_TX_DRV_LVL_MUX_EN` bit that `phy-qcom-qmp-combo.c:3136` sets and
   `phy-qcom-edp.c` never does). Wrote `0x2b`/`0x3f`, **read back `0x0b0b0b0b`/`0x1f1f1f1f`**
   — bit 5 is not implemented. Link-status ladder byte-identical to test62. Reverted.
2. **UEFI DisplayDxe reverse-engineered** (Ghidra headless; the bundled Ghidra has no
   linux_arm_64 decompiler native, so the scripts in `re/ghidra_scripts/` dump disassembly).
   The firmware's eDP swing/emphasis table is **byte-identical to our Linux v8 table**, and
   it writes them to **the same offsets** (emph `TX+0x04`, swing `TX+0x14`, `TX1 = TX0+0x400`),
   clamped to `0x1f`, no MUX_EN, no latch. Tables and offsets are both vendor-correct.
3. **The one surviving discrepancy:** that HAL lays the PHY region out as
   COM+0x000 / TX0+**0x200** / TX1+**0x600**, while vendor `glymur.dtsi:2367` (= our DTB) uses
   COM len 0x358 / TX0+**0x400** / TX1+**0x800**. Most likely the DXE is for the older
   x1e80100-style part, **not proven** — it holds no absolute base constants. Settle it
   before acting: see the RE task list at the end of the write-up.

**Next experiment — `patches/glymur-edp-phywin-dump-DIAGNOSTIC.patch` (built, not yet run).**
Snapshots the PHY registers around the four drive-level writes and prints every register
that changed, plus one layout dump after `power_on`. Chases the last anomaly: a 5-bit level
register that returns `0x0b0b0b0b` for a write of `0x0b` is not behaving like a per-TX
register, so the question is now whether `tx0`/`tx1` point at real TX blocks at all. Reads
only the DT-mapped ranges by default (`dbg_full=1` to sweep the gaps — opt-in, unproven on
this SoC). Module-only, no reboot:

```bash
sudo rmmod phy_qcom_edp && sudo modprobe phy_qcom_edp   # initramfs still serves the old one
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh phywin
```

⚠️ **Stop re-deriving "the driver matches vendor".** That conclusion has now been reached
three times by three independent routes (2026-07-12 DT-vs-CLO, 07-24 CLO source search,
07-24 firmware RE). It is true. The bug is somewhere that comparison cannot see.

---

## SESSION 2026-07-24 (cont.) — the VALID drive-level readback: writes LAND, not plumbing

Booted into **test62** by hand (Jesse picked the GRUB entry; `saved_entry` still reads
clean2 because the eDP entries are hand-written menuentries that don't touch grubenv).
Verified the DTB the *right* way before trusting anything — dispcc/mdss `okay`, **pin 18
free** in the decoded `gpio-reserved-ranges` (range stops at 17, resumes at 19), dptx3
**not** orphaned, DP3 endpoint `link-frequencies` = RBR/HBR/**HBR2/HBR3** (all four → test62,
not test63). Note: `model` still reads "Glymur CRD" on the eDP DTB too — that check in the
old block below is wrong; ignore it, trust dispcc/mdss + gpio ranges. Reloaded the stock PHY
the box came up with (`D981…`) → instrumented (`AC8A39…`), srcversion-verified LIVE, then ran
`edp-train-probe.sh v8probe`.

**Result (valid — supersedes the 07-21 "Result 2", which unknowingly ran the stock module):**

`XXX setvolt` fired on every call and the **readback matches the written value at every
(v,p) cell**: `v=0 p=0 → 0x0b/0x0c`, `v=0 p=1 → 0x1f/0x1f`, `v=2 p=0 → 0x19/0x0e`,
`v=2 p=1 → 0x1f/0x14`, each with `rb tx0`/`tx1` echoing the same bytes. Per the decision
table: **the drive-level writes reach the PHY.** `qcom_edp_set_voltages()` runs (is_edp=1,
no early return); the `TXn_TX_DRV_LVL` / `EMP_POST1_LVL` offsets are correct. **The write
path was never the bug.**

Bonus — AC8A39 also carries the `[0][1]→0x1f/0x1f` swing slam (only that one cell; rest
stock, confirmed by `v=2 p=1` reading stock `0x1f/0x14`). The sink converges on requesting
exactly the `[0][1]` cell (v=0,p=1) at 4 lanes, we drove it to **maximum swing +
pre-emphasis**, readback confirms `0x1f/0x1f` hit both tx0 and tx1 — **and EQ still failed.**
So it is also **not an insufficient-drive problem.**

Link-status decode (unchanged from 07-21, now confirmed at max drive):
`0x202=0x11 0x203=0x11 ALIGN=0` → every lane **CR locks, EQ never sets, SYM never locks**,
interlane align never asserts. Rate stays HBR2 (5400); only lanes drop 4→2→1, never rate.

### Now ruled out
- write path / TX register offsets — readback proves writes land
- `set_voltages` early-return; `is_edp` — is_edp=1, it runs
- "not driving hard enough" — max `0x1f/0x1f` at the requested cell still fails EQ
- fine drive-level tuning as *the* fix at HBR2 — increasing drive is insensitive

### Two live hypotheses
A. **Rate ceiling** — HBR2 (5.4 Gbps/lane) SI limit: CR locks, EQ can't.
B. **Structural EQ-path gap** — a v8 PHY EQ/FFE/CTLE or training step missing, drive-independent.

CR-clean but EQ/SYM totally absent, symmetric across all lanes, insensitive to max drive →
leans A or B, not tuning.

### NEXT STEP — the test63 experiment, now the decisive single variable
Boot **`fedora-glymur-test63`** (test62 + eDP link capped to HBR) and re-run. AC8A39 is
CLEAN for this: the `[0][1]` slam lives only in the *hbr2_hbr3* arrays; at HBR the driver
uses the untouched `swing_hbr_rbr` tables, so test63 reads as stock drive + the readback.
Re-verify srcversion after boot (fresh boots load stock — the trap) and rmmod/modprobe.

```bash
# NOTE: test63-run.sh was NEVER a real file — it was consolidated into edp-train-probe.sh,
# which auto-detects HBR vs HBR2 from the live DT and prints the same VERDICT. Use it:
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh test63hbr
# It prints "HBR (2.7G) capped - test63-style" when you're on the right DTB.
```

EQ passes at HBR → rate-dependent SI; follow-up is HBR2 PHY-EQ/drive, not living at HBR.
EQ fails identically at HBR → structural; go after the PHY EQ programming path, not drive.

Logs from this run: `logs/edp-v8probe-RESULT.log`, `edp-v8probe-bind.log`, `edp-v8probe-phy.log`.
Desktop left stopped (only display is the dead eDP). Restore: `systemctl start display-manager`.

---

## SESSION 2026-07-24 (earlier) — a null probe run, fully explained: WRONG DTB (clean2, display off)

Ran `scripts/edp-train-probe.sh v8probe`. It came back **completely empty** — no sink
caps, no link_status, no `XXX setvolt`, no link_train verdict. **Discard this run.**

Root cause, confirmed against the live `/proc/device-tree` (not guessed):

- The box was booted into **clean2** (`saved_entry=…-glymur-clean2`, booted by hand for
  USB/office work). The clean2 DTB is the display-OFF baseline: model reads
  **"Qualcomm Technologies, Inc. Glymur CRD"**, and **`dispcc @af00000` = disabled**,
  **`mdss @ae00000` = disabled**.
- `phy@faac00` (eDP PHY) is `okay`, but with dispcc disabled it has no clock provider, so
  its clk index 0 (`aux`) returns `-ENOENT`:
  `/soc@0/phy@faac00: Failed to get clk index: 0 ret: -2` →
  `qcom-edp-phy faac00.phy: probe … failed with error -2`. No PHY → no training.

**eDP work CANNOT run on clean2/test55** — dispcc/mdss are disabled *in the DTB*, nothing
binds them at runtime. Must boot an eDP DTB.

Also cleared up (not real problems):
- The debugfs "Automounting of tracing … deprecated … 2030" notice is cosmetic, emitted
  by our own tracefs use in the probe script. Ignore.
- `ath12k_wifi7_pci … Timeout while waiting for regulatory update` (every ~5 min) means
  Wi-Fi's regdomain never applies — **Wi-Fi is not a trustworthy SSH fallback**. The USB
  r8152 NIC also spams `rtl8153a-4.fw … -2` (patch firmware missing) and `-19` USB resets
  on the flaky USB-C port — that's the disconnect Jesse flagged.
- "Missing BLS files" was a red herring: `/boot/loader/entries/` is mode 0700, so a
  non-root `*.conf` glob expanded literally. `sudo ls` shows them. The real active menu
  is **`/boot/grub/grub.cfg`** (NOT `/boot/grub2/`); test62/test63 are hand-written
  menuentries there.

### NEXT STEP — reboot into test62, then re-run the probe

GRUB (`/boot/grub/grub.cfg`, timeout 10, default=0=test55): pick
**`fedora-glymur-test62`** (HBR2, entry [8]) — this is where last session got CR-lock /
EQ-fail. (Fallback to test55/clean2 is preserved; do not edit it.)

On the fresh boot, BEFORE running anything, verify we're actually on the eDP DTB:

```bash
cat /proc/device-tree/soc@0/clock-controller@af00000/status; echo   # must say: okay
tr -d '\0' </proc/device-tree/model; echo   # must NOT say "Glymur CRD"
```

Then displace the stock PHY module (fresh boots load stock — known trap) and confirm:

```bash
sudo rmmod phy_qcom_edp && sudo modprobe phy_qcom_edp
diff <(cat /sys/module/phy_qcom_edp/srcversion) \
     <(modinfo -F srcversion $(modinfo -n phy_qcom_edp)) && echo "instrumented LIVE"
# expect srcversion AC8A39A86C18C653ED3AACC (stock is D981A7A0AE1ECDA17C26A43)
```

Then the actual probe (goal: the drive-level readback that was the whole point):

```bash
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh v8probe
sudo dmesg | grep 'XXX setvolt'
```

Reading it: readback `drv=`/`emp=` matches written `swing=`/`emph=` → writes land, it's a
tuning problem; no match → wrong TX register offsets for the v8 PHY; no line at all →
`qcom_edp_set_voltages()` early-returns and never programs drive level.

---

## SESSION 2026-07-21 — the link_status bytes, and a tooling trap that ate two reboots

### Result 1: we finally have the per-lane link_status the last session wanted

`scripts/edp-train-probe.sh` was silently failing to install its three `drm_dp_*` kprobes,
so every prior run produced an empty "LINK STATUS decoded" section. Fixed (see below).
With probes working, at HBR2 4-lane (`logs/edp-hbr2-status3-*`):

```
EQ-check  0x202=0x11 0x203=0x11 ALIGN=0 | L0:CR eq sym  L1:CR eq sym  L2:CR eq sym  L3:CR eq sym
```

**All four lanes identical: CR locked, EQ never sets, no symbol lock, ALIGN=0.**
Perfectly symmetric across lanes. This rules out lane mapping and any `tx1`-side-only
config problem — those would be asymmetric. Combined with the already-established facts
(PLL locks, `phypo`/`phyv8` both return 0, CR passes), the failure is confined to the
EQ / drive-level path.

Also verified this session, and now closed:

- **Training pattern selection is correct.** `hw: bit=1 train=1` + `sink: pattern=21`
  (TPS1 + scrambling-disable) for CR, then `hw: bit=4 train=3` + `sink: pattern=3` (TPS3)
  for EQ. Both legal at HBR2. Not the bug.
- The sink requests `req_vol_swing=0 req_pre_emphasis=8` on all 4 lanes and **never
  changes its request** across all 6 retries, at HBR2. (At HBR in test63 it asked
  `v=2 p=0`, also never changing.) Consistent with the requested level never reaching
  the wire — but see the warning below, this is NOT yet proven.

### Result 2 (NEGATIVE, and the important one): a module-provenance trap

I built a modified `phy-qcom-edp.ko` (swing/emph `[0][1]` slammed `0x11/0x15` -> `0x1f/0x1f`)
to test whether anything we write reaches the PHY. **That experiment produced a null
result which must be discarded — the modified module was never running.**

Two separate causes, both worth knowing:

1. **`phy_qcom_edp` loads from the initramfs at ~1.8s, not from `/lib/modules`.**
   `cp` + `depmod -a` is NOT enough. You must
   `sudo dracut --force /boot/initramfs-$(uname -r).img $(uname -r)`.
2. **Even after regenerating the initramfs, the boot still came up with the stock module**
   (`srcversion D981A7A0AE1ECDA17C26A43`) despite the initramfs containing *only* the
   instrumented one (`AC8A39A86C18C653ED3AACC`, verified by `lsinitrd --unpack`) and
   `/usr/lib/modules/7.1.0-glymur-clean2/` also being instrumented. **This is unexplained
   and still open.** A manual `rmmod phy_qcom_edp && modprobe phy_qcom_edp` loads the
   correct module, so it is a boot-path issue, not a packaging one.

**RULE, now mandatory before trusting any driver experiment on this box:**

```bash
diff <(cat /sys/module/phy_qcom_edp/srcversion) \
     <(modinfo -F srcversion $(modinfo -n phy_qcom_edp)) && echo "module OK"
```

If those differ, whatever you just "tested" was the stock driver.

### Corrections to the record

- The swing-table `[0][1]` experiment is **invalid, not negative.** Do not cite it.
- I re-derived two things this file already stated (that `is_edp` is true via the runtime
  `phy_set_mode_ext` call, and that the v8 vs generic tables are *identical at HBR2*).
  Read this file before theorising. The v8-table hypothesis remains dismissed for the
  reason already recorded here: at HBR2 those arrays are the same objects.

### Live state right now (no reboot since)

- `msm` **not loaded** (blacklist held this boot), `phy_qcom_edp` refcount was 0.
- Instrumented `phy_qcom_edp` (`AC8A39...`) is **loaded right now** via manual reload.
- A `pr_info` was added to `qcom_edp_set_voltages()` printing
  `is_edp / rate / lanes / v / p / swing / emph` **plus a readback of `TXn_TX_DRV_LVL`
  and `TXn_TX_EMP_POST1_LVL` on both tx0 and tx1**.

### NEXT STEP — one command, no reboot needed

```bash
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh v8probe
sudo dmesg | grep 'XXX setvolt'
```

Do **not** reboot first — rebooting re-triggers whatever loads the stock module. If you
must reboot, re-verify srcversion with the `diff` above and `rmmod`/`modprobe` if needed.

Reading the result:

| Observation | Conclusion |
|---|---|
| readback `drv=`/`emp=` **match** written `swing=`/`emph=` | writes land; tables are in play; it becomes a tuning problem |
| readback **does not match** | `TXn_TX_DRV_LVL`/`EMP_POST1_LVL` offsets are wrong for the v8 PHY — tables were never the issue |
| `is_edp=0` | contradicts this file's earlier finding; the DP v8 table is in play, re-open that question |
| **no line at all** | `qcom_edp_set_voltages()` returns early — the `0xff` guard or `com_ldo_config()` — and no drive level is ever programmed |

### Files touched

- `scripts/edp-train-probe.sh` — kprobe fixes (see below), plus `error_log` surfacing on
  probe failure so this can never fail silently again.
- `patches/glymur-edp-swing-v8-DIAGNOSTIC.patch` — the swing change. **Diagnostic only,
  do not upstream.** Does not yet include the `pr_info` instrumentation.
- `patches/phy-qcom-edp.ko.orig` — pristine stock module for revert.
- `/boot/initramfs-7.1.0-glymur-clean2.img.known-good` — pre-dracut initramfs backup.

To revert the driver entirely:
```bash
sudo cp ~/Projects/zenbook-a16-linux/patches/phy-qcom-edp.ko.orig \
        /lib/modules/$(uname -r)/kernel/drivers/phy/qualcomm/phy-qcom-edp.ko
sudo depmod -a && sudo dracut --force /boot/initramfs-$(uname -r).img $(uname -r)
```

### kprobe gotchas (cost an hour, now fixed in the script)

- `drm_dp_channel_eq_ok` / `drm_dp_clock_recovery_ok` live in **`drm_display_helper`**,
  which is not loaded when the script installs probes (msm pulls it in later). A bare
  symbol name is unresolvable -> `EINVAL`. Use the `MOD:SYM` form for a deferred probe.
- **A deferred module probe cannot use `$arg1`.** The kernel can't verify the probe is at
  function entry until the module loads, so it rejects `$arg*` with
  `"$arg* can be used only on function entry or exit"`. `$retval` is exempt — which is
  why the `r:` probes worked and the `p:` ones didn't. Use raw arm64 registers
  (`%x0`, `%x1`) instead; no entry check, and at offset 0 they are arg1/arg2.
  **This is arch-specific** — on x86_64 it would be `%di`/`%si`.
- `$T/error_log` records the real reason for any `kprobe_events` write failure. Always
  read it; the bare shell error is just `write error: Invalid argument`.

---

## One-line status (as of test62/test63) — SUPERSEDED 2026-07-24 19:57

> ⛔ **Historical.** The `-110` wall described in this section is **gone** — HBR3 clears
> it. See the RESULT block at the top of this file. Kept for the reasoning trail.

**test62 BOOTED AND THE CLOCK FIX WORKED — the pixel clock runs for the first time.
The panel is still dark, now blocked one layer higher on eDP link training `-110`.**

### test62 result (2026-07-20 20:50) — verified

- `dptx3` gone from `clk_orphan_summary` — **not orphaned**.
- **No `-EBUSY`, no Oops.** `enable_mainlink_clocks END rc=0`.
- Clocks running and claimed by `af6c000.displayport-controller`:

| clock | test58 | test62 |
|---|---|---|
| `faac00.phy::vco_div_clk` | 0 | **1,350,000,000** |
| `disp_cc_mdss_dptx3_pixel0_clk_src` | 0 | **532,224,000** |
| `disp_cc_mdss_dptx3_link_clk_src` | 0 | **540,000,000** (HBR2) |

- `eDP-1` connected/enabled, modes `2880x1800`, `dp_aux_backlight` 716/2047.

**The machine did not crash.** The script ran to completion and wrote all three logs. No
Oops, panic, or watchdog anywhere. The screen goes black at
`Console: switching to colour frame buffer device` — msm takes the console from simplefb
and hands it to a display with no trained link. Expect a black screen on every display
test from here; work over SSH.

### The current wall

```
[124.191] *ERROR* link training #2 on phy 0 failed. ret=-110
[124.230] *ERROR* Unexpected DP AUX IRQ 0x01000000 when not busy
          x3 attempts, then msm_dp_ctrl_on_link END rc=-104
```

Logs: `logs/test62-prebind.log`, `test62-msm-bind.log`, `test62-RESULT.log`.

### Link-training investigation — what's established

**The PLL is fine. `test62b` settled it — kretprobe returns, all zero:**

```
phycfg (qcom_edp_phy_configure)     arg1=0x0
phyv8  (qcom_edp_phy_power_on_v8)   arg1=0x0    <- C_READY_STATUS lock poll SUCCEEDED
phypo  (qcom_edp_phy_power_on)      arg1=0x0    <- the value msm discards
```

- **`0x01000000` is BIT(24) = `DP_INTR_PLL_UNLOCKED`** (`dp_reg.h:36`), not an AUX error —
  `msm_dp_aux_isr` (`dp_aux.c:461`) logs any bit it sees while `!cmd_busy`. **But it is a
  RED HERRING.** Timestamps show it fires *after* each training failure, during the PHY
  re-power in the retry loop: `197.507` train fail → `197.5456` AUX IRQ + `phyv8`/`phypo`
  re-power. It is a consequence of the retry, not a cause. Do not chase it again.
- `dp_ctrl.c:1803-1804` does discard the return of `phy_configure()` and `phy_power_on()`.
  Worth an upstream patch on principle, but **it is not our bug** — both return 0.
- Rates in `clk_summary` are what the clock framework *programmed*, not proof of PLL lock.
  (Still true; we just now have independent proof the PLL does lock.)

**Where the `-110` actually comes from:** `dp_ctrl.c:1596` — plain loop exhaustion.
`msm_dp_ctrl_link_train_2` retries channel EQ 6 times (`maximum_retries = 5`, `0..5`),
never reaches `drm_dp_channel_eq_ok`, returns `-ETIMEDOUT`. Not an AUX timeout.

**Clock recovery PASSES, equalization FAILS.** `link_train_1` succeeds every time; only
`link_train_2` fails (`dp_ctrl.c:1604-1616`). The sink locks to the clock — so lanes,
PLL, and basic signalling work. The failure is specifically in EQ / drive levels.

**Lane fallback confirmed.** The 3 failures per bind are 4 lanes -> 2 -> 1, all at HBR2.
`dp_debug` after the run:

```
drm_dp_link:  rate=540000  num_lanes=4  capabilities=1
dp_link:      num_lanes=1  bw_code=20 (HBR2)  lclk=540000000  v_level=0  p_level=1
```

`num_lanes=1` is the post-fallback state, not the negotiated one. **Rate is never reduced
— only lanes.** Failing identically at 4, 2, and 1 lane is a strong hint the problem is
not lane-specific.

**DT link config is correct:** `data-lanes = <0 1 2 3>`, `link-frequencies` = RBR / HBR /
HBR2 / HBR3 (1.62 / 2.7 / 5.4 / 8.1 GHz).

**Swing-table version mismatch — real but NOT our bug.** `glymur_phy_cfg` is the only
config pairing a v8 DP table with the *generic* eDP table
(`.dp_swing_pre_emph_cfg = &dp_phy_swing_pre_emph_cfg_v8`,
`.edp_swing_pre_emph_cfg = &edp_phy_swing_pre_emph_cfg`; there is no
`edp_phy_swing_pre_emph_cfg_v8` upstream). **However** `dp_phy_swing_pre_emph_cfg_v8`
differs from generic *only* in `pre_emphasis_hbr_rbr` — its `hbr3_hbr2` arrays are the
same objects. At HBR2 the v8 and generic tables are identical, so this cannot explain the
failure. Worth an upstream note; do not "fix" it expecting a lit panel.

**Ruled out — the eDP submode path is correct.** `msm_dp_desc_glymur` has our controller
at `0x0af6c000`; `is_edp` derives from the connector type (`dp_display.c:1390`), which is
eDP because the node has an `aux-bus/panel` child — hence `eDP-1` and
`msm_edp_bridge_ops`. So `msm_dp_init_sub_modules` does call
`phy_set_mode_ext(PHY_MODE_DP, PHY_SUBMODE_EDP)` (`dp_display.c:773`), which sets
`edp->is_edp = true` at runtime, overriding the probe default. The eDP swing/pre-emphasis
table, the eDP `ldo_config`, and the `aux_cfg[8]` path are therefore all correct. Note
`glymur_phy_cfg` does *not* set `.is_edp` — that is fine, but it means the flag is only
correct because of the runtime `set_mode` call. Don't "fix" the cfg without checking this.

Our eDP PHY DT node matches upstream `glymur.dtsi:2366` exactly (`qcom,glymur-dp-phy`,
same reg/clocks/power-domains).

### NEXT: boot `test63` and run `scripts/test63-run.sh`

GRUB entry **`Fedora (glymur A16, test63 - test62 + eDP link capped to HBR)`**
(id `fedora-glymur-test63`), DTB `/boot/glymur/glymur-a16-test63.dtb`, DTS `dts/test63.dts`.

Both open questions in one boot:

1. **Rate cap (the single variable).** `link-frequencies` on the eDP endpoint truncated
   from RBR/HBR/HBR2/HBR3 to **RBR/HBR**, so `max_dp_link_rate` = 270000 (HBR).
   `msm_dp_link_link_frequencies` (`dp_link.c:1215`) reads element `cnt-1` as the cap.
   Diff vs test62 is exactly one line.
2. **`drm.debug=0x100`** (DRM_UT_DP) added to the cmdline — pure observability, not a
   second variable. Gives the per-retry `link_status[]` from
   `drm_dp_dpcd_read_phy_link_status`.

```bash
# test63-run.sh was folded into edp-train-probe.sh — use that instead:
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh test63hbr
```

The script reports which DTB is live (HBR vs HBR2) rather than refusing (i.e. you booted test62 by
mistake) and prints a VERDICT line: EQ succeeded at HBR -> rate/signal-integrity
dependent; EQ still fails -> something structural.

**Expect the panel to stay dark either way.** HBR x4 = 8.64 Gbps effective, but the
native mode needs ~12.8 Gbps (532 MHz pixel clock x 24 bpp). This run is diagnostic —
EQ success at HBR is the result we're after, not a lit screen. If EQ does pass at HBR,
the follow-up is drive levels at HBR2, not living at HBR.

Backups: `/boot/grub/grub.cfg.bak-pre-test63`.

### Background — why the link_status bytes matter

We know EQ fails; we do **not** know why. The missing data is the per-retry
`link_status[]` from `drm_dp_dpcd_read_phy_link_status` — which lanes fail, and whether
it's symbol lock, interlane align, or EQ-done. msm logs this via `drm_dbg_dp`, which is
DRM_UT_DP = **`drm.debug=0x100`** (currently unset).

Boot test62, then before binding msm:

```bash
sudo sh -c 'echo 0x100 > /sys/module/drm/parameters/debug'
sudo ~/Projects/zenbook-a16-linux/scripts/test62b-phyprobe.sh   # probes are harmless, keep them
```

Read the `adjust_levels` / `link_status` lines around each of the 3 attempts. That tells
us whether to chase drive levels, the panel's own EQ behaviour, or a rate fallback that
msm never attempts (it only drops lanes, never rate — forcing RBR/HBR is a candidate test).

**Tooling notes.** bpftrace is installed but unusable — `/lib/modules/$(uname -r)/build`
points at `kernel-build/usb-out`, which has no headers, so clang can't find `kconfig.h`.
Raw ftrace kprobes need no headers and are verified working. Also: `test62b` failed to
clear `kprobe_events` at exit ("Device or resource busy") because the events were still
enabled — disable `events/kprobes/enable` first. Harmless; probes were cleaned up by hand.

**Note the display manager here is `plasmalogin.service` (aliased `display-manager`).
It is NOT sddm** — `systemctl stop sddm` is a silent no-op and left Plasma compositing
to the dead display during the first test62 run. Fixed in `scripts/test62-run.sh`.

---

## The bug

`dispcc-glymur.c:25-44` resolves its parent clocks **by index** into the DT `clocks`
array. test58-edp has the eDP PHY (`phy@faac00`, = `mdss_dp3_phy`, phandle `0xf7`) at
index 2-3 — the **DP0** slot — which shifts everything down:

| idx | driver expects | test58-edp has | |
|---|---|---|---|
| 0-1 | `DT_BI_TCXO`, `DT_SLEEP_CLK` | `&rpmhcc 0`, `&sleep_clk` | ok |
| 2-3 | `DT_DP0_PHY_PLL_*` | **`&phy@faac00 0,1`** ← eDP PHY | wrong |
| 4-5 | `DT_DP1_PHY_PLL_*` | `&phy@fd5000 1,2` | shifted |
| 6-7 | `DT_DP2_PHY_PLL_*` | `&phy@fde000 1,2` | shifted |
| 8-9 | **`DT_DP3_PHY_PLL_*`** | **`&phy@88e1000 1,2` — `status=disabled`** | wrong |
| 10-17 | dsi / standalone | zeros | ok |

`DT_DP3_PHY_PLL_LINK_CLK` therefore resolves to `phy@88e1000`, which is **disabled** and
never registers a clock provider.

### The full failure chain

1. `disp_cc_mdss_dptx3_link_clk_src` and `dptx3_pixel0_clk_src` can't resolve a parent →
   both are **orphaned**. Observable live with msm *not even loaded*:
   `grep dptx3 /sys/kernel/debug/clk/clk_orphan_summary`
2. Orphan ⇒ `best_parent_hw == NULL`.
3. The DP node's `assigned-clock-parents` tries to reparent to `faac00.phy::link_clk` —
   but faac00 sits in the **DP0** slot, so it isn't a legal parent of dptx3 → **`-EBUSY`**
   on *both* clocks (t+83.478 link, t+83.479 pixel0).
4. Later `clk_byte2_determine_rate` (clk-rcg2.c:1057) does
   `clk_hw_round_rate(req->best_parent_hw = NULL, rate)` → **kernel Oops**,
   `pc : clk_hw_round_rate+0x44`, via `msm_dp_ctrl_enable_mainlink_clocks+0x98`.

Fingerprint: dptx0/1/2 are **not** orphaned (parented to XO, 19.2 MHz). Only dptx3.

---

## test62 — BOOTED, clock fix verified (see result above)

GRUB entry: **`Fedora (glymur A16, test62 - dispcc clocks[] dp3 slot fixed + pKVM)`**
(id `fedora-glymur-test62`)

| | |
|---|---|
| DTB | `/boot/glymur/glymur-a16-test62.dtb` |
| DTS | `dts/test62.dts` (baseline for diff: `dts/test58-edp.dts`) |
| Kernel | `vmlinuz-7.1.0-glymur-clean2` |
| pKVM | **ON** — required, do not drop |
| msm | blacklisted at boot, bound by the script |

**The diff is exactly one line** of 7,555 — the dispcc `clocks` array, `0xf7` moved from
the DP0 slot to the DP3 slot. This now matches upstream `glymur.dtsi:4586` verbatim.

Boot it, then:

```bash
sudo ~/Projects/zenbook-a16-linux/scripts/test62-run.sh
```

The script gates itself. **Stage 1 runs before msm loads** and greps `clk_orphan_summary`
for dptx3 — that alone proves or kills the hypothesis at zero risk. On FAIL it stops
before touching msm, so you can just reboot back. On PASS it stops sddm, starts an
unbuffered capture, binds msm, and writes `logs/test62-RESULT.log`.

### What to expect

- Stage 1 passes — high confidence, it's a direct consequence of the index mapping.
- No `-EBUSY`, no Oops — high confidence, same reasoning.
- **Panel actually lights — unknown.** Link training is the next thing that can fail, and
  `-110` there is the oldest ghost in the archive. This gets us to that question for the
  first time; it does not answer it.

Expected non-regression: `phy@88e1000` is disabled, so after the fix **dptx2** will orphan
instead. DP2 is an external port we don't use. Harmless — don't mistake it for a new bug.

---

## Retired — do not spend time on these

- ~~"PHY PLL ordering / reparent is too early"~~ — wrong. The reparent fails because the
  parent is unresolvable, not because it's early.
- ~~Stop sddm before binding~~ — good hygiene, but not the bug. The Oops is inside
  `modprobe`, in probe, before userspace sees a connector.
- ~~Drive the modeset with `modetest` / `fbdev=0`~~ — same reason.
- ~~"clean3" with `dpu_reg_write` instrumentation~~ — aimed at DPU register programming;
  this was a DT indexing error.
- The archive's §4 "TrustZone XPU wall, impossible without a Gunyah port" is superseded —
  the atomic commit completes with no reset.
- Also ruled out and settled: SMMU faults, missing panel node, gpucc
  (`no GPU device was found` is harmless).

---

## Hard-won facts — don't relearn these

- **pKVM is REQUIRED.** Correct to drop for booting *test57*; wrong for test58/test62.
- **Pin 18 must be free in `gpio-reserved-ranges`.** test55/clean2/test57 reserve it,
  making the panel's `enable-gpios = <&tlmm 18>` unresolvable. test58-edp and test62 free
  it, matching test48. Pin 70 was already free. Verify by decoding the (start,count)
  pairs: the range must stop at 17 and resume at 19.
- **`glymur-a16-clean2.dtb` is byte-identical to `glymur-a16-test55.dtb`** — clean2 was a
  kernel change (keyboard drivers), not a DT change.
- **`/proc/cmdline` cannot distinguish clean2 from test58/test62.** These GRUB entries use
  the `devicetree` directive, and their `linux` lines are byte-identical. To tell which
  DTB is live, read `/proc/device-tree` — check mdss/dispcc `status` and the decoded
  `gpio-reserved-ranges`.
- **`modprobe msm` exits 139 (segfault) but loads fine.** Ignore rc; check `/sys/class/drm/`.
- **Log unbuffered.** `dmesg -w > file` lost everything past 128K on a freeze. Use `stdbuf -o0`.
- netconsole is useless for the hard-freeze mode; pstore is empty for the same reason.
- There is an **upstream `glymur.dtsi`** in `~/kernel-build/linux-src` — use it as the
  reference for any DT question. It is how this bug was found.

---

## Networking during display tests

The old "MDSS + msm ⇒ Wi-Fi dies" trap is **not reproducing** after adjusting when ath12k
loads. In the test58 log, Wi-Fi associates at t+29.4 and there are no ath12k lines at all
after t+35.0 — no MHI error, no firmware crash — while msm binds at t+83.5.

Note there is also a **USB Ethernet dongle** (`enu1u3`, r8153_ecm) holding the default
route at metric 100 vs Wi-Fi's 600, so SSH survives regardless. Both links are up.

---

## Evidence on disk

`~/Projects/zenbook-a16-linux/logs/`

| File | What |
|---|---|
| `test58-pkvm-FINAL-dmesg.log` | the breakthrough run — contains the `-EBUSY` pair and the Oops |
| `test58-pkvm-msm-bind.log` | same run, unbuffered live capture |
| `test58-pkvm-connector-state.txt` | eDP-1 + backlight sysfs state |
| `test58-pkvm-prebind.log` | baseline before binding |
| `test57-nopkvm-FULL-dmesg.log` | first boot with dispcc + eDP PHY bound |

---

## Boot menu

`default=0` is test55 (known-good), timeout 10s. Backups:
`/boot/grub/grub.cfg.bak-pre-test62`, `.bak-pre-test57`.

| Entry | Purpose |
|---|---|
| `fedora-glymur` | test55 — known-good fallback, never edit in place |
| `fedora-glymur-clean2` | clean2 kernel, display off — daily driver |
| `fedora-glymur-test58-pkvm` | XPU wall passed; Oops on the orphaned clock |
| **`fedora-glymur-test62`** | **the fix — boot this** |
| `fedora-glymur-test57*` | superseded, pin 18 still reserved |

---

## Working style

Single-variable tests. Ground claims in source/dumps, not symptoms — the root cause on
this project has reversed three times. Keep a known-good entry; never edit the fallback.
Few steps, one-shot chained commands. Claude Code CLI only. Results are meant to go
upstream, so keep diffs clean.

⚠️ `memory-archive/a16-disk-and-fedora-daily.md` holds plaintext credentials. Keep this
tree private.

---

## 2026-07-25 — teardown bisect ARMED (in progress)

Since Linux emits **no fault** at the crash (netconsole with a provably empty
queue and ramoops on a genuine test69 cycle both came back blank — `kmsg_dump`
never ran, the SoC is reset externally), there is no trace to read. So: skip one
teardown step at a time and see whether the crash stops. The result is binary
and needs no log.

**Built:** one `msm.ko` with a runtime-writable bitmask, so all four candidates
are selectable without rebuilding. `msm` srcversion **`81C04A37E454BDD35514CE7`**.

| bit | skipped call | file |
|-----|--------------|------|
| 1 | `msm_dp_ctrl_phy_exit()` | `dp/dp_display.c:473` |
| 2 | DP core clk disable | `dp/dp_ctrl.c:1749` |
| 4 | `dev_pm_opp_set_rate(dev, 0)` | `disp/dpu1/dpu_core_perf.c:406` |
| 8 | `icc_set_bw(path, 0, 0)` | `disp/dpu1/dpu_core_perf.c:248` |

Every skip is **symmetric** — the matching enable path is already guarded on the
same state flag (`!dp->phy_initialized`, `ctrl->core_clks_on`), so a skipped
disable makes the re-enable a correct no-op. Bits 4 and 8 skip *only* in the
zero direction, so normal operation is untouched.

**Run:** `/usr/local/bin/glymur-bisect.sh <0|1|2|4|8>` — sets the param, verifies
readback, stamps it into kmsg, then chains to `glymur-arm-and-fire.sh`. It
refuses to run if `/sys/module/msm/parameters/glymur_skip` is absent, which is
the "installed but did not reboot" trap.

**Installed and verified 2026-07-25:** build tree, `/lib/modules/.../msm.ko` and
the copy inside `/boot/initrd.img-7.1.0-glymur-gdsc1` are all byte-identical
(`cmp`, not srcversion). Backup of the pre-bisect module:
`~/kernel-build/msm.ko.bak-pre-bisect`.

⚠️ **Two build traps hit this session:**
- `srcversion` **cannot** see catalog-only changes — `has_idle_pc` true vs false
  produce byte-different modules with the *identical* srcversion. Verify with
  `cmp` against a known-good copy. This overrides the old "diff the srcversion"
  rule.
- With `M=` + `O=`, the fresh `msm.ko` lands in the **source** tree
  (`linux-src/drivers/gpu/drm/msm/msm.ko`), *not* in `usb-out/`. The copy under
  `usb-out/drivers/gpu/drm/msm/` is stale — do not verify against it.
- `msm` is in the initrd; `cp` + `depmod` alone boots the old module. Always
  `dracut --force /boot/initrd.img-$(uname -r) $(uname -r)`.

**Status:** staged, not yet run. Needs a reboot (running msm is still
`54594C3A39F83EAAD4C51A2`). First cut is **bit 1**, since two of three captures
died at or just after `msm_dp_display_host_phy_exit`.

---

# ★ 2026-07-25 08:55 — BIT 1 RAN. It MOVED the crash. This is the live state.

**First causal handle in the entire hunt.** `glymur_skip=1` (skip
`msm_dp_ctrl_phy_exit()`) **survived 60 s of screen-off** — nothing had ever done that —
and then **hard-reset the SoC on screen-ON**, during/just after `kscreen-doctor --dpms on`.

## How we know it was a hard reset and not a dropped ssh

In `/var/log/glymur-kmsg.log` the `SURVIVED 60s` marker (line 11788) is followed
immediately by a fresh `===== glymur kmsg logger up =====` banner with timestamps
restarting at 6.0 s, and **no shutdown sequence in between**. The `Connection reset by
peer` on the ssh session was the box going down.

## What this does and does not establish

**Does:** `msm_dp_ctrl_phy_exit()` is causally involved in the screen-off death.

**Does not:** isolate it. The bisect's founding premise — *"every skip is symmetric,
because the matching enable path is guarded on the same state flag"* — is **DISPROVEN for
bit 1**. It leaves `phy_initialized` set, so the enable path skips
`msm_dp_ctrl_phy_init()`; but the DP core clocks still go off and
`msm_dp_pm_runtime_suspend` still runs in between, so the enable came up on a PHY that had
lost its programming. **Symmetric in the flag, not in the hardware.** Bits 4 and 8 skip
only in the zero direction and do remain genuinely symmetric.

Unifying reading of both deaths: *an access to a display block whose real power/clock
state does not match what the driver believes.*

## Mechanism, grounded in source

`msm_dp_ctrl_phy_exit()` (`dp/dp_ctrl.c:1959`) = `msm_dp_ctrl_phy_reset()` +
`phy_exit()`, and `qcom_edp_phy_exit()` (`phy/qualcomm/phy-qcom-edp.c:1235`) =
`clk_bulk_disable_unprepare()` + `regulator_bulk_disable()`.

That fires ~120 ms **before** the CRTC disables. So everything downstream — core clk to
0 Hz, `icc_set_bw(...,0,0)`, crtc 108→111 — touches display blocks whose supplies are
already dropped. Coherent with `synchronous external abort` / XPU violation, and it
explains the 120 ms gap and why only the 4th CRTC dies.

**A real fix reorders or defers phy_exit until after the DPU teardown. It does not skip
it** — skipping leaves the eDP PHY clocked and powered forever.

## Free bonus: second confirmation there is no Oops

That was a genuine test69 → crash → test69 cycle (ramoops node present, pre-flight
verified) and `/sys/fs/pstore/` came back **empty**. Independent re-confirmation that
`kmsg_dump` never runs and the SoC is reset externally. The trace hunt stays closed.

## REBUILT — msm srcversion `0A813C6088270650CDB9681`

Was `81C04A37E454BDD35514CE7`. This is a **code** edit, so the srcversion check is valid
here (unlike the catalog-only trap).

| bit | skipped | site |
|---|---|---|
| 1 | `msm_dp_ctrl_phy_exit()`, leaves `phy_initialized` set | `dp/dp_display.c:473` |
| 2 | DP core clk disable | `dp/dp_ctrl.c:1749` |
| 4 | `dev_pm_opp_set_rate(dev, 0)` | `disp/dpu1/dpu_core_perf.c:406` |
| 8 | `icc_set_bw(path, 0, 0)` | `disp/dpu1/dpu_core_perf.c:248` |
| **16** | `phy_exit()` skipped **but `phy_initialized` cleared**, so enable re-runs `phy_init()` | `dp/dp_display.c:473` |
| **32** | only `msm_dp_ctrl_phy_reset()`; still calls `phy_exit()` | `dp/dp_ctrl.c:1967` |

Installed to `/lib/modules/7.1.0-glymur-gdsc1/…/msm.ko`, `depmod -a` done, and
`/boot/initrd.img-7.1.0-glymur-gdsc1` rebuilt **and verified** to carry
`0A813C6088270650CDB9681` (ADSP firmware confirmed still inside). Kernel, DTB and GRUB
unchanged — test69 is still the default. Just reboot.

## ⏭️ NEXT — reboot, then run bit 16

```bash
cat /sys/module/msm/srcversion          # must be 0A813C6088270650CDB9681
/usr/local/bin/glymur-netconsole-arm.sh # + a listener on 192.168.8.22
DRMDEBUG=0x100 /usr/local/bin/glymur-bisect.sh 16
```

- **Survives off AND on** → pins the killer on `qcom_edp_phy_exit()`'s
  clk/regulator disable firing too early. Next is bit 32 to split the reset register from
  the clk/regulator half, then the reorder patch.
- **Dies on off** → phy_exit is not the trigger after all; bit 1's survival was an
  artifact of the PHY staying powered, and the next cuts are bits 2/4/8.

Also still worth one run: **`glymur-bisect.sh 0`** as a proper control on this module.

## Script changes (both from what bit 1 exposed)

- `glymur-arm-and-fire.sh` **now fires `dpms on` and heartbeats 30 s afterwards.** The old
  version printed `RESULT: survived` and exited *before* the restore — which is exactly how
  the bit-1 screen-ON death nearly got scored as a pass.
- `glymur-arm-and-fire.sh` takes **`DRMDEBUG=`** (default 0). Use `0x100` when you expect
  to survive and want the teardown trace as proof the sequence completed rather than
  diverged. The clean-pipe rule only matters when you expect to die.
- `glymur-bisect.sh` **refuses masks 16/32 if the running srcversion is the old build** —
  those bits don't exist there, so they would skip nothing and fake a PASS.

Backups: `~/kernel-build/msm.ko.bak-bisect-bit1-81C04A37`,
`/boot/initrd.img-7.1.0-glymur-gdsc1.bak-pre-bit16`,
`/usr/local/bin/glymur-{bisect,arm-and-fire}.sh.bak-pre-bit16`.

---

# ▶ 2026-07-25 10:35 — BIT 64 (deferred phy power-down) BUILT + INSTALLED. Reboot and run it.

msm srcversion **`71AEC22EF8E61818BA215DF`** (was `0A813C60...`); phy stays
`42EC3127A7D95F116670B08`. Both verified **inside** `/boot/initrd.img-7.1.0-glymur-gdsc1`,
ADSP firmware still present. Kernel/DTB/GRUB untouched, test69 still default.

```bash
cat /sys/module/msm/srcversion          # must be 71AEC22EF8E61818BA215DF
/usr/local/bin/glymur-netconsole-arm.sh # + listener on 192.168.8.22
OFFWAIT=10 ONDEBUG=0x104 /usr/local/bin/glymur-bisect.sh 64
```

## The full bisect result table

| mask | what it skips | screen-off | screen-on |
|---|---|---|---|
| 0 | baseline | **dies** | — |
| 1 | `phy_exit()`, leaves `phy_initialized` set | survives | **dies** |
| 4 | `dev_pm_opp_set_rate(0)` | **dies** | — |
| 8 | `icc_set_bw(0,0)` | **dies** | — |
| 16 | `phy_exit()`, clears flag so enable re-inits | survives | **dies** |
| 32 | `phy_reset` only, still calls `phy_exit()` | **dies** | — |
| PHYSKIP=1 | `clk_bulk_disable_unprepare` only | **dies** | — |
| PHYSKIP=2 | `regulator_bulk_disable` only | **dies** | — |
| PHYSKIP=3 | both halves of `qcom_edp_phy_exit()` | survives | **dies** |

**What that establishes.** `msm_dp_ctrl_phy_exit()` is the screen-off trigger, and **both
of its halves are independently lethal** — so it is not a specific clock or a specific
rail, it is that the eDP PHY gives *anything* up ~120 ms before the DPU has finished
tearing down. Bit 32 exonerates `msm_dp_ctrl_phy_reset()`. Breaking the *far* end instead
(bits 4 and 8, the things that touch the block afterwards) does **not** help.

**The bind we were in.** Every config that survives the off does so by leaving the PHY
powered, and every one of those then dies on screen-ON. A clean off→on cycle has never
happened on this machine. Bit 64 is the only arrangement that gets both a surviving off
*and* a properly exited PHY.

## What bit 64 does

Splits `msm_dp_ctrl_phy_exit()`. `msm_dp_ctrl_phy_reset()` stays **inline** — it is an AHB
register write that must happen while the DP core clocks are still on, so deferring it
would manufacture a *fresh* unclocked access, and bit 32 already showed it is not the
trigger. Only `phy_exit()` (the `clk_bulk_disable_unprepare` + `regulator_bulk_disable`
half, which touches no registers) moves to a **1 s delayed work item**, landing clear of
the fatal window while the panel is still blanked.

`msm_dp_display_host_phy_init()` calls `cancel_delayed_work_sync()` first; if it catches
the work still pending it does the power-down inline right there. So the exit happens
**exactly once per init** in either ordering and the PHY driver's refcounts stay balanced —
unlike bits 1/16, which drift by one every cycle.

New helpers `msm_dp_ctrl_phy_reset_only()` / `msm_dp_ctrl_phy_power_down()` in `dp_ctrl.c`
(declared in `dp_ctrl.h`). Work item `INIT_DELAYED_WORK`'d in `msm_dp_display_probe()`,
`cancel_delayed_work_sync`'d in `msm_dp_display_remove()` before the sub-modules are torn
down — the work fn dereferences `dp->ctrl`.

## Reading the result

- **Survives off AND on** → ordering theory confirmed; this is the shape of the upstream
  patch. Tidy it up (drop the bisect bits, make it unconditional) and it is submittable.
- **Survives off, dies on** → the ON crash is independent of the PHY. Next target is the
  DPU commit path, where it already demonstrably dies — see below.
- **Dies on off** → 1 s is not late enough, or the reset half matters after all.

## The screen-ON crash — separate problem, first trace captured

`ONDEBUG=0x104` finally made it visible (every earlier run used `drm.debug=0` or `0x100` =
`DRM_UT_DP`; the DPU logs under `DRM_UT_KMS` = 0x04, so we had been watching the wrong
subsystem):

```
560.926  ===== FIRING dpms on =====
560.940  [drm:dpu_rm_reserve] reserving hw for crtc 108  x4  (num_lm:2 num_dsc:0 num_intf:1)
560.959  dpms on returned rc=0
561.001  [drm:drm_mode_addfb2] [FB:115]
561.001  [drm:dpu_rm_reserve] reserving hw for crtc 108
         (dead - 58 ms after the fire)
```

**Not one `msm_dp_*` line.** No encoder enable, no `msm_dp_display_enable`, no PHY init. It
dies inside the atomic commit just after resource-manager reservation. Identical after a
5 s blank and a 60 s blank, so DPU runtime-suspend duration is **not** the variable.

Unknown and load-bearing: whether this crash is **pre-existing or induced**. The baseline
always died on the off first, so a successful screen-on has never been observed here.

## Script knobs added this session

- `OFFWAIT=` — seconds blanked before restoring (default 60).
- `ONDEBUG=` — drm.debug raised *immediately before* `dpms on`, so the off teardown does not
  flood netconsole and the ON path gets a clean pipe.
- `DRMDEBUG=` — drm.debug during the off fire (default 0).
- `glymur-arm-and-fire.sh` now **fires `dpms on` and heartbeats 30 s afterwards**. The old
  version printed `RESULT: survived` and exited before the restore, so the first screen-ON
  death showed up only as an ssh `Connection reset by peer` and was nearly scored a PASS.
- `glymur-bisect.sh` refuses masks whose bits the running module does not implement, and
  refuses `PHYSKIP` with an msm mask that skips `phy_exit` entirely (it would test nothing
  while looking like a clean result).

## Traps banked this session

- **`__clk_get_enable_count()` has no `EXPORT_SYMBOL`** — declared in `clk-provider.h`,
  absent from `Module.symvers`. A module cannot call it; it will not link.
- **`glymur-clkwatch.sh`'s first run was VOID** — counts never moved because the teardown
  never ran, and with `drm.debug=0` the script could not tell that from "released nothing".
  It now asserts teardown evidence in dmesg and exits 2 rather than printing numbers.
- **pstore has come back empty after every crash this session** (three genuine
  test69→crash→test69 cycles). No Oops, SoC reset externally. The trace hunt stays closed.

Backups: `~/kernel-build/msm.ko.bak-pre-bit64-0A813C60`,
`~/kernel-build/msm.ko.bak-bisect-bit1-81C04A37`,
`~/kernel-build/phy-qcom-edp.ko.bak-stock-D981A7A0`,
`/boot/initrd.img-7.1.0-glymur-gdsc1.bak-pre-bit64` (and `.bak-pre-physkip`,
`.bak-pre-bit16`), `/usr/local/bin/glymur-{bisect,arm-and-fire}.sh.bak-pre-bit16`.

---

# ★★ 2026-07-25 10:45 — NETCONSOLE HAS BEEN LYING ABOUT DEATH TIMES. Read this first.

**`netconsole` stops delivering the moment TZ/ADSP crashes**, because it runs over Wi-Fi
and the Wi-Fi path goes down with the ADSP. Every netconsole capture therefore *looks* like
"instant death right after `dpms off returned rc=0`" when the box actually kept running for
seconds afterwards.

**`/var/log/glymur-kmsg.log` is the authoritative channel.** The fsync logger is local and
survives the TZ event. This file already said "after any crash read
`/var/log/glymur-kmsg.log` FIRST" — several rounds of 2026-07-25's verdicts were read off
netconsole instead and were wrong about timing.

## Corrected result table, re-derived from `/var/log/glymur-kmsg.log`

| boot | mask | last heartbeat reached | TZ fatal | died at |
|---|---|---|---|---|
| 10 | msm=1 | t+60s off | no | 113.9 s, after `SURVIVED 60s - restoring` |
| 12 | msm=16 | t+60s off, fired ON | no | 130.5 s, after `dpms on rc=0` |
| 14 | msm=16 | t+60s off, fired ON | **YES** | 129.1 s |
| 15 | msm=32 | (none) | no | 426.5 s, after `core_clk_disable stream/link off` |
| 16 | msm=32 | **t+5s off** | no | 62.5 s |
| 18 | PHYSKIP=1 | **t+5s off** | **YES** | 117.1 s |
| 19 | PHYSKIP=2 | (none) | **YES** | 56.2 s |
| 20 | PHYSKIP=3 | t+60s off, fired ON | no | 434.7 s |
| 21 | PHYSKIP=3 | t+60s off | no | 579.7 s |
| 22 | PHYSKIP=3 | t+5s off, fired ON | no | 561.0 s, after `drm_mode_addfb2 [FB:115]` |
| 23 | msm=8 | (none) | no | 539.1 s, after `dpms off rc=0` |
| 24 | msm=4 | (none) | no | 280.1 s |
| 27 | msm=64 | **t+5s off** | **YES** | 52.1 s |

**Masks 32, PHYSKIP=1 and 64 all reached `alive t+5s`** — they did NOT die instantly on the
teardown as recorded earlier today. There is a delayed component that was being missed.

## Bit 64 ran exactly as designed — and still died

```
45.472  dpms off returned rc=0
47.138  GLYMUR: deferred phy power-down firing         <- work fired at +1.67s
47.275  qcom_q6v5_pas: Handover signaled, but it already happened
47.288  qcom_q6v5_pas: fatal error received: sys_m_smsm.c:783:err fatal notification from TZ
47.288  remoteproc0: crash detected in adsp: type fatal error -> recovering adsp
50.487  alive t+5s after dpms off                      <- SURVIVED the power-down itself
51.042  ath12k: time out while waiting for get fw stats
52.066  ath12k: time out while waiting for get fw stats
        (dead before the t+10s heartbeat)
```

**The eDP PHY power-down provokes a TrustZone fatal within 137 ms**, which crashes the
ADSP; the SoC goes down ~5 s later during ADSP recovery. First *direct* causal link from
the display power-down to TZ, and it fits "the SoC is reset externally — TZ, secure
watchdog, or hardware."

⚠️ The standing note that the `fatal notification received from TZ` / ADSP watchdog at
07:15 was "a DIFFERENT failure mode — don't conflate" is **now doubtful**. It may have been
the same mechanism all along. Do not rely on that separation without re-checking.

## What this means for the next session

1. **Re-verify earlier verdicts against `/var/log/glymur-kmsg.log`.** Some "dies" are
   probably "survives, then dies of a second thing." Deferring the power-down bought ~5 s
   and changed the failure into a TZ/ADSP one rather than preventing it.
2. **The TZ/ADSP angle is now the live lead**, not DPU register ordering. The deferred
   `qcom-pon` item — reading `PON_REASON` / `POFF_REASON` / `WARM_RESET_REASON` — is no
   longer a nice-to-have; it names the resetting agent, which is now the central question.
3. `glymur-bisect.sh` guard gap fixed: it checked `N & 48`, so **bit 64 could have run
   silently on a module lacking it**. Now `N & 112`.

Module state unchanged: msm `71AEC22EF8E61818BA215DF` (bits 1/2/4/8/16/32/64),
phy `42EC3127A7D95F116670B08` (PHYSKIP 1/2), both in the initrd, test69 default.

---

# ⛔ SUPERSEDED BY THE 2026-07-27 SECTION BELOW — WHEN YOU GET BACK (2026-07-25 version)

⚠️ Step 0's `setsid nohup` command **does not survive the shell** — see the 07-27 section
for the form that works. Step 2's "needs a build and a reboot" framing for the `qcom-pon`
read is **wrong** — it is a live module swap, and the work is already done.
§5 ("what is genuinely settled") is still valid.

## 0. First, stop the box killing itself (30 seconds, no reboot)

The KDE screen inhibitor does **not** survive a reboot and is currently OFF, so an idle
blank will hard-reset the machine on its own.

```bash
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
setsid nohup kde-inhibit --screenSaver --power sleep 86400 >/dev/null 2>&1 &
qdbus-qt6 --literal org.kde.Solid.PowerManagement.PolicyAgent \
  /org/kde/Solid/PowerManagement/PolicyAgent ListInhibitions   # expect two entries, not "{}"
```

Panel brightness is also sitting at 5% from a powerdevil dim — nudge it back up.

## 1. Read the correction above before trusting anything

`2026-07-25 10:45 — NETCONSOLE HAS BEEN LYING ABOUT DEATH TIMES`. Short version:
**netconsole dies with the ADSP, so it under-reports survival. Read
`/var/log/glymur-kmsg.log`, not the netconsole log.** The corrected per-boot table is
there. Several of the day's "died instantly" verdicts were actually "survived 5+ s".

## 2. The live lead is TrustZone, not DPU register ordering

The eDP PHY power-down provokes `fatal notification received from TZ` within **137 ms**,
which crashes the ADSP; the SoC goes down ~5 s later during ADSP recovery. That is a
direct causal link we did not have before.

**Highest-value next task: the PMIC reset-reason read.** `qcom-pon` binds at
`c426000.spmi:pmic@0:pon@1300` but upstream only *writes* reboot-mode. ~10 lines of
`pr_info` reading `PON_REASON` / `POFF_REASON` / `WARM_RESET_REASON` would **name the
agent that resets the SoC**. This was parked earlier as "names the killer but doesn't find
the fix" — that judgement is now out of date, because which agent resets us *is* the
open question.

## 3. Everything is installed and ready if you want to run more bisects

No rebuild needed. Just re-arm netconsole (it does not survive a reboot):

```bash
/usr/local/bin/glymur-netconsole-arm.sh          # + listener on 192.168.8.22:
                                                 #   nc -ul 6666 | tee ~/glymur-netconsole.log
OFFWAIT=10 ONDEBUG=0x104 /usr/local/bin/glymur-bisect.sh <mask>
```

| | |
|---|---|
| msm | `71AEC22EF8E61818BA215DF` — bits 1/2/4/8/16/32/64 |
| phy | `42EC3127A7D95F116670B08` — `PHYSKIP=` 1/2 |
| both verified inside | `/boot/initrd.img-7.1.0-glymur-gdsc1` |
| GRUB default | `fedora-glymur-test69` (unchanged) |

**Only untested mask left: `2`** (skip DP core clk disable). Low value — it can only
survive the off by keeping DP clocks on, which reproduces the same screen-ON poisoning as
bits 1/16/PHYSKIP=3.

**After every crash, read `/var/log/glymur-kmsg.log` first.** Use the awk in the 10:45
section to rebuild the table.

## 4. Session work is saved but NOT committed

- `patches/glymur-teardown-bisect-2026-07-25.patch` — the full diff (6 files, 385 lines):
  the `glymur_skip` bitmask incl. bit 64's deferred power-down, the `glymur_phy_skip`
  split in `phy-qcom-edp.c`, and the `msm_dp_ctrl_phy_reset_only()` /
  `msm_dp_ctrl_phy_power_down()` helpers.
- `logs/glymur-kmsg-2026-07-25.log` — **the authoritative log.** Keep this one.
- `logs/glymur-netconsole-2026-07-25.log` — kept for cross-reference; timings unreliable.
- **COMMITTED** to `~/kernel-build/linux-src` branch `glymur-edp-hbr3` as `503e2044c`
  ("drm/msm/dp: glymur eDP teardown crash bisect (diagnostic, not for upstream)"), 6 files,
  +240/-5. The commit message carries the full result table and the reasoning. Working tree
  is clean. **Not pushed** — that is still your call.

## 5. What is genuinely settled (do not re-derive)

- `msm_dp_ctrl_phy_exit()` is the screen-off trigger, and **both halves are independently
  lethal** — not a specific clock, not a specific rail.
- `msm_dp_ctrl_phy_reset()` is **exonerated** (bit 32).
- Breaking the far end instead (bits 4, 8) does **not** help.
- Deferring the power-down 1 s (bit 64) does **not** prevent it — it buys ~5 s and turns it
  into a TZ/ADSP failure.
- The screen-**ON** crash is in the **DPU commit path**, not DP: it dies just after
  `dpu_rm_reserve` with no `msm_dp_*` line at all, identically after a 5 s or 60 s blank.
  Still unknown whether it is pre-existing or induced — no clean off→on cycle has ever
  been observed on this machine.
- pstore empty after every crash. No Oops. The trace hunt stays closed.

---

# ▶▶ 2026-07-27 — mask 2 ARMED, qcom-pon reason dump LANDED

Session opened on a **fresh boot at 05:42 that followed a clean shutdown**, not a crash:
the previous boot's last line in `/var/log/glymur-kmsg.log` is
`systemd-shutdown[1]: Syncing filesystems and block devices.` So `/sys/fs/pstore/` being
empty this time is expected and means nothing. **That clean shutdown is what makes the
PON baseline below trustworthy.**

## 0. Two arrival fixes — the guard, and the command that was wrong

**The documented guard command does not work.** This form —

```bash
setsid nohup kde-inhibit --screenSaver --power sleep 86400 >/dev/null 2>&1 &
```

— launches and then **dies with the shell**. `ListInhibitions` came back `{}` and
`pgrep kde-inhibit` found nothing. An idle blank would still have hard-reset the box.
Use a user unit instead, which survives shell exit:

```bash
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
systemd-run --user --unit=glymur-inhibit --collect kde-inhibit --screenSaver --power sleep 86400
qdbus-qt6 --literal org.kde.Solid.PowerManagement.PolicyAgent \
  /org/kde/Solid/PowerManagement/PolicyAgent ListInhibitions   # expect two entries, not "{}"
```

Verified: two `{"Running Script", "sleep"}` entries. **Still does not survive a reboot.**

⚠️ **`pgrep -a powerdevil` finds nothing even when powerdevil is running** — the process is
`org_kde_powerdevil`. That briefly looked like "powerdevil is dead", which was wrong. It is
running, `plasma-powerdevil.service` is active, and `~/.config/powerdevilrc` still has the
99999s timeouts. Also note every `systemctl` timestamp on this box reads `Jun 26 20:00`
because the RTC starts there — do not read "4 weeks ago" as real uptime.

Brightness was at 5% (`dp_aux_backlight` 103/2047) from a powerdevil dim → raised to 1200.

## 1. Mask 2 — armed, NOT fired

Nothing to build; bit 2 is in the live module. Pre-flight verified clean:
`glymur_skip`=0, `glymur_phy_skip`=0, msm srcversion `71AEC22EF8E61818BA215DF` matches
the script's `EXPECT_SV`, `glymur-kmsg.service` active, screen guard up.

```bash
OFFWAIT=10 ONDEBUG=0x104 /usr/local/bin/glymur-bisect.sh 2
```

netconsole is optional (`glymur-netconsole-arm.sh` + listener on 192.168.8.22) and its
timings are not trustworthy — `/var/log/glymur-kmsg.log` is the authoritative channel.

Expectation: mask 2 can only survive the off by keeping DP core clocks on, which should
reproduce the same screen-ON poisoning as bits 1/16/PHYSKIP=3. This is the last untested
mask and was rated low value; run for completeness.

## 2. ★ qcom-pon reason dump — BUILT, LOADED, BASELINE CAPTURED

**The premise that parked this for two days was wrong.** `qcom_pon` is a loadable module
with **refcount 0**, bound at `c426000.spmi:pmic@0:pon@1300`. It swaps with
`rmmod`/`insmod` and re-probes. **No reboot, no initrd rebuild.**

| | |
|---|---|
| Patch | `patches/glymur-qcom-pon-reason-dump-DIAGNOSTIC.patch` (102 lines) |
| Module | `~/kernel-build/qcom-pon.ko.glymur-reason-dump` |
| srcversion | **`93A35C2AE7855A09CA9DE58`** (stock `4EC3BAF40876D3E6297CB64`) |
| Baseline log | `logs/glymur-pon-baseline-2026-07-27-cleanshutdown.log` |
| Source | `drivers/power/reset/qcom-pon.c` in `~/kernel-build/linux-src` (uncommitted) |

⚠️ **It deliberately contains NO vendor register offsets.** Mainline has no gen3
(pmk8350/pmk8850) reason-register map and the vendor offsets are not published, so
guessing them would violate the project's grounding rule. Instead it dumps **both** PON
peripherals wholesale, 16 bytes per line, one chunk at a time so a single unimplemented
register cannot kill the whole dump. The only offset it asserts is `PON_SUBTYPE` (0x05),
which mainline does document in `drivers/input/misc/pm8941-pwrkey.c`.

### What the baseline established

The DT's `reg-names = "hlos", "pbs"` resolves to two real peripherals and **both
self-identify correctly**: HLOS @0x1300 `subtype=0x09`, PBS @0x800 `subtype=0x08`,
`PERPH_TYPE=0x01` (PON) in both, standard SPMI ID block at 0x00–0x05 consistent.
That validates the read path — the dump is real data, not garbage.

Against the one bit-definition set that **is** in-tree (`drivers/watchdog/pm8916_wdt.c`:
POFF_REASON1 @0x0c BIT(2)=PMIC_WD, POFF_REASON2 @0x0d BIT(5)=UVLO, BIT(6)=OTST3), both
peripherals read `0x00` / `0x01` → **no PMIC watchdog, no UVLO, no thermal shutdown.**
Correct for a clean shutdown. This is a trustworthy zero.

⚠️ **Honest limit:** gen3 may have relocated the reason registers, and 0x0a–0x0d reading
*identically* in both peripherals (`c4 44 00 01`) is mildly suspicious for anything
reason-specific. The bytes that actually **differ** between the two are the interesting
ones: **PBS +0x08 = `0x02`, +0x09 = `0x03`** (HLOS reads 0x00 at both) — and 0x08 is
gen1's `PON_REASON1` offset, making PBS+0x08 the leading candidate. Also non-zero and
unexplained: PBS +0xc6 = `0x7f`, +0xc8 = `0x40`.

### ★ The differential is the experiment — decoding is not required

After the next crash and reboot:

⚠️ **`rmmod` FIRST.** The stock `qcom_pon` loads from the initrd at boot, so a bare
`insmod` fails with `File exists` and silently produces an EMPTY capture — the diff then
looks like "everything vanished" (`1,34d0`). This bit us on the first real use.

```bash
sudo rmmod qcom_pon && sudo insmod ~/kernel-build/qcom-pon.ko.glymur-reason-dump
sudo dmesg | grep GLYMUR-PON | sed 's/^.*GLYMUR-PON: //' > /tmp/pon-postcrash.log
diff logs/glymur-pon-baseline-2026-07-27-cleanshutdown.log /tmp/pon-postcrash.log
```

The registers are latched, so a late read loses nothing — just rmmod and redo it.

Whichever bytes move name the resetting agent, with no vendor spec needed.
**A null result is also informative:** if POFF_REASON1 stays `0x00`, the reset never went
through the PMIC power-off path at all, which points at a warm/TZ-driven SoC reset rather
than anything the PMIC initiated — and that is consistent with the standing
"SoC is reset externally" conclusion.

The registers are latched and survive until read, so the manual `insmod` after reboot
loses nothing. **The initrd was deliberately left alone** — auto-dumping at boot would
need a `dracut` rebuild, which is a documented trap here for no gain.

## 3. Build-tree trap worth knowing

`make O=... drivers/power/reset/qcom-pon.ko` (single-`.ko` target) **regenerates
`Module.symvers` from scratch** and then fails modpost with
`"devm_reboot_mode_register" undefined`. That would have silently destroyed the 32227-line
`Module.symvers` from the full build. It did not — the failure happened before the write,
verified afterwards. Build single modules this way instead:

```bash
cd ~/kernel-build/linux-src && make O=/home/jcasco/kernel-build/usb-out M=drivers/power/reset modules
```

Backup taken this session: `Module.symvers.bak` in the session scratchpad.
Build output dir is `~/kernel-build/usb-out` (`/lib/modules/$(uname -r)/build` → it).

## 4. Not committed

`drivers/power/reset/qcom-pon.c` is modified in `~/kernel-build/linux-src` on branch
`glymur-edp-hbr3` (otherwise clean at `503e2044c`). The patch file is saved in the project
repo; the kernel-side change is **not** committed and **not** pushed.

## 5. Audio, unchanged

Broken again on this boot — the `DSP returned error[1001006] 9` storm from t+23s to t+28s
in the kmsg log. Still parked per Jesse's direction. See `docs/audio-adsp-boot-ordering.md`.

---

# ▶▶▶ 2026-07-27 (later) — MASK 2 RAN AND DIED. FIRST PON DIFF IS IN.

## Mask 2 result: dies on the OFF path, delayed, with no TZ fatal

```
279.547  GLYMUR-BISECT: glymur_skip=2 (skip msm_dp_ctrl_core_clk_disable)
283.639  dpms off returned rc=0
288.653  alive t+5s after dpms off          <- survived the teardown
         (dead before t+10s; OFFWAIT was 10, so it never reached the restore)
```

**No `fatal notification received from TZ`. No ADSP crash. No Oops. No pstore.** Just
silence and a reboot. So mask 2 joins the **delayed-death** group (masks 32, PHYSKIP=1,
64) rather than the instant one — it survives the teardown itself and dies seconds later.
Notably it died *without* the TZ/ADSP sequence that bit 64 produced, so that sequence is
**not required** for the crash. Mask list is now exhausted; every bit has been run.

## ★★ THE PON DIFF — the PMIC did NOT reset this box

Baseline (after a genuine clean shutdown) vs post-mask-2-crash. **Exactly one line moved,
out of 34:**

```
< pbs +10: 10 90 a7 10 00 b7 b7 00 00 00 03 00 00 00 00 00
> pbs +10: 10 90 a7 10 00 97 97 00 00 00 03 00 00 00 00 00
```

i.e. **PBS +0x15 and +0x16, `0xb7` → `0x97` — BIT(5) cleared in both.** Verified **stable**:
re-read three times on this boot, `0x97` every time. Latched state, not fluctuating status.

### What is now established

- **POFF_REASON1 (@0x0c) = `0x00`, unchanged.** BIT(2)=PMIC_WD is clear ⇒ **no PMIC
  watchdog reset.** POFF_REASON2 (@0x0d) = `0x01` unchanged ⇒ no UVLO, no OTST3 thermal.
  (These are the only offsets with in-tree bit definitions — `drivers/watchdog/pm8916_wdt.c`.)
- **The PON_REASON candidates (PBS +0x08=`0x02`, +0x09=`0x03`) are unchanged too.**

Both halves unchanged is the informative part: **the reset never went through the PMIC
power-off path AND never registered as a fresh power-on.** That is the signature of a
**warm / SoC-internal reset that does not power-cycle the PMIC** — consistent with the
standing "SoC is reset externally by TZ, a secure watchdog, or hardware" conclusion, and
it now **rules the PMIC out as the resetting agent**. `qcom_wdt` and TZ remain.

### ⚠️ The one moved bit is an OPEN LEAD, not a conclusion

Two adjacent identical registers both losing BIT(5) is suggestive — the pairing smells
like one-per-PON-input (KPDPWR / RESIN) — but **there is no vendor spec for gen3 PBS
offsets and I will not invent one.** Do not write this up as a reset reason yet.

**The control test that settles it, cheap and safe: clean reboot, then re-read.**

- returns to `0xb7` ⇒ the bit genuinely tracks reset type, and PBS +0x15/+0x16 is a real
  crash signature worth identifying.
- stays `0x97` ⇒ it is one-way or unrelated drift, the whole diff is a null result, and
  the only finding is the (still valuable) "PMIC did not do it".

Until that control runs, the honest summary is: **one confirmed negative (not the PMIC),
one unidentified stable bit.**

## Housekeeping

- `logs/glymur-pon-2026-07-27-postcrash-mask2.log`, `logs/glymur-pon-2026-07-27-DIFF.txt`
- Guard re-armed this boot via the systemd unit. ⚠️ It takes **~5 s** to register — the
  first `ListInhibitions` right after `systemd-run` returns `{}` and that is not a failure.
- ⚠️ `pgrep powerdevil` / `pgrep org_kde_powerdevil` both fail (name >15 chars). Use
  `pgrep -f`.

## ▶ CONTROL TEST IN PROGRESS — run this FIRST on the next boot

A **clean reboot** was issued 2026-07-27 ~06:57 purely to settle whether PBS +0x15/+0x16
tracks reset type. **The very first thing to do on the next boot:**

```bash
# 1. guard first - it does NOT survive a reboot, and takes ~5s to register
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
systemd-run --user --unit=glymur-inhibit --collect kde-inhibit --screenSaver --power sleep 86400
sleep 5; qdbus-qt6 --literal org.kde.Solid.PowerManagement.PolicyAgent \
  /org/kde/Solid/PowerManagement/PolicyAgent ListInhibitions   # expect two entries

# 2. the control read - rmmod FIRST or the capture is empty
cd ~/Projects/zenbook-a16-linux
sudo rmmod qcom_pon && sudo insmod ~/kernel-build/qcom-pon.ko.glymur-reason-dump
sudo dmesg | grep GLYMUR-PON | sed 's/^.*GLYMUR-PON: //' > logs/glymur-pon-2026-07-27-control-cleanreboot.log
echo "--- vs CLEAN-SHUTDOWN baseline (expect identical if the bit tracks reset type):"
diff logs/glymur-pon-baseline-2026-07-27-cleanshutdown.log logs/glymur-pon-2026-07-27-control-cleanreboot.log
echo "--- vs POST-CRASH (expect the 0xb7/0x97 line to differ if the bit tracks reset type):"
diff logs/glymur-pon-2026-07-27-postcrash-mask2.log logs/glymur-pon-2026-07-27-control-cleanreboot.log
```

**Reading it:**

| control reads | means |
|---|---|
| `pbs +10: … b7 b7 …` (matches baseline) | ★ the bit **tracks reset type**. PBS +0x15/+0x16 is a real crash signature — worth identifying, and it becomes the way to classify future crashes without a spec. |
| `pbs +10: … 97 97 …` (matches post-crash) | one-way / unrelated drift. The diff is a **null result**; the only finding stands as "the PMIC did not reset the box". Stop chasing this bit. |
| anything else | neither — re-read and check the module srcversion is `93A35C2AE7855A09CA9DE58`. |

Either way the PMIC-eliminated conclusion above is unaffected — it rests on POFF_REASON1/2
and PON_REASON being unchanged, not on this bit.

## ✅ CONTROL TEST RESULT (2026-07-27 07:17) — NULL. The bit is NOT a crash signature.

Clean reboot confirmed genuine (previous boot ended `systemd-shutdown[1]: Syncing
filesystems and block devices.`). Control read:

```
control vs CLEAN-SHUTDOWN baseline:  pbs +10: … b7 b7 …  ->  … 97 97 …   DIFFERS
control vs POST-CRASH:               IDENTICAL (all 34 lines)
```

**PBS +0x15/+0x16 did NOT return to `0xb7` after a clean reboot.** It matches the crash
state exactly. So the `0xb7`→`0x97` flip is **one-way drift that happened once, somewhere
between 06:06 and 06:52, and sticks across reboots** — it does not distinguish a crash
from a clean reboot and is **useless as a signature**. Drop this lead. Do not re-open it
without a cold power cycle to see whether `0xb7` is even restorable.

## ⚠️⚠️ CORRECTION — "the PMIC did not reset the box" is WEAKER than stated earlier

The claim in the section above rested on POFF_REASON1 (@0x0c) reading `0x00` after the
crash. **That inference requires that the register WOULD have moved had the PMIC done it —
and we have never observed these registers move for anything.**

Three reads now exist — **clean shutdown, post-crash, clean reboot — and the reason
registers are byte-identical across all three.** That is equally consistent with:

- **(a)** the PMIC genuinely was not involved in any of these events, **or**
- **(b)** these bytes never move at all — wrong offsets for gen3, or latched only on a
  cold/full power cycle, in which case reading `0x00` proves nothing.

**There is no positive control, so (a) and (b) cannot currently be told apart.** Treat
"PMIC eliminated" as *unproven*, not established. The dump itself is still sound (both
peripherals self-identify, the read path is validated) — the problem is purely that
nothing has ever been seen to change these registers.

### ▶ NEXT: get a positive control, then re-read

Force a **PMIC-level reset** — a long power-button hold (KPDPWR_N → PS_HOLD reset) is a
PMIC-initiated event by definition — then `rmmod`/`insmod` and diff again.

- reason registers **move** ⇒ they are live and correctly located ⇒ the crash reads become
  meaningful and "PMIC not involved" is genuinely established.
- reason registers **still identical** ⇒ we are reading the wrong offsets for gen3 (or
  they only latch on a cold cycle). The PMIC conclusion collapses and the qcom-pon route
  needs the vendor offsets before it can say anything at all.

This is the single cheapest experiment that makes the whole qcom-pon workstream either
trustworthy or discardable. Do it before drawing any further conclusion from PON data.

Log: `logs/glymur-pon-2026-07-27-control-cleanreboot.log`.

### ▶▶ PENDING RIGHT NOW (2026-07-27 07:25) — positive control, forced power-button hold

Jesse is holding the power button to force a PMIC-level power-off. **The box will power
OFF, not reboot — press power again to boot it.** GRUB default `fedora-glymur-test69`,
unchanged. On the next boot, in this order:

```bash
# 1. guard FIRST (does not survive a reboot; takes ~5s to register)
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
systemd-run --user --unit=glymur-inhibit --collect kde-inhibit --screenSaver --power sleep 86400
sleep 6; qdbus-qt6 --literal org.kde.Solid.PowerManagement.PolicyAgent \
  /org/kde/Solid/PowerManagement/PolicyAgent ListInhibitions   # expect TWO entries

# 2. the positive control - rmmod FIRST or the capture is empty
cd ~/Projects/zenbook-a16-linux
sudo rmmod qcom_pon && sudo insmod ~/kernel-build/qcom-pon.ko.glymur-reason-dump
sudo dmesg | grep GLYMUR-PON | sed 's/^.*GLYMUR-PON: //' > logs/glymur-pon-2026-07-27-poscontrol-pwrhold.log
diff logs/glymur-pon-2026-07-27-control-cleanreboot.log logs/glymur-pon-2026-07-27-poscontrol-pwrhold.log
```

**Reading it — this decides whether qcom-pon is worth anything on this machine:**

| diff shows | verdict |
|---|---|
| **any change in the reason bytes** (PBS/HLOS +0x08, +0x09, +0x0c, +0x0d) | ★ registers are **live and correctly located**. The earlier crash reads become meaningful, and "the PMIC did not reset the box" is then genuinely established. |
| **identical (all 34 lines)** | the reason registers **never move** ⇒ wrong offsets for gen3, or they latch only on something we cannot trigger. **The whole qcom-pon route says nothing without vendor offsets** — retire it rather than reading more tea leaves. |
| only PBS +0x15/+0x16 moves again | ignore — that byte pair is known one-way drift, already closed. |

⚠️ Whatever happens, this does NOT revive the PBS +0x15/+0x16 lead. That is closed.

## ⛔ POSITIVE CONTROL RESULT (2026-07-27 07:32) — NULL. RETIRE THE qcom-pon ROUTE.

The power-button hold was genuine: boot `-1` ends abruptly at **07:28:26** with no
`systemd-shutdown` lines at all, and boot `0` starts **07:30:25** — a ~2 min gap, i.e. the
box was OFF and hand-pressed back on. A long KPDPWR_N hold → PS_HOLD is a **PMIC-initiated
power-off by definition**. This is the strongest PMIC event available on this machine.

```
diff logs/glymur-pon-2026-07-27-control-cleanreboot.log \
     logs/glymur-pon-2026-07-27-poscontrol-pwrhold.log
     -> IDENTICAL, all 34 lines
```

Live module verified as the dump build (`/sys/module/qcom_pon/srcversion` =
`93A35C2AE7855A09CA9DE58`, matches the file); 34 lines, single dump, timestamp t+111 s on
this boot. `rmmod` was done first, so the capture is real and not the stock module.

**Not one byte moved anywhere in either peripheral's full 0x00–0xFF window** after a
PMIC-level power-off. Per the pre-registered decision table that is the "identical"
row: **the reason registers never move ⇒ we are not reading the gen3 reason registers.**

### What this does and does not establish

- ✅ **The read path is sound and demonstrably live.** Both peripherals self-identify
  (`hlos` subtype `0x09`, `pbs` subtype `0x08`, both rev2 `0x03`), and PBS +0x15/+0x16 was
  *observed to change once* (`0xb7`→`0x97`, between 06:06 and 06:52). So these are real
  reads of real hardware that **can** show change — the problem is purely *which* bytes.
- ⛔ **`POFF_REASON1 = 0x00` means nothing.** It reads `0x00` after a clean shutdown, after
  a crash, after a clean reboot, **and after a forced PMIC power-off**. A register that
  does not move for a PMIC-initiated power-off cannot be used to rule the PMIC out.
- ⛔ **"The PMIC did not reset the box" is formally WITHDRAWN** — not disproven, just
  unsupported. It rested entirely on the register above. The PMIC is back to *unknown*.
- ⛔ **PBS +0x08=`0x02` / +0x09=`0x03` are NOT `PON_REASON1`.** A cold power-off/power-on
  cycle must register as a fresh power-on somewhere; these did not move either.

### ▶ Verdict: the qcom-pon workstream is DONE and produced no usable signal.

Four distinct reset/power events, four byte-identical 512-byte dumps. Mainline has no
gen3 (pmk8350/pmk8850) reason-register map and this sweep did not find one empirically.
**Do not read further tea leaves from these dumps and do not re-run this module** — the
only thing that could revive it is genuine vendor offsets for gen3 PON. Anything else is
re-diffing the same static bytes.

Log: `logs/glymur-pon-2026-07-27-poscontrol-pwrhold.log`.
Patch/module kept (`patches/glymur-qcom-pon-reason-dump-DIAGNOSTIC.patch`,
`~/kernel-build/qcom-pon.ko.glymur-reason-dump`) in case offsets ever turn up.

### Where that leaves the crash hunt

Everything cheap is now spent: **every bisect mask has run**, the Oops hunt is closed
(no fault is ever emitted), ramoops came back empty on a genuine cycle, and the PMIC
reason path says nothing. Standing facts that survive:

- The trigger is `qcom_edp_phy_exit()`, and **both its halves are independently lethal** —
  so it is *timing*, not a specific clock or regulator.
- Deferring the power-down 1 s (bit 64) did **not** save it, and mask 2 died **without**
  any TZ fatal — so the TZ/ADSP sequence bit 64 produced is a **symptom, not the
  mechanism**. There may be two routes to the same reset.
- The SoC is reset externally. Remaining candidates: **`qcom_wdt`** and **TrustZone**.

Untested lead still on the board: the **`sync_state() pending due to 1c00000.pci`**
story — the clock and interconnect frameworks never leave their pre-`sync_state` state on
this box, and the crashing code is exactly what drops clock/interconnect votes. Plausible,
unproven, and it is now one of the few things left that has never been touched.

# ▶▶▶ 2026-07-27 07:45 — THE sync_state LEAD, OPENED. NO REBOOT NEEDED, AND IT HAS TEETH.

## ★ It is a runtime test, not a boot test. `state_synced` is WRITABLE.

`drivers/base/dd.c:562` `state_synced_store()` is `DEVICE_ATTR_RW`: writing **exactly `1`**
sets `dev->state_synced = true` and calls `dev_sync_state(dev)` immediately. So the whole
sync_state theory can be tested **with no kernel build and no reboot**.

⚠️ **Write trap:** `strcmp("1", buf)` — `echo 1 >` sends `"1\n"` and returns **-EINVAL**.
Use `printf 1 >`. And it is one-way: a second write returns -EINVAL, so a reboot is the
only way back.

⚠️ **The right cmdline token, if a boot test is ever wanted, is `fw_devlink.sync_state=timeout`
— NOT `fw_devlink=permissive`.** Permissive still gates sync_state (links are created
SYNC_STATE_ONLY). Confirmed why it is stuck: **`# CONFIG_FW_DEVLINK_SYNC_STATE_TIMEOUT is
not set`** in `usb-out/.config`, so `fw_devlink_sync_state` defaults to **STRICT** and
these callbacks simply never fire.

## The five unsynced devices (full `/sys/devices` sweep, not just soc@0)

`100000.clock-controller` (gcc-glymur), `16c0000.interconnect`, `1920000.interconnect`,
`2000000.interconnect`, and **`interconnect-1`** — note the last one is NOT under `soc@0`
and a `soc@0/*` glob misses it.

## ✅ Four of five synced, live, with ZERO effect

| written | result |
|---|---|
| `100000.clock-controller` (gcc) | alive, **not one new kernel message** |
| `16c0000.interconnect` | alive, silent |
| `1920000.interconnect` | alive, silent |
| `interconnect-1` | alive, silent |

- **gcc being a no-op is expected and confirms the cmdline:** `clk_ignore_unused` is set, so
  `clk_sync_state()`'s disable-unused pass has nothing to do.
- **The interconnect floors did NOT drop.** `interconnect_summary` still has **52** INT_MAX
  rows, identical before and after except `100d400.pmu` DDR numbers (that is `icc_bwmon`
  doing normal scaling — background noise, not our change).

## ★★ WHY: `icc_sync_state()` is ALL-OR-NOTHING, gated on the LAST provider

`drivers/interconnect/core.c:1199` —

```c
void icc_sync_state(struct device *dev) {
	static int count;
	count++;
	if (count < providers_count)      /* <-- nothing happens until the last one */
		return;
	...
	list_for_each_entry(p, &icc_providers, provider_list)
		list_for_each_entry(n, &p->nodes, node_list)
			if (n->init_avg || n->init_peak) {
				n->init_avg = 0; n->init_peak = 0;
				aggregate_requests(n); p->set(n, n);   /* ALL floors drop at once */
			}
}
```

So the experiment **cannot be done incrementally**. All 52 boot floors, across every
provider, drop on the single remaining write to **`2000000.interconnect`**. The four safe
writes above just advanced the counter.

## ⚠️★ AND THAT LAST WRITE IS PREDICTED TO BE LETHAL — with a named mechanism

Scanning the baseline summary for nodes whose INT_MAX is boot-floor **only** (i.e. every
real consumer vote is 0/0), across all four unsynced providers, there is **exactly one**:

```
qnm_lpass@2000000.interconnect          2147483647   2147483647
  6800000.remoteproc                 7          0            0      <- the ADSP, voting ZERO
```

**`qnm_lpass` is held up solely by the boot floor, and its only consumer is the ADSP.**
When the floor drops, `aggregate_requests()` gives it the ADSP's real vote — **zero** — and
`p->set()` pushes 0 bandwidth to the LPASS NoC path while the ADSP is live.

That predicts precisely the signature already on record from bit 64: **ADSP loses its NoC
path → `fatal notification received from TZ` → `crash detected in adsp` → SoC down a few
seconds later.**

### ▶ This makes the last write a POSITIVE CONTROL FOR THE CRASH MECHANISM ITSELF

```bash
sudo sh -c 'printf 1 > /sys/devices/platform/soc@0/2000000.interconnect/state_synced'
```

| outcome | meaning |
|---|---|
| **dies with TZ fatal / ADSP crash, display never touched** | ★★★ The crash signature is reproduced **without any display teardown at all.** That would make the mechanism general: *an interconnect/clock vote reaching zero on a path a co-processor needs → TZ resets the SoC.* The eDP teardown becomes one instance of a class, and it explains why **both halves of `qcom_edp_phy_exit()` are independently lethal** — they are both vote-drops, and the resource identity never mattered. |
| **survives** | sync_state is **closed** as a theory. Bonus: the box is then in a fully-synced state, so re-running the screen-off test costs nothing extra and is a genuinely new configuration. |

Either way it is decisive, and either way it costs at most one reboot cycle — which is what
the crash costs anyway. `/var/log/glymur-kmsg.log` (fsync logger) is **active** and is the
authoritative channel; netconsole is not required and under-reports.

Baselines saved: `logs/glymur-icc-summary-baseline-2026-07-27.log`,
`logs/glymur-icc-summary-after-safesync-2026-07-27.log`.

## ✅ RESULT (2026-07-27 07:52) — IT SURVIVED. The prediction above was WRONG.

Fired at kmsg t=1303.94 with a stamped marker. **The box did not die.** Checked at t+1 s,
t+11 s and t+41 s: alive, `remoteproc0` = **`running`**, `card1-eDP-1` connected,
`fb0 = msmdrmfb`, and **not one kernel message of any kind** produced by the operation.

The write did everything it was supposed to:

| | before | after |
|---|---|---|
| INT_MAX (boot-floor) rows | **52** | **0** |
| `qnm_lpass@2000000` | `2147483647 / 2147483647` | **`0 / 0`** |
| devices with `state_synced=0` | 5 | **0** |

So `qnm_lpass` really did collapse to zero bandwidth with the ADSP live, exactly as
predicted — **and the ADSP did not notice.** No `fatal notification received from TZ`, no
`crash detected in adsp`, no reset.

### ★ What this rules out — a real, load-bearing negative

**"An interconnect vote reaching zero on a path a co-processor needs makes TZ reset the
SoC" is FALSE**, at least for the LPASS NoC path. That was the attractive generalisation
that would have explained why both halves of `qcom_edp_phy_exit()` are independently
lethal. **It does not survive contact.** Do not re-propose it.

Corollaries worth keeping:
- **Dropping ICC bandwidth to zero is not, by itself, dangerous on this SoC.** That weakens
  every "the crash is a vote-drop" story, including the reading of bit 8 / mask 2.
- **The ADSP is not fragile to losing its NoC floor.** The ADSP crashes seen on bit 64 were
  therefore provoked by something more specific than "a resource went away" — go back to
  treating that TZ fatal as display-specific, not generic.
- **`sync_state` pending was never protecting anything.** The box runs fine fully synced.
  Retire the `sync_state()`/`1c00000.pci` line as a crash explanation.

### ▶ The free bonus: the box is now in a fully-synced state for the first time ever

Every previous screen-off test in this entire hunt ran with 52 boot floors still in place.
Running the teardown now is a genuinely new configuration and costs nothing extra.

```bash
OFFWAIT=10 ONDEBUG=0x104 /usr/local/bin/glymur-bisect.sh 0     # mask 0 = control
```

⚠️ This state does **not** survive a reboot — `state_synced` resets, and there is no
cmdline knob compiled in (`CONFIG_FW_DEVLINK_SYNC_STATE_TIMEOUT` is not set). To get it
back after any reboot, re-run the five writes (gcc first, `2000000.interconnect` last).

Log: `logs/glymur-icc-summary-after-fullsync-2026-07-27.log`.

## ⛔ AND THE TEARDOWN TEST RAN IN THAT STATE — IT STILL DIES. sync_state IS FULLY CLOSED.

`OFFWAIT=10 ONDEBUG=0x104 glymur-bisect.sh 0` (mask 0, **baseline, nothing skipped**), with
all 52 icc floors dropped and every device synced. From `/var/log/glymur-kmsg.log` — the
authoritative channel, **not** netconsole:

```
1481.016  GLYMUR-CRASH-TEST: dpms off returned rc=0
1481.710  qcom_q6v5_pas: Handover signaled, but it already happened
1481.733  qcom_q6v5_pas: fatal error received: sys_m_smsm.c:783:err fatal notification from TZ
1481.733  remoteproc0: crash detected in adsp: type fatal error
1486.047  GLYMUR-CRASH-TEST: alive t+5s after dpms off        <- survived the teardown
          (dead before t+10s)
```

**`/sys/fs/pstore/` empty again** — third independent confirmation of "no Oops, SoC reset
externally".

### What this settles

- **The fully-synced state changes nothing.** Same delayed death, same shape. sync_state is
  now closed as an *explanation* **and** as a *fix*. Do not revisit it.
- **★ BASELINE PRODUCES A TZ FATAL, at +717 ms.** This is the first clean baseline capture
  with the TZ sequence. It matters because the standing note read the TZ fatal as a bit-64
  artefact — it is not, it is what the *unmodified* teardown does.
- **The delayed-death group is now the norm, not the exception.** Baseline reaches
  `alive t+5s` and dies between t+5 and t+10, exactly like masks 32 / PHYSKIP=1 / 64 / 2.
  Earlier "instant death" readings were netconsole artefacts.
- **Mask 2 remains the odd one out** — it is the only run that died *without* a TZ fatal.
  Everything else that has been captured properly shows TZ.

⚠️ The netconsole `WARNING: net/mac80211/tx.c:3867 at ieee80211_tx_dequeue` in this capture
is the known-benign `WARN_ON_ONCE(softirq_count() == 0)` context assertion. Not the crash.

# ▶▶▶ 2026-07-27 08:15 — DOWNLOAD MODE (EDL) ROUTE. Feasibility CONFIRMED on the box side.

After qcom-pon, qcom_wdt and sync_state all came back negative, the only remaining way to
name the resetting agent is a **TrustZone-side ramdump via Qualcomm download mode (EDL)**.
Jesse's call 2026-07-27: set it up.

## ✅ The box supports it — verified, not assumed

| check | result |
|---|---|
| `/sys/module/qcom_scm/parameters/download_mode` | exists, mode **0644**, reads `off` |
| `qcom_scm` | **built-in** (no `initstate`) ⇒ `qcom_scm.download_mode=full` works on cmdline |
| `/proc/device-tree/firmware/scm/qcom,dload-mode` | **present**, `<0x2a 0x4000>` (phandle + IMEM offset) |
| scm compatible | `qcom,scm-glymur`, `qcom,scm` |
| write `full` then `off` | **succeeded, no SCM error logged** ⇒ TZ accepted the IMEM read-modify-write |
| `qcom,sdi-enabled` | **absent** |

**Why `qcom,sdi-enabled` being absent matters:** `qcom_scm.c:2849` registers a shutdown
handler that calls `qcom_scm_set_download_mode(QCOM_DLOAD_NODUMP)`. So the cookie is
**cleared on a clean shutdown/reboot** — a normal reboot will NOT land in EDL — and it must
be **re-armed every boot**. A crash skips the handler, so the cookie survives a crash.

⚠️ `set_download_mode()` returns 0 even when the SCM write fails — failures only appear via
`dev_err`. **Never trust the write's exit status; stamp kmsg and grep.** The script below
does this.

## Installed: `/usr/local/bin/glymur-dload-arm.sh [full|off]`

Arms/disarms, verifies the readback, greps kmsg for an SCM error, and warns if the
screen-blank inhibitor is not armed — because **once armed, ANY crash goes to EDL,
including an accidental idle blank.**

## ▶ PHASE 0 — the cheap discriminator, costs one crash cycle, NO host needed

"TZ accepted the cookie" ≠ "the firmware honours it". Retail WoA hardware often has dload
fused off. One crash answers it:

```bash
/usr/local/bin/glymur-dload-arm.sh full
OFFWAIT=10 /usr/local/bin/glymur-bisect.sh 0
```

- **Box reboots normally** ⇒ firmware ignores the cookie. **Route is dead, abandon it.**
- **Screen goes black and STAYS black — no POST, no reboot** ⇒ it is sitting in EDL. Green
  light for the host setup.

**Recovery either way: long power-button hold.** Nothing is written to disk.

## Phase 1 — host side (only if Phase 0 is green)

Host is one of Jesse's laptops with a USB-C port (the .22 desktop's USB-C is backside and
awkward — rejected 2026-07-27). Tool: **`bkerler/edl`** (Python, speaks Sahara + Firehose).

- In EDL the SoC enumerates as **`05c6:9008`** — check with `lsusb | grep -i 05c6`.
- ⚠️ Glymur's USB-C ports are `dr_mode=host`, so **the connection cannot be pre-tested** —
  glymur only appears as a USB *device* once in EDL. **Try BOTH ports** before concluding.
- ⚠️ Must be a **data** cable, not charge-only. Verify it with any normal USB device first.

🛑 **READ-ONLY OPERATIONS ONLY.** edl can write to UFS. Partitions p1–p11
(Qualcomm/WoA firmware) and p13–p16 (Windows) must never be touched. Nothing with
`w`/`write`/`flash`/`erase`.

## Phase 2 — expected value, stated honestly

The prize in a full DDR dump is the **TZ diagnostic buffer**, where TrustZone records reset
reasons and XPU/access-violation detail — precisely what has been invisible all along.
Caveat: proper parsing is vendor-tooling territory. Best realistic case is a reset-reason
string and a fault address; worst case is a large binary we can only grep.

# ▶▶▶ 2026-07-27 ~11:05 — CLAUDE MOVED TO THE HOST. PHASE 0 FIRED.

## ★ Two machines now. Read this before any live check.

| | |
|---|---|
| **host** — `fedora`, x86_64 Fedora 44 COSMIC, fresh install | Claude, the repo, the memory dir, `edl` |
| **glymur** — `loazen`, aarch64 | the device under test; ALL live hardware state |

**Live checks are `ssh loazen '<cmd>'` from the host.** ⚠️ Use the **name**, not an IP:
`loazen` resolves as `loazen.internal` over **IPv6** `2600:4041:502b:ea00::1c0c`, and that
is the only entry in the host's `known_hosts`. **`ssh jcasco@192.168.8.60` fails with
`Host key verification failed`** — .60 is glymur's Wi-Fi IPv4 and is still what the older
notes and the netconsole modprobe line use. There is no `~/.ssh/config` on the host.

Running `uname -r` / `/proc/cmdline` / `/sys/class/drm/` **locally on the host** returns
x86_64 Fedora values and yields a confidently wrong state report. Easiest way to waste a
session now.

**Why moved:** Claude on glymur dies with glymur, and this phase is *defined* by glymur
being crashed or in EDL (running no OS at all). Host survives to fire and read.

Migrated and verified 2026-07-27: 12 state files (memory ×9 + RESUME-HERE/HANDOFF/CLAUDE)
**md5-identical** both ends, `git HEAD ba27d3c`. `memory-archive/` deliberately NOT copied
(plaintext creds). `~/kernel-build` (12 G) stays on glymur — modules build where they run,
as do `/usr/local/bin/glymur-*.sh` and `/var/log/glymur-kmsg.log`.

⚠️ **Host is canonical** for the memory dir and this file. glymur's copies are a frozen
snapshot — do not write to them or the two forks will contradict each other.

`edl` installed on the host from git (**`pip install edlclient` does NOT exist** — not on
PyPI; and the entrypoint is `edl.py`, not `edl`). venv at `~/edl/.venv`, symlinked to
`~/.local/bin/edl`. `51-edl.rules` installed via the repo's own installer. `Capstone`/
`Keystone` report missing — **optional**, exploit/patch features only, irrelevant to
read-only dumps. ⚠️ `sudo edl` will NOT resolve; use `sudo ~/edl/.venv/bin/edl`.

## ★★ NEW, UNEXPLAINED: silent spontaneous crashes, NOT the teardown crash

Three crashes on 2026-07-27 morning with **no display teardown whatsoever** — no `msm_dp_*`,
no `dpu_*`, no TZ fatal, no ADSP crash, no Oops, in `/var/log/glymur-kmsg.log`:

| boot ended | how |
|---|---|
| 09:12:42 | crash, 0 shutdown markers |
| 10:03:05 | crash — **the blank guard was armed and verified 90 s earlier** |
| 10:16:02 | crash |

On the 10:16 boot the kernel went silent at t+30 s and the box ran ~10 more minutes with
**nothing at all** in kmsg. Both tails just stop mid-stream.

**These are NOT the screen-off crash** and must not be pooled with it. The guard being
armed through the 10:03 death also rules out an idle blank.

**Correlation — `usb usb4-port1: Cannot enable. Maybe the USB cable is bad?` every ~4 s:**

| boot | -7 | -6 | -5 | -4 | -3 | -2 | -1 | 0 |
|---|---|---|---|---|---|---|---|---|
| usb4-port1 lines | 0 | 0 | 0 | 337 | 161 | 25 | 1 | 97 |

**Zero through 07:53, then it starts — and the crashes start with it.** Both USB-C ports
have partners; `port1` sits in **device** data role at 1.5A (something is driving glymur as
a USB device — consistent with the host-to-host EDL cable, which is exactly what produces
`Cannot enable`). Jesse's call: leave the cable in, since Phase 0 is answered by *any*
crash. Unproven whether the cable is causal. See [[zenbook-a16-usbc-nic-hub]].

## ▶ PHASE 0 FIRED — read this first on return

Armed `glymur-dload-arm.sh full` at 11:04 (`download_mode = full`, readback ok, no SCM
error), guard active, kmsg logger active, pstore empty, msm srcversion
`71AEC22EF8E61818BA215DF`, netconsole loaded. Then fired
`OFFWAIT=10 /usr/local/bin/glymur-bisect.sh 0` (baseline, nothing skipped).

**The discriminator is VISUAL and does not time out — check whenever:**

- **Screen black, stays black, no POST, no vendor logo** ⇒ **IN EDL. Route is green** →
  Phase 1. Confirm on the host: `lsusb | grep -i 05c6` → expect **`05c6:9008`**. Try
  **BOTH** USB-C ports (glymur is `dr_mode=host`, the link cannot be pre-tested). Data
  cable, not charge-only.
- **Rebooted normally** ⇒ firmware ignores the cookie. **Route is dead, abandon EDL.**

Recovery either way: **long power-button hold.** Nothing is written to disk.

🛑 If it IS in EDL: **READ-ONLY ONLY.** edl can write UFS. p1–p11 (Qualcomm/WoA firmware)
and p13–p16 (Windows) must never be touched. Nothing with `w`/`write`/`flash`/`erase`.

⚠️ **Three things do not survive a reboot** — re-do all three before any further testing:
1. `systemd-run --user --unit=glymur-inhibit --collect kde-inhibit --screenSaver --power sleep 86400`
   (verify: `ListInhibitions` shows two `{"Running Script","sleep"}` — takes ~5 s to register)
2. `sudo /usr/local/bin/glymur-dload-arm.sh full` — cleared on every clean shutdown
   (no `qcom,sdi-enabled`)
3. netconsole modprobe — ⚠️ its command still hardcodes IPv4 `192.168.8.60`
