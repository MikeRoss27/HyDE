#!/usr/bin/env bash
# installer/diagnose-startup.sh - `install.sh --diagnose-startup`. Entirely
# read-only: never launches a compositor, never touches system state.
#
# Two parts:
#   1. a static startup graph - can every piece HyDE's start_up.lua wires up
#      (Configs/.local/share/hypr/lua/start_up.lua) actually resolve right
#      now, without starting a graphical session at all
#   2. a correlation against the most recent Hyprland/UWSM session found in
#      the systemd --user journal, so "which daemon never actually started
#      last time" doesn't require a TTY photo
#
# See docs/personal-fork/ARCHITECTURE.md for the app2unit finding this
# command exists to catch before it becomes another gray screen.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

row() {
    # row <label> <status: OK|WARN|FAIL|--> <detail>
    local label=$1 status=$2 detail=${3:-}
    local colour=$_c_green
    case "$status" in
        OK) colour=$_c_green ;;
        WARN) colour=$_c_yellow ;;
        FAIL) colour=$_c_red ;;
        *) colour=$_c_blue ;;
    esac
    printf '%-26s %s%-5s%s  %s\n' "$label" "$colour" "$status" "$_c_reset" "$detail"
}

echo "== HyDE startup graph (static - no session required) =="

# Hyprland Lua entry point
entry="$HOME/.local/share/hypr/hyde.lua"
luac_bin=$(command -v luac5.5 || command -v luac || true)
if [ ! -f "$entry" ]; then
    row "Hyprland config" FAIL "not deployed: $entry"
elif [ -z "$luac_bin" ]; then
    row "Hyprland config" WARN "$entry present, no luac to syntax-check"
elif "$luac_bin" -p "$entry" >/dev/null 2>&1; then
    row "Hyprland config" OK "$entry parses ($luac_bin -p)"
else
    row "Hyprland config" FAIL "$entry fails to parse"
fi

# Lua runtime (luarocks env start_up.lua's own require chain needs)
lua_env_dir="$XDG_STATE_HOME/hyde/lua_env"
if [ -d "$lua_env_dir" ]; then
    row "Lua runtime" OK "$lua_env_dir present (hyde-shell luainit has run)"
else
    row "Lua runtime" FAIL "$lua_env_dir missing - run: hyde-shell luainit"
fi
lua_bin=$(command -v lua5.5 || command -v lua || true)
if [ -n "$lua_bin" ] && ! "$lua_bin" -e "require('lgi')" >/dev/null 2>&1; then
    row "  lgi (optional)" WARN "unavailable - open.lua/dconf.lua/batterynotify.lua degrade gracefully (verified: each wraps require('lgi') in pcall); none of these are on the hyprland.start critical path"
fi

# Python runtime - NOT required for the hyprland.start critical path: the
# only Python component started there is waybar.py, whose imports
# (pyutils.* - compositor/logger/wrapper.libnotify/wrapper.rofi/
# xdg_base_dirs) are all local, vendored, stdlib-only modules resolved via
# waybar.py's own script directory, run under system python3 (no venv
# activation on the `hyde-shell app` dispatch path - see app.sh/hyde-shell's
# `app)` case, which only calls python_activate when HYDEPY=1). The venv is
# used by hyde-shell reload/completion/pypr/theme-import - none startup-critical.
venv="$XDG_STATE_HOME/hyde/python_env"
if [ -x "$venv/bin/python" ]; then
    row "Python venv (optional)" OK "$venv present"
else
    row "Python venv (optional)" WARN "$venv missing - NOT required for Waybar/wallpaper/SwayNC startup (verified: waybar.py only imports local stdlib-only pyutils modules under system python3); needed for hyde-shell reload/completion/pypr/theme-import. Run: hyde-shell pyinit"
fi

# app2unit - the actual hard dependency of every daemon dispatch
if app2unit_gate >/tmp/hyde-diagnose-app2unit.err 2>&1; then
    row "app2unit" OK "$(command -v app2unit)"
else
    row "app2unit" FAIL "missing - see below (this blocks Waybar/wallpaper/hypridle/polkit/notifications/config-watcher ALL at once)"
fi

# Waybar
if bin_present waybar; then row "Waybar binary" OK "$(command -v waybar)"; else row "Waybar binary" FAIL "waybar not installed"; fi
if [ -f "$XDG_CONFIG_HOME/waybar/config.jsonc" ]; then row "Waybar config" OK "$XDG_CONFIG_HOME/waybar/config.jsonc"; else row "Waybar config" FAIL "not deployed"; fi
if [ -s "$HOME/.config/waybar/theme.css" ]; then row "Waybar CSS" OK "theme.css rendered"; else row "Waybar CSS" FAIL "theme.css missing/empty - run install.sh --repair"; fi
waybar_py="$HOME/.local/lib/hyde/waybar.py"
if [ -x "$waybar_py" ]; then row "waybar.py launcher" OK "$waybar_py"; else row "waybar.py launcher" FAIL "$waybar_py missing or not executable"; fi

# SwayNC
if bin_present swaync; then row "SwayNC binary" OK "$(command -v swaync)"; else row "SwayNC binary" FAIL "swaync not installed"; fi
if [ -f "$XDG_CONFIG_HOME/swaync/config.json" ]; then row "SwayNC config" OK "$XDG_CONFIG_HOME/swaync/config.json"; else row "SwayNC config" FAIL "not deployed"; fi
style_css="$XDG_CONFIG_HOME/swaync/style.css"
if [ -f "$style_css" ]; then
    if grep -qE '^@import "user-style\.css"$' "$style_css" 2>/dev/null; then
        row "SwayNC style.css" FAIL "missing trailing ';' after last @import (GTK CSS: 'Unterminated block') - check Configs/.config/swaync/style.css, then install.sh --repair"
    else
        row "SwayNC style.css" OK "@import lines terminated"
    fi
else
    row "SwayNC style.css" WARN "not deployed yet"
fi
if [ -s "$XDG_CONFIG_HOME/swaync/theme.css" ] \
    && check_no_unresolved_wallbash_tokens "$XDG_CONFIG_HOME/swaync/theme.css" >/dev/null 2>&1 \
    && check_css_imports_resolve "$XDG_CONFIG_HOME/swaync/theme.css" >/dev/null 2>&1; then
    row "SwayNC theme.css" OK "rendered, imports resolve"
else
    row "SwayNC theme.css" FAIL "missing/empty/unresolved - run install.sh --repair"
fi
swaync_dropin="$XDG_CONFIG_HOME/systemd/user/swaync.service.d/10-hyde-session-scope.conf"
if [ -f "$swaync_dropin" ] && grep -q 'ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland' "$swaync_dropin" 2>/dev/null; then
    row "SwayNC/KDE isolation" OK "session-scope drop-in deployed ($swaync_dropin)"
else
    row "SwayNC/KDE isolation" FAIL "drop-in not deployed - swaync.service D-Bus-activates in ANY session (org.erikreider.swaync.service) and start-limit-hits under KDE; run install.sh --repair"
fi

# Wallpaper backend
wallpaper_backend=$(grep -E '^\s*backend\s*=' "$HOME/.config/hyde/config.toml" 2>/dev/null | head -1 | sed -E 's/.*=\s*"([^"]*)".*/\1/')
[ -n "$wallpaper_backend" ] || wallpaper_backend="awww"
wallpaper_handler="$HOME/.local/lib/hyde/wallpaper.$wallpaper_backend.sh"
if [ -x "$wallpaper_handler" ]; then row "Wallpaper handler" OK "$wallpaper_handler"; else row "Wallpaper handler" FAIL "$wallpaper_handler missing or not executable"; fi
if bin_present "$wallpaper_backend"; then
    row "Wallpaper backend bin" OK "$wallpaper_backend: $(command -v "$wallpaper_backend")"
else
    row "Wallpaper backend bin" FAIL "$wallpaper_backend not installed - wallpaper.$wallpaper_backend.sh calls it with no fallback and no error surfaced (silently produces no wallpaper). See installer/packages.manifest"
fi

# Polkit agent
if [ -e /usr/libexec/hyprpolkitagent ] || [ -e /usr/lib/hyprpolkitagent ] || [ -e /usr/lib/hyprpolkitagent/hyprpolkitagent ]; then
    row "Polkit agent" OK "hyprpolkitagent present (polkitkdeauth.sh's preferred agent)"
else
    row "Polkit agent" WARN "hyprpolkitagent not found - polkitkdeauth.sh falls back through a search list, see installer/diagnose-startup.sh output above for what's on this machine"
fi

# hypridle
if bin_present hypridle; then row "hypridle" OK "$(command -v hypridle)"; else row "hypridle" FAIL "not installed"; fi

echo
echo "== Previous Hyprland session (systemd --user journal) =="

# Find the most recent boot that actually ran a Hyprland/UWSM session.
hy_boot=""
hy_start=""
hy_end=""
while IFS= read -r line; do
    boot_off=$(printf '%s' "$line" | awk '{print $1}')
    [ -n "$boot_off" ] || continue
    if journalctl --user -b "$boot_off" -o cat 2>/dev/null | grep -q "Started Main service for Hyprland"; then
        hy_boot=$boot_off
        break
    fi
done < <(journalctl --user --list-boots 2>/dev/null | awk '{print $1}' | sort -rn)

if [ -z "$hy_boot" ]; then
    row "Hyprland session found" WARN "no boot in the retained journal ever started Hyprland - nothing to correlate"
else
    hy_start=$(journalctl --user -b "$hy_boot" -o short-iso --no-pager 2>/dev/null | grep -m1 "Starting Main service for Hyprland" | awk '{print $1}')
    hy_end=$(journalctl --user -b "$hy_boot" -o short-iso --no-pager 2>/dev/null | tail -1 | awk '{print $1}')
    log_info "correlating boot offset $hy_boot ($hy_start .. $hy_end)"
    # -o short-precise (not -o cat): check_seen's patterns match against the
    # "host comm[pid]: message" prefix, which -o cat strips entirely.
    dump=$(journalctl --user -b "$hy_boot" -o short-precise --no-pager 2>/dev/null)

    check_seen() {
        local label=$1 pattern=$2 detail_ok=$3 detail_missing=$4
        if printf '%s' "$dump" | grep -qE "$pattern"; then
            row "$label" OK "$detail_ok"
        else
            row "$label" FAIL "$detail_missing"
        fi
    }

    check_seen "Hyprland" "Started Main service for Hyprland" "compositor reached ready" "never reached 'Started'"
    check_seen "UWSM" "Reached target Session envelope of hyprland.desktop|Welcome to Hyprland" "envelope/compositor banner seen" "no envelope/banner seen"
    check_seen "Waybar" "\\bwaybar\\[[0-9]+\\]|Started hyde-.*-bar\\.scope" "waybar process/unit seen in journal" "NOT STARTED - no waybar process or hyde-*-bar.scope unit ever appeared"
    check_seen "SwayNC" "\\bswaync\\[[0-9]+\\]" "swaync process seen (native D-Bus-activated swaync.service or hyde-*-notifications.service - journal alone doesn't distinguish which)" "NOT STARTED"
    check_seen "Wallpaper" "hyde-.*-wallpaper\\.service|\\bawww(-daemon)?\\[[0-9]+\\]|\\bswww(-daemon)?\\[[0-9]+\\]|\\bhyprpaper\\[[0-9]+\\]" "wallpaper unit/process seen" "NOT STARTED - no hyde-*-wallpaper.service or backend process ever appeared"
    check_seen "hypridle" "hyde-.*-idle\\.service|\\bhypridle\\[[0-9]+\\]" "hypridle unit/process seen" "NOT STARTED"
    check_seen "Polkit agent" "\\bhyprpolkitagent\\[[0-9]+\\]|polkitkdeauth" "agent process/script seen" "NOT STARTED"
    check_seen "Portal (Hyprland)" "Started Portal service \\(Hyprland implementation\\)" "xdg-desktop-portal-hyprland started" "not started"
fi

echo
echo "== Root startup blocker =="
if ! bin_present app2unit; then
    printf '%s[XX]%s app2unit is missing on PATH.\n' "$_c_red" "$_c_reset"
    printf '     Configs/.local/lib/hyde/app.sh execs it unconditionally for every\n'
    printf '     hyde-shell app ... dispatch (Waybar, wallpaper, hypridle, hyprpolkitagent,\n'
    printf '     config watcher, battery-notify all go through it). Without it each launch\n'
    printf '     is "app2unit: command not found" (exit 127) in a forked shell Hyprland never\n'
    printf '     surfaces anywhere visible - no systemd unit is ever created, so it does not\n'
    printf '     even reach the journal. This is consistent with the previous-session\n'
    printf '     correlation above (Waybar/wallpaper/hypridle/polkit all NOT STARTED, while\n'
    printf '     SwayNC/nm-applet/blueman - which start via D-Bus activation or XDG autostart,\n'
    printf '     bypassing hyde-shell entirely - did start).\n'
    printf '     Fix: installer/build-app2unit.sh, then install.sh --repair, then retry login.\n'
elif ! bin_present "$wallpaper_backend"; then
    printf '%s[XX]%s wallpaper backend "%s" is missing on PATH.\n' "$_c_red" "$_c_reset" "$wallpaper_backend"
    printf '     wallpaper.%s.sh calls it directly with no fallback and no visible error.\n' "$wallpaper_backend"
    printf '     Fix: install it (installer/packages.manifest), then install.sh --repair.\n'
elif grep -qE '^@import "user-style\.css"$' "$style_css" 2>/dev/null; then
    printf '%s[XX]%s SwayNC style.css is malformed at the deployed copy (source already fixed - re-deploy).\n' "$_c_red" "$_c_reset"
    printf '     Fix: install.sh --repair.\n'
else
    printf '%s[--]%s no single static blocker detected - re-run after a real Hyprland login and check the correlation section above for what actually failed to start.\n' "$_c_blue" "$_c_reset"
fi
