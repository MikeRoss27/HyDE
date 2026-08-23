#!/usr/bin/env bash
# installer/build-grimblast.sh - deterministic, confirmation-gated install of
# `grimblast` (hyprwm/contrib) from a pinned upstream commit.
#
# grimblast is the screenshot capture helper every screenshot keybind
# (MOD+P, MOD+CTRL+P, MOD+ALT+P, Print) depends on unconditionally - see
# Configs/.local/lib/hyde/screenshot.sh, which execs
# "$LIB_DIR/hyde/screenshot/grimblast" with no existence check. It was
# fetched as a raw blob at deploy time by upstream HyDE's now-deleted
# Scripts/; nothing in this fork's own installer ever fetched it, so
# every screenshot keybind fails silently ("No such file or directory")
# on a fresh machine. hyprwm/contrib has no tags/releases to speak of (one
# old v0.1 tag) - pinning HEAD after reviewing the script's actual content
# (plain bash, grim/slurp/hyprctl/jq/notify-send/wl-copy wrapping, no
# network calls, no obfuscation) is the correct call here, same as this
# installer already does for hyq/app2unit.
#
# This script:
#   - never runs sudo, never installs/removes pacman packages
#   - clones and installs ONLY the pinned commit below, after showing the
#     exact plan and asking for confirmation
#   - installs only Configs/.local/lib/hyde/screenshot/grimblast's real
#     runtime target: ~/.local/lib/hyde/screenshot/grimblast (the exact
#     path screenshot.sh already execs)
#   - is idempotent: a second run with the same pin is a no-op unless
#     --force is passed
#
# Separately required (official-repo packages, not fetched here - see
# installer/packages.manifest): hyprpicker (freeze-frame selection),
# wl-clipboard (wl-copy, used by every grimblast copy/copysave action).
#
# Usage: installer/build-grimblast.sh [--force]
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

refuse_root

# Pinned upstream identity. Update deliberately, after reviewing the diff
# upstream, not automatically. `GB_COMMIT` is verified against the actual
# checked-out HEAD below - a moved/re-pointed ref is refused, not silently
# followed.
GB_REPO="https://github.com/hyprwm/contrib"
GB_REF="main"
GB_COMMIT="57baf317e5196a8286b80976771ef55febad8660"

BUILD_ROOT="$INSTALLER_STATE_DIR/grimblast-build"
SRC_DIR="$BUILD_ROOT/src"
INSTALL_TARGET_DIR="$HOME/.local/lib/hyde/screenshot"
INSTALL_TARGET="$INSTALL_TARGET_DIR/grimblast"
INSTALL_BIN_DIR="$HOME/.local/bin"
MARKER="$INSTALLER_STATE_DIR/grimblast.built-commit"

force=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        *) die "build-grimblast.sh: unknown argument: $arg" ;;
    esac
done

if [ "$force" -eq 0 ] && [ -x "$INSTALL_TARGET" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$GB_COMMIT" ]; then
    log_skip "grimblast already installed from the pinned commit ($GB_COMMIT) at $INSTALL_TARGET - nothing to do (use --force to reinstall)"
    exit 0
fi

log_info "=== grimblast install plan ==="
log_info "source:       $GB_REPO"
log_info "pinned ref:   $GB_REF"
log_info "pinned commit: $GB_COMMIT"
log_info "build dir:    $SRC_DIR (this installer's own state dir, not your repo checkout)"
log_info "install target: $INSTALL_TARGET - never sudo"
log_info "no compiler needed: upstream is a single plain-bash script"
log_info "still required separately (official repo, see installer/packages.manifest):"
log_info "  hyprpicker    - freeze-frame area selection (MOD+CTRL+P)"
log_info "  wl-clipboard  - wl-copy, used by every copy/copysave action"
echo

if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[dry-run] would clone $GB_REPO @ $GB_REF, verify commit == $GB_COMMIT, install to $INSTALL_TARGET"
    exit 0
fi

if ! confirm "Clone the pinned grimblast commit above and install it now (network, no sudo, no compilation)?"; then
    log_skip "grimblast install declined"
    exit 0
fi

ensure_dir "$INSTALLER_STATE_DIR"
rm -rf "$SRC_DIR"
ensure_dir "$BUILD_ROOT"

log_info "cloning $GB_REPO @ $GB_REF ..."
if ! git clone --quiet "$GB_REPO" "$SRC_DIR"; then
    die "git clone failed"
fi

actual_commit=$(git -C "$SRC_DIR" rev-parse HEAD)
if [ "$actual_commit" != "$GB_COMMIT" ]; then
    rm -rf "$SRC_DIR"
    die "commit identity check failed: expected $GB_COMMIT, got $actual_commit for ref $GB_REF (upstream moved - refusing to install an unverified commit; update the pin in installer/build-grimblast.sh only after reviewing the diff)"
fi
log_ok "commit identity verified: $actual_commit"

[ -f "$SRC_DIR/grimblast/grimblast" ] || die "expected file missing from checkout: $SRC_DIR/grimblast/grimblast (upstream layout changed - update this script after reviewing the diff)"

ensure_dir "$INSTALL_TARGET_DIR"
install -m 755 "$SRC_DIR/grimblast/grimblast" "$INSTALL_TARGET"
ensure_dir "$INSTALL_BIN_DIR"
ln -sfT "$INSTALL_TARGET" "$INSTALL_BIN_DIR/grimblast"
printf '%s\n' "$GB_COMMIT" >"$MARKER"
log_ok "installed grimblast -> $INSTALL_TARGET (from commit $GB_COMMIT), symlinked at $INSTALL_BIN_DIR/grimblast"

if command -v hyprpicker >/dev/null 2>&1; then
    log_ok "hyprpicker present (freeze-frame selection will work)"
else
    log_warn "hyprpicker not installed - MOD+CTRL+P (frozen selection) will fail; add it via installer/packages.manifest + install.sh --install"
fi

if command -v wl-copy >/dev/null 2>&1; then
    log_ok "wl-copy present (clipboard copy will work)"
else
    log_warn "wl-copy (wl-clipboard) not installed - every screenshot copy/copysave action will fail; add it via installer/packages.manifest + install.sh --install"
fi
