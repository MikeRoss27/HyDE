hyde = hyde or {}
hyde.env.finalize()
hl.env("PATH", (hyde.env("PATH") or "") .. ":" .. hyde.path.lib)
-- ? Isolate dconf (Prevents already-opened GTK apps (brave, nwg-displays, etc.) from updating their theme)
-- hl.env("DCONF_PROFILE",  ((os.getenv("XDG_CONFIG_HOME") ~= "" and os.getenv("XDG_CONFIG_HOME")) or (os.getenv("HOME") or "" ) .. "/.config") .. "/dconf/profile/hyde_hyprland")

-- NVIDIA: intentionally not forced as the session-wide renderer here. On
-- this Intel + NVIDIA hybrid laptop, Intel stays the compositor GPU (VA-API,
-- GLX vendor, and GBM buffer allocation all default to Mesa/Intel with
-- nothing set here); NVIDIA is reserved for explicit per-app offload via
-- `hyde-shell gpu-offload <command>` (Configs/.local/lib/hyde/gpu-offload.sh).
-- See https://wiki.hypr.land/Nvidia/ if a specific app still needs a
-- session-wide variable set in ~/.config/hypr/hyprland.lua.
