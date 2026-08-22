#!/usr/bin/env bash
# Run one command on the discrete NVIDIA GPU via PRIME render offload.
#
# Intel is the default session-wide GPU on this hybrid laptop (see
# Configs/.local/share/hypr/lua/env.lua and
# Configs/.config/uwsm/env.d/01-gpu.sh). This wrapper is the opt-in escape
# hatch for the one app that actually needs the NVIDIA GPU (a game, a
# renderer, a CUDA workload) without forcing NVIDIA onto the whole session.
#
# Usage: hyde-shell gpu-offload <command> [args...]

if [ $# -eq 0 ]; then
    echo "Usage: hyde-shell gpu-offload <command> [args...]" >&2
    exit 1
fi

export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export DRI_PRIME=1

exec "$@"
