# Third-party theme assets — Qylock

`pixel-rainyroom/` and `pixel-cyberpunk/` (QML, `BackgroundVideo.qml`,
`metadata.desktop`, `theme.conf`, `bg.mp4`, `font/PixelifySans-Bold.ttf`) are
vendored, unmodified except where noted in this fork's own scripts, from:

- Upstream: https://github.com/Darkkal44/qylock
- Author: Darkkal44
- Commit vendored: `f86d3f669cf988f50662e60b9128ca726d269a12` (2026-08-24)
- License: GPL-3.0 — full text in `LICENSE-qylock` next to this file,
  unchanged from upstream.
- Wallpaper videos (`bg.mp4`): sourced by the upstream author from
  [MoeWalls](https://moewalls.com/pixel-art/) — pixel-art live wallpapers,
  credited in qylock's own `README.md` "Acknowledgements" table.
  Not re-hosted or modified here beyond the copy itself.
- Font (`PixelifySans-Bold.ttf`): [Pixelify Sans](https://fonts.google.com/specimen/Pixelify+Sans)
  by Alden Wu, distributed under the SIL Open Font License 1.1. Bundled by
  upstream qylock for offline use; carried forward unchanged.

Only these two themes were vendored (not the full ~40-theme qylock
collection) — see `docs/personal-fork/ROADMAP.md` for why and how they're
wired into this fork's own SDDM setup/switch scripts under `installer/`.
