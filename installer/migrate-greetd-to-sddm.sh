#!/bin/sh

# Root-only. Switches the active display-manager.service alias from greetd
# to sddm. Refuses to run unless /etc/sddm.conf.d/ already matches this
# repo's installer/sddm/sddm.conf.d/ (i.e. setup-sddm.sh ran first) and
# unless sddm/weston and both vendored themes are actually present.
#
# Does NOT remove greetd/greetd-regreet (kept installed, disabled, as the
# rollback path), does NOT touch KDE/Plasma, GRUB, /boot, mkinitcpio,
# NVIDIA, sudoers, or PAM beyond what the sddm package already installs.
# Never leaves two display managers enabled at once. Deliberately does not
# start sddm live - reboot to test the full chain cold, same policy as
# switch-display-manager.sh.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR/sddm/sddm.conf.d"

for f in 10-theme.conf 20-wayland.conf; do
    if ! cmp -s "$SRC_DIR/$f" "/etc/sddm.conf.d/$f" 2>/dev/null; then
        printf '/etc/sddm.conf.d/%s does not match %s - run installer/setup-sddm.sh first.\n' "$f" "$SRC_DIR/$f" >&2
        exit 1
    fi
done

for bin in sddm weston; do
    command -v "$bin" >/dev/null 2>&1 || { printf 'missing required binary: %s (installer/packages.sh --install)\n' "$bin" >&2; exit 1; }
done
for theme in pixel-rainyroom pixel-cyberpunk; do
    [ -f "/usr/share/sddm/themes/$theme/Main.qml" ] || { printf 'missing /usr/share/sddm/themes/%s - run installer/setup-sddm.sh first.\n' "$theme" >&2; exit 1; }
done
[ -L /etc/sddm/hyde-sessions/hyprland-uwsm.desktop ] && [ -e /etc/sddm/hyde-sessions/hyprland-uwsm.desktop ] || {
    printf '/etc/sddm/hyde-sessions/hyprland-uwsm.desktop missing or broken - run installer/setup-sddm.sh first.\n' >&2
    exit 1
}

# Same VT1/DRM-master race documented in ROADMAP.md for greetd applies
# identically to sddm's own greeter process - guard against it recurring.
if [ -e /etc/systemd/system/getty.target.wants/kmsconvt@tty1.service ] || \
   [ -e /etc/systemd/system/autovt@.service ]; then
    printf 'A getty replacement (kmsconvt@tty1/autovt@.service) is enabled on tty1 - it will race sddm for VT1. Run installer/fix-vt1-conflict.sh first.\n' >&2
    exit 1
fi

if systemctl is-active --quiet sddm.service; then
    printf 'sddm.service is already active - refusing (reboot to test a fresh config instead of live-switching).\n' >&2
    exit 1
fi

systemctl disable greetd.service
systemctl enable sddm.service

printf '%s\n' \
    '--- verification ---' \
    "sddm:   $(systemctl is-enabled sddm.service 2>&1)" \
    "greetd: $(systemctl is-enabled greetd.service 2>&1)" \
    "display-manager.service -> $(readlink -f /etc/systemd/system/display-manager.service)" \
    '' \
    'Not started now on purpose - reboot to test the full chain cold.' \
    'If it fails to reach a usable session: boot to a TTY (Ctrl+Alt+F2..F6),' \
    'log in, and run: sudo systemctl disable sddm && sudo systemctl enable greetd'
