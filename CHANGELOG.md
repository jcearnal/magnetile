# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-04-14

### Fixed

- Prevent connected resize from assigning floating windows to the nearest zone,
  which could move or resize unrelated snapped windows while resizing a
  non-zoned window.

## [0.1.0] - 2026-04-12

### Added

- Connected resizing: adjacent tiled windows resize together after a manual
  edge drag, with runtime grid tracking so future snaps follow resized zones.
- Visual layout editor (`tools/layout-editor.html`) for creating, editing,
  previewing, importing, and exporting JSON layouts without hand-editing.
- Free movement toggle (`Ctrl+Alt+F`) to temporarily exempt a window from snap
  behavior.
- Per-monitor layout defaults via `monitorLayoutsJson`.
- Independent active-layout tracking per output and optionally per virtual
  desktop.
- Resolution-independent multi-monitor geometry fixes including outputs with
  non-zero origin coordinates.
- Wayland-only / KDE Plasma 6.4+ / KWin 6 focus with no X11 code paths.
- Layout editor features: zone snapping, padding preview, aspect ratio presets,
  file save/load.
- Makefile targets for nested Wayland test sessions (`make test`), live reload,
  and KWin log tailing.
- `PROJECT_DESIGN.md` architecture documentation.
- `CONTRIBUTING.md` with dev setup, debugging, and formatting guidance.
- `NOTICE.md` with KZones attribution.

### Preserved from KZones

- FancyZones-style percentage-based zone layouts.
- Top-of-screen zone selector while dragging.
- Full-screen zone overlay while moving windows.
- Optional edge snapping.
- Multiple saved layouts with cycling.
- Keyboard shortcuts for zone movement, layout switching, zone cycling, window
  cycling, and snap-all.
- Plasma color-scheme aware overlay and selector styling.
- JSON-based layout configuration with applications, indicators, and colors.
- Window geometry remember/restore.
- Window class include/exclude filters.
- OSD messages and configurable polling rate.
- Debug overlay for window class inspection.
