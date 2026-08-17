# HANDOFF — 2026-07-28

Start here → then `RESUME-HERE.md` (live state) → `docs/DTB_CHANGELOG.md` (the full story).
Previous handoff archived as `HANDOFF-2026-07-20-archived.md` (stale: it describes the eDP
blocker, which was solved 2026-07-24 with HBR3).

Everything below is verified on-box unless marked ⏳ (untested) or ⚠️ (caution).

## Connect to the laptop THIS way

```bash
ssh -o HostKeyAlias=loazen jcasco@192.168.8.60
```

The IPv6 name (`loazen` → `…ea00::1c0c`) **goes stale after reboots** and gives phantom
`No route to host` while the machine is up and browsing fine. This cost hours. The host key
is stored under the bare name `loazen`, which is why plain IPv4 ssh fails verification.
**Before concluding the box crashed, ping `192.168.8.60`.**

Three more traps that bit us today:
- `/tmp` is wiped on reboot — long-running helper scripts must live in `~` (killed a kernel
  install twice).
- `pgrep -f "<pattern>"` inside an ssh command **self-matches** and always reports "running".
- A kernel that boots **headless** looks identical to one that failed to boot. **Check
  `journalctl --list-boots` before saying a kernel does not boot.**

## Machine state

- GRUB default: **`fedora-glymur-baseline`** = `glymur-a16-test71.dtb` + `7.1.0-glymur-gdsc1`.
- **Screen-off still hard-resets the SoC.** The guard is finally real:
  `glymur-stayawake.service` (user unit, enabled) = a **logind** inhibitor, *verified present
  in `systemd-inhibit --list`*, plus a 45 s `SimulateUserActivity` loop. The old
  `kde-inhibit` guard never registered (`ListInhibitions` = `{}`), so the box was free to
  blank and reset itself during an unknown number of earlier tests.
- Entries: `baseline`, `baseline-edp1k`, `ab-t64/65/68/69/70`, `ab-oldcmd`, `ab-t64-newcmd`,
  `test69..test72`, `konrad1`, plus the older lineage. Every `grub.cfg` edit has a
  `/boot/grub/grub.cfg.bak-*`.

## Workstream 1 — display teardown crash (OPEN; best lead is upstream contact)

The SoC hard-resets whenever the eDP panel powers down. **Do not re-derive:** Linux emits no
fault (pstore empty 7×); the trigger is `qcom_edp_phy_exit()` with **both halves
independently lethal**; deferring the power-down 1 s doesn't help; `phy_power_off()` provably
runs first; and the death signature (TZ fatal, latency) is **run-to-run variance, not a
discriminator**. Eliminated: `qcom_wdt`, PMIC PON registers, `sync_state`/interconnect,
idle-PC, EDL (download mode is fused off on retail hardware), eDP HPD.

### ★ The konrad tree — built, and it produced our most publishable result

`fedora-glymur-konrad1` = **Konrad Dybcio's upstream A16 device tree** (posted 2026-07-21,
still unmerged) on `7.2.0-rc3-konrad1`. Details: `docs/konrad-tree-plan.md`.

1. **★ eDP link training fails `-110` on his device tree.** We deliberately omitted our HBR3
   force to see whether his DT negotiates correctly alone. **It does not.** ⇒ the HBR3 finding
   is load-bearing, and upstream's A16 tree does not address it.
2. His DT boots fine (full Plasma session, 16 s) — it only *looked* dead: no display, no net.
3. The black screen was **his `&gpu`/`&gmu`**: adreno fails `-19` (SMMU + GX clock controller
   time out) and msm is a component framework, so one failed component kills the entire DRM
   bind. All four DP controllers bound fine. Fixed by disabling gpu/gmu.
4. Wi-Fi died because `VREG_WCN_3P3` was switched off — dropping `&pcie4_port0_ep` removed the
   graph link that keeps the rail claimed. Fixed with `regulator-always-on`.
5. `&remoteproc_cdsp` disabled — we never extracted `qccdsp8480.mbn`.

**konrad2** (HBR3 force + CDSP off + WCN pinned) is built and installed; msm srcversion
`257777F752CF092862B1337`, **verified inside the initrd**. ⏳ **Not yet booted.**

⚠️ **Five declared deviations from his DTS** — state all of them in any upstream report:
`&pcie4_port0_ep` removed, `&remoteproc_soccp` removed, the dangling `remote-endpoint` line
removed, `&gpu`/`&gmu` disabled, `&remoteproc_cdsp` disabled.

**Next:** boot `konrad1` (it picks up the konrad2 artifacts). Panel lights with HBR3? Then
**`kscreen-doctor --dpms off`** — does his tree reset too? That answer is the report.

## Workstream 2 — audio — ★ CAUSE FOUND 2026-07-28

**Two tweak files had gone missing from the live system:**

```
/usr/local/bin/glymur-audio-wait
/usr/lib/systemd/user/glymur-audio-wait.service
```

Found by diffing all 23 files in `tweaks/` against the box: **21 identical, 0 differing,
exactly these 2 missing.** They are the ADSP/PCM boot-race workaround — the thing
`CLAUDE.md` and `docs/audio-adsp-boot-ordering.md` both warn to check first.

The script's own header describes the observed symptom exactly: the card registers at
~t+11.4 s but its PCMs aren't openable for another second; PipeWire probes inside that
window, gets `EINVAL` on `hw:0,0/1/2`, **and does not retry** — so no output device ever
appears, while `hw:0,3` (capture) opens fine, *which is why the mic worked and output did
not*. That matches the "no output devices on BASELINE, that's NOT normal" report precisely.

**Restored, `systemctl --user enable`d** (symlinked into `wireplumber.service.wants`).

**Audio is working again as of 19:30 on 2026-07-28**, proven three ways at once:
`pw-play` of a 440 Hz tone moves **30 WSA884x registers** (out of 262 144 lines diffed) where
the same test showed **0** earlier today; the sink reports `RUNNING`; and the playback
produces **zero `CMD timeout` / `DSP returned` / `ASoC error`** lines — the oracle
`docs/audio-adsp-boot-ordering.md` says to trust instead of `speaker-test`.

⚠️ **Three honest limits on that claim:**

1. **Restoring `glymur-audio-wait` is NOT what fixed today's session.** It ran, printed
   `sink present (attempt 1)`, and took no action. What preceded the recovery was the
   `HiFi.conf` restore (18:59), `glymur-audio-route.service` (18:56), and a card
   re-registration at 18:43. Its value is **surviving the next reboot**, unproven so far.
2. **The boot-time failure is UNCHANGED.** This boot still logged **8 `CMD timeout` and 248
   `DSP returned error[1001006]`** in early boot. The DSP still drops its first commands; the
   session recovered afterwards. Expect a fresh boot to fail until something re-probes —
   which is precisely the job of the unit that was missing.
3. Register movement proves the hardware is driven, not that sound is audible. **Get user
   confirmation.**

⚠️ **`dmesg` on this box returns 0 lines** — the ring buffer is drained (`glymur-kmsg.service`
is the likely consumer). A grep of `dmesg` for `CMD timeout` returns 0 and looks like a clean
boot. **Always use `journalctl -k -b 0`.** This produced a false "first clean boot ever"
reading today before it was caught.

⚠️ **Kernel timestamps lie until NTP lands.** Early-boot lines are stamped `Jun 26 20:00`
(dead RTC, see `CLAUDE.md`); the clock jumps to real wall-clock mid-log. When correlating
events, anchor on the jump, not on the printed date.

### How they went missing — most likely our own cleanup

**Not a package update.** No audio package appears in any dnf transaction, and `alsa-ucm` was
installed 2026-07-18 and **never updated since**. The Jul-24 updates (txn 32 = 118 pkgs,
txn 36 = 18 pkgs) contain nothing audio-related.

The likely answer is in our own notes: memory `glymur-audio-adsp-ordering` says
*"`glymur-audio-wait.service` remains enabled as a **canary only**; if it says `sink present
(attempt 1)`, delete it."* A later session almost certainly followed that instruction. ⚠️ **It
reported exactly `sink present (attempt 1)` again today** — so the rule would delete it a
second time. **The rule is wrong and has been removed from memory:** the canary reports on an
*already-recovered* session, which says nothing about the *next boot*, where it is the only
thing that forces a re-probe.

**Recommended:** move the unit to `/etc/systemd/user/` (config territory, survives packaging)
and stop treating it as disposable.

⚠️ **`dnf history list --since <date>` silently returns EMPTY on dnf5 even when matching
transactions exist.** It sent me down a wrong path today. Use plain `dnf history list`, or
`rpm -qa --last` (which also catches PackageKit/Discover updates).

### ⛔ Retracted — two wrong conclusions from earlier today

1. **"Audio has never worked on this installation."** WRONG. It was built on absence of
   evidence — no captured log of working audio after the Jul-18 Fedora install. But
   `CLAUDE.md` lists audio under **Working** as of **2026-07-24**, and the user confirms it
   worked until a few days ago. It is a genuine regression on this install.
2. **"An `alsa-ucm` update replaced the customized `HiFi.conf`."** Not supported: that
   package was never updated. The restored `HiFi.conf` is correct to keep, but it was not
   the cause.

### Older material (kept — the eliminations remain valid)

**Symptom, every boot, deterministic to the microsecond across every kernel and DTB:**
`CMD timeout [1001021]` (`GET_SPF_STATE`) ~10.21 s → `CMD timeout [1001002]`
(`GRAPH_START`) ~17.89 s → cascade of `DSP returned error[1001006]`
(**`APM_CMD_SET_CFG`**, *not* "GRAPH_OPEN" as older notes claimed).

**Objective proof of where it stops:** 14 592 WSA884x amp registers compared idle vs playing
— **zero changed.** The amplifier is never engaged, because the DSP never starts the graph.

### Eliminated — all measured, do not repeat

device tree (audio nodes byte-identical across test47/52/55/64/71) · the eDP era (test55,
display disabled in DT) · msm (test72, blacklisted) · the kernel (clean+, edp1, gdsc1 **and
7.2-rc3**) · the gdsc patch (45 genpd domains on both kernels, 0 errors) · `qcom_pd_mapper`
(v7.1 *does* carry `qcom,glymur`) · `qcom,intents` + `qcom,protection-domain` (identical to
upstream) · DMIC routing · mixer state · PipeWire default sink · SELinux (disabled, 0 AVCs) ·
**the hardware — audio works in Windows** · `tqftpserv` (1.1.1 installed, running from boot,
no change) · the ACDB (`acdb_cal.acdb` staged in both serve paths, no change) · every file in
`a16-tweaks.tar.gz` (all 15 byte-identical to live).

`HiFi.conf` had also drifted to the stock X1E80100 version (playback on **MultiMedia1 /
`hw:0,0`** instead of **MultiMedia2 / `hw:0,1`**, which `glymur-audio-route.sh` and PipeWire
drive). Restored from `a16-tweaks.tar.gz`; stock kept as `HiFi.conf.stock-fc44.bak`. Correct
to keep, but see the retraction above — no package update caused it.

Also established: `hw:0,1` (MultiMedia2) **rejects 2 channels** — 4ch only. So the Jul-15
`speaker-test -c2` that "played cleanly" must have been `hw:0,0` (MultiMedia1). And the
working-era `tqftpserv` "tweak" was only a **build-environment fix** (meson needed
`systemd-dev` for `systemd_system_unit_dir`), **not a source patch** — confirmed from the
session transcripts. That thread is closed.

### Remaining audio leads — now LOW priority (only if sound is still wrong)

1. **The topology.** Ours descends from **X1E80100-Romulus — a Microsoft Surface file**
   (31 892 B, kept as `.romulus.bak`), hand-modified into the current 29 496 B file that
   matches no public board. `firmware/tplg/GLYMUR-CRD.tplg` **loads fine** but exposes a
   different PCM layout (`pcm0p pcm1c` vs our four), so it cannot be judged without a matching
   UCM. **Inconclusive, not eliminated.** System restored to the 29 KB file.
2. **The ADSP firmware payload** — `qcadsp8480.mbn` (19 851 224 B) + `adsp_dtbs.elf`
   (225 080 B). Never varied. Compare byte-for-byte against `FileRepository.zip`; Windows
   works, so what it feeds the DSP is correct by definition. **Cheapest untried step.**
3. **Rebuild qrtr + tqftpserv 1.2 from `linux-msm`** (SRCREV `b6bb92d…` per meta-qcom) instead
   of Fedora's 1.1.1 — the only remaining version delta.

## Upstream / LKML

**Ready:** the eDP `-110` result on Konrad's own DT at v7.2-rc3, plus the teardown-crash
report with its elimination list. His series is unmerged and taking review; cc **Abel Vesa**
and **Dmitry Baryshkov** (both reviewed it).

⛔ **Do NOT send the gdsc patch as ours** — upstream fixed the `gdsc_unregister()` half itself
between v7.1 and v7.2. Only the `gdsc_register()` **error-path** cleanup is still missing, and
it is a leak-on-failure, not a crash fix.

⚠️ Before writing: **reproduce the konrad results at least twice** (a single unreproduced boot
sent us down a two-day path), and check whether msm's DP link-rate code changed after rc3 so
the report isn't stale.

Credit rules and the adopted-work table live in **`UPSTREAM-CREDITS.md`** — every piece of
upstream work we carry is credited with author, patch subject and message-id.

## Order I would take next

1. **Confirm audio is audible after a fresh reboot** — the boot-race workaround is back and
   enabled, but it has not yet been proven across a reboot (today it was run by hand).
2. Boot **`konrad1`** → does the panel light? → `kscreen-doctor --dpms off` → does it reset?
   While there, check whether the internal keyboard/backlight works **without**
   `asus-kbd-init` — Konrad's DT can't supply a vendor HID handshake, but an upstream ASUS
   HID quirk would make that tweak redundant.
3. Draft the upstream mail once konrad is reproduced.

### Keep the tweaks honest

`tweaks/` is the source of truth for the 23 local customizations. **Verify it against the box
whenever anything behaves oddly** — that single diff is what found this bug after two days of
looking in the wrong places:

```bash
cd tweaks && find . -type f -printf '%P\n' | while read -r f; do
  md5sum "$f" | sed "s|  \./|  /|"; done   # then compare each path on the box
```

A committed `scripts/verify-tweaks.sh` doing exactly this would be worth the ten minutes.

## Privacy

`memory-archive/a16-disk-and-fedora-daily.md` contains **plaintext credentials** and the NVMe
partition map. Keep this tree private — never paste it into public issues, LKML posts, or PRs.
NVMe p1–p11 (Qualcomm/WoA firmware) and p13–p16 (Windows) must never be written to.
