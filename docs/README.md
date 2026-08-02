# Documentation

Four documents. If you are looking for something else, it was working detail and now lives in
the maintainer's untracked `internal/` archive rather than in this repo.

| Doc | What it answers |
|---|---|
| [`hardware.md`](hardware.md) | **What each component is, how it connects, and where it stands.** Start here. |
| [`modifications.md`](modifications.md) | **Every device-tree and kernel change, and why.** The delta vs upstream. |
| [`../README.md`](../README.md) | Project overview — what this machine is, what works, how to boot it |
| [`../LOCAL-TWEAKS.md`](../LOCAL-TWEAKS.md) | Firmware extraction and local system configuration |

## Component deep-dives

Kept because they document a protocol or trap that cannot be re-derived cheaply:

- [`fan-ec-interface.md`](fan-ec-interface.md) — the EC on i2c-9: addresses, decoded commands,
  and why nothing writes to it
- [`power-and-thermal.md`](power-and-thermal.md) — the SCMI/cpufreq root cause in full, plus
  the thermal chain
- [`audio-adsp-boot-ordering.md`](audio-adsp-boot-ordering.md) — the ADSP boot race, which is
  what "audio is broken" almost always means
- [`usb-c-ucsi-dp-altmode.md`](usb-c-ucsi-dp-altmode.md) — the Type-C pipeline and why USB4 is
  still out of reach

## Contributing

See [`../CONTRIBUTING.md`](../CONTRIBUTING.md). Credit for adopted upstream work goes in
[`../UPSTREAM-CREDITS.md`](../UPSTREAM-CREDITS.md), in the same change that adopts it.

> This project was developed with heavy AI assistance and the maintainer is not a kernel
> developer by trade. Treat findings as field notes and verify before relying on them.
