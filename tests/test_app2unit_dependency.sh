#!/usr/bin/env sh
# app2unit is a hard runtime dependency of Configs/.local/lib/hyde/app.sh -
# every daemon start_up.lua launches (Waybar, wallpaper, hypridle,
# hyprpolkitagent, config watcher, battery-notify, notifications) goes
# through `hyde-shell app ...` -> app.sh -> app2unit. Its absence was found
# to be silent: the forked shell just exits 127 with no systemd unit ever
# created, so nothing reaches the journal - the actual root cause of a gray
# Hyprland screen with a working compositor but no Waybar/wallpaper.
#
# Regression coverage for both halves of the fix:
#   1. app.sh must fail LOUDLY (clear stderr message, exit 127, a line in
#      the startup log) when app2unit is missing, instead of silently.
#   2. the dependency must be documented and checkable ahead of time
#      (packages.manifest, installer/lib.sh's app2unit_gate,
#      installer/validate.sh's readiness gate) so install.sh --check
#      catches it before another gray-screen login.

. "$(dirname -- "$0")/lib/common.sh"

wrapper="$REPO_ROOT/Configs/.local/lib/hyde/app.sh"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

# A PATH with no app2unit anywhere on it (only a minimal set of the
# binaries the shell itself needs), exercising the systemd-present branch.
minimal_path=""
for d in /usr/bin /bin; do
    [ -d "$d" ] && minimal_path="$minimal_path:$d"
done
minimal_path=${minimal_path#:}

fake_home=$(mktemp -d)
trap 'rm -rf "$fixture" "$fake_home"' EXIT HUP INT TERM

if [ -d /run/systemd/system ]; then
    output=$(PATH="$minimal_path" HOME="$fake_home" XDG_STATE_HOME="$fake_home/.local/state" "$wrapper" -- true 2>&1)
    status=$?

    [ "$status" -eq 127 ] || fail "app.sh with no app2unit on PATH exited $status, expected 127"
    printf '%s\n' "$output" | grep -qi "app2unit not found" ||
        fail "app.sh did not print a clear 'app2unit not found' message on stderr"

    log="$fake_home/.local/state/hyde/log/startup.log"
    [ -f "$log" ] || fail "app.sh did not write $log"
    grep -q "app2unit not found" "$log" 2>/dev/null ||
        fail "$log does not record the app2unit-missing dispatch failure"
else
    skip "no /run/systemd/system on this machine - app.sh's non-systemd fallback path does not involve app2unit"
fi

lib="$REPO_ROOT/installer/lib.sh"
grep -q '^app2unit_gate()' "$lib" || fail "installer/lib.sh: app2unit_gate() helper missing"

validate="$REPO_ROOT/installer/validate.sh"
grep -q 'bin_present app2unit' "$validate" || fail "installer/validate.sh: no app2unit check found"
grep -q '_gate_fail "app2unit missing' "$validate" ||
    fail "installer/validate.sh: app2unit is not a hard [READY]/[NOT READY] gate condition"

manifest="$REPO_ROOT/installer/packages.manifest"
grep -qE '^app2unit\s' "$manifest" || fail "installer/packages.manifest: app2unit not documented"
grep -qE '^awww\s' "$manifest" || fail "installer/packages.manifest: awww (default wallpaper backend) not documented"

[ -x "$REPO_ROOT/installer/build-app2unit.sh" ] || fail "installer/build-app2unit.sh missing or not executable"

finish
