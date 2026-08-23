#!/usr/bin/env bash
# installer/rollback.sh - restore files backed up by the most recent
# deploy.sh run. Only ever restores files that were actually backed up
# (i.e. existed and were overwritten); never deletes a file this installer
# created that had no prior version - those are listed instead, for the
# user to remove by hand if they really want to.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

refuse_root

BACKUPS_ROOT="$INSTALLER_STATE_DIR/backups"
[ -d "$BACKUPS_ROOT" ] || die "no backups found under $BACKUPS_ROOT - nothing to roll back"

latest=$(find "$BACKUPS_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)
[ -n "$latest" ] || die "no backup runs found under $BACKUPS_ROOT"

log_info "rolling back using backup: $latest"
if ! confirm "Restore every file under $latest to its original location?"; then
    log_skip "rollback cancelled"
    exit 0
fi

restored=0
while IFS= read -r -d '' f; do
    rel=${f#"$latest"/}
    dest="$HOME/$rel"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[dry-run] would restore $dest <- $f"
    else
        mkdir -p "$(dirname "$dest")"
        cp -a "$f" "$dest"
        log_ok "restored $dest"
    fi
    restored=$((restored + 1))
done < <(find "$latest" -type f -print0)

log_info "rollback complete: $restored file(s) restored from $latest"
log_info "note: files this run CREATED (had no prior version to back up) were not deleted; review install.sh --check output if you want to remove them by hand"
