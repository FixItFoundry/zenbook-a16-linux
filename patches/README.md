# Zenbook A16 Kernel Patch Queues

Active patch stacks are split into two maintained tracks (`stable` and `rc`), while historical bringup snapshots live under [`../archive/patches/`](../archive/patches/).

| Directory | Track | Base | Patches | Replayed Source Tree |
|---|---|---|---:|---|
| [`stable/`](stable/README.md) | **Stable Release Track** (`kernel/stable`) | Linux `v7.3` (`c03c1a14507dfaf8b856c2608f9ac216021fc222`) | 143 | `11f818cf609ff60e6f826f47e757f939b5442adc` |
| [`rc/`](rc/README.md) | **RC / Upstream Development Track** (`kernel/rc`) | Linux `v7.3-rc5` (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`) | 115 (64 + 40 + 10 + 1) | `b3ae7b3a8a4c74930dfeb905c6471c16da0f69f0` |
| [`../archive/patches/`](../archive/patches/) | Retired bringup snapshots (`next-202608*`, `rc3-*`, `rc5-20261002`, `rc5-20261008`, `standalone/`) | Historical | — | Retained for provenance |

## Verifying Both Tracks

Run the hardware-free source replay against any Linux Git repository containing `v7.3` and `v7.3-rc5`:

```sh
python3 scripts/ci.py --replay-only --track both --linux-git /path/to/linux.git
```

Each track preserves original upstream `From:`, `Date:`, `Signed-off-by:`, and `Link:` trailers. See [`../UPSTREAM-CREDITS.md`](../UPSTREAM-CREDITS.md) for full provenance.
