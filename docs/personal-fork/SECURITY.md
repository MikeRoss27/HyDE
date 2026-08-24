# Security

HyDE's installer (`Scripts/`) was never executed against the live machine,
was audited below, and has since been **deleted from this fork**
(ROADMAP.md Slice 5) — `DEPENDENCIES.md` now captures what it used to
install. This document is a historical record of that audit (why deletion
was the right call), not a live threat model for code that remains in the
fork.

## Live login and dual-boot baseline (2026-08-23)

**Superseded (2026-08-25)**: KDE Plasma has since been removed entirely by
the user (`pacman -Q plasma-desktop plasma-meta` finds nothing) — single-DE
by design, Hyprland only. `plasmalogin.service` no longer exists; SDDM is
the active `display-manager.service` (see ROADMAP.md "SDDM live, Plasma
removed"). The baseline below is a historical snapshot from before that
change, kept for the record — read it as "what was true then," not current
state.

The workstation keeps Windows permanently in a dual boot. The Microsoft
boot files, the shared EFI system partition, and all Windows partitions are
therefore protected state, not migration leftovers to remove.

- `plasmalogin.service` is the active display manager. No Plasma Login
  autologin setting was found. Its PAM service includes `system-login`, and
  the system authentication chain uses `pam_unix` plus `pam_faillock`.
- Live journal evidence confirmed two incorrect Plasma Login passwords were
  rejected before a correct password opened the session. A separate
  incorrect Hyprlock password was also rejected. `/etc/pam.d/hyprlock`
  includes the standard `login` PAM chain.
- Hypridle locks before suspend and does not contain the former insecure
  signal-driven `unlock_cmd`.
- Secure Boot is enabled, TPM 2.0 is present, and firewalld is active.
- Linux boots through the active `SHIM with GRUB Secure Boot` entry from the
  shared EFI partition. `Windows Boot Manager` remains active on that same
  partition, and `/boot/EFI/Microsoft` is present.
- Linux root is the dedicated Btrfs partition `/dev/nvme0n1p5`; the Windows
  partitions are neither mounted nor referenced by Linux's `fstab`.
- The Linux root volume is not encrypted. AppArmor is installed but disabled
  by the current kernel configuration. Enabling either is a separate,
  explicitly approved system/boot project; this fork does not silently touch
  the kernel command line, initramfs, EFI, partitions, or filesystems.

`hyde-shell security-status` exposes these checks read-only from the unified
settings menu. It performs no remediation and ends by restating the dual-boot
invariant.

## Vendored SDDM greeter theme review (qylock, 2026-08-24)

`installer/sddm/themes/{pixel-rainyroom,pixel-cyberpunk}/` vendors two QML
themes from a third-party GPL-3.0 repo ([Darkkal44/qylock](https://github.com/Darkkal44/qylock),
commit `f86d3f6`) that will run inside the SDDM greeter process — i.e. before
any user authenticates, on every boot. Reviewed both themes' `Main.qml`/
`BackgroundVideo.qml` (the only executable content; `theme.conf`/
`metadata.desktop` are plain ini) before vendoring:
`grep -niE "exec|process|xmlhttprequest|openurl|shell|system\(|Qt\.include|import \"http|network"`
across both files returned no matches other than an unrelated
`isQuickshell`/`Quickshell` identifier substring. Neither theme makes
network calls, spawns processes, or loads remote content — `BackgroundVideo.qml`
plays the bundled local `bg.mp4` via `QtMultimedia.MediaPlayer`, and the
only privileged calls made are `sddm.login()`/`sddm.reboot()`/
`sddm.powerOff()`, SDDM's own sanctioned greeter JS API (same surface every
SDDM theme uses). See ROADMAP.md "SDDM + qylock" entry for the full
integration decision.

## System mutation surfaces (stock HyDE installer)

| Surface | Mutated by | Default or opt-in |
|---|---|---|
| `/etc/pacman.conf` | `install_pre.sh` (Color/multilib/ParallelDownloads) | Default (first run) |
| Full system upgrade | `install_pre.sh` (`pacman -Syyu`) | Default (first run) |
| Chaotic-AUR repo + keyring | `install_pre.sh` + `chaotic_aur.sh` | Opt-in prompt, **defaults to yes on timeout/bad input** |
| AUR helper build+install | `install_aur.sh` (`git clone` + `makepkg -si`) | Default on `install` |
| Bootloader (GRUB/systemd-boot) | `install_pre.sh` (backup, `sed`, `grub-mkconfig`, `nvidia_drm.modeset=1` kernel param) | Default whenever GRUB/systemd-boot detected |
| NVIDIA driver + kernel boot params | `install.sh` (TOML-driven install) + `install_pre.sh` (bootloader cmdline) | Default when NVIDIA GPU detected (opt-out via `-n`) |
| initramfs/`mkinitcpio`, `/etc/modprobe.d` | `Scripts/extra/install_mod.sh` | **Dead code** — not called from `install.sh` |
| systemd services (system + user) | `restore_svc.sh` (`sudo systemctl <verb>` from a data file) | Default on `services` op |
| Display manager (SDDM) config/theme | `install_pst.sh` (`/etc/sddm.conf.d`, `/usr/share/sddm/themes`) | Default when SDDM installed |
| System-wide theme/font archives (`/usr/share/...`) | `install_pre.sh`, `install_pst.sh`, `restore_fnt.sh`, `theme.patch.sh` (root tar extraction, some from separately git-cloned repos) | Default/conditional on writability |
| Remote script execution (`curl\|sh`) | `restore_shl.sh` (oh-my-zsh install/upgrade), `restore_cfg.sh` (`uv` installer fallback) | Default-yes prompts / fallback path |
| Login shell | `restore_shl.sh` (`chsh`) | Default when shell choice differs |
| `/etc/fstab`, disk labels | `Scripts/extra/drivext_mnt.sh` | **Dead code** — personal script, not wired in |

## Highest-severity findings (why deletion, not patching)

**CRITICAL**
- `Scripts/restore_shl.sh:32,39` — `sh -c "$(curl -fsSL https://install.ohmyz.sh/)"` and an equivalent upgrade line: curl-pipe-to-shell with no integrity check, default-yes prompt.
- `Scripts/restore_cfg.sh:298` — `curl -LsSf https://astral.sh/uv/install.sh | sh` fallback if the pacman path for `uv` fails.
- `Scripts/chaotic_aur.sh:122,128` — `pacman -U --noconfirm` of packages fetched from a third-party CDN as root, plus a permanent `[chaotic-aur]` repo added to `/etc/pacman.conf`; reachable via a prompt in `install_pre.sh` that **defaults to yes** on timeout or invalid input.
- `Scripts/install_pre.sh:63` — `sudo grub-mkconfig -o /boot/grub/grub.cfg` regeneration after scripted `sed` edits to `/etc/default/grub` — boot-breaking blast radius if the edit is wrong, runs by default whenever GRUB is detected.

**HIGH**
- `Scripts/install_pre.sh:95-103` — backs up then rewrites `/etc/pacman.conf`, then `sudo pacman -Syyu` — a full system upgrade as a side effect of a HyDE install, unscoped from HyDE itself.
- `Scripts/install_aur.sh:32,40` — `git clone` of an AUR helper + `makepkg -si` (root install via sudo internally), unconditional on a default install.
- `Configs/.local/lib/hyde/theme.patch.sh:235` — `sudo tar -xf` extracting an SDDM theme archive from a separately git-cloned, unpinned `hyde-themes` repo into `/usr/share/sddm/themes` — supply-chain risk (content isn't from the audited main repo).
- `Scripts/restore_svc.sh:62` — `sudo systemctl "${cmd_array[@]}" "${service}.service"` where the verb/service come from a data file (`restore_svc.lst`) — an injection-shaped pattern if that file were ever untrusted (it isn't, today).

**MEDIUM/LOW** (see `Scripts/install_pre.sh`, `install_pst.sh`, `restore_fnt.sh`, `restore_cfg.sh` `eval echo "${pth}"` pattern) — scoped mostly to `$HOME` or gated behind explicit prompts; not blocking.

## Dead/orphaned scripts (confirmed unreachable from `install.sh`)

`Scripts/extra/install_mod.sh`, `Scripts/extra/drivext_mnt.sh` (hardcoded personal disk labels), `Scripts/extra/restore_app.sh`, `Scripts/extra/restore_lnk.sh`, `Scripts/hydevm/` (dev VM tooling with its own `eval`/curl surface, entirely disconnected from the install call graph). These would be zero-impact to delete on their own; in this fork they go with the rest of `Scripts/`.

## Mitigation applied in this fork

- **`Scripts/` has been deleted outright** (ROADMAP.md Slice 5), not
  patched — the installer will never run on this machine, and every finding
  above was removed by removing the code, not by adding guards around it.
  The root `dots.toml` manifest (which only existed to drive `Scripts/`'s
  deploy tool and ran `Scripts/install_aur.sh` as a `pre_command`) was
  deleted with it.
- Package installation going forward is manual, against official Arch
  repos, per `DEPENDENCIES.md` — the one exception is `wlogout` via an AUR
  helper (paru/yay), a deliberate, scoped, user-approved exception, not an
  automated bootstrap.
- No bootloader, kernel, mkinitcpio, or NVIDIA driver state is ever touched
  by this fork's tooling — those remain entirely manual, out-of-band changes
  the user makes themselves.
- CLAUDE.md (repo root) encodes "never run install*.sh / any system-mutating
  script, no sudo, no package installs" as a standing rule for future work
  in this repo.

## Runtime audit (post-Slice-5) — the ~50 `Configs/.local/lib/hyde/` scripts

With `Scripts/` gone, this is the entire remaining code-execution surface:
`Configs/.local/bin/hyde-shell` will `exec` any `.lua`/`.sh`/`.py` file
matching a requested name with no allowlist (`hyde-shell:286-334`), reached
via keybinds, waybar clicks, rofi menus, and a few background daemons.
Three independent sweeps covered the shell scripts, the ~49 Python scripts,
and the waybar/rofi/lock UI-integration layer. Overall: the codebase is
notably careful about the classic mistake (building shell commands out of
attacker-controlled strings — window titles, clipboard, network responses)
— almost everything shells out via argv lists, not string interpolation.
The real issues cluster in two places: the lock/idle trust model, and a
couple of automatic network-fetch paths with no verification.

### CRITICAL — fixed conservatively; still worth verifying live

**`hypridle`'s `unlock_cmd` trusted an unauthenticated signal to kill the lock screen.**
`Configs/.config/hypr/hypridle.conf` bound `general.unlock_cmd` to
`sh -c 'sleep 3 && pkill -9 $(hyde-shell lockscreen --get)'`. hypridle runs
this whenever it sees the session's logind `Unlock` signal — but that same
D-Bus signal can be fired by any local unprivileged process via
`loginctl unlock-session <id>` (session IDs are enumerable, no password
needed), independent of whether `hyprlock` ever authenticated anyone.
Depending on how strictly Hyprland's `ext-session-lock-v1` implementation
follows the protocol's design (a killed lock client should never reveal the
desktop), this was either a denial-of-service (lock screen killed, user
stuck behind a blank screen) or, in the worst case, a full no-password
bypass.

**Fixed**: `unlock_cmd` is removed rather than patched. The line existed
purely as a stray-process cleanup convenience (per its own comment) — it
plays no role in the actual unlock, which happens when hyprlock itself
exits after successful PAM auth, independent of this binding. Removing it
can only reintroduce the (purely cosmetic) old cleanup gap it was added
for; it cannot weaken authentication, since it was never part of the
authentication path. **Still worth verifying** once deployed: lock the
screen, watch whether hyprlock exits cleanly on its own after a real
unlock. If it ever lingers, that's a hygiene issue to solve separately
(e.g. gate the cleanup on hyprlock's own exit code) — not by reintroducing
a kill triggered by an unauthenticated signal.

### HIGH — fixed in this fork

- **`Configs/.local/lib/hyde/hyprlock.sh` (`mpris_thumb`)** — read the
  now-playing track's `artUrl` from `playerctl` and `curl`'d it unvalidated
  into ImageMagick (`magick`) on every lock screen render. MPRIS metadata,
  including `artUrl`, can be set by *any* unprivileged local process
  (including a web page via the browser's MediaSession API) — this is an
  attacker-triggered SSRF-style fetch feeding unvalidated remote content
  into a parser (ImageMagick) with a long CVE history, and it fired
  automatically with no user action. **Fixed**: only `file://` URIs are
  now used (copied locally, no network fetch); any other scheme is skipped
  and no thumbnail is shown for that track.
- **`Configs/.local/share/hypr/hyprlock.conf:40`** — ran
  `cmd[update:86400000] font.sh resolve "$LAYOUT_PATH"` once a day by
  default: `font.sh` downloads and auto-extracts an archive from whatever
  domain a hyprlock layout's `$resolve.font` line names, with no
  checksum/signature check. Several bundled layouts (`Anurati.conf`,
  `Arfan on Clouds.conf`, `SF Pro.conf`) point at the third-party domain
  `font.download` — not GitHub, not HyDE-owned, not reviewed. **Fixed**:
  the automatic daily trigger is removed; running
  `hyde-shell font.sh resolve "$LAYOUT_PATH"` explicitly still works if a
  layout's font is genuinely missing, but it's now an informed, one-time
  user action instead of a silent background fetch.

### MEDIUM — two fixed, others documented (require an existing local foothold or an explicit rare action)

- **`Configs/.local/lib/hyde/rofi.websearch.sh`** — built `SITES[key]=...`
  assignments via `eval` from `websearch.lst`, escaping `"`/`\` in the
  `url`/`icon` fields but not in `key`. A crafted `key` (e.g. from a
  downloaded rice/theme's `websearch.lst`) could break out of the eval'd
  string and run arbitrary code. **Fixed**: `key` is now escaped the same
  way as `url`/`icon`.
- **`Configs/.local/lib/hyde/restore.config.sh`** — expanded `~`/`$VAR` in
  each list-file's path field via `eval echo "$pth"` (two call sites);
  since `restore.config` is directly callable with any list file
  (`hyde-shell restore.config <list> <dir>`), a crafted field could run
  arbitrary code. **Fixed**: replaced with `~` prefix substitution +
  `envsubst` (expands `$VAR` against the real environment only, never
  executes anything).
- **`Configs/.local/lib/hyde/theme.patch.sh` / `theme.import.py`** — still
  present (this logic lives under `Configs/`, not the deleted `Scripts/`):
  `git clone`s a theme URL, then `sudo tar -xf`s an archive into
  `/usr/share/sddm/themes` when `$HOME`-scoped paths aren't writable, and
  copies theme-authored config (potentially including Hyprland
  `exec-once =` lines) into `$HOME/.config`. Confirmed **no automatic
  caller remains anywhere in `Configs/`** — the only path in is an explicit
  `hyde-shell theme.import --select|--fetch <name>`, sourcing URLs from the
  curated `HyDE-Project/hyde-gallery` catalog. Not disabled: importing a
  theme is a deliberate, rare, user-initiated action against a curated
  source, functionally similar in trust model to installing an AUR package.
  Left as-is; documented here so it's not mistaken for dead code.
- **`Configs/.local/lib/hyde/color.set.sh:158`** — runs
  `bash -c "$exec_command"` where `exec_command` is a field read verbatim
  from wallbash template (`.dcol`) files under `WALLBASH_DIRS`, which
  includes the user-writable `${XDG_CONFIG_HOME}/hyde/wallbash`. This is
  the wallbash template system's actual design (a template declares what
  command renders it) — not a bug to patch, but a standing architectural
  fact: anything that can write into a `WALLBASH_DIRS` path gets arbitrary
  code execution on the next theme/wallpaper switch. Only matters if
  something else already has write access there.
- **AUR helper bootstrap** (`Configs/.local/lib/hyde/pm.sh`,
  `package_managers/pacman.py`) — `git clone` + `makepkg -si` of an AUR
  helper, and by extension `wlogout` itself. Inherent to AUR usage, not a
  bug; accepted per `DEPENDENCIES.md` as the fork's one deliberate AUR
  exception.

### LOW / INFO — two fixed, others documented

- `Configs/.local/lib/hyde/session/compositor/niri.py` — `launch()` and
  `dispatch_plugin_cmd()` ran a pre-quoted command string via
  `subprocess.Popen(cmd, shell=True)`, relying entirely on every upstream
  caller remembering `shlex.quote()`. **Fixed**: both now run
  `subprocess.Popen(shlex.split(cmd))` instead — `shlex.split()` reverses
  the same quoting into an argv list, so there's no shell in the loop at
  all, not just one that happens to be safe today.
- `Configs/.local/lib/hyde/session.py:247-248` — splices an unescaped
  Flatpak app-id into a restore command string; constrained by Flatpak's
  app-id naming rules, low practical risk. Left as-is (would need a wider
  look at `session.py`'s command-building to fix properly, not a
  contained one-line change).
- `Configs/.local/lib/hyde/sensorsinfo.py` — wrote predictable filenames
  (`/tmp/sensorinfo_page`, `/tmp/sensorinfo`) directly under shared `/tmp`
  instead of a per-user runtime dir; classic insecure-tempfile pattern.
  **Fixed**: both now live under `$XDG_RUNTIME_DIR/hyde/`, matching the
  convention already used by `cava.py`.
- `Configs/.local/lib/hyde/globalcontrol.sh:153,156` — `eval`s a `find`
  command string built from configured wallpaper-directory paths; only
  exploitable via an unusual local directory name the user would have to
  set themselves.
- MPRIS track title/artist and the waybar weather module's API response are
  rendered as Pango markup without escaping `<`/`&` — a UI-spoofing
  footgun (attacker-controlled text could alter the bar/lock-screen's
  appearance), not code execution.
- `Configs/.local/lib/hyde/gpu-offload.sh` and the `rofilaunch.sh`
  `n | --nvidia` mode (added this session, Slice 8) were specifically
  re-reviewed: `gpu-offload.sh` does a plain `export ...; exec "$@"` (argv
  preserved, no re-interpretation), and the rofi `n` mode is structurally
  identical to the pre-existing `r | --run` mode it's modeled on — no new
  injection surface, and rofi's `{cmd}` there is the user's own typed
  input, not attacker-supplied data.
