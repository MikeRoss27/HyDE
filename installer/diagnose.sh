#!/usr/bin/env bash
# installer/diagnose.sh - `install.sh --diagnose`. Entirely read-only:
# captures GPU/DRM/EGL/driver/coredump state relevant to the Aquamarine
# SIGSEGV crash (Aquamarine::CDRMRenderer teardown, stack frames in
# libaquamarine.so/DRM renderer/libEGL/eglDestroyContext - see
# docs/personal-fork/ROADMAP.md and ARCHITECTURE.md "Aquamarine crash").
#
# Never changes drivers, kernel params, Secure Boot, GRUB, EFI or /boot.
# Every command here is a query; nothing here mutates system state.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./lib.sh
. "$SCRIPT_DIR/lib.sh"

section() { printf '\n== %s ==\n' "$1"; }
run() {
    local desc=$1
    shift
    printf -- '-- %s: %s\n' "$desc" "$*"
    if ! "$@" 2>&1; then
        printf '(command exited nonzero or produced no output)\n'
    fi
    echo
}

section "GPU (lspci)"
run "VGA/3D controllers" bash -c 'lspci -nnk 2>/dev/null | grep -A3 -E "VGA|3D controller"'

section "DRM devices"
run "card/render nodes" ls -l /dev/dri
run "by-path" bash -c 'ls -l /dev/dri/by-path 2>/dev/null || echo "(no /dev/dri/by-path)"'
run "drm sysfs" bash -c 'for c in /sys/class/drm/card*; do [ -e "$c/device/uevent" ] && { echo "== $c =="; cat "$c/device/uevent"; }; done'

section "NVIDIA driver/package state (read-only)"
run "loaded kernel modules" bash -c 'lsmod | grep -i nvidia || echo "(no nvidia module loaded)"'
run "nvidia packages" bash -c 'pacman -Qs "^nvidia" || echo "(none installed)"'
run "nvidia-smi" bash -c 'command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi || echo "(nvidia-smi not present or failed)"'

section "UWSM GPU env resolution (as actually sourced)"
run "01-gpu.sh resolved vars" bash -c '
    envd="'"$XDG_CONFIG_HOME"'/uwsm/env.d/01-gpu.sh"
    if [ -f "$envd" ]; then
        ( unset __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND GPU_SETUP LIBVA_DRIVER_NAME VK_ICD_FILENAMES
          # shellcheck disable=SC1090
          source "$envd" >/dev/null 2>&1
          echo "GPU_SETUP=${GPU_SETUP:-<unset>}"
          echo "__GLX_VENDOR_LIBRARY_NAME=${__GLX_VENDOR_LIBRARY_NAME:-<unset>}"
          echo "GBM_BACKEND=${GBM_BACKEND:-<unset>}"
          echo "LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-<unset>}" )
    else
        echo "(not found: $envd)"
    fi'
run "live session GPU env (if inside Hyprland)" bash -c 'env | grep -E "^(__GLX_VENDOR_LIBRARY_NAME|GBM_BACKEND|__NV_PRIME_RENDER_OFFLOAD|__VK_LAYER_NV_optimus|LIBVA_DRIVER_NAME)=" || echo "(none set in this shell - expected outside a live Hyprland session)"'

section "EGL/GLVND vendor state"
run "EGL vendor JSON files" bash -c 'ls -l /usr/share/glvnd/egl_vendor.d/ 2>/dev/null; ls -l /etc/glvnd/egl_vendor.d/ 2>/dev/null || true'
run "libEGL owner" bash -c 'pacman -Qo /usr/lib/libEGL.so.1 2>&1'
run "GLX vendor selection" bash -c 'command -v eglinfo >/dev/null 2>&1 && eglinfo 2>&1 | head -20 || echo "(eglinfo not installed - part of mesa-utils/eglinfo, optional)"'

section "Mesa / GLVND package state"
run "mesa + glvnd packages" bash -c 'pacman -Qs "^mesa$|^libglvnd$|^vulkan-icd-loader$"'

section "Hyprland / Aquamarine versions"
run "Hyprland --version" Hyprland --version
run "aquamarine package" bash -c 'pacman -Qi aquamarine 2>&1 | grep -E "^(Name|Version|Description)"'
run "libaquamarine linkage" bash -c 'ldd /usr/bin/Hyprland 2>/dev/null | grep aquamarine'

section "Lua ABI evidence (Hyprland vs libinput)"
run "Hyprland direct NEEDED (readelf -d)" bash -c 'readelf -d /usr/bin/Hyprland 2>/dev/null | grep -iE "NEEDED.*lua"'
run "full transitive closure (ldd)" bash -c 'ldd /usr/bin/Hyprland 2>/dev/null | grep -i lua'
run "who NEEDS liblua5.4 among Hyprland deps" bash -c '
    for lib in $(ldd /usr/bin/Hyprland 2>/dev/null | awk "{print \$3}" | grep -v "^\$"); do
        readelf -d "$lib" 2>/dev/null | grep -q "liblua5\.4" && echo "NEEDS liblua5.4: $lib"
    done
    true'
run "package ownership" bash -c 'pacman -Qo /usr/lib/liblua.so.5.5 /usr/lib/liblua5.4.so.5.4 /usr/lib/libinput.so.10 2>&1'

section "Seat / session ownership (read-only)"
run "active seat0 session" bash -c '
    id=$(loginctl list-sessions --no-legend 2>/dev/null | awk "\$4==\"seat0\" && \$6==\"user\" {print \$1}" | head -1)
    if [ -z "$id" ]; then echo "(no active user session on seat0)"; exit 0; fi
    loginctl show-session "$id" -p Id -p Type -p Class -p Active -p State -p TTY -p VTNr 2>&1'
run "compositor currently holding the seat" bash -c '
    ps -eo pid,cmd | grep -E "kwin_wayland$|Hyprland$|weston$|sway$" | grep -v grep || echo "(no compositor process found)"'
run "why this matters" bash -c 'cat <<'"'"'EOF'"'"'
If a compositor above is running AND you launch `Hyprland` or `start-hyprland`
from a terminal INSIDE that same active session, Aquamarine cannot acquire
DRM master: logind refuses TakeControl() with EBUSY because the running
compositor already owns the seat. Aquamarine then either (a) falls back to
its nested Wayland backend if WAYLAND_DISPLAY is inherited (harmless, runs
as a window inside the other compositor) or (b) if no fallback is possible,
Hyprland throws `CBackend::create() failed!` and aborts (SIGABRT).
Neither outcome says anything about GPU/EGL/multi-GPU compatibility - it is
a seat-ownership conflict caused by the test methodology itself. A real
test requires an empty VT with no compositor already holding seat0.
EOF'

section "Coredump summary (if any, read-only)"
run "coredumpctl list (Hyprland)" bash -c 'command -v coredumpctl >/dev/null 2>&1 && coredumpctl list Hyprland --no-pager 2>&1 | tail -20 || echo "(coredumpctl not available)"'
run "coredumpctl info (most recent Hyprland dump)" bash -c '
    command -v coredumpctl >/dev/null 2>&1 || { echo "(coredumpctl not available)"; exit 0; }
    coredumpctl info Hyprland --no-pager 2>&1 | tail -60'

section "Coredump classification (startup failure vs. shutdown-only crash)"
run "per-crash classification" bash -c '
    command -v coredumpctl >/dev/null 2>&1 || { echo "(coredumpctl not available)"; exit 0; }
    coredumpctl list Hyprland --no-legend --no-pager 2>&1 | while read -r _dow date time _tz pid _rest; do
        [ -n "$pid" ] || continue
        printf "%s" "$pid" | grep -qE "^[0-9]+$" || continue
        info=$(coredumpctl info "$pid" --no-pager 2>&1)
        cmdline=$(printf "%s\n" "$info" | grep -m1 "^ *Command Line:" | sed -E "s/^ *Command Line: *//")
        sig=$(printf "%s\n" "$info" | grep -m1 "^ *Signal:" | sed -E "s/^ *Signal: *//")
        unit=$(printf "%s\n" "$info" | grep -m1 "^ *User Unit:" | sed -E "s/^ *User Unit: *//")
        verdict="UNKNOWN - inspect manually"
        ts="$date $time"
        ts_epoch=$(date -d "$ts" "+%s" 2>/dev/null)
        until_ts="$ts"
        [ -n "$ts_epoch" ] && until_ts=$(date -d "@$((ts_epoch + 5))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
        if printf "%s" "$cmdline" | grep -qE -- "--config|--watchdog-fd"; then
            if [ -n "$unit" ]; then
                stopping=$(journalctl --user -o cat --since "$ts" --until "$until_ts" 2>/dev/null | grep -c "^Stopping.*[Hh]yprland" || true)
                if [ "${stopping:-0}" -gt 0 ]; then
                    verdict="SHUTDOWN crash (stop was already in progress) - matches aquamarine#267 CDRMRenderer teardown, cosmetic, backend creation had already SUCCEEDED"
                else
                    verdict="STARTUP crash - backend creation likely failed, needs investigation (check seat ownership above first)"
                fi
            else
                verdict="manual test run (no systemd user unit) - if launched from inside an active graphical session, an abort here is EXPECTED (see seat ownership section above), not a bug"
            fi
        fi
        printf "PID %-8s sig=%-8s unit=%-45s %s\n" "$pid" "$sig" "${unit:-<none>}" "$verdict"
    done'

section "Portals installed"
run "portal packages" bash -c 'pacman -Qs "^xdg-desktop-portal" '

echo
log_info "diagnose complete - purely informational, no system state was changed. See docs/personal-fork/ARCHITECTURE.md for how to read the Lua ABI evidence and the Aquamarine crash's current status."
