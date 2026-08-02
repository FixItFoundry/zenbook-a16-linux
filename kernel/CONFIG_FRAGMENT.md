# glymur config fragment (v7.1)

The working build starts from a distro config (`/boot/config-*-generic`, `make olddefconfig`)
and then force-enables the glymur boot-critical drivers below.

⚠️ This used to cite `boot-kit/scripts/build-kernel-native-full.sh`, which has never existed in
this repo — the build script lives only on the maintainer's machines. The fragment below is the
authoritative list.

Distro-config fixups (remove signing keys we don't have, drop heavy debuginfo):

```
./scripts/config --set-str SYSTEM_TRUSTED_KEYS "" \
                 --set-str SYSTEM_REVOCATION_KEYS "" \
                 -d DEBUG_INFO -e DEBUG_INFO_NONE -d DEBUG_INFO_BTF \
                 -d DEBUG_INFO_DWARF5 -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
```

Glymur boot-critical built-ins:

```
./scripts/config \
  -e ARCH_QCOM -e QCOM_SCM -e QCOM_CMD_DB -e QCOM_RPMH -e QCOM_TCSR \
  -e PINCTRL_GLYMUR -e COMMON_CLK_QCOM -e CLK_GLYMUR_GCC -e CLK_GLYMUR_TCSRCC \
  -e CLK_RPMH -e INTERCONNECT_QCOM -e INTERCONNECT_QCOM_GLYMUR \
  -e REGULATOR_QCOM_RPMH -e QCOM_PDC -e ARM_SCMI_PROTOCOL -e ARM_SCMI_CPUFREQ \
  -e PCI -e PCIE_QCOM -e PHY_QCOM_QMP_PCIE \
  -e BLK_DEV_NVME -e NVME_CORE \
  -e SERIAL_QCOM_GENI -e SERIAL_QCOM_GENI_CONSOLE -e QCOM_GENI_SE \
  -e I2C -e I2C_QCOM_GENI -e HID -e I2C_HID -e I2C_HID_OF \
  -e USB -e USB_DWC3 -e USB_DWC3_QCOM -e USB_XHCI_HCD -e USB_HID \
  -e PHY_QCOM_QMP_COMBO -e PHY_QCOM_QMP_USB -e PHY_QCOM_SNPS_EUSB2 \
  -e TYPEC -e TYPEC_UCSI -e UCSI_PMIC_GLINK -e QCOM_PMIC_GLINK \
  -e SYSFB_SIMPLEFB -e DRM -e DRM_SIMPLEDRM -e FB -e FRAMEBUFFER_CONSOLE \
  -e ARM_SMMU -e ARM_SMMU_QCOM -e MAILBOX -e QCOM_IPCC \
  -e POWER_RESET_QCOM_PON
make olddefconfig
```

Notes:
- `PINCTRL_GLYMUR`, `CLK_GLYMUR_GCC`, `CLK_GLYMUR_TCSRCC`, `INTERCONNECT_QCOM_GLYMUR` are the
  SoC-specific pieces; without them the box resets before console.
- Display stays on `SIMPLEDRM` + `SIMPLEFB` (the UEFI framebuffer). The `msm`/DPU stack is
  intentionally not the default — see the display docs.
- Boot cmdline must include `efi=noruntime` (see boot-kit).
- Audio/battery/EC extras are built as modules and installed separately
  (`../boot-kit/scripts/install-battery-modules.sh`).
