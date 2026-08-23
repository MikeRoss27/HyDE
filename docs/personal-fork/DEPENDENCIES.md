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
| udiskie | Auto-mount external drives/USB (tray + notify) | `lua/variables.lua` (`hc.start.automount`) | ADD | — | Kernel/udisks2 detected external media fine but nothing mounted it; no automount daemon was installed. Official repo, no AUR |
| Bluetooth + `blueman-applet` | Bluetooth + tray icon | `hc.start.applet_bluetooth` | KEEP | — | User confirmed keep |
| grim, slurp, satty | Screenshot stack | `screenshot.sh`, `pm.py` | KEEP | — | No duplicate tool present (no swappy alongside satty) |
| hyprpicker | Freeze-frame for grimblast's area selection | `grimblast area` (MOD+CTRL+P) | KEEP | — | Missing on this machine as of this audit; official `extra` repo, added to `installer/packages.manifest` |
| wl-clipboard | `wl-copy`/`wl-paste` | grimblast's copy/copysave actions (every screenshot keybind that isn't pure `save`) | KEEP | — | Missing on this machine as of this audit; official `extra` repo, added to `installer/packages.manifest` |
| grimblast (hyprwm/contrib) | Screenshot capture helper wrapping grim/slurp/hyprctl | `screenshot.sh` execs `$LIB_DIR/hyde/screenshot/grimblast` unconditionally, no existence check, for every screenshot keybind | KEEP (source build) | — | No repo/AUR package. Was completely missing from this machine and undocumented in this table — found auditing why every screenshot keybind (MOD+P/CTRL+P/ALT+P, Print) silently failed. Upstream `hyprwm/contrib` has no meaningful tags (one old `v0.1`); reviewed the actual script content (plain bash, no network calls, no obfuscation) and pinned HEAD. `installer/build-grimblast.sh` installs a pinned, verified commit to `~/.local/lib/hyde/screenshot/grimblast` (symlinked at `~/.local/bin/grimblast`) only after explicit confirmation, same pattern as `build-hyq.sh`/`build-app2unit.sh` |
| swaync | Notifications | `dots-groups/extra.toml` → `swaync.toml` | KEEP | — | User chose swaync's panel/history over dunst |
| dunst | Notifications | `dots-groups/core.toml` → `dunst.toml` | REMOVE | swaync | Both installed by default due to a HyDE "choose 1" bug never enforced; user picked swaync. **Done**: `hc.start.notifications` in `variables.lua` now launches `swaync` instead of `dunst` |
| wlogout | Power/logout menu | `Scripts/dots/deps.toml` (`yay=[...]`/`paru=[...]`, **AUR-only, no pacman entry**), `logoutlaunch.sh` | KEEP | — | User accepted this as the fork's sole AUR dependency |
| AUR helper (yay/paru) | Package manager for AUR | `install_aur.sh`, needed solely because `wlogout` has no official-repo package | KEEP (scoped) | — | Required only to install wlogout; not used for anything else in this fork |
| cliphist | Clipboard history | `cliphist-watch.service`, `wl-paste` | KEEP | — | Explicitly requested for the final workstation. One user service owns both text and image watchers; no competing clipboard manager is started. Clipboard history is persistent and can contain sensitive copied data, so `cliphist wipe` remains an explicit user action. |
| wl-clip-persist | Keep clipboard after app closes | ~~`hc.start.clipboard_persist`~~ | REMOVE | none | Only relevant alongside cliphist; drops with it. **Done**: removed from `variables.lua`/`start_up.lua` |
| udiskie | Auto-mount removable media, tray icon | ~~`hc.start.applet_removable_media`~~ | REMOVE | none | User chose to drop it. **Done**: removed from `variables.lua`/`start_up.lua` |
| battery-notify | Low-battery popup (`batterynotify.lua`) | `hc.start.battery_notify` | KEEP | — | User confirmed keep (laptop) |
| kitty | Terminal | `pkg_core.lst`; hardcoded in `fzf_preview.sh` (`xterm-kitty` check, `kitty icat`), `system.monitor.sh`, `fastfetch.sh` (`--logo-type kitty`), `session/plugins/kitty.py` | KEEP | — | User revisited the initial "Ghostty preferred" assumption and chose to keep Kitty (already familiar with it, no concrete reason to switch found) |
| code (code-oss) | Editor | `Scripts/dots/code.toml` (`optionals.toml` only, official repo) | KEEP | — | User wants to keep VS Code available for occasional use; Zed is not being forced in |
| vscode/vscodium | Editor (AUR variants) | `Scripts/dots/code.toml` optional profiles | KEEP (optional) | — | Not actively used, but no longer scheduled for removal since VS Code itself stays |
| Chaotic-AUR | Third-party repo/mirror | `Scripts/chaotic_aur.sh`, `install_pre.sh` opt-in prompt (defaults yes on timeout) | REMOVE | none | Prefer official repos; installer deleted entirely anyway (Slice 5) |
| Oh My Zsh | Zsh framework | not installed; no runtime call sites | DO NOT ADD | Native Zsh completion + three packaged plugins + Starship | The measured native configuration already provides the requested UX in roughly 55 ms. OMZ would duplicate plugin/framework initialization without an identified benefit. |
| Lua + luarocks + `lgi` | Hyprland config runtime | `deps.toml`, 47 `.lua` files under `hypr/lua`, `batterynotify.lua`/`open.lua`/`color/dconf.lua` (DBus/UPower/GTK sync via `lgi`) | KEEP | — | Required by the Lua config architecture. **`lgi` is confirmed broken under Arch's Lua 5.5** (compile-time error, not a packaging fluke - see ARCHITECTURE.md "Lua runtime"); all three call sites now degrade gracefully via `pcall` instead of crashing. Not fixed upstream as of this audit |
| imagemagick | `magick` binary - wallbash palette extraction | `wallbash.sh`, `color.set.sh` | KEEP | — | Was missing entirely on this machine; without it the whole wallbash/theming pipeline cannot run at all. Installed via `installer/packages.sh` this session |
| GNU `parallel` | Renders wallbash templates in `color.set.sh` | `color.set.sh` | KEEP | — | Already installed, but its default job shell is `$SHELL` (zsh here), which silently breaks every exported-bash-function job; `color.set.sh` now pins `PARALLEL_SHELL=/bin/bash` |
| hyq (HyDE-Project/hyprquery) | `.hypr-lang` query tool | `theme.switch.sh`, `color/hypr.sh` (hard dependency, no guard - see ARCHITECTURE.md "Runtime initialization"), `waybar.py`, `wallbash/scripts/swaync.sh` (guarded, degrades to defaults) | KEEP (source build) | — | No official-repo or AUR package found. Upstream ships **CMake/C++23** source, not Rust/Cargo (earlier note in this file was wrong). Not built automatically by `install.sh --install`/`--repair` - `installer/build-hyq.sh` builds a pinned, verified commit into `~/.local/bin/hyq` only after explicit confirmation; `install.sh --install`/`--repair` now hard-stop before runtime init if `hyq` is absent instead of warning and continuing |
| app2unit (Vladimir-csp/app2unit) | Turns `hyde-shell app ...` into a transient systemd scope/service | `Configs/.local/lib/hyde/app.sh` execs it unconditionally whenever `/run/systemd/system` exists - this is the dispatch path for **every** daemon `start_up.lua` launches: Waybar, wallpaper, hypridle, hyprpolkitagent, the config watcher, battery-notify, notifications | KEEP (source install) | — | No official-repo or AUR package. **Was completely missing from this machine and undocumented in this table** - found by auditing a real gray-screen Hyprland session: the previous-boot journal showed Waybar/wallpaper/hypridle/polkit never starting at all (no `hyde-*.scope/service` unit ever created), while SwayNC/nm-applet/blueman-applet DID start because they go through D-Bus activation / XDG autostart, not `hyde-shell`. `app.sh`'s `exec app2unit "$@"` failed with a plain, invisible "command not found" (exit 127) for every single dispatch - **this is HyDE's actual gray-screen root cause on a fresh machine**, more fundamental than any theming/CSS bug. Pure POSIX shell upstream, no compiler - `installer/build-app2unit.sh` installs a pinned, verified commit to `~/.local/bin` only after explicit confirmation. `install.sh --check` now hard-fails the `[READY]` gate if it's absent |
| awww | Default wallpaper backend daemon | `Configs/.local/lib/hyde/wallpaper.awww.sh` (`hc.config.wallpaper.backend = "awww"` in `schema/config.toml`) calls `awww`/`awww-daemon` directly with **no fallback and no surfaced error** | KEEP (repo package) | — | Was missing from this machine and undocumented in this table; found while diagnosing the same gray-screen wallpaper failure. Unlike `app2unit`/`hyq`, it **is** in the official `extra` repo (`extra/awww`) - added to `installer/packages.manifest` so `install.sh --install` picks it up in the normal single-confirmation `pacman -S --needed` step, no source build needed |
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
