#!/usr/bin/env bash
# installer/preflight.sh - read-only system detection and validation.
# Never mutates anything. Used standalone as `install.sh --check` (before
# install) and again after --install to confirm the result.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

PF_PASS=0
PF_WARN=0
PF_FAIL=0

_pass() { PF_PASS=$((PF_PASS + 1)); log_ok "$*"; }
_warn() { PF_WARN=$((PF_WARN + 1)); log_warn "$*"; }
_fail() { PF_FAIL=$((PF_FAIL + 1)); log_err "$*"; }

check_arch() {
    if [ -r /etc/os-release ] && grep -q '^ID=arch$' /etc/os-release; then
        _pass "Arch Linux confirmed"
    else
        _fail "not Arch Linux (or /etc/os-release unreadable) - this installer is Arch-only"
    fi
}

check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        _fail "running as root - refusing (installer must run as your user)"
    else
        _pass "running as user $(id -un)"
    fi
}

check_xdg() {
    _pass "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
    _pass "XDG_DATA_HOME=$XDG_DATA_HOME"
    _pass "XDG_STATE_HOME=$XDG_STATE_HOME"
}

check_hyprland() {
    if bin_present Hyprland; then
        local ver
        ver=$(Hyprland --version 2>/dev/null | head -1)
        _pass "Hyprland present: ${ver:-unknown version}"
    else
        _fail "Hyprland binary not found - install it before continuing"
    fi
}

check_uwsm() {
    if bin_present uwsm; then
        _pass "uwsm present"
    else
        _fail "uwsm binary not found"
    fi
    if [ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ]; then
        _pass "hyprland-uwsm.desktop session file exists"
    else
        _warn "hyprland-uwsm.desktop not found under /usr/share/wayland-sessions - SDDM won't offer a UWSM Hyprland session until the hyprland/uwsm packages provide it"
    fi
}

check_display_manager() {
    # This fork's docs assume SDDM, but the live display-manager.service
    # symlink is the ground truth - on this machine it actually resolves to
    # plasmalogin (KDE's SDDM successor), not sddm. Both read session
    # .desktop files from the same /usr/share/{wayland-sessions,xsessions}
    # dirs, so "never replace the display manager" applies to whichever is
    # actually active, not to the name "sddm" specifically.
    local dm_unit
    dm_unit=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)
    if [ -z "$dm_unit" ]; then
        _warn "no display-manager.service symlink found - could not determine the active display manager"
        return
    fi
    local dm_name
    dm_name=$(basename "$dm_unit" .service)
    case "$dm_name" in
        sddm) _pass "display manager: sddm" ;;
        plasmalogin) _pass "display manager: plasmalogin (KDE's SDDM successor - not sddm, docs assumption was wrong; never replaced automatically either way)" ;;
        *) _warn "display manager: $dm_name (not sddm/plasmalogin - never replaced automatically, but this fork's docs assume one of those)" ;;
    esac
}

check_kde_coexistence() {
    if pkg_installed plasma-desktop || pkg_installed plasma-meta; then
        _pass "KDE Plasma still installed (fallback preserved)"
    else
        _warn "no KDE Plasma package detected - expected it to remain installed as a fallback"
    fi
    if [ -f /usr/share/wayland-sessions/plasma.desktop ] || [ -f /usr/share/xsessions/plasmax11.desktop ]; then
        _pass "a Plasma session file is present for SDDM"
    else
        _warn "no Plasma session file found under /usr/share/{wayland-sessions,xsessions}"
    fi
}

check_gpu() {
    local vga
    vga=$(lspci -nn 2>/dev/null | grep -E "VGA|3D")
    if echo "$vga" | grep -qi '8086' && echo "$vga" | grep -qi '10de'; then
        _pass "hybrid Intel + NVIDIA GPU detected"
    else
        _warn "expected hybrid Intel+NVIDIA GPUs; lspci shows: $(echo "$vga" | tr '\n' ';')"
    fi
    if pkg_installed nvidia-open; then
        _pass "nvidia-open driver package installed"
    elif pkg_installed nvidia; then
        _warn "nvidia (proprietary) driver installed, not nvidia-open - not changing this, just noting it"
    else
        _warn "no NVIDIA driver package detected"
    fi
}

check_gpu_env_leak() {
    # Grepping the file text is not enough: 01-gpu.sh forces NVIDIA vars
    # inside its "NVIDIA-only" (key=0001) case branch, which is correct
    # and never executes on a hybrid Intel+NVIDIA machine. Actually source
    # the live env.d script (exactly what uwsm does) and check what it
    # resolves to for THIS machine's real GPU topology.
    local envd="$XDG_CONFIG_HOME/uwsm/env.d/01-gpu.sh"
    if [ ! -f "$envd" ]; then
        _warn "not found: $envd - cannot verify GPU env resolution"
        return
    fi
    local glx gbm setup
    eval "$(
        unset __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND GPU_SETUP
        # shellcheck disable=SC1090
        source "$envd" >/dev/null 2>&1
        printf 'glx=%q\n' "${__GLX_VENDOR_LIBRARY_NAME:-}"
        printf 'gbm=%q\n' "${GBM_BACKEND:-}"
        printf 'setup=%q\n' "${GPU_SETUP:-}"
    )"
    if [ -n "$glx" ] || [ -n "$gbm" ]; then
        _fail "01-gpu.sh resolves to GPU_SETUP=$setup with __GLX_VENDOR_LIBRARY_NAME='$glx' GBM_BACKEND='$gbm' - NVIDIA is being forced session-wide"
    else
        _pass "01-gpu.sh resolves to GPU_SETUP=$setup with no session-wide NVIDIA forcing (Intel stays default compositor GPU)"
    fi

    local offload_hits
    offload_hits=$(grep -rlE '__GLX_VENDOR_LIBRARY_NAME=nvidia|GBM_BACKEND=nvidia-drm' \
        "$XDG_DATA_HOME/hypr" 2>/dev/null)
    if [ -n "$offload_hits" ]; then
        _fail "session-wide NVIDIA GPU env forcing found in $offload_hits"
    fi
}

check_lua_runtime() {
    if bin_present lua5.5 || bin_present lua; then
        _pass "Lua interpreter present"
    else
        _fail "no lua interpreter found"
    fi

    local collision
    collision=$(detect_lua_abi_collision)
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        _warn "Lua ABI coexistence: Hyprland links liblua.so.5.5 directly, libinput.so (an official Arch package, not foreign/AUR) links $collision for its own optional Lua quirks support - both export unversioned lua_*/luaL_* symbols into the same process. Evidence-gathered, not proven to cause any actual symptom (unrelated to the Aquamarine SIGSEGV crash's stack frames). Full dependency-chain evidence: install.sh --diagnose. Details: docs/personal-fork/ARCHITECTURE.md."
    elif [ "$rc" -eq 1 ]; then
        _pass "no Lua 5.4/5.5 symbol collision detected in Hyprland's link graph"
    else
        _warn "could not evaluate Lua ABI collision (Hyprland binary or ldd unavailable)"
    fi

    for mod in ssl argparse dkjson socket lfs lgi; do
        local interp
        interp=$(command -v lua5.5 || command -v lua)
        if "$interp" -e "require('$mod')" >/dev/null 2>&1; then
            _pass "Lua module '$mod' loads"
        else
            local err
            err=$("$interp" -e "require('$mod')" 2>&1 | tail -1)
            if [ "$mod" = "lgi" ]; then
                _warn "Lua module 'lgi' fails to load: $err (see docs/personal-fork/ARCHITECTURE.md - known Lua 5.5 incompatibility; verified non-fatal: open.lua/dconf.lua/batterynotify.lua each os.exit(0)/pcall around it, and color.set.sh's load_dconf_kdeglobals no longer lets that propagate as a fatal wallbash-render abort - see the 'gray-screen startup failure' section)"
            else
                _fail "Lua module '$mod' fails to load: $err"
            fi
        fi
    done
}

check_required_binaries() {
    # hyq and app2unit are HARD runtime dependencies - their absence is a
    # FAIL, not a warning. hyq: theme.switch.sh, color/hypr.sh, waybar.py,
    # wallbash/scripts/swaync.sh all call it directly (installer/
    # theme.manifest). app2unit: Configs/.local/lib/hyde/app.sh execs it
    # unconditionally, and every daemon start_up.lua launches (Waybar,
    # wallpaper, hypridle, hyprpolkitagent, config watcher, battery-notify,
    # notifications) goes through it - its absence is HyDE's actual
    # gray-screen root cause, see docs/personal-fork/ARCHITECTURE.md.
    # awww is the default wallpaper backend (schema/config.toml) with no
    # fallback in wallpaper.awww.sh. install.sh --install/--repair stop
    # before runtime init when hyq is missing; build hyq/app2unit
    # deterministically with installer/build-hyq.sh / build-app2unit.sh.
    local bins=(waybar rofi swaync-client hypridle hyprlock jq hyq magick parallel app2unit awww)
    for b in "${bins[@]}"; do
        if bin_present "$b"; then
            _pass "binary present: $b"
        else
            _fail "binary missing: $b"
        fi
    done
    if bin_present hyq && ! hyq --help >/dev/null 2>&1; then
        _fail "hyq is on PATH but 'hyq --help' does not exit cleanly - treat it as absent until this is fixed"
    fi
    local optional=(wlogout)
    for b in "${optional[@]}"; do
        if bin_present "$b"; then
            _pass "binary present: $b"
        else
            _warn "binary missing: $b (see installer/packages.manifest)"
        fi
    done
}

check_portals() {
    if pkg_installed xdg-desktop-portal-hyprland; then
        _pass "xdg-desktop-portal-hyprland installed"
    else
        _fail "xdg-desktop-portal-hyprland not installed"
    fi
    if pkg_installed xdg-desktop-portal-gtk; then
        _pass "xdg-desktop-portal-gtk installed"
    else
        _warn "xdg-desktop-portal-gtk not installed (GTK file pickers may fail)"
    fi
}

check_runtime_state() {
    local theme_css="$XDG_CONFIG_HOME/swaync/theme.css"
    if [ -f "$theme_css" ]; then
        _pass "swaync/theme.css exists"
    else
        _warn "swaync/theme.css missing - run installer/runtime.sh (via --install/--repair) to generate it"
    fi
    local themes_dir="$XDG_CONFIG_HOME/hyde/themes"
    if [ -d "$themes_dir" ] && [ -n "$(find "$themes_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]; then
        _pass "at least one HyDE theme is installed ($themes_dir)"
    else
        _warn "no theme under $themes_dir - wallbash has nothing to generate colors from"
    fi
}

check_current_session() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        _pass "currently running inside a Hyprland session"
    else
        _pass "not currently inside Hyprland (expected if running from KDE/TTY) - session: ${XDG_SESSION_TYPE:-unknown}/${XDG_CURRENT_DESKTOP:-unknown}"
    fi
}

run_all_checks() {
    check_arch
    check_not_root
    check_xdg
    check_hyprland
    check_uwsm
    check_display_manager
    check_kde_coexistence
    check_gpu
    check_gpu_env_leak
    check_lua_runtime
    check_required_binaries
    check_portals
    check_runtime_state
    check_current_session

    echo
    log_info "preflight summary: $PF_PASS pass, $PF_WARN warn, $PF_FAIL fail"
    [ "$PF_FAIL" -eq 0 ]
}

if [ "${1:-}" != "--source-only" ]; then
    run_all_checks
fi
