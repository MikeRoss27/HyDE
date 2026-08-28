-- Hyprland loads this file when it is started without a config, and it prefers
-- it over hyprland.conf. HyDE loads it too, last, as the override layer below.
-- The block keeps the two apart: hyde.lua sets `hyde` on its first line, so it
-- runs only when this file is the entry point and HyDE has not been loaded.
-- Removing it leaves a session with a cursor and nothing else.
if not hyde then
	local share = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
	local entry = share .. "/hypr/hyde.lua"
	local handle = io.open(entry, "r")
	if not handle then
		error("HyDE is not installed at " .. entry .. ". Run install.sh -r, or point Hyprland at your own config.")
	end
	handle:close()
	dofile(entry)
end

-- Your Hyprland configuration. HyDE never overwrites this file.
--
-- It loads after HyDE's own binds, so settings here take precedence. Replacing
-- a bind needs more than that: see below. HyDE's defaults live in
-- ~/.local/share/hypr/lua/ and are overwritten on every update, so edits there
-- do not survive.
--
-- Adding a keybind:
--
--     hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(hyde.sh.gamelauncher()), {
--         description = "[Utilities] game launcher",
--     })
--
-- Replacing one of HyDE's: bind the same combination again and yours takes
-- over, but copy its flags across as well. A bind counts as the same one only
-- when its flags match, and `description` is not a flag — miss one and both
-- binds stay live on that combination. Copy the whole options table from
-- ~/.local/share/hypr/lua/key_binds.lua and change only what you need:
--
--     hl.bind("F9", hl.dsp.exec_cmd(hyde.sh.volumecontrol("-o", "m")), {
--         locked = true,
--         description = "[Hardware Controls|Audio] un/mute output",
--     })
--
-- Press SUPER + / to see what is actually loaded, your own binds included.
-- The full reference is KEYBINDINGS.md in the HyDE repository.
--
-- Other Lua files next to this one can be pulled in with require("name").

-- ============================================================================
-- Monitors
-- ============================================================================

-- HDMI-A-1 (external, main) sits physically to the left on the desk, eDP-1
-- (laptop panel) to the right. Hyprland's auto-arrangement put eDP-1 at 0x0
-- instead, so moving a window "left" from the external monitor went to the
-- laptop panel even though it sits to the right in real life. Swapped here
-- to match physical layout.
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "1920x0", scale = 1.2 })

-- Toggle a region/full-output recording. The first press opens slurp; the
-- second stops the recorder and saves the result under Videos/Recordings.
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("swaync-actions record-toggle"), {
	description = "[Utilities] toggle screen recording",
})

-- One entry point for workstation settings. SUPER+I is already used by the
-- master layout, so CTRL is kept to avoid silently replacing that behavior.
hl.bind("SUPER + CTRL + I", hl.dsp.exec_cmd("hyde-shell control-center"), {
	description = "[Utilities] open unified settings",
})

-- Modern native file manager; SUPER + SHIFT + E still opens Rofi's file finder.
hl.bind("SUPER + E", hl.dsp.exec_cmd("hyde-shell files"), {
	description = "[Launcher|Apps] HyDE Files",
})

-- Replace HyDE's plain SUPER+TAB window list with an overview-aware wrapper.
-- It falls back to the same reliable list while no compatible plugin is loaded.
hl.bind("SUPER + TAB", hl.dsp.exec_cmd("hyde-shell workspace-overview"), {
	description = "[Window Management] workspace overview",
})

-- ============================================================================
-- Input
-- ============================================================================

-- French AZERTY keyboard
hl.config({
	input = {
		kb_layout = "fr",
	},
	general = {
		gaps_in = 5,
		gaps_out = 10,
		border_size = 2,
	},
	decoration = {
		rounding = 14,
		active_opacity = 0.97,
		inactive_opacity = 0.91,
		fullscreen_opacity = 1.0,
		blur = {
			enabled = true,
			size = 7,
			passes = 3,
			noise = 0.01,
			vibrancy = 0.18,
			special = true,
		},
		shadow = {
			enabled = true,
			range = 18,
			render_power = 3,
			color = "rgba(00000055)",
		},
	},
})

-- A quiet, responsive motion profile: short fades, directional workspaces.
hl.curve("hyde-modern", { type = "bezier", points = { { 0.2, 0.0 }, { 0.0, 1.0 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "hyde-modern" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "hyde-modern", style = "popin 88%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "hyde-modern", style = "popin 88%" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "hyde-modern" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "hyde-modern" })
