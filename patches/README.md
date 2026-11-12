# Zenbook A16 Kernel Patch Queues

Active patch stacks are split into two maintained tracks (`stable` and `rc`), while historical bringup snapshots live under [`../archive/patches/`](../archive/patches/).

| Directory | Track | Base | Patches | Replayed Source Tree |
|---|---|---|---:|---|
| [`stable/`](stable/README.md) | **Stable Release Track** (`kernel/stable`) | Linux `v7.3` (`c03c1a14507dfaf8b856c2608f9ac216021fc222`) | 146 | `ca55d57edf4c0c2ade677f0b5336e69ab8645c3a` |
| [`rc/`](rc/README.md) | **RC / Upstream Development Track** (`kernel/rc`) | Linux `next-20261103` (`d6bcfc94eb4da6e089c5473970cd96727292fd97`, `v7.4-rc1`) | 103 | `e52a4f3ca29b6348ecaf84a4f349bde8d0cc1fb7` |
| [`../archive/patches/`](../archive/patches/) | Retired bringup snapshots (`next-202608*`, `rc3-*`, `rc5-20261002`, `rc5-20261008`, `rc5-20261031`, `standalone/`) | Historical | — | Retained for provenance |

## Verifying Both Tracks

Run the hardware-free source replay against any Linux Git repository containing `v7.3` and `next-20261103`:

```sh
python3 scripts/ci.py --replay-only --track both --linux-git /path/to/linux.git
```

Each track preserves original upstream `From:`, `Date:`, `Signed-off-by:`, and `Link:` trailers. See [`../UPSTREAM-CREDITS.md`](../UPSTREAM-CREDITS.md) for full provenance.
