# KWin Layout Editor

This is a standalone, client-side visual editor for Magnetile, KZones, and
[PlasmaZones](https://github.com/fuddlesworth/PlasmaZones) layout JSON.

It edits the shared KWin script layout schema:

- Top-level value: an array of layouts
- Layout fields: `name`, `padding`, and `zones`
- Zone fields: `x`, `y`, `width`, and `height` as screen percentages
- Optional zone fields are preserved where possible, including `applications`, `indicator`, and `color`

## Compatibility

The default export target is Magnetile. The KZones export target emits the same
documented KZones-compatible layout array and keeps common optional KZones
fields. PlasmaZones can import KZones layouts, so use the KZones export target
for PlasmaZones.

Use the generated JSON in:

- `System Settings / Window Management / KWin Scripts / Magnetile / Layouts`
- `System Settings / Window Management / KWin Scripts / KZones / Layouts`
- PlasmaZones' KZones layout import flow

After saving settings, disable and enable the KWin script if the new layout does not appear immediately.

## Local Development

The app uses vanilla HTML, CSS, and JavaScript modules. No build step is required.

Run a local static server from the repository root:

```sh
python3 -m http.server 8000
```

Then open:

```text
http://localhost:8000/web-editor/
```

Opening `index.html` directly can work for most editor behavior, but the example layout JSON is loaded with `fetch`, so a local server is the closest match to GitHub Pages.

## Deployment

GitHub Pages deployment is handled by `.github/workflows/deploy-editor.yml`.

The workflow uploads the `web-editor/` directory and deploys it with the modern GitHub Pages Actions flow:

- `actions/configure-pages@v5`
- `actions/upload-pages-artifact@v3`
- `actions/deploy-pages@v4`

## Contributing

Keep the editor fully client-side and dependency-free unless a dependency removes significant complexity. Preserve existing imported layout metadata when editing zones, because users may carry optional Magnetile or KZones settings in their JSON.

Useful checks before opening a pull request:

- Create a two-zone layout by dragging on the canvas.
- Export both Magnetile and KZones JSON.
- Import a previously exported file.
- Copy JSON to the clipboard.
- Load each bundled preset.
- Test the page in Chromium, Firefox, and Safari/WebKit where available.
