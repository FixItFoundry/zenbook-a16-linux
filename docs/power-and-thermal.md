# Power and thermal on the Zenbook A16 — how it's supposed to work, and where ours stops

*Written 2026-07-30, after suspend landed. Everything below is measured on the box, not
inferred — where something is a guess it says so.*

Two goals: **unlock the `scmi-cpufreq -110`**, and **get fan control into Linux instead of
leaving it to the EC**. This document is the map. It starts with how the pieces are supposed
to fit, because the failure only makes sense once you can see the shape of the working system.

---

## 1. How CPU frequency scaling works on a machine like this

On an x86 laptop the CPU changes its own frequency. The kernel writes an MSR, the silicon
responds, and `cpufreq` is essentially a thin shim over that. Nothing negotiates.

Arm laptops don't work that way. The application CPUs (the cores you run code on) do **not**
control their own clocks. A separate always-on microcontroller does — on Qualcomm parts that's
the **CPUCP** (CPU Control Processor). It owns the PLLs, the voltage rails and the thermal
budget, and the main CPUs *ask* it for performance levels.

So the stack looks like this:

```
  cpufreq governor  (schedutil)          "I want CPU3 faster"
        |
  cpufreq driver    (scmi-cpufreq)       translate to a performance level
        |
  SCMI protocol 0x13  (Performance)      a message format
        |
  SCMI transport      (mailbox + shmem)  how the message physically travels
        |
  CPUCP firmware                         actually moves the clock and voltage
```

**SCMI** (System Control and Management Interface) is an Arm standard for exactly this
conversation. It's not Qualcomm-specific — it's how a rich OS talks to a power controller it
doesn't own. Each capability is a numbered *protocol*:

| ID | Protocol | What it does |
|---|---|---|
| 0x10 | Base | "who are you, what do you support" |
| 0x11 | Power domain | turn blocks on and off |
| 0x12 | System power | shutdown/reboot/suspend |
| **0x13** | **Performance** | **DVFS — the one cpufreq needs** |
| 0x14 | Clock | generic clocks |
| 0x15 | Sensor | temperatures |

The **transport** is a shared-memory mailbox: the kernel writes a request into an SRAM buffer,
rings a doorbell (an interrupt to the CPUCP), the CPUCP writes a reply into a second buffer and
rings back. Two channels, `tx` and `rx`. That is exactly what our device tree describes:

```
/proc/device-tree/firmware/scmi:
    compatible = "arm,scmi"
    mbox-names = "tx", "rx"
    mboxes     = <&cpucp_mbox 0>, <&cpucp_mbox 1>
    shmem      = <&tx_buffer>, <&rx_buffer>
    protocol@13 { #power-domain-cells = <1>; }     <- the perf domain provider
```

and the CPU nodes reference `protocol@13` through `power-domains`, which is how a core says
"my DVFS lives over there". **This wiring is correct and matches how X1 Elite does it.**

---

## 2. The failure, precisely

```
arm-scmi arm-scmi.0.auto: Using scmi_mailbox_transport
arm-scmi arm-scmi.0.auto: SCMI Protocol v2.0 'Qualcomm:PDP0' Firmware version 0x0
arm-scmi arm-scmi.0.auto: timed out in resp(caller: do_xfer+0x164/0x8b0)
arm-scmi arm-scmi.0.auto: Failed to query supported version for protocol 0x13.
arm-scmi arm-scmi.0.auto: Trying version 0x40000. Backward compatibility is NOT assured.
arm-scmi arm-scmi.0.auto: timed out in resp(caller: do_xfer+0x164/0x8b0)
scmi-cpufreq scmi_dev.3: probe with driver scmi-cpufreq failed with error -110
```

`-110` is `-ETIMEDOUT`. Read that sequence carefully, because it says more than "it didn't
work":

- **The transport is alive.** The Base protocol (0x10) completed — we got a vendor string,
  `Qualcomm:PDP0`. You cannot read that without a full round trip.
- **The doorbell fires.** `/proc/interrupts` shows `apss_cpucp_mbox` (IRQ 156) at **7
  interrupts**. Replies really do come back.
- **Only 0x13 is silent.** The kernel asks the Performance protocol for its version, twice
  (once normally, once with a forced version), and gets nothing both times.

So this is *not* a broken mailbox, a wrong SRAM address, or a missing driver. Something answers
on 0x10 and ignores 0x13.

Two other details worth holding onto:

- **`Firmware version 0x0`.** On a healthy CPUCP you'd expect a real version. Zero suggests
  firmware that is present enough to answer the Base protocol but not fully brought up.
- **There is no `arm,max-rx-timeout-ms` in our node**, so the timeout is the 30 ms default.
  That's the cheapest possible thing to rule out, and it should be ruled out first — not
  because it's likely (the other protocols answer well within 30 ms) but because it costs one
  DT property.

### Ranked hypotheses

| # | Hypothesis | How to test | Cost |
|---|---|---|---|
| 1 | 30 ms timeout too short for the first perf query | add `arm,max-rx-timeout-ms = <100>` to the scmi node | one DTB, one boot |
| 2 | CPUCP firmware doesn't implement 0x13 on this SKU/boot path | get the Base protocol to *list* its supported protocols and see whether 0x13 is in it (`CONFIG_ARM_SCMI_RAW_MODE_SUPPORT` is on — SCMI RAW is already initialised, so we can send handcrafted messages from userspace) | no reboot |
| 3 | CPUCP needs firmware loaded/started that our boot path skips | compare against the X1E boot flow; check whether anything loads a CPUCP image | reading |
| 4 | We should not be using SCMI at all — the Qualcomm-native path | see below | DT work |

### Hypothesis 4 deserves its own note

`CONFIG_ARM_QCOM_CPUFREQ_HW=m` is built. That's **EPSS/OSM** — Qualcomm's own hardware DVFS
block, driven directly by the kernel with no firmware conversation at all. Many Qualcomm SoCs
use it instead of SCMI, via a `cpufreq@...` node and `qcom,freq-domain` on the CPUs.

Our DT has **no such node**, and our CPUs use `power-domains` (the SCMI way). X1 Elite also
uses the SCMI way, so following it is defensible. But if the CPUCP firmware genuinely won't
speak 0x13, EPSS is the fallback — and the register block may well exist in silicon even
though nothing describes it. That's a DT archaeology job, not a quick test.

★ **SCMI RAW was run. Both hypotheses 1 and 2 are now DEAD.** Results below.

### ✅ Measured 2026-07-30 via SCMI RAW — and it narrows things sharply

SCMI RAW mode is already enabled on this kernel (`SCMI RAW Mode initialized for instance 0`),
which lets us hand-craft messages from userspace through
`/sys/kernel/debug/scmi/0/raw/message` — no reboot, no rebuild.

**Test 1 — ask the Base protocol what the firmware supports:**

```
BASE_DISCOVER_LIST_PROTOCOLS (protocol=0x10, msg=0x6)
  -> status=0  num_protocols=2  protocols: [0x13, 0x80]
```

⇒ ⛔ **Hypothesis 2 is dead. The firmware explicitly advertises 0x13.** It is not a SKU without
DVFS, and the CPUCP is not too dumb to do performance management — it says it can.
(`0x80` is a Qualcomm vendor-specific protocol; SCMI reserves 0x80+ for those. Worth a look
later — it may be where Qualcomm actually put the interesting controls.)

**Test 2 — query protocol 0x13 directly, with no timeout at all:**

```
PROTOCOL_VERSION (protocol=0x13, msg=0x0)
  -> blocked for 60+ seconds, no reply, read never returned
```

⇒ ⛔ **Hypothesis 1 is dead too.** The 30 ms default timeout is irrelevant — we waited more
than a thousand times that and nothing came back.

### So the failure is now a genuine contradiction

The same firmware, over the same channel, in the same session:

- **answers** Base (0x10) correctly, repeatedly
- **claims** in that answer that 0x13 is supported
- **never answers** a single message addressed to 0x13

That is not a timeout, not a missing feature, and not a broken transport. Something about
messages addressed to protocol 0x13 is being dropped.

---

## ★★★ 2. bis — ROOT CAUSE, measured 2026-07-30. The contradiction is resolved.

**The CPUCP firmware processes protocol 0x13 messages and writes correct replies into the
SCMI shared memory — but it never rings the mailbox doorbell for them.** The kernel waits
on an interrupt that never arrives, times out, and gives up.

SCMI RAW exposes both a normal interrupt-driven file (`raw/message`) and a **polling** file
(`raw/message_poll`) that reads the shmem channel status directly and ignores the doorbell.
Running the *same message* through both settles it:

| message | polling mode | interrupt mode | doorbell IRQ |
|---|---|---|---|
| `0x10/0x1` BASE_PROTOCOL_ATTRIBUTES | ✅ status 0 | ✅ status 0 | **+1** |
| `0x13/0x0` PERF PROTOCOL_VERSION | ✅ replies, status −4 | ⛔ hangs | **+0** |
| `0x13/0x1` PERF PROTOCOL_ATTRIBUTES | ✅ **status 0** | ⛔ hangs | **+0** |

The doorbell accounting is unambiguous. Eight messages in interrupt mode took IRQ 156 from
**9 → 16** — exactly one interrupt per reply, and **none** for the 0x13 message. A later
control took it 16 → 17 while a hanging `0x13/0x1` added nothing.

### The perf protocol is alive and healthy

`0x13/0x1 PROTOCOL_ATTRIBUTES` returns **status 0, attributes `0x00020003`**:

- **3 performance domains**
- power values reported in mW
- no statistics shared-memory region

So the CPUCP is fully capable of DVFS and willing to describe it. This was never a firmware
capability problem — it is a **signalling bug, and nothing else**.

`0x13/0x0 PROTOCOL_VERSION` returns **−4 (NOT_FOUND)**: the firmware simply does not
implement message 0, which is unfortunately the *first* thing the kernel asks any protocol.
(Its trailing payload bytes are stale leftovers from the previous transaction — the firmware
writes the status without shrinking `length`. Only the status field means anything.)

### ★ The fix to try first: one DT property

`arm,no-completion-irq` is a **documented upstream boolean** on the `arm,scmi` node —
`Documentation/devicetree/bindings/firmware/arm,scmi.yaml:149`, consumed at
`drivers/firmware/arm_scmi/driver.c:3154`. It sets `cinfo->no_completion_irq`, which makes
`is_polling_enabled()` true, which makes the core **poll every transfer** instead of waiting
for a doorbell.

No kernel patch. No C change. One line in the `scmi` node. The mailbox transport already
advertises `.poll_done = mailbox_poll_done` (`transports/mailbox.c:366`), and we have proven
empirically that polling works on this box for both 0x10 and 0x13.

If the property alone isn't enough, the C-side equivalent is `.force_polling = true` in
`scmi_mailbox_desc`, which currently isn't set.

### What this rules out

- ⛔ **The rx-mailbox-channel theory is dead.** Qualcomm's `glymur.dtsi` uses
  `<&pdp0_mbox 0>, <&pdp0_mbox 1>` where X1E's `hamoa.dtsi` uses channels 0 and 2, and the
  shmem pair is reversed too — but none of that matters, because the firmware doesn't ring
  *any* channel for 0x13.
- ⛔ **"The CPUCP needs a Windows-bootloader init step" is dead** as an explanation. The
  protocol answers correctly the moment you stop waiting for an interrupt.
- ⛔ **Ghidra / the PDP0 firmware image is not needed.** No reason to open the NHLOS
  partitions for this.
- ⛔ **The memory mapping is correct** and is not a fix path: `pdp_ns_shared_mem` at
  `0x81e00000` (len `0x200000`, `no-map`) properly carves out the `0x81e08600` shmem, and
  `/proc/iomem` shows it claimed with no `System RAM` overlap.

### Other facts from the same sweep

- Base `PROTOCOL_ATTRIBUTES` = `0x102` ⇒ **1 agent, 2 protocols**.
- **Vendor protocol 0x80 is live** — `PROTOCOL_VERSION` = 1.0, status 0. Its
  `PROTOCOL_ATTRIBUTES`/`MESSAGE_ATTRIBUTES` return −3 DENIED. Unexplored; it may be where
  Qualcomm put the interesting controls.
- The firmware **returns errors rather than ignoring**: `0x10/0x7 DISCOVER_AGENT` and
  `0x10/0x2 MESSAGE_ATTRIBUTES` both come back −3 DENIED *and* ring the doorbell. Silence on
  0x13 was never "unimplemented" — it was always a missing signal.
- The failure reproduces identically on `7.2.0-rc3-konrad1`; it is not version-specific.

### Tooling

On loazen, in `~` so it survives a reboot: `glymur-scmi-probe.py` sends one raw message
(`SCMI_RAW_FILE` picks IRQ vs polling; header = `msg_id | type<<8 | protocol<<10 |
token<<18`), driven by `glymur-scmi-run.sh`, `glymur-scmi-poll.sh`, `glymur-scmi-poll2.sh`,
`glymur-scmi-irq13.sh`, logging to `~/scmi-*.log`.

⚠️ Always launch with `sudo setsid nohup … &`. ⚠️ `~` under `sudo` is `/root` — use absolute
paths inside the scripts. ⚠️ `pkill -f "glymur-scmi-probe.py 0x13"` **kills your own ssh
session**, because the remote command line self-matches; kill by PID.

---

### The original candidate list, kept for the record — all three now closed

1. ~~0x13 expects a different channel~~ — dead, see above.
2. ~~The CPUCP needs an initialisation step~~ — dead, see above.
3. ~~The vendor protocol 0x80 gates it~~ — 0x80 answers fine and gates nothing.

⚠️ **Trap for whoever runs this next:** a read on `/sys/kernel/debug/scmi/0/raw/message` with no
reply pending **blocks uninterruptibly** — `timeout` cannot kill it and it will hold your ssh
session until you kill the process from another one. Use `message_poll` instead, or run it
detached.

---

## 3. Why fixing cpufreq also fixes thermal

This is the part worth internalising, because it explains why the machine currently has
**102 thermal sensors and almost no way to act on them**.

Measured right now:

| | |
|---|---|
| thermal zones | **102** (101 of them have trip points) |
| cooling devices | **2** |
| zones with a cooling device attached | **14 / 102** |
| governor | `step_wise` |

The two cooling devices are `devfreq-3d00000.gpu` (the GPU) and `ath12k_thermal` (the Wi-Fi
radio). **There is no CPU cooling device at all.**

A "cooling device" is the thermal framework's word for an actuator — something it can turn down
when a zone gets hot. On an Arm SoC the primary CPU actuator is `cpufreq-cooling`, and it is
*created by the cpufreq driver when a policy comes up*. No cpufreq policy, no cooling device.

So the chain is:

```
SCMI 0x13 times out
   -> scmi-cpufreq fails -110
      -> no cpufreq policies              (measured: 0 policy directories)
         -> no cpufreq-cooling device     (measured: only GPU + Wi-Fi)
            -> 101 zones with trips and nothing to throttle
               -> the only real defence left is the fan, which Linux cannot see
```

Every symptom on the list — cores pinned at boot clock, thermal shutdowns under load, poor
battery life, the fan doing whatever it likes — hangs off that one timeout.

### ⚠️ And the mitigation we thought we had was a no-op — now REMOVED

> **★ RESOLVED 2026-07-31: the guard has been removed from the machine.**
>
> Sequence: the `arm,no-completion-irq` fix landed, cpufreq policies appeared, and
> `scaling_max_freq` existed for the first time — so the guard became genuinely capable of
> throttling. It was retired at that point rather than kept, because its trigger is the max
> over **every** sensor on the SoC (including ones unrelated to CPU load), it would now
> compete with the real governor (`schedutil` via power-profiles-daemon), and the kernel's
> own `cpufreq-cooling` devices now exist so the correct mechanism is `cooling-maps` in the
> DT rather than a shell loop. Files and rationale kept in `tweaks/retired/`.
>
> **★ And the "validated under load" claim it carried is now RETRACTED.** `LOCAL-TWEAKS.md`
> §6 used to say it held an 18-core load at ~70 °C where the machine had previously crashed
> every 10–20 minutes. Measured against a **persistent journal covering 62 retained boots**:
> 33,048 lines from the unit, every one of them the `No such file or directory` error below,
> and **zero level-change events in its entire recorded history.** It never throttled once,
> so it cannot have been what stopped the shutdowns. What did is **unknown and was never
> isolated** — the EC fan and the many DT/kernel changes over that period are both live
> candidates.
>
> **What protects the CPU right now:** 101 critical trip points and the EC/BIOS-autonomous
> fan. There is no Linux-side thermal *actuation* — the `cpufreq-cpu0/6/12` cooling devices
> exist but no zone binds them. That is the next task.

The description below is retained as the record of *why it was harmless until 2026-07-31*.

`glymur-thermal-guard.service` was `active` and polling every 2 seconds. It wrote to:

```
/sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq
```

That path **did not exist**, because there were no cpufreq policies. The journal shows the
proof, twice a second, across every retained boot:

```
glymur-thermal-guard.sh[2047]: line 14: /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq:
                               No such file or directory
```

It never throttled anything. It could not. It was also filling the journal at 0.5 Hz —
33,048 lines across 62 boots.

In practice this has not bitten us — the fans do spin up, autonomously, from the EC/BIOS
side (Jesse, 2026-07-30). That is the machine defending itself without Linux, not the guard
working. The goal remains to bring the fan under kernel control; the guard is dead weight
either way.

This is the **third** time on this project that one of our own workarounds outlived its
evidence and then quietly confounded the picture — after `modprobe.blacklist=gpucc_glymur`
hiding the GPU, and `efi=noruntime` poisoning crash capture. The lesson keeps being the same
one: *audit your own workarounds as ruthlessly as the hardware.* Worth deciding whether to fix
the guard to fail loudly, or delete it, rather than leaving it running and mute.

---

## 4. The fan

Goal was "fan control, not BIOS level". Current state, measured:

- **No fan interface of any kind.** No `fan*_input`, no `pwm*` anywhere in sysfs.
- **No ACPI.** `/sys/firmware/acpi` is empty — we boot from a device tree, so the ACPI embedded
  controller (`PNP0C09`) that an x86 laptop would use simply isn't in play.
- **No EC or fan node in the device tree.**
- `hid_asus` is the only ASUS driver loaded, and it handles the keyboard, not the EC.
- The 102 thermal zones are *sensors only* — reading them does not imply anyone acts on them.

So the fan is entirely autonomous inside the embedded controller, exactly as the hardware notes
said. The EC has its own view of temperature and its own curve, and Linux is not part of that
conversation.

★ **This section is superseded by `docs/fan-ec-interface.md` (2026-07-30).** The EC has been
found and it answers Linux: I2C bus `/dev/i2c-9` (`a84000` / `QUP_1_SE_1`), **EC at 0x76,
subdevice at 0x5b**, both ACKing on the live box. The fan-curve command set is decoded. The
one remaining gap is RPM readback, which needs an SSDT dump we never took. Read that doc,
not the prose below, before doing fan work.

**Getting into it means finding the EC's interface**, and there is a proven route on this
project: the **Windows-on-Arm ACPI dump**. The lid switch came from there — TLMM GPIO 92,
recovered from the WoA DSDT and wired into our DT in test65. The same dump will describe the EC:
which bus it hangs off (I2C on a GENI SE is most likely on this platform), its address, and the
operation regions Windows uses to read fan RPM and write a curve.

That is a reading-and-decompiling job before it is a coding job, and the sequence is:

1. Find the EC device in the WoA DSDT — look for `EmbeddedControl` operation regions, or an
   I2C serial bus resource on an ASUS-specific device.
2. Map its bus to our DT (which GENI I2C controller, what address).
3. Add an i2c node and read a byte. Read-only first — a fan RPM value that tracks reality is
   the proof you have the right device.
4. Only then think about writing a curve.

⚠️ Note the risk asymmetry: reading EC registers is generally safe, writing them is not. The EC
also owns charging and power sequencing on these machines. Read first, and read a lot.

---

## 5. Suggested order of work

1. ~~SCMI RAW probe of the Base protocol~~ — **done 2026-07-30, and it found the root cause.**
   See §2 bis.
2. ~~`arm,max-rx-timeout-ms`~~ — **dead.** No reply ever arrives on the interrupt path, at any
   timeout.
3. ~~★ **Add `arm,no-completion-irq` to the `scmi` node and boot it.**~~ **DONE — PASSED
   2026-07-31.** Three performance domains, `scaling_driver = scmi`, doorbell IRQ flat at 0,
   `cpufreq-cooling` created by itself. Full before/after table and the two benign log-noise
   lines are in `docs/DTB_CHANGELOG.md`. **This section's root-cause analysis is confirmed
   correct by experiment.** The remaining cpufreq-adjacent work is now (a) pick a governor —
   all three come up `performance`, i.e. pinned at max — and (b) write `cooling-maps`, since
   no thermal zone binds the new `cpufreq-cpuN` cooling devices yet.
   - **⚠️ `glymur-thermal-guard.service` is no longer a no-op.** See §3 below; it now
     actually clamps `scaling_max_freq`.
   - Build/staging record, kept because it is how to rebuild it: the property is in
     `~/kernel-build/konrad/linux-7.2/arch/arm64/boot/dts/qcom/glymur.dtsi` (backup:
     `glymur.dtsi.bak-pre-scmipoll`; the isolated hunk is
     `patches/glymur-scmi-no-completion-irq-EXPERIMENT.patch`). DTB installed as
     `/boot/glymur/glymur-a16-merged-gpu-scmipoll.dtb`; **a `dtc` diff against the
     currently-booted `glymur-a16-merged-gpu.dtb` is exactly one added line**, so this
     really is single-variable. GRUB entry **`SCMI poll test (cpufreq)`** appended to
     `/boot/grub/grub.cfg` (backup `.bak-pre-scmipoll`) — a byte-for-byte clone of the
     default `fedora-linux-arm-suspend` entry with only the `devicetree` line changed.
     `set default` is **unchanged**, so the known-good entry still wins on a timeout and
     the test entry must be selected by hand.
   - Verdict script: **`~/glymur-scmi-poll-check.sh`** on loazen. It first confirms
     `arm,no-completion-irq` is actually in `/proc/device-tree` (i.e. you booted the right
     entry — `/proc/cmdline` cannot tell you, the entries differ only in the DTB), then
     reports cpufreq policies, per-policy frequencies, scmi/cpufreq dmesg, the doorbell IRQ
     count, and the cooling-device list.
   - Pre-test baseline measured the same day: **0 entries** under
     `/sys/devices/system/cpu/cpufreq/`, **2 cooling devices** (`ath12k_thermal`,
     `devfreq-3d00000.gpu`).
   - If the property alone doesn't take, set `.force_polling = true` in `scmi_mailbox_desc`
     (`drivers/firmware/arm_scmi/transports/mailbox.c`) and rebuild.
   - EPSS/OSM archaeology is no longer needed unless both of those fail.
4. ★ **NEXT: write the `cooling-maps`.** Confirmed 2026-07-31 that `cpufreq-cooling` did
   appear by itself — `cpufreq-cpu0` (20 states), `cpufreq-cpu6` and `cpufreq-cpu12` (21
   each). But **no thermal zone binds them**, so there is still no Linux-side actuation.
   The job is now exactly what this line predicted: `cooling-maps` in the DT wiring those
   cooling devices to *passive* trips, so the zones with trip points can reach them.
   Check: `for f in /sys/class/thermal/thermal_zone*/cdev*_type; do cat $f; done | grep -c cpufreq`
   currently returns `0`.
5. **Fan** is independent of all of the above and can proceed in parallel — it's a WoA ACPI
   mining task first.
6. ~~**Delete or fix `glymur-thermal-guard.service`**~~ — **DONE 2026-07-31, deleted.**
   Stopped, disabled, and both files removed from the machine; kept with the full rationale
   in `tweaks/retired/`. Its "validated under load" claim was retracted at the same time —
   see §3. Until the `cooling-maps` land, the CPU is protected only by the 101 critical
   trips and the EC/BIOS-autonomous fan.

---

## 6. What's running while you're out

`glymur-thermal-soak.service` (system scope, survives disconnect) samples every 30 s to
`~/thermal-soak-<timestamp>.log`:

```
# time     uptime_s  energy_now   cpu_avgC gpu_avgC hottest              gpu_MHz  cpufreq
18:59:14  2608  68369000  41  40  cpu-2-0-1-thermal=43  310  0
```

It's collecting three things:

- **Idle thermal baseline with the cores pinned at boot clock.** With no DVFS the CPUs never
  drop below their boot frequency, so idle temperature and idle drain are both worse than they
  should be. This quantifies "worse".
- **Idle battery drain**, to compare against once cpufreq works.
- ★ **Suspend drain, which has never been measured.** hypridle now suspends after 30 minutes
  idle, so if the machine is left alone it will sleep. The jump in wall-clock next to the drop
  in `energy_now` gives milliwatts in suspend — the number that tells us how much the
  `glymur_pci_skip=5` workaround is actually costing us, since PCI devices stay powered.

Stop it with `sudo systemctl stop glymur-thermal-soak`.

---

## Appendix — the commands used here

```sh
# the failure
dmesg | grep -iE 'scmi|cpufreq'
grep apss_cpucp_mbox /proc/interrupts          # does the doorbell fire?

# the DT wiring
ls /proc/device-tree/firmware/scmi/            # protocol@13, shmem, mboxes
tr '\0' ' ' < /proc/device-tree/firmware/scmi/mbox-names

# what cpufreq exists
ls -d /sys/devices/system/cpu/cpu*/cpufreq | wc -l

# thermal reality
ls /sys/class/thermal/ | grep -c thermal_zone
for c in /sys/class/thermal/cooling_device*; do cat $c/type; done

# the guard that does nothing
journalctl -u glymur-thermal-guard -n 5
```
