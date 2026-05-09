# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] - 2026-05-09

### Added

- Custom edge-snap trigger regions for zones via optional `snapEdge`, `snapX`,
  and `snapWidth` layout fields.
- Layout editor controls for editing and round-tripping custom edge-snap
  triggers.

### Fixed

- Edge snapping overlapping layouts can now target different zones from
  different screen edges without changing placement geometry.
- Dropping into runtime resized zones now uses the same effective geometry as
  the preview.
- Resizing a single zone preserves unchanged padded edges instead of collapsing
  layout padding.

## [0.2.2] - 2026-04-29

### Fixed

- Restored per-output layout tracking for reset and layout cycling after the
  0.2.1 runtime merged-zone fixes.
- `Ctrl+Alt+R` now clears runtime merge/resize state only for the active
  output, desktop, activity, and layout scope.
- `Ctrl+Alt+D` and reverse layout cycling now refresh from the active window's
  output before updating the tracked layout key.

## [0.2.1] - 2026-04-29

### Fixed

- Connected resizing now treats runtime merged zones as first-class resize
  targets, preserving merged-zone metadata and stacked windows during resize.
- Resetting the current layout now clears runtime merged-zone and resized-grid
  state so merged zones return to the configured layout.
- Snapping windows back into normal zones no longer loses configured padding
  after runtime resize or merge state changes.

### Changed

- Default bundled layouts and examples now use 10 px padding instead of zero
  padding, matching the expected out-of-box visual spacing.

## [0.2.0] - 2026-04-28

### Added

- Runtime merged zones: drop near a shared zone edge to span adjacent zones
  until the current layout is reset.
- High-contrast cyan zone and merge preview indicators.
- Existing tiled windows in affected zones now expand to the merged target so
  zone stacks stay coherent.

### Changed

- Multi-zone spanning uses edge/gutter drop detection instead of a held hotkey,
  because KWin script shortcuts are not reliable during interactive window
  moves.

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
