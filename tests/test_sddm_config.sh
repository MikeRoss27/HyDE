#!/usr/bin/env sh
# Static checks for the SDDM + qylock login-screen integration
# (installer/sddm/, installer/setup-sddm.sh, installer/switch-sddm-theme.sh,
# installer/migrate-greetd-to-sddm.sh) - see docs/personal-fork/ROADMAP.md.
# Everything here is read-only: no sudo, no systemctl, no pacman.

. "$(dirname -- "$0")/lib/common.sh"

SDDM_DIR="$REPO_ROOT/installer/sddm"

for script in setup-sddm.sh switch-sddm-theme.sh migrate-greetd-to-sddm.sh; do
    path="$REPO_ROOT/installer/$script"
    [ -f "$path" ] || { fail "$script is missing"; continue; }
    [ -x "$path" ] || fail "$script is not executable"
    sh -n "$path" 2>/dev/null || fail "$script does not parse (sh -n)"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$path" >/dev/null 2>&1 || fail "$script fails shellcheck"
    fi
done

for conf in 10-theme.conf 20-wayland.conf; do
    [ -f "$SDDM_DIR/sddm.conf.d/$conf" ] || fail "sddm.conf.d/$conf is missing"
done

python3 - "$SDDM_DIR" <<'PY' || fail 'sddm.conf.d / theme.conf / metadata.desktop did not parse as valid ini'
import configparser
import sys
from pathlib import Path

base = Path(sys.argv[1])
files = [
    base / "sddm.conf.d/10-theme.conf",
    base / "sddm.conf.d/20-wayland.conf",
]
for theme in ("pixel-rainyroom", "pixel-cyberpunk"):
    files += [base / "themes" / theme / "metadata.desktop", base / "themes" / theme / "theme.conf"]

for f in files:
    c = configparser.ConfigParser()
    if not c.read(f):
        sys.exit(f"could not read {f}")

theme_conf = configparser.ConfigParser()
theme_conf.read(base / "sddm.conf.d/10-theme.conf")
current = theme_conf.get("Theme", "Current")
if current != "pixel-rainyroom":
    sys.exit(f"default theme should be pixel-rainyroom, got {current!r}")

for theme, expect_author in (("pixel-rainyroom", "Darkkal44"), ("pixel-cyberpunk", "Darkkal44")):
    meta = configparser.ConfigParser()
    meta.read(base / "themes" / theme / "metadata.desktop")
    if meta.get("SddmGreeterTheme", "QtVersion") != "6":
        sys.exit(f"{theme}: expected QtVersion=6")
    if meta.get("SddmGreeterTheme", "Author") != expect_author:
        sys.exit(f"{theme}: unexpected Author")
PY

for theme in pixel-rainyroom pixel-cyberpunk; do
    theme_dir="$SDDM_DIR/themes/$theme"
    for f in Main.qml BackgroundVideo.qml bg.mp4 metadata.desktop theme.conf font/PixelifySans-Bold.ttf; do
        [ -f "$theme_dir/$f" ] || fail "$theme is missing $f"
    done
done

[ -f "$SDDM_DIR/themes/LICENSE-qylock" ] || fail 'qylock LICENSE is missing (GPL-3.0 attribution requirement)'
[ -f "$SDDM_DIR/themes/CREDITS.md" ] || fail 'qylock CREDITS.md is missing (wallpaper/font attribution requirement)'

# The session-filter mechanism must point at a fork-owned SessionDir, never
# at the package-owned /usr/share/wayland-sessions/ directly - that's the
# whole point of not touching hyprland.desktop/plasma.desktop.
grep -q '^SessionDir=/etc/sddm/hyde-sessions$' "$SDDM_DIR/sddm.conf.d/20-wayland.conf" ||
    fail '20-wayland.conf must point SessionDir at a fork-owned directory, not /usr/share/wayland-sessions'
grep -q 'hyprland-uwsm.desktop' "$REPO_ROOT/installer/setup-sddm.sh" ||
    fail 'setup-sddm.sh must reference hyprland-uwsm.desktop for the session symlink'
grep -q 'ln -sf' "$REPO_ROOT/installer/setup-sddm.sh" ||
    fail 'setup-sddm.sh should symlink the session file, not copy it (avoids drift from the packaged .desktop)'

grep -q 'greetd' "$REPO_ROOT/installer/migrate-greetd-to-sddm.sh" ||
    fail 'migrate-greetd-to-sddm.sh should reference greetd (rollback path)'
grep -q 'kmsconvt' "$REPO_ROOT/installer/migrate-greetd-to-sddm.sh" ||
    fail 'migrate-greetd-to-sddm.sh should carry the kmscon/VT1 preflight guard'

grep -qE '^sddm[[:space:]]*\|[[:space:]]*repo[[:space:]]*\|' "$REPO_ROOT/installer/packages.manifest" ||
    fail 'sddm entry missing from installer/packages.manifest'
grep -qE '^weston[[:space:]]*\|[[:space:]]*repo[[:space:]]*\|' "$REPO_ROOT/installer/packages.manifest" ||
    fail 'weston entry missing from installer/packages.manifest'

printf '    SDDM/qylock config, scripts, and theme assets checked\n'
finish
