# Roadmap

## Post-Slice-8 (cont. 3) — Aquamarine "CBackend::create() failed" reclassified as seat conflict, not GPU bug

A follow-up report claimed a *new* backend-creation failure (`CBackend::
create() failed!`, SIGABRT) below HyDE, distinct from the already-documented
`#267` SIGSEGV teardown crash, and asked for an `AQ_DRM_DEVICES` backend
test matrix, GPU-topology diagnostics, and a possible Aquamarine repackage.
Investigated by live-capturing Aquamarine's runtime log during a
reproduction and re-reading the full `journalctl --user -u wayland-wm@
hyprland.desktop.service` transcripts (not just coredump backtraces) for
the existing SIGSEGV coredumps. Full findings in `docs/personal-fork/
ARCHITECTURE.md` ("Session update" under "Aquamarine crash"). Summary:

- **The SIGABRT is a test-methodology artifact, not a GPU/EGL/Aquamarine
  bug.** `Aquamarine`'s DRM backend needs `logind` `TakeControl()` on
  seat0; every reproduction was launched from a terminal inside the
  already-active KDE Plasma Wayland session, so `TakeControl()` fails with
  `EBUSY` (`[libseat] Could not take control of session: Device or
  resource busy`) before any Intel/NVIDIA/EGL/GBM/modifier code runs.
  Whether this then aborts (`CBackend::create() failed!`) or silently
  falls back to Aquamarine's nested Wayland backend (no crash) depends only
  on whether `WAYLAND_DISPLAY` was inherited from the launching shell —
  neither outcome is evidence about hybrid-GPU compatibility. **Did not**
  build the requested `AQ_DRM_DEVICES`/`AQ_MGPU_NO_EXPLICIT`/
  `AQ_NO_MODIFIERS` probe matrix or touch any Aquamarine/EGL env vars — it
  would only re-measure the same seat conflict, not real GPU behaviour.
  **Did not** pursue a custom Aquamarine package/patch for the same reason.
- **The three most recent SIGSEGV coredumps with a real systemd session
  unit (`43346`, `48540`, `53055`) are shutdown-only crashes, not startup
  failures.** Cross-checking each against its unit's journal shows
  `CBackend::create()` succeeded (systemd `Started Main service for
  Hyprland` readiness notification, portals/swaync/wireplumber all came up
  live), and the SIGSEGV happened only after `Stopping Main service for
  Hyprland…` was already logged — the known `#267`
  `CDRMRenderer::~CDRMRenderer → eglDestroyContext` exit-time bug, already
  on file, not a new issue.
- **`installer/diagnose.sh` gained two read-only sections**: "Seat /
  session ownership" (reports the active seat0 session/compositor and
  explains the `EBUSY` mechanism so this doesn't get re-litigated by hand
  next time) and "Coredump classification" (auto-correlates each
  `coredumpctl list Hyprland` entry's timestamp against its unit's
  `Stopping…` journal line to label it shutdown-cosmetic vs.
  startup-needs-investigation vs. manual-test-expected). Both are pure
  queries — no launches, no env vars set, no drivers touched.
- **Open item, not addressed this session (requires the user, not more log
  archaeology)**: confirm by actually watching a clean login — ideally from
  an empty VT with no other compositor holding seat0, to also rule out the
  seat-conflict class entirely — that Hyprland renders a real desktop and
  not a grey screen. If that still fails, that is the one scenario this
  session's evidence does not yet cover, and would be the actual next
  backend-level investigation.

## Post-Slice-8 (cont. 2) — hyq hard dependency, theme completeness, fail-fast runtime, readiness gate
Follow-up after a real `./install.sh --install` + `--check` run (37
pass/4 warn/0 fail) still left the runtime in a broken state: `hyq:
command not found` scrolled by during install but nothing failed, and the
`Default` theme was silently missing `hypr.theme`. Full findings in
`docs/personal-fork/ARCHITECTURE.md` ("Personal installer", "hyq: hard
dependency", "Canonical theme manifest", "Lua runtime", "Graphical-session
readiness gate", "Aquamarine crash"). Summary:

- **`hyq` is now a hard dependency, not a warning.** `color/hypr.sh` had no
  presence check before calling `hyq` and its failure was never
  propagated - `color.set.sh` now checks `load_dconf_kdeglobals`'s exit
  status and aborts. `installer/preflight.sh` moved `hyq` (and `magick`,
  `parallel` - equally hard-required, previously unchecked) from the
  optional/warn list to the mandatory/fail list, and checks `hyq --help`
  actually runs, not just `command -v`. `install.sh --install`/`--repair`
  now call `installer/lib.sh:hyq_gate()` and stop **before** touching any
  theme/colour state if `hyq` is absent.
- **Built `installer/build-hyq.sh`**: deterministic, pinned-commit,
  confirmation-gated build of `hyq` (`HyDE-Project/hyprquery`) into
  `~/.local/bin/hyq` only, never `sudo`. Corrected a wrong assumption in
  this repo's own notes and `installer/packages.manifest`/
  `DEPENDENCIES.md`: upstream is **CMake/C++23**, not Cargo/Rust - found by
  actually cloning the pinned tag and reading `CMakeLists.txt`.
- **Canonical theme manifest** (`installer/theme.manifest`): directory
  existence is not completeness. `installer/runtime.sh` now backs up and
  repairs only the missing REQUIRED files of its own `Default` theme
  (`installer/templates/hypr.theme.default` for a missing `hypr.theme`),
  never touches a foreign/user theme beyond reporting it. Verified against
  a scratch copy of the live machine's actual incomplete `Default` theme
  this session (real bug, real fix, not hypothetical).
- **Runtime init is fail-fast end to end**: `installer/runtime.sh` now
  semantically verifies its own output (non-empty, not just `test -e`; no
  unresolved `<wallbash_*>` tokens; `@import` targets in generated CSS
  actually exist) instead of trusting `[ok] wallbash render completed`
  blindly, and `install.sh --install`/`--repair` now `die` (not
  `log_warn`) on a runtime-init failure.
- **Optional wallbash noise reduced**: `installer/runtime.sh` now
  classifies `fn_wallbash`'s "skip 'missing directory'" warnings against a
  known-optional-component keyword list (Kvantum, Spicetify, vim, gtk-4.0,
  qt5ct/qt6ct) and collapses matches into one summary line; anything not
  matching stays fully visible. `HYDE_KDEGLOBALS_FIX` stays `0`, nothing
  KDE/Kvantum-related is created or mutated.
- **Lua ABI collision**: gathered the full evidence chain this time
  (`readelf -d`, `ldd`, `pacman -Qo`) instead of asserting it - confirmed
  official-package coexistence (`lua`/`lua54`/`libinput`, not
  foreign/AUR), confirmed unrelated to the Aquamarine crash's stack
  frames, still not proven to be an *active* interposition bug (vs. inert
  coexistence) - documented as such, not overclaimed either direction.
- **`lgi` startup-critical audit**: every call site classified
  (`open.lua` on-demand/feature-only, `color/dconf.lua` theme-apply-time
  but self-degrading, `batterynotify.lua` a real startup daemon that
  degrades to a clean no-op instead of crashing, `luautils/global/log.lua`
  has no actual `lgi` dependency despite its comment). None are
  startup-critical - confirmed with evidence, not assumed.
- **Fixed a real latent bug found while testing the above**:
  `Configs/.config/uwsm/env-hyprland.d/00-hyde.sh` referenced
  `$HYDE_ACTIVATED` unguarded (`[ -z "$HYDE_ACTIVATED" ]`) - harmless under
  a normal shell, but breaks under `set -u` (which is exactly how the new
  UWSM-resolution readiness check needed to probe it). Fixed to
  `${HYDE_ACTIVATED:-}`.
- **Added `install.sh --diagnose`**: read-only GPU/DRM/EGL/NVIDIA/Lua-ABI/
  coredump report. Confirmed live on this machine: the documented
  Aquamarine SIGSEGV coredump is real (`coredumpctl` shows it with
  `libaquamarine.so` frames) and still unrelated to the Lua ABI
  coexistence; also surfaced a previously-undocumented `Hyprland` SIGABRT
  coredump from earlier the same day. A later session investigated both
  further: the SIGSEGV matches upstream `hyprwm/aquamarine#267` (a closer
  match than the `#272` originally cited — see ARCHITECTURE.md), and the
  SIGABRT turned out to be an unrelated `initServer()` exception from
  running the `Hyprland` binary directly inside a terminal while KDE
  Plasma already owned the session, not a bug.
- **Added a `[READY]`/`[NOT READY]` graphical-session readiness gate** to
  `install.sh --check` - see ARCHITECTURE.md for the exact PASS/WARN
  criteria.

**Verified live on this machine**: `installer/build-hyq.sh` run to the
confirmation prompt (declined, non-interactively - plan-printing and
build-dependency checks execute correctly, no network/build attempted);
`theme_missing_required`/`theme_repair_default` exercised directly against
a scratch copy of the real (incomplete) `Default` theme dir, confirmed
idempotent on a second run; `install.sh --diagnose` run for real (read-only
by construction); `install.sh --check` re-run after the `00-hyde.sh` fix
was deployed, confirming the UWSM readiness check now passes. A `deploy.sh`
run during this testing incidentally overwrote several live
wallbash-generated files with their repo-tracked placeholder content (see
"Known caveat" in ARCHITECTURE.md's "Personal installer" section) - restored
from the automatic pre-write backup before finishing.

**Not done this session (`hyq` genuinely absent, needs the user's explicit
go-ahead per their own stated requirement before any network/build
activity)**: `install.sh --build-hyq` was not run to completion, so the
`Default` theme was not actually repaired against a real render, and
`install.sh --check` still reports `[NOT READY]` on this machine pending
that. Next command for the user: `./install.sh --build-hyq`, then
`./install.sh --repair`, then `./install.sh --check`.

## Post-Slice-8 (cont.) — first real install + runtime debugging + personal installer
User asked to stop auditing and start fixing the live machine, build a real
installer, and keep KDE/SDDM-equivalent untouched as fallback. Full findings
in `docs/personal-fork/ARCHITECTURE.md` ("Personal installer" and "Lua
runtime" sections). Summary:

- **Corrected a stated assumption**: the display manager is `plasmalogin`
  (KDE's SDDM successor), not `sddm` — `sddm` isn't even installed.
  `readlink -f /etc/systemd/system/display-manager.service` is the ground
  truth; `installer/preflight.sh` checks both.
- **Fixed**: `open.lua`/`color/dconf.lua` hard-crashed instead of degrading
  when `lgi` fails to load (Lua 5.5 incompatibility, see ARCHITECTURE.md) -
  now `pcall`-guarded like `batterynotify.lua` already was.
- **Fixed**: `color.set.sh` never actually rendered any wallbash template on
  this machine, for any theme - GNU `parallel` runs jobs under `$SHELL`,
  which is zsh here, and zsh can't see bash's `export -f` functions. Fixed
  via `PARALLEL_SHELL=/bin/bash`. Also fixed an unrelated pre-existing bug
  in the same script: `render_failures` was read before being initialized.
- **Root-caused, documented, not fixed in-repo** (system packages, not
  ours to patch): a Lua 5.4/5.5 unversioned-symbol collision between
  Hyprland's own `liblua.so.5.5` and `libinput.so`'s `liblua5.4.so.5.4`.
- **Built**: `install.sh` + `installer/*.sh` - a from-scratch, idempotent,
  no-upstream-installer-code personal installer. Never touches GRUB/EFI/
  Secure Boot/mkinitcpio/kernel params/NVIDIA drivers/sudoers/partitions,
  never removes KDE, never replaces the display manager, only ever asks for
  `sudo` once (a single confirmed `pacman -S --needed` call for
  official-repo packages). `installer/deploy.manifest` and
  `installer/packages.manifest` are the explicit, reviewable source of
  truth for what gets deployed/installed.

**Verified live on this machine**: `bash tests/run.sh` (20/20, unchanged);
`./install.sh --check` (37 pass / 4 warn / 0 fail - the 4 warnings are the
documented Lua ABI collision, `lgi` incompatibility, and the two
not-auto-installed `hyq`/`wlogout` dependencies); a full
`./install.sh --install --yes` then `./install.sh --repair --yes` run,
confirming `~/.config/swaync/theme.css` and the rest of the wallbash output
(`~/.config/hypr/themes/colors.conf`, `~/.cache/hyde/wallbash/*.css`, etc.)
now actually get generated.

**Not done / explicitly out of scope this slice**: the Aquamarine
`SIGSEGV` crash inside `eglDestroyContext` during process exit
(`Aquamarine::CDRMRenderer` teardown) matches an open upstream issue
(hyprwm/aquamarine#267, a static-destructor-order bug - see
ARCHITECTURE.md; #272 was an earlier, less precise citation) rather than
anything in this fork's config - no forcing GPU env vars were found live,
so there was nothing here to fix; monitoring upstream is the only lever.
`hyq` (HyDE-Project/hyprquery) has no repo/AUR package and was not built
from source without the user's explicit go-ahead. `wlogout` (AUR) was not
installed. Actually restoring `lgi` functionality (vs. graceful
degradation) needs either an upstream `lua-lgi` fix or a separate pinned
Lua 5.1-5.3 interpreter, not attempted here - see ARCHITECTURE.md.

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
