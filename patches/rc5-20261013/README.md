# RC5 soc2 source stack

Apply these 64 patches in `series` order to Linux v7.3-rc5
`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`. The result is tree
`e3af70b5403334c7d762fdb00b0a7cdfbb5a362c`, matching tested soc2 source commit
`80849361fb38a8adc11dd66f1d6856260d98e01b`.

| Patches | Contents |
|---|---|
| 1–59 | Byte-identical [audiopm1 exports](../rc5-20261008/README.md), including the two-controller keep-active audio workaround. |
| 60 | Local EFI, GMU, DP, ath12k, PCIe, battery, remoteproc, RTC, RPMh, SoundWire, USB and QMP error/cleanup fixes. |
| 61 | Hibernation configuration fragment; hibernation remains unvalidated. |
| 62 | Bluetooth firmware handling, GPI DMA, SoundWire and DP fixes. |
| 63 | QMP Type-C ownership and PMIC-glink/PS883x transition error handling. |
| 64 | GPI ring cleanup on failures before hardware commands. |

`commits.txt` preserves the exported identities. The first 59 patches end at the
same tree as soc2 parent `373e33ccb14beb7d3a5bbb7aad52b31a200b9c52`;
patches 60–64 retain the five subsequent commits and their authorship.

These include local aggregate commits, not an upstream-ready series. Use the
[build package](../../kernel/rc5-20261013/README.md); see [credits](../../UPSTREAM-CREDITS.md)
and [hardware acceptance limits](../../docs/current-build.md).
