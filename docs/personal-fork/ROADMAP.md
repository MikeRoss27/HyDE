# Roadmap

## Post-Slice-8 (cont. 5) — SDDM live, Plasma removed: single-DE by design

User confirmed the SDDM/qylock migration below was actually completed
out-of-band since it was written (`installer/setup-sddm.sh` and
`installer/migrate-greetd-to-sddm.sh` both ran, live-verified this session:
`readlink -f /etc/systemd/system/display-manager.service` →
`sddm.service`, theme `pixel-rainyroom` active) and that KDE Plasma has been
deliberately uninstalled entirely (`pacman -Q plasma-desktop plasma-meta`
finds nothing) — the user's stated end goal ("eventually drop KDE Plasma
entirely," see the greetd/ReGreet entry below) is reached: Hyprland is now
the only session, by design, already verified by the user before this was
raised here.

This broke three things still written against the old plasmalogin/KDE
world, found by live-checking rather than trusting the docs above (which
were correct when written, stale after the removal):

- `install.sh --check` hard-failed `[NOT READY]` — `installer/validate.sh`'s
  readiness gate required `plasma-desktop`/`plasma-meta` as a fallback
  session. **Fixed**: gate now checks that `display-manager.service`
  resolves to `sddm.service` instead (the actual live login path), not a
  Plasma fallback that's no longer meant to exist.
- `Configs/.local/lib/hyde/security-status.sh` still checked
  `plasmalogin.service`, `/usr/lib/pam.d/plasmalogin`, and
  `/etc/plasmalogin.conf*` for its "Connexion et verrouillage"/autologin
  section — all would misreport now that plasmalogin doesn't exist.
  **Fixed**: checks `sddm.service`, `/etc/pam.d/sddm`, and an
  `[Autologin]` section under `/etc/sddm.conf.d/` instead.
- `Configs/.local/lib/hyde/control-center.sh`'s "Réglages" rofi menu had 7
  of its ~13 entries pointing at KDE System Settings tools
  (`kcmshell6`, `systemsettings`, `kinfocenter`, `plasma-discover`) —
  confirmed via `command -v` that **all four are now absent**. **Fixed**:
  "Gestionnaire de connexion" is now a read-only kitty summary
  (`systemctl is-active sddm.service` + the active theme file, with the
  manual `sudo installer/switch-sddm-theme.sh` command printed rather than
  wired in directly — that script lives under `installer/`, which is
  dev-checkout-only and never deployed to `$HOME`, so a deployed rofi
  script can't call it by a reliable path); "Applications par défaut" now
  opens `mimeapps.list` in the editor instead of `kcm_componentchooser`;
  "Comptes utilisateurs" (`kcm_users`, no non-KDE equivalent, single-user
  laptop) and "Tous les réglages KDE" (`systemsettings`, nothing left to
  open) were dropped rather than faked; "Pare-feu" now shows
  `firewall-cmd --state`/`--list-all` read-only (`firewall-config` GUI
  isn't installed); "Sécurité du firmware" now runs `fwupdmgr security`;
  "Informations système" now runs `fastfetch`; "Mises à jour" now runs
  `checkupdates` (list-only, no `pacman -Syu` — consistent with this
  fork's no-automatic-installs rule) — all in a held kitty window, same
  pattern the menu already used for "Résumé des écrans actifs".

**Verified live**: `bash Configs/.local/lib/hyde/security-status.sh` run
directly - all "Connexion et verrouillage" lines now read `[OK]` against
the real SDDM state; `sh -n` on all three edited scripts;
`./install.sh --check` re-run end to end - now prints `[READY]` (previously
`[NOT READY]` on the Plasma-fallback line alone, every other check already
passing). Both live deployed copies under `~/.local/lib/hyde/` were synced
to match the repo-tracked fix (they run from `$HOME`, not from the
checkout).

**Not done / left as-is**: `docs/personal-fork/SECURITY.md`'s
"Live login and dual-boot baseline (2026-08-23)" section still describes
`plasmalogin.service` as active - left as a historical snapshot (annotated
with a superseded-by note) rather than rewritten, since it was accurate
when captured. `.audit/` (untracked swaync screenshots) and
`Configs/.config/autostart/` (untracked KDE Connect + pam_kwallet autostart
entries) were flagged during this session's audit but not touched - the
user hasn't said whether the autostart entries are wanted going forward
now that Plasma is gone.

## Post-Slice-8 (cont. 4) — SDDM + qylock (pixel-rainyroom/pixel-cyberpunk) login screen, replacing greetd/ReGreet

User wants a real animated login screen (video background, custom QML UI)
instead of ReGreet's plain GTK4 form, specifically the `pixel-rainyroom`
theme (default) and `pixel-cyberpunk` theme (switchable) from
[Darkkal44/qylock](https://github.com/Darkkal44/qylock) (GPL-3.0), properly
integrated into this fork rather than installed alongside it.

**Architecture decision, researched before touching anything**: migrate
from greetd/ReGreet back to **SDDM**, Wayland-native, no KDE/Plasma
install. qylock's themes are Qt6/QML `sddm-theme`s (`metadata.desktop`
declares `Type=sddm-theme`, `QtVersion=6`) whose `Main.qml` calls
`sddm.login()`/`sddm.reboot()`/`sddm.powerOff()` and reads `userModel`/
`sessionModel`/`SddmComponents 2.0` — an API that only exists inside SDDM's
own greeter process. ReGreet is a GTK4 app with a completely different
plugin model; hosting this QML unmodified under greetd would mean
reimplementing the theme from scratch, which the user explicitly ruled out
("ne tente pas de reproduire artificiellement ce design dans ReGreet").
Confirmed live on this machine (read-only) before deciding:
- `qt6-declarative`, `qt6-multimedia`, `qt6-multimedia-ffmpeg`,
  `qt6-5compat`, `qt6-svg` (6.11.2-1) are **already installed** (pulled in
  by the existing KDE/Plasma install) — only the `sddm` package itself and
  a Wayland-greeter host compositor are actually missing.
- `sddm` is **not** installed; `greetd`/`greetd-regreet`/`kmscon` are (and
  `greetd.service` is the live, working `display-manager.service` — the
  prior "greetd/ReGreet login chain" entries below already got this
  working, including the VT1/kmscon fix).
- SDDM's Wayland greeter needs a host compositor via `CompositorCommand=`.
  Researched three options: `CompositorCommand=Hyprland` (real forum
  reports — Arch Linux Forums #289612 — of it rendering only the wallpaper
  with no greeter window, an unacceptable regression class right after all
  the kmscon/VT1 debugging already in this file), `cage` (no confirmed
  SDDM-specific precedent found — its common pairing is greetd/ReGreet, a
  different codepath), and **weston with no `CompositorCommand` override**
  (SDDM's own documented default when `DisplayServer=wayland` is set — the
  one path actually described as the tested default). Chose weston.

**Built** (`installer/sddm/` — versioned source; nothing under `/etc` or
`/usr` was touched):
- `themes/pixel-rainyroom/`, `themes/pixel-cyberpunk/` — vendored unmodified
  from qylock commit `f86d3f6` (2026-08-24): `Main.qml`,
  `BackgroundVideo.qml`, `bg.mp4`, `font/PixelifySans-Bold.ttf`,
  `metadata.desktop`, `theme.conf`. Only these 2 of qylock's ~40 themes
  were copied in, not the full repo (not the Quickshell-lockscreen half
  either — out of scope, this is the SDDM login screen only).
  `themes/LICENSE-qylock` (full GPL-3.0 text, unchanged) and
  `themes/CREDITS.md` (author, commit, wallpaper source (MoeWalls) and
  font (Pixelify Sans, OFL) credits, as qylock's own README attributes
  them) carry the license/attribution forward per the user's explicit
  requirement.
- `sddm.conf.d/10-theme.conf` — `[Theme] Current=pixel-rainyroom`,
  `ThemeDir=/usr/share/sddm/themes`.
- `sddm.conf.d/20-wayland.conf` — `[General] DisplayServer=wayland`,
  `Numlock=on`; `[Wayland] SessionDir=/etc/sddm/hyde-sessions`,
  `GreeterEnvironment=XKB_DEFAULT_LAYOUT=fr`. Comments in the file record
  the compositor decision above and the keyboard-layout caveat below.
- `installer/setup-sddm.sh` — root-only, `setup-greetd.sh`-style
  (`set -eu`, refuses non-root, refuses to run if
  `/usr/share/wayland-sessions/hyprland-uwsm.desktop` is missing). Backs up
  any existing `/etc/sddm.conf.d/` (timestamped), installs the two conf
  files, deploys both vendored themes to `/usr/share/sddm/themes/`, and
  creates `/etc/sddm/hyde-sessions/hyprland-uwsm.desktop` as a **symlink**
  to the packaged file — never a copy, so it can't drift, and never touches
  `hyprland.desktop`/`plasma.desktop` under `/usr/share/wayland-sessions/`
  at all. This is the "no three useless session choices" requirement: SDDM
  is pointed at a fork-owned `SessionDir` containing only the one entry,
  instead of masking/deleting anything under the package-owned directory.
- `installer/switch-sddm-theme.sh rainy-room|cyberpunk` — root-only, the
  requested one-command theme switch. Edits `Current=` in
  `/etc/sddm.conf.d/10-theme.conf` only; does not restart `sddm.service` or
  touch a live session (takes effect at the next greeter start).
- `installer/migrate-greetd-to-sddm.sh` — root-only, mirrors
  `switch-display-manager.sh`'s preflight rigor exactly: refuses unless
  `/etc/sddm.conf.d/` byte-matches `installer/sddm/sddm.conf.d/` (i.e.
  `setup-sddm.sh` ran), `sddm`/`weston` binaries and both theme dirs are
  actually present, the `hyde-sessions` symlink resolves, and the
  kmscon/VT1 conflict (documented below, in the "greetd boot falls back to
  tty1" entry) is still clear — that race applies identically to sddm's own
  greeter process on VT1. Then `systemctl disable greetd.service &&
  systemctl enable sddm.service`. Does **not** remove `greetd`/
  `greetd-regreet` (kept installed+disabled as the rollback path) and does
  **not** start sddm live — reboot-to-test, same policy as
  `switch-display-manager.sh`. Rollback printed on every run:
  `sudo systemctl disable sddm && sudo systemctl enable greetd`, or from a
  TTY (Ctrl+Alt+F2..F6) if the graphical session never comes up.
- `installer/packages.manifest` — added `sddm`, `weston` (both missing,
  official `extra` repo, picked up by `install.sh --install`'s existing
  single-confirmation `pacman -S --needed` step) and `greetd`,
  `greetd-regreet`, `kmscon` (already installed, added for manifest
  completeness — they were undocumented gaps left over from the earlier
  ad hoc greetd work below).

**Verified (read-only, no `sudo`, nothing executed as root)**: `sh -n` and
(shellcheck unavailable on this machine, same fallback as prior entries)
on all three new scripts; `python3 -c 'import configparser; ...'` parses
every new `.conf`/`.desktop` file into the expected sections/keys;
`localectl status` confirms the machine's real layout is already `fr`
(`VC Keymap: fr`, `X11 Layout: fr`) so `XKB_DEFAULT_LAYOUT=fr` matches;
`readlink -f /etc/systemd/system/display-manager.service` confirms greetd
is still the live, untouched DM; `pacman -Q` confirms `sddm`/`cage`/
`weston` are genuinely absent and the Qt6 modules qylock needs are already
present.

**Not done (by design)**: no package installed, no file written under
`/etc` or `/usr`, no systemd service enabled/disabled/started — greetd is
still the active display manager. `installer/setup-sddm.sh` and
`installer/migrate-greetd-to-sddm.sh` both require `sudo` and are left for
the user to run and review themselves, same hard boundary as every prior
DM-related entry in this file. Next steps for the user, in order:
1. `./install.sh --install` (or `installer/packages.sh --install`) to get
   the single confirmed `pacman -S --needed sddm weston` prompt.
2. `sudo installer/setup-sddm.sh`
3. `sudo installer/migrate-greetd-to-sddm.sh`
4. Reboot, verify the Rainy Room greeter, French keyboard input in the
   password field, and login into Hyprland-UWSM. The one flagged
   uncertainty is keyboard layout on SDDM's Wayland greeter specifically —
   sddm/sddm#1528 documents cases where layout selection doesn't take on
   Wayland even when configured; if `fr` doesn't apply, that's the first
   thing to report back, with a plain `systemctl disable sddm && systemctl
   enable greetd` rollback available immediately from a TTY.
5. `sudo installer/switch-sddm-theme.sh cyberpunk` (or `rainy-room`) to
   change theme at any time afterward.

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

## Post-Slice-8 (cont.) — greetd/ReGreet login chain, decoupling from plasmalogin

User's end goal: eventually drop KDE Plasma entirely. First step: make the
Hyprland login chain (greetd → ReGreet → `Hyprland (uwsm-managed)`) fully
independent of Plasma, without touching Plasma yet.

**Origin, established by reading the machine, not assumed**: `greetd` and
`greetd-regreet` (0.10.3-2 / 0.5.0-1) were already installed on this machine
and `/etc/greetd/{config.toml,regreet.toml}` already existed, dated the same
day as this audit — but neither the repo (any branch, `git log`/`grep` on
`greetd|regreet` across `origin` and `upstream/master` all came back empty)
nor upstream HyDE has ever referenced greetd/ReGreet anywhere. This was a
manual, undocumented on-machine install, not part of this fork.

**Found broken**: the live `/etc/greetd/config.toml` had
`command = "regreet"` — ReGreet is a GTK4/`gtk4-layer-shell` app, not a
compositor; run bare like this it has no Wayland session to draw into and
greetd would just restart-loop it. `greetd-regreet`'s own pacman dependency
graph pulls in `hyprland` directly (confirmed via `pacman -Qi hyprland`,
"Required by: greetd-regreet") and `cage` isn't installed — so the intended
wrapper on this system is Hyprland itself, not cage.

**Built** (`installer/greetd/` — versioned source; nothing under `/etc` was
touched):
- `config.toml` — `command = "env HOME=/var/lib/regreet start-hyprland --
  --config /etc/greetd/hyprland.lua"`, `user = "greeter"`. `start-hyprland`
  (not the bare `Hyprland` binary) per the current Hyprland wiki's Master
  Tutorial ("Launching Hyprland"), confirmed live: `start-hyprland -h` prints
  its watchdog-wrapper usage and passes `--` args straight to Hyprland.
  `HOME` is overridden to `/var/lib/regreet` because the `greeter` system
  user's real home is `/` (read-only root, `dr-xr-xr-x`) — Hyprland/GTK would
  fail writing cache/state there. `/var/lib/regreet` (and `/var/log/regreet`)
  already exist, `greeter`-owned 755, provisioned by
  `greetd-regreet`'s own `tmpfiles.d` — not something we created.
- `hyprland.lua` — minimal **native Lua** Hyprland config (Hyprland 0.56.2
  loads `.lua` directly, confirmed against the live `hl.on`/`hl.exec_cmd`
  API and the Hyprland wiki's Autostart docs), isolated from
  `~/.local/share/hypr/hyde.lua`/`~/.config/hypr/hyprland.lua` — no HyDE
  bindings, no daemons. Sets `input.kb_layout = "fr"` to match this
  machine's real layout (`localectl status` → `VC Keymap: fr`; the login
  screen must accept password input in the right layout). On
  `hyprland.start`, execs `regreet; hyprctl dispatch exit` — Hyprland quits
  cleanly the moment ReGreet hands off (success or cancel) instead of
  lingering.
- `regreet.toml` — unchanged from the live file (already correct: dark
  theme, French greeting, `systemctl reboot/poweroff`), just brought under
  version control.
- `setup-greetd.sh` — root-only, `finalize-workstation-root.sh`-style
  (`set -eu`, refuses non-root). Backs up the existing `/etc/greetd/` (whole
  dir, timestamped) and installs the three files above with
  root:root/644. Does **not** touch any systemd service or plasmalogin.
- `switch-display-manager.sh` — root-only. Refuses to run unless
  `/etc/greetd/*` already matches `installer/greetd/*` byte-for-byte (i.e.
  `setup-greetd.sh` ran first) and unless `regreet`/`start-hyprland`/`uwsm`
  and the `hyprland-uwsm.desktop` session file are all present. Then:
  `systemctl disable plasmalogin.service && systemctl enable greetd.service`
  — the two units share the same `Alias=display-manager.service`, so
  disabling the old one first avoids any alias conflict — then prints the
  resulting `is-enabled`/`is-enabled`/`readlink -f
  display-manager.service` state. Deliberately does not start greetd live;
  the plan is reboot-to-test, not a live DM swap. Never runs
  `pacman -R` on anything.

**Verified on the live machine (read-only, no `sudo`)**: `greetd.service`
already correctly declares `Conflicts=getty@tty1.service` /
`After=getty@tty1.service` for VT1 (mirrors `plasmalogin.service`'s own
`Conflicts=getty@tty1.service`), and `getty@tty1.service` is
disabled/inactive — no VT contention. PAM chain
(`greetd` → `system-local-login` → `system-login`) includes
`pam_systemd.so`, so `XDG_RUNTIME_DIR`/logind session setup for the
`greeter` user works the same way it does for a normal login. Three session
`.desktop`s are present for ReGreet to list: `hyprland-uwsm.desktop`,
`hyprland.desktop`, `plasma.desktop` — Plasma stays selectable throughout.
`luac -p` on `hyprland.lua`; `sh -n` on both new scripts (`shellcheck` isn't
installed on this machine, so that check was skipped — `sh -n` was used
instead, per this doc's own verification-commands fallback).

**Not done (by design, stopped here)**: nothing under `/etc` was written,
no systemd service was enabled/disabled/started, plasmalogin is still the
active `display-manager.service`, KDE/Plasma packages untouched. Running
`setup-greetd.sh` and `switch-display-manager.sh` both require `sudo` and
are left for the user to run and review themselves — this assistant does
not run `sudo` per this fork's hard boundaries. Next actual DM switch and
the post-reboot verification are a separate, explicitly-approved step.

## Post-Slice-8 (cont.) — greetd boot falls back to tty1: root cause and fix

By the time of this entry `switch-display-manager.sh` had already been run
(by the user, out of band) — `greetd.service` is enabled and
`display-manager.service` points at it — and `/etc/greetd/{config.toml,
hyprland.lua}` had already been hand-patched live to `dbus-run-session
start-hyprland -- -c ...` and `hl.dsp.exit()` (both confirmed correct
against current community greetd+ReGreet+Hyprland examples). Yet every
boot still landed on a plain `tty1` login prompt instead of the ReGreet
screen.

**Root cause, found via `journalctl -b -1 -u greetd` / `coredumpctl` /
`systemctl status kmsconvt@tty1.service`, not assumed**:
`/etc/systemd/system/kmsconvt@.service` — a manual, undocumented unit
created directly on this machine on 2026-08-22 (owned by no pacman package,
referenced nowhere in this repo or upstream HyDE) — is aliased to
`autovt@.service` and enabled on `tty1` via `getty.target`. The prior audit
entry above checked only `getty@tty1.service` (correctly inactive) and
concluded "no VT contention," missing that `kmsconvt@tty1.service` is a
*different* unit that greetd's `Conflicts=getty@tty1.service` does nothing
to stop. On boot, both greetd and kmscon try to become DRM master on
`/dev/dri/card1` for `tty1`. kmscon loses the race, hits an unhandled error
path in its `drm_shared` backend and segfaults
(`systemd-coredump`/`coredumpctl` confirmed `SIGSEGV` in
`drm_shared.c:set_drm_master`) — and its `TTYVHangup=yes`/`TTYReset=yes`
cleanup on `tty1` kills the Hyprland/ReGreet session greetd had just
started there, before Hyprland logs a single line (`journalctl -b 0
_COMM=Hyprland` — no entries). greetd then reports `error: check_children:
greeter exited without creating a session` and deactivates; systemd's
`OnFailure=getty@tty1.service` in `kmsconvt@.service` starts a bare
`agetty` on `tty1` — exactly the observed symptom.

**Fixed** (`installer/`):
- `fix-vt1-conflict.sh` — new, root-only. Disables the
  `kmsconvt@tty1.service` instance and removes the `autovt@.service` alias
  symlink so no future VT activation on `tty1` re-spawns kmscon there.
  Leaves the `kmsconvt@.service` unit file and the `kmscon` package in
  place (not this fork's to remove) in case the user wants it on a
  different tty later.
- `switch-display-manager.sh` — added a preflight check that refuses to
  enable greetd if `kmsconvt@tty1.service`/`autovt@.service` is still
  enabled, pointing at `fix-vt1-conflict.sh`, so this exact failure mode
  can't silently recur on a future reinstall.
- `installer/greetd/{config.toml,hyprland.lua}` — the repo copies had
  drifted behind the live, already-fixed files (still had the older
  `start-hyprland -- --config ...` without `dbus-run-session`, and
  `hyprctl dispatch exit` instead of `hl.dsp.exit()`); synced to match live
  so `setup-greetd.sh` can no longer overwrite a working config with a
  stale one.
- Removed two stray, superseded root-level files (`greetd-config.toml` —
  an even earlier draft with `command = "regreet"`, the exact bug already
  documented above as "found broken" — and a duplicate `regreet.toml`);
  `installer/greetd/` is the single source of truth.

**Verified (read-only, no `sudo`)**: `sh -n` on all four installer scripts;
`luac -p` on `hyprland.lua`; `python3 -c 'import tomllib; ...'` on
`config.toml`/`regreet.toml`; confirmed via `WebSearch` that
`dbus-run-session start-hyprland -- -c <path>` matches current
community-maintained greetd+ReGreet+Hyprland examples (not just this
machine's own prior fix). Not verified by an actual reboot — that step is
still the user's, deliberately, per this fork's hard boundaries (no
`sudo`, no service enable/disable/restart performed by this assistant).
