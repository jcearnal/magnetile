import { exportLayouts, formatDescriptions } from "./export.js";
import { clamp, deepClone, layoutFileName, normalizeZone, validateLayouts } from "./utils.js";

const fallbackExamples = {
  priority: [
    {
      name: "Priority Grid",
      padding: 10,
      zones: [
        { x: 0, y: 0, height: 100, width: 25 },
        { x: 25, y: 0, height: 100, width: 50 },
        { x: 75, y: 0, height: 100, width: 25 }
      ]
    }
  ],
  quadrants: [
    {
      name: "Quadrant Grid",
      padding: 10,
      zones: [
        { x: 0, y: 0, height: 50, width: 50 },
        { x: 0, y: 50, height: 50, width: 50 },
        { x: 50, y: 50, height: 50, width: 50 },
        { x: 50, y: 0, height: 50, width: 50 }
      ]
    }
  ],
  columns: [
    {
      name: "Columns",
      padding: 10,
      zones: [
        { x: 0, y: 0, height: 100, width: 25 },
        { x: 25, y: 0, height: 100, width: 25 },
        { x: 50, y: 0, height: 100, width: 25 },
        { x: 75, y: 0, height: 100, width: 25 }
      ]
    }
  ]
};

let examples = deepClone(fallbackExamples);
let layouts = deepClone(fallbackExamples.priority.concat(fallbackExamples.quadrants));
let layoutIndex = 0;
let zoneIndex = 0;
let drag = null;

const snapTolerance = 1.25;
const previewRatios = {
  "16:9": [1920, 1080],
  "16:10": [1920, 1200],
  "21:9": [3440, 1440],
  "32:9": [5120, 1440],
  "4:3": [1600, 1200]
};

const el = (id) => document.getElementById(id);
const canvas = el("canvas");

function activeFormat() {
  return document.querySelector("input[name='format']:checked")?.value || "magnetile";
}

function activeLayout() {
  return layouts[layoutIndex];
}

function activeZone() {
  return activeLayout().zones[zoneIndex] || null;
}

function previewSize() {
  return {
    width: Math.max(100, Number(el("previewWidth").value) || 1920),
    height: Math.max(100, Number(el("previewHeight").value) || 1080)
  };
}

function canvasPoint(event) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: clamp(((event.clientX - rect.left) / rect.width) * 100, 0, 100),
    y: clamp(((event.clientY - rect.top) / rect.height) * 100, 0, 100),
    rect
  };
}

function applyPreviewRatio() {
  const selected = el("previewRatio").value;
  if (selected !== "custom" && previewRatios[selected]) {
    const [width, height] = previewRatios[selected];
    el("previewWidth").value = width;
    el("previewHeight").value = height;
  }

  const size = previewSize();
  canvas.style.aspectRatio = `${size.width} / ${size.height}`;
}

function snapConfig() {
  return {
    enabled: el("snapEnabled").checked,
    step: Math.max(0.1, Number(el("snapStep").value) || 5),
    edges: el("snapEdges").checked,
    zones: el("snapZones").checked
  };
}

function snapNumber(value, targets, tolerance) {
  let snapped = value;
  let best = tolerance;

  for (const target of targets) {
    const distance = Math.abs(value - target);
    if (distance <= best) {
      snapped = target;
      best = distance;
    }
  }

  return Number(snapped.toFixed(1));
}

function snapZone(zone, index, resize) {
  const config = snapConfig();

  if (!config.enabled) {
    normalizeZone(zone);
    return;
  }

  if (config.step > 0) {
    if (resize) {
      const right = Math.round((zone.x + zone.width) / config.step) * config.step;
      const bottom = Math.round((zone.y + zone.height) / config.step) * config.step;
      zone.width = right - zone.x;
      zone.height = bottom - zone.y;
    } else {
      zone.x = Math.round(zone.x / config.step) * config.step;
      zone.y = Math.round(zone.y / config.step) * config.step;
    }
  }

  const xTargets = [];
  const yTargets = [];

  if (config.edges) {
    xTargets.push(0, 100);
    yTargets.push(0, 100);
  }

  if (config.zones) {
    activeLayout().zones.forEach((other, otherIndex) => {
      if (otherIndex === index) return;
      xTargets.push(other.x, other.x + other.width);
      yTargets.push(other.y, other.y + other.height);
    });
  }

  if (resize) {
    const right = snapNumber(zone.x + zone.width, xTargets, snapTolerance);
    const bottom = snapNumber(zone.y + zone.height, yTargets, snapTolerance);
    zone.width = right - zone.x;
    zone.height = bottom - zone.y;
  } else {
    const snappedX = snapNumber(zone.x, xTargets, snapTolerance);
    const snappedY = snapNumber(zone.y, yTargets, snapTolerance);
    const snappedRight = snapNumber(zone.x + zone.width, xTargets, snapTolerance);
    const snappedBottom = snapNumber(zone.y + zone.height, yTargets, snapTolerance);

    zone.x = Math.abs(snappedX - zone.x) <= Math.abs(snappedRight - (zone.x + zone.width))
      ? snappedX
      : snappedRight - zone.width;
    zone.y = Math.abs(snappedY - zone.y) <= Math.abs(snappedBottom - (zone.y + zone.height))
      ? snappedY
      : snappedBottom - zone.height;
  }

  normalizeZone(zone);
}

function setStatus(text, type = "") {
  const node = el("status");
  node.textContent = text;
  node.className = `status${type ? ` is-${type}` : ""}`;
}

function selectedJson() {
  return exportLayouts(layouts, activeFormat());
}

function refreshJson() {
  el("json").value = selectedJson();
  el("formatHelp").textContent = formatDescriptions[activeFormat()];
}

function render() {
  if (!layouts.length) {
    layouts.push({ name: "Layout 1", padding: 10, zones: [] });
  }

  layoutIndex = clamp(layoutIndex, 0, layouts.length - 1);
  zoneIndex = clamp(zoneIndex, 0, Math.max(0, activeLayout().zones.length - 1));

  el("layoutList").innerHTML = "";
  layouts.forEach((layout, index) => {
    const item = document.createElement("button");
    item.type = "button";
    item.className = `item${index === layoutIndex ? " active" : ""}`;
    item.textContent = `${index + 1}. ${layout.name || "Unnamed"}`;
    item.onclick = () => {
      layoutIndex = index;
      zoneIndex = 0;
      render();
    };
    el("layoutList").append(item);
  });

  el("layoutName").value = activeLayout().name || "";
  el("layoutPadding").value = activeLayout().padding || 0;
  applyPreviewRatio();

  canvas.innerHTML = "";
  activeLayout().zones.forEach((zone, index) => {
    normalizeZone(zone);

    const size = previewSize();
    const padding = Math.max(0, Number(activeLayout().padding) || 0);
    const zonePixelWidth = (zone.width / 100) * size.width;
    const zonePixelHeight = (zone.height / 100) * size.height;
    const insetX = clamp(padding, 0, Math.max(0, zonePixelWidth / 2));
    const insetY = clamp(padding, 0, Math.max(0, zonePixelHeight / 2));

    const node = document.createElement("div");
    node.className = `zone${index === zoneIndex ? " active" : ""}`;
    node.style.left = `${zone.x}%`;
    node.style.top = `${zone.y}%`;
    node.style.width = `${zone.width}%`;
    node.style.height = `${zone.height}%`;
    node.style.borderColor = zone.color || "";
    node.innerHTML = '<span class="padding-preview"></span><span class="label"></span><span class="handle"></span>';
    node.querySelector(".label").textContent = `Zone ${index + 1}`;

    const preview = node.querySelector(".padding-preview");
    preview.style.left = `${insetX}px`;
    preview.style.top = `${insetY}px`;
    preview.style.right = `${insetX}px`;
    preview.style.bottom = `${insetY}px`;

    node.onpointerdown = (event) => startDrag(event, index, event.target.classList.contains("handle"));
    canvas.append(node);
  });

  el("zoneList").innerHTML = "";
  activeLayout().zones.forEach((zone, index) => {
    const item = document.createElement("button");
    item.type = "button";
    item.className = `item${index === zoneIndex ? " active" : ""}`;
    item.textContent = `Zone ${index + 1}: ${zone.x}, ${zone.y}, ${zone.width} x ${zone.height}`;
    item.onclick = () => {
      zoneIndex = index;
      render();
    };
    el("zoneList").append(item);
  });

  const zone = activeZone();
  for (const id of ["zoneX", "zoneY", "zoneWidth", "zoneHeight", "zoneColor"]) {
    el(id).disabled = !zone;
  }

  if (zone) {
    el("zoneX").value = zone.x;
    el("zoneY").value = zone.y;
    el("zoneWidth").value = zone.width;
    el("zoneHeight").value = zone.height;
    el("zoneColor").value = zone.color || "";
  }

  refreshJson();
}

function importJsonText(text) {
  const parsed = JSON.parse(text);
  layouts = validateLayouts(parsed);
  layoutIndex = 0;
  zoneIndex = 0;
  render();
}

function loadPreset(key) {
  layouts = validateLayouts(deepClone(examples[key] || fallbackExamples[key]));
  layoutIndex = 0;
  zoneIndex = 0;
  render();
  setStatus(`Loaded ${activeLayout().name}.`, "success");
}

function startDrag(event, index, resize) {
  event.preventDefault();
  event.stopPropagation();

  zoneIndex = index;
  const point = canvasPoint(event);
  const zone = activeZone();
  drag = {
    mode: resize ? "resize" : "move",
    startX: event.clientX,
    startY: event.clientY,
    canvasW: point.rect.width,
    canvasH: point.rect.height,
    zone: { ...zone }
  };

  canvas.classList.add("dragging");
  canvas.setPointerCapture(event.pointerId);
  render();
}

canvas.onpointerdown = (event) => {
  if (event.target !== canvas) return;

  const point = canvasPoint(event);
  const zone = {
    x: Number(point.x.toFixed(1)),
    y: Number(point.y.toFixed(1)),
    width: 5,
    height: 5
  };

  activeLayout().zones.push(zone);
  zoneIndex = activeLayout().zones.length - 1;
  drag = {
    mode: "create",
    originX: point.x,
    originY: point.y
  };

  canvas.classList.add("dragging");
  canvas.setPointerCapture(event.pointerId);
  render();
};

canvas.onpointermove = (event) => {
  if (!drag) return;

  const zone = activeZone();
  if (!zone) return;

  if (drag.mode === "create") {
    const point = canvasPoint(event);
    zone.x = Number(Math.min(drag.originX, point.x).toFixed(1));
    zone.y = Number(Math.min(drag.originY, point.y).toFixed(1));
    zone.width = Number(Math.max(5, Math.abs(point.x - drag.originX)).toFixed(1));
    zone.height = Number(Math.max(5, Math.abs(point.y - drag.originY)).toFixed(1));
    normalizeZone(zone);
    snapZone(zone, zoneIndex, true);
    render();
    return;
  }

  const dx = ((event.clientX - drag.startX) / drag.canvasW) * 100;
  const dy = ((event.clientY - drag.startY) / drag.canvasH) * 100;

  if (drag.mode === "resize") {
    zone.width = clamp(Number((drag.zone.width + dx).toFixed(1)), 0.1, 100 - zone.x);
    zone.height = clamp(Number((drag.zone.height + dy).toFixed(1)), 0.1, 100 - zone.y);
  } else {
    zone.x = clamp(Number((drag.zone.x + dx).toFixed(1)), 0, 100 - zone.width);
    zone.y = clamp(Number((drag.zone.y + dy).toFixed(1)), 0, 100 - zone.height);
  }

  snapZone(zone, zoneIndex, drag.mode === "resize");
  render();
};

function endDrag() {
  drag = null;
  canvas.classList.remove("dragging");
}

canvas.onpointerup = endDrag;
canvas.onpointercancel = endDrag;

el("addLayout").onclick = () => {
  layouts.push({ name: `Layout ${layouts.length + 1}`, padding: 10, zones: [{ x: 0, y: 0, width: 50, height: 50 }] });
  layoutIndex = layouts.length - 1;
  zoneIndex = 0;
  render();
};

el("duplicateLayout").onclick = () => {
  const copy = deepClone(activeLayout());
  copy.name = `${copy.name || "Layout"} Copy`;
  layouts.splice(layoutIndex + 1, 0, copy);
  layoutIndex += 1;
  render();
};

el("deleteLayout").onclick = () => {
  if (layouts.length <= 1) {
    setStatus("At least one layout is required.", "error");
    return;
  }

  layouts.splice(layoutIndex, 1);
  render();
};

el("moveLayoutUp").onclick = () => {
  if (layoutIndex <= 0) return;
  [layouts[layoutIndex - 1], layouts[layoutIndex]] = [layouts[layoutIndex], layouts[layoutIndex - 1]];
  layoutIndex -= 1;
  render();
};

el("moveLayoutDown").onclick = () => {
  if (layoutIndex >= layouts.length - 1) return;
  [layouts[layoutIndex + 1], layouts[layoutIndex]] = [layouts[layoutIndex], layouts[layoutIndex + 1]];
  layoutIndex += 1;
  render();
};

el("addZone").onclick = () => {
  activeLayout().zones.push({ x: 10, y: 10, width: 40, height: 40 });
  zoneIndex = activeLayout().zones.length - 1;
  render();
};

el("deleteZone").onclick = () => {
  if (!activeZone()) return;
  activeLayout().zones.splice(zoneIndex, 1);
  render();
};

el("clearCanvas").onclick = () => {
  activeLayout().zones = [];
  zoneIndex = 0;
  render();
  setStatus("Cleared the active layout.", "success");
};

el("resetCanvas").onclick = () => {
  layouts = deepClone(fallbackExamples.priority.concat(fallbackExamples.quadrants));
  layoutIndex = 0;
  zoneIndex = 0;
  render();
  setStatus("Restored the default layouts.", "success");
};

el("layoutName").oninput = (event) => {
  activeLayout().name = event.target.value;
  render();
};

el("layoutPadding").oninput = (event) => {
  activeLayout().padding = Math.max(0, Number(event.target.value) || 0);
  render();
};

el("previewRatio").onchange = () => {
  applyPreviewRatio();
  render();
};

for (const id of ["previewWidth", "previewHeight"]) {
  el(id).oninput = () => {
    el("previewRatio").value = "custom";
    applyPreviewRatio();
    render();
  };
}

for (const [id, key] of [["zoneX", "x"], ["zoneY", "y"], ["zoneWidth", "width"], ["zoneHeight", "height"]]) {
  el(id).oninput = (event) => {
    const zone = activeZone();
    if (!zone) return;
    zone[key] = Number(event.target.value);
    snapZone(zone, zoneIndex, key === "width" || key === "height");
    render();
  };
}

el("zoneColor").oninput = (event) => {
  const zone = activeZone();
  if (!zone) return;
  zone.color = event.target.value.trim();
  normalizeZone(zone);
  render();
};

el("loadJson").onclick = () => {
  try {
    importJsonText(el("json").value);
    setStatus("Imported pasted JSON.", "success");
  } catch (error) {
    setStatus(error.message, "error");
  }
};

el("openJson").onclick = () => {
  el("jsonFile").click();
};

el("jsonFile").onchange = async (event) => {
  const [file] = event.target.files;
  if (!file) return;

  try {
    importJsonText(await file.text());
    setStatus(`Opened ${file.name}.`, "success");
  } catch (error) {
    setStatus(error.message, "error");
  } finally {
    event.target.value = "";
  }
};

el("saveJson").onclick = () => {
  const blob = new Blob([selectedJson(), "\n"], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = layoutFileName(activeLayout(), activeFormat());
  link.click();
  URL.revokeObjectURL(url);
  setStatus("Saved JSON file.", "success");
};

el("copyJson").onclick = async () => {
  try {
    await navigator.clipboard.writeText(selectedJson());
    setStatus("Copied JSON.", "success");
  } catch (error) {
    el("json").focus();
    el("json").select();
    setStatus("Copy is blocked by this browser. The JSON is selected.", "error");
  }
};

for (const radio of document.querySelectorAll("input[name='format']")) {
  radio.onchange = () => {
    refreshJson();
    setStatus(`Export target set to ${radio.value === "kzones" ? "KZones" : "Magnetile"}.`, "success");
  };
}

el("loadPresetPriority").onclick = () => loadPreset("priority");
el("loadPresetQuadrants").onclick = () => loadPreset("quadrants");
el("loadPresetColumns").onclick = () => loadPreset("columns");

async function loadExamples() {
  try {
    const response = await fetch("examples/layouts.json");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    examples = await response.json();
  } catch (error) {
    examples = deepClone(fallbackExamples);
  }
}

loadExamples().finally(render);
