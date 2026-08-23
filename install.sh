#!/usr/bin/env bash
# install.sh - installer for this personal HyDE/Hyprland fork.
#
# This installer is scoped to the trimmed-down runtime under Configs/ (see
# CLAUDE.md and docs/personal-fork/). It never touches GRUB/EFI/Secure
# Boot/mkinitcpio/kernel params/NVIDIA drivers/sudoers/partitions, never
# removes KDE/Plasma, never replaces SDDM, and only ever asks for sudo once,
# for a single confirmed `pacman -S --needed <packages>` call.
#
# Usage:
#   install.sh --check     read-only validation, safe to run any time. Ends
#                          with a [READY]/[NOT READY] graphical-session
#                          verdict.
#   install.sh --dry-run   preview every action --install would take
#   install.sh --install   first-time install (idempotent, safe to re-run).
#                          Stops before runtime init (does not attempt a
#                          theme/colour render) if hyq is missing.
#   install.sh --repair    re-deploy + re-init runtime state (no package step)
#   install.sh --build-hyq deterministic, confirmation-gated build of hyq
#                          from a pinned upstream commit, installed to
#                          ~/.local/bin only, never sudo
#   install.sh --build-app2unit
#                          deterministic, confirmation-gated install of
#                          app2unit from a pinned upstream commit, installed
#                          to ~/.local/bin only, never sudo
#   install.sh --build-grimblast
#                          deterministic, confirmation-gated install of
#                          grimblast (screenshot capture helper) from a
#                          pinned upstream commit, installed to
#                          ~/.local/lib/hyde/screenshot only, never sudo
#   install.sh --diagnose  read-only GPU/DRM/EGL/Lua-ABI/coredump report
#   install.sh --diagnose-startup
#                          read-only Waybar/SwayNC/wallpaper/hypridle/polkit
#                          startup graph + previous-boot correlation report
#   install.sh --rollback  restore files from the most recent backup
#   install.sh --yes       (with --install/--repair/--build-hyq) skip
#                          confirmation prompts explicitly marked safe to
#                          auto-confirm
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$SCRIPT_DIR"
export REPO_ROOT
INSTALLER_DIR="$SCRIPT_DIR/installer"

# shellcheck source=installer/lib.sh
. "$INSTALLER_DIR/lib.sh"

usage() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

mode=""
build_hyq_args=()
build_app2unit_args=()
build_grimblast_args=()
for arg in "$@"; do
    case "$arg" in
        --check) mode=check ;;
        --dry-run) mode=dryrun; DRY_RUN=1 ;;
        --install) mode=install ;;
        --repair) mode=repair ;;
        --build-hyq) mode=build-hyq ;;
        --build-app2unit) mode=build-app2unit ;;
        --build-grimblast) mode=build-grimblast ;;
        --diagnose) mode=diagnose ;;
        --diagnose-startup) mode=diagnose-startup ;;
        --rollback) mode=rollback ;;
        --yes) ASSUME_YES=1 ;;
        --force) build_hyq_args+=(--force); build_app2unit_args+=(--force); build_grimblast_args+=(--force) ;;
        -h|--help) usage; exit 0 ;;
        *) log_err "unknown argument: $arg"; usage; exit 2 ;;
    esac
done
[ -n "$mode" ] || { usage; exit 2; }
export DRY_RUN ASSUME_YES

refuse_root

case "$mode" in
    check)
        exec "$INSTALLER_DIR/validate.sh"
        ;;

    dryrun)
        log_info "=== DRY RUN: package check ==="
        "$INSTALLER_DIR/packages.sh" --report
        echo
        log_info "=== DRY RUN: deploy preview ==="
        "$INSTALLER_DIR/deploy.sh"
        echo
        log_info "=== DRY RUN: runtime init preview ==="
        "$INSTALLER_DIR/runtime.sh"
        echo
        log_info "dry run complete - nothing was changed"
        ;;

    install)
        log_info "=== step 1/4: packages ==="
        "$INSTALLER_DIR/packages.sh" --install
        echo
        log_info "=== step 2/4: deploy ==="
        "$INSTALLER_DIR/deploy.sh" || die "deploy failed - see errors above. Backups (if any) are under $INSTALLER_BACKUP_DIR"
        echo
        log_info "=== step 3/4: runtime init ==="
        if ! hyq_gate; then
            die "stopping before runtime init: hyq is a hard dependency of the theme pipeline (see installer/theme.manifest) and it is not soft-warnable. Build it with: install.sh --build-hyq, then re-run: install.sh --repair"
        fi
        "$INSTALLER_DIR/runtime.sh" || die "runtime init failed - see errors above. Fix the reported issue, then re-run: install.sh --repair"
        echo
        log_info "=== step 4/4: validate ==="
        "$INSTALLER_DIR/validate.sh"
        rc=$?
        echo
        if [ "$rc" -eq 0 ]; then
            log_ok "install complete. Log out and pick 'Hyprland (uwsm)' at SDDM to try it; KDE Plasma is untouched as a fallback."
        else
            log_warn "install finished with warnings/failures above - review before switching sessions."
        fi
        exit "$rc"
        ;;

    repair)
        log_info "=== step 1/3: deploy ==="
        "$INSTALLER_DIR/deploy.sh" || die "deploy failed - see errors above"
        echo
        log_info "=== step 2/3: runtime init ==="
        if ! hyq_gate; then
            die "stopping before runtime init: hyq is a hard dependency of the theme pipeline (see installer/theme.manifest) and it is not soft-warnable. Build it with: install.sh --build-hyq"
        fi
        "$INSTALLER_DIR/runtime.sh" || die "runtime init failed - see errors above"
        echo
        log_info "=== step 3/3: validate ==="
        "$INSTALLER_DIR/validate.sh"
        ;;

    build-hyq)
        "$INSTALLER_DIR/build-hyq.sh" "${build_hyq_args[@]}"
        ;;

    build-app2unit)
        "$INSTALLER_DIR/build-app2unit.sh" "${build_app2unit_args[@]}"
        ;;

    build-grimblast)
        "$INSTALLER_DIR/build-grimblast.sh" "${build_grimblast_args[@]}"
        ;;

    diagnose)
        exec "$INSTALLER_DIR/diagnose.sh"
        ;;

    diagnose-startup)
        exec "$INSTALLER_DIR/diagnose-startup.sh"
        ;;

    rollback)
        "$INSTALLER_DIR/rollback.sh"
        ;;
esac
