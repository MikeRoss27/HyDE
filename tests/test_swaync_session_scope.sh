#!/usr/bin/env sh
# swaync ships its own D-Bus service-activation file
# (/usr/share/dbus-1/services/org.erikreider.swaync.service, a package file
# this fork does not own) advertising org.freedesktop.Notifications
# globally. dbus-daemon D-Bus-activates swaync.service on ANY notification
# request in ANY session, regardless of the unit's own enabled/disabled
# state (WantedBy=graphical-session.target is irrelevant to D-Bus
# activation). Under a Plasma session this races
# org.kde.plasma.Notifications.service, loses, exit(1)s, and hits
# systemd's start-limit-hit within a second (5 restarts).
#
# Fix: a systemd user drop-in gating the unit to the Hyprland session via
# ConditionEnvironment, which reads systemd --user's own activation
# environment (imported at session start - see hc.start.dbus_share_picker
# in Configs/.local/share/hypr/lua/variables.lua and UWSM's
# DesktopNames=Hyprland), not the triggering process's environment. See
# docs/personal-fork/ARCHITECTURE.md.

. "$(dirname -- "$0")/lib/common.sh"

dropin="$REPO_ROOT/Configs/.config/systemd/user/swaync.service.d/10-hyde-session-scope.conf"

if [ ! -f "$dropin" ]; then
    fail "missing: $dropin"
    finish
fi

grep -q '^\[Unit\]$' "$dropin" || fail "$dropin: missing [Unit] section"
grep -q '^ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland$' "$dropin" ||
    fail "$dropin: missing ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland"

manifest="$REPO_ROOT/installer/deploy.manifest"
grep -qF '.config/systemd/user/swaync.service.d/10-hyde-session-scope.conf' "$manifest" ||
    fail "$dropin exists but is not listed in $manifest - install.sh --install/--repair would never deploy it"

finish
