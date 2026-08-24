#!/usr/bin/env bash
# installer/deploy.sh - deploy Configs/ paths listed in deploy.manifest into
# $HOME, per-file, with backup-before-replace. Never invoked directly; run
# via install.sh --install / --repair / --dry-run.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

MANIFEST="$SCRIPT_DIR/deploy.manifest"
[ -f "$MANIFEST" ] || die "deploy manifest not found: $MANIFEST"

deploy_run() {
    local count=0 failed=0
    while IFS= read -r line; do
        line=${line%%#*}
        line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        [ -n "$line" ] || continue

        if [[ $line == */ ]]; then
            local dir_rel=${line%/}
            local dir_abs="$REPO_ROOT/Configs/$dir_rel"
            [ -d "$dir_abs" ] || { log_err "manifest directory missing from repo: $dir_rel"; failed=1; continue; }
            while IFS= read -r -d '' f; do
                local rel=${f#"$REPO_ROOT/Configs/"}
                deploy_path_excluded "$rel" && continue
                deploy_one "$rel" "$HOME/$rel" || failed=1
                count=$((count + 1))
            done < <(find "$dir_abs" -type f -print0)
        else
            deploy_path_excluded "$line" && continue
            deploy_one "$line" "$HOME/$line" || failed=1
            count=$((count + 1))
        fi
    done <"$MANIFEST"

    log_info "deploy: $count entries processed"
    return $failed
}

# reload_systemd_user_units - deploy.manifest ships systemd user unit
# drop-ins (e.g. .config/systemd/user/swaync.service.d/) whose new content
# is inert until the user manager re-reads unit files. daemon-reload only
# reloads definitions - it does not start, stop, or restart anything.
reload_systemd_user_units() {
    [ -d /run/systemd/system ] || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would run: systemctl --user daemon-reload"
        return 0
    fi
    if systemctl --user daemon-reload 2>/dev/null; then
        log_ok "systemctl --user daemon-reload (picks up unit/drop-in changes just deployed)"
    else
        log_warn "systemctl --user daemon-reload failed - unit/drop-in changes may not be picked up until the next login"
    fi
}

if [ "${1:-}" = "--source-only" ]; then
    return 0 2>/dev/null || exit 0
fi

refuse_root
ensure_dir "$INSTALLER_STATE_DIR"
[ "$DRY_RUN" -eq 1 ] || ensure_dir "$INSTALLER_BACKUP_DIR"
deploy_run
deploy_rc=$?
reload_systemd_user_units
exit "$deploy_rc"
