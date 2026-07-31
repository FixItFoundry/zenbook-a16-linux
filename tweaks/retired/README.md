# Retired tweaks

Things that were installed on loazen and have since been removed. Kept so they
can be restored, and so the reason for retiring them is not lost.

## `glymur-thermal-guard.service` + `glymur-thermal-guard.sh` — retired 2026-07-31

An interim userspace CPU throttle: a 2-second poll that clamped
`scaling_max_freq` in four steps, keyed on the hottest of all 102 thermal zones
(step up at 86 °C and 94 °C, step down after 4 consecutive samples below 76 °C).

**It never once fired — zero level changes across every boot it ever ran.**
For almost all of that time it *could* not: it wrote to
`/sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq`, which did not exist
because `scmi-cpufreq` was failing to probe with `-110`, so it logged that
failure twice a second and did nothing else.

When the `arm,no-completion-irq` fix landed on 2026-07-31 and cpufreq came up,
that path became real and the guard became genuinely capable of throttling for
the first time. Retired rather than kept, because:

- its trigger is the max over **every** sensor on the SoC, including ones with
  no relation to CPU load — a crude signal;
- it now competes with the real governor (`schedutil`, via power-profiles-daemon);
- the kernel's own `cpufreq-cooling` devices exist as of that fix, so the
  correct mechanism is `cooling-maps` in the DT, not a shell loop;
- and it was adopted at a time when it demonstrably could not act, so it had
  never been evaluated on its merits.

**What protects the CPU now:** 101 critical trip points, and the fan, which is
EC/BIOS-autonomous and spins up without Linux involvement. There is no
Linux-side *actuation* until `cooling-maps` are written — the `cpufreq-cpu0/6/12`
cooling devices exist but no thermal zone binds them yet. That is the next
thermal task.

Restore with:

```
sudo cp tweaks/retired/glymur-thermal-guard.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/glymur-thermal-guard.sh
sudo cp tweaks/retired/glymur-thermal-guard.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now glymur-thermal-guard
```


## `asus-kbd-init.py` + `asus-kbd-init.service` — retired 2026-07-31

A userspace hidraw script that sent the ASUS handshake and forced a fixed keyboard-backlight
level, run at boot and again from `/usr/lib/systemd/system-sleep/` after every resume.

Superseded by the kernel LED: the patched `hid-asus` registers
`/sys/class/leds/asus::kbd_backlight` with four levels, and `asus_resume()` restores its
state on wake.

**Retired rather than merely left alone**, because both would have written the backlight on
every resume in unspecified order, leaving the sysfs LED value disagreeing with the actual
hardware. Restore with:

```
sudo cp tweaks/retired/asus-kbd-init.py /usr/local/bin/
sudo cp tweaks/retired/asus-kbd-init.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now asus-kbd-init
```
