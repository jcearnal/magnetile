import QtQuick
import org.kde.kwin

Item {
    signal cycleLayouts()
    signal cycleLayoutsReversed()
    signal moveActiveWindowToNextZone()
    signal moveActiveWindowToPreviousZone()
    signal toggleZoneOverlay()
    signal switchToNextWindowInCurrentZone()
    signal switchToPreviousWindowInCurrentZone()
    signal moveActiveWindowToZone(int zone)
    signal activateLayout(int layout)
    signal moveActiveWindowUp()
    signal moveActiveWindowDown()
    signal moveActiveWindowLeft()
    signal moveActiveWindowRight()
    signal snapActiveWindow()
    signal snapAllWindows()

    ShortcutHandler {
        name: "Magnetile: Cycle layouts"
        text: "Magnetile: Cycle layouts"
        sequence: "Ctrl+Alt+D"
        onActivated: {
            cycleLayouts();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Cycle layouts (reversed)"
        text: "Magnetile: Cycle layouts (reversed)"
        sequence: "Ctrl+Alt+Shift+D"
        onActivated: {
            cycleLayoutsReversed();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Move active window to next zone"
        text: "Magnetile: Move active window to next zone"
        sequence: "Ctrl+Alt+Right"
        onActivated: {
            moveActiveWindowToNextZone();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Move active window to previous zone"
        text: "Magnetile: Move active window to previous zone"
        sequence: "Ctrl+Alt+Left"
        onActivated: {
            moveActiveWindowToPreviousZone();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Toggle zone overlay"
        text: "Magnetile: Toggle zone overlay"
        sequence: "Ctrl+Alt+C"
        onActivated: {
            toggleZoneOverlay();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Switch to next window in current zone"
        text: "Magnetile: Switch to next window in current zone"
        sequence: "Ctrl+Alt+Up"
        onActivated: {
            switchToNextWindowInCurrentZone();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Switch to previous window in current zone"
        text: "Magnetile: Switch to previous window in current zone"
        sequence: "Ctrl+Alt+Down"
        onActivated: {
            switchToPreviousWindowInCurrentZone();
        }
    }

    Repeater {
        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]

        delegate: Item {
            ShortcutHandler {
                name: "Magnetile: Move active window to zone " + modelData
                text: "Magnetile: Move active window to zone " + modelData
                sequence: "Ctrl+Alt+" + modelData
                onActivated: {
                    moveActiveWindowToZone(modelData - 1);
                }
            }

        }

    }

    Repeater {
        model: [1, 2, 3, 4, 5, 6, 7, 8, 9]

        delegate: Item {
            ShortcutHandler {
                name: "Magnetile: Activate layout " + modelData
                text: "Magnetile: Activate layout " + modelData
                sequence: "Ctrl+Alt+Shift+" + modelData
                onActivated: {
                    activateLayout(modelData - 1);
                }
            }

        }

    }

    ShortcutHandler {
        name: "Magnetile: Move active window up"
        text: "Magnetile: Move active window up"
        sequence: "Meta+Up"
        onActivated: {
            moveActiveWindowUp();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Move active window down"
        text: "Magnetile: Move active window down"
        sequence: "Meta+Down"
        onActivated: {
            moveActiveWindowDown();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Move active window left"
        text: "Magnetile: Move active window left"
        sequence: "Meta+Left"
        onActivated: {
            moveActiveWindowLeft();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Move active window right"
        text: "Magnetile: Move active window right"
        sequence: "Meta+Right"
        onActivated: {
            moveActiveWindowRight();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Snap active window"
        text: "Magnetile: Snap active window"
        sequence: "Meta+Shift+Space"
        onActivated: {
            snapActiveWindow();
        }
    }

    ShortcutHandler {
        name: "Magnetile: Snap all windows"
        text: "Magnetile: Snap all windows"
        sequence: "Meta+Space"
        onActivated: {
            snapAllWindows();
        }
    }

}
