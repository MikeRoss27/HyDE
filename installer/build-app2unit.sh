#!/usr/bin/env bash
# installer/build-app2unit.sh - deterministic, confirmation-gated install of
# `app2unit` (Vladimir-csp/app2unit) from a pinned upstream commit.
#
# app2unit is a hard runtime dependency of every daemon start_up.lua
# launches (Waybar, wallpaper, hypridle, hyprpolkitagent, the config
# watcher, battery-notify, notifications - see Configs/.local/lib/hyde/
# app.sh, which execs it unconditionally whenever /run/systemd/system
# exists) and has no official-repo or AUR package. Upstream ships plain
# POSIX shell scripts - no compiler, no build step, just install + symlink
# (see upstream Makefile's install-bin target, mirrored below).
#
# This script:
#   - never runs sudo, never installs/removes pacman packages
#   - clones and installs ONLY the pinned commit below, after showing the
#     exact plan and asking for confirmation
#   - installs only to ~/.local/bin (app2unit plus 6 symlinks: app2unit-open,
#     app2unit-open-scope, app2unit-open-service, app2unit-term,
#     app2unit-term-scope, app2unit-term-service - mirroring upstream's own
#     install-bin target)
#   - is idempotent: a second run with the same pin is a no-op unless
#     --force is passed
#
# Usage: installer/build-app2unit.sh [--force]
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

refuse_root

# Pinned upstream identity. Update deliberately, after reviewing the diff
# upstream, not automatically. `A2U_COMMIT` is verified against the actual
# checked-out HEAD below - a moved/re-pointed tag is refused, not silently
# followed.
A2U_REPO="https://github.com/Vladimir-csp/app2unit"
A2U_REF="v1.4.4"
A2U_COMMIT="47e23ec6ab9e97bbe335c32fb640744a29bf32f7"

BUILD_ROOT="$INSTALLER_STATE_DIR/app2unit-build"
SRC_DIR="$BUILD_ROOT/src"
INSTALL_BIN_DIR="$HOME/.local/bin"
INSTALL_TARGET="$INSTALL_BIN_DIR/app2unit"
MARKER="$INSTALLER_STATE_DIR/app2unit.built-commit"
LINK_NAMES=(app2unit-open app2unit-open-scope app2unit-open-service app2unit-term app2unit-term-scope app2unit-term-service)

force=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        *) die "build-app2unit.sh: unknown argument: $arg" ;;
    esac
done

if [ "$force" -eq 0 ] && [ -x "$INSTALL_TARGET" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$A2U_COMMIT" ]; then
    log_skip "app2unit already installed from the pinned commit ($A2U_COMMIT) at $INSTALL_TARGET - nothing to do (use --force to reinstall)"
    exit 0
fi

log_info "=== app2unit install plan ==="
log_info "source:       $A2U_REPO"
log_info "pinned ref:   $A2U_REF"
log_info "pinned commit: $A2U_COMMIT"
log_info "build dir:    $SRC_DIR (this installer's own state dir, not your repo checkout)"
log_info "install target: $INSTALL_TARGET plus symlinks (${LINK_NAMES[*]}) in $INSTALL_BIN_DIR - never sudo"
log_info "no compiler needed: upstream is plain POSIX shell (app2unit) + man page; install is copy + symlink"
echo

if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[dry-run] would clone $A2U_REPO @ $A2U_REF, verify commit == $A2U_COMMIT, install to $INSTALL_TARGET plus symlinks"
    exit 0
fi

if ! confirm "Clone the pinned app2unit commit above and install it now (network, no sudo, no compilation)?"; then
    log_skip "app2unit install declined"
    exit 0
fi

ensure_dir "$INSTALLER_STATE_DIR"
rm -rf "$SRC_DIR"
ensure_dir "$BUILD_ROOT"

log_info "cloning $A2U_REPO @ $A2U_REF ..."
if ! git clone --quiet --branch "$A2U_REF" "$A2U_REPO" "$SRC_DIR"; then
    die "git clone failed"
fi

actual_commit=$(git -C "$SRC_DIR" rev-parse HEAD)
if [ "$actual_commit" != "$A2U_COMMIT" ]; then
    rm -rf "$SRC_DIR"
    die "commit identity check failed: expected $A2U_COMMIT, got $actual_commit for ref $A2U_REF (tag may have moved upstream - refusing to install an unverified commit; update the pin in installer/build-app2unit.sh only after reviewing the diff)"
fi
log_ok "commit identity verified: $actual_commit"

[ -f "$SRC_DIR/app2unit" ] || die "expected file missing from checkout: $SRC_DIR/app2unit (upstream layout changed - update this script after reviewing the diff)"

ensure_dir "$INSTALL_BIN_DIR"
install -m 755 "$SRC_DIR/app2unit" "$INSTALL_TARGET"
for link in "${LINK_NAMES[@]}"; do
    ln -sfT app2unit "$INSTALL_BIN_DIR/$link"
done
printf '%s\n' "$A2U_COMMIT" >"$MARKER"
log_ok "installed app2unit -> $INSTALL_TARGET (from commit $A2U_COMMIT), plus symlinks: ${LINK_NAMES[*]}"

if "$INSTALL_TARGET" --help >/dev/null 2>&1 || "$INSTALL_TARGET" -h >/dev/null 2>&1; then
    log_ok "app2unit runs cleanly"
else
    log_warn "app2unit was installed but did not exit cleanly on --help/-h - inspect manually before relying on it"
fi
