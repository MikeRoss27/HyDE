#!/usr/bin/env bash
# installer/packages.sh - dependency-manifest-driven package check/install.
# Only ever runs ONE sudo pacman invocation, only for official-repo
# packages, only after listing them and asking for confirmation. AUR and
# source-build entries are reported, never auto-installed.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

MANIFEST="$SCRIPT_DIR/packages.manifest"
[ -f "$MANIFEST" ] || die "package manifest not found: $MANIFEST"

missing_repo=()
missing_aur=()
missing_source=()

scan_manifest() {
    while IFS='|' read -r name source reason; do
        name=$(printf '%s' "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        source=$(printf '%s' "$source" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        reason=$(printf '%s' "$reason" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        [ -n "$name" ] || continue
        case "$name" in \#*) continue ;; esac

        case "$source" in
            repo)
                pkg_installed "$name" || missing_repo+=("$name")
                ;;
            aur)
                pkg_installed "$name" || missing_aur+=("$name|$reason")
                ;;
            source)
                bin_present "$name" || missing_source+=("$name|$reason")
                ;;
        esac
    done < <(grep -v '^[[:space:]]*#' "$MANIFEST" | grep -v '^[[:space:]]*$')
}

report_only() {
    scan_manifest
    if [ ${#missing_repo[@]} -eq 0 ]; then
        log_ok "all official-repo dependencies already installed"
    else
        log_warn "missing official-repo packages: ${missing_repo[*]}"
    fi
    for entry in "${missing_aur[@]:-}"; do
        [ -n "$entry" ] || continue
        log_warn "AUR dependency not installed: ${entry%%|*} (${entry#*|})"
    done
    for entry in "${missing_source[@]:-}"; do
        [ -n "$entry" ] || continue
        log_warn "build-from-source dependency not installed: ${entry%%|*} (${entry#*|})"
    done
}

install_repo_missing() {
    scan_manifest
    if [ ${#missing_repo[@]} -eq 0 ]; then
        log_ok "no official-repo packages to install"
        return 0
    fi

    log_info "the following official-repo packages are missing:"
    printf '  - %s\n' "${missing_repo[@]}"
    local cmd="sudo pacman -S --needed ${missing_repo[*]}"
    log_info "exact command: $cmd"

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would run: $cmd"
        return 0
    fi

    if ! confirm "Run this pacman command now?"; then
        log_skip "package install declined by user"
        return 0
    fi
    # shellcheck disable=SC2086
    sudo pacman -S --needed "${missing_repo[@]}"
}

report_aur_and_source() {
    if [ ${#missing_aur[@]} -gt 0 ]; then
        echo
        log_info "AUR packages (not auto-installed - this fork never bootstraps an AUR helper):"
        for entry in "${missing_aur[@]}"; do
            [ -n "$entry" ] || continue
            log_info "  ${entry%%|*}: ${entry#*|}"
        done
        log_info "  install manually with your AUR helper of choice, e.g.: yay -S wlogout"
    fi
    if [ ${#missing_source[@]} -gt 0 ]; then
        echo
        log_info "build-from-source dependencies (not auto-built):"
        for entry in "${missing_source[@]}"; do
            [ -n "$entry" ] || continue
            log_info "  ${entry%%|*}: ${entry#*|}"
        done
        log_info "  hyq: no cargo/Rust build - upstream is CMake/C++23. Run installer/build-hyq.sh (pinned commit, asks for confirmation, installs only to ~/.local/bin, never sudo)"
        log_info "  app2unit: pure POSIX shell, no build. Run installer/build-app2unit.sh (pinned commit, asks for confirmation, installs only to ~/.local/bin, never sudo)"
    fi
}

case "${1:---report}" in
    --report)
        report_only
        report_aur_and_source
        ;;
    --install)
        refuse_root
        install_repo_missing
        report_aur_and_source
        ;;
    --source-only) : ;;
    *)
        die "packages.sh: unknown mode ${1:-}"
        ;;
esac
