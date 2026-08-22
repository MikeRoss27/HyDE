# Dependencies

Source of truth for what a stock HyDE install used to pull in was
`Scripts/dots-groups/{core,extra,optionals,shell,notification-daemon}.toml`
→ `Scripts/dots/*.toml` (installed via a Python tool called `deez`).
`Scripts/pkg_core.lst`/`pkg_extra.lst` were a dead, drifted mirror of this
and were never consulted by `install.sh`. This table was transcribed from
those manifests before `Scripts/` (and the root `dots.toml` that drove it)
were deleted wholesale in ROADMAP.md Slice 5 — **this table is now the only
surviving source of truth**; packages are installed manually against it.

| Dependency | Purpose | Referenced by | Decision | Replacement | Justification |
|---|---|---|---|---|---|
| Hyprland | Compositor | everything | KEEP | — | Core of the setup |
| UWSM | Session/env manager | `Configs/.config/uwsm/*`, `lua/start_up.lua` (`uwsm finalize`), `lua/events.lua` (`uwsm stop`) | KEEP | — | User-preferred session model |
| Waybar | Status bar | `lua/variables.lua` (`hc.start.bar`), `Configs/.local/share/waybar/` | KEEP | — | Core UI |
| hyprlock | Lockscreen | `rofi hyprlock.sh`, `hypridle.conf` `$LOCK_CMD` | KEEP | — | Core |
| hypridle | Idle daemon | `lua/variables.lua` (`hc.start.idle_daemon`) | KEEP | — | Core |
| hyprpolkitagent | Polkit auth agent | `hc.start.auth_dialogue` | KEEP | — | Required for GUI privilege prompts |
| xdg-desktop-portal-hyprland | Screen share/portal | `hyde.toml` syncs `hyprland-portals.conf` | KEEP | — | Required by Wayland apps |
| xdg-desktop-portal-gtk | File picker portal | `deps.toml` | KEEP | — | Required for GTK file dialogs |
| rofi | Launcher/menu framework | ~29 call sites across `~/.local/lib/hyde` (`rofilaunch.sh`, `cliphist.sh`, `theme.select.sh`, waybar `custom-app-launcher.jsonc`, etc.) | KEEP | — | Too deeply wired to replace without a rewrite; retained per brief's "rofi not automatically removed" |
| brightnessctl | Backlight control | hypridle listeners | KEEP | — | Standard, no overlap |
| playerctl | Media control | waybar mediaplayer/spotify modules | KEEP | — | Standard, no overlap |
| NetworkManager + `nm-applet` | Networking + tray icon | `hc.start.applet_network_manager` | KEEP | — | Already user's networking stack |
| Bluetooth + `blueman-applet` | Bluetooth + tray icon | `hc.start.applet_bluetooth` | KEEP | — | User confirmed keep |
| grim, slurp, satty | Screenshot stack | `screenshot.sh`, `pm.py` | KEEP | — | No duplicate tool present (no swappy alongside satty) |
| swaync | Notifications | `dots-groups/extra.toml` → `swaync.toml` | KEEP | — | User chose swaync's panel/history over dunst |
| dunst | Notifications | `dots-groups/core.toml` → `dunst.toml` | REMOVE | swaync | Both installed by default due to a HyDE "choose 1" bug never enforced; user picked swaync. **Done**: `hc.start.notifications` in `variables.lua` now launches `swaync` instead of `dunst` |
| wlogout | Power/logout menu | `Scripts/dots/deps.toml` (`yay=[...]`/`paru=[...]`, **AUR-only, no pacman entry**), `logoutlaunch.sh` | KEEP | — | User accepted this as the fork's sole AUR dependency |
| AUR helper (yay/paru) | Package manager for AUR | `install_aur.sh`, needed solely because `wlogout` has no official-repo package | KEEP (scoped) | — | Required only to install wlogout; not used for anything else in this fork |
| cliphist | Clipboard history | ~~`hc.start.text_clipboard`/`image_clipboard`, `MOD+SHIFT+V`/`MOD+V` keybinds, rofi `cliphist.sh`~~ | REMOVE | none (no persistent clipboard) | Explicit standing preference: no persistent clipboard history. **Done**: startup watchers and both keybinds removed from `variables.lua`/`start_up.lua`/`key_binds.lua`; the two dead `menu.clipboard`/`menu.cliphist` dispatcher entries were also removed. Waybar's `custom-cliphist.jsonc`/`custom-clipboard.jsonc` modules still exist and are referenced from the `hyprdots/*.jsonc` layout presets — not yet touched, deferred to Slice 7 (pick one waybar layout, drop the rest) since editing all 15 preset files now would be premature |
| wl-clip-persist | Keep clipboard after app closes | ~~`hc.start.clipboard_persist`~~ | REMOVE | none | Only relevant alongside cliphist; drops with it. **Done**: removed from `variables.lua`/`start_up.lua` |
| udiskie | Auto-mount removable media, tray icon | ~~`hc.start.applet_removable_media`~~ | REMOVE | none | User chose to drop it. **Done**: removed from `variables.lua`/`start_up.lua` |
| battery-notify | Low-battery popup (`batterynotify.lua`) | `hc.start.battery_notify` | KEEP | — | User confirmed keep (laptop) |
| kitty | Terminal | `pkg_core.lst`; hardcoded in `fzf_preview.sh` (`xterm-kitty` check, `kitty icat`), `system.monitor.sh`, `fastfetch.sh` (`--logo-type kitty`), `session/plugins/kitty.py` | KEEP | — | User revisited the initial "Ghostty preferred" assumption and chose to keep Kitty (already familiar with it, no concrete reason to switch found) |
| code (code-oss) | Editor | `Scripts/dots/code.toml` (`optionals.toml` only, official repo) | KEEP | — | User wants to keep VS Code available for occasional use; Zed is not being forced in |
| vscode/vscodium | Editor (AUR variants) | `Scripts/dots/code.toml` optional profiles | KEEP (optional) | — | Not actively used, but no longer scheduled for removal since VS Code itself stays |
| Chaotic-AUR | Third-party repo/mirror | `Scripts/chaotic_aur.sh`, `install_pre.sh` opt-in prompt (defaults yes on timeout) | REMOVE | none | Prefer official repos; installer deleted entirely anyway (Slice 5) |
| oh-my-zsh | Zsh framework | `Scripts/restore_shl.sh` (`curl\|sh` installer/upgrader) | KEEP | none | User wants to keep it. Note: Starship (already kept) is what actually renders the "pretty prompt" — oh-my-zsh itself is a plugin/theme framework layered underneath, so this is additive, not required for the visual polish. Security note stands regardless (see SECURITY.md): if/when installed on the live machine, prefer a `git clone` of the repo over the `curl\|sh` one-liner, since `Scripts/` (the only thing that ran that installer automatically) is being deleted anyway — this becomes a manual, one-time action the user controls directly |
| Lua + luarocks + `lgi` | Hyprland config runtime | `deps.toml`, 47 `.lua` files under `hypr/lua`, `batterynotify.lua`/`open.lua` (DBus/UPower via `lgi`) | KEEP | — | Required by the Lua config architecture |
| Python (implicit) | Backs ~49 scripts under `~/.local/lib/hyde` (waybar modules, session restore, theme import, gpuinfo, etc.) | never explicitly declared as a pacman dependency anywhere in the manifests | INVESTIGATE | — | Works today because something else pulls in `python`; should be pinned explicitly once `Scripts/` is gone and this fork owns its own dependency list |
| power-profiles-daemon | Waybar module backend | waybar has a `power-profiles-daemon` module, but the package itself is commented out in `pkg_core.lst` | INVESTIGATE | — | Currently a dead/broken tray module unless the user manually installs the daemon (already running `power-profiles-daemon` per standing environment — module likely just needs enabling, not code changes) |
| grimblast | Screenshot helper | `Scripts/dots/hyde.toml`: `source = blob+https://raw.githubusercontent.com/hyprwm/contrib/...` | INVESTIGATE | — | Fetched as a raw script blob at deploy time rather than an official package — supply-chain note, not urgent since `Scripts/` (the only thing that fetches it) is being deleted |
| `Source/arcs/*.tar.gz` | Bundled optional theme archives (grub/sddm/steam/firefox themes) | only `Icon_Wallbash.tar.gz` is pulled by default (`archives.toml`, part of `core.toml`) | REMOVE (repo cleanup) | none | ~29MB, unused by default; not a runtime dependency, just working-tree bloat |
| `Source/assets` | README/doc images | docs only | REMOVE (repo cleanup) | none | ~36MB, no runtime relevance |

## Notes

- Font/cursor archives (5 nerd fonts, Bibata cursor, Cantarell) are fetched
  from GitHub release URLs unconditionally by `archives.toml` in `core.toml`
  — flagged here as a network dependency of a stock install, not removed
  from this doc since it's install-time behavior that no longer applies once
  `Scripts/` is deleted (packages will be installed manually per this table).
- "REMOVE" throughout means: removed from `dots-groups`/config so a manual
  reinstall of this fork doesn't pull it in — not a claim that anything is
  uninstalled on the live machine automatically (no `sudo`/package removal
  is ever run by this fork's tooling; see SECURITY.md).
