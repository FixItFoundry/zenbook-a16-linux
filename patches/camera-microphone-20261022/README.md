# A16 camera and microphone integration overlay

This ten-patch series applies after the repository's 104-patch
[Qualcomm bridge](../../kernel/rc5-qcom-bridge-20261018/README.md).
It combines the working RGB/IR camera paths, the microphone channel-map fix,
and an **experimental Windows-derived DMIC pin configuration**. It is a local
integration series, not an upstream submission or a confirmed banding fix.

| Checkpoint | Kernel source tree |
|---|---|
| Existing 104-patch bridge | `65fd4b07749a5d6b48f5b2dbbfc3e78681f04bf1` |
| Eight camera patches | `27e7dd0621d1f752bf778a67d8787a98e1c43444` |
| Camera plus channel-map clearing | `ffe6f4155024d97ef2607af7d165d1d0386514ad` |
| Complete overlay | `622916bf1849749a5aa3cdbccf5179de4423ae76` |

## Apply and build

From this repository, verify the complete source replay without changing your
Linux checkout or creating commits:

```sh
python3 patches/camera-microphone-20261022/verify.py /path/to/linux-git
```

Apply to a **separate source tree already containing the 104 bridge patches**:

```sh
patch_dir="$PWD/patches/camera-microphone-20261022"
(
    set -e
    while IFS= read -r patch; do
        git -C /path/to/bridge-source apply "$patch_dir/$patch"
    done < "$patch_dir/series"
)
```

Check that all ten patches applied before building. Merge `camera.config` into
the bridge configuration using the kernel's `scripts/kconfig/merge_config.sh`,
then run `olddefconfig` and build Image, modules and the A16 DTB with your distro
pipeline. The existing bridge `build.sh` still reproduces its original 104-patch
tree; it does not automatically add this overlay. Use a distinct kernel release
and retain the previous kernel for rollback.

Camera builds must omit the older package command-line option
`modprobe.blacklist=i2c_qcom_cci,qcom_camss,ov02c10`. The current generic
`packaging/zenbook-a16-kernel/package.py` still emits that option, so downstream
camera packaging must remove it from the generated metadata as well as GRUB.
Retain the existing DSP policy and sleep restrictions. No firmware is included.

## Contents and provenance

- `0001`, `0008`, `0009`: CCI fixes by Oleg Keri, Hitesh Patel and Loic Poulain.
  Original commit messages and trailers are retained.
- `0002`, `0003`: PM8010 support adapted from Qualcomm's
  [laptops-kernel tree at c9f622e](https://github.com/linux-msm/laptops-kernel/tree/c9f622e03e7143c38d0910656354e703f3eba823).
  The backport preserves PM8008 GPIO/IRQ behavior and permits the A16's
  regulator-only PM8010 node without an interrupt.
- `0004`: HM1092 driver by Ramshouriesh R and Jake Steinman from the same tree;
  removes the unused `get_selection` client-info argument for this rc5 API.
- `0006`: Glymur-only restriction to the tested CSID0/VFE0 nonsecure path,
  without TPG. Secure-lite resource ownership remains unresolved.
- `0007`: Konrad Dybcio's
  [PM8010](https://github.com/linux-msm/laptops-kernel/commit/893830312dbbdbc9d6056e23a33f20a8dc8a6cc6),
  [RGB](https://github.com/linux-msm/laptops-kernel/commit/1bc6ad82803e759dcc8fae7cedac0825852abcb3)
  and [IR](https://github.com/linux-msm/laptops-kernel/commit/8edb01d40899bbc8b755a615bfa76505936efb34)
  wiring, adapted to this board tree with tested TITAN_TOP runtime power-domain
  dependencies. Unproven PMIC input supplies remain omitted.
- `0010`: clear all default channel-map entries before filling the requested
  channels. The same clearing line appears in Zhangfei Gao's broader
  [multichannel submission](https://lore.kernel.org/all/20261021102549.411456-1-zhangfei.gao@oss.qualcomm.com/).
  No additional multichannel support or new authorship/sign-off is claimed.
- `0011`: apply DMIC01 drive **4 mA**, pull-downs and slew code **1** on GPIO6/7,
  with Glymur-specific slew support. Clock stays at 2.4 MHz. Installed Windows
  calibration requests raw drive 3; tracing the shipped DSP's scaling and
  quantizer resolves this to the 4 mA hardware setting. This is static binary
  evidence, not live Windows register capture or an electrical measurement.
  No proprietary binary content is distributed.

Number `0005` is absent because an earlier speculative PLL change was discarded.
The failed 2 mA clock-drive experiment is also excluded. The complete overlay
applies directly to the original 8 mA bridge/camera source.

## Validation and limits

RGB and IR capture worked on the camera baseline. After the channel-map fix,
direct ALSA 2-to-4-to-2-channel capture transitions passed with nonzero samples
and clean exits. `test-channel-map.py /path/to/audioreach.c` compiles the real
helper and checks dirty-map clearing across 4-to-2-to-1-channel transitions.
It needs the adjacent `audioreach.h` and `q6dsp-common.h` files.

The final source was built and installed on Fedora as
`7.3.0-rc5-ZenbookA16-20261022-a16pkg3+`. Image/DTB checks, all 8,469 AArch64
module versions, compiled 4/4 mA/pull-down/slew settings, initramfs contents and
both GRUB boot locations passed verification. The machine was powered off for
a later cold boot; **the final pin configuration has not been boot-validated**.
The previous 2 mA test worsened bands during recording. Keep this series
experimental until simultaneous camera/microphone recording is checked in
both preview and saved video, with microphone level and speaker playback.

Ubuntu packaging/boot, simultaneous RGB/IR, IR emitter operation, camera
calibration, full sleep and permanent cold-boot reliability remain unvalidated.
An installed four-channel UCM workaround remains separate from this kernel
series; stereo profile loading must be checked before removing it.
