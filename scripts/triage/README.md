# Diagnostic tools

- `check-boot-housekeeping.sh`: read-only RC3 session gate. Requires the mixer to
  have executed successfully this boot and both portals to be active. It does
  not certify physical speakers or historical link continuity.
- `audio-cycle-watch.py OUTPUT_DIR`: at most 30 minutes of journal/PipeWire events
  and slave-state samples; 32 MiB per event stream. No playback or audio recording.
  Startup failures terminate acquired children and record their reason.
- `lockup-capture.sh`: 30-second system counters. Three 8 MiB rotated segments plus
  the active segment per boot (one-sample size overshoot possible). A 256 MiB
  total collector-directory budget stops capture with status 75; old boot folders
  are not automatically deleted. Archive evidence and explicitly restart after
  reaching the limit. One data sync per sample preserves crash evidence.

The lockup collector retains initial/static evidence, avoids repeated per-IRQ
arrays in `/proc/stat`, and uses shell reads for cpufreq fields. `iw link` is
bounded to 5 seconds but actively queries firmware statistics: account for that
when interpreting Wi-Fi timing. Hard-coded Wi-Fi interface/PCI identities are
host-specific and must be audited before use on another machine.

Install the persistent collector as root-owned files, not a root service running
mutable checkout code:

```sh
sudo install -d /usr/local/libexec/zenbook-a16
sudo install -m755 scripts/triage/lockup-capture.sh scripts/triage/capture-storage.sh /usr/local/libexec/zenbook-a16/
sudo install -m644 scripts/triage/zenbook-lockup-triage.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now zenbook-lockup-triage.service
# For an already-running collector, explicitly restart to load the new scripts.
```

Do not launch the audio capture with sudo: its user journal must be the logged-in
desktop user's. Do not use SoundWire register debugfs dumps during a baseline
test; earlier reads disrupted this hardware.

Hardware-free tests: `python3 -m unittest discover -s scripts/triage -v`.
