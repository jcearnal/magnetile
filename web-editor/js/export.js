import { deepClone, validateLayouts } from "./utils.js";

export const formatDescriptions = {
  magnetile:
    "Magnetile export: paste this array into System Settings / Window Management / KWin Scripts / Magnetile / Layouts.",
  kzones:
    "KZones export: paste this array into System Settings / Window Management / KWin Scripts / KZones / Layouts."
};

const commonZoneKeys = new Set([
  "x",
  "y",
  "width",
  "height",
  "applications",
  "indicator",
  "color",
  "fullscreen"
]);

function sortZone(zone) {
  const sorted = {};

  for (const key of ["x", "y", "height", "width"]) {
    if (zone[key] !== undefined) sorted[key] = zone[key];
  }

  for (const [key, value] of Object.entries(zone)) {
    if (!Object.prototype.hasOwnProperty.call(sorted, key)) {
      sorted[key] = value;
    }
  }

  return sorted;
}

function normalizeForFormat(layouts, format) {
  const copy = validateLayouts(deepClone(layouts));

  return copy.map((layout) => {
    const next = {
      ...layout,
      zones: layout.zones.map((zone) => {
        if (format !== "kzones") {
          return sortZone(zone);
        }

        const compatible = {};
        for (const [key, value] of Object.entries(zone)) {
          if (commonZoneKeys.has(key)) {
            compatible[key] = value;
          }
        }
        return sortZone(compatible);
      })
    };

    return next;
  });
}

export function exportLayouts(layouts, format) {
  const normalized = normalizeForFormat(layouts, format);
  return JSON.stringify(normalized, null, 2);
}
