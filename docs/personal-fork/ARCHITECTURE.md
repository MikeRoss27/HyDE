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
- **No upstream installer in the working tree**: `Scripts/` is deleted
  (Slice 5) once its package/dependency truth is captured in
  DEPENDENCIES.md; packages are managed manually against the official Arch
  repos per DEPENDENCIES.md. This fork ships its **own** minimal installer
  instead — `install.sh` / `installer/*.sh` at the repo root, see "Personal
  installer" below.
- **One notification daemon** (swaync), one power menu (wlogout, the fork's
  sole accepted AUR dependency).
- **Not yet touched**: the waybar `custom-cliphist.jsonc`/`custom-clipboard.jsonc`
  module definitions still exist and are still referenced from the 15
  `hyprdots/*.jsonc` layout presets under `Configs/.local/share/waybar/layouts/`.
  Removing them per-layout is deferred to Slice 7 (pick one layout preset,
  delete the rest) rather than edited 15 times now.

## Personal installer

`install.sh` at the repo root (`--check` / `--dry-run` / `--install` /
`--repair` / `--build-hyq` / `--diagnose` / `--rollback`) drives
`installer/{lib,preflight,packages,deploy,runtime,validate,build-hyq,
diagnose,rollback}.sh`. It only ever asks for `sudo` once, for a single
confirmed `pacman -S --needed <official-repo packages>` call
(`installer/packages.manifest`); AUR (`wlogout`) is reported, never
auto-installed. `hyq` (build-from-source, no repo/AUR package) is a hard
runtime dependency, not "report and move on" — see "hyq: hard dependency,
not a warning" below. Deployment is driven by an explicit allow-list
(`installer/deploy.manifest`) — Configs/ also carries KDE/Dolphin/editor
config that must never be touched.

**Known caveat**: `deploy.manifest` includes whole directories
(`.config/hypr/`, `.config/waybar/`, `.config/rofi/`, `.config/swaync/`)
that also contain wallbash-*generated* files this repo happens to track a
stub/default version of (e.g. `Configs/.config/hypr/themes/colors.conf`
ships upstream HyDE's default placeholder colors). Every `deploy.sh` run
(part of `--install`/`--repair`) therefore overwrites the live
wallbash-rendered version of these files with the repo's placeholder,
relying on `runtime.sh` running immediately afterward to regenerate them.
This was already true before this session; it is more consequential now
that `runtime.sh` is fail-fast (see below) — if it stops early (e.g. `hyq`
missing), the deploy step has already left placeholder colours live until
the next successful `--repair`. Not fixed this session (would mean
deciding whether these generated paths belong in `deploy.manifest` at all,
a deliberate call for the user to make) — flagged here so it isn't
re-discovered from scratch.

### hyq: hard dependency, not a warning

`hyq` (`HyDE-Project/hyprquery`) is called unconditionally by
`color/hypr.sh` (no guard, previously - see below), `theme.switch.sh`,
`waybar.py`, and (guarded) `wallbash/scripts/swaync.sh`. Treating its
absence as a soft warning let `install.sh --install` continue straight
into a theme render that immediately hit `hyq: command not found` inside
`color/hypr.sh` (sourced from `color.set.sh`'s `load_dconf_kdeglobals`),
which failed silently — `color/hypr.sh` had no presence check and its `eval
"$(hyq ...)"` failure was never propagated, so `color.set.sh` printed `[ok]
wallbash render completed` regardless. Two independent fixes now close
this:

- **`color/hypr.sh`** now checks `command -v hyq` itself before calling it
  and `return`s/`exit`s 1 with a clear message if absent (it is always
  `source`d from inside `load_dconf_kdeglobals`, so `return 1` correctly
  propagates out of that function).
- **`color.set.sh`** now checks `load_dconf_kdeglobals`'s exit status and
  aborts (`exit 1`) instead of continuing into template rendering with a
  half-populated colour/theme environment.
- **`installer/lib.sh:hyq_gate()`** is called by `install.sh --install`/
  `--repair` *before* `runtime.sh` even starts, and again inside
  `runtime.sh` itself (defense in depth for anyone invoking it directly) -
  either one missing `hyq` stops the run with a nonzero exit and a pointer
  to `installer/build-hyq.sh`, before any theme/colour state is touched.
- **`installer/preflight.sh`**: `hyq` moved from the `optional` binaries
  list (warn) to the mandatory list (fail), and its presence check now also
  runs `hyq --help` to catch an installed-but-broken binary, not just a
  missing one.

**Building `hyq`**: upstream ships **CMake/C++23 source** (a `.clangd`/
`CMakeLists.txt`/`src/*.cpp` tree), **not Cargo/Rust** as earlier notes in
this repo (and HyDE's own `Scripts/`, before deletion) assumed —
confirmed by cloning the pinned tag and reading `CMakeLists.txt`/
`README.md` directly. `installer/build-hyq.sh`:

- prints the exact plan (pinned tag `v0.6.8.r1`, commit
  `50bacf226de0f8d7ea8fdc8f274a1620cfd084a1`, build dir, install target,
  and the fact that upstream's `CMakeLists.txt` `FetchContent`-fetches
  `spdlog` unconditionally and `CLI11`/`nlohmann_json`/`hyprlang` unless
  satisfied by installed packages — real additional network activity this
  script does not control) before doing anything;
- asks for confirmation (`installer/lib.sh:confirm()`) before any
  clone/build;
- clones the pinned ref, then verifies the checked-out commit hash exactly
  matches the pin - refuses to build if a tag moved upstream;
- builds with `cmake`/`cmake --build`, never `sudo make install`;
  `install -m 755` puts only `bin/hyq` into `~/.local/bin/hyq`;
- is idempotent via a marker file (`$INSTALLER_STATE_DIR/hyq.built-commit`)
  recording the built commit - a second run with the same pin is a no-op
  unless `--force`;
- never runs `sudo`, never touches anything outside its own state
  directory and `~/.local/bin/hyq`.

### Canonical theme manifest (`installer/theme.manifest`)

Directory existence (`themes/Default/` present) is not the same as
"complete" - the exact bug this session started from: `install.sh
--install` printed `a theme already exists (.../Default) - not creating
Default` for a `Default` directory that had `wall.png`/`wall.set` but no
`hypr.theme`, so every `hyq`/`get_hyprConf` read against it came back
empty. `installer/theme.manifest` now defines what a theme directory
actually needs, split REQUIRED (`wall.set`, `hypr.theme`) vs OPTIONAL
(`.sort`, `wallpapers/`, `theme.dcol`), derived from reading what
`color/hypr.sh`, `theme.switch.sh`, `globalcontrol.sh:get_themes`/
`get_hyprConf`, `waybar.py`, and `wallbash/scripts/swaync.sh` actually
touch under a theme directory - not guessed.

`installer/lib.sh:theme_missing_required()` checks a directory against
that manifest. `installer/runtime.sh:theme_repair_default()` only ever
runs against the `Default` theme this installer itself owns (never a
foreign/user-named theme dir - that case is only reported with `_warn`,
never auto-repaired): it backs up the whole directory first, then fills in
*only* the specific missing REQUIRED files -
`installer/templates/hypr.theme.default` (canonical `$KEY = value`
content, matching the same defaults already shipped in
`Configs/.local/share/hyde/env-theme`) for a missing `hypr.theme`, a fresh
offline gradient seed + relink for a missing `wall.set` - and re-checks
completeness afterward. Idempotent: re-running against an already-complete
theme is a no-op (verified directly against the live machine's `Default`
theme dir via a scratch copy, not the real one, during this session).

**Runtime state generation is not static file copying.** HyDE generates a
lot of config at runtime from a wallpaper via the wallbash pipeline
(`color.set.sh`, GNU `parallel` + ImageMagick), and this fork's `Configs/`
ships zero theme/wallpaper content by design (upstream HyDE fetches that
separately). Without a theme under `~/.config/hyde/themes/<name>/wall.set`,
wallbash has no color source and files like `~/.config/swaync/theme.css`
are never generated — that was the actual root cause behind the missing
`theme.css` import error, not a swaync-specific bug. `installer/runtime.sh`
fixes this by generating one offline gradient-PNG seed theme (ImageMagick,
no network) and running HyDE's real `color.set.sh` against it
(`reload_flag=1`, matching what `theme.switch.sh` normally exports; without
it `color.set.sh` silently skips every `theme/*.dcol` template with no
error) with `HYDE_KDEGLOBALS_FIX=0` so `kdeglobals`/Plasma colors are never
touched automatically.

**GNU parallel + zsh bug (fixed in `color.set.sh`)**: `color.set.sh` renders
each wallbash template via `parallel fn_wallbash {} ... ::: <templates>`,
where `fn_wallbash` is a bash function exported with `export -f`. GNU
`parallel` runs each job under `$SHELL`. On any account whose login shell is
zsh or fish (this fork's own documented shell choice — see CLAUDE.md), that
resolves to a shell that has no concept of bash's function-export mechanism,
so every job fails with "command not found" — silently, because
`color.set.sh`'s own failure-counting had a second bug (`render_failures`
used before being initialized, so the final `[ "$render_failures" -ne 0 ]`
itself errored and always evaluated false). **Net effect: no wallbash
template was ever rendered on this machine, for any theme, regardless of
whether a theme/wallpaper was configured.** Fixed by exporting
`PARALLEL_SHELL=/bin/bash` at the top of `color.set.sh` (forces parallel's
job shell independent of the user's login shell) and initializing
`render_failures=0` before it's first read.

## Lua runtime

**Two Lua interpreters coexist in the same process on purpose vs. by
accident.** `Hyprland` links `liblua.so.5.5` directly (Arch's `lua` package,
5.5) for its own embedded Lua config. Separately, `libinput.so.10` (system
package, unrelated to HyDE) links `liblua5.4.so.5.4` and genuinely calls
into it (`luaL_newstate`, `lua_pcallk`, `luaopen_base/math/string/table` —
confirmed via `nm -D --undefined-only`, this is libinput's own Lua
scripting support, not dead weight). Both shared objects export ~150
identical unversioned `lua_*`/`luaL_*` C symbols with no ELF symbol
versioning (Lua itself never uses `.symver`), so when both land in the same
process's global symbol scope, whichever was resolved first for a given
symbol wins for **every** caller of that symbol process-wide — including
libinput's internal calls, which could silently execute against the wrong
struct layout. `install.sh --check` / `preflight.sh` detects and reports
this (`detect_lua_abi_collision` in `installer/lib.sh`); it cannot be fixed
from this repository (both libraries are system packages Arch builds this
way) — reported as a standing risk, not "fixed."

**Full evidence chain** (re-run any time with `install.sh --diagnose`,
gathered live on this machine this session, package versions will drift):

```
$ readelf -d /usr/bin/Hyprland | grep NEEDED.*lua
 (NEEDED) Shared library: [liblua.so.5.5]     # Hyprland's OWN direct link - only this one

$ ldd /usr/bin/Hyprland | grep lua             # full transitive closure
 liblua.so.5.5   => /usr/lib/liblua.so.5.5
 liblua5.4.so.5.4 => /usr/lib/liblua5.4.so.5.4  # pulled in indirectly

$ readelf -d /usr/lib/libinput.so.10 | grep NEEDED
 ... [liblua5.4.so.5.4] ...                    # libinput links 5.4 directly

$ pacman -Qo /usr/lib/liblua.so.5.5 /usr/lib/liblua5.4.so.5.4 /usr/lib/libinput.so.10
 liblua.so.5.5   -> lua 5.5.1-1
 liblua5.4.so.5.4 -> lua54 5.4.8-6
 libinput.so.10  -> libinput 1.31.3-1
```

So the chain is `Hyprland -> liblua.so.5.5` (direct) and `Hyprland ->
libinput.so.10 -> liblua5.4.so.5.4` (transitive, one hop through an
official package). **Verdict, with evidence, not assumption:**

- **Not** a stale/foreign/AUR library — `lua`, `lua54`, and `libinput` are
  all official Arch repo packages, cleanly owned (`pacman -Qo` above).
- **Is** a real, live two-ABI coexistence in one process, and it is eagerly
  loaded (`DT_NEEDED`, not `dlopen`'d), so every process linking `libinput`
  on any current Arch system with `libinput >= 1.31` carries this, not
  something specific to this fork's install.
- **Whether it is an active "collision"** (actual unversioned-symbol
  interposition causing wrong behavior) vs. inert coexistence (libinput's
  Lua quirks path only actually calls into Lua when a `.lua` quirks file is
  loaded, which may never happen in normal use) was **not** further proven
  this session — flagged as "coexistence, evidence-gathered" in
  `preflight.sh`'s wording, not asserted as a confirmed active bug.
- **Not linked to the Aquamarine SIGSEGV crash** (see below): the crash's
  stack frames are entirely inside `libaquamarine.so`/DRM/EGL rendering
  code, a completely different subsystem from Lua config parsing or
  libinput's quirks loading. No evidence connects the two; do not treat
  fixing one as addressing the other.

**`lua-lgi` is broken under Lua 5.5, confirmed as a language-semantics
break, not a packaging mistake.** Lua 5.5 makes generic-`for` loop control
variables implicitly `<const>` (extending 5.4's numeric-`for` behavior).
`lgi`'s own `component.lua:68` (`/usr/share/lua/5.5/lgi/component.lua`,
part of the `lua-lgi` 0.9.2 Arch package) does `for en, idx in pairs(index)
do ... en = ... end` — reassigning the now-const loop variable — which is a
**compile-time** error under 5.5 ("attempt to assign to const variable
'en'"), before any of lgi's C code runs. This is upstream `lgi` not yet
updated for Lua 5.5's stricter loop-variable semantics; nothing in this
fork's own Lua code triggers it. Every call site was audited
(`grep -rln lgi Configs/`): `batterynotify.lua` already guarded `require
'lgi'` with `pcall` and degrades gracefully (pre-existing, not touched);
`open.lua` and `color/dconf.lua` did **not** and would hard-crash the whole
script on any `hyde-shell open` call or theme-apply run — both now wrapped
in the same `pcall` pattern (fixed this session). Net effect: DBus/GIO
features (default-app resolution, GTK/dconf sync at theme-apply time,
UPower battery notifications) degrade to "unavailable, logged, non-fatal"
instead of crashing their caller. `install.sh --check` runs `lua5.5 -e
"require('lgi')"` as a standing regression probe.

**Not fixed, left as an open choice for the user**: actually restoring lgi
functionality means either (a) waiting for upstream `lua-lgi` to ship a
Lua-5.5-compatible `component.lua`, or (b) building a separate Lua 5.1/5.2/
5.3 interpreter + `lgi` just for these three scripts and invoking them with
that interpreter explicitly (never mixed into Hyprland's own Lua 5.5
process — that would reintroduce the exact ABI collision risk described
above). `installer/packages.manifest` documents this as `lua51-lgi | source`
but does not install anything for it.

**Startup-critical audit** (every `require("lgi")`/`require 'lgi'` call
site, `grep -rln lgi Configs/`, classified this session): **none are
startup-critical** - a missing `lgi` never blocks Hyprland from starting or
the theme pipeline from completing.

| File | Called from | On missing `lgi` |
|---|---|---|
| `open.lua` | On-demand only (`hyde-shell open`), not in `hc.start.*` | `pcall`-guarded, `os.exit(3)` - that one file-open action fails, nothing else does |
| `color/dconf.lua` | `color/hypr.sh:load_dconf_kdeglobals` (theme-apply path, feature-critical for GTK/dconf sync, not startup-critical) | `pcall`-guarded, `os.exit(0)` - color.set.sh continues normally, only GTK/GNOME dconf sync is skipped |
| `batterynotify.lua` | `hc.start.battery_notify` (an actual startup daemon, launched as a systemd user service via `hyde-shell app`) | Already `pcall`-guarded (pre-existing). Prints a diagnostic and `return`s from `main()` before entering the GLib main loop - the service starts and exits cleanly instead of crashing; battery notifications just don't work. Does not block or delay Hyprland/session startup. |
| `luautils/global/log.lua` | Logging helper, many callers | **No actual `require("lgi")` in the file at all** - the header comment ("uses lgi logging when available") is stale/aspirational, there is no lgi code path here to guard or classify |

`install.sh --check` / the readiness gate only ever WARNs on `lgi`
unavailability (never fails readiness) precisely because of this audit -
see "graphical-session readiness gate" below.

## Graphical-session readiness gate

`install.sh --check` (`installer/validate.sh`) ends with a dedicated `==
graphical-session readiness ==` section and a final `[READY]` /
`[NOT READY]` verdict, separate from the diagnostic pass/warn/fail detail
above it. PASS-required (any failure here means `[NOT READY]`): deployment
complete, canonical theme complete (`installer/theme.manifest`), `hyq`
present and functional, `app2unit` present (see "Gray-screen startup
failure" below - without it the gate would previously say `[READY]` while
every daemon `start_up.lua` launches silently failed to start), runtime
generation successful (swaync/waybar `theme.css` non-empty), swaync CSS
valid enough to load (non-empty, no unresolved `<wallbash_*>` tokens,
`@import` targets exist on disk), Waybar config generated, UWSM resolves
`HYPRLAND_CONFIG` to a readable file,
Intel stays default compositor GPU with no session-wide NVIDIA
`__GLX_VENDOR_LIBRARY_NAME`/`GBM_BACKEND`, `xdg-desktop-portal-hyprland`
installed, `hyde.lua` parses (`luac -p`), SDDM is the active
`display-manager.service` (single-DE by design since 2026-08-25 — KDE
Plasma was deliberately removed once Hyprland was confirmed working; the
gate used to require a Plasma fallback, see ROADMAP.md). WARN-only, never
blocks readiness: `wlogout` missing (AUR,
optional), `lgi` unavailable (see the startup-critical audit above - never
blocks anything that actually needs to start).

Every check in the gate is self-contained (re-evaluates the same
underlying facts directly, e.g. `installer/lib.sh:check_nonempty_file()`/
`check_no_unresolved_wallbash_tokens()`/`check_css_imports_resolve()`/
`check_hypr_colour_state_complete()`, shared with `installer/runtime.sh`'s
own post-render verification) rather than threading state through the
preflight pass/warn/fail counters, so the gate section stays readable on
its own and can never silently disagree with the detail sections printed
just above it.

## Gray-screen startup failure (`install.sh --diagnose-startup`)

A real `uwsm`-managed Hyprland login (boot journal offset `-1`, session
10:32:31–10:38:38) produced a working compositor - `Hyprland` reached
"Started Main service for Hyprland", UWSM's activation environment resolved
correctly, `xdg-desktop-portal-hyprland` started - but an empty gray
surface: no Waybar, no wallpaper, no visible notification daemon activity
tied to HyDE. Root-caused by correlating that boot's
`journalctl --user -b -1` against `start_up.lua`'s dispatch list:

- **`app2unit` is not installed on this machine** (no official-repo/AUR
  package - see DEPENDENCIES.md) and was not documented anywhere in this
  fork before this audit. `Configs/.local/lib/hyde/app.sh` execs it
  unconditionally whenever `/run/systemd/system` exists - this is the sole
  dispatch path `hyde-shell app ...` uses for **every** daemon
  `start_up.lua` launches: Waybar (`waybar.py`), wallpaper (`wallpaper.sh`),
  `hypridle`, `hyprpolkitagent`/`polkitkdeauth.sh`, the config watcher,
  battery-notify, notifications. Without it, each dispatch was a plain
  `app2unit: command not found` (exit 127) in a forked shell - invisible
  from inside Hyprland (no systemd unit is ever created, so nothing reaches
  the journal at all) and easy to mistake for a compositor/theming problem.
  Confirmed against the actual boot journal: Waybar/wallpaper/hypridle/the
  polkit agent never appear anywhere in it, while SwayNC, `nm-applet`, and
  `blueman-applet` DID start - because those three reach the desktop
  through D-Bus activation and XDG autostart respectively, bypassing
  `hyde-shell`/`app2unit` entirely. Fix: `installer/build-app2unit.sh`
  (same pinned-commit, confirmation-gated pattern as `build-hyq.sh` - see
  above; upstream is plain POSIX shell, no compiler needed). `app.sh` now
  also checks for `app2unit` explicitly before exec'ing it, so a future
  absence fails with a clear stderr message and a line in
  `~/.local/state/hyde/log/startup.log` instead of a bare "command not
  found"; `install.sh --check` hard-fails `[READY]` on its absence.
- **`awww` (the default wallpaper backend, `hc.config.wallpaper.backend =
  "awww"`) was also missing** and undocumented. Unlike `app2unit`, it *is*
  in the official `extra` repo - added to `installer/packages.manifest`.
  `wallpaper.awww.sh` calls `awww`/`awww-daemon` with no fallback and no
  surfaced error, so even with `app2unit` fixed, a missing `awww` silently
  produces no wallpaper rather than an error.
- **SwayNC's own D-Bus service-activation file**
  (`/usr/share/dbus-1/services/org.erikreider.swaync.service`, a package
  file this fork does not own) advertises `org.freedesktop.Notifications`
  globally. `dbus-daemon` D-Bus-activates `swaync.service` on *any*
  notification request in *any* session - this bypasses the unit's own
  `[Install] WantedBy=graphical-session.target` state entirely, so leaving
  it "disabled" does nothing. Under a Plasma session this races
  `org.kde.plasma.Notifications.service` for the bus name, loses ("Could
  not acquire notification name"), `exit(1)`s, and hits systemd's
  start-limit-hit within about a second (`Restart=on-failure` retries 5x).
  Fixed with a systemd user drop-in,
  `Configs/.config/systemd/user/swaync.service.d/10-hyde-session-scope.conf`,
  gating the unit with `ConditionEnvironment=XDG_CURRENT_DESKTOP=Hyprland`
  - this reads systemd `--user`'s own activation environment (imported at
  session start via `hc.start.dbus_share_picker`/`systemd_share_picker` in
  `variables.lua`, populated from UWSM's `DesktopNames=Hyprland`), not the
  triggering process's environment, and a failed `ConditionEnvironment` is
  a silent skip, not a failure - no restart loop under KDE, and Plasma's
  own notification daemon is untouched. (Separately, the shipped
  `Configs/.config/swaync/style.css` had a missing `;` after its last
  `@import`, a real but non-fatal GTK CSS parser warning - fixed at the
  source template; see `tests/test_swaync_css.sh`.)
- `lgi` unavailability and a missing Python venv were both **verified not
  to be involved**: every `require('lgi')` call site (`open.lua`,
  `color/dconf.lua`, `batterynotify.lua`) already wraps it in `pcall` and
  none are on the `hyprland.start` critical path; the only Python component
  `start_up.lua` launches is `waybar.py`, whose imports are local, vendored,
  stdlib-only `pyutils` modules resolved via its own script directory under
  plain system `python3` - `hyde-shell app`'s dispatch path only activates
  the venv when `HYDEPY=1`, which `hc.start.bar` does not set.

`install.sh --diagnose-startup` (read-only, `installer/diagnose-startup.sh`)
turns this whole investigation into one command: a static graph (can every
piece resolve right now, without a session) plus a correlation against the
most recent Hyprland boot found in the retained `systemd --user` journal.

## Aquamarine crash (`install.sh --diagnose`)

The SIGSEGV inside `eglDestroyContext`/`Aquamarine::CDRMRenderer` teardown
(ROADMAP.md) is real and reproducible on this machine — `coredumpctl list
Hyprland` shows two actual SIGSEGV coredumps (PIDs `9065`, `43346`, one
from `session-9.scope`, one from the UWSM `wayland-wm@hyprland.desktop.service`
unit — i.e. real login sessions, not test runs) with byte-identical
`libaquamarine.so` stack traces, confirming the crash still occurs on
every session exit. `install.sh --diagnose` is a **read-only** report (no
driver/kernel/GRUB/Secure Boot/mkinitcpio changes, ever) covering: `lspci`
GPU info, `/dev/dri` + `/dev/dri/by-path`, DRM sysfs `uevent` per card,
loaded NVIDIA kernel modules + installed NVIDIA packages + `nvidia-smi`,
the live-resolved UWSM GPU env (same technique as
`preflight.sh:check_gpu_env_leak` — actually sources `01-gpu.sh` and prints
what it resolves to, not just greps the file text), EGL/GLVND vendor JSON
locations, Mesa/GLVND package versions, Hyprland/aquamarine versions and
linkage, the full Lua ABI evidence chain above, and
`coredumpctl list`/`info` for `Hyprland`. Corrected this session: the
closer upstream match is **`hyprwm/aquamarine#267`** ("SIGSEGV in
`CDRMRenderer::~CDRMRenderer` → `eglDestroyContext` during static
destruction"), not `#272` — #267 is reported on the same class of hardware
(Intel+NVIDIA hybrid laptop) with the identical frame sequence
(`CDRMRenderer::~CDRMRenderer` → `CDRMBackend::~CDRMBackend` →
`CBackend::~CBackend` → `__cxa_finalize`, i.e. a *static-destructor-order*
bug: the global `CSharedPointer<CBackend>` is torn down after the EGL
display it depends on), whereas `#272` is AMD Strix-Halo-specific with a
different signature (`SDRMConnector::disconnect`/render-path abort). Both
issues are still **open** upstream with no merged fix as of this session.
Per #267's own reporter, the practical impact beyond the coredump is that
`xdg-desktop-portal-gtk` can be left in a broken state, so GTK apps
(waybar, ghostty) may hang for minutes on the *next* login waiting on the
dead portal's D-Bus timeout — worth checking if a slow next-login is ever
seen. No forcing GPU env vars are present live on this machine (confirmed
again this session via the same `01-gpu.sh` resolution the readiness gate
checks), so there is no config-level lever here; a real fix needs either
an upstream aquamarine patch (explicit backend teardown before `exit()`,
or guarding `eglDestroyContext` against an already-torn-down display) or
would require touching the NVIDIA driver stack, which is out of scope per
CLAUDE.md's machine-safety boundaries. Monitoring upstream remains the
only lever; nothing here changes drivers.

**The SIGABRT (PID `3631`, earlier the same day) is unrelated and not a
bug to fix.** Its stack trace is a C++ exception thrown inside
`CCompositor::initServer` during *startup* (`__cxa_throw` →
`std::terminate` → `abort`, nothing in `libaquamarine`), and its cgroup
(`app-dev.zed.Zed@….service`) shows it was `Hyprland` launched bare from a
terminal inside Zed while the live session was actually KDE Plasma
(`kwin_wayland`, confirmed via the `nvidia-smi` process list and the
journal around that timestamp showing Plasma/Spectacle/KDE activity, no
compositor handoff). Running the `Hyprland` binary directly while another
compositor already holds the DRM master is expected to fail this way —
there is nothing in this fork's config to change for it.

**Session update — the exact `libseat`/logind mechanism behind the SIGABRT
class was captured live, and the SIGSEGV coredumps were re-examined and
reclassified.** A follow-up report described a *new* uncaught
`std::runtime_error: CBackend::create() failed!` (SIGABRT, not the
`#267` SIGSEGV) reproduced by running `Hyprland --config
/home/na/hypr-minimal.lua` and `start-hyprland -- -c
/home/na/hypr-minimal.lua` directly from a terminal, and asked whether
this was a new/different backend bug (GPU topology, EGL vendor selection,
multi-GPU modifiers, etc.). It is not — it is the same class of problem
already documented above (PID `3631`), now with the exact underlying error
captured by tailing Aquamarine's runtime log live during a reproduction:

```
ERR from aquamarine ]: [libseat] Could not take control of session: Device or resource busy
ERR from aquamarine ]: No backend was able to open a seat
ERR from aquamarine ]: Failed to open a session
ERR from aquamarine ]: DRM Backend failed
```

`loginctl seat-status`/`session-status` at the time of the test confirmed
the terminal was running inside the currently **active** seat0 session
(`kwin_wayland`, KDE Plasma Wayland, `Active=yes`) — i.e. the exact same
"launched from inside another compositor's session" scenario as PID `3631`,
just via `Hyprland --config`/`start-hyprland` instead of a bare `Hyprland`
invocation from Zed's terminal. `Aquamarine::CBackend::create()` tries its
DRM backend first, which needs `logind`'s `TakeControl()` on the seat;
since `kwin_wayland` already holds it, `TakeControl()` returns `EBUSY` and
the DRM backend aborts before ever touching Intel/NVIDIA topology, EGL
vendor selection, GBM, or modifiers — none of that machinery is reached.
What happens next depends only on whether a fallback is available: in this
reproduction `WAYLAND_DISPLAY` was inherited from the parent shell, so
Aquamarine's Wayland (nested) backend backend succeeded instead and ran
cleanly for the rest of the test (no crash) — it only aborts with
`CBackend::create() failed!` when *no* fallback backend can succeed either,
as with `start-hyprland`/session-service invocations that don't inherit a
live parent Wayland socket. **This is a test-methodology artifact, not a
GPU/EGL/Aquamarine/hybrid-graphics bug** — none of the upstream areas the
report asked to investigate (`AQ_DRM_DEVICES`, `AQ_MGPU_NO_EXPLICIT`,
`AQ_NO_MODIFIERS`, EGL vendor forcing, multi-GPU renderer/buffer issues,
GBM device selection) are implicated by this evidence, and building the
requested `AQ_DRM_DEVICES` backend test matrix now would only re-measure
the same seat conflict under different env vars, not real GPU behaviour.
A real test needs an empty VT with no compositor already holding seat0 —
see `installer/diagnose.sh`'s new "Seat / session ownership" section,
which now flags this condition read-only, no launches performed.

**The three most recent SIGSEGV coredumps with a real `wayland-wm@
hyprland.desktop.service` user unit (`43346`, `48540`, `53055`) were
re-examined against the full `journalctl --user -u
wayland-wm@hyprland.desktop.service` transcript for each, not just the
coredump backtrace, and reclassified as shutdown-only crashes, not startup
failures.** For `53055` specifically: the unit is `Type=notify`, systemd
logged `Started Main service for Hyprland` ~2s after launch (Hyprland sent
its own readiness notification, meaning `CBackend::create()` **succeeded**
and monitors were live), `xdg-desktop-portal-hyprland` connected and
enumerated the full Wayland protocol interface list, `swaync` started and
loaded its config/CSS, `wireplumber` came up — a genuinely working ~24-
second Hyprland session, not a grey screen. The SIGSEGV only happened
*after* `systemd[…]: Stopping Main service for Hyprland…` was already
logged, i.e. during requested shutdown, matching the exact `#267`
`CDRMRenderer::~CDRMRenderer → eglDestroyContext` static-destructor-order
stack already on file. `installer/diagnose.sh` now has a "Coredump
classification" section that automates this correlation (coredump
timestamp vs. that unit's `Stopping…` journal line, ±5s window) for every
future `coredumpctl list Hyprland` entry, so this doesn't need re-deriving
by hand next time. **Net effect: as of this session, there is no evidence
of an unresolved startup-blocking backend failure in a real (non-nested,
non-manual) Hyprland login on this hardware** — the only outstanding,
already-documented issue is the cosmetic `#267` exit-time coredump.
Confirming this requires the user to actually watch a clean login (ideally
from an empty VT, to also rule out the seat-conflict class entirely) rather
than further log archaeology.

## Components retained unchanged

Hyprland (Lua config), UWSM (session env only — HyDE never launches the
session itself, it just supplies `env.d`/`env-hyprland.d` fragments and
hooks `uwsm finalize`/`uwsm stop` into Lua event handlers), Waybar, hyprlock,
hypridle, hyprpolkitagent, xdg-desktop-portal-{hyprland,gtk}, rofi (used in
~29 call sites — swapping it out would mean rewriting most of
`~/.local/lib/hyde`), wallbash, `hyde-shell`.
