#!/bin/sh

# Root-only. Removes the on-machine kmscon-as-getty-replacement override
# that races greetd for VT1 / DRM master on /dev/dri/card1.
#
# Root cause found live (see docs/personal-fork/ROADMAP.md, "greetd login
# falls back to tty1" entry): /etc/systemd/system/kmsconvt@.service (created
# manually on this machine 2026-08-22, not part of this fork, not part of
# upstream HyDE, not owned by any pacman package) is aliased to
# autovt@.service and enabled on tty1 via getty.target. greetd.service only
# declares Conflicts=getty@tty1.service, so nothing stops kmscon from also
# starting on tty1 alongside greetd. Both try to become DRM master on
# /dev/dri/card1; kmscon loses the race, hits an unhandled error path in its
# drm_shared backend and segfaults (systemd-coredump confirms SIGSEGV in
# drm_shared.c:set_drm_master), and its TTYVHangup=yes/TTYReset=yes cleanup
# on tty1 kills the Hyprland/ReGreet session greetd just started there --
# before Hyprland logs a single line. greetd then reports "greeter exited
# without creating a session" and deactivates, and systemd's
# OnFailure=getty@tty1.service falls back to a bare agetty prompt: exactly
# the "boot lands on tty1" symptom this fixes.
#
# This disables the kmsconvt@tty1 instance and removes the autovt@.service
# alias so no future VT activation on tty1 re-spawns kmscon there. It does
# NOT remove the kmscon package or the kmsconvt@.service unit file itself --
# only the enablement links -- so kmscon stays available if wanted on a
# different tty later.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run with sudo: sudo %s\n' "$0" >&2
    exit 1
fi

UNIT=/etc/systemd/system/kmsconvt@.service
AUTOVT=/etc/systemd/system/autovt@.service
WANT_LINK=/etc/systemd/system/getty.target.wants/kmsconvt@tty1.service

if [ ! -e "$WANT_LINK" ] && [ ! -e "$AUTOVT" ]; then
    printf 'Nothing to do: no kmsconvt@tty1 enablement found (already clean).\n'
    exit 0
fi

if [ -e "$WANT_LINK" ]; then
    systemctl disable kmsconvt@tty1.service
fi
systemctl reset-failed kmsconvt@tty1.service 2>/dev/null || true

if [ -L "$AUTOVT" ] && [ "$(readlink -f "$AUTOVT")" = "$(readlink -f "$UNIT")" ]; then
    rm -f "$AUTOVT"
    printf 'Removed %s (was aliased to kmsconvt@.service).\n' "$AUTOVT"
fi

printf '%s\n' \
    '--- verification ---' \
    "kmsconvt@tty1.service: $(systemctl is-enabled kmsconvt@tty1.service 2>&1 || true)" \
    "autovt@.service present: $([ -e "$AUTOVT" ] && echo yes || echo no)" \
    '' \
    'tty1 is now free for greetd - no more kmscon/greetd DRM-master race.' \
    "kmsconvt@.service unit file left in place at $UNIT for reference." \
    '' \
    'Rollback (re-enable kmscon on tty1 - NOT recommended while greetd targets vt=1,' \
    'it reproduces the crash this fixed):' \
    "  sudo ln -s $UNIT $AUTOVT" \
    '  sudo systemctl enable --now kmsconvt@tty1.service'
