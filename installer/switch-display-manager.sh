#!/bin/sh

# Root-only. Switches the active display-manager.service alias from
# plasmalogin to greetd. Refuses to run unless /etc/greetd/ already matches
# this repo's installer/greetd/ (run setup-greetd.sh first).
#
# Does NOT remove KDE/Plasma packages, GRUB, /boot, mkinitcpio, NVIDIA,
# sudoers, or PAM beyond what the greetd/greetd-regreet packages already
# installed. Never leaves two display managers enabled at once.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR/greetd"

for f in config.toml regreet.toml hyprland.lua; do
    if ! cmp -s "$SRC_DIR/$f" "/etc/greetd/$f" 2>/dev/null; then
        printf '/etc/greetd/%s does not match %s - run setup-greetd.sh first.\n' "$f" "$SRC_DIR/$f" >&2
        exit 1
    fi
done

for bin in regreet start-hyprland uwsm; do
    command -v "$bin" >/dev/null 2>&1 || { printf 'missing required binary: %s\n' "$bin" >&2; exit 1; }
done
[ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ] || { printf 'missing /usr/share/wayland-sessions/hyprland-uwsm.desktop\n' >&2; exit 1; }

# greetd only declares Conflicts=getty@tty1.service; a getty replacement
# (e.g. kmsconvt@tty1.service via the autovt@.service alias) racing it for
# VT1/DRM master crashes the greeter with no logs - see
# docs/personal-fork/ROADMAP.md and installer/fix-vt1-conflict.sh.
if [ -e /etc/systemd/system/getty.target.wants/kmsconvt@tty1.service ] || \
   [ -e /etc/systemd/system/autovt@.service ]; then
    printf 'A getty replacement (kmsconvt@tty1/autovt@.service) is enabled on tty1 - it will race greetd for VT1. Run installer/fix-vt1-conflict.sh first.\n' >&2
    exit 1
fi

if systemctl is-active --quiet greetd.service; then
    printf 'greetd.service is already active - refusing (reboot to test a fresh config instead of live-switching).\n' >&2
    exit 1
fi

systemctl disable plasmalogin.service
systemctl enable greetd.service

printf '%s\n' \
    '--- verification ---' \
    "greetd:      $(systemctl is-enabled greetd.service 2>&1)" \
    "plasmalogin: $(systemctl is-enabled plasmalogin.service 2>&1)" \
    "display-manager.service -> $(readlink -f /etc/systemd/system/display-manager.service)" \
    '' \
    'Not started now on purpose - reboot to test the full chain cold.' \
    'If it fails to reach a usable session: boot to a TTY (Ctrl+Alt+F2..F6),' \
    'log in, and run: sudo systemctl disable greetd && sudo systemctl enable plasmalogin'
