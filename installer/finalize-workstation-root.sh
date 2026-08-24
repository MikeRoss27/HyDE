#!/bin/sh

# Root-only, narrowly scoped workstation finalization.
# No package removal and no KDE/SDDM/plasmalogin changes.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

if ! systemctl is-active --quiet NetworkManager.service; then
    printf 'Refusing to disable systemd-networkd: NetworkManager is not active.\n' >&2
    exit 1
fi

pacman -S --needed cliphist wf-recorder rtkit
systemctl disable --now systemd-networkd.service systemd-networkd.socket

printf '%s\n'     'Root finalization complete.'     'Rollback network choice: sudo systemctl enable --now systemd-networkd.service systemd-networkd.socket'

