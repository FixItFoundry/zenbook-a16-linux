# G14 — RAM-dump capture runbook (for the LPASS hard-hang + any future un-loggable crash)

Goal: capture the crash that leaves NO logs (LPASS macro probe hard-hangs the SoC — a bus/NOC
error; kdump can't run, pstore/ramoops didn't survive). Qualcomm SDI full-RAM-dump over USB is
the right instrument. This runbook is the one-pass procedure + what's pre-staged vs. your part.

## Status (audited 2026-07-12)
- KERNEL SIDE READY: `qcom_scm.download_mode` accepts off/full (round-trips, no SCM reject).
  DT has `qcom,dload-mode = <0x2a 0x4000>` (IMEM cookie). Firmware SDI fires on bus/NOC + panic.
- Kernel MINIDUMP driver NOT built in 7.1 (no CONFIG_QCOM_MINIDUMP) → only FULL dump available.
- Parse assets on box: `/home/jcasco/kernel-build/linux/vmlinux` (75M, NOT stripped, symtab
  present; NO DWARF), `System.map` (8.9M), `crash` utility (/usr/bin/crash), python3.
- Box has no direct internet; sandbox proxy blocks codelinaro/github → RDP (linux-ramdump-parser
  -v2) must come from your Qualcomm access OR be fetched on a networked machine. For our goal
  (faulting PC/function) the symtab + crash + a __log_buf extract is enough (see Parse below).

## What YOU provide (host = Windows box 192.168.8.22)
1. A **USB-C cable** A16 ↔ Windows box.
2. A **collector**, one of:
   a. **PCAT** (Qualcomm Product Configuration Assistant Tool) — softwarecenter.qualcomm.com
      (needs your Qualcomm ID). Purpose-built: auto-detects the dump-mode device, pulls all DDR
      regions to a folder. EASIEST if you have entitlement.
   b. **Open-source `edl.py`** (github.com/bkerler/edl): `pip install edlclient`; then swap the
      dump-mode USB device's driver to WinUSB via **Zadig** (the device shows as "Qualcomm
      9008"/"QDLoader" or "…900E Diagnostics"). Collect with the Sahara memory-dump mode.
3. Which port enters dump mode: usually the left USB-C. We confirm in Step 1.

## Pre-staged by me (on the box, ready to fire)
- `~/arm_dumpcap.sh` — sets grub one-shot to the crashing DTB with `qcom_scm.download_mode=1`
  baked into its cmdline (so dump mode is armed from the start of THAT boot), saved fallback =
  dt-test37. (Also a `~/disarm_dumpcap.sh` to revert.)
- `dt-test39` entry = test37 + LPASS macros (the reliable reproducer of the hang) + ramoops.
- `~/extract_logbuf.py` — fallback parser: given the DDR dump .bin(s) + System.map, locates the
  printk ringbuffer and dumps the kernel log (the panic/backtrace) without RDP.

## THE ONE PASS
### Step 0 — (optional but recommended) confirm firmware honors SDI, with a GUARANTEED panic
Purpose: prove the retail ASUS firmware actually enters dump mode before you invest in the
collector. On the box (SSH):
```
echo 1 | sudo tee /sys/module/qcom_scm/parameters/download_mode   # =full
echo c | sudo tee /proc/sysrq-trigger                             # forced clean panic
```
Watch the A16 screen: if it enters a dump/QDL state or just sits with USB enumerating (NOT a
normal reboot) → firmware honors SDI ✓. Plug the USB-C into the Windows box; PCAT/edl should see
a Qualcomm 9008/900E device. Power-cycle to recover (saved default = dt-test37). If it instead
reboots normally → firmware has dump mode fused off; STOP (need a debug policy — separate path).

### Step 1 — arm the real capture
On the box: `bash ~/arm_dumpcap.sh`  (arms dt-test39 one-shot + download_mode=1 on its cmdline).
On Windows: start the collector waiting for the device (PCAT "start"/edl dump mode).

### Step 2 — trigger
On the box: `sudo systemctl reboot -i`. The A16 boots dt-test39, the LPASS macro probe wedges
the SoC → firmware SDI → device enters dump mode on USB.

### Step 3 — collect
Plug/confirm the USB-C to the Windows box. PCAT auto-pulls all DDR regions → a dump folder
(DDRCS0.BIN, DDRCS1.BIN, load.cmm/rawdump table, etc.). Or `edl` Sahara memory-read.

### Step 4 — recover
Power-cycle the A16. It boots saved default = dt-test37 (fully working). Run `~/disarm_dumpcap.sh`
if needed (clears download_mode / one-shot).

### Step 5 — parse (find the faulting function)
Copy the dump folder to the box (or wherever vmlinux is). Options:
- RDP: `python2 ramparse.py -v vmlinux -a <dumpdir> -o out/` → out/dmesg_TZ.txt + stacks.
- `crash vmlinux <vmcore-or-DDR>` (needs the load layout; RDP or PCAT can emit an ELF vmcore).
- Fallback (no RDP): `python3 ~/extract_logbuf.py <DDRCS0.BIN> <phys_base> System.map` → prints
  the kernel log ring → the panic line + `pc : <func>` + Call trace. That names the faulting
  macro/register and settles "bad address vs clock stall."

## Notes / gotchas
- Bake `qcom_scm.download_mode=1` into the CRASHING kernel's cmdline (done in arm script) — a
  value set only on the current boot may be reset to "off" when the next kernel boots.
- If the macro fault is a pure hang with NO reset at all, dump mode won't engage (nothing resets
  the SoC). Step 0's sysrq-c panic is the guaranteed-reset fallback to at least prove the pipe.
- Recovery is always: power-cycle → dt-test37 (no watchdog on this platform, so a hang needs a
  manual power-cycle).
