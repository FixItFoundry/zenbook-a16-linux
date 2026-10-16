#!/bin/sh
# Run after coldplug, before mounting root; the name is retained for installed layouts.
. /lib/dracut-lib.sh
. /usr/lib/zenbook-a16/dsp-policy.sh

msg() { info "$*"; }
a16_emergency() {
    warn "$1"
    warn 'A16 DSP startup stopped before root mount; reboot into the DSP-disabled rescue entry.'
    # A hook subprocess must never return to the root-mount sequence.
    while :; do /bin/sh -i </dev/console >/dev/console 2>&1; done
}
run_hook
