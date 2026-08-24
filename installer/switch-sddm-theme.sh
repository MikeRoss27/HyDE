#!/bin/sh

# Root-only. Switches /etc/sddm.conf.d/10-theme.conf's Current= between the
# two vendored qylock themes. Config-only - does not restart sddm.service or
# touch a live session; the new theme is picked up the next time the
# greeter starts (log out, or reboot).
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

CONF=/etc/sddm.conf.d/10-theme.conf
THEMES_DIR=/usr/share/sddm/themes

usage() {
    printf 'Usage: %s rainy-room|cyberpunk\n' "$0" >&2
    exit 1
}

[ $# -eq 1 ] || usage

case "$1" in
    rainy-room|rainyroom|pixel-rainyroom|rain) TARGET=pixel-rainyroom ;;
    cyberpunk|pixel-cyberpunk|cyber)           TARGET=pixel-cyberpunk ;;
    *) usage ;;
esac

[ -f "$CONF" ] || { printf '%s not found - run installer/setup-sddm.sh first.\n' "$CONF" >&2; exit 1; }
[ -f "$THEMES_DIR/$TARGET/Main.qml" ] || { printf '%s/%s not found - run installer/setup-sddm.sh first.\n' "$THEMES_DIR" "$TARGET" >&2; exit 1; }

sed -i "s|^Current=.*|Current=$TARGET|" "$CONF"

printf '%s\n' \
    "Active SDDM theme set to: $TARGET" \
    "$(grep '^Current=' "$CONF")" \
    '' \
    'Takes effect at the next greeter start (log out, or reboot) - sddm.service was not restarted.'
