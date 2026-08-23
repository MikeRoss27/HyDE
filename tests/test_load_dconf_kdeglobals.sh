#!/usr/bin/env sh
# Regression tests for load_dconf_kdeglobals() in
# Configs/.local/lib/hyde/color.set.sh - see docs/personal-fork/
# ARCHITECTURE.md "Gray-screen startup failure" for the investigation.
#
# Prior bug: the function's return value was accidentally dictated by its
# LAST statement, `[[ -n $HYPRLAND_INSTANCE_SIGNATURE ]] && lua
# shaders.lua --reload` - false (exit 1) any time this runs outside a live
# Hyprland session, i.e. ALWAYS during `install.sh --repair`, regardless
# of whether color/dconf.lua/lgi/anything else actually failed. The caller
# then aborted wallbash rendering entirely on that spurious failure, which
# is what made `install.sh --repair` fail with "load_dconf_kdeglobals
# failed" even though dconf.lua itself was already degrading gracefully.
#
# The function is extracted verbatim from color.set.sh (same technique as
# test_colour_pass.sh's fn_wallbash extraction) and run against stubs, so a
# change that keeps the shape but reintroduces the bug is caught.

. "$(dirname -- "$0")/lib/common.sh"

color_set="$REPO_ROOT/Configs/.local/lib/hyde/color.set.sh"
[ -f "$color_set" ] || {
    fail "missing $color_set"
    finish
}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

# A fake `lua` on PATH: given a script path whose content is a bare exit
# code, prints a marker and exits with that code - stands in for both
# color/dconf.lua and shaders.lua without needing real lgi or Hyprland.
mkdir -p "$work_dir/bin"
cat >"$work_dir/bin/lua" <<'EOF'
#!/usr/bin/env bash
script="$1"
code=0
[ -f "$script" ] && code=$(cat "$script")
printf 'lua ran: %s\n' "$script"
exit "${code:-0}"
EOF
chmod +x "$work_dir/bin/lua"

##
# Assembles an isolated run of load_dconf_kdeglobals(), extracted verbatim
# from color.set.sh, against stubs for everything it touches.
#
# Arguments:
#   $1  stand directory
#   $2  exit status the color/hypr.sh stub reports (the REQUIRED step)
#   $3  exit status the color/dconf.lua stub reports (OPTIONAL, via fake lua)
#   $4  HYDE_KDEGLOBALS_FIX value
# Outputs:
#   The path of the script to run
##
build_stand() {
    local stand="$1" hypr_exit="$2" dconf_exit="$3" kdeglobals_fix="$4"
    mkdir -p "$stand/share/hyde" "$stand/lib/hyde/color" "$stand/config"

    printf 'GTK_THEME=stub\n' >"$stand/share/hyde/env-theme"

    # Stub color/hypr.sh in place of the real one (which needs hyq/hyde-shell
    # to be meaningfully exercised) - only its success/failure matters here.
    # It is `source`d by load_dconf_kdeglobals, so it must `return`, not
    # `exit` - an `exit` here would terminate the whole test harness script,
    # not just this stand-in for the sourced file.
    printf '%s\n' '#!/usr/bin/env bash' "return $hypr_exit 2>/dev/null || exit $hypr_exit" >"$stand/lib/hyde/color/hypr.sh"
    chmod +x "$stand/lib/hyde/color/hypr.sh"

    # "Scripts" for the fake lua above: their content IS the exit code.
    printf '%s' "$dconf_exit" >"$stand/lib/hyde/color/dconf.lua"
    printf '0' >"$stand/lib/hyde/shaders.lua"

    cat >"$stand/run.sh" <<STAND
#!/usr/bin/env bash
PATH="$work_dir/bin:\$PATH"
SHARE_DIR="$stand/share"
LIB_DIR="$stand/lib"
XDG_CONFIG_HOME="$stand/config"
HYDE_KDEGLOBALS_FIX=$kdeglobals_fix
dcol_mode="dark"
print_log() { printf 'log: %s\n' "\$*" >&2; }
toml_write() { printf 'toml_write %s\n' "\$*" >>"$stand/kdeglobals.calls"; }
rgba_to_rgb() { printf ''; }
$(sed -n '/^load_dconf_kdeglobals() {/,/^}$/p' "$color_set")
load_dconf_kdeglobals
printf 'status=%s\n' "\$?"
STAND
    chmod +x "$stand/run.sh"
    printf '%s\n' "$stand/run.sh"
}

# --- 1 & 3: an optional color/dconf.lua (lgi) failure must not be fatal ---
stand_lgi="$work_dir/lgi-broken"
output_lgi=$(bash "$(build_stand "$stand_lgi" 0 1 0)" 2>&1)
case "$output_lgi" in
*'status=0'*) ;;
*) fail "an optional color/dconf.lua (lgi) failure aborted load_dconf_kdeglobals: $output_lgi" ;;
esac
case "$output_lgi" in
*'optional cosmetic desktop integration'*) ;;
*) fail "an optional dconf.lua failure was not logged as a clear, non-fatal warning: $output_lgi" ;;
esac

# --- 2: HYDE_KDEGLOBALS_FIX=0 must not touch kdeglobals at all ---
stand_nofix="$work_dir/kdeglobals-fix-0"
output_nofix=$(bash "$(build_stand "$stand_nofix" 0 0 0)" 2>&1)
[ -f "$stand_nofix/kdeglobals.calls" ] &&
    fail "HYDE_KDEGLOBALS_FIX=0 still wrote to kdeglobals: $(cat "$stand_nofix/kdeglobals.calls")"
case "$output_nofix" in
*'status=0'*) ;;
*) fail "HYDE_KDEGLOBALS_FIX=0 with no other failures did not succeed: $output_nofix" ;;
esac

# Regression guard for the above: HYDE_KDEGLOBALS_FIX=1 (the default) must
# still apply the fix, so "no writes with FIX=0" isn't true merely because
# the whole block was deleted.
stand_fix="$work_dir/kdeglobals-fix-1"
output_fix=$(bash "$(build_stand "$stand_fix" 0 0 1)" 2>&1)
[ -f "$stand_fix/kdeglobals.calls" ] ||
    fail "HYDE_KDEGLOBALS_FIX=1 did not write to kdeglobals at all: $output_fix"

# --- 4: a genuinely required failure must still be fatal ---
# color/hypr.sh renders $XDG_STATE_HOME/hyde/lua_state/ui.lua, one of the
# three files installer/lib.sh:check_hypr_colour_state_complete() requires.
stand_required="$work_dir/hypr-sh-fails"
output_required=$(bash "$(build_stand "$stand_required" 1 0 0)" 2>&1)
case "$output_required" in
*'status=1'*) ;;
*) fail "a failed color/hypr.sh (the REQUIRED step) was not propagated as fatal: $output_required" ;;
esac

# The caller in color.set.sh must still treat a nonzero return as fatal -
# only the function's own return-value correctness changed, not the
# caller's fatal handling of it (no 'command || true' hack expected).
grep -q 'if ! load_dconf_kdeglobals; then' "$color_set" ||
    fail "$color_set no longer gates wallbash rendering on load_dconf_kdeglobals - a genuinely required failure could now render templates against an incomplete colour environment"

# --- 5: after a real repair, the generated theme CSS stays valid ---
# installer/lib.sh already defines the exact semantic checks runtime.sh and
# validate.sh use; reuse them here instead of re-implementing "non-empty,
# no unresolved <wallbash_*> tokens, @import targets resolve".
lib_sh="$REPO_ROOT/installer/lib.sh"
waybar_css="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/theme.css"
swaync_css="${XDG_CONFIG_HOME:-$HOME/.config}/swaync/theme.css"
if [ -f "$waybar_css" ] && [ -f "$swaync_css" ]; then
    # shellcheck disable=SC1090
    . "$lib_sh"
    check_nonempty_file "$waybar_css" "waybar theme.css" >/dev/null 2>&1 ||
        fail "$waybar_css is missing/empty after a repair - see whether load_dconf_kdeglobals's fix actually let wallbash rendering complete"
    check_nonempty_file "$swaync_css" "swaync theme.css" >/dev/null 2>&1 ||
        fail "$swaync_css is missing/empty after a repair"
    check_no_unresolved_wallbash_tokens "$waybar_css" >/dev/null 2>&1 ||
        fail "$waybar_css still has unresolved <wallbash_*> placeholders"
    check_no_unresolved_wallbash_tokens "$swaync_css" >/dev/null 2>&1 ||
        fail "$swaync_css still has unresolved <wallbash_*> placeholders"
    check_css_imports_resolve "$swaync_css" >/dev/null 2>&1 ||
        fail "$swaync_css has a dangling @import"
else
    skip "no generated theme.css under \$XDG_CONFIG_HOME yet - run install.sh --repair first to exercise this check"
fi

printf '    load_dconf_kdeglobals: lgi-optional / HYDE_KDEGLOBALS_FIX / required-failure behaviour checked\n'
finish
