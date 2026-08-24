#!/usr/bin/env bash
# @name: workspace-overview
# @short: Open a graphical workspace overview, with a safe window-list fallback

set -uo pipefail

plugins=$(hyprctl plugin list 2>/dev/null || true)

if grep -qi 'hyprspace' <<<"$plugins"; then
    if hyprctl dispatch overview:toggle all >/dev/null 2>&1; then
        exit 0
    fi
fi

if grep -qi 'hyprexpo' <<<"$plugins"; then
    if hyprctl dispatch hyprexpo:expo toggle >/dev/null 2>&1; then
        exit 0
    fi
fi

# A real overview requires a Hyprland-version-matched plugin. Until one is
# explicitly installed, keep the shortcut useful and crash-free.
exec hyde-shell rofilaunch w
