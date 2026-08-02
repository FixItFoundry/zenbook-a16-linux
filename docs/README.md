# Documentation index

Curated docs for the Zenbook A16 (glymur / sm8750) Linux bring-up.

## Start here

- [`../README.md`](../README.md) — project overview, what works / what doesn't
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — how to help (validation + patches)
- [`THINGS_TRIED.md`](THINGS_TRIED.md) — dead-ends, so you don't repeat them
- [`STATUS_2026-07-15.md`](STATUS_2026-07-15.md) — most recent full status writeup

## reverse-engineering

- [`HARDWARE_MAP.md`](HARDWARE_MAP.md) — buses, addresses, peripherals
- [`DTB_CHANGELOG.md`](DTB_CHANGELOG.md) — every test DTB, its delta, result, and lesson (test1 → test59)
- [`DT_BRINGUP_NOTES.md`](DT_BRINGUP_NOTES.md) — device-tree bring-up notes

## Display / eDP

- [`display-bringup-findings.md`](display-bringup-findings.md) — DPU/eDP analysis
- [`edp-enable-findings.md`](edp-enable-findings.md), [`edp-enable-plan.md`](edp-enable-plan.md)

## GPU reverse-engineering (`gpu-re/`)

- [`gpu-re/gpu-investigation-summary.md`](gpu-re/gpu-investigation-summary.md) — the headline: `gpucc` is the blocker
- [`gpu-re/gpu-smmu-routing-from-woa-acpi.md`](gpu-re/gpu-smmu-routing-from-woa-acpi.md) — authoritative StreamIDs/bases from the WoA ACPI dump
- [`gpu-re/gpucc-clock-registers.md`](gpu-re/gpucc-clock-registers.md) — candidate clock-controller registers from Ghidra
- [`gpu-re/gpu-reverse-engineering-plan.md`](gpu-re/gpu-reverse-engineering-plan.md) — the RE approach
- [`gpu-re/gunyah-dpu-path-scope.md`](gpu-re/gunyah-dpu-path-scope.md), [`gpu-re/pkvm-smmu-findings.md`](gpu-re/pkvm-smmu-findings.md)

## Analysis logs (`analysis/`)

Chronological engineering transcripts (G01–G18) covering battery, audio, SMMU/VMID, and the
netconsole crash-capture tooling. Raw and unedited; useful for tracing _why_ decisions were made.

> Note: these docs are assembled from the maintainer's working project folder via `assemble.sh`.
> If a link 404s, that source file wasn't copied in — please open an issue.
