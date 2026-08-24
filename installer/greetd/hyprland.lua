-- Minimal Hyprland config for greetd's ReGreet greeter session only.
--
-- Loaded via `--config /etc/greetd/hyprland.lua` (see installer/greetd/config.toml),
-- not via the default ~/.config/hypr/hyprland.lua lookup - the "greeter" system
-- user's $HOME is "/", so Hyprland would never find that file anyway. Deliberately
-- isolated from the real HyDE session: no hyde.lua, no keybinds, no autostart
-- daemons - just enough compositor to host ReGreet's layer-shell surface, then
-- exit cleanly once ReGreet's session hand-off is done (success or cancel).
--
-- kb_layout must match the real console/X11 layout (`localectl status`) so
-- password entry on the login screen isn't silently mistyped in the wrong layout.
hl.config({
	input = {
		kb_layout = "fr",
	},
})

hl.on("hyprland.start", function()
	hl.exec_cmd("regreet; hyprctl dispatch 'hl.dsp.exit()'")
end)
