#!/usr/bin/env bash
# installer/lib.sh - shared helpers for the personal-fork installer.
# Sourced by install.sh and every installer/*.sh stage. Never executed
# directly.

# --- output -----------------------------------------------------------

_c_red=$'\033[31m'; _c_yellow=$'\033[33m'; _c_green=$'\033[32m'; _c_blue=$'\033[34m'; _c_reset=$'\033[0m'
[ -t 1 ] || { _c_red=""; _c_yellow=""; _c_green=""; _c_blue=""; _c_reset=""; }

log_info()  { printf '%s[..]%s %s\n' "$_c_blue"   "$_c_reset" "$*"; }
log_ok()    { printf '%s[ok]%s %s\n' "$_c_green"  "$_c_reset" "$*"; }
log_warn()  { printf '%s[!!]%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
log_err()   { printf '%s[XX]%s %s\n' "$_c_red"    "$_c_reset" "$*" >&2; }
log_skip()  { printf '%s[--]%s %s\n' "$_c_blue"   "$_c_reset" "$*"; }

die() { log_err "$*"; exit 1; }

# --- environment --------------------------------------------------------

REPO_ROOT=${REPO_ROOT:-$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
export REPO_ROOT
INSTALLER_DIR="$REPO_ROOT/installer"
export INSTALLER_DIR

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}

INSTALLER_STATE_DIR="$XDG_STATE_HOME/hyde-installer"
INSTALLER_RUN_ID=${INSTALLER_RUN_ID:-$(date +%Y%m%d-%H%M%S)}
INSTALLER_BACKUP_DIR="$INSTALLER_STATE_DIR/backups/$INSTALLER_RUN_ID"
INSTALLER_MANIFEST_LOG="$INSTALLER_STATE_DIR/deploy-manifest.log"

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}

refuse_root() {
    if [ "$(id -u)" -eq 0 ]; then
        die "Do not run this installer as root. It requests sudo itself, only for the one pacman step, after showing you exactly what it will install."
    fi
}

# --- confirmation ---------------------------------------------------------

# confirm "question" -> 0 (yes) / 1 (no). Never auto-yes for anything
# destructive; ASSUME_YES only applies to prompts the caller explicitly
# marks safe by passing --assume-safe.
confirm() {
    local question=$1 assume_safe=${2:-}
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would ask: $question"
        return 1
    fi
    if [ "$ASSUME_YES" -eq 1 ] && [ "$assume_safe" = "--assume-safe" ]; then
        log_info "$question -> yes (--yes)"
        return 0
    fi
    local reply
    printf '%s [y/N] ' "$question" >&2
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# --- filesystem helpers -----------------------------------------------

ensure_dir() {
    local d=$1
    if [ "$DRY_RUN" -eq 1 ]; then
        [ -d "$d" ] || log_info "[dry-run] would mkdir -p $d"
    else
        mkdir -p "$d"
    fi
}

# backup_then_write <target> <content-source-file>
# Backs up an existing target (file or symlink) before it is replaced, and
# appends an entry to the run's manifest log so rollback can restore it.
# Never touches a target that isn't already tracked as ours unless it
# differs from what we're about to write.
backup_and_stage() {
    local target=$1
    if [ -e "$target" ] || [ -L "$target" ]; then
        local rel backup_path
        rel=${target#"$HOME"/}
        backup_path="$INSTALLER_BACKUP_DIR/$rel"
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[dry-run] would back up $target -> $backup_path"
        else
            mkdir -p "$(dirname "$backup_path")"
            cp -a "$target" "$backup_path"
            printf '%s\t%s\t%s\n' "$(date -Iseconds)" "$target" "$backup_path" >>"$INSTALLER_MANIFEST_LOG"
        fi
    fi
}

# deploy_one <src-relative-to-Configs> <dest-absolute>
# Copies a single file, backing up any existing destination first. Creates
# parent dirs. Idempotent: a no-op (but still logged) if content is already
# identical.
deploy_one() {
    local src=$1 dest=$2
    local src_abs="$REPO_ROOT/Configs/$src"

    [ -e "$src_abs" ] || { log_err "manifest entry missing from repo: $src"; return 1; }

    if [ -e "$dest" ] && cmp -s "$src_abs" "$dest" 2>/dev/null; then
        log_skip "$dest (unchanged)"
        return 0
    fi

    backup_and_stage "$dest"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would deploy $src -> $dest"
        return 0
    fi

    ensure_dir "$(dirname "$dest")"
    install -m "$(stat -c '%a' "$src_abs")" "$src_abs" "$dest"
    log_ok "deployed $dest"
}

# --- Lua ABI collision detection ---------------------------------------

# Returns 0 (collision present) / 1 (clean) and prints a human summary.
detect_lua_abi_collision() {
    local hyprland_bin="/usr/bin/Hyprland"
    [ -x "$hyprland_bin" ] || return 2

    local hy_lua libinput_so
    hy_lua=$(ldd "$hyprland_bin" 2>/dev/null | awk '/liblua\.so\./{print $3; exit}')
    libinput_so=$(ldd "$hyprland_bin" 2>/dev/null | awk '/libinput\.so\./{print $3; exit}')
    [ -n "$hy_lua" ] || return 2

    local other_lua=""
    if [ -n "$libinput_so" ] && command -v readelf >/dev/null 2>&1; then
        other_lua=$(readelf -d "$libinput_so" 2>/dev/null | grep -oE 'liblua5\.[0-9]\.so\.[0-9.]+' | head -1)
    fi
    [ -n "$other_lua" ] || return 1

    printf '%s' "$other_lua"
    return 0
}

# --- package.installed check --------------------------------------------

pkg_installed() { pacman -Qq "$1" >/dev/null 2>&1; }
bin_present()   { command -v "$1" >/dev/null 2>&1; }

# --- theme completeness (see installer/theme.manifest) --------------------

# theme_missing_required <theme-dir> - prints one missing path per line
# (relative to theme-dir) for every REQUIRED entry in theme.manifest that
# is absent. Prints nothing and returns 0 when the theme is complete.
theme_missing_required() {
    local theme_dir=$1
    local manifest="$REPO_ROOT/installer/theme.manifest"
    local missing=0
    local path kind rest
    while IFS='|' read -r path kind rest; do
        path=$(printf '%s' "$path" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        kind=$(printf '%s' "$kind" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        [ -n "$path" ] || continue
        case "$path" in \#*) continue ;; esac
        [ "$kind" = "REQUIRED" ] || continue
        if [[ $path == */ ]]; then
            [ -d "$theme_dir/${path%/}" ] || { printf '%s\n' "$path"; missing=1; }
        else
            [ -e "$theme_dir/$path" ] || { printf '%s\n' "$path"; missing=1; }
        fi
    done < <(grep -v '^[[:space:]]*#' "$manifest" | grep -v '^[[:space:]]*$')
    return $missing
}

# --- semantic runtime-output checks (existence alone is not enough) ------
# Shared by installer/runtime.sh (post-render) and installer/validate.sh
# (the graphical-session readiness gate) so both apply the same definition
# of "actually generated", not just `test -e`.

# check_nonempty_file <path> <label> - exists AND non-empty.
check_nonempty_file() {
    local path=$1 label=$2
    if [ -s "$path" ]; then
        log_ok "$label exists and is non-empty ($path)"
        return 0
    fi
    if [ -e "$path" ]; then
        log_err "$label exists but is EMPTY: $path"
    else
        log_err "$label missing: $path"
    fi
    return 1
}

# check_no_unresolved_wallbash_tokens <generated-css-path> - a
# <wallbash_...> placeholder surviving in generated output means the sed
# substitution pass in color.set.sh never ran against this file (or ran
# against different variables) - the file exists and is non-empty but is
# not actually usable.
check_no_unresolved_wallbash_tokens() {
    local path=$1
    [ -f "$path" ] || return 0
    local hits
    hits=$(grep -c '<wallbash_' "$path" 2>/dev/null || true)
    if [ -n "$hits" ] && [ "$hits" -gt 0 ]; then
        log_err "$path still contains $hits unresolved <wallbash_*> placeholder(s) - colour substitution did not complete"
        return 1
    fi
    log_ok "$path has no unresolved wallbash placeholders"
    return 0
}

# check_css_imports_resolve <generated-css-path> - every `@import "..."`
# in the rendered CSS must point at a file that actually exists; a dangling
# import (e.g. gtk.css never rendered) is silently ignored by CSS parsers
# at runtime, so `test -e` on theme.css alone would not have caught it.
check_css_imports_resolve() {
    local path=$1
    [ -f "$path" ] || return 0
    local ok=0
    local import_path
    while IFS= read -r import_path; do
        [ -n "$import_path" ] || continue
        if [ ! -e "$import_path" ]; then
            log_err "$path imports a source that does not exist: $import_path"
            ok=1
        fi
    done < <(grep -oE '@import[[:space:]]+"[^"]+"' "$path" | sed -E 's/@import[[:space:]]+"([^"]+)"/\1/')
    [ "$ok" -eq 0 ] && log_ok "$path: all @import paths resolve"
    return "$ok"
}

# check_json_include_paths_resolve <includes.json-path> - every entry in
# the "include" array must point at a file that exists; a stale entry
# (e.g. left over from committed defaults with a different $HOME baked in)
# is silently skipped by waybar at runtime ("Unable to find resource
# file"), so the bar quietly loses modules with no error - not caught by
# `test -e` on includes.json itself.
check_json_include_paths_resolve() {
    local path=$1
    [ -f "$path" ] || return 0
    local ok=0 p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ ! -e "$p" ]; then
            log_err "$path includes a module path that does not exist: $p"
            ok=1
        fi
    done < <(jq -r '.include[]?' "$path" 2>/dev/null)
    [ "$ok" -eq 0 ] && log_ok "$path: all include[] paths resolve"
    return "$ok"
}

# check_hypr_colour_state_complete - same completeness definition as
# globalcontrol.sh's wallbash_state_is_complete(), reimplemented here so
# read-only callers (validate.sh) never need to source the live runtime
# environment - which has mkdir side effects - just to check it.
check_hypr_colour_state_complete() {
    local f
    for f in "$XDG_CONFIG_HOME/hypr/themes/colors.conf" \
        "$XDG_STATE_HOME/hyde/lua_state/colors.lua" \
        "$XDG_STATE_HOME/hyde/lua_state/ui.lua"; do
        [ -s "$f" ] || return 1
    done
    return 0
}

# hyq_gate - logs a clear, consistent message and returns 1 when hyq is not
# on PATH. hyq is a hard runtime dependency (theme.switch.sh, color/hypr.sh,
# waybar.py, wallbash/scripts/swaync.sh all invoke it) - callers must treat
# a nonzero return as fatal, not a soft warning.
hyq_gate() {
    if bin_present hyq; then
        return 0
    fi
    log_err "hyq not found on PATH - this is a hard runtime dependency (theme.switch.sh, color/hypr.sh, waybar.py, wallbash/scripts/swaync.sh all call it directly)"
    log_err "build it deterministically: $INSTALLER_DIR/build-hyq.sh (clones a pinned commit, asks for confirmation, installs only to ~/.local/bin, never sudo)"
    return 1
}

# app2unit_gate - logs a clear, consistent message and returns 1 when
# app2unit is not on PATH. app2unit is a hard runtime dependency of
# EVERY daemon start_up.lua launches (Waybar, wallpaper, hypridle,
# hyprpolkitagent/polkitkdeauth, the config watcher, battery-notify,
# nm-applet/blueman-applet dispatched via hyde-shell, notifications) -
# Configs/.local/lib/hyde/app.sh execs it unconditionally whenever
# /run/systemd/system exists. Its absence is silent at the Hyprland level
# (the forked shell just exits 127, no systemd unit is ever created, so
# nothing reaches the journal) - this is HyDE's actual gray-screen root
# cause on a machine where app2unit was never installed. See
# docs/personal-fork/ARCHITECTURE.md.
app2unit_gate() {
    if bin_present app2unit; then
        return 0
    fi
    log_err "app2unit not found on PATH - hard runtime dependency of every daemon start_up.lua launches (Waybar, wallpaper, hypridle, hyprpolkitagent, config watcher, battery-notify, notifications all go through Configs/.local/lib/hyde/app.sh -> app2unit)"
    log_err "without it, hyde-shell app ... fails silently (exit 127, no systemd unit ever created) - this is the actual cause of a gray Hyprland screen with a working compositor but no Waybar/wallpaper"
    log_err "build it deterministically: $INSTALLER_DIR/build-app2unit.sh (clones a pinned commit, asks for confirmation, installs only to ~/.local/bin, never sudo)"
    return 1
}
