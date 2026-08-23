#!/usr/bin/env bash
# installer/validate.sh - `install.sh --check`. Runs preflight.sh plus
# deployment-specific checks (files present, executable, Lua entry point
# parses), then a dedicated graphical-session readiness gate. Entirely
# read-only; safe to run at any time, before or after install, without
# starting a graphical session.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"
# shellcheck source=./preflight.sh
. "$SCRIPT_DIR/preflight.sh" --source-only

check_deployed_manifest() {
    local manifest="$SCRIPT_DIR/deploy.manifest" missing=0 checked=0
    while IFS= read -r line; do
        line=${line%%#*}
        line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        [ -n "$line" ] || continue
        if [[ $line == */ ]]; then
            local dir_abs="$REPO_ROOT/Configs/${line%/}"
            [ -d "$dir_abs" ] || continue
            while IFS= read -r -d '' f; do
                local rel=${f#"$REPO_ROOT/Configs/"}
                checked=$((checked + 1))
                [ -e "$HOME/$rel" ] || { _warn "not deployed: ~/$rel"; missing=$((missing + 1)); }
            done < <(find "$dir_abs" -type f -print0)
        else
            checked=$((checked + 1))
            [ -e "$HOME/$line" ] || { _warn "not deployed: ~/$line"; missing=$((missing + 1)); }
        fi
    done <"$manifest"
    if [ "$missing" -eq 0 ]; then
        _pass "all $checked manifest entries present under \$HOME (run install.sh --install/--repair if this is a fresh checkout)"
    else
        _warn "$missing/$checked manifest entries not yet deployed"
    fi
}

check_bin_executable() {
    for b in hyde-shell hydectl hyde-ipc; do
        local p="$HOME/.local/bin/$b"
        if [ -x "$p" ]; then
            _pass "$b is executable"
        elif [ -e "$p" ]; then
            _fail "$p exists but is not executable"
        fi
    done
}

check_lua_entry_point() {
    local entry="$HOME/.local/share/hypr/hyde.lua"
    [ -f "$entry" ] || { _warn "$entry not deployed yet"; return; }
    local luac_bin
    luac_bin=$(command -v luac5.5 || command -v luac)
    if [ -z "$luac_bin" ]; then
        _warn "no luac available to syntax-check $entry"
        return
    fi
    if "$luac_bin" -p "$entry" 2>/tmp/hyde-installer-luac.err; then
        _pass "hyde.lua parses cleanly ($luac_bin -p)"
    else
        _fail "hyde.lua fails to parse: $(cat /tmp/hyde-installer-luac.err)"
    fi
}

# first_theme_dir - the theme get_themes()/runtime.sh would pick: the first
# entry (alphabetically) under $HYDE_CONFIG_HOME/themes.
first_theme_dir() {
    find "$XDG_CONFIG_HOME/hyde/themes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1
}

check_theme_complete() {
    local theme_dir
    theme_dir=$(first_theme_dir)
    if [ -z "$theme_dir" ]; then
        _warn "no theme directory under \$XDG_CONFIG_HOME/hyde/themes yet - run install.sh --install/--repair"
        return
    fi
    local missing
    missing=$(theme_missing_required "$theme_dir")
    if [ -z "$missing" ]; then
        _pass "theme '$theme_dir' is complete (installer/theme.manifest)"
    else
        _fail "theme '$theme_dir' is missing required files: $(printf '%s' "$missing" | tr '\n' ' ') (installer/theme.manifest) - run install.sh --repair"
    fi
}

check_runtime_generated() {
    check_nonempty_file "$XDG_CONFIG_HOME/swaync/theme.css" "swaync theme.css" >/dev/null 2>&1 \
        && _pass "swaync theme.css generated" || _fail "swaync theme.css not generated - run install.sh --repair"
    check_nonempty_file "$HOME/.config/waybar/theme.css" "waybar theme.css" >/dev/null 2>&1 \
        && _pass "waybar theme.css generated" || _fail "waybar theme.css not generated - run install.sh --repair"
    check_no_unresolved_wallbash_tokens "$HOME/.config/waybar/theme.css" >/dev/null 2>&1 \
        && _pass "waybar theme.css has no unresolved wallbash placeholders" || _fail "waybar theme.css still has unresolved <wallbash_*> placeholders"
    check_no_unresolved_wallbash_tokens "$XDG_CONFIG_HOME/swaync/theme.css" >/dev/null 2>&1 \
        && _pass "swaync theme.css has no unresolved wallbash placeholders" || _fail "swaync theme.css still has unresolved <wallbash_*> placeholders"
    check_css_imports_resolve "$XDG_CONFIG_HOME/swaync/theme.css" >/dev/null 2>&1 \
        && _pass "swaync theme.css @import targets resolve" || _fail "swaync theme.css has a dangling @import"
    if check_hypr_colour_state_complete; then
        _pass "hypr colour state complete (colors.conf, lua_state/colors.lua, lua_state/ui.lua)"
    else
        _warn "hypr colour state incomplete - run install.sh --repair (not fatal until a theme switch actually needs it)"
    fi
}

check_app2unit() {
    if bin_present app2unit; then
        _pass "app2unit is on PATH ($(command -v app2unit))"
    else
        _fail "app2unit not found - Configs/.local/lib/hyde/app.sh execs it unconditionally for every daemon start_up.lua launches (Waybar, wallpaper, hypridle, hyprpolkitagent, config watcher, battery-notify, notifications); without it those all fail silently (exit 127, no systemd unit ever created) - build it with: $INSTALLER_DIR/build-app2unit.sh"
    fi
}

check_uwsm_hyprland_config() {
    local envd="$XDG_CONFIG_HOME/uwsm/env-hyprland.d/00-hyde.sh"
    if [ ! -f "$envd" ]; then
        _warn "not found: $envd - cannot verify UWSM's HYPRLAND_CONFIG resolution"
        return
    fi
    local resolved
    resolved=$(
        unset HYPRLAND_CONFIG HYDE_ACTIVATED
        # shellcheck disable=SC1090
        . "$envd" >/dev/null 2>&1
        printf '%s' "${HYPRLAND_CONFIG:-}"
    )
    if [ -z "$resolved" ]; then
        _fail "UWSM env-hyprland.d/00-hyde.sh did not resolve HYPRLAND_CONFIG to anything"
    elif [ -r "$resolved" ]; then
        _pass "UWSM resolves HYPRLAND_CONFIG -> $resolved (exists, readable)"
    else
        _fail "UWSM resolves HYPRLAND_CONFIG -> $resolved, but that file is missing or unreadable"
    fi
}

echo "== preflight =="
run_all_checks
echo
echo "== deployment =="
check_deployed_manifest
check_bin_executable
check_lua_entry_point
check_theme_complete
check_runtime_generated
check_app2unit
check_uwsm_hyprland_config

echo
log_info "validate summary: $PF_PASS pass, $PF_WARN warn, $PF_FAIL fail"

# --- graphical-session readiness gate --------------------------------
# A dedicated, explicit verdict: everything above is diagnostic detail,
# this section is the single "is it safe to try a Hyprland login" answer -
# every PASS/FAIL line below is its own self-contained check (same
# underlying facts as the detail sections above, evaluated directly here
# rather than threaded through PF_* counters) so this section stays
# readable on its own.
echo
echo "== graphical-session readiness =="
ready=1
_gate_pass() { printf '%s[ok]%s %s\n' "$_c_green" "$_c_reset" "$*"; }
_gate_fail() { printf '%s[XX]%s %s\n' "$_c_red" "$_c_reset" "$*"; ready=0; }
_gate_warn() { printf '%s[!!]%s %s\n' "$_c_yellow" "$_c_reset" "$*"; }

# deployment complete
missing_manifest=$(
    while IFS= read -r line; do
        line=${line%%#*}; line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        [ -n "$line" ] || continue
        if [[ $line == */ ]]; then
            dir_abs="$REPO_ROOT/Configs/${line%/}"
            [ -d "$dir_abs" ] || continue
            while IFS= read -r -d '' f; do
                rel=${f#"$REPO_ROOT/Configs/"}
                [ -e "$HOME/$rel" ] || echo missing
            done < <(find "$dir_abs" -type f -print0)
        else
            [ -e "$HOME/$line" ] || echo missing
        fi
    done <"$SCRIPT_DIR/deploy.manifest" | wc -l
)
if [ "$missing_manifest" -eq 0 ]; then _gate_pass "deployment complete"; else _gate_fail "deployment incomplete ($missing_manifest manifest entries missing) - run install.sh --install/--repair"; fi

# canonical theme complete
theme_dir=$(first_theme_dir)
if [ -z "$theme_dir" ]; then
    _gate_fail "no theme installed under \$XDG_CONFIG_HOME/hyde/themes"
elif [ -z "$(theme_missing_required "$theme_dir")" ]; then
    _gate_pass "canonical theme complete ($theme_dir)"
else
    _gate_fail "theme '$theme_dir' incomplete - run install.sh --repair"
fi

# hyq present and functional
if bin_present hyq && hyq --help >/dev/null 2>&1; then
    _gate_pass "hyq present and functional"
else
    _gate_fail "hyq missing or not functional - build with installer/build-hyq.sh"
fi

# app2unit present - hard dependency of every daemon start_up.lua launches
# (Waybar, wallpaper, hypridle, hyprpolkitagent, config watcher,
# battery-notify, notifications). Its absence is invisible from inside a
# live Hyprland session (hyde-shell app -> app.sh execs it unconditionally;
# missing it means exit 127 with no systemd unit ever created, so nothing
# reaches the journal) - this is the actual root cause of a gray Hyprland
# screen with a working compositor but no Waybar/wallpaper, so it is a hard
# gate here rather than a warning.
if bin_present app2unit; then
    _gate_pass "app2unit present ($(command -v app2unit))"
else
    _gate_fail "app2unit missing - every hyde-shell app ... daemon launch (Waybar, wallpaper, hypridle, hyprpolkitagent, notifications) will silently fail - build with installer/build-app2unit.sh"
fi

# runtime generation successful
if [ -s "$XDG_CONFIG_HOME/swaync/theme.css" ] && [ -s "$HOME/.config/waybar/theme.css" ]; then
    _gate_pass "runtime generation successful (swaync/waybar theme.css present, non-empty)"
else
    _gate_fail "runtime generation incomplete - run install.sh --repair"
fi

# swaync CSS valid enough to load
if [ -s "$XDG_CONFIG_HOME/swaync/theme.css" ] \
    && check_no_unresolved_wallbash_tokens "$XDG_CONFIG_HOME/swaync/theme.css" >/dev/null 2>&1 \
    && check_css_imports_resolve "$XDG_CONFIG_HOME/swaync/theme.css" >/dev/null 2>&1; then
    _gate_pass "swaync theme.css valid enough to load (non-empty, no unresolved tokens, @import targets exist)"
else
    _gate_fail "swaync theme.css not valid enough to load - run install.sh --repair"
fi

# Waybar config generated
if [ -f "$XDG_CONFIG_HOME/waybar/config.jsonc" ] && [ -s "$HOME/.config/waybar/theme.css" ]; then
    _gate_pass "Waybar config generated (config.jsonc deployed, theme.css rendered)"
else
    _gate_fail "Waybar config not fully generated - run install.sh --install/--repair"
fi

# UWSM activation resolves HYPRLAND_CONFIG correctly
envd="$XDG_CONFIG_HOME/uwsm/env-hyprland.d/00-hyde.sh"
resolved=""
if [ -f "$envd" ]; then
    resolved=$(unset HYPRLAND_CONFIG HYDE_ACTIVATED; . "$envd" >/dev/null 2>&1; printf '%s' "${HYPRLAND_CONFIG:-}")
fi
if [ -n "$resolved" ] && [ -r "$resolved" ]; then
    _gate_pass "UWSM activation resolves HYPRLAND_CONFIG -> $resolved"
else
    _gate_fail "UWSM activation does not resolve HYPRLAND_CONFIG to a readable file"
fi

# Intel remains selected as default compositor GPU / no session-wide NVIDIA vars
gpu_envd="$XDG_CONFIG_HOME/uwsm/env.d/01-gpu.sh"
glx="" gbm=""
if [ -f "$gpu_envd" ]; then
    eval "$(
        unset __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND
        # shellcheck disable=SC1090
        source "$gpu_envd" >/dev/null 2>&1
        printf 'glx=%q\n' "${__GLX_VENDOR_LIBRARY_NAME:-}"
        printf 'gbm=%q\n' "${GBM_BACKEND:-}"
    )"
fi
if [ -f "$gpu_envd" ] && [ -z "$glx" ] && [ -z "$gbm" ]; then
    _gate_pass "Intel remains default compositor GPU, no session-wide NVIDIA EGL/GLX variables"
else
    _gate_fail "GPU env resolution forces NVIDIA session-wide, or $gpu_envd is missing"
fi

# required portals installed
if pkg_installed xdg-desktop-portal-hyprland; then
    _gate_pass "required portal installed: xdg-desktop-portal-hyprland"
else
    _gate_fail "xdg-desktop-portal-hyprland not installed"
fi

# Hyprland Lua config parses
entry="$HOME/.local/share/hypr/hyde.lua"
luac_bin=$(command -v luac5.5 || command -v luac || true)
if [ -f "$entry" ] && [ -n "$luac_bin" ] && "$luac_bin" -p "$entry" >/dev/null 2>&1; then
    _gate_pass "Hyprland Lua config parses ($entry)"
else
    _gate_fail "Hyprland Lua config missing or fails to parse ($entry)"
fi

# KDE fallback still present
if pkg_installed plasma-desktop || pkg_installed plasma-meta; then
    _gate_pass "KDE Plasma fallback still installed"
else
    _gate_fail "KDE Plasma fallback not detected"
fi

# --- warn-only, non-blocking ---
bin_present wlogout || _gate_warn "wlogout missing (AUR, optional - install manually if you want it: yay -S wlogout)"
lua_bin=$(command -v lua5.5 || command -v lua || true)
if [ -n "$lua_bin" ] && ! "$lua_bin" -e "require('lgi')" >/dev/null 2>&1; then
    _gate_warn "lgi unavailable - verified non-fatal to the whole runtime, not just to each individual caller: open.lua/dconf.lua/batterynotify.lua each degrade on their own, and color.set.sh's load_dconf_kdeglobals (installer/runtime.sh's wallbash render step) no longer lets an optional dconf/kdeglobals/shader failure abort colour generation - see docs/personal-fork/ARCHITECTURE.md"
fi

echo
if [ "$ready" -eq 1 ]; then
    printf '%s[READY]%s Hyprland/UWSM graphical login may be tested\n' "$_c_green" "$_c_reset"
else
    printf '%s[NOT READY]%s Do not start Hyprland yet - fix the [XX] items above and re-run install.sh --check\n' "$_c_red" "$_c_reset"
fi

[ "$PF_FAIL" -eq 0 ] && [ "$ready" -eq 1 ]
