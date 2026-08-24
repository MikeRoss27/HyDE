#!/bin/sh

# Root-only, narrowly scoped: deploys this fork's SDDM config and the two
# vendored qylock themes (pixel-rainyroom, pixel-cyberpunk - see
# installer/sddm/themes/CREDITS.md) from installer/sddm/ to /etc/sddm.conf.d/
# and /usr/share/sddm/themes/. Does NOT enable/disable/start any systemd
# service and does NOT touch greetd - see migrate-greetd-to-sddm.sh for that
# separate, explicit step.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR/sddm"
CONF_SRC="$SRC_DIR/sddm.conf.d"
THEMES_SRC="$SRC_DIR/themes"
CONF_DEST=/etc/sddm.conf.d
THEMES_DEST=/usr/share/sddm/themes
SESSIONS_DEST=/etc/sddm/hyde-sessions
UWSM_SESSION=/usr/share/wayland-sessions/hyprland-uwsm.desktop
CONF_BACKUP="/etc/sddm.conf.d.bak.$(date +%Y%m%d-%H%M%S)"

for f in 10-theme.conf 20-wayland.conf; do
    [ -f "$CONF_SRC/$f" ] || { printf 'missing source file: %s\n' "$CONF_SRC/$f" >&2; exit 1; }
done
for theme in pixel-rainyroom pixel-cyberpunk; do
    [ -f "$THEMES_SRC/$theme/Main.qml" ] || { printf 'missing theme source: %s\n' "$THEMES_SRC/$theme" >&2; exit 1; }
done
[ -f "$UWSM_SESSION" ] || { printf 'missing %s - install/repair this fork'"'"'s Configs deploy first (hyprland-uwsm.desktop session file).\n' "$UWSM_SESSION" >&2; exit 1; }

# Config
if [ -d "$CONF_DEST" ]; then
    cp -a "$CONF_DEST" "$CONF_BACKUP"
    printf 'Backed up %s -> %s\n' "$CONF_DEST" "$CONF_BACKUP"
fi
install -d -m 755 -o root -g root "$CONF_DEST"
install -m 644 -o root -g root "$CONF_SRC/10-theme.conf"   "$CONF_DEST/10-theme.conf"
install -m 644 -o root -g root "$CONF_SRC/20-wayland.conf" "$CONF_DEST/20-wayland.conf"

# Themes (reproducible from this repo - rm+recopy is safe, no user data)
install -d -m 755 -o root -g root "$THEMES_DEST"
for theme in pixel-rainyroom pixel-cyberpunk; do
    rm -rf "${THEMES_DEST:?}/$theme"
    cp -r "$THEMES_SRC/$theme" "$THEMES_DEST/$theme"
    chown -R root:root "$THEMES_DEST/$theme"
    find "$THEMES_DEST/$theme" -type d -exec chmod 755 {} +
    find "$THEMES_DEST/$theme" -type f -exec chmod 644 {} +
done

# Session filter: point SDDM's own SessionDir at a fork-owned directory
# containing only a symlink to the packaged hyprland-uwsm.desktop, instead
# of touching, hiding, or deleting anything under the package-owned
# /usr/share/wayland-sessions/ (which also lists hyprland.desktop and
# plasma.desktop - both intentionally left alone).
install -d -m 755 -o root -g root "$SESSIONS_DEST"
ln -sf "$UWSM_SESSION" "$SESSIONS_DEST/hyprland-uwsm.desktop"

printf '%s\n' \
    'SDDM config + pixel-rainyroom/pixel-cyberpunk themes deployed.' \
    'greetd is still the active display manager - nothing has switched.' \
    "Rollback (config only): sudo cp -a $CONF_BACKUP/. $CONF_DEST/" \
    'Next (manual, review first): installer/migrate-greetd-to-sddm.sh'
