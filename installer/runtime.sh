#!/usr/bin/env bash
# installer/runtime.sh - runtime state initialization.
#
# Static file copying (deploy.sh) is not enough: HyDE's swaync/waybar/GTK
# theming is generated at runtime by the wallbash pipeline from a
# wallpaper, and this fork's Configs/ ships zero theme/wallpaper content
# (upstream HyDE fetches that separately; deliberately not this fork's
# concern - see docs/personal-fork/ARCHITECTURE.md). Without at least one
# COMPLETE theme directory under ~/.config/hyde/themes/<name>/ (see
# installer/theme.manifest - directory existence alone is not enough), the
# wallbash pipeline cannot produce a usable colour/theme state.
#
# This stage creates/repairs one minimal offline-generated "Default" theme
# (a gradient PNG via ImageMagick - no network - plus a canonical
# hypr.theme) and then runs HyDE's own color.set.sh against it, the same
# code path theme.switch.sh uses. It never re-implements wallbash's
# template logic.
#
# Every step here is fail-fast: a missing hard dependency (hyq) or a failed
# render stops the script with a nonzero exit, it does not degrade to a
# warning and continue - see docs/personal-fork/ARCHITECTURE.md "Runtime
# initialization".
#
# Must run after deploy.sh (needs ~/.local/bin/hyde-shell and
# ~/.local/lib/hyde/* already in place).
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

# Wallbash "skip 'missing directory'" lines whose target path matches one of
# these are components this fork does not install by default (see CLAUDE.md
# "Preferred applications" / DEPENDENCIES.md) - expected, not a problem.
# Anything that does NOT match is a real, unexpected skip and stays visible.
WALLBASH_OPTIONAL_KEYWORDS=(Kvantum kvantum Spicetify spicetify /vim/ .vimrc gtk-4.0 Wallbash-Icon qt5ct qt6ct)

# summarize_wallbash_output <captured-log-file> - re-prints every line
# except "skip 'missing directory'" warnings for known-optional components,
# which are collapsed into one summary line instead of scrolling raw
# per-file warnings (item 4: don't make a minimal install look broken
# because Kvantum/Spicetify/vim/etc. are deliberately absent).
summarize_wallbash_output() {
    local log_file=$1
    local -A optional_seen=()
    local line matched kw
    while IFS= read -r line; do
        matched=""
        if [[ $line == *"skip 'missing directory'"* ]]; then
            for kw in "${WALLBASH_OPTIONAL_KEYWORDS[@]}"; do
                if [[ $line == *"$kw"* ]]; then
                    matched=$kw
                    break
                fi
            done
        fi
        if [ -n "$matched" ]; then
            optional_seen["$matched"]=1
        else
            printf '%s\n' "$line"
        fi
    done <"$log_file"

    if [ "${#optional_seen[@]}" -gt 0 ]; then
        log_skip "optional wallbash targets skipped (component not installed on this minimal fork): ${!optional_seen[*]}"
    fi
}

# theme_repair_default <theme-dir> - fills in ONLY the REQUIRED files this
# installer itself manages for its own generated "Default" theme (never
# called on a foreign/user theme - see runtime_init()). Backs up the whole
# directory first; never overwrites a file that is already present.
theme_repair_default() {
    local theme_dir=$1
    local missing
    missing=$(theme_missing_required "$theme_dir")
    [ -z "$missing" ] && return 0

    log_warn "Default theme at $theme_dir is incomplete - missing: $(printf '%s' "$missing" | tr '\n' ' ')"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would back up $theme_dir then repair the files listed above"
        return 0
    fi

    local backup="$INSTALLER_BACKUP_DIR/theme-Default"
    ensure_dir "$(dirname "$backup")"
    cp -a "$theme_dir" "$backup"
    log_ok "backed up incomplete Default theme -> $backup"

    local rel
    while IFS= read -r rel; do
        case "$rel" in
        wall.set)
            log_info "regenerating offline seed wallpaper (no network) at $theme_dir/wall.png"
            magick -size 1920x1080 'gradient:#1e1e2e-#313244' "$theme_dir/wall.png" \
                || { log_err "magick failed to generate seed wallpaper"; return 1; }
            ln -sf "$theme_dir/wall.png" "$theme_dir/wall.set"
            log_ok "repaired $theme_dir/wall.set"
            ;;
        hypr.theme)
            cp "$SCRIPT_DIR/templates/hypr.theme.default" "$theme_dir/hypr.theme"
            log_ok "repaired $theme_dir/hypr.theme (canonical defaults - installer/templates/hypr.theme.default)"
            ;;
        *)
            log_err "no repair rule defined for missing REQUIRED theme file: $rel (see installer/theme.manifest)"
            return 1
            ;;
        esac
    done <<<"$missing"

    missing=$(theme_missing_required "$theme_dir")
    if [ -n "$missing" ]; then
        log_err "Default theme still incomplete after repair: $(printf '%s' "$missing" | tr '\n' ' ')"
        return 1
    fi
    log_ok "Default theme repaired and complete (installer/theme.manifest)"
    return 0
}

runtime_init() {
    if ! bin_present hyde-shell; then
        log_err "hyde-shell not on PATH (~/.local/bin not in PATH, or deploy.sh hasn't run yet) - stopping before runtime init"
        return 1
    fi

    if ! bin_present magick; then
        log_err "magick (imagemagick) not installed - cannot generate a seed wallpaper or run wallbash. Install it (installer/packages.sh) then re-run: install.sh --repair"
        return 1
    fi
    if ! bin_present parallel; then
        log_err "GNU parallel not installed - color.set.sh needs it to render templates. Install it then re-run: install.sh --repair"
        return 1
    fi

    # hyq is a hard dependency of the theme pipeline this stage is about to
    # run (color/hypr.sh, theme.switch.sh, waybar.py, swaync.sh all call it
    # directly - see installer/theme.manifest). Stop BEFORE touching any
    # theme/colour state rather than let it fail silently mid-render.
    if [ "$DRY_RUN" -ne 1 ] && ! hyq_gate; then
        return 1
    fi

    # hyde-shell init's own code (globalcontrol.sh) is not nounset-clean -
    # relax -u only around the eval, not for the rest of this script.
    set +u
    eval "$(hyde-shell init)"
    set -u
    local hyde_conf_home="${HYDE_CONFIG_HOME:-$XDG_CONFIG_HOME/hyde}"
    local lib_dir="$HOME/.local/lib/hyde"

    local existing
    existing=$(find "$hyde_conf_home/themes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)

    local theme_dir="$hyde_conf_home/themes/Default"
    local managed=0
    if [ -n "$existing" ]; then
        theme_dir="$existing"
        [ "$(basename "$existing")" = "Default" ] && managed=1
        log_skip "a theme already exists ($existing) - not creating a new 'Default'"
    elif [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would create seed theme (wall.set + hypr.theme) at $theme_dir"
        managed=1
    else
        ensure_dir "$theme_dir"
        log_info "generating offline seed wallpaper (no network) at $theme_dir/wall.png"
        magick -size 1920x1080 'gradient:#1e1e2e-#313244' "$theme_dir/wall.png" \
            || { log_err "magick failed to generate seed wallpaper"; return 1; }
        ln -sf "$theme_dir/wall.png" "$theme_dir/wall.set"
        echo 0 >"$theme_dir/.sort"
        cp "$SCRIPT_DIR/templates/hypr.theme.default" "$theme_dir/hypr.theme"
        managed=1
        log_ok "created seed theme: $theme_dir (wall.set + hypr.theme)"
    fi

    if [ "$DRY_RUN" -ne 1 ]; then
        if [ "$managed" -eq 1 ]; then
            theme_repair_default "$theme_dir" || return 1
        else
            local foreign_missing
            foreign_missing=$(theme_missing_required "$theme_dir")
            if [ -n "$foreign_missing" ]; then
                log_warn "theme '$theme_dir' is not managed by this installer and is missing required files: $(printf '%s' "$foreign_missing" | tr '\n' ' ') (see installer/theme.manifest) - not auto-repairing a theme this installer did not create"
            fi
        fi
    fi

    local wall_set="$theme_dir/wall.set"
    [ -e "$wall_set" ] || wall_set="$theme_dir/wall.png"
    [ -e "$wall_set" ] || { log_err "no wallpaper found under $theme_dir"; return 1; }

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would run: HYDE_KDEGLOBALS_FIX=0 $lib_dir/color.set.sh $wall_set"
        return 0
    fi

    log_info "running HyDE's wallbash color pipeline (color.set.sh) against $wall_set"
    log_info "HYDE_KDEGLOBALS_FIX=0 - kdeglobals/Plasma colors are never touched by this installer"
    # color.set.sh only renders theme/*.dcol templates (swaync, waybar,
    # hyprlock, gtk...) when its caller has exported reload_flag=1 - normally
    # done by theme.switch.sh. Calling color.set.sh directly (as here, for a
    # one-shot first-run init) needs the same flag or those templates are
    # silently skipped with no error.
    local render_log render_rc=0
    render_log=$(mktemp)
    if HYDE_KDEGLOBALS_FIX=0 reload_flag=1 "$lib_dir/color.set.sh" "$wall_set" >"$render_log" 2>&1; then
        render_rc=0
    else
        render_rc=$?
    fi
    summarize_wallbash_output "$render_log"
    rm -f "$render_log"

    if [ "$render_rc" -ne 0 ]; then
        log_err "wallbash render failed (exit $render_rc) - see output above"
        return 1
    fi
    log_ok "wallbash render completed"

    # Configs/.config/waybar/style.css and includes/includes.json ship as
    # HyDE's committed defaults with the upstream maintainer's own $HOME
    # baked into absolute paths (@import "/home/khing/..." etc) - deploy.sh
    # only copies files verbatim, it never templates them. Any non---watch
    # invocation of waybar.py resolves both files against the real $HOME on
    # THIS machine (see waybar.py main(): the unconditional tail reached
    # whenever --watch is absent calls update_style()/generate_includes()).
    # Without this step waybar crashes on first login with "Failed to
    # import: ... No such file or directory" against a foreign $HOME.
    if [ ! -x "$lib_dir/waybar.py" ]; then
        log_err "$lib_dir/waybar.py missing or not executable - deploy.sh hasn't run yet?"
        return 1
    fi
    log_info "regenerating waybar style.css/includes.json for \$HOME=$HOME (waybar.py -u)"
    if ! "$lib_dir/waybar.py" -u >/dev/null 2>&1; then
        log_err "waybar.py -u failed - style.css/includes.json may still reference a foreign \$HOME"
        return 1
    fi
    log_ok "waybar style.css/includes.json regenerated"

    # Semantic verification of the actually-required outputs - existence
    # alone (test -e) is not enough, see item 3: empty files and unresolved
    # placeholders both pass -e but are not usable state.
    local fail=0
    check_nonempty_file "$XDG_CONFIG_HOME/swaync/theme.css" "swaync theme.css" || fail=1
    check_nonempty_file "$HOME/.config/waybar/theme.css" "waybar theme.css" || fail=1
    if check_hypr_colour_state_complete; then
        log_ok "hypr colour state complete (colors.conf, lua_state/colors.lua, lua_state/ui.lua)"
    else
        log_err "hypr colour state incomplete (expected all of: \$XDG_CONFIG_HOME/hypr/themes/colors.conf, \$HYDE_STATE_HOME/lua_state/colors.lua, \$HYDE_STATE_HOME/lua_state/ui.lua present and non-empty)"
        fail=1
    fi
    check_no_unresolved_wallbash_tokens "$HOME/.config/waybar/theme.css" || fail=1
    check_no_unresolved_wallbash_tokens "$XDG_CONFIG_HOME/swaync/theme.css" || fail=1
    check_css_imports_resolve "$XDG_CONFIG_HOME/swaync/theme.css" || fail=1
    check_css_imports_resolve "$HOME/.config/waybar/style.css" || fail=1
    check_json_include_paths_resolve "$HOME/.config/waybar/includes/includes.json" || fail=1

    [ "$fail" -eq 0 ]
}

if [ "${1:-}" != "--source-only" ]; then
    refuse_root
    runtime_init
fi
