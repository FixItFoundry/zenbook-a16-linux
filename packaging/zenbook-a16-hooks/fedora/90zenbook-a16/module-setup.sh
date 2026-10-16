#!/usr/bin/env bash
# Dracut module for ASUS Zenbook A16 (UX3607OA / Glymur)
# Installs ASUS-signed ADSP/CDSP firmware, early DSP/QRTR/regulator/PHY/USB/NVMe modules,
# and the pre-udev ordering hook.

check() {
    return 0
}

depends() {
    return 0
}

install() {
    inst_multiple tr grep
    # Pre-udev hook: load QRTR, PD mapper, and Q6V5 PAS before systemd-udevd
    inst_hook pre-udev 01 "$moddir/zenbook-a16-pre-udev.sh"

    # ASUS-signed ADSP/CDSP board firmware and audio topology
    local fw_dir
    for fw in \
        qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn \
        qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf \
        qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn \
        qcom/glymur/ASUSTeK/UX3607OA/cdsp_dtbs.elf \
        qcom/glymur/ASUSTeK/UX3607OA-tplg.bin \
        qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin; do
        for fw_dir in /lib/firmware/updates /lib/firmware /usr/lib/firmware; do
            for ext in "" ".zst" ".xz"; do
                if [[ -s "$fw_dir/$fw$ext" ]]; then
                    inst_simple "$fw_dir/$fw$ext" "/lib/firmware/$fw$ext"
                    break 2
                fi
            done
        done
    done

    # Early Qualcomm DSP, QRTR and RPMSG stack
    instmods qrtr qrtr_smd qcom_q6v5_pas qcom_pd_mapper qcom_battmgr \
             snd_soc_x1e80100 snd_soc_wsa884x soundwire_qcom \
             pinctrl_sm8550_lpass_lpi snd_soc_lpass_wsa_macro snd_soc_lpass_va_macro

    # Early PMIC, regulator, PHY, USB, and NVMe modules
    instmods qcom_rpmh_regulator fixed qcom_spmi_pmic llcc_qcom qcom_aoss \
             phy_qcom_edp phy_qcom_qmp_pcie pmic_glink xhci_plat_hcd nvme nvme_core \
             dwc3_qcom phy_qcom_qmp_combo phy_qcom_qmp_usb \
             phy_qcom_m31_eusb2 phy_qcom_eusb2_repeater phy_qcom_qmp_pcie_multiphy \
             qcom_glink_smem dispcc_glymur gpucc_glymur
}
