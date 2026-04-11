# Contributing

## Code Formatting

### QML

QML files should be formatted using the `qmlformat` tool.

```bash
qmlformat -i path/to/file.qml
```

## Development Resources

### API Documentation

- [KDE Frameworks API reference](https://api.kde.org/)
- [Kirigami style colors](https://develop.kde.org/docs/getting-started/kirigami/style-colors/)
- [KWin scripting API](https://develop.kde.org/docs/plasma/kwin/api/)

### Examples and source code

- [Example KWin scripts](https://invent.kde.org/plasma/kwin/-/tree/master/src/plugins)
- [KWin scripting API source code](https://invent.kde.org/plasma/kwin/-/tree/master/src/scripting)

## KWin debugging

Script configurations are saved inside: `~/.config/kwinrc`

Live script code is stored here: `~/.local/share/kwin/scripts`

Build, install, and start a nested Plasma session:

```bash
make test
```

Reload the installed script in the current session:

```bash
make
qdbus6 org.kde.KWin /KWin reconfigure
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```

If QML signal handlers or shortcut declarations changed, restart KWin so old
script instances are cleared:

```bash
qdbus6 org.kde.KWin /KWin org.kde.KWin.replace
```

Follow KWin scripting logs:

```bash
journalctl --user -u plasma-kwin_wayland -f QT_CATEGORY=kwin_scripting QT_CATEGORY=qml QT_CATEGORY=js
```

## Tips

- You can edit the configuration UI (`src/contents/ui/config.ui`) using [Qt Widgets Designer](https://doc.qt.io/qt-6/qtdesigner-manual.html), which is part of the Qt development tools.
- The makefile contains some handy commands to test and run the script, either by loading it directly or in a nested Plasma session.
- The visual layout customizer is `tools/layout-editor.html`. It is a browser
  helper that imports and exports the same JSON stored in the KWin script
  settings; it does not write KWin settings directly.
