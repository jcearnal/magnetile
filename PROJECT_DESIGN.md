# Magnetile Project Design

This file is the handoff document for future development sessions. Read it before changing behavior.

## Goal

Magnetile is a KDE Plasma 6.4+ KWin script for Wayland. It combines:

- KZones-style PowerToys FancyZones behavior: percentage-based custom zones, visual overlay, zone selector, edge snapping, layout switching, and shortcuts.
- Fluid Tile-style connected resizing: when a tiled window is manually resized, adjacent tiled windows resize to fill the space automatically.

Magnetile should preserve existing KZones behavior unless a change is explicitly fixing a bug or adding connected tiling behavior.

## Platform Constraints

- KWin 6 API only.
- Plasma 6.4+ minimum.
- Wayland only. Do not add X11-specific code paths.
- Use `qdbus6`, not `qdbus`.
- Geometry must be resolution-independent. Layout zones are percentages. Do not hardcode monitor-size assumptions.
- Must work on 1080p, 1440p, 4K, ultrawide, high DPI, fractional scaling, and multi-monitor setups.

## Licensing

Magnetile is derived from KZones. KZones is GPL-3.0, so Magnetile is GPL-3.0 unless upstream KZones grants relicensing permission. Keep KZones attribution and Magnetile attribution in `NOTICE.md`.

## Current Architecture

The package root is `src/`.

- `src/metadata.json`: KWin script package metadata. Plugin id is `magnetile`.
- `src/contents/ui/main.qml`: main runtime, KWin signal handling, zone movement, layout state, connected resizing, overlay dialog.
- `src/contents/ui/components/Shortcuts.qml`: all KGlobalAccel shortcut declarations.
- `src/contents/ui/components/Zones.qml`: visual zone overlay geometry.
- `src/contents/ui/components/Selector.qml`: top zone selector.
- `src/contents/code/core.mjs`: config loading and shared runtime state.
- `src/contents/code/utils.mjs`: logging, OSD, hover helpers.
- `src/contents/config/main.xml`: KWin script config schema.
- `src/contents/ui/config.ui`: settings UI.

The code intentionally remains close to KZones. Avoid large rewrites unless they are necessary.

## Zone Geometry

Layout zones are stored as percentages:

```json
{ "x": 0, "y": 0, "width": 25, "height": 100 }
```

Runtime conversion happens in `zoneGeometry(layoutIndex, zoneIndex, screen)` in `main.qml`.

Important details:

- Always include the client area offset (`area.x`, `area.y`) when converting percentage zones to absolute geometry.
- Use `Workspace.clientArea(KWin.FullScreenArea, screen, Workspace.currentDesktop)` for current zone behavior.
- Use tolerant geometry matching. Exact equality is fragile with Wayland scaling and KWin rounding.

## Window State

Magnetile tracks state as dynamic properties on KWin windows:

- `client.zone`: active zone index, or `-1`.
- `client.layout`: active layout index.
- `client.desktop`: desktop captured when assigning the zone.
- `client.activity`: activity captured when assigning the zone.
- `client.oldGeometry`: previous floating geometry when restore behavior is enabled.
- `client.magnetileResizeSnapshot`: temporary snapshot used during connected resize.

When adding new state, prefix Magnetile-specific temporary fields with `magnetile`.

## Connected Resize

Connected resizing lives in `main.qml`.

Flow:

1. `onInteractiveMoveResizeStarted` detects `client.resize`.
2. If the client is in a known zone, `snapshotResizeGroup(client)` captures:
   - resized window geometry,
   - layout,
   - zone,
   - output,
   - desktop,
   - activity,
   - other tiled windows in the same scope.
3. `onInteractiveMoveResizeFinished` calls `connectedResize(client)`.
4. `connectedResize` compares the resized window's old and new edges.
5. Adjacent windows whose old edge touched the resized edge are resized to the new edge.

Scope rules:

- Only normal, non-filtered windows participate.
- Only same output/screen.
- Only same virtual desktop.
- Only same activity.
- Only same Magnetile layout.

The implementation is edge-adjacent, not a full tile-tree solver. It works best for non-overlapping grids and shared-edge layouts.

## Shortcuts

Current default shortcuts avoid numpad dependency:

- `Ctrl+Alt+1..9`: move active window to zone 1-9.
- `Ctrl+Alt+Shift+1..9`: activate layout 1-9.
- `Ctrl+Alt+D`: cycle layouts.
- `Ctrl+Alt+Shift+D`: cycle layouts reversed.
- `Ctrl+Alt+Left/Right`: previous/next zone.
- `Ctrl+Alt+Up/Down`: previous/next window in current zone.
- `Meta+Space`: snap all windows.
- `Meta+Shift+Space`: snap active window.
- `Ctrl+Alt+C`: toggle zone overlay while moving.

KDE keeps old bindings in `~/.config/kglobalshortcutsrc`. If shortcut defaults change, existing installs may need live KGlobalAccel updates or manual changes in System Settings.

## Known Limitations

- Connected resize runs after mouse release, not continuously during drag.
- Overlapping zones and multi-zone spanning are not fully solved.
- Multiple windows stacked in one zone can make resize behavior ambiguous.
- Some GTK/Flatpak apps may fight requested geometry.
- KWin script config reload is unreliable; disabling/enabling or restarting KWin scripting may be needed after config changes.

## Local Development

Build and install:

```sh
make
kwriteconfig6 --file kwinrc --group Plugins --key magnetileEnabled true
qdbus6 org.kde.KWin /KWin reconfigure
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

The Makefile uses `zip` when available and Python's `zipfile` module as a fallback.

Watch logs:

```sh
journalctl --user -u plasma-kwin_wayland -f QT_CATEGORY=kwin_scripting QT_CATEGORY=qml QT_CATEGORY=js
```

## Manual Test Checklist

- Install and enable the script.
- Confirm KWin logs show `Magnetile: Loading config`.
- Move a window to zones 1, 2, and 3 with `Ctrl+Alt+1..3`.
- Switch layouts with `Ctrl+Alt+Shift+1..2`.
- Drag a window to the top selector and drop into a zone.
- Move a window while overlay is visible.
- Put three windows into adjacent zones and resize the center window by mouse.
- Repeat connected resize on a secondary monitor if available.
- Test at fractional scaling if available.

## Feature Ideas Already Requested

- Better native KWin tile API integration.
- Multi-zone spanning.
- GUI layout editor.
- More robust multi-monitor default layout selection.
- Continuous live connected resizing while the mouse is moving.
- Better handling for overlapping zones.
