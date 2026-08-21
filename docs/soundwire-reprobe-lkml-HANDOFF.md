# SoundWire Reprobe Fix — LKML Submission Handoff

## Summary of Patch

`patches/next-20260817/0013-soundwire-qcom-reprobe-unattached-slaves-directly-in.patch` (also in cumulative `patches/0002-soundwire-qcom-...patch`).

In `drivers/soundwire/qcom.c` (`qcom_swrm_probe()`): when the enumeration retry loop exhausts with slaves still unattached at `dev_num 0`, invoke `device_reprobe()` directly on each unattached slave rather than only logging a timeout.

## Problem Context

A SoundWire slave remaining at `dev_num 0` is typically caused by its driver returning `-EPROBE_DEFER`. On Qualcomm platforms, WSA884x codec `reset-gpios` resolve through the generic reset-gpio bridge (`drivers/reset/core.c`), which requires `lpass_tlmm` GPIO registration. Clocks for `lpass_tlmm` are in turn gated behind ADSP APM initialization.

Bus-level rescan cannot attach a slave held electrically in reset. Re-running the slave's `.probe()` normally relies on unrelated driver binding events (`driver_bound()` → `driver_deferred_probe_trigger()`), causing non-deterministic attach delays (ranging from <1ms to >15s on hardware tests).

Non-viable alternatives tested:
- **Extended enum timeout (`qcom,enum-timeout-ms`)**: Delays sibling controller initialization without resolving underlying deferred probe.
- **`PROBE_PREFER_ASYNCHRONOUS`**: Introduces register contention and FIFO read underflow errors across concurrent controller probes.

`device_reprobe()` (`EXPORT_SYMBOL_GPL` in `drivers/base/bus.c`) explicitly retriggers probe on unattached slaves without requiring core subsystem modifications.

## Submission Checklist

1. **Subsystem details (`MAINTAINERS`)**:
   ```
   SOUNDWIRE SUBSYSTEM
   M: Vinod Koul <vkoul@kernel.org>
   M: Bard Liao <yung-chuan.liao@linux.intel.com>
   R: Pierre-Louis Bossart <pierre-louis.bossart@linux.dev>
   L: linux-sound@vger.kernel.org
   T: git git://git.kernel.org/pub/scm/linux/kernel/git/vkoul/soundwire.git
   ```
2. **Additional context**: Note `drivers/reset/core.c` reset-gpio deferred probe behavior as background context.
3. **Sign-off**: Verify valid `Signed-off-by:` developer certificate of origin.

## Hardware Verification

Deterministic recovery time measured from initial `-EPROBE_DEFER` to slave attachment: ~1.6s. Verified across `qcom.c`, `wsa884x.c`, and `pinctrl-lpass-lpi.c`.
