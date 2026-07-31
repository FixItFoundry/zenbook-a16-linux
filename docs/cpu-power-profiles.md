# CPU power profiles on the Zenbook A16 — what the levers actually are

Written 2026-07-31, the day cpufreq started working. Everything here is measured on the
box, not inferred.

## First, a correction: there is no EPP on this platform

EPP — Energy Performance Preference — is an **x86 concept**. It is the HWP hint that
`intel_pstate` and `amd-pstate` expose as `energy_performance_preference`. It does not
exist on ARM, and it does not exist here: this machine runs `scaling_driver = scmi`, where
the kernel picks an explicit operating point and asks the CPUCP firmware for it.

The equivalent levers on this platform are:

| lever | where | what it does |
|---|---|---|
| `scaling_max_freq` | per policy | caps the top of the range — the main knob |
| `scaling_min_freq` | per policy | raises the floor; rarely worth touching here |
| `boost` | per policy + global | exposes the two boost bins on the performance clusters |
| governor | per policy | `schedutil` is the right default (see below) |
| Energy Model | firmware-supplied | EAS uses it for **placement**; no configuration needed |

## The clusters, as the kernel actually sees them

```
policy0   cpus 0-5    355.2 MHz - 3.6096 GHz   21 OPPs   capacity  619
policy6   cpus 6-11   355.2 MHz - 4.4544 GHz   21 OPPs   capacity 1024   + boost 4.5696 / 4.7232
policy12  cpus 12-17  355.2 MHz - 4.4544 GHz   21 OPPs   capacity 1024   + boost 4.5696 / 4.7232
```

⚠️ **`policy6` and `policy12` are identical.** Same `capacity-dmips-mhz`, same OPP table,
same boost bins, same energy model. They are two SCMI performance domains, **not** a
"performance" tier and a "prime" tier. Nothing should treat them differently, and the
profiles here do not.

The asymmetry that matters is 6 efficiency cores versus 12 performance cores, and it comes
straight out of Konrad's DT:

```
capacity-dmips-mhz = <1024>   x6    (cpus 0-5)
capacity-dmips-mhz = <1372>   x12   (cpus 6-17)
```

The kernel scales those by max frequency to get the runtime capacities:

```
E:  1024 * 3609600 = 3.696e9
P:  1372 * 4454400 = 6.111e9      ratio 0.6048  ->  0.6048 * 1024 = 619   ✓ matches
```

## Is there DT precedent? Does Konrad have this mapped?

**For the clustering: yes, and it is already correct.** Konrad's `glymur.dtsi` supplies
`capacity-dmips-mhz` for all 18 CPUs and wires each CPU to one of three
`power-domains = <&scmi_perf N>` domains. That is exactly what produces the 619/1024
asymmetry EAS needs. Nothing to add.

**For the power *profiles*: no, and there should not be.** Frequency caps per power profile
are not a device-tree concept at any level — DT describes the hardware, not policy. This
belongs in userspace, which is where it is implemented below.

**There is no X1E precedent to copy, because X1E does it a completely different way.**
Comparing the two SoC files in-tree:

| | `glymur.dtsi` (ours) | `hamoa.dtsi` (X1E) |
|---|---|---|
| `capacity-dmips-mhz` | 18 entries | **0** |
| `scmi_perf` domains | 3 | **0** |
| `opp-table` / `operating-points` | 36 refs | 78 refs |

X1E carries its OPP tables **in the device tree** and drives them through
`qcom-cpufreq-hw` (EPSS/OSM). Glymur has **no CPU OPP table in DT at all** — the operating
points, their power values and the whole Energy Model arrive from **SCMI firmware** at
runtime. That is why we get real µW power figures per OPP without any
`dynamic-power-coefficient` property (`glymur.dtsi` has zero of those, and does not need
any). Two different mechanisms; do not port assumptions between them.

## The Energy Model is the right basis for choosing caps

`/sys/kernel/debug/energy_model/cpuN/ps:<freq>/cost` is energy per unit of work, normalised
so it is comparable **across** clusters. Measured 2026-07-31:

| policy0 (E) | cost | | policy6/12 (P) | cost |
|---|---|---|---|---|
| 355.2 MHz | 1576 ⚠️ *inefficient* | | 355.2 MHz | 2017 |
| **902.4 MHz** | **1560** ← cheapest | | 883.2 MHz | 2022 |
| 1516.8 MHz | 1935 | | 1996.8 MHz | 2983 |
| 2073.6 MHz | 2422 | | 2400.0 MHz | 3392 |
| 2918.4 MHz | 3406 | | 3033.6 MHz | 4213 |
| 3225.6 MHz | 3922 | | 3628.8 MHz | 5411 |
| 3609.6 MHz | 4723 | | 4454.4 MHz | 7779 |
| | | | 4569.6 MHz | 8377 ⚠️ *inefficient* |
| | | | 4723.2 MHz | 8371 |

Two things fall out of this that are not obvious:

1. **Running the efficiency cores flat out is a loss on both axes.** policy0 at its 3.6096
   GHz ceiling costs **4723** per unit work — *more* than the performance cluster at 3.0336
   GHz (**4213**), which also finishes the work sooner. Capping the E-cores is the single
   best lever, and it is the opposite of the intuition that little cores are always cheaper.
2. **The kernel already flags two dominated operating points.** `355.2 MHz` on the E cluster
   and `4569.6 MHz` on the P clusters are marked `inefficient=1` — 4569.6 costs *more* than
   the higher 4723.2. cpufreq skips these automatically; nothing to do.

## The profiles

`/usr/local/bin/glymur-cpu-profile.sh` + three `tuned` profiles in
`/etc/tuned/profiles/glymur-{performance,balanced,powersave}`, wired into KDE's power slider
through `/etc/tuned/ppd.conf`.

| profile | policy0 | policy6/12 | boost | governor |
|---|---|---|---|---|
| **performance** | 3609600 (full) | 4723200 (boost) | on | schedutil |
| **balanced** | 2918400 | 3628800 | off | schedutil |
| **powersave** | 2073600 | 2400000 | off | schedutil |

Rationale:

- **performance** opens the two boost bins that ship **disabled** by default. This is where
  the ~4.7 GHz the SoC can actually reach lives.
  ⚠️ It deliberately overrides the inherited `governor=performance` from stock
  `throughput-performance` back to **schedutil**. Pinning every core at its ceiling while
  idle costs real battery for no gain in peak — `fast_switch` is active here (no `sugov`
  kthreads) with a 30 µs transition latency, so schedutil reaches the same peak on demand.
  Change `[cpu] governor=` in the profile if you want guaranteed pinned clocks.
- **balanced** caps each cluster at roughly **81% of its top frequency for ~70% of its
  energy per unit of work** — 3406/4723 on E, 5411/7779 on P. Symmetric treatment of two
  differently-shaped curves.
- **powersave** sits deep in the flat region — 51% and 44% of max cost respectively — while
  still leaving 18 cores at 2.0–2.4 GHz, which is far more than a browser or an editor needs.

Boost is set **before** `scaling_max_freq` on purpose: enabling boost is what raises
`cpuinfo_max_freq` to the top bin, and a max-freq write above the current ceiling is
silently clamped. This is why the caps are applied by a script rather than a tuned `[sysfs]`
block, which gives no ordering guarantee.

### Verify

```
/usr/local/bin/glymur-cpu-profile.sh status
tuned-adm active
busctl --system get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
       net.hadess.PowerProfiles ActiveProfile
```

## ✅ AC detection works — an earlier version of this doc said otherwise and was wrong

**Retracted 2026-07-31.** This section previously claimed AC detection was broken and would
"fight" the profiles. That was a stale claim inherited from `hardware-status.md` (dated
2026-07-24, *before* UCSI was fixed on 07-29) and repeated here without being re-checked.

Measured live while plugging the charger in:

```
qcom-battmgr-usb                      type=USB       online=1     <- the charger
ucsi-source-psy-pmic_glink.ucsi.02    type=USB       online=1     <- the port used
qcom-battmgr-bat                      status=Charging, energy_now rising ~35 W
qcom-battmgr-ac                       type=Mains     online=0
upower -d                             on-battery: no
```

**`qcom-battmgr-ac/online = 0` is correct, not a fault.** Its `type` is `Mains` — a
dedicated AC/barrel-jack rail. This laptop does not have one; it charges over USB-C PD, and
that path reports correctly through `qcom-battmgr-usb` and the UCSI source PSY for whichever
port the charger is in. Reading `qcom-battmgr-ac` and concluding "no charger" is the mistake.

Consequently **UPower reports `on-battery: no`, so `battery_detection=true` in
`/etc/tuned/ppd.conf` works as intended** and the KDE slider maps correctly on both AC and
battery. Nothing here needs a workaround.

One consequence of the rewiring that is worth knowing: `[battery] balanced` now maps to
`glymur-balanced`, i.e. the same caps on battery as on AC. Stock Fedora mapped it to
`balanced-battery`, which is biased toward power saving. If you want that bias back, add a
`glymur-balanced-battery` profile with tighter caps (something like policy0 2496000 /
policy6-12 3033600) and point `[battery] balanced` at it.

**The lesson, for the second time in one day:** a claim that was true when written had
silently become false, and got carried forward into new analysis unverified. Re-measure
before repeating. See `tweaks/retired/README.md` for the other instance.

## Not yet done

- **`cooling-maps`.** `cpufreq-cpu0/6/12` cooling devices exist but no thermal zone binds
  them. Frequency *caps* are not thermal *control*; these profiles do not make the machine
  thermally managed. See `power-and-thermal.md`.
- **No measured battery-life delta yet.** The caps are derived from the Energy Model, which
  is the right basis, but nothing here has been validated against a wall-clock runtime test.
  Treat the numbers as a well-founded starting point, not a tuned result.
