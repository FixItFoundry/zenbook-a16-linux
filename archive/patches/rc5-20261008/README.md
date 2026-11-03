# RC5 audiopm1 source stack

The complete 59-patch stack reproduces the source of
`7.3.0-rc5-ZenbookA16-20261008-rc5-audiopm1+`, promoted as a working audio bringup
baseline on October 12. Apply `series` in order to Linux v7.3-rc5
`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`. The resulting tree must be
`14fd463c06510c760dde22ef215fcbd0bff9a898`.

| Patches | Provenance and role |
|---|---|
| 1–28 | Byte-identical exports from the retained [October 2 stack](../rc5-20261002/README.md), ending at tree `a3327a6d526503774e01b3bb15841883da87a180`. |
| 29 | Original snapshot commit `9fda9db11b16789febc8f7e0694f9fc8c7d2a107`, tree `c43c04bf7e4fafae9ad18a7b92d8f8f063688347`. Aggregated camera/CSI PHY, DP, I2C, QMP and SoundWire work already present in the tested source. This checkpoint is not a single upstream submission. |
| 30–50 | Preserved GPU, PCIe, ath12k and PMIC-glink backports plus the local bounded QMI allocation fix (45). Author and available source/review trailers remain in each mail patch. |
| 51–58 | Local RPMh/GMU error and lifetime repairs, EC fan-profile opt-in, SoundWire/I2C ownership fixes, DP return-value correction and GPI retirement repair. Ends at repair1 tree `e762c89d3e04f70327ae32ee2eb9f7cf11858dbe`. |
| 59 | Exact 19-line audiopm1 delta: a board-scoped DT opt-in and `pm_runtime_forbid()` keep both speaker controllers active. Exported into a commit without changing the tested source. |

`commits.txt` records the exported commit identities. After snapshot 29, commits
come from the reconstructed private repair history ending at
`a40530c981d416781dc6330463ff6653a4da73f3`; they need not be ancestors of the
public Linux base. The snapshot's tree was checked against that reconstructed
history, and full ordered replay establishes the final source identity.

Patch 59 deliberately retains its test-only comments. It prevents controller
autosuspend on this board; it neither repairs an already detached slave nor
proves why detachment happened. The earlier RC3 `audio-ecpm1` workaround was
omitted from the October 2 stack; this new opt-in is explicit and separate from
the retained repair fixes. Do not treat this stack as an upstream-ready series
or camera, USB1, suspend, battery or long-duration stability acceptance.

Use the [build package and verifier](../../kernel/rc5-20261008/README.md).
The [October 12 build record](../../docs/build-20261012.md) separates source replay,
installed artifacts, live attachment, physical audio and remaining gates.
