# CLAUDE.md

## What this repo is

A personal fork of [HyDE-Project/HyDE](https://github.com/HyDE-Project/HyDE)
(`origin`), selectively reduced to a minimal, auditable Hyprland workstation.
This is **not** a generic HyDE install — HyDE is treated as an upstream
codebase we're forking from and trimming, not a project to keep in sync
feature-for-feature. Detailed architecture/dependency/security findings live
in `docs/personal-fork/` — read those before re-deriving conclusions about
what a script or config does.

## Machine safety — hard boundaries

This is inspected/edited on a live Arch Linux laptop (Intel iGPU + NVIDIA
RTX 4060 hybrid graphics, NVIDIA open kernel driver already working).
HyDE's installer (`Scripts/`) has been **deleted from this fork** — it used
to mutate `/etc/pacman.conf`, GRUB/systemd-boot, `/etc/mkinitcpio.conf`,
SDDM config and more (full audit in `docs/personal-fork/SECURITY.md`).
Unless the user explicitly approves the exact action in the moment:

- **Never reintroduce or run an installer/restore/migration script** of
  that kind. If upstream HyDE is ever merged from again, treat anything
  under a re-added `Scripts/` as untrusted until reviewed — do not execute
  it.
- **Never** use `sudo`, install/remove packages, run `curl|sh` / `wget|sh`,
  enable/disable systemd services, or touch `/boot`, GRUB, EFI entries,
  Secure Boot, mkinitcpio, the kernel command line, NVIDIA kernel
  modules/drivers, `/etc/sudoers`, partitioning, or filesystems.
- Do not "fix" or replace the working NVIDIA/hybrid-graphics setup just
  because HyDE ships its own NVIDIA logic — it already works.
- System mutations are recommendations only until the user explicitly
  approves them, out of band from routine code edits.

## Package policy

- Prefer official Arch repository packages over AUR.
- AUR is accepted **only** for `wlogout` (no official-repo package exists);
  do not add further AUR dependencies without explicit approval.
- No Chaotic-AUR. oh-my-zsh is kept by user choice, but never via the
  `curl|sh` one-liner from `Scripts/restore_shl.sh` — install manually via
  `git clone` if/when needed.
- `docs/personal-fork/DEPENDENCIES.md` is the source of truth for what's
  kept/replaced/removed and why — update it when a dependency decision
  changes, don't let it drift.

## Preferred applications (do not replace without a concrete reason)

Kitty, VS Code (kept by user choice — do not swap to Ghostty/Zed unless
asked again), Zsh + Starship + oh-my-zsh, fzf, zoxide, NetworkManager,
PipeWire/WirePlumber, firewalld, power-profiles-daemon, swaync (not dunst),
wlogout, rofi. No persistent clipboard history by default
(cliphist/wl-clip-persist removed).

## Architecture invariants

- Hyprland's real entry point is the generated `~/.local/share/hypr/hyde.lua`
  — never hand-edit anything under `Configs/.local/share/hypr/lua/`
  expecting it to survive; user customization belongs in
  `Configs/.config/hypr/hyprland.lua` (deploy-marked `preserve`, loaded last).
- `hyde-shell` (`Configs/.local/bin/hyde-shell`) is the single dispatcher for
  keybinds/waybar/rofi actions — don't bypass it by hardcoding raw commands
  in new integrations.
- Startup daemons are data (`hc.start.*` in
  `Configs/.local/share/hypr/lua/variables.lua`), not code — trim/add there,
  not by editing `start_up.lua`'s logic.
- Full architecture map: `docs/personal-fork/ARCHITECTURE.md`.

## Files that must not be changed automatically

`Configs/.config/hypr/hyprland.lua` (user-owned override — only edit when
the user asks for a specific personalization change, never as a side effect
of another task), anything under `~/.config` outside this repo's checkout,
`docs/personal-fork/*.md` content should reflect real findings only — don't
pad them with speculation.

## Verification commands

- Shell script changes: `shellcheck <file>`.
- Lua changes: syntax-check with `luac -p <file>` if available.
- After removing a dependency/daemon/script: `grep -rn <name> Configs/ docs/`
  to confirm no dangling reference remains.
- `git status` / `git diff --stat` after each slice to confirm the diff
  matches what was intended — see `docs/personal-fork/ROADMAP.md` for the
  slice sequence and per-slice verification steps.
