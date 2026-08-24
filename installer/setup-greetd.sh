#!/bin/sh

# Root-only, narrowly scoped: deploys this fork's greetd/ReGreet config from
# installer/greetd/ to /etc/greetd/. Does NOT enable/disable/start any
# systemd service and does NOT touch plasmalogin - see switch-display-manager.sh
# for that separate, explicit step.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR/greetd"
DEST_DIR=/etc/greetd
BACKUP_DIR="/etc/greetd.bak.$(date +%Y%m%d-%H%M%S)"

for f in config.toml regreet.toml hyprland.lua; do
    [ -f "$SRC_DIR/$f" ] || { printf 'missing source file: %s\n' "$SRC_DIR/$f" >&2; exit 1; }
done

if [ -d "$DEST_DIR" ]; then
    cp -a "$DEST_DIR" "$BACKUP_DIR"
    printf 'Backed up %s -> %s\n' "$DEST_DIR" "$BACKUP_DIR"
fi

install -d -m 755 -o root -g root "$DEST_DIR"
install -m 644 -o root -g root "$SRC_DIR/config.toml"   "$DEST_DIR/config.toml"
install -m 644 -o root -g root "$SRC_DIR/regreet.toml"  "$DEST_DIR/regreet.toml"
install -m 644 -o root -g root "$SRC_DIR/hyprland.lua"  "$DEST_DIR/hyprland.lua"

printf '%s\n' \
    'greetd config deployed to /etc/greetd/.' \
    'plasmalogin is still the active display manager - nothing has switched.' \
    "Rollback: sudo cp -a $BACKUP_DIR/. $DEST_DIR/" \
    'Next (manual, review first): installer/switch-display-manager.sh'
