# Where crash evidence lives on this machine

**Written 2026-07-30.** Read this before concluding that a crash "left no evidence" — that
claim has been wrong in this project three separate times, for three different reasons.

Box: `loazen` · ASUS Zenbook A16 UX3607OA · `BIOS UX3607OA.309 04/23/2026`

---

## TL;DR — the three places to look

```sh
# 1. Live, but usually EMPTY, because systemd harvests and deletes from it
ls -la /sys/fs/pstore

# 2. THE ARCHIVE. This is where records actually end up. Root-only.
sudo find /var/lib/systemd/pstore -type f | sort

# 3. Was anything harvested this boot?
sudo journalctl -b 0 -u systemd-pstore.service
```

**`/sys/fs/pstore` being empty means nothing on its own.** `systemd-pstore.service` copies
every record into `/var/lib/systemd/pstore/` and then *unlinks it from `/sys/fs/pstore`*
(`Unlink=yes` is the default and is not overridden here). So the live directory is empty by
design after the first boot following a crash.

⚠️ It also runs with `ConditionDirectoryNotEmpty=/sys/fs/pstore`, so when there is nothing to
harvest it logs `skipped, unmet condition check` — which looks like a failure and is not.

---

## Archive layout

```
/var/lib/systemd/pstore/<unix-time>/<seq>/dmesg-<backend>-<id>
                        ^^^^^^^^^^^
                        time of ARCHIVAL, not time of crash
```

Two things that make this confusing:

1. **The directory name is when systemd harvested the record, not when the crash happened.**
   Convert with `date -d @<unix-time>`. The crash time must come from the `[    x.xxxxxx]`
   monotonic timestamps *inside* the record.
2. **A single crash is split across many files, and often across several directories**,
   because harvesting takes more than one second. Group by the `Oops#N PartM` header on the
   first line of each file — not by directory.

**Part numbering is backwards from what you would expect.** `Part1` holds the crash itself
(the `Call trace:`); higher part numbers hold progressively *earlier* dmesg context. To read a
dump, start at Part1, then walk upward for the lead-up.

```sh
# read one dump in the right order
sudo find /var/lib/systemd/pstore -type f | while read f; do
  printf '%s\t%s\n' "$(sudo head -1 "$f")" "$f"
done | sort -t'#' -k2 -V
```

---

## What is currently in the archive (2026-07-30)

30 files, but only **two distinct dumps** — do not read "30 files" as "30 crashes":

| Archived | Kernel | Parts | What it is |
|---|---|---|---|
| 2026-07-20 19:21 | `7.1.0-glymur-clean2` | 1–13 (+1 empty) | driver-probe oopses from bring-up (`really_probe`, `platform_probe`, `load_module`) |
| 2026-07-24 21:58 | `7.1.0-glymur-edp1` | 1–16 | includes an oops in `summary_show` ← `seq_read` ← `full_proxy_read` — a **debugfs summary read**, i.e. self-inflicted by our own `regulator_summary` debugging. `x0 = 0`, `x20 = fffffffffffffbe0` (an error pointer), so the read dereferenced an error value |

**Neither is the suspend crash.** `grep -rlE 'PM: suspend|s2idle|dpm_'` across the whole
archive returns **zero files**. The 2026-07-24 date is a coincidence of harvesting, not
evidence of the suspend fault.

The `summary_show` oops looks like a genuine upstream kernel bug (a debugfs read that
dereferences an error pointer) and is worth reporting separately. It is *not* a glymur bug.

---

## The two capture backends, and why the choice matters here

| | `efi_pstore` | `ramoops` |
|---|---|---|
| Stores in | UEFI variables (**non-volatile flash**) | a reserved DRAM region |
| Survives warm reset | yes | **not demonstrated** — see status below |
| **Survives power cycle** | **yes** | **NO — DRAM contents are lost** |
| Worked on 7.1 | **yes** — produced both archived dumps | n/a (no region existed) |
| Works on 7.2-rc3 | **NO** — loads but cannot register, efivars unavailable | registers, but has captured nothing |
| Status here | un-blacklisted 2026-07-30; loads and quietly declines | `ramoops@ffc00000`, 2 MB, added 2026-07-30 |

**Why that table matters more than it looks:** a kernel panic does **not** reboot this
machine. `panic=10` is set and honoured (`kernel.panic=10`), yet `emergency_restart()` hangs
— verified by `echo c > /proc/sysrq-trigger`, which left the box unreachable until a manual
power cycle. So *every real crash here ends in a power cycle*, and a power cycle destroys
DRAM.

That makes `efi_pstore` — which writes to flash — **the backend better suited to this
machine**, and it is the one that produced both dumps we actually have. Unfortunately it
cannot register on 7.2-rc3 (tested 2026-07-30, see below), so on the current kernel neither
path works.

---

## The ramoops region we added

```
ramoops@ffc00000 {
	compatible = "ramoops";
	reg = <0x0 0xffc00000 0x0 0x200000>;   /* 2 MB, directly below smem@ffe00000 */
	record-size = <0x8000>;
	ecc-size = <16>;
	max-reason = <4>;                      /* KMSG_DUMP_SHUTDOWN, see below */
};
```

Placed inside the `fed80000-ffdfffff` System RAM range — memory the firmware declares
*usable*, not one of its own carve-outs — and checked programmatically against all 21 fixed
reservations for overlap (none; it abuts `smem` exactly). Mapped, no `no-map`, no `mem-type`,
following the in-tree majority (50 of 60 arm64 ramoops nodes are mapped, 57 of 60 omit
`mem-type`).

Confirmed live:

```
OF: reserved mem: 0x00000000ffc00000..0x00000000ffdfffff (2048 KiB) map non-reusable ramoops@ffc00000
pstore: Registered ramoops as persistent store backend
ramoops: using 0x200000@0xffc00000, ecc: 16
```

`max-reason = <4>` is `KMSG_DUMP_SHUTDOWN`, so a **clean reboot** also writes a record —
added specifically so DRAM persistence can be tested without crashing. ⚠️ This must be a **DT
property**; the `max_reason` *module parameter* is ignored for a DT-created device
(`ramoops_parse_dt()` overwrites it and `ram.c` then assigns
`ramoops_max_reason = pdata->max_reason`). Setting it in `/etc/modprobe.d/` had no effect —
observed `max_reason` staying at `2`.

**Status: NOT capturing anything (2026-07-30).** Tested properly: the previous boot had
ramoops registered at `0xffc00000` with `max_reason` confirmed at `4`, `pstore.backend=ramoops`,
and shut down **cleanly** (2 shutdown markers in `journalctl -b -1`). The following boot found
`/sys/fs/pstore` empty and the archive still at exactly 30 files. So a clean warm reboot with
the shutdown dump enabled produced **no surviving record**.

Two candidate causes remain and this test cannot separate them:

- the DRAM region at `0xffc00000` does not survive a warm reset, or
- `kmsg_dump(KMSG_DUMP_SHUTDOWN)` is not reaching the pstore dumper

Practically it does not matter yet: **ramoops as configured is not a working evidence path.**
The way to settle it is `CONFIG_PSTORE_CONSOLE=y`, which captures the console *continuously*
rather than only at a dump event — so any reboot at all leaves content, which tests persistence
directly, and it is also the only thing that can capture a **silent hang** (the likely shape of
the suspend fault, given a panic does not reboot this machine). One rebuild answers both.

---

## Config gaps that limit what is capturable

```
CONFIG_PSTORE=y
CONFIG_PSTORE_RAM=m
CONFIG_PSTORE_COMPRESS=y
# CONFIG_PSTORE_CONSOLE is not set     <-- console-size in DT is silently IGNORED
# CONFIG_PSTORE_PMSG is not set
# CONFIG_PSTORE_FTRACE is not set
```

Only oops/panic **records** are captured. Without `CONFIG_PSTORE_CONSOLE` a *silent* reset
with no oops leaves nothing at all — which is easy to misread as "the region does not
persist". Enabling it needs a kernel rebuild.

---

## Gotchas that have each cost real time

- **`kernel.dmesg_restrict=1`** — plain `dmesg` returns **zero lines** as non-root, so any
  `dmesg | grep -c ...` check silently returns 0 and reads as "no problems". Always
  `sudo dmesg`. This produced a false PASS in a check script here.
- **sysrq `c` needs `SYSRQ_ENABLE_DUMP` (`0x0008`)** — confirmed from
  `sysrq_crash_op.enable_mask` in `drivers/tty/sysrq.c`. This box boots `kernel.sysrq=16`
  (sync only), so `echo c > /proc/sysrq-trigger` is **silently ignored**. Set
  `sysctl -w kernel.sysrq=24` first. It does not persist across reboot, by design.
- **`/proc/device-tree` is a symlink**, so `find /proc/device-tree -name ...` does not
  descend. Use `/sys/firmware/devicetree/base`.
- **A panic does not reboot this machine**, so do not wait indefinitely; and expect the power
  cycle to destroy any ramoops evidence.

---

## Corrected history

Three separate explanations for "no crash evidence" have appeared in this repo. The first two
were wrong:

1. ~~`efi=noruntime` is mandatory and disables EFI runtime services, so pstore is empty.~~
   Wrong on both halves — the flag was retired 2026-07-30, and efivars were unavailable
   independently of it.
2. ~~EFI runtime services never come up, so efi-pstore never existed.~~ Also wrong. Runtime
   services *do* come up (`Remapping and enabling EFI services.` at `0.003015`), and
   `efi_pstore` demonstrably **did** capture two dumps on this hardware.
3. **`pstore.backend=ramoops` was on the cmdline for months with no ramoops region declared**,
   so it did nothing — and `efi_pstore`, the backend that actually worked, was blacklisted.
   That is the real reason recent crashes produced nothing.

⚠️ **Open contradiction, unresolved.** On 7.2-rc3 tonight, `GetVariable` returned
`EFI_UNSUPPORTED` (`0x8000000000000003`, logged as `integrity: Couldn't get size:`) and
`fsopen("efivarfs")` failed `EOPNOTSUPP`. Yet the two archived dumps were written by
`efi_pstore` under 7.1 kernels **whose GRUB entries carried `efi=noruntime`** and did *not*
blacklist `efi_pstore`. Both cannot be simply true. Candidate explanations, none confirmed:

- the museum GRUB config is a 2026-07-29 snapshot and may not reflect what was actually
  booted on 07-20 / 07-24
- a behaviour change in EFI runtime/variable handling between 7.1 and 7.2-rc3
- a `CONFIG_EFI_*` difference between our 7.1 build and the 7.2 build

### Test run 2026-07-30: efi_pstore cannot register on 7.2-rc3

Dropped both `modprobe.blacklist=efi_pstore` and `pstore.backend=ramoops` from the daily
driver (the latter matters: `pstore_register()` refuses any backend whose name does not match
`pstore.backend=`, so leaving it set would have voided the test). Result:

- `efi_pstore` module **loaded**
- it **never registered** — `ramoops` took the backend slot, and there is no
  `backend 'ramoops' already in use: ignoring 'efi_pstore'` line, so efi_pstore bailed out
  before attempting registration
- `GetVariable` still returns `EFI_UNSUPPORTED`; `fsopen("efivarfs")` still fails `EOPNOTSUPP`

**So on 7.2-rc3 as we build it, EFI variable services genuinely are unavailable**, and
`qcom,uefi-rtc-info` cannot bind. That part of the RTC report stands as an observation.

**The contradiction with 7.1 is still unexplained.** efi_pstore demonstrably wrote records
under 7.1 on this same firmware. So the correct framing remains "unavailable on our 7.2-rc3
build", *not* "the firmware does not support it" — the cause has not been isolated, and it
could still be a config or behaviour difference on our side. Do not state it as a firmware
property.

Net position: **there is currently no working crash-capture path on 7.2-rc3.** efi_pstore
cannot register, and ramoops registers but has produced nothing.
