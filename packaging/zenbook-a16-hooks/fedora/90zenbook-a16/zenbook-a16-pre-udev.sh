#!/bin/sh
# Zenbook A16: Pre-load QRTR, PD mapper, and Q6V5 PAS before systemd-udevd starts
# so that msm_drm never races CDSP bringup.
if ! type getarg >/dev/null 2>&1 && [ -f /lib/dracut-lib.sh ]; then
    . /lib/dracut-lib.sh
fi

if [ -r /sys/firmware/devicetree/base/compatible ]; then
    if ! tr '\0' '\n' < /sys/firmware/devicetree/base/compatible 2>/dev/null | grep -Eq '^(asus,zenbook-a16-ux3607oa|qcom,glymur)$'; then
        return 0 2>/dev/null || exit 0
    fi
fi

modprobe qrtr 2>/dev/null || true
modprobe qrtr_smd 2>/dev/null || true
modprobe qcom_pd_mapper 2>/dev/null || true
modprobe qcom_q6v5_pas 2>/dev/null || true
