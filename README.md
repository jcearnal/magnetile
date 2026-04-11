# Magnetile

<img align="right" width="125" height="75" src="./media/icon.png">

KDE Plasma 6.4+ KWin script for snapping windows into zones with connected tile resizing.

Magnetile starts from the KZones zone overlay and shortcut workflow, then adds Fluid Tile-style connected resizing: when a tiled window is manually resized, adjacent tiled windows resize to fill the gap automatically.

## Features

### Zone Selector

The Zone Selector is a small widget that appears when you drag a window to the top of the screen. It allows you to snap the window to a zone regardless of the current layout.

![](./media/selector.gif)

### Zone Overlay

The Zone Overlay is a fullscreen overlay that appears when you move a window. It shows all zones from the current layout and the window will snap to the zone you drop it on.

![](./media/dragdrop.gif)

### Edge Snapping

Edge Snapping allows you to snap windows to zones by dragging them to the edge of the screen.

![](./media/edgesnapping.gif)

### Multiple Layouts

Create multiple layouts and cycle between them.

![](./media/layouts.gif)

### Keyboard Shortcuts

Magnetile comes with a set of [shortcuts](#shortcuts) to move your windows between zones and layouts.

![](./media/shortcuts.gif)

### Connected Resizing

When a tiled window is resized by mouse, Magnetile detects adjacent tiled windows on the same monitor, virtual desktop, activity, and layout. Adjacent windows sharing the resized edge are resized after the mouse is released so the tiled area stays connected.

### Theming

By using the same colors as your selected color scheme, Magnetile will blend in perfectly with your desktop.

![](./media/theming.png)

## Requirements

- KDE Plasma 6.4 or newer
- KWin 6 on Wayland
- `kpackagetool6`
- `qdbus6`
- `make`
- `zip`, or Python 3 for the Makefile fallback packager

## Installation

Clone and install locally:

```sh
git clone https://github.com/jcearnal/magnetile.git
cd magnetile
make
kwriteconfig6 --file kwinrc --group Plugins --key magnetileEnabled true
qdbus6 org.kde.KWin /KWin reconfigure
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

## Configuration

The script settings can be found under `System Settings / Window Management / KWin Scripts / Magnetile / ⚙️`

### General

#### Zone Selector

The zone selector is a small widget that appears when you drag a window to the top of the screen. It allows you to snap the window to a zone regardless of the current layout.

- Enable or disable the zone selector.
- Set the distance from the top of the screen at which the zone selector will start to appear.

#### Zone Overlay

The zone overlay is a fullscreen overlay that appears when you move a window. It shows all zones from the current layout and the window will snap to the zone you drop it on.

- Enable or disable the zone overlay.
- Choose whether the overlay should be shown when you start moving a window or when you press the toggle overlay shortcut.
- Choose where the cursor needs to be in order to highlight a zone, either in the center of the zone or anywhere inside the zone.
- Choose if you want the indicator to display all zones or only the highlighted zone.

#### Edge Snapping

Edge Snapping allows you to snap windows to zones by dragging them to the edge of the screen. Make sure to disable the default edge snapping functionality before enabling this.

- Enable or disable edge snapping.
- Set the distance from the edge of the screen at which the edge snapping will start to appear.

#### Remember and restore window geometries

The script will remember the geometry of each window when it's moved to a zone. When the window is moved out of the zone, it will be restored to it's original geometry.

- Enable or disable this behavior.

#### Track active layout per screen

If you have multiple monitors, you can enable this to track the active layout per screen. This will allow you to have different active layouts on different screens.

- Enable or disable this behavior.

#### Automatically snap all new windows

When a new window is launched, the script will automatically snap it to its closest zone.

- Enable or disable this behavior.

#### Display OSD messages

Disable this if you don't want to see any OSD messages.

- Enable or disable this behavior.

#### Fade windows while moving

Reduce the opacity of other windows while the active window is being moved.

- Enable or disable this behavior.

### Layouts

You can define your own layouts in the **Layouts** tab in the script settings.
`layoutsJson` is still the source of truth, but you do not have to hand-edit it
from scratch.

#### Visual helper editor

Open `tools/layout-editor.html` in a browser. Paste the current JSON from the
Layouts tab, edit the layout visually, then copy the generated JSON back into
the Layouts tab.

The helper editor can:

- Create, rename, duplicate, delete, and reorder layouts.
- Add and delete zones.
- Move and resize zones by dragging.
- Edit zone `x`, `y`, `width`, `height`, and optional `color` precisely.

KWin's generic scripted config window cannot host a full drag/resize editor with
custom save logic, so the helper keeps the existing KWin config model intact.

Here are some examples to get you started:

#### Examples

<details open>
  <summary>Simple</summary>

```json
[
    {
        "name": "Layout 1",
        "padding": 0,
        "zones": [
            {
                "x": 0,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "x": 25,
                "y": 0,
                "height": 100,
                "width": 50
            },
            {
                "x": 75,
                "y": 0,
                "height": 100,
                "width": 25
            }
        ]
    }
]
```

</details>

<details>
  <summary>Advanced</summary>

```json
[
    {
        "name": "Priority Grid",
        "padding": 0,
        "zones": [
            {
                "x": 0,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "x": 25,
                "y": 0,
                "height": 100,
                "width": 50,
                "applications": ["firefox"]
            },
            {
                "x": 75,
                "y": 0,
                "height": 100,
                "width": 25
            }
        ]
    },
    {
        "name": "Quadrant Grid",
        "padding": 0,
        "zones": [
            {
                "x": 0,
                "y": 0,
                "height": 50,
                "width": 50
            },
            {
                "x": 0,
                "y": 50,
                "height": 50,
                "width": 50
            },
            {
                "x": 50,
                "y": 50,
                "height": 50,
                "width": 50
            },
            {
                "x": 50,
                "y": 0,
                "height": 50,
                "width": 50
            }
        ]
    },
    {
        "name": "Columns",
        "padding": 0,
        "zones": [
            {
                "x": 0,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "x": 25,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "x": 50,
                "y": 0,
                "height": 100,
                "width": 25
            },
            {
                "x": 75,
                "y": 0,
                "height": 100,
                "width": 25
            }
        ]
    }
]
```

</details>

#### Explanation

The main array can contain as many layouts as you want:

Each **layout** object needs the following keys:

- `name`: The name of the layout, shown when cycling between layouts
- `padding`: The amount of space between the window and the zone in pixels
- `zones`: An array containing all zone objects for this layout

Each **zone** object can contain the following keys:

- `x`, `y`: position of the top left corner of the zone in screen percentage
- `width`, `height`: size of the zone in screen percentage
- `applications`: an array of window classes that should snap to this zone when launched (optional)
- `indicator`: an object containing the indicator settings (optional)
  - `position`: default is `center`, other options are `top-left`, `top-center`, `top-right`, `right-center`, `bottom-right`, `bottom-center`, `bottom-left`, `left-center`
  - `margin`: an object containing the margin for the indicator
    - `top`, `right`, `bottom`, `left`: margin in pixels
- `color`: a color name or hex value to tint the zone with (optional)

### Per-Monitor Layouts

Enable **Track active layout per screen** to keep a separate active layout for
each physical output. Magnetile keys this by KWin output name, so monitor
arrangements can be left, right, above, below, or use negative virtual
coordinates.

Use **Monitor layout defaults** to seed a specific output with a layout. The
value is a JSON object whose keys are KWin output names and whose values are
layout names or zero-based layout indexes:

```json
{
    "DP-1": "Priority Grid",
    "HDMI-A-1": 1
}
```

After a monitor has an active layout, layout switching on that monitor updates
only that monitor's runtime selection. If **Track active layout per virtual
desktop** is also enabled, Magnetile tracks the output and virtual desktop
together.

### Filters

Stop certain windows from snapping to zones by adding them to the filter list.

- Select the filter mode, either **Include** or **Exclude**.
- Add window classes to the list seperated by a newline.

You can enable the debug overlay to see the window class of the active window.

### Advanced

#### Polling rate

The polling rate is the amount of time between each zone check when dragging a window. The default is 100ms, a faster polling rate is more accurate but will use more CPU. You can change this to your liking.

#### Debugging

Here you can enable logging or turn on the debug overlay.

## Shortcuts

List of all available shortcuts:

| Shortcut                                           | Default Binding                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------- |
| Move active window to zone                         | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>1-9</kbd>                   |
| Move active window to previous zone                | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Left</kbd>                  |
| Move active window to next zone                    | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Right</kbd>                 |
| Switch to previous window in current zone          | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Down</kbd>                  |
| Switch to next window in current zone              | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Up</kbd>                    |
| Cycle layouts                                      | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>D</kbd>                     |
| Cycle layouts (reversed)                           | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd>  |
| Toggle zone overlay                                | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>C</kbd>                     |
| Activate layout                                    | <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>1-9</kbd> |
| Move active window up                              | <kbd>Meta</kbd> + <kbd>Up</kbd>                                     |
| Move active window down                            | <kbd>Meta</kbd> + <kbd>Down</kbd>                                   |
| Move active window left                            | <kbd>Meta</kbd> + <kbd>Left</kbd>                                   |
| Move active window right                           | <kbd>Meta</kbd> + <kbd>Right</kbd>                                  |
| Snap all windows                                   | <kbd>Meta</kbd> + <kbd>Space</kbd>                                  |
| Snap active window                                 | <kbd>Meta</kbd> + <kbd>Shift</kbd> + <kbd>Space</kbd>               |

*To change the default bindings, go to `System Settings / Shortcuts` and search for Magnetile*

> [!NOTE]  
> Not all shortcuts will be bound by default as they conflict with existing system bindings.

## Testing Connected Resize

1. Open three normal windows.
2. Move them into the default Priority Grid using `Ctrl+Alt+1`, `Ctrl+Alt+2`, and `Ctrl+Alt+3`.
3. Resize the center window with the mouse by dragging its left or right edge.
4. Release the mouse.
5. The adjacent window sharing that edge should resize to fill the space or yield space.

## Tips and Tricks

### Animate window movements

Install the "Geometry change" KWin effect to animate window movements: https://store.kde.org/p/2136283

### Trigger KWin shortcuts using a command

Replace the last part with any shortcut from the list above:

```sh
qdbus6 org.kde.kglobalaccel /component/kwin invokeShortcut "Magnetile: Cycle layouts"
```

### Clean corrupted shortcuts

Sometimes KWin can leave behind corrupt or missing shortcuts in the Settings after uninstalling or updating scripts, you can remove those using this command:

```sh
qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.cleanUp
```

## Troubleshooting

### The script doesn't work

Check if your KDE Plasma version is at 6 or higher (for older versions, check the releases)  
Make sure there is at least one layout defined in the script settings and that it contains at least one zone.

### My settings are not saved

After changing settings, reload the script by disabling, saving and enabling it again.  
This is a known issue with the KWin Scripting API

### Logs

Follow KWin scripting logs while testing:

```sh
journalctl --user -u plasma-kwin_wayland -f QT_CATEGORY=kwin_scripting QT_CATEGORY=qml QT_CATEGORY=js
```

### Plasma 5 and X11

Magnetile targets KDE Plasma 6.4+ and Wayland. Plasma 5 and X11 are not supported.

## License

Magnetile is derived from KZones and is distributed under GPL-3.0. See [NOTICE.md](./NOTICE.md).
