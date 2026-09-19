# RC3 integration — 2026-09-19

These 24 ordered patches reproduce the source of the promoted RC3 build.
Apply only to Linux v7.3-rc3 (`fd73f4a6659897191fa0d40695fe370925dd3780`).
`series` defines order; `commits.txt` records the original integration commits.
Author and provenance trailers are retained from the source worktree.

See [build instructions](../../kernel/rc3-20260919/README.md) and
[current validation limits](../../docs/current-build.md).

This is an integration snapshot, not an upstream submission series. In
particular, patch11 carries experimental SoundWire recovery, patch14 bypasses
PCI suspend behavior, and patches18–24 preserve board compatibility. Their
inclusion does not establish correctness or upstream readiness. Camera patches
and the separate CDSP initramfs experiment are excluded.

The manifest verifies source-tree equality, not byte-identical binaries:
compiler versions, generated signing keys and build timestamps affect outputs.
