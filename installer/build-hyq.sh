#!/usr/bin/env bash
# installer/build-hyq.sh - deterministic, confirmation-gated build of `hyq`
# (HyDE-Project/hyprquery) from a pinned upstream commit.
#
# hyq is a hard runtime dependency of this fork's theme pipeline
# (theme.switch.sh, color/hypr.sh, waybar.py, wallbash/scripts/swaync.sh -
# see installer/theme.manifest) with no official-repo or AUR package
# (upstream ships CMake/C++ source only - despite what older notes in this
# repo said, it is NOT a Cargo/Rust project).
#
# This script:
#   - never runs sudo, never installs/removes pacman packages
#   - clones and builds ONLY the pinned commit below, after showing the
#     exact plan and asking for confirmation
#   - installs only a single file, to ~/.local/bin/hyq
#   - is idempotent: a second run with the same pin is a no-op unless
#     --force is passed
#
# Usage: installer/build-hyq.sh [--force]
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

refuse_root

# Pinned upstream identity. Update deliberately, after reviewing the diff
# upstream, not automatically. `HYQ_COMMIT` is verified against the actual
# checked-out HEAD below - a moved/re-pointed tag is refused, not silently
# followed.
HYQ_REPO="https://github.com/HyDE-Project/hyprquery"
HYQ_REF="v0.6.8.r1"
HYQ_COMMIT="50bacf226de0f8d7ea8fdc8f274a1620cfd084a1"

BUILD_ROOT="$INSTALLER_STATE_DIR/hyprquery-build"
SRC_DIR="$BUILD_ROOT/src"
INSTALL_TARGET="$HOME/.local/bin/hyq"
MARKER="$INSTALLER_STATE_DIR/hyq.built-commit"

force=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        *) die "build-hyq.sh: unknown argument: $arg" ;;
    esac
done

if [ "$force" -eq 0 ] && [ -x "$INSTALL_TARGET" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "$HYQ_COMMIT" ]; then
    log_skip "hyq already built from the pinned commit ($HYQ_COMMIT) at $INSTALL_TARGET - nothing to do (use --force to rebuild)"
    exit 0
fi

log_info "=== hyq build plan ==="
log_info "source:       $HYQ_REPO"
log_info "pinned ref:   $HYQ_REF"
log_info "pinned commit: $HYQ_COMMIT"
log_info "build dir:    $SRC_DIR (this installer's own state dir, not your repo checkout)"
log_info "install target: $INSTALL_TARGET (only file written outside $INSTALLER_STATE_DIR; never sudo)"
log_info "build deps needed: a C++23 compiler (gcc>=13 or clang>=16), cmake>=3.19, pkgconf - install with:"
log_info "  sudo pacman -S --needed base-devel cmake pkgconf"
log_info "note: upstream's CMakeLists.txt FetchContent-fetches spdlog (always), and CLI11/nlohmann_json/hyprlang"
log_info "  (unless satisfied by installed packages) from their own GitHub repos during the cmake configure step -"
log_info "  this is genuine additional network activity beyond the initial clone, entirely upstream's build system,"
log_info "  not something this script controls."
echo

missing_build_deps=()
bin_present cmake || missing_build_deps+=(cmake)
bin_present pkg-config || missing_build_deps+=(pkgconf)
{ bin_present cc || bin_present gcc || bin_present clang || bin_present c++ || bin_present g++; } || missing_build_deps+=("a C++ compiler (gcc or clang)")
if [ "${#missing_build_deps[@]}" -gt 0 ]; then
    log_err "missing build dependencies: ${missing_build_deps[*]}"
    log_err "install them yourself (e.g. sudo pacman -S --needed base-devel cmake pkgconf) and re-run this script - it never installs packages for you"
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[dry-run] would clone $HYQ_REPO @ $HYQ_REF, verify commit == $HYQ_COMMIT, build with cmake, install to $INSTALL_TARGET"
    exit 0
fi

if ! confirm "Clone the pinned hyprquery commit above and build it now (network + local compilation, no sudo)?"; then
    log_skip "hyq build declined"
    exit 0
fi

ensure_dir "$INSTALLER_STATE_DIR"
rm -rf "$SRC_DIR"
ensure_dir "$BUILD_ROOT"

log_info "cloning $HYQ_REPO @ $HYQ_REF ..."
if ! git clone --quiet --branch "$HYQ_REF" "$HYQ_REPO" "$SRC_DIR"; then
    die "git clone failed"
fi

actual_commit=$(git -C "$SRC_DIR" rev-parse HEAD)
if [ "$actual_commit" != "$HYQ_COMMIT" ]; then
    rm -rf "$SRC_DIR"
    die "commit identity check failed: expected $HYQ_COMMIT, got $actual_commit for ref $HYQ_REF (tag may have moved upstream - refusing to build an unverified commit; update the pin in installer/build-hyq.sh only after reviewing the diff)"
fi
log_ok "commit identity verified: $actual_commit"

cmake_args=(-B "$SRC_DIR/build" -DCMAKE_BUILD_TYPE=Release)
if pkg-config --exists hyprlang 2>/dev/null; then
    log_info "system hyprlang found via pkg-config - building against it instead of fetching a copy"
    cmake_args+=(-DUSE_SYSTEM_HYPRLANG=ON)
fi

log_info "configuring (cmake) ..."
if ! cmake "${cmake_args[@]}" -S "$SRC_DIR"; then
    die "cmake configure failed - see output above"
fi

log_info "building (this fetches spdlog and, unless satisfied locally, CLI11/nlohmann_json/hyprlang from upstream GitHub repos) ..."
nproc_bin=$(command -v nproc || true)
jobs=1
[ -n "$nproc_bin" ] && jobs=$("$nproc_bin")
if ! cmake --build "$SRC_DIR/build" -j"$jobs"; then
    die "build failed - see output above"
fi

built_bin="$SRC_DIR/bin/hyq"
[ -x "$built_bin" ] || die "build reported success but $built_bin is missing or not executable"

ensure_dir "$HOME/.local/bin"
install -m 755 "$built_bin" "$INSTALL_TARGET"
printf '%s\n' "$HYQ_COMMIT" >"$MARKER"
log_ok "installed hyq -> $INSTALL_TARGET (from commit $HYQ_COMMIT)"

if "$INSTALL_TARGET" --help >/dev/null 2>&1; then
    log_ok "hyq --help runs cleanly"
else
    log_warn "hyq was installed but 'hyq --help' did not exit cleanly - inspect manually before relying on it"
fi
