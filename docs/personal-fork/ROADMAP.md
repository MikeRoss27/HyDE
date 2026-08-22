# Roadmap

## Post-Slice-8 — full runtime security audit and hardening
Not one of the original 8 slices — a user-requested complete security audit
of everything left under `Configs/` now that `Scripts/` is gone (the entire
remaining code-execution surface). Full findings in
`docs/personal-fork/SECURITY.md`. Fixed: `hyprlock.sh`'s MPRIS album-art
fetch (was `curl`-ing an attacker-settable URL into ImageMagick on every
lock), the hyprlock layouts' daily unauthenticated font auto-download from a
third-party domain, an `eval`-based injection gap in `rofi.websearch.sh`,
and the same pattern in `restore.config.sh`. Flagged but **not** fixed
blind: a CRITICAL-potential issue in `hypridle`'s `unlock_cmd` trusting an
unauthenticated `loginctl unlock-session` signal to kill the lock
screen — needs the user to verify actual behavior on a live session before
any fix is safe to write (see SECURITY.md for the exact test to run).

Ordered, reviewable slices. Each slice: inspect diff, grep for dangling
references to anything removed, run relevant static checks (shellcheck,
Lua syntax), fix regressions, commit only when explicitly requested.

## Slice 1 — Documentation foundation (this slice)
`docs/personal-fork/{ARCHITECTURE,DEPENDENCIES,SECURITY,ROADMAP}.md` +
`CLAUDE.md`. Zero functional changes. Establishes the source of truth so
later slices don't re-derive this session's findings.

**Verify**: `git status` shows only new doc files; no config/script changes.

## Slice 2 — App assumption replacement — SKIPPED
Originally planned as Kitty → Ghostty, VS Code → Zed. The user revisited
this after Slice 1 and chose to keep both Kitty and VS Code — no concrete
reason to switch was found, and VS Code is still occasionally useful to
them. No code changes needed; see DEPENDENCIES.md for the updated KEEP
rows. Not revisited unless the user asks again.

## Slice 3 — Package manifest reduction — SUPERSEDED BY SLICE 5
Originally planned as editing `Scripts/dots-groups/*.toml` to drop
`dunst`/`cliphist`/`udiskie`/Chaotic-AUR before deleting `Scripts/`. Since
Slice 5 deletes the manifests outright, editing them first would have been
pure waste — `docs/personal-fork/DEPENDENCIES.md` is the package source of
truth going forward, already reflecting every KEEP/REPLACE/REMOVE decision
(including oh-my-zsh being kept). No manifest editing was needed.

## Slice 4 — Startup daemon trim — DONE
Edited `Configs/.local/share/hypr/lua/variables.lua` (`hc.start.*` table),
`start_up.lua` (matching `check_exec` calls removed rather than left as
silent no-ops), `key_binds.lua` (`MOD+V`/`MOD+SHIFT+V` clipboard keybinds
removed), and `hyde/dispatcher.lua` (dead `menu.clipboard`/`menu.cliphist`
entries removed): dropped `text_clipboard`, `image_clipboard`,
`clipboard_persist`, `applet_removable_media` (udiskie); swapped
`notifications` from `dunst` to `swaync`.

**Verified**: `luac -p` syntax check passed on all four edited files;
`grep -rn` for the removed `hc.start.*` keys and dispatcher menu names
across `Configs/` returned no remaining references.

**Known follow-up (deferred to Slice 7)**: waybar's
`custom-cliphist.jsonc`/`custom-clipboard.jsonc` module definitions still
exist and are still referenced by all 15 `hyprdots/*.jsonc` layout presets
under `Configs/.local/share/waybar/layouts/`. They're inert until cliphist
is actually removed from the package set (Slice 3) and would then be a
broken/dead waybar button — not fixed now because doing it once the user
has picked a single active layout (Slice 7) avoids editing 15 files whose
majority will be deleted anyway.

## Slice 5 — Delete `Scripts/` — DONE
Confirmed first (`grep -rln "Scripts/" Configs/ docs/ CLAUDE.md tests/`)
that nothing under `Configs/` depends on `Scripts/` at runtime — only the
deploy manifests referenced it, and `DEPENDENCIES.md` already supersedes
those as the package source of truth. Deleted:
- `Scripts/` wholesale (installer, `dots`/`dots-groups` manifests,
  migrations, `extra/`, `hydevm/`).
- Root `dots.toml` — it only existed to `include` the now-deleted
  `Scripts/dots/*.toml` files and run `Scripts/install_aur.sh` as a
  `pre_command`; nothing else referenced it.
- Tests that exclusively exercised the installer/manifest/migration
  machinery: `test_install_env.sh`, `test_install_restore.sh`,
  `test_migrations.sh`, `test_shell_choice.sh`, `test_icon_theme.sh`,
  `test_dots.sh`, `test_hyprlang_leftovers.sh`, `test_install_config.sh`,
  `test_wallbash_targets.sh`, and their Python backends
  `check_dots.py`/`check_install_config.py`/`check_wallbash_targets.py`.
  These tested migration/deploy behavior that has no code left to exercise
  once `Scripts/` is gone — not general repo quality checks.

Two tests mixed installer coverage with coverage of code we keep; trimmed
rather than deleted:
- `test_theme_state.sh` — dropped its `Scripts/install.sh` existence check
  and the three `installer_flat` assertions about the installer's
  theme-switch error handling; kept everything testing the wallbash/theme
  runtime under `Configs/.local/lib/hyde/`.
- `test_lua_entry_point.sh` — dropped the `Scripts/migrations/v26.8.1.sh`
  exercise (chmod/symlink/backup behavior of a migration script that no
  longer exists); kept and preserved the loader-runs-once check (now driven
  directly off the shipped `Configs/.config/hypr/hyprland.lua` instead of a
  migration-produced copy) and the real-tree entry-point harness check.
- `test_shell.sh` also had a stale `find` path over `$REPO_ROOT/Scripts`
  (printed a harmless-but-noisy "no such file" to stderr) — removed.

**Verified**: `grep -rln "Scripts/" tests/ Configs/ docs/personal-fork/ CLAUDE.md`
now only matches this roadmap's own prose and `tests/README.md`/`test_references.sh`'s
historical mention — no executable path left pointing at `Scripts/`.
`bash tests/run.sh` — 20/20 cases pass, no stderr noise.

**Not done in this slice** (left for later, out of scope for "delete the
installer"): `Source/arcs/*.tar.gz` and `Source/assets` are still present
(DEPENDENCIES.md marks them "REMOVE — repo cleanup"); root prose docs
(`README.md`, `CONTRIBUTING.md`, `TESTING.md`, `Hyprdots-to-HyDE.md`,
`MIGRATION-LUA.md`, `.github/`) still describe the upstream project/installer
and were not rewritten — they're inert documentation, not something the fork
executes, so cleaning them up is a documentation pass, not a safety issue.

## Slice 6 — Theming simplification — SKIPPED (by user request)
User likes the current visual system as seen in screenshots/renders — no
wallbash/theme pipeline changes. Not revisited unless asked.

## Slice 7 — Personalization (scoped to keybinds only, by user request)
Monitors/input/touchpad/workspace personalization and animation/layout/
workflow preset pruning are **not** being done now — the user wants to keep
all 16 animation presets, all 5 layouts, and all 5 workflow profiles
available to try later rather than deleting any of them. Scope is limited
to keybind changes the user specifies explicitly, applied to
`Configs/.local/share/hypr/lua/key_binds.lua` (and `hyde/dispatcher.lua` if
a new action needs a dispatcher entry). Revisit the broader personalization
scope (monitors, input, preset pruning) only if the user asks for it later.

**Done — AZERTY workspace-switching fix**: all shipped keybinds use the US
QWERTY keysym for their key (e.g. digits `1`..`0`), which breaks on a
French AZERTY layout for the number row specifically: the unshifted top-row
keys produce `& é " ' ( - è _ ç à`, not digits, so `MOD+1`..`MOD+0`
(workspace switching, in all three variants: focus, move-window, move-window
silently) never fired. Fixed in `key_binds.lua` by binding directly on the
keysym the French layout actually produces (`ampersand`, `eacute`,
`quotedbl`, `apostrophe`, `parenleft`, `minus`, `egrave`, `underscore`,
`ccedilla`, `agrave` for 1..0) via a `ws_key` lookup table, instead of the
raw digit. Hyprland's native `.conf` `code:N` (hardware-keycode) escape
hatch was tried first but is **not supported** by this Lua config's
`hl.bind` — confirmed by `tests/lua/bind_harness.lua`'s explicit
"uses a keycode, which the Lua bind parser does not accept" check — so the
per-layout-symbol approach is the correct fix here, not a workaround.

**Verified**: `luac -p` syntax check passed; `bash tests/run.sh` — 20/20
pass, including `test_binds` re-validating all 162 binds for conflicts.

**Not changed, flagged for the user to test on the real keyboard**: the
`MOD + period` (glyph picker) bind may have the same root cause — French
AZERTY needs Shift to produce `.` — while `MOD + comma` (emoji picker) and
`MOD + slash`/`MOD + SHIFT + slash` (binds hint / web search) are unshifted
on French AZERTY and should already work. Not touched without confirmation
since getting this wrong would silently break a working bind; report back
which ones don't fire and they'll be fixed the same way as the workspace
keys.

## Slice 8 — Intel/NVIDIA hybrid-graphics tuning — DONE
No kernel driver, module, or bootloader changes — purely Hyprland/session
env vars, as scoped. Finding: both `Configs/.local/share/hypr/lua/env.lua`
(NVIDIA hook) and `Configs/.config/uwsm/env.d/01-gpu.sh` (`0101`
hybrid-intel-nvidia case) were **forcing NVIDIA as the session-wide
renderer** whenever the driver was detected as loaded
(`__GLX_VENDOR_LIBRARY_NAME=nvidia`, `LIBVA_DRIVER_NAME=nvidia`,
`GBM_BACKEND=nvidia-drm`) — the opposite of "Intel as the normal compositor
GPU, NVIDIA for offload." These files aren't live on the machine yet (this
fork has never been deployed via an installer), so fixing them now doesn't
touch anything currently running.

Changes:
- `env.lua`: removed the forcing block entirely (and the now-unconsumed
  `has_nvidia_working()` detection function with it — dead code once
  nothing branches on it). Nothing is set here now; VA-API/GLX/GBM all fall
  through to Mesa/Intel by default.
- `01-gpu.sh`: removed `__GLX_VENDOR_LIBRARY_NAME=nvidia` and
  `VK_LAYER_NV_optimus=1` from the hybrid case. `NVD_BACKEND=direct` is left
  in place — it's inert unless something explicitly requests the NVIDIA
  VA-API driver, which nothing does by default anymore.
- New `Configs/.local/lib/hyde/gpu-offload.sh` (executable, wired into the
  existing `hyde-shell <name>` resolution automatically — no dispatcher
  changes needed): `hyde-shell gpu-offload <command> [args...]` sets
  `__NV_PRIME_RENDER_OFFLOAD`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`,
  `__VK_LAYER_NV_optimus=NVIDIA_only`, `DRI_PRIME=1` for that one process
  only, then `exec`s it. No sudo, no network, no daemon — a plain env-var
  wrapper the user points at whichever specific app needs the discrete GPU
  (e.g. a game launch command, or a `.desktop` file's `Exec=`).

**Verified**: `luac -p` on `env.lua`, `sh -n` on both shell files;
`bash tests/run.sh` — 20/20 pass (`test_shell` now parses 94 files,
+1 for `gpu-offload.sh`).

**Follow-up — generic NVIDIA launcher**: the user doesn't know in advance
which app(s) will need the NVIDIA GPU, so rather than pre-wiring one
specific app, added a generic rofi launch mode: `MOD + SHIFT + N` opens
rofi's typed-command ("run") entry with `-run-command` pointed straight at
`hyde-shell gpu-offload {cmd}` instead of the default `app.sh` path — typing
any command name launches it with the offload env vars already set, no
intermediate systemd-run/app2unit layer that could reset them before exec.
Implementation: `Configs/.local/lib/hyde/rofilaunch.sh` (`n | --nvidia`
case, modeled on the existing `r | --run` case), `hyde/dispatcher.lua`
(`menu.nvidia_run` entry), `key_binds.lua` (the keybind itself). This only
covers rofi's "run" (typed) mode, not "drun" (clicking an app icon) — that
tradeoff was chosen deliberately over wrapping app.sh/app2unit, whose
environment-forwarding behavior for a plain `exec` wrapper wasn't something
that could be verified without a live session to test against.

**Verified (updated)**: `luac -p` on the two edited Lua files, `sh -n` on
`rofilaunch.sh`; `bash tests/run.sh` — 20/20 pass.
