# Architecture

## Upstream architecture (as shipped by HyDE)

**Entry point**: Hyprland is launched with `HYPRLAND_CONFIG` pointed at
`~/.local/share/hypr/hyde.lua` (set by `Configs/.config/uwsm/env-hyprland.d/00-hyde.sh`).
That file is deployed/overwritten on every update — never hand-edit it.

**Require chain** (`Configs/.local/share/hypr/hyde.lua` →
`Configs/.local/share/hypr/lua/`):

```
hyde.path                              # XDG dirs, package.path setup
hyde.{utils,env,config,binds,dispatcher,handlers}
variables                              # hc.start.*, hc.ui.*, hc.app.* defaults
defaults                               # baseline hl.config() options
window_rules / layer_rules
env                                    # env finalization, NVIDIA detection hook
dynamic                                # reads lua_state.colors (wallbash output)
key_binds                              # HyDE's default keybinds
events                                 # Hyprland event handlers
start_up                               # registers hyprland.start daemon list
check_require("monitors")              # optional, e.g. nwg-displays output
check_require("hyprland")              # <- ~/.config/hypr/hyprland.lua (user)
check_require("lua_state.workflows")   # generated, overrides everything
```

`check_require` is a no-op-safe `require`. The **user override point** is
`~/.config/hypr/hyprland.lua`: it is deploy-marked `preserve` (seeded once,
never overwritten) and loaded last among static files, so `hl.bind` /
`hl.config` / `hl.window_rule` calls there win over HyDE's own. It also
doubles as a standalone bootstrap file if Hyprland is pointed at it directly.
Only the generated `lua_state.workflows` (selected via
`hyde-shell workflows --select`) loads after it and truly has the last word.

**Deploy model** (`Scripts/dots/*.toml`, `action = sync|preserve`, driven by
a Python tool called `deez`):
- `sync` — overwritten every update: the whole Lua runtime above,
  `~/.local/lib/hyde` (the `hyde-shell` CLI/library tree), `~/.local/bin/{hyde-shell,hydectl}`,
  `~/.config/uwsm/env*`.
- `preserve` — seeded once, user-owned: `~/.config/hypr/hyprland.lua`,
  `~/.config/hyde/config.toml`, `~/.config/hypr/themes/colors.conf`.
- Fully runtime-generated, not shipped in the repo: `$XDG_STATE_HOME/hyde/lua_state/*.lua`
  (colors, ui, workflows), written by `hyde-shell` selector scripts.

**Runtime dispatcher**: `hyde-shell` (`Configs/.local/bin/hyde-shell`) is the
single CLI front door for the whole runtime — waybar click handlers,
keybinds, and rofi menus all call `hyde-shell <script>`. `hyde-shell app ...`
wraps `app2unit`, turning every daemon launch into a transient
`systemd --user` scope/service instead of a raw backgrounded process, so
daemons are individually inspectable/restartable via `systemctl --user`.

**wallbash** (`Configs/.local/lib/hyde/wallbash.sh`): synchronous ImageMagick
k-means color extraction over the current wallpaper. Triggered manually
(wallpaper change, theme switch, `hyde-shell reload theme`) — it is not a
background watcher and makes no network calls. Output feeds `<wallbash_*>`
template placeholders that `color.set.sh` substitutes into app configs
(waybar, hyprlock, dunst/swaync, gtk, kvantum).

**Startup daemon list** (`lua/start_up.lua` fires on the `hyprland.start`
event; actual commands are data in `lua/variables.lua`'s `hc.start.*`
table, each wrapped `hyde-shell app -u <unit> -t service|scope -- <cmd>`):
idle daemon (hypridle), blue-light filter (hyprsunset), text/image clipboard
watchers (cliphist), clipboard persist (wl-clip-persist), battery-notify,
notification daemon, waybar, hyde-config-watcher, polkit auth agent,
network-manager applet, removable-media applet (udiskie), bluetooth applet.
Because this list is plain data, trimming it (see ROADMAP.md, Slice 4) is a
config edit, not a code change.

**Package manifest**: `Scripts/dots-groups/{core,extra,optionals,shell,notification-daemon}.toml`
`include` the per-component `Scripts/dots/*.toml` files — this is the real,
live install source of truth. `Scripts/pkg_core.lst` / `pkg_extra.lst` are a
**dead/drifted mirror**: nothing in `install.sh`'s call graph reads them
(only `uninstall.sh` prints their path as a hint). A default `install.sh`
run installs `core.toml` **and** `extra.toml` unconditionally — "extra" is
not actually optional despite the name, which is why both `dunst` and
`swaync` land on a stock HyDE install even though a `notification-daemon.toml`
group exists explicitly commented "choose only 1" (and is never invoked).

## Target architecture (this fork)

The Lua config architecture, `hyde-shell` dispatcher, and deploy model above
are kept as-is — they're well-designed and not worth rewriting. What changes:

- **Trimmed startup daemon list** (done — `Configs/.local/share/hypr/lua/{variables,start_up,key_binds,hyde/dispatcher}.lua`):
  dropped cliphist (+ its two `wl-paste --watch` units and both its
  keybinds), wl-clip-persist, udiskie. `notifications` now launches
  `swaync` instead of `dunst`. Kept: hypridle, hyprsunset, battery-notify,
  waybar, hyde-config-watcher, polkit agent, nm-applet, blueman-applet.
- **App assumptions**: kitty and VS Code are both kept as-is (no code
  changes needed) — see DEPENDENCIES.md for the reasoning behind not
  switching to Ghostty/Zed.
- **No installer in the working tree**: `Scripts/` is deleted (Slice 5) once
  its package/dependency truth is captured in DEPENDENCIES.md. This fork is
  never installed via HyDE's installer on this machine; packages are managed
  manually against the official Arch repos per DEPENDENCIES.md.
- **One notification daemon** (swaync), one power menu (wlogout, the fork's
  sole accepted AUR dependency).
- **Not yet touched**: the waybar `custom-cliphist.jsonc`/`custom-clipboard.jsonc`
  module definitions still exist and are still referenced from the 15
  `hyprdots/*.jsonc` layout presets under `Configs/.local/share/waybar/layouts/`.
  Removing them per-layout is deferred to Slice 7 (pick one layout preset,
  delete the rest) rather than edited 15 times now.

## Components retained unchanged

Hyprland (Lua config), UWSM (session env only — HyDE never launches the
session itself, it just supplies `env.d`/`env-hyprland.d` fragments and
hooks `uwsm finalize`/`uwsm stop` into Lua event handlers), Waybar, hyprlock,
hypridle, hyprpolkitagent, xdg-desktop-portal-{hyprland,gtk}, rofi (used in
~29 call sites — swapping it out would mean rewriting most of
`~/.local/lib/hyde`), wallbash, `hyde-shell`.
