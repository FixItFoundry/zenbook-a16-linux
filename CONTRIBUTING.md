# Contributing

Follow the [stable/rc track policy](docs/kernel-tracks.md): prepare the 7.3 final
port for `main` and linux-next snapshots for `rc`, retaining the A16 work and
reviewing Qualcomm updates against each base. Neither port is release-ready yet.

Choose the track named in [current status](docs/current-build.md). Omarchy work targets the shared package recipe and coordinated runtime/ISO PRs described in [Omarchy status](docs/omarchy-status.md). For a Fedora soc2 experiment, use Linux v7.3-rc5 plus the [64-patch series](patches/rc5-20261013/README.md) and its [recorded config and verifier](kernel/rc5-20261013/README.md).

- Make each hardware experiment a separate change with a distinct kernel release. Preserve a tested fallback and the Windows boot route.
- Build the board DTB from the replayed kernel source; historical files under `dts/` and `prebuilt/` do not define this baseline.
- Preserve patch authors, review trailers and source links. Add adopted upstream work to [UPSTREAM-CREDITS.md](UPSTREAM-CREDITS.md).
- Keep kernel-derived files under `SPDX-License-Identifier: GPL-2.0-only`. Do not commit private signing keys or proprietary firmware/driver binaries.

## Reports and validation

Include the hardware variant, kernel/source identity, DTB hash, config changes,
boot command line, boot ID and relevant kernel journal. State test duration,
power source and attached devices; remove personal information before posting.

Separate source tests, boot/enumeration, traffic/playback and physical acceptance.
A short pass does not close the [remaining hardware limits](docs/current-build.md#remaining-limits).
Keep README and changelog additions factual and brief: one or two sentences per item.

## Local CI

Run `python3 -B scripts/ci.py` on Linux before building either track. It runs the
Python regression suites, including the early-DSP shell fixtures, and requires
`bash`, `git`, `make`, `rpm` and `rpmbuild` so the RPM check cannot silently skip.
Tests use temporary fixtures; this does not install a candidate kernel.

With a Linux Git repository containing the pinned bases, run:

```sh
python3 -B scripts/ci.py --linux-git /path/to/linux.git
```

This independently replays the stable 7.3-final queue and the retained rc5
camera/microphone queue, then their opt-in
[USB PHY candidate overlay](patches/glymur-usb3-20261031/README.md), checking
their manifests and source identities. Use
`--track stable` or `--track rc` to select one. Keep dated recipes unchanged;
update the candidate metadata and CI verifier when adopting a new recipe.
The rc5 result does not validate the planned linux-next port or experimental
patches outside that queue.

The existing Omarchy CI image can run the repository tests in a disposable
x86_64 KVM guest:

```sh
bash scripts/ci-vm.sh /path/to/image /path/to/new-results
```

The host needs writable `/dev/kvm`, QEMU x86/virtio display support, OpenSSH,
Python, Git and GNU coreutils. The image directory holds `base.qcow2`, `vmlinuz`,
`initrd` and `cmdline` from the same image. The runner records their hashes and
the exact working source archive, boots an overlay, installs test dependencies
inside the guest, and retains logs and the exit code. It removes its guest and
overlay on exit; the base image remains unchanged. On the existing CI server,
these host tools can run in the same disposable Arch container used by Omarchy CI.
Source replay runs separately against the Linux Git object store.

A KVM pass covers repository logic and fixture packaging only. For **each**
track, require a full ARM64 Image/modules/DTB build with `modpost`, native package
install/update/rollback checks, then attended A16 boot and peripheral acceptance
before promotion. Record source/config/artifact identities with each result.
Omarchy's working hardware result is comparison evidence, not acceptance of a
different source queue, audio topology or boot policy.
