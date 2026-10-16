#!/usr/bin/env bash
# Dracut module for ASUS Zenbook A16 (UX3607OA / Glymur)
# Installs ASUS-signed ADSP/CDSP firmware, early DSP/QRTR/regulator/PHY/USB/NVMe modules,
# and the pre-root-mount readiness hook.

check() {
    return 0
}

depends() {
    return 0
}

install() {
    inst_multiple tr grep udevadm modprobe sleep || return 1
    inst_simple /usr/lib/zenbook-a16/dsp-policy.sh /usr/lib/zenbook-a16/dsp-policy.sh || return 1
    inst_simple /usr/share/omarchy-a16/remoteproc-blacklist.conf /etc/modprobe.d/zenbook-a16-remoteproc.conf || return 1
    # Coldplug supplies deferred dependencies; readiness still gates root mount.
    inst_hook pre-mount 01 "$moddir/zenbook-a16-pre-udev.sh" || return 1

    # ASUS-signed ADSP/CDSP board firmware and audio topology
    local fw_dir found candidate
    local -a candidates
    for fw in \
        qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn \
        qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf \
        qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn \
        qcom/glymur/ASUSTeK/UX3607OA/cdsp_dtbs.elf \
        qcom/glymur/ASUSTeK/UX3607OA-tplg.bin; do
        found=0
        candidates=("$fw")
        [[ $fw != *UX3607OA-tplg.bin ]] || candidates+=(qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin)
        for candidate in "${candidates[@]}"; do
        for fw_dir in /lib/firmware/updates /lib/firmware /usr/lib/firmware; do
            for ext in "" ".zst" ".xz"; do
                if [[ -s "$fw_dir/$candidate$ext" ]]; then
                    inst_simple "$fw_dir/$candidate$ext" "/lib/firmware/$candidate$ext" || return 1
                    found=1
                    break 3
                fi
            done
        done
        done
        [[ $found == 1 ]] || { dfatal "Missing A16 firmware: $fw"; return 1; }
    done

}

installkernel() {
    # Bypass host autodetection: an installer may build for another machine.
    local hostonly=
    # Required DSP dependencies; instmods -c fails on missing modules, not built-ins.
    instmods -c qrtr qrtr_smd qcom_q6v5_pas qcom_pd_mapper qcom_battmgr \
             snd_soc_x1e80100 snd_soc_wsa884x soundwire_qcom \
             pinctrl_sm8550_lpass_lpi snd_soc_lpass_wsa_macro snd_soc_lpass_va_macro || return 1

    # Platform drivers are optional when built in or disabled by this kernel config.
    instmods qcom_rpmh_regulator fixed qcom_spmi_pmic llcc_qcom qcom_aoss \
             phy_qcom_edp phy_qcom_qmp_pcie pmic_glink xhci_plat_hcd nvme nvme_core \
             dwc3_qcom phy_qcom_qmp_combo phy_qcom_qmp_usb \
             phy_qcom_m31_eusb2 phy_qcom_eusb2_repeater phy_qcom_qmp_pcie_multiphy \
             qcom_glink_smem dispcc_glymur gpucc_glymur
}
