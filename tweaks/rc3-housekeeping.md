# Userspace accompanying the RC3 baseline

The following repo files match the inspected live configuration:

- `etc/dracut.conf.d/98-glymur-soundwire-early.conf`: early modules and audio topology.
- `etc/dracut.conf.d/99-glymur-adsp.conf`: ADSP firmware in the boot initramfs.
- `etc/modules-load.d/battery-baseline.conf`: retain ps883x; retire soccp_glink.
- `etc/systemd/system/wsa-mix-boost.service`: four valid mixer controls, bounded startup.
- `etc/systemd/system/NetworkManager-wait-online.service.d/first-uplink.conf`:
  wait for connectivity rather than all autoconnect attempts.
- `etc/systemd/system/plymouth-read-write.service.d/20-bound-client.conf`:
  bound the optional Plymouth client.
- `etc/wireplumber/wireplumber.conf.d/51-glymur-ucm.conf` and
  `usr/share/alsa/ucm2/Qualcomm/glymur/`: native four-channel audio routes.

These are not an unattended installer. Back up existing files and review paths
before deployment; dracut files do not change an existing initramfs until rebuilt.
The separate CDSP firmware/initramfs trial is deliberately excluded.

## Session integration

Personal ML4W dotfiles and automatic-login identities are not distributed here.
The baseline uses the packaged Hyprland UWSM session and exports its environment
before finalizing startup. The Hyprland startup command is:

```sh
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP QT_QPA_PLATFORMTHEME GTK_THEME && uwsm finalize QT_QPA_PLATFORMTHEME GTK_THEME
```

Portals use D-Bus/systemd activation, not direct background launches.
`swaync.service` is enabled for the graphical session; remove direct `swaync`
autostart to avoid two notification daemons. The generic quickshell service is
disabled because ML4W starts its own instance. The SELinux applet has a user-unit
drop-in containing `[Unit]` and `ConditionSecurity=selinux`, so it skips when
SELinux is disabled without changing security policy.

EasyEffects and its custom routing service are removed. Do not restore the
retired audio-route/wait services as a supposed native boot fix.
Malformed crash records and a corrupt journal archive were quarantined on the
test host; this is evidence-specific cleanup, not a generic deletion recipe.
