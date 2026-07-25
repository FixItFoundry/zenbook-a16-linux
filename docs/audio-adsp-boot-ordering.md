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
