# Changelog

All notable changes to macndowsfan are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning.

## [0.3.0] - 2026-11-12

### Changed

- Redesigned the Flutter dashboard as a bento grid: a compact header bar, a
  hero fan tile with the live RPM gauge, target/peak/load stat tiles, and
  separate profile and control-mode tiles.
- Promoted the hottest temperature sensor to a wide feature tile with a
  `HOTTEST` badge and larger sparkline; the remaining sensors stay in the
  responsive grid.
- Restyled the compact always-on-top widget with rounded reading tiles and a
  tile-style app mark.
- Moved the UI to a dark moss palette with a shared tile gradient, a subtle
  background glow, and tighter chips, sliders and section labels.
- Redrew the app icon as a bento mark: a lime fan tile, teal speed bars, a
  sparkline tile and a gauge-arc tile. Sizes below 48 px drop the fine detail
  and keep the fan hub so the icon stays legible in the tray.

### Added

- Fan presets check for their required sensor before applying. Quiet and
  Balanced need `TC0P`, Gaming needs `TG0d`; unavailable presets are disabled
  and explain why instead of silently falling back.
- Widget tests covering the dashboard at 1180×880 and its 900×620 minimum, plus
  compact S/M/L sizes, and preset availability.

### Fixed

- Header and temperature-header overflows on narrow windows.
- Compact widget clipping at all three sizes.
