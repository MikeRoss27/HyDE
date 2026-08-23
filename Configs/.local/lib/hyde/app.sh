#!/usr/bin/env sh
# @name: app
# @ver: 0.1.0
# @short: Wrapper for scripts to optionally use systemd
# @cmd: service
# @cmd.desc: Run a script as a systemd service

# app2unit and xdg-terminal-exec fall back to the generic DEBUG variable,
# which may contain non-boolean build modes such as "release".
# Give both helpers an explicit, scoped default while preserving any
# user-provided values on both execution paths.
APP2UNIT_DEBUG=${APP2UNIT_DEBUG:-0}
XTE_DEBUG=${XTE_DEBUG:-0}
export APP2UNIT_DEBUG XTE_DEBUG

# One line per dispatch to a flat, persistent log - not a substitute for
# `journalctl --user -u <unit>` (the transient unit's own stdout/stderr),
# but the one thing that survives even a dispatch that never reaches
# systemd at all (e.g. app2unit missing: exec below fails before any unit
# ever exists to have a journal). See install.sh --diagnose-startup.
_log="${XDG_STATE_HOME:-$HOME/.local/state}/hyde/log/startup.log"
mkdir -p "$(dirname "$_log")" 2>/dev/null
printf '%s dispatch: %s\n' "$(date -Iseconds)" "$*" >>"$_log" 2>/dev/null

if [ -d "/run/systemd/system" ]; then
    if ! command -v app2unit >/dev/null 2>&1; then
        printf '%s [XX] app2unit not found on PATH - dispatch aborted: %s\n' "$(date -Iseconds)" "$*" >>"$_log" 2>/dev/null
        echo "app2unit not found on PATH - install it with: installer/build-app2unit.sh (see docs/personal-fork/ARCHITECTURE.md)" >&2
        exit 127
    fi
    unset _log
    exec app2unit "$@"
fi
unset _log
# no systemd: drop args before -- and run only the command after --
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    shift
done
[ "$#" -gt 0 ] && shift
exec "$@"
