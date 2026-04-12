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

Magnetile-specific changes are developed with AI coding assistance. Treat that
as an implementation detail, not a licensing shortcut: preserve the GPL-3.0
license, keep upstream KZones attribution, and document Magnetile improvements
as derivative work rather than clean-room authorship.

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
- `tools/layout-editor.html`: standalone browser helper for visual layout editing.

The code intentionally remains close to KZones. Avoid large rewrites unless they are necessary.

## Layout Editing Architecture

`layoutsJson` remains the source of truth for layouts. The schema is still a
backward-compatible array of layout objects, and all zones remain percentages.
Optional fields such as `applications`, `indicator`, `color`, `fullscreen`, and
future metadata are preserved by the JSON parser and helper editor where
possible.

The built-in KWin scripted config UI is a static QWidget `.ui` loaded by KDE's
generic scripted config module. It is suitable for storing `kcfg_*` fields but
not for a FancyZones-style drag/resize editor with custom save logic. The first
visual editor milestone is therefore `tools/layout-editor.html`, a local helper
that can import current layout JSON, edit layouts and zones visually, and copy
the resulting JSON back into the Magnetile Layouts setting.

Implemented helper editor operations:

- Create, rename, duplicate, delete, and reorder layouts.
- Add and delete zones.
- Move and resize zones by dragging in a resolution-independent canvas.
- Snap zone edges to a grid, screen edges, and other zones.
- Preview layout padding and common/custom screen aspect ratios.
- Import pasted JSON, open JSON files, save JSON files, and copy generated JSON.
- Edit zone `x`, `y`, `width`, `height`, and optional `color` precisely.

A future fully integrated editor should be either:

- A custom KCM or external helper that writes the KWin script config directly
  and triggers a KWin reconfigure, or
- A runtime KWin QML editor only if the deployed KWin API exposes a reliable
  script config write path.

Do not replace `layoutsJson` with pixel geometry. Any migration must keep old
arrays valid and make new fields optional.

## Per-Monitor Layout Defaults

`monitorLayoutsJson` is an optional JSON object mapping KWin output names,
`landscape`, or `portrait` to a layout name or zero-based layout index:

```json
{
  "DP-1": "Priority Grid",
  "HDMI-A-1": 1,
  "landscape": "Priority Grid",
  "portrait": "Horizontal Split"
}
```

This map is only used when `trackLayoutPerScreen` is enabled. On first use of an
output/desktop layout key, Magnetile seeds the active layout from
`monitorLayoutsJson`; output-name defaults take precedence over orientation
defaults. If no valid mapping exists, landscape outputs prefer `Priority Grid`
and portrait outputs prefer `Horizontal Split` when those layouts exist. After
seeding, runtime layout switching is tracked
independently in memory for that output, and optionally for that virtual desktop
when `trackLayoutPerDesktop` is also enabled.

Monitor identity uses KWin output names (`output.name`). Geometry does not rely
on output order or an origin of `x=0, y=0`; snapping uses
`Workspace.clientArea(KWin.FullScreenArea, output, desktop)` plus percentage
zones. Output orientation is included in the runtime layout key so rotating a
monitor seeds and remembers a separate layout selection for that orientation.

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
- `client.magnetileFreeMove`: window-level override that prevents drag/drop
  snapping until toggled off or until the window is explicitly snapped to a
  zone again.

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
   If KWin script reloads have cleared Magnetile's dynamic window properties,
   the snapshot path first recovers the resized window's layout/zone from its
   current frame geometry across all configured layouts, then recovers other
   same-layout windows in the resize scope.
3. `onInteractiveMoveResizeStepped` calls `connectedResize(client)` during the
   drag so adjacent windows follow live. The solver always compares against the
   original snapshot, not against already-mutated neighbor windows.
4. `onInteractiveMoveResizeFinished` calls `connectedResize(client)` again as
   the final correctness pass.
5. `connectedResize` compares the resized window's old and new edges.
6. Adjacent windows whose old edge touched the resized edge, or whose old edge
   was separated by the layout padding gap, are resized to follow the new edge.
   Padded layouts preserve the measured gap between the resized window and the
   neighbor instead of collapsing the windows together.
7. If the dragged edge would consume an adjacent neighbor past the minimum
   tracked size, Magnetile constrains the dragged window before applying
   neighbor geometry so the solver does not leave overlapping windows behind.
8. Resize snapshots store both current frame geometry and original logical zone
   geometry. Neighbor detection can use either source so full-height zones can
   stay connected to stacked half-height zones across their shared logical edge.
9. Stacked or side-by-side sibling zones that share the same logical outer edge
   follow that edge together, so accidentally grabbing one half of a split stack
   still keeps the other half aligned.
10. `Ctrl+Alt+R` clears the current layout's resized runtime geometry for the
   active output, desktop, and activity, then moves windows in that layout back
   to their configured zone geometry. If a window's dynamic layout/zone state is
   stale, reset falls back to the nearest configured zone.

Scope rules:

- Only normal, non-filtered windows participate.
- Only same output/screen.
- Only same virtual desktop.
- Only same activity.
- Only same Magnetile layout.

When `enableDebugLogging` is enabled, resize start logs include the active
layout/zone, resize participants, and same-session windows skipped because they
were filtered or outside the resize scope. The debug overlay also includes the
current resize snapshot summary.

The implementation is edge-adjacent, not a full tile-tree solver. It works best for non-overlapping grids and shared-edge layouts.

## Shortcuts

Current default shortcuts avoid numpad dependency:

- `Ctrl+Alt+1..9`: move active window to zone 1-9.
- `Ctrl+Alt+Shift+1..9`: activate layout 1-9.
- `Ctrl+Alt+!/@/#...`: compatibility aliases for activate layout 1-9 on
  keyboard paths that report shifted number keys as symbols.
- `Ctrl+Alt+D`: cycle layouts.
- `Ctrl+Alt+Shift+D`: cycle layouts reversed.
- `Ctrl+Alt+Left/Right`: previous/next zone.
- `Ctrl+Alt+Up/Down`: previous/next window in current zone.
- `Meta+Space`: snap all windows.
- `Meta+Shift+Space`: snap active window.
- `Ctrl+Alt+F`: free active window from Magnetile drag snapping.
- `Ctrl+Alt+C`: toggle zone overlay while moving.
- `Ctrl+Alt+R`: reset windows in the current layout back to configured zone
  geometry.

KDE keeps old bindings in `~/.config/kglobalshortcutsrc`. If shortcut defaults change, existing installs may need live KGlobalAccel updates or manual changes in System Settings.
Shortcut declaration changes and old dev-loaded signal handlers may require a
full KWin restart with `qdbus6 org.kde.KWin /KWin org.kde.KWin.replace`.

## Free Movement

Free movement is a per-window override controlled by `Ctrl+Alt+F`.

Behavior:

- When enabled, Magnetile does not show the zone overlay for that window during
  drag moves and the drop remains at the user's custom size and position.
- Pressing `Ctrl+Alt+F` again disables the override for the active window.
- Moving the window to a zone with a zone shortcut, selector drop, or snap
  command clears the override.
- The override is stored only as a dynamic KWin window property. It does not
  survive window recreation or a full KWin restart.

This is intentionally implemented as a toggle rather than a held global key.
KWin `ShortcutHandler` activation is reliable for shortcuts, but it does not
provide a matching key-release signal that can be used as a robust global
"while held" state from the script.

## Known Limitations

- Connected resize depends on KWin's interactive resize step events, so apps
  that throttle or reject scripted geometry updates may feel less fluid.
- Overlapping zones and multi-zone spanning are not fully solved.
- Multiple windows stacked in one zone can make resize behavior ambiguous.
- Some GTK/Flatpak apps may fight requested geometry.
- KWin script config reload is unreliable; disabling/enabling or restarting KWin scripting may be needed after config changes.
- `wf-recorder` is not a valid capture backend on KWin sessions that do not
  expose `wlr-screencopy-unstable-v1`; recording tooling needs a KDE
  PipeWire/portal-compatible backend before final demo capture.

## Local Development

For normal runtime or config changes, build, install, enable, reconfigure, and
restart KWin scripting with:

```sh
tools/reload-clean.sh --normal
```

Use the full restart path when shortcut declarations changed, when signal
handler lifecycle changed, or when logs still mention stale development load
paths such as temporary `src.XXXXXX` directories:

```sh
tools/reload-clean.sh --restart
```

The full restart path packages and installs with `make`, enables Magnetile in
`kwinrc`, then calls `qdbus6 org.kde.KWin /KWin org.kde.KWin.replace`. This is
expected to be necessary for KGlobalAccel shortcut declaration changes and for
clearing old QML closures left by temporary development loads.

The Makefile uses `zip` when available and Python's `zipfile` module as a fallback.

Watch logs:

```sh
journalctl --user -u plasma-kwin_wayland -f QT_CATEGORY=kwin_scripting QT_CATEGORY=qml QT_CATEGORY=js
```

## Manual Test Checklist

- Install and enable the script.
- Confirm KWin logs show `Magnetile: Loading config`.
- Move a window to zones 1, 2, and 3 with `Ctrl+Alt+1..3`.
- Switch layouts with `Ctrl+Alt+Shift+1..3` and confirm the numbered OSD shows
  the selected layout name.
- Drag a window to the top selector and drop into a zone.
- Move a window while overlay is visible.
- Put three windows into adjacent zones and resize the center window by mouse.
- Press `Ctrl+Alt+R` and confirm resized windows return to the configured
  layout geometry.
- Press `Ctrl+Alt+F`, drag the active window freely, then press `Ctrl+Alt+F`
  again and confirm zone snapping returns.
- Use `tools/layout-editor.html` to import, edit, copy, and reapply layout JSON.
- Repeat connected resize on a secondary monitor if available.
- Test at fractional scaling if available.

## Feature Ideas Already Requested

- Better native KWin tile API integration.
- Multi-zone spanning.
- GUI layout editor.
- Continuous live connected resizing while the mouse is moving.
- Better handling for overlapping zones.
- KDE PipeWire/portal-compatible recording workflow for demo media.
