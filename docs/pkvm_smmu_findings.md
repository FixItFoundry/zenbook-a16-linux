# pKVM Display Driver (MSM) Root Cause Analysis

## The Issue
When booting the Linux 7.1.0-glymur kernel on the Snapdragon X Elite Zenbook with `kvm-arm.mode=protected` (pKVM) enabled, the system experiences a hard freeze with zero logs (a hypervisor execution/trap) the moment the display driver (`msm`) attempts to load.

## The Investigation
Through logless binary searching by injecting `-ENODEV` breadcrumbs, we successfully isolated the crash sequence.

1. **Child Component Probing:** `mdss_probe`, `dpu_probe`, and `dp_display_probe` successfully execute without crashing. This eliminates the components' basic hardware detection as the culprit.
2. **Master Bind:** The components wait until `msm_drm_bind` (in `msm_drv.c`) is called. This master function orchestrates the final power-on and hardware integration.
3. **The SMMU Trap:** We intercepted `msm_iommu_new()` and fed the driver a "dummy MMU" that skips all hardware IOMMU programming (specifically `iommu_attach_device()`). With this dummy MMU, **the `msm` driver survived initialization without a hypervisor trap**. This serves as absolute proof that the crash is caused by the Linux host attempting to configure the System MMU (IOMMU) for the display subsystem.

## The Architectural Wall
The SMMU trap is not a bug; it is an architectural enforcement by the Qualcomm EL2 hypervisor.

As corroborated by upstream mailing list discussions regarding `remoteproc` under pKVM:
> *"The design of the Qualcomm EL2 hypervisor dictates that the Linux host OS running at EL1 is not permitted to configure IOMMU translation... and only a single-stage translation is configured."*

1. **The Hypervisor Lockout:** The hypervisor securely owns the SMMU and forbids the host Linux kernel (EL1) from writing to the SMMU registers to set up its own translation tables.
2. **The Hardware Reality:** Because the SMMU is effectively locked/bypassed from the host's perspective, the Display Processing Unit (DPU) reads pixels directly from physical memory addresses. This requires the framebuffer to be a **physically contiguous** block of RAM.
3. **The Software Reality:** Modern versions of the Linux `msm` DRM driver do not have a contiguous memory allocator (CMA/VRAM). They assume the IOMMU is always available, and therefore allocate memory using fragmented/scattered pages (`shmem`). Without the SMMU to stitch these scattered pages into a virtual contiguous buffer, the DPU reads random garbage physical addresses, resulting in a dark screen.

## The Path Forward
To achieve functional hardware-accelerated display rendering under pKVM on this platform, one of two massive architectural shifts is required:

1. **The Massive Hack (Kernel Driver Rewrite):** Rewrite the `msm_gem.c` allocator to forcibly use the Contiguous Memory Allocator (CMA) via `dma_alloc_coherent()`, bypassing the SMMU completely. The physically contiguous address must then be fed directly to the DPU.
2. **Wait for Upstream Qualcomm Support:** Qualcomm engineers are actively working on an architecture to proxy SMMU configuration via SMC calls to TrustZone/Hypervisor. Once this lands upstream for `remoteproc`, it must be ported/adopted by the `mdss` display subsystem.

## Conclusion
The `msm` driver simply cannot function under the current Qualcomm EL2 hypervisor restrictions because it fundamentally relies on creating scattered memory translation tables, an action the hypervisor explicitly forbids.
