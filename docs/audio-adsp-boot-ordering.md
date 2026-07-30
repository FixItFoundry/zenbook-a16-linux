# Audio: the ADSP firmware boot-ordering trap

**Status as of 2026-07-24:** root cause identified and a persistent fix applied.
Sound card + routing verified up; end-to-end playback still failing on a DSP
graph-open error, pending a clean-boot retest.

This has now bitten the project more than once. Read this before concluding that
"audio broke" or that an ADSP patch/firmware was lost.

## The symptom

No sound at all. `/proc/asound/cards` reports `--- no soundcards ---`, and six
devices are wedged in deferred probe:

```
$ cat /sys/kernel/debug/devices_deferred
6c80000.soundwire   platform: wait for supplier /soc@0/pinctrl@7760000/wsa-swr-active-state
6ca0000.soundwire   platform: wait for supplier /soc@0/pinctrl@7760000/wsa2-swr-active-state
sound               snd-x1e80100: WSA Playback: error getting cpu dai name
7760000.pinctrl     qcom-sm8650-lpass-lpi-pinctrl: Failed to get clk 'core'
7660000.codec       platform: wait for supplier /soc@0/pinctrl@7760000/dmic23-default-state
6c90000.codec       platform: supplier 7660000.codec not ready
```

It looks like six independent failures. It is one, with five knock-ons.

## The actual cause

**It is not a missing driver, a missing DT node, or missing firmware.** Every one
of those is present and correct. It is a boot *ordering* race:

```
t+1.56s  qcom_q6v5_pas probes (it ships INSIDE the initramfs)
t+1.56s  request_firmware(qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn) -> -2 (ENOENT)
t+2.46s  EXT4-fs (nvme0n1p17): mounted filesystem      <-- the firmware lives HERE
```

The driver asks for its firmware ~0.9 s before the filesystem holding it is
mounted. `remoteproc` does **not** retry, so the ADSP stays `offline` forever.

The dependency chain that collapses from there:

```
ADSP offline
  -> q6prmcc never registers          (the clock provider lives INSIDE the ADSP)
    -> pinctrl@7760000 never gets clk 'core'
      -> wsa/wsa2 soundwire, 3x codec, sound card all stay deferred
        -> no sound card
```

The giveaway that the provider is the DSP and not any `gcc`: the pinctrl node's
`clocks` property is a **two-cell** spec, `<&q6prmcc 102 1>, <&q6prmcc 103 1>`
(`LPASS_HW_MACRO_VOTE`, `LPASS_HW_DCODEC_VOTE`). Decode it from the live tree:

```sh
xxd -p /proc/device-tree/soc@0/pinctrl@7760000/clocks
# 000001330000006600000001 000001330000006700000001
```

## Confirming it in a running session

```sh
cat /sys/class/remoteproc/remoteproc0/state          # offline
sudo dmesg | grep -i "request_firmware failed"       # -2
ls -l /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn   # present!
```

Firmware present + `-2` at boot == this bug. Start it by hand to prove it:

```sh
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
```

The ADSP boots, `q6prmcc` appears, and the whole audio stack cascades up within
a few seconds — card `GLYMUR-A16` shows up in `/proc/asound/cards`.

## The persistent fix

Ship the firmware **inside the initramfs** so it is readable when the driver probes
at ~t+1.5s. Keep the driver in the initramfs where dracut already put it.

`/etc/dracut.conf.d/99-glymur-adsp.conf`:

```
install_items+=" /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn \
                 /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf \
                 /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/adspr.jsn \
                 /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/adspua.jsn "
```

Costs ~9 MB of initramfs (49 MB → 58 MB). Worth it.

### Rejected first attempt — `omit_drivers`, and why it was wrong

The first fix was `omit_drivers+=" qcom_q6v5_pas "`, keeping the driver *out* of the
initramfs so it loaded after switch-root when the firmware was readable. That does fix
the `-2` and the ADSP does come up — **but it introduced a second, subtler bug.**

Delaying the driver moved ADSP boot from t+1.5s to **t+5.3s**, and card registration
takes a further ~5.7s (soundwire enumeration + codec probes), so the sound card did not
register until **t+11.4s**. PipeWire starts at **t+12.2s** — a margin of ~0.8s. It then
opened the PCMs before they were ready:

```
spa.alsa: 'hw:0,0': playback open failed: Invalid argument
spa.alsa: 'hw:0,1': playback open failed: Invalid argument
spa.alsa: 'hw:0,2': capture open failed: Invalid argument
wireplumber: Failed to create alsa_output.platform-sound.playback.0.0
```

WirePlumber does **not** retry, so the speakers never appeared and had to be recovered
by toggling the card off/on in the desktop. `hw:0,3` (MultiMedia4 Capture) opened fine,
which is exactly why **the microphone worked at boot and the output did not** — a very
distinctive symptom worth recognising.

Lesson: the historical, working behaviour was ADSP up at ~t+1.5s and the card
registered around t+7s, leaving PipeWire seconds of margin. Fix the firmware
availability, do not delay the driver.

Then rebuild **the initramfs the GRUB entry actually loads** (see the initramfs
trap in the memory notes — it is `/boot/initrd.img-<kver>`, NOT dracut's default
`/boot/initramfs-<kver>.img`):

```sh
sudo dracut --force --kver 7.1.0-glymur-gdsc1 /boot/initrd.img-7.1.0-glymur-gdsc1
# both must be PRESENT:
sudo lsinitrd /boot/initrd.img-7.1.0-glymur-gdsc1 | grep q6v5
sudo lsinitrd /boot/initrd.img-7.1.0-glymur-gdsc1 | grep qcadsp8480
```

## The remaining race: msm costs the second that matters

Measured across builds (all times monotonic):

| build | msm | ADSP up | SPF timeout | card registers |
|---|---|---|---|---|
| test57 | blacklisted | 1.76s | 9.19s | **9.34s** |
| test58-edp | blacklisted | 1.84s | 9.19s | **9.34s** |
| gdsc1 (`omit_drivers`, 49 MB initrd) | autoloads | 5.3s | ~10.2s | **10.359s** |
| gdsc1 (firmware in initrd, 58 MB) | autoloads | 1.41s | 10.21s | **10.36s** |

PipeWire starts in the **10.4–12.2s** band, so the margin is 0–2s and it is a coin
flip which one wins. Two conclusions the numbers force:

- **The 5s `APM_CMD_GET_SPF_STATE` timeout is not new** — it is in every log going
  back to test57. It is not caused by any recent change.
- **Initramfs size is irrelevant.** 49 MB and 58 MB both land the card at 10.36s.
- **msm is the ~1s.** Every boot with the card at 9.34s had
  `modprobe.blacklist=msm`; every boot at 10.36s autoloads it. msm is a 2 MB module
  binding through udev in the same window.

### Do NOT "fix" this by deleting the blocking state query

`q6apm_probe()` calls `q6apm_get_apm_state()` and discards the result, which looks
like 5 wasted seconds begging to be deleted. It is not safe to remove:
`prm_probe()` in `q6prm.c` calls the same `q6apm_is_adsp_ready()` and returns
`-EPROBE_DEFER` when the DSP is not ready. It is a real readiness gate. Deleting the
apm_probe call just moves the identical wait into q6prm's defer loop.

The DSP genuinely is not audio-ready until ~10s from boot. The first query appears to
be sent before the APM service is listening and is simply dropped (the *second* query
succeeds immediately). A short-timeout-with-retry instead of one blocking 5s wait is
the promising direction, but it is unproven.

### Canary: `glymur-audio-wait.service`

A user unit (`~/.config/systemd/user/glymur-audio-wait.service` +
`~/.local/bin/glymur-audio-wait`) waits for the ALSA sink after WirePlumber starts and
restarts WirePlumber if it never appears. It was written as a workaround for the
`omit_drivers` regression above.

With the firmware-in-initramfs fix it should be **unnecessary**, and it is deliberately
left enabled as a **canary**: check its log after boot.

```sh
journalctl --user -b -u glymur-audio-wait
```

- `sink present (attempt 1)` → the real fix worked; **the unit can be deleted.**
- `restarting wireplumber (try N)` → the race is still happening; keep it and dig further.

Autoload after switch-root is verified — the ADSP node's compatible chain is
`qcom,glymur-adsp-pas`, `qcom,sm8550-adsp-pas`, and the **second** matches the
module alias:

```sh
$ cat /sys/bus/platform/devices/6800000.remoteproc/modalias
of:NremoteprocT(null)Cqcom,glymur-adsp-pasCqcom,sm8550-adsp-pas
$ sudo modprobe -R "$(cat /sys/bus/platform/devices/6800000.remoteproc/modalias)"
qcom_q6v5_pas
```

Note: grepping the module aliases for the *first* compatible alone gives a false
negative. DT compatibles are a fallback chain; match against the whole modalias.

## Still open

After hand-starting the ADSP mid-session, the card, the four WSA884x amps, the
UCM profiles and the mixer routing all come up, but playback fails with:

```
qcom-apm gprsvc:service:2:1: DSP returned error[1001006] 9
qcom-apm gprsvc:service:2:1: Error (9) Processing 0x01001006 cmd
```

i.e. the DSP refuses graph-open. Strongly suspected to be an artifact of starting
the ADSP ~1000 s late, after the audio stack had already probed and settled.
**Retest from a clean boot with the initramfs fix before debugging this further.**
If it persists on a clean boot, look at the topology file next
(`/lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin`, which has `.predrop.bak` and
`.romulus.bak` variants alongside it).

Also note: `RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1`/`MultiMedia2` were both
`[off]` and had to be switched on by hand. On a clean boot UCM should set these;
if it does not, that is a separate UCM-application bug worth its own look.

## Reproduction procedure (Jesse's, use this one)

The failure is intermittent, so a single "it played" or "it didn't" proves very little.
Use a fixed procedure every boot:

1. Boot. Wait for Wi-Fi to associate and connect.
2. Change the volume — Plasma plays a feedback sound. **That is the test.**
3. If there is no sound: open audio settings, switch the *Built-in Audio* card
   **off**, wait ~3 seconds, switch it **on**, and repeat step 2.
4. If still nothing: try the test button in the settings UI.
5. If nothing brings audio up, capture `sudo dmesg | grep -E "CMD timeout|DSP returned|ASoC error"`.

⚠️ **`speaker-test` is not a reliable oracle here.** It has both produced clean
4-channel output (PCM `state: RUNNING`, `hw_ptr` advancing, no DSP errors) *and* hung
on "Front Left" on a later boot. Do not conclude "audio works" from one successful
`speaker-test` run — that mistake was made during the 2026-07-25 session.

## What is actually known (2026-07-25)

- The card, the sink, the four WSA884x amps and the UCM profiles all come up.
- Failures cluster in the **first ~20 seconds**, and always on the *first* DSP
  interaction: `GET_SPF_STATE` times out then works; the first graph fails then works.
- Two distinct boot-time failures were captured in one boot:
  - `t+11.79s  MultiMedia1 Playback: no backend DAIs enabled, possibly missing ALSA
    mixer-based routing or UCM profile` — the login sound firing 0.8s after the card
    registered, before WirePlumber applied UCM routing. Silent, no hard error.
  - `t+18.40s  MultiMedia2: CMD timeout [1001002] (APM_CMD_GRAPH_START), -110`, then
    repeated `DSP returned error[1001006] 9` (GRAPH_OPEN refused).
- Later playback in the same session has been observed working cleanly, and also
  observed hanging. **It is intermittent, not deterministically fixed by time.**

Do not claim this is solved without repeated runs of the procedure above.

---

# ★ 2026-07-27 — MEASURED BOOT, AND A CORRECTION TO THIS DOCUMENT

Full timeline captured on the 19:13:10 boot (test70 DTB, kernel `7.1.0-glymur-gdsc1`,
msm **autoloading**, ADSP firmware in the initramfs). All times are monotonic `dmesg`.

| t (s) | event |
|---|---|
| 1.611 | `remoteproc0: adsp is available` |
| 1.629 | booting `qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn` (19.85 MB) |
| **2.013** | **`remote processor adsp is now up`** |
| 2.053 | `PDR: Indication received from msm/adsp/audio_pd, state: 0x1fffffff` — GPR services `gprsvc:service:2:1` and `:2:2` added |
| 2.535–2.538 | msm binds `af54000` / `af5c000` / `af6c000` displayport-controllers |
| 2.596 | `[drm] Initialized msm 1.13.0` |
| **3.680** | **`fb0: msmdrmfb` — msm is finished** |
| **10.212** | **`qcom-apm: CMD timeout for [1001021] opcode`** |
| 10.463 | `snd-x1e80100 sound: Parent card not yet available, widget card binding deferred` |
| 10.470 | `input: GLYMUR-A16 Headset Jack … card0` — the card exists |
| 11.408 | `MultiMedia1 Playback: no backend DAIs enabled … missing UCM profile` |
| **18.404** | **`CMD timeout for [1001002]`** → `Failed to start APM port 105` → `ASoC error (-110) at soc_dai_trigger() on WSA_CODEC_DMA_RX_0` |
| 18.446+ | `DSP returned error[1001006] 9`, repeating |

## ⛔ Correction 1 — `1001006` is **not** "GRAPH_OPEN"

Decoded against `sound/soc/qcom/qdsp6/audioreach.h`:

| opcode | name | header line |
|---|---|---|
| `0x01001021` | `APM_CMD_GET_SPF_STATE` | `audioreach.h:38` |
| `0x01001002` | `APM_CMD_GRAPH_START` | `audioreach.h:55` |
| `0x01001006` | **`APM_CMD_SET_CFG`** | `audioreach.h:59` |

Earlier text in this document calls `DSP returned error[1001006] 9` a "GRAPH_OPEN refused".
**That is wrong.** It is `APM_CMD_SET_CFG` being rejected with status 9, which is a
*downstream consequence* of the failed `GRAPH_START` immediately above it, not an
independent failure. Do not keep treating the two as separate symptoms.

## ⛔ Correction 2 — "msm is the ~1 s" does not survive this boot

The timeout is not a mystery constant. `audioreach.c:604-606`:

```c
rc = wait_event_timeout(*cmd_wait, (result->opcode == hdr->opcode), 5 * HZ);
...
dev_err(dev, "CMD timeout for [%x] opcode\n", hdr->opcode);
```

**Every synchronous DSP command waits a hard-coded 5 seconds.** So the print time minus 5 s
is the send time:

- `GET_SPF_STATE` printed at 10.212 ⇒ **sent at ≈ 5.21 s**
- `GRAPH_START` printed at 18.404 ⇒ **sent at ≈ 13.40 s**

**msm was completely finished at 3.680 s — 1.5 s before the first DSP command was even
sent.** On this boot msm cannot be what delays card registration. The card lands at ~10.4 s
because a command sent at 5.2 s went unanswered for its full 5 s timeout.

The measured table in "The remaining race" above is still real data, but its conclusion —
"msm is the ~1s" — was **a correlation presented as a mechanism**. The defensible version:

> With msm autoloading, the audio probe chain *starts* about a second later (udev and the
> deferred-probe list are serialised, and msm is a 2 MB driver binding four sub-devices in
> that window). That shifts the whole timeout cascade by ~1 s. **The dominant term is not
> msm — it is the 5 s timeout on a dropped first command.** Blacklisting msm buys ~1 s;
> making the first command retry would buy ~5 s.

This is still not proven. **The discriminating experiment** is a same-DTB control: a GRUB
entry identical to test69/test70 plus `modprobe.blacklist=msm`, changing exactly one
variable (the old 9.34 s data points came from test57/test58 DTBs, so they carry a second
variable). Measure the send time of the first `GET_SPF_STATE`, not just the card time.

## ★ What this actually points at — the same failure, twice

Both failures are one phenomenon: **the DSP does not answer the first command of a kind, and
the caller eats a 5 s timeout.**

- at 5.2 s, `GET_SPF_STATE` is dropped → card registration is pushed to ~10.4 s;
- at 13.4 s, `GRAPH_START` is dropped → playback fails outright, and the following
  `SET_CFG`s are then rejected (status 9) because the graph never started.

The second one is the audio breakage users hear. It is **not** a PipeWire race — PipeWire
had already been running for seconds by 13.4 s. Framing this as "a thin race with PipeWire"
under-describes it.

### Candidate fix, unproven: retry the first command instead of eating the timeout

`audioreach.c` waits once, 5 s, then gives up. If the first packet of a session is genuinely
dropped rather than slow, a short-timeout-and-resend would fix **both** symptoms with one
change. This supersedes the "short-timeout retries would pull card registration from ~10.4 s
to ~6 s" note above, which only considered the card, not the playback failure.

⚠️ Still do **not** simply delete `q6apm_get_apm_state()` — `prm_probe()` depends on the same
readiness gate (see the section above; that reasoning is unchanged and still correct).

### Also worth one cheap test: we route two DMICs that upstream does not

Konrad Dybcio's upstream A16 device tree routes **two** DMICs:

```
"VA DMIC0", "vdd-micb",
"VA DMIC1", "vdd-micb"
```

Ours routes **four** — `VA DMIC2` and `VA DMIC3` as well. If those two do not physically
exist on this board, any graph containing them is invalid, which is a plausible contributor
to `SET_CFG` rejections. Removing them from `audio-routing` is a one-line DT change and a
single variable. (Everything else in our `sound` node is structurally identical to his —
same `qcom,glymur-sndcard`, same dai-link shape, same `WSA_CODEC_DMA_RX_0` = 105 and
`VA_CODEC_DMA_TX_0` = 110 port numbers, same twelve-entry WSA codec list.)

## How to reproduce this measurement

```bash
sudo dmesg | grep -aE "adsp is now up|Initialized msm|msmdrmfb|CMD timeout|DSP returned|\
Headset Jack|no backend DAIs|soc_dai_trigger"
```

Read it as: `adsp is now up` = ADSP ready; `msmdrmfb` = msm done; each `CMD timeout for [X]`
happened **5 s after that command was sent**; the card exists once `Headset Jack … card0`
appears. Decode opcodes against `sound/soc/qcom/qdsp6/audioreach.h`.

## ⛔ Correction 3 — audio is NOT "intermittent" at the DSP level. It fails on EVERY boot.

Jesse asked the right question: *do the logs ever come back clean?* Answer, measured across
the whole persistent `/var/log/glymur-kmsg.log` (which spans every boot since the fsync
logger was installed):

```
boots that reached a card: 76
of those, ZERO DSP timeouts and ZERO errors: 0
```

**Not one clean boot in 76.** Every boot that registered a card shows:

- `CMD timeout for [1001021]` (`GET_SPF_STATE`) at **9.7–10.7 s**, and
- the card appearing **0.15–0.3 s later**, every time, 76/76, and
- in nearly all of them, `CMD timeout for [1001002]` (`GRAPH_START`) at **17.4–18.9 s**,
  followed by 1–229 `DSP returned error[1001006] 9` (`SET_CFG`) rejections.

So the standing description — "playback is a lottery in the first ~20 s", "intermittent,
not deterministically fixed by time" — describes **what the user hears**, not what the
hardware does. The underlying DSP failure is **100 % deterministic and reproducible on
every single boot.** What varies is only whether something later recovers enough for sound
to come out.

This matters for how we test: a fix can be evaluated on **one boot**, by grepping for the
two timeouts, instead of needing repeated runs of the subjective listening procedure. It
also means the card-registration time is not a race at all — it is a fixed 5 s penalty:

```
card_time ≈ (time the first GET_SPF_STATE is sent) + 5 s + ~0.2 s
```

### Reproduce this analysis

```bash
sudo python3 - <<'PY'
import re
LOG="/var/log/glymur-kmsg.log"; boots=[]; cur=None
for raw in open(LOG, errors="replace"):
    m=re.match(r'^\d+,(\d+),(\d+),[^;]*;(.*)$', raw.rstrip("\n"))
    if not m: continue
    usec, text = int(m.group(2)), m.group(3)
    if cur is None or usec < cur["last"] or "kmsg logger up" in text:
        cur={"last":usec,"card":None,"to":[],"err":0,"n":0}; boots.append(cur)
    cur["last"]=usec; cur["n"]+=1
    if "Headset Jack" in text and cur["card"] is None: cur["card"]=usec/1e6
    t=re.search(r'CMD timeout for \[([0-9a-f]+)\]', text)
    if t: cur["to"].append((usec/1e6,t.group(1)))
    if "DSP returned error" in text: cur["err"]+=1
full=[b for b in boots if b["n"]>=50 and b["card"]]
clean=[b for b in full if not b["to"] and not b["err"]]
print("boots that reached a card:", len(full))
print("of those, ZERO timeouts and ZERO errors:", len(clean))
PY
```

Opcodes: `1001021` = `GET_SPF_STATE`, `1001002` = `GRAPH_START`, `1001006` = `SET_CFG`
(`sound/soc/qcom/qdsp6/audioreach.h`).

## ⏭️ STAGED — `fedora-glymur-test71`: drop `VA DMIC2`/`VA DMIC3` from `audio-routing`

Jesse's call 2026-07-27 — he had questioned the four-DMIC routing before, and upstream's A16
DTS routes only two. Built from the **installed** test70 DTB, single property changed:

```
-   … "VA DMIC0", "vdd-micb", "VA DMIC1", "vdd-micb", "VA DMIC2", "vdd-micb", "VA DMIC3", "vdd-micb";
+   … "VA DMIC0", "vdd-micb", "VA DMIC1", "vdd-micb";
```

Verified by decompiling both DTBs and diffing: **that one line and nothing else.**
`/boot/glymur/glymur-a16-test71.dtb`; GRUB entry `fedora-glymur-test71`; backup
`/boot/grub/grub.cfg.bak-pre-test71`; default still test69; test69 and test70 untouched.

**How to read the result — one boot is now enough (see Correction 3):**

```bash
sudo dmesg | grep -aE "CMD timeout|DSP returned|Headset Jack"
```

- Both timeouts still present ⇒ the DMIC routing was not involved. Honest expectation: this
  is the likely outcome, because a bogus DAPM route normally produces a widget warning
  rather than a DSP-side rejection. It is still worth doing — the routing is wrong on its
  own merits and upstream disagrees with us.
- `GRAPH_START` timeout gone ⇒ the invalid mic widgets were poisoning graph setup, and this
  is a real fix.
- Card still lands ~5 s after the first `GET_SPF_STATE` either way; only the retry patch
  would change that.

## ⛔ test71 RESULT — dropping `VA DMIC2/3` changes NOTHING

Booted 2026-07-27 19:43 on test71 (live DT confirmed: `VA DMIC0 VA DMIC1` only):

```
[   10.212760] CMD timeout for [1001021]   (GET_SPF_STATE)
[   18.404692] CMD timeout for [1001002]   (GRAPH_START)
[   10.353208] Headset Jack ... card0
             275 x DSP returned error[1001006]
```

Byte-for-byte the same failure. Keep the change — the four-DMIC routing was wrong and
upstream routes two — but it is **not** the audio fix. Predicted outcome, now confirmed: a
bogus DAPM route produces a widget warning, not a DSP-side rejection.

### ★★ The failure is DETERMINISTIC TO THE MILLISECOND, so it is not a race

| boot | GET_SPF_STATE timeout | GRAPH_START timeout |
|---|---|---|
| 19:13 (test70) | 10.212123 | 18.404069 |
| 19:43 (test71) | 10.212**760** | 18.404**692** |

Two separate boots, sub-millisecond agreement. **A race jitters; this does not.** Retire
the "thin race with PipeWire" model entirely — it is a fixed, reproducible sequence.

## ★★★ THE REGRESSION, LOCATED — it is `GRAPH_START`, and only `GRAPH_START`

Jesse's recollection that audio worked before msm is supported by the archived dmesg
captures in `logs/` (Jul 20–24, all `modprobe.blacklist=msm`, kernel `clean2`):

| capture | ADSP up | CMD timeouts | DSP errors | card |
|---|---|---|---|---|
| `edp-hbr2-bind.log` | 1.74 s | **1** — `[1001021]` @ 9.19 s | **0** | 9.43 s |
| `test58-edp-msm-bind.log` | 1.84 s | **1** — `[1001021]` @ 9.19 s | **0** | 9.34 s |
| `test62-msm-bind.log` | 1.95 s | **1** — `[1001021]` @ 14.31 s | **0** | 14.57 s |
| `edp-v8probe`, `edp-v8swing`, `test58-pkvm`, `test62b`, `test63` | — | **1** each | **0** each | yes |

Eleven archived captures, **`DSP returned error` count = 0 in every one.**

So, precisely:

- **`GET_SPF_STATE` timing out is NOT the regression** — it is in every capture back to
  Jul 20, at 9.19 s then and 10.21 s now. It only delays card registration.
- **`MultiMedia1: no backend DAIs enabled` is NOT the regression** — also present back then
  (20.7 s / 25.7 s).
- **The regression is `MultiMedia2`'s `GRAPH_START` being dropped**, and the `SET_CFG`
  rejections that follow it. Nothing else changed.

### ⚠️ Honest limit on that evidence — do not treat it as proof yet

In every one of those old boots msm was blacklisted, so **there was no display and no normal
desktop session**. It is entirely possible that nothing ever attempted MultiMedia2 playback,
and that the zero error count reflects *absence of attempts*, not a healthy DSP. The
MultiMedia1 warning shows something touched audio, but that path fails at DAPM level without
ever issuing a DSP graph command.

### ⏭️ The discriminating experiment, and it is cheap

A GRUB entry identical to test71 **plus `modprobe.blacklist=msm`** — same kernel, same DTB,
one variable. There will be no display, which is fine: drive playback over ssh and watch
`dmesg`, rather than relying on the desktop.

```bash
# on the msm-blacklisted boot, over ssh:
sudo dmesg | grep -aE "CMD timeout"      # is [1001002] GRAPH_START absent at boot?
speaker-test -c 4 -l 1                   # force a real playback attempt
sudo dmesg | grep -aE "CMD timeout|DSP returned"
```

- `GRAPH_START` succeeds without msm ⇒ **msm is causally involved**, and the ~1 s probe-order
  story is not the whole picture. That would be the regression, located.
- `GRAPH_START` fails identically without msm ⇒ msm is exonerated, the old clean logs were
  simply boots where nobody played anything, and the target is the DSP first-command
  behaviour itself.

Either answer is worth the boot. This supersedes "blacklisting msm buys ~1 s" as the reason
to run the control.

## Konrad Dybcio's upstream A16 audio config, compared property by property

From `upstream/dts/glymur-asus-zenbook-a16-ux3607oa.dts` (see `UPSTREAM-CREDITS.md`).

| | ours (test71) | upstream | verdict |
|---|---|---|---|
| sound compatible | `qcom,glymur-sndcard` | same | ✅ |
| WSA speakers | 4x `sdw20217020400`, `swr0` left / `swr3` right | same | ✅ |
| `qcom,port-mapping` woofer | `<1 2 3 7 12 14>` | `<1 2 3 7 12 14>` | ✅ identical |
| `qcom,port-mapping` tweeter | `<4 5 6 7 13 15>` | `<4 5 6 7 13 15>` | ✅ identical |
| speaker `reset-gpios` | `lpass_tlmm 12` / `13` | same | ✅ |
| dai-links | `q6apmbedai 105` WSA / `110` VA | same | ✅ |
| ADSP `firmware-name` | `qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn` + `adsp_dtbs.elf` | **identical** | ✅ |
| `qcom,dmic-sample-rate` | `<4800000>` (dtc prints it as `"", "I>"`) | `<4800000>` | ✅ |
| **DMIC routing** | DMIC0–1 after test71 (was 0–3) | **DMIC0–1** | ✅ after test71 |
| **DMIC pinmux** | `pinctrl-0 = <&dmic01 &dmic23>` — **two states** | **`<&dmic01_default>` only** | ❌ still differs |
| **card `model`** | `GLYMUR-A16` | `GLYMUR-ASUS-Zenbook-A16-UX3607OA` | ⚠️ see below |

**⇒ The speaker path is byte-identical to upstream.** Port mapping, supplies, reset GPIOs,
DAI links, ADSP firmware paths — all the same. Whatever breaks `GRAPH_START` is not in the
speaker wiring.

### ★ The card `model` string selects the topology binary — do not change it casually

`sound/soc/qcom/qdsp6/topology.c:1320`:

```c
char *tplg_fw_name = kasprintf(GFP_KERNEL, "qcom/%s/%s-tplg.bin",
                               card->driver_name, card->name);
```

`card->name` is the DT `sound { model = ... }`. So:

- ours → `qcom/glymur/GLYMUR-A16-tplg.bin` — **present** (29 496 bytes, dated Jul 12),
  alongside `GLYMUR-A16-tplg.bin.predrop.bak` (same size) and
  `GLYMUR-A16-tplg.bin.romulus.bak` (31 892 bytes — a Microsoft *Romulus* topology that was
  evidently tried and rejected);
- upstream → `qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin` — **we do not have this
  file.**

⚠️ **Consequence, and a trap for later:** if we ever adopt Konrad's DTS wholesale, audio will
break at topology load unless we either keep our `model` string or obtain the matching
topology binary. Conversely, our topology has not changed since **Jul 12**, i.e. it is
constant across the whole working→broken transition, so **the topology cannot by itself be
the regression** — though it remains the thing that defines the MultiMedia2 graph that now
fails to start.

### DMIC verdict: two is correct, and our change is not finished

Upstream muxes **only** `dmic01_default` and routes only `VA DMIC0`/`DMIC1`. Our
`lpass_vamacro` still carries **two** pinctrl states (`pinctrl-0 = <0x210 0x211>` =
`dmic01` + `dmic23`), so test71 removed the DAPM routes but left the pins muxed. Completing
it means dropping the second phandle. Low risk either way — muxing unpopulated DMIC pins is
inert — so this is a **correctness fix, not a bug fix**; test71 already proved it changes
none of the DSP failures.

⚠️ Before finishing it, confirm capture still works on test71 (`pcm2c`/`pcm3c` exist). If
this board really does have four DMICs, dropping the pins would cost microphone channels.

## ★★★ 2026-07-27 (late) — THE DEVICE TREE IS ELIMINATED. The regression is in the BUILD.

Jesse: *"test 53-55 had flawless audio"*. So the whole audio subtree was compared between
`test55.dts` (from the LoA drive, `Linux-X2-Project/boot-kit/`) and our current `test69.dts`,
using brace-matched node extraction (raw diff is useless — dtc renumbers phandles):

| node | result |
|---|---|
| `codec@6c90000` (WSA macro) | **IDENTICAL** |
| `codec@6cb0000` (WSA2 macro) | **IDENTICAL** |
| `codec@7660000` (VA macro) | **IDENTICAL** |
| `pinctrl@7760000` (LPASS LPI) | **IDENTICAL** |
| `soundwire@6c80000` | **IDENTICAL** |
| `soundwire@6ca0000` | **IDENTICAL** |
| `remoteproc@6800000` (ADSP) | **IDENTICAL**, incl. `firmware-name` |

And the `sound` node is byte-identical to **test47** as well — same `model = "GLYMUR-A16"`,
same dai-links, and *all four DMICs routed in the working era too*.

⇒ **Nothing in the device tree changed between flawless audio and broken audio.** Stop
looking there. The regression is in what we *packaged*: kernel build, firmware, or initramfs.

### ★ What the DSP is actually doing now — every command times out

Measured on the 2026-07-27 evening session (test71):

| command | opcode | result |
|---|---|---|
| `APM_CMD_GET_SPF_STATE` | `1001021` | timeout, every boot |
| `APM_CMD_GRAPH_START` | `1001002` | timeout, every boot |
| `APM_CMD_SHARED_MEM_UNMAP_REGIONS` | `100100d` | timeout ×4 on card rebind |

**Not one successful DSP command has ever been observed.** The kernel does not check, so it
starts the DMA regardless: `hw_ptr` advances, the mixer reads `on`, the whole WSA macro
chain powers up through `WSA_SPK1/2 OUT` — and yet on the amps themselves
`WooferLeft SPKR Playback: Off  in 1 out 0`. Amps `Attached` and powered, no data arriving.

⇒ The APM service inside the ADSP is **not servicing commands at all**, despite
`remoteproc0` reporting the ADSP up and PDR reporting `audio_pd` state `0x1fffffff` (= UP).
Everything above that is theatre. This is why nothing tried today moved the needle: DMIC
routing, msm blacklisting, mixer re-apply, PipeWire restarts, and a full card rebind are all
upstream of a DSP that is not listening.

⚠️ After a card rebind the DSP is left wedged (4 consecutive unmap timeouts) — **reboot
before any further audio experiment** or the results are meaningless.

### ⏭️ THE NEXT TEST — an A/B that already exists in GRUB, one variable: the kernel

| entry | DTB | kernel |
|---|---|---|
| `fedora-glymur-gpucc1` | `glymur-a16-test64.dtb` | `7.1.0-glymur-edp1` — **before** the gdsc patch |
| `fedora-glymur-gdsc1` | `glymur-a16-test64.dtb` — **same** | `7.1.0-glymur-gdsc1` — **with** it |

Same device tree, different kernel. The suspect is **our own gdsc genpd-teardown patch**:
it modified `drivers/clk/qcom/gdsc.c`, which is **built-in and governs every Qualcomm power
domain on the SoC — including LPASS**. It landed in exactly the window where audio went bad.

⚠️ `initrd.img-7.1.0-glymur-edp1` predated the ADSP-firmware dracut fix and did **not**
contain `qcadsp8480.mbn`, which would have left the ADSP offline and produced a *false*
"no audio". It has been rebuilt (2026-07-27, now 58 MB, firmware verified inside; backup at
`.bak-pre-adspfw`), so the A/B is clean.

**Boot `fedora-glymur-gpucc1` and run the audio procedure.** Display works there (eDP is
enabled in test64 and the edp1 kernel has the HBR3 msm), so the normal desktop test applies.

- Audio works on gpucc1 ⇒ the regression is in the `edp1 → gdsc1` kernel bump, and the gdsc
  patch is the prime suspect. Confirm by diffing the two source trees before blaming it.
- Audio fails identically ⇒ the kernel is exonerated too, and the remaining candidates are
  the firmware/topology payload and the initramfs.

## ★★★ CONFIRMED A/B (2026-07-27, Jesse): audio WORKS on the pre-gdsc kernel

| entry | DTB | kernel | audio |
|---|---|---|---|
| `fedora-glymur-gpucc1` | `test64` | `7.1.0-glymur-edp1` | **WORKS** |
| `fedora-glymur-gdsc1` / test69-71 | same `test64` / later | `7.1.0-glymur-gdsc1` | **silent** |

Jesse: *"audio is working. It didn't work on boot which is a minor regression."* — i.e. the
boot-time failure is present on **both** kernels; what the newer kernel loses is the
**recovery**.

Confirmed on the working kernel: the same two boot timeouts appear —
`CMD timeout [1001021]` @10.21 s and `[1001002]` @17.89 s — yet audio plays afterwards. So
those timeouts are **not** the regression. They are the older, separate boot-time bug.

### Where the difference is — narrowed by checksum, not by guesswork

| compared | result |
|---|---|
| all 7 audio/LPASS/ADSP **DT nodes** (test55 vs test69) | identical |
| `sound` node (test47 vs test69) | identical |
| audio module **`srcversion`** (q6apm-dai, q6apm-lpass-dais, q6prm, apr, snd-soc-x1e80100, snd-soc-wsa884x, snd-soc-lpass-wsa-macro, soundwire-qcom) — edp1 vs gdsc1 | **all identical source** |
| `vmlinuz` image | **differs** (`d35901d5…` vs `4a375cc6…`, same size) |

No audio driver source changed. The difference is **built-in code**, and the only built-in
commit between the two builds is **`df6099b2f clk: qcom: gdsc: remove genpds on unregister
and error paths`** — our own patch. Everything else in that window
(`b4c376a41`, `daf0e0183`, `a6ffbf708`, the phy/msm work) builds as modules.

⚠️ **This does not prove the gdsc patch is the cause** — it proves it is the only identified
candidate. Verify before blaming it.

### Why that patch exists (it is NOT needed by the daily driver)

`gdsc_init()` calls `pm_genpd_init()` (adds to the global `gpd_list`) but nothing called
`pm_genpd_remove()`, so `rmmod`-ing any qcom clock controller left `gpd_list` pointing into
freed module memory — the next `modprobe` threw `list_add corruption` and reading
`pm_genpd_summary` oopsed. That only bites when a **clock controller is unloaded**, which we
did constantly during gpucc bring-up and the daily driver never does. **If it costs audio,
reverting it from the daily kernel costs nothing but gpucc hot-swap convenience.**

The patch touches only `gdsc_unregister()` and `gdsc_register()`'s error paths, so it should
be inert on a clean boot. If it is the cause, then **some GDSC provider is hitting a
`gdsc_register()` error path at boot**, where the old code leaked the domains and carried on
and ours now removes them.

### ⏭️ The decisive test — reference already captured

Working-kernel reference saved in `logs/`:
- `genpd-edp1-WORKING-AUDIO-2026-07-27.txt` — **45 power domains**, dmesg clean of any
  gdsc/genpd/power-domain error
- `clk-edp1-WORKING-AUDIO-playing-2026-07-27.txt` — LPASS clock tree during audible playback
  (`LPASS_HW_MACRO` en=4, `LPASS_CLK_ID_WSA_CORE_TX_MCLK` en=3, `wsa2-mclk` en=1, …)

**Boot the gdsc1 kernel (test71 or `fedora-glymur-gdsc1`) and capture the same two:**

```bash
sudo cat /sys/kernel/debug/pm_genpd/pm_genpd_summary | grep -cE '^[a-z_0-9]+ +(on|off)'   # 45?
sudo dmesg | grep -aiE "gdsc|genpd|power domain"                                          # errors?
```

- **Fewer than 45 domains** ⇒ the patch removed domains that the old code kept, and the
  missing names identify the provider that fails registration. Root cause found.
- **45 domains and clean dmesg** ⇒ the patch is inert here, and the built-in delta is
  something else in the image — diff the two builds' `.config` and object lists next.

⛔ Until this is settled, **do not propose `df6099b2f` upstream** and do not treat it as a
finished fix. It is currently a suspect in a real audio regression.

## ⛔ 2026-07-27 — THE gdsc PATCH IS EXONERATED (measured, not argued)

Booted the gdsc1 kernel and compared against the working-kernel reference:

| | edp1 (audio works) | gdsc1 (no audio) |
|---|---|---|
| genpd domain count | **45** | **45** |
| gdsc / genpd / power-domain errors in dmesg | none | **none** |

**The patch removed no domains and no provider hits an error path.** The
"`gdsc_register()` error path deletes domains that used to leak" mechanism is dead.
`df6099b2f` is not implicated by any measurement — Jesse's instinct that it was a wild
goose chase was right.

⚠️ **And the A/B that pointed there was not single-variable after all.** The working boot
was **edp1 kernel + test64 DTB**; every failing boot tonight was **gdsc1 kernel + test69/70/71
DTB**. Two variables. The DT *audio nodes* are identical across those DTBs (proven above),
but the DTBs differ in many other ways (lid switch, UCSI role-switch deletion, ramoops,
gpio-reserved-ranges, eDP HPD), any of which could matter indirectly.

### ⏭️ Baseline pair created to settle it — one variable, the kernel

| entry | DTB | kernel |
|---|---|---|
| `fedora-glymur-baseline` (**new default**) | `glymur-a16-test71.dtb` | `7.1.0-glymur-gdsc1` |
| `fedora-glymur-baseline-edp1k` | `glymur-a16-test71.dtb` — **same** | `7.1.0-glymur-edp1` |

Identical devicetree, cmdline and initrd policy; only the kernel and its initrd differ.
(The edp1 initrd was rebuilt earlier today to include the ADSP firmware, so it is a fair
comparison.) GRUB backup: `/boot/grub/grub.cfg.bak-pre-baseline`.

**Boot `baseline-edp1k` and run the audio procedure:**

- **Audio works** ⇒ the variable really is the kernel image, and since gdsc is exonerated by
  the genpd measurement, the next step is diffing the two builds' `.config` and built-in
  object lists — not assuming a culprit.
- **Audio fails** ⇒ the kernel is exonerated too and the variable is the **DTB lineage**
  (test64 → test69/71), despite the audio nodes being byte-identical. Then diff test64 vs
  test71 *wholesale*, not just the audio subtree.

Either way this is the first genuinely single-variable audio test of the session.

## ⛔⛔ 2026-07-27 (end of session) — THE KNOWN-GOOD IS NOT REPRODUCIBLE. All config A/Bs are void.

Jesse re-booted the **exact** working entry (`gpucc1`, unmodified) plus `ab-oldcmd`,
`ab-t64-newcmd` and `clean2`. **All silent.** The single working boot earlier in the evening
could not be reproduced on the same configuration.

⇒ **Every conclusion of the form "X is the variable" from this session is unsound**, because
they were all measured against that one lucky boot: kernel-is-the-variable,
DTB-is-the-variable, cmdline-is-the-variable. Do not carry any of them forward.
(`clean2` having no card at all is separate and expected — its initrd was never rebuilt with
the ADSP firmware, so the ADSP never boots there.)

### What IS solidly eliminated (each measured, not argued)

| candidate | how it was killed |
|---|---|
| audio device-tree nodes | 7 nodes byte-identical test55 vs test69; `sound` identical to test47 |
| msm | GRAPH_START fails identically with `modprobe.blacklist=msm` |
| DMIC2/3 routing | test71 removed them, failure unchanged |
| mixer / route service | all controls verified `on`, re-applied, no change |
| PipeWire default sink | correct sink, correct 4ch, idle |
| gdsc genpd patch | **45 genpd domains on both kernels**, zero gdsc/genpd errors |
| the kernel | edp1 kernel fails too (`baseline-edp1k`) |
| `qcom_pd_mapper` | v7.1 **does** have `qcom,glymur` → `glymur_domains` (line 583) |
| PD naming | `adsp_audio_pd` = domain `msm/adsp/audio_pd` **with service `avs/audio` inside**, so one PDR indication covers both names our node requires |
| `qcom,intents` / `protection-domain` | ours `<0x200 0x14>` = upstream `<512 20>`; both services carry the same protection-domain pair |

### ★ The leading hypothesis is now Jesse's: the ADSP is WEDGED at hardware level

Every DSP command times out — `GET_SPF_STATE`, `GRAPH_START`, `SHARED_MEM_UNMAP` — on every
boot, **deterministic to the microsecond across separate boots and across different kernels
and DTBs**. Nothing in software could produce that invariance while everything above it
differs.

The project has already documented this exact failure class, in
`kernel-stability-and-battery-fix.md`:

> Kernel `7.1.0-glymur-full+` is unstable — it **wedges the ADSP/SOCCP co-processor** and
> **recovery costs 10–15 min unplugged draining**.

A wedged ADSP survives warm reboot and even a normal shutdown, which is exactly what we saw.
It also explains why the one success came *before* tonight's rapid reboot cycling and
nothing after it worked.

**Procedure before any further audio test: power off, unplug, drain 10–15 minutes, then cold
boot straight to `baseline` and test audio BEFORE any other reboot.** Rapid reboot
succession is the suspected trigger and must be avoided while testing.

- Audio returns after the drain ⇒ wedge confirmed; the real question becomes what wedges it.
- Still dead after a proper drain ⇒ wedge theory out, and the ADSP firmware payload is the
  one thing never varied.

### Reference captured for the next comparison (no laptop needed)

`logs/srcversion-cleanplus-AUDIO-WORKED.txt` — audio module **source** hashes from
`modules-7.1.0-glymur-clean+.tar.gz` on the LoA drive, i.e. the era audio was flawless.
Compare with `modinfo -F srcversion` on `/lib/modules/7.1.0-glymur-gdsc1`; any mismatch is a
genuine audio-driver source change between then and now. (edp1 vs gdsc1 already matched, so
this reaches further back.)

⚠️ **`7.1.0-glymur-full-plus-modules.zip` on the drive is NOT a safe base** — it is the
`-full+` build that the note above identifies as the ADSP-wedging kernel. The correct
archive for the clean lineage is `modules-7.1.0-glymur-clean+.tar.gz`.

## ★★ 2026-07-28 — TOPOLOGY PROVENANCE: ours is X1E-derived, and it is the one thing never varied

From `a16dump/tplg_pick_out.txt` (the firmware-dump analysis):

```
=== current glymur tplg = which x1e one (size match) ===
31892
```

**31892 bytes is exactly `GLYMUR-A16-tplg.bin.romulus.bak` on the box.** So the lineage is:

    X1E80100-Romulus (a MICROSOFT SURFACE topology)  ->  hand-modified  ->  current 29496-byte file

and `tplg-public-source.md` already records that the working 29 KB file "matches NO public
board file — it was hand-derived". Note also that Romulus is a **two-speaker** board in the
UCM lists while the A16 is four-speaker.

⇒ **Our DSP graphs were authored for X1E80100 silicon and its ADSP firmware, and we feed them
to glymur's `qcadsp8480`.** A topology whose graphs that firmware will not accept produces
exactly our symptom: card enumerates, DAPM builds, then `GRAPH_START` is refused. Every other
component has now been eliminated; **the topology has never been varied.**

### Two candidate replacements, both built for the right silicon

| candidate | where | note |
|---|---|---|
| `firmware/tplg/GLYMUR-CRD.tplg` (11 320 B) | **in this repo** | glymur-native, built from Linaro's public BSD-3 `GLYMUR-CRD.m4` |
| `SM8750-MTP-tplg.bin.zst` / `SM8750-QRD-tplg.bin.zst` | linux-firmware, already on the box | glymur's audio/display IP is **SM8750-derived** |

### The test — no reboot, fully reversible, objective

UCM is tuned to the current layout, so the *desktop* path may misbehave with a different
topology — irrelevant, because `speaker-test` plus `dmesg` is the oracle now.

```bash
sudo cp /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin{,.pre-crd.bak}
sudo cp <candidate> /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin
echo sound | sudo tee /sys/bus/platform/drivers/snd-x1e80100/unbind
echo sound | sudo tee /sys/bus/platform/drivers/snd-x1e80100/bind
sudo dmesg | grep -aE "tplg|CMD timeout|DSP returned"
```

- `GRAPH_START` **succeeds** ⇒ the topology was the bug all along.
- Fails identically ⇒ topology eliminated too, and the ADSP firmware payload is all that is
  left.

⚠️ Restore the 29 KB file afterwards either way; the UCM profile and `glymur-audio-route.sh`
are tuned to it. Recovery if PipeWire loses the sink is in `tplg-public-source.md`.

---

# ★★★ 2026-07-29 — ROOT CAUSE OF THE "SOMETIMES NO AUDIO": a system↔user ordering race

**This is the one that explains weeks of "audio is intermittent".** It is not the ADSP
firmware, not the topology, and not the DMIC routing. It is a **missing ordering guarantee
between a system unit and a user unit**, and it was being won by luck.

## The evidence — two boots, same DTB, same kernel, opposite outcome

Both boots are `7.2.0-rc3-konrad1` + `glymur-a16-merged-gpu.dtb`, identical cmdline
(`blacklist=efi_pstore`), GMU loaded. Only the *timing* differs:

| milestone | boot with WORKING audio | boot with NO audio |
|---|---|---|
| `adsp is now up` | 1.765 s | 1.700 s |
| `CMD timeout for [1001021]` | 9.697 s | 10.210 s |
| `sound.target` reached | 9.846 s | 10.365 s |
| **`glymur-audio-route` ran** | **20.395 → 20.485 s** | 16.585 → **18.464 s** |
| **`wireplumber` started** | **21.167 s** | **11.222 s** |
| **relative order** | **route → wireplumber** | **wireplumber → route** |
| `Failed to start APM port 105` | — | 18.413 s |
| `ASoC error (-110)` on `WSA_CODEC_DMA_RX_0` | — | 18.413 s |

⇒ **Every `-110` in the failing boot lands inside `glymur-audio-route`'s own window
(16.585 → 18.464 s).** When wireplumber starts first it claims the card and applies its own
UCM state; `glymur-audio-route`'s `amixer cset` calls then hit a card mid-negotiation, the DSP
refuses `GRAPH_START`, and the route never takes. Sink present, unmuted, correct 4ch format —
and silent.

**A ~10 s swing in user-session start time decides whether you have audio.** In the working
boot wireplumber came up at 21.2 s; in the failing boot at 11.2 s.

⚠️ Consistent with **Correction 3** above: the *first* DSP command
(`CMD timeout for [1001021]`) times out on **every** boot, working or not. That one is
harmless. The fatal one is the second round (`[1001002]` → `APM port 105` → `-110`), which
only appears when the route loses the race.

## Why the race existed

```
/etc/systemd/system/glymur-audio-route.service     (SYSTEM unit)
  After=sound.target multi-user.target             <- nothing about wireplumber

wireplumber.service                                (USER unit)
  start time depends on session/login timing
```

systemd cannot express ordering across the system/user manager boundary directly, so there was
never any guarantee. It happened to work for weeks.

Worse, the existing canary was blind to it: `glymur-audio-wait` exited as soon as a **sink
existed** (`sink present (attempt 1)`) and never checked whether the DSP route was actually
established. **"Sink present" is not "audio works."**

## The fix — two layers, both installed

Mirrored in the repo under [`tweaks/`](../tweaks/); paths below are the live ones.

**Layer 1 — apply the route *after* wireplumber settles.**
`/usr/local/bin/glymur-audio-wait` (run by the user unit
`/usr/lib/systemd/user/glymur-audio-wait.service`, which is already correctly
`After=wireplumber.service`) now calls `/usr/local/bin/glymur-audio-route.sh` once the sink
appears. The route script is idempotent — only `amixer cset` calls — and the session user has
`rw` on `/dev/snd/controlC0` via the logind ACL, so **this needs no privileges**.

**Layer 2 — stop wireplumber starting before the route (belt and braces).**

```
/etc/systemd/user/glymur-audio-route-wait.service          (oneshot)
   ExecStart=/usr/local/bin/glymur-wait-for-audio-route

/etc/systemd/user/wireplumber.service.d/10-glymur-audio-route.conf
   [Unit]
   Wants=glymur-audio-route-wait.service
   After=glymur-audio-route-wait.service
```

`glymur-wait-for-audio-route` polls `systemctl is-active glymur-audio-route` for at most
**30 s** and **always exits 0**. That bound is deliberate: if the system route unit never
becomes active we must not wedge the login session — it degrades to the old behaviour, and
Layer 1 still repairs the route afterwards.

⚠️ Both live in **`/etc/systemd/user/`**, not `~/.config/systemd/user/`, so they are
machine-wide and survive a home-directory reset. Do not install a second copy under `~` — one
source of truth.

## Verified

```
19:30:26  glymur-audio-route-wait: Starting
19:30:26  glymur-wait-for-audio-route: route unit active, continuing
19:30:26  glymur-audio-route-wait: Finished
19:30:26  glymur-audio-wait: Starting
19:30:27  glymur-audio-wait: sink present (attempt 1)
19:30:27  glymur-audio-wait: (re)applying AudioReach route
19:30:27  glymur-audio-wait: route applied
19:30:27  glymur-audio-wait: Finished
```

All three units `Result=success`, **zero new kernel audio errors**, sink
`s16le 4ch 48000Hz`.

## ✅ VALIDATED across four boots (2026-07-29)

Journals for six boots were exported and diffed. The correlation is perfect, with no
exceptions:

| boot | `glymur-audio-route` | `wireplumber` started | order | `ASoC error (-110)` | audio |
|---|---|---|---|---|---|
| -3 | 20 s → 20 s | 21 s | **route first** | none | ✅ worked |
| -2 | 16 s → 17 s | **10 s** | wireplumber first | **yes @17 s** | ✗ silent |
| -1 | 16 s → 18 s | **11 s** | wireplumber first | **yes @18 s** | ✗ silent |
| **0** (fix active) | 10 s → **16 s** | **16 s** | **route first** | none | ✅ works |
| cold boot (fix active) | — | — | route first | **0 errors** | ✅ works |

**The causal evidence is boot 0:** wireplumber's start moved from ~11 s to **16 s — exactly
when the route finished.** That is `glymur-audio-route-wait` holding it back, and the `-110`
errors disappear with it. Confirmed again on a subsequent cold boot: `0` occurrences of
`ASoC error (-110)`, route applied, sink healthy.

⇒ **Root cause and fix are both confirmed.** Audio was never intermittent in the hardware
sense — it was a coin-flip on user-session start time.

## Manual recovery, if it ever bites again

```bash
sudo systemctl restart glymur-audio-route     # re-establish the route
# or, as the user:
/usr/local/bin/glymur-audio-route.sh
```

Both are idempotent. `pactl set-card-profile alsa_card.platform-sound off` then `on` also
works (that is what toggling the card in the desktop was doing all along).

## Not in scope, deliberately

`remoteproc1` (**cdsp**) is `offline` — `qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn` fails
`-2` at t+1.2 s because the initramfs does not carry CDSP firmware (same shape as the ADSP
`install_items+=` fix). **This is a deliberate deferral, not a defect**: the priority was a
working main laptop. CDSP mapping belongs with the next phase — camera RE, peripherals
(including HDMI validation), hibernate, and CPU/GPU timing and scheduling work.
