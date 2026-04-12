# Magnetile Recording Guide

Record on the 5120x1440 Wayland desktop with a tidy workspace, the Magnetile
script enabled, and the default Priority Grid layout available. Use a focused
region around the windows and overlay rather than the full monitor unless the
full width is needed to explain the behavior.

Install the capture tools first:

```sh
yay -S --noconfirm wf-recorder slurp ffmpeg
```

Run each mode from the repository root or by absolute path:

```sh
bash ~/projects/magnetile/tools/record-demo.sh connected-resize
```

After running a mode, select the screen region with `slurp`, perform the demo,
then press `Enter` in the terminal to stop recording. The script writes the
optimized output directly into `~/projects/magnetile/media/`.

## selector.gif

1. Start with one normal window floating near the center of the selected region.
2. Drag the window toward the top of the screen.
3. Pause briefly when the zone selector appears.
4. Move over a zone preview so the target is clear.
5. Drop the window into that zone.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh selector
```

## dragdrop.gif

1. Start with one floating window and the active layout visible only when moving.
2. Begin moving the window.
3. Show the overlay appearing on the current monitor.
4. Hover over one zone long enough for the highlight to read clearly.
5. Release the window into the highlighted zone.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh dragdrop
```

## edgesnapping.gif

1. Enable Magnetile edge snapping and disable KDE's built-in edge snap if it
   conflicts.
2. Start with one floating window away from the monitor edge.
3. Drag the window toward a screen edge.
4. Pause when the nearest zone target becomes clear.
5. Release the window and show it snapping into that zone.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh edgesnapping
```

## layouts.gif

1. Open one or two windows already snapped into the current layout.
2. Use `Ctrl+Alt+D` to cycle to a second layout.
3. Pause briefly after the windows settle.
4. Use `Ctrl+Alt+D` again to cycle to a third layout or back to the original.
5. Keep the region wide enough to show the layout change clearly.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh layouts
```

## shortcuts.gif

1. Open three normal windows.
2. Keep them visible and slightly staggered before recording.
3. Activate each window and press `Ctrl+Alt+1`, `Ctrl+Alt+2`, and `Ctrl+Alt+3`
   to snap them quickly into zones.
4. Leave a short pause at the end with all three windows aligned.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh shortcuts
```

## connected-resize.gif

This is the hero demo and should be the most polished recording. It shows the
Magnetile behavior KZones does not provide.

1. Open three normal windows.
2. Snap them into a three-zone layout with `Ctrl+Alt+1`, `Ctrl+Alt+2`, and
   `Ctrl+Alt+3`.
3. Start recording after the windows are cleanly aligned.
4. Slowly drag the left edge of the center window left, then right.
5. Release and show the neighboring window resize to keep the group connected.
6. Slowly drag the right edge of the center window right, then left.
7. Release and show the adjacent window resizing in real time to fill the gap.
8. End with a short pause on the final connected layout.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh connected-resize
```

## theming.png

1. Use a clean desktop with no distracting notifications.
2. Trigger the zone overlay with a window move or `Ctrl+Alt+C`.
3. Select a region that includes the overlay and enough desktop context to show
   the Plasma theme integration.
4. Capture a static screenshot to `media/theming.png`.

Command:

```sh
bash ~/projects/magnetile/tools/record-demo.sh theming
```
