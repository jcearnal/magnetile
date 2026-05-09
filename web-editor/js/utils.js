export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function deepClone(value) {
  if (typeof structuredClone === "function") {
    return structuredClone(value);
  }

  return JSON.parse(JSON.stringify(value));
}

export function normalizeZone(zone) {
  zone.x = clamp(Number(zone.x) || 0, 0, 100);
  zone.y = clamp(Number(zone.y) || 0, 0, 100);
  zone.width = clamp(Number(zone.width) || 10, 0.1, 100 - zone.x);
  zone.height = clamp(Number(zone.height) || 10, 0.1, 100 - zone.y);

  if (!zone.color) {
    delete zone.color;
  }

  normalizeSnapFields(zone);

  return zone;
}

export function normalizeSnapFields(zone) {
  const validEdges = new Set(["top", "right", "bottom", "left"]);
  const rawEdges = Array.isArray(zone.snapEdge) ? zone.snapEdge : (zone.snapEdge ? [zone.snapEdge] : []);
  const edges = rawEdges
    .map((edge) => String(edge).toLowerCase())
    .filter((edge) => validEdges.has(edge));

  if (edges.length === 0) {
    delete zone.snapEdge;
    delete zone.snapX;
    delete zone.snapWidth;
    return zone;
  }

  zone.snapEdge = edges.length === 1 ? edges[0] : edges;

  if (zone.snapX !== undefined) {
    zone.snapX = Number(clamp(Number(zone.snapX) || 0, 0, 100).toFixed(1));
  }

  if (zone.snapWidth !== undefined) {
    zone.snapWidth = Number(clamp(Number(zone.snapWidth) || 0, 0, 100).toFixed(1));
  }

  return zone;
}

export function normalizeLayout(layout, fallbackName = "Layout") {
  const normalized = {
    ...layout,
    name: String(layout.name || fallbackName),
    padding: Math.max(0, Number(layout.padding) || 0),
    zones: Array.isArray(layout.zones) ? layout.zones : []
  };

  normalized.zones.forEach(normalizeZone);
  return normalized;
}

export function validateLayouts(value) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error("Expected a non-empty array of layouts.");
  }

  return value.map((layout, index) => {
    if (!layout || typeof layout !== "object" || Array.isArray(layout)) {
      throw new Error(`Layout ${index + 1} must be an object.`);
    }

    if (!Array.isArray(layout.zones)) {
      throw new Error(`Layout ${index + 1} must have a zones array.`);
    }

    return normalizeLayout(layout, `Layout ${index + 1}`);
  });
}

export function layoutFileName(layout, format) {
  const prefix = format === "kzones" ? "kzones" : "magnetile";
  const name = (layout?.name || `${prefix}-layouts`)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");

  return `${prefix}-${name || "layouts"}.json`;
}
