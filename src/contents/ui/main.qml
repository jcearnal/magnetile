import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kwin
import "../code/core.mjs" as Core
import "../code/utils.mjs" as Utils
import "components" as Components

Item {
    id: root

    property var config: new Object()
    property bool moving: false
    property bool moved: false
    property bool resizing: false
    property bool freeMoving: false
    property var clientArea: new Object()
    property var cachedClientArea: new Object()
    property var displaySize: new Object()
    property int currentLayout: 0
    property var screenLayouts: new Object()
    property var resizedZoneGeometries: new Object()
    property var mergedZones: new Object()
    property var resizeDebugInfo: new Object()
    property int highlightedZone: -1
    property var highlightedTarget: null
    property bool mergedZoneSelectionArmed: false
    property bool selectingMergedZones: false
    property var pendingMergeZones: []
    property var activeScreen: null
    property bool showZoneOverlay: config.zoneOverlayShowWhen == 0
    property int geometryTolerance: 3
    property string signalToken: Math.random().toString() + Date.now().toString()
    property bool disposing: false
    property bool outputsSettling: false

    function resizeDialogToClientArea(dialog) {
        const fallbackSize = workspaceVirtualScreenSize();
        const width = Math.max(1, Math.round(clientArea.width || fallbackSize.width || 1));
        const height = Math.max(1, Math.round(clientArea.height || fallbackSize.height || 1));
        dialog.setWidth(width);
        dialog.setHeight(height);
    }

    function hideDialogSurface(dialog) {
        dialog.visible = false;
        dialog.setWidth(1);
        dialog.setHeight(1);
    }

    function clientOutput(client) {
        return client && (client.output || client.screen || Workspace.activeScreen);
    }

    function outputName(screen) {
        return screen && screen.name ? screen.name : "";
    }

    function workspaceVirtualScreenSize() {
        try {
            const size = Workspace.virtualScreenSize;
            if (size && isFinite(size.width) && isFinite(size.height))
                return size;

        } catch (error) {
            Utils.log("Could not read virtual screen size: " + error, "warning");
        }
        return Qt.size(0, 0);
    }

    function workspaceArea(screen, desktop) {
        const resolvedScreen = screen || activeScreen || Workspace.activeScreen;
        const resolvedDesktop = desktop || Workspace.currentDesktop;
        if (!resolvedScreen || !resolvedDesktop)
            return Qt.rect(0, 0, 0, 0);

        try {
            const area = Workspace.clientArea(KWin.FullScreenArea, resolvedScreen, resolvedDesktop);
            if (area && isFinite(area.x) && isFinite(area.y) && isFinite(area.width) && isFinite(area.height))
                return area;

        } catch (error) {
            Utils.log("Could not read client area for " + outputName(resolvedScreen) + ": " + error, "warning");
        }
        return Qt.rect(0, 0, 0, 0);
    }

    function workspaceGeometryReady(screen) {
        const size = workspaceVirtualScreenSize();
        const area = workspaceArea(screen, Workspace.currentDesktop);
        return size.width > 0 && size.height > 0 && area.width > 0 && area.height > 0;
    }

    function canMutateWindowGeometry(client) {
        return !disposing && !outputsSettling && workspaceGeometryReady(client ? clientOutput(client) : activeScreen || Workspace.activeScreen);
    }

    function clampLayoutIndex(layout) {
        if (!config.layouts || config.layouts.length === 0)
            return 0;

        const index = Number(layout);
        if (!isFinite(index))
            return 0;

        return Math.max(0, Math.min(config.layouts.length - 1, Math.round(index)));
    }

    function layoutIndexByName(name) {
        if (!config.layouts || name === undefined || name === null)
            return -1;

        const layoutName = name.toString();
        for (let i = 0; i < config.layouts.length; i++) {
            if (config.layouts[i].name === layoutName)
                return i;

        }
        return -1;
    }

    function layoutIndexFromAssignment(assigned) {
        if (assigned === undefined || assigned === null || assigned === "")
            return -1;

        if (typeof assigned === "number")
            return clampLayoutIndex(assigned);

        if (typeof assigned === "string") {
            const byName = layoutIndexByName(assigned);
            if (byName !== -1)
                return byName;

            const byIndex = parseInt(assigned, 10);
            if (!isNaN(byIndex))
                return clampLayoutIndex(byIndex);

        }
        return -1;
    }

    function outputOrientation(screen) {
        const area = workspaceArea(screen || activeScreen || Workspace.activeScreen, Workspace.currentDesktop);
        return area.height > area.width ? "portrait" : "landscape";
    }

    function orientationDefaultLayout(screen) {
        const orientation = outputOrientation(screen);
        const preferred = orientation === "portrait" ? "Horizontal Split" : "Priority Grid";
        const preferredIndex = layoutIndexByName(preferred);
        if (preferredIndex !== -1)
            return preferredIndex;

        return 0;
    }

    function configuredLayoutForOutput(screen) {
        const name = outputName(screen);
        const orientation = outputOrientation(screen);
        const defaults = config.monitorLayouts || {};
        const outputLayout = layoutIndexFromAssignment(name ? defaults[name] : undefined);
        if (outputLayout !== -1)
            return outputLayout;

        const orientationLayout = layoutIndexFromAssignment(defaults[orientation] !== undefined ? defaults[orientation] : defaults["__" + orientation]);
        if (orientationLayout !== -1)
            return orientationLayout;

        return orientationDefaultLayout(screen);
    }

    function clientDesktops(client) {
        if (client && client.desktops)
            return client.desktops;

        if (client && client.desktop)
            return [client.desktop];

        return [Workspace.currentDesktop];
    }

    function sameDesktop(client, desktop) {
        return clientDesktops(client).indexOf(desktop) !== -1;
    }

    function clientActivity(client) {
        return client && client.activity !== undefined ? client.activity : Workspace.currentActivity;
    }

    function clientDebugName(client) {
        if (!client)
            return "<none>";

        if (client.caption)
            return client.caption.toString();

        if (client.resourceClass)
            return client.resourceClass.toString();

        return "<window>";
    }

    function clientStackLabel(client) {
        if (!client)
            return "<none>";

        const caption = client.caption ? client.caption.toString() : "";
        const resourceClass = client.resourceClass ? client.resourceClass.toString() : "";
        if (caption && resourceClass && caption !== resourceClass)
            return caption + " (" + resourceClass + ")";

        return caption || resourceClass || "<window>";
    }

    function clientResourceClass(client) {
        return client && client.resourceClass ? client.resourceClass.toString() : "";
    }

    function isProtectedCaptureClient(client) {
        const resourceClass = clientResourceClass(client);
        return resourceClass === "org.kde.spectacle" || resourceClass === "spectacle";
    }

    function debugInfo() {
        return {
            "activeWindow": {
                "caption": Workspace.activeWindow && Workspace.activeWindow.caption,
                "resourceClass": Workspace.activeWindow && Workspace.activeWindow.resourceClass && Workspace.activeWindow.resourceClass.toString(),
                "frameGeometry": {
                    "x": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.x,
                    "y": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.y,
                    "width": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.width,
                    "height": Workspace.activeWindow && Workspace.activeWindow.frameGeometry && Workspace.activeWindow.frameGeometry.height
                },
                "zone": Workspace.activeWindow && Workspace.activeWindow.zone
            },
            "highlightedZone": highlightedZone,
            "moving": moving,
            "resizing": resizing,
            "oldGeometry": Workspace.activeWindow && Workspace.activeWindow.oldGeometry,
            "activeScreen": activeScreen && activeScreen.name,
            "currentLayout": currentLayout,
            "screenLayouts": screenLayouts,
            "resize": resizeDebugInfo
        };
    }

    function updateDebugDialog() {
        if (config.enableDebugOverlay && resizing) {
            refreshClientArea(activeScreen || Workspace.activeScreen);
            resizeDialogToClientArea(debugDialog);
            debugDialog.visible = true;
        } else {
            hideDialogSurface(debugDialog);
        }
    }

    function validLayoutIndex(layout) {
        const index = Number(layout);
        return config.layouts && isFinite(index) && index >= 0 && index < config.layouts.length;
    }

    function validZoneIndex(layout, zone) {
        if (!validLayoutIndex(layout))
            return false;

        const index = Number(zone);
        return isFinite(index) && index >= 0 && index < config.layouts[Math.round(layout)].zones.length;
    }

    function clientInCurrentScope(client, output, desktop, activity) {
        return clientOutput(client) === output && sameDesktop(client, desktop) && clientActivity(client) === activity;
    }

    function recoverClientZone(client, layout, fallbackToClosest) {
        if (!checkFilter(client) || !validLayoutIndex(layout))
            return -1;

        const layoutIndex = clampLayoutIndex(layout);
        if (validZoneIndex(layoutIndex, client.zone) && client.layout === layoutIndex)
            return client.zone;

        const matchedZone = matchZoneInLayout(client, layoutIndex);
        if (matchedZone !== -1)
            return matchedZone;

        if (!fallbackToClosest)
            return -1;

        const closestZone = closestConfiguredZone(client, layoutIndex, clientOutput(client));
        if (closestZone !== -1) {
            client.zone = closestZone;
            client.layout = layoutIndex;
            client.desktop = Workspace.currentDesktop;
            client.activity = Workspace.currentActivity;
        }
        return closestZone;
    }

    function refreshClientArea(screen) {
        activeScreen = screen || Workspace.activeScreen;
        clientArea = workspaceArea(activeScreen, Workspace.currentDesktop);
        displaySize = workspaceVirtualScreenSize();
        currentLayout = getCurrentLayout();
    }

    function refreshClientAreaForClient(client) {
        refreshClientArea(clientOutput(client));
    }

    function roundedRect(x, y, width, height) {
        return Qt.rect(Math.round(x), Math.round(y), Math.round(width), Math.round(height));
    }

    function rectEdges(geometry) {
        return {
            "left": geometry.x,
            "top": geometry.y,
            "right": geometry.x + geometry.width,
            "bottom": geometry.y + geometry.height,
            "width": geometry.width,
            "height": geometry.height
        };
    }

    function rectsClose(a, b, tolerance) {
        const diff = tolerance || geometryTolerance;
        return Math.abs(a.x - b.x) <= diff &&
            Math.abs(a.y - b.y) <= diff &&
            Math.abs(a.width - b.width) <= diff &&
            Math.abs(a.height - b.height) <= diff;
    }

    function rangesOverlap(aStart, aEnd, bStart, bEnd, tolerance) {
        const diff = tolerance || geometryTolerance;
        return aStart < bEnd - diff && aEnd > bStart + diff;
    }

    function resizeGapTolerance(layout) {
        const padding = layout && layout.padding ? Number(layout.padding) : 0;
        const safePadding = isFinite(padding) ? Math.max(0, padding) : 0;
        return Math.max(geometryTolerance, safePadding + geometryTolerance);
    }

    function isResizeAdjacent(edgeGap, tolerance) {
        return edgeGap >= -geometryTolerance && edgeGap <= tolerance;
    }

    function preservedResizeGap(edgeGap) {
        return Math.max(0, edgeGap);
    }

    function edgesAligned(a, b) {
        return Math.abs(a - b) <= geometryTolerance;
    }

    function runtimeZoneKey(layoutIndex, zoneIndex, screen, desktop, activity) {
        const resolvedScreen = screen || activeScreen || Workspace.activeScreen;
        const resolvedDesktop = desktop || Workspace.currentDesktop;
        const area = workspaceArea(resolvedScreen, resolvedDesktop);
        const parts = [
            clampLayoutIndex(layoutIndex),
            zoneIndex,
            outputName(resolvedScreen),
            area.x,
            area.y,
            area.width,
            area.height,
            resolvedDesktop && resolvedDesktop.id ? resolvedDesktop.id : "",
            activity !== undefined && activity !== null ? activity : ""
        ];
        return parts.join(":");
    }

    function layoutScopeKey(layoutIndex, screen, desktop, activity) {
        const resolvedScreen = screen || activeScreen || Workspace.activeScreen;
        const resolvedDesktop = desktop || Workspace.currentDesktop;
        const area = workspaceArea(resolvedScreen, resolvedDesktop);
        const parts = [
            clampLayoutIndex(layoutIndex),
            outputName(resolvedScreen),
            area.x,
            area.y,
            area.width,
            area.height,
            resolvedDesktop && resolvedDesktop.id ? resolvedDesktop.id : "",
            activity !== undefined && activity !== null ? activity : ""
        ];
        return parts.join(":");
    }

    function isArrayValue(value) {
        return Object.prototype.toString.call(value) === "[object Array]";
    }

    function normalizeZoneList(layoutIndex, zones) {
        if (!validLayoutIndex(layoutIndex))
            return [];

        const input = isArrayValue(zones) ? zones : [zones];
        const seen = {};
        const normalized = [];
        for (let i = 0; i < input.length; i++) {
            const zone = Number(input[i]);
            if (!isFinite(zone))
                continue;

            const index = Math.round(zone);
            if (!validZoneIndex(layoutIndex, index) || seen[index])
                continue;

            seen[index] = true;
            normalized.push(index);
        }
        normalized.sort(function(a, b) {
            return a - b;
        });
        return normalized;
    }

    function mergeIdForZones(zones) {
        return zones.join(",");
    }

    function activeMergedZones(layoutIndex, screen, desktop, activity) {
        const key = layoutScopeKey(layoutIndex, screen, desktop, activity);
        const merges = mergedZones[key];
        return isArrayValue(merges) ? merges : [];
    }

    function storeMergedZones(layoutIndex, screen, desktop, activity, merges) {
        const key = layoutScopeKey(layoutIndex, screen, desktop, activity);
        mergedZones[key] = merges;
        mergedZones = Object.assign({}, mergedZones);
    }

    function clearMergedZones(layoutIndex, screen, desktop, activity) {
        const key = layoutScopeKey(layoutIndex, screen, desktop, activity);
        delete mergedZones[key];
        mergedZones = Object.assign({}, mergedZones);
    }

    function clientZones(client) {
        if (!client)
            return [];

        if (validLayoutIndex(client.layout)) {
            const multiZones = normalizeZoneList(client.layout, client.zones);
            if (multiZones.length > 0)
                return multiZones;

            if (validZoneIndex(client.layout, client.zone))
                return [Math.round(Number(client.zone))];
        }
        return [];
    }

    function zonesOverlap(a, b) {
        const seen = {};
        for (let i = 0; i < a.length; i++)
            seen[a[i]] = true;

        for (let i = 0; i < b.length; i++) {
            if (seen[b[i]])
                return true;

        }
        return false;
    }

    function zonesFormRectangle(layoutIndex, zones) {
        const normalized = normalizeZoneList(layoutIndex, zones);
        if (normalized.length <= 1)
            return true;

        const layout = clampLayoutIndex(layoutIndex);
        let left = Infinity;
        let top = Infinity;
        let right = -Infinity;
        let bottom = -Infinity;
        let totalArea = 0;
        for (let i = 0; i < normalized.length; i++) {
            const zone = config.layouts[layout].zones[normalized[i]];
            const zoneLeft = Number(zone.x);
            const zoneTop = Number(zone.y);
            const zoneRight = zoneLeft + Number(zone.width);
            const zoneBottom = zoneTop + Number(zone.height);
            left = Math.min(left, zoneLeft);
            top = Math.min(top, zoneTop);
            right = Math.max(right, zoneRight);
            bottom = Math.max(bottom, zoneBottom);
            totalArea += Number(zone.width) * Number(zone.height);
        }

        const unionArea = (right - left) * (bottom - top);
        return Math.abs(unionArea - totalArea) <= 0.01;
    }

    function zonesUnionGeometry(layoutIndex, zones, screen) {
        const normalized = normalizeZoneList(layoutIndex, zones);
        if (normalized.length === 0)
            return null;

        let left = Infinity;
        let top = Infinity;
        let right = -Infinity;
        let bottom = -Infinity;
        for (let i = 0; i < normalized.length; i++) {
            const geometry = zoneGeometry(layoutIndex, normalized[i], screen);
            left = Math.min(left, geometry.x);
            top = Math.min(top, geometry.y);
            right = Math.max(right, geometry.x + geometry.width);
            bottom = Math.max(bottom, geometry.y + geometry.height);
        }

        if (!isFinite(left) || !isFinite(top) || !isFinite(right) || !isFinite(bottom))
            return null;

        return roundedRect(left, top, right - left, bottom - top);
    }

    function configuredZoneForTarget(layoutIndex, zoneIndex) {
        if (!validZoneIndex(layoutIndex, zoneIndex))
            return {};

        return config.layouts[clampLayoutIndex(layoutIndex)].zones[zoneIndex] || {};
    }

    function targetGeometry(target) {
        if (!target)
            return null;

        const stored = rectFromStoredGeometry(target.geometry);
        if (stored)
            return stored;

        if (target.type === "merge")
            return zonesUnionGeometry(target.layout, target.zones, target.output || activeScreen || Workspace.activeScreen);

        if (validZoneIndex(target.layout, target.zone))
            return zoneGeometry(target.layout, target.zone, target.output || activeScreen || Workspace.activeScreen);

        return null;
    }

    function targetContainsZone(target, zone) {
        if (!target)
            return false;

        const zones = normalizeZoneList(target.layout, target.zones !== undefined ? target.zones : target.zone);
        return zones.indexOf(Math.round(Number(zone))) !== -1;
    }

    function singleZoneTarget(layoutIndex, zoneIndex, screen, desktop, activity) {
        if (!validZoneIndex(layoutIndex, zoneIndex))
            return null;

        const layout = clampLayoutIndex(layoutIndex);
        const resolvedScreen = screen || activeScreen || Workspace.activeScreen;
        const zone = config.layouts[layout].zones[zoneIndex];
        return {
            "type": "zone",
            "id": zoneIndex.toString(),
            "layout": layout,
            "zone": zoneIndex,
            "zones": [zoneIndex],
            "geometry": zoneGeometry(layout, zoneIndex, resolvedScreen),
            "output": resolvedScreen,
            "color": zone.color,
            "label": (zoneIndex + 1).toString()
        };
    }

    function effectiveTargetForZone(layoutIndex, zoneIndex, screen, desktop, activity) {
        const targets = effectiveZoneTargets(layoutIndex, screen, desktop, activity);
        for (let i = 0; i < targets.length; i++) {
            if (targetContainsZone(targets[i], zoneIndex))
                return targets[i];

        }
        return singleZoneTarget(layoutIndex, zoneIndex, screen, desktop, activity);
    }

    function mergeTargetFromZones(layoutIndex, zones, screen, desktop, activity) {
        const layout = clampLayoutIndex(layoutIndex);
        const normalized = normalizeZoneList(layout, zones);
        if (normalized.length === 0)
            return null;

        if (normalized.length === 1)
            return singleZoneTarget(layout, normalized[0], screen, desktop, activity);

        const geometry = zonesUnionGeometry(layout, normalized, screen);
        if (!geometry)
            return null;

        const anchor = normalized[0];
        const anchorZone = configuredZoneForTarget(layout, anchor);
        return {
            "type": "merge",
            "id": mergeIdForZones(normalized),
            "layout": layout,
            "zone": anchor,
            "zones": normalized,
            "geometry": geometry,
            "output": screen || activeScreen || Workspace.activeScreen,
            "color": anchorZone.color,
            "label": normalized.map(function(zone) {
                return zone + 1;
            }).join("+")
        };
    }

    function mergeZones(layoutIndex, zones, screen, desktop, activity) {
        const layout = clampLayoutIndex(layoutIndex);
        const normalized = normalizeZoneList(layout, zones);
        if (normalized.length <= 1)
            return mergeTargetFromZones(layout, normalized, screen, desktop, activity);

        if (!zonesFormRectangle(layout, normalized)) {
            Utils.osd("Merged zones must form a rectangle");
            return null;
        }

        const target = mergeTargetFromZones(layout, normalized, screen, desktop, activity);
        if (!target)
            return null;

        const resolvedScreen = screen || activeScreen || Workspace.activeScreen;
        const resolvedDesktop = desktop || Workspace.currentDesktop;
        const resolvedActivity = activity !== undefined && activity !== null ? activity : Workspace.currentActivity;
        const current = activeMergedZones(layout, resolvedScreen, resolvedDesktop, resolvedActivity);
        const next = [];
        for (let i = 0; i < current.length; i++) {
            const merge = current[i];
            const mergeZonesList = normalizeZoneList(layout, merge && merge.zones);
            if (!zonesOverlap(mergeZonesList, normalized))
                next.push(merge);

        }
        next.push({
            "id": target.id,
            "zones": normalized,
            "geometry": target.geometry,
            "color": target.color,
            "label": target.label
        });
        storeMergedZones(layout, resolvedScreen, resolvedDesktop, resolvedActivity, next);
        return target;
    }

    function addZonesToPendingMerge(zones, notify) {
        const candidate = normalizeZoneList(currentLayout, pendingMergeZones.concat(normalizeZoneList(currentLayout, zones)));
        if (candidate.length === pendingMergeZones.length)
            return false;

        if (!zonesFormRectangle(currentLayout, candidate)) {
            if (notify)
                Utils.osd("Merged zones must form a rectangle");

            return false;
        }

        pendingMergeZones = candidate;
        return true;
    }

    function toggleMergedZoneSelection() {
        if (!moving || !mainDialog.visible) {
            mergedZoneSelectionArmed = !mergedZoneSelectionArmed;
            selectingMergedZones = false;
            pendingMergeZones = [];
            Utils.osd(mergedZoneSelectionArmed ? "Multi-zone selection armed for next drag" : "Multi-zone selection disarmed");
            return;
        }

        if (!selectingMergedZones) {
            const initialZones = highlightedTarget ? highlightedTarget.zones : (validZoneIndex(currentLayout, highlightedZone) ? [highlightedZone] : []);
            if (initialZones.length === 0) {
                Utils.osd("Hover a zone before starting multi-zone selection");
                return;
            }

            pendingMergeZones = normalizeZoneList(currentLayout, initialZones);
            selectingMergedZones = true;
            Utils.osd("Multi-zone selection started");
            return;
        }

        if (pendingMergeZones.length > 1) {
            Utils.osd("Multi-zone selection ready");
        } else {
            selectingMergedZones = false;
            pendingMergeZones = [];
            Utils.osd("Multi-zone selection cancelled");
        }
    }

    function effectiveZoneTargets(layoutIndex, screen, desktop, activity) {
        if (!validLayoutIndex(layoutIndex))
            return [];

        const layout = clampLayoutIndex(layoutIndex);
        const resolvedScreen = screen || activeScreen || Workspace.activeScreen;
        const resolvedDesktop = desktop || Workspace.currentDesktop;
        const resolvedActivity = activity !== undefined && activity !== null ? activity : Workspace.currentActivity;
        const hiddenZones = {};
        const targets = [];
        const merges = activeMergedZones(layout, resolvedScreen, resolvedDesktop, resolvedActivity);

        for (let i = 0; i < merges.length; i++) {
            const merge = merges[i] || {};
            const zones = normalizeZoneList(layout, merge.zones);
            if (zones.length === 0)
                continue;

            const geometry = rectFromStoredGeometry(merge.geometry) || zonesUnionGeometry(layout, zones, resolvedScreen);
            if (!geometry)
                continue;

            const anchor = zones[0];
            const anchorZone = configuredZoneForTarget(layout, anchor);
            for (let zoneIndex = 0; zoneIndex < zones.length; zoneIndex++)
                hiddenZones[zones[zoneIndex]] = true;

            targets.push({
                "type": "merge",
                "id": merge.id || mergeIdForZones(zones),
                "layout": layout,
                "zone": anchor,
                "zones": zones,
                "geometry": geometry,
                "output": resolvedScreen,
                "color": merge.color || anchorZone.color,
                "label": merge.label || zones.map(function(zone) {
                    return zone + 1;
                }).join("+")
            });
        }

        const zones = config.layouts[layout].zones;
        for (let i = 0; i < zones.length; i++) {
            if (hiddenZones[i])
                continue;

            const geometry = zoneGeometry(layout, i, resolvedScreen);
            targets.push({
                "type": "zone",
                "id": i.toString(),
                "layout": layout,
                "zone": i,
                "zones": [i],
                "geometry": geometry,
                "output": resolvedScreen,
                "color": zones[i].color,
                "label": (i + 1).toString()
            });
        }

        targets.sort(function(a, b) {
            return a.zone - b.zone;
        });
        return targets;
    }

    function clearClientTargetProperties(client) {
        if (!client)
            return;

        client.zones = [];
        client.magnetileMergedZone = "";
    }

    function rectFromStoredGeometry(geometry) {
        if (!geometry)
            return null;

        if (!isFinite(geometry.x) || !isFinite(geometry.y) || !isFinite(geometry.width) || !isFinite(geometry.height))
            return null;

        return roundedRect(geometry.x, geometry.y, geometry.width, geometry.height);
    }

    function storeRuntimeZoneGeometry(layoutIndex, zoneIndex, screen, desktop, activity, geometry) {
        if (zoneIndex === undefined || zoneIndex === -1 || !geometry)
            return;

        const key = runtimeZoneKey(layoutIndex, zoneIndex, screen, desktop, activity);
        resizedZoneGeometries[key] = {
            "x": Math.round(geometry.x),
            "y": Math.round(geometry.y),
            "width": Math.round(geometry.width),
            "height": Math.round(geometry.height)
        };
    }

    function clearRuntimeLayoutGeometry(layoutIndex, screen, desktop, activity) {
        const zones = config.layouts[clampLayoutIndex(layoutIndex)].zones;
        for (let i = 0; i < zones.length; i++)
            delete resizedZoneGeometries[runtimeZoneKey(layoutIndex, i, screen, desktop, activity)];

    }

    function resetCurrentLayoutGeometry() {
        const referenceClient = Workspace.activeWindow;
        if (referenceClient)
            refreshClientAreaForClient(referenceClient);
        else
            refreshClientArea(activeScreen || Workspace.activeScreen);

        const output = referenceClient ? clientOutput(referenceClient) : activeScreen || Workspace.activeScreen;
        const desktop = Workspace.currentDesktop;
        const activity = Workspace.currentActivity;
        const layout = currentLayout;
        let count = 0;

        clearRuntimeLayoutGeometry(layout, output, desktop, activity);
        clearMergedZones(layout, output, desktop, activity);
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (!checkFilter(client) || client.minimized)
                continue;

            if (clientOutput(client) !== output || !sameDesktop(client, desktop) || clientActivity(client) !== activity)
                continue;

            let zone = -1;
            if (clientInCurrentScope(client, output, desktop, activity))
                zone = recoverClientZone(client, layout, true);

            if (zone < 0 || zone >= config.layouts[layout].zones.length)
                continue;

            client.setMaximize(false, false);
            client.frameGeometry = zoneGeometry(layout, zone, output);
            client.zone = zone;
            client.layout = layout;
            client.desktop = desktop;
            client.activity = activity;
            client.magnetileFreeMove = false;
            client.magnetileTiled = true;
            client.magnetileResizeSnapshot = null;
            clearClientTargetProperties(client);
            count++;
        }

        resizedZoneGeometries = Object.assign({}, resizedZoneGeometries);
        Utils.osd(count > 0 ? `Reset ${count} window${count === 1 ? "" : "s"} to ${config.layouts[layout].name}` : `Reset ${config.layouts[layout].name}`);
    }

    function closestConfiguredZone(client, layoutIndex, screen) {
        const layout = clampLayoutIndex(layoutIndex);
        const zones = config.layouts[layout].zones;
        const geometry = client.frameGeometry;
        const center = {
            "x": geometry.x + geometry.width / 2,
            "y": geometry.y + geometry.height / 2
        };
        let closestZone = -1;
        let closestDistance = Infinity;

        for (let i = 0; i < zones.length; i++) {
            const zone = zoneGeometry(layout, i, screen);
            const zoneCenter = {
                "x": zone.x + zone.width / 2,
                "y": zone.y + zone.height / 2
            };
            const distance = Math.sqrt(Math.pow(center.x - zoneCenter.x, 2) + Math.pow(center.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                closestZone = i;
                closestDistance = distance;
            }
        }

        return closestZone;
    }

    function snapshotZoneGeometries(layoutIndex, screen) {
        const zones = config.layouts[clampLayoutIndex(layoutIndex)].zones;
        const geometries = [];
        for (let i = 0; i < zones.length; i++)
            geometries.push(zoneGeometry(layoutIndex, i, screen));

        return geometries;
    }

    function zoneGeometry(layoutIndex, zoneIndex, screen) {
        const stored = rectFromStoredGeometry(resizedZoneGeometries[runtimeZoneKey(layoutIndex, zoneIndex, screen, Workspace.currentDesktop, Workspace.currentActivity)]);
        if (stored)
            return stored;

        return configuredZoneGeometry(layoutIndex, zoneIndex, screen);
    }

    function configuredZoneGeometry(layoutIndex, zoneIndex, screen) {
        const layout = config.layouts[clampLayoutIndex(layoutIndex)];
        const zone = layout.zones[zoneIndex];
        const zonePadding = layout.padding || 0;
        const area = workspaceArea(screen || activeScreen || Workspace.activeScreen, Workspace.currentDesktop);
        const zoneX = area.x + ((zone.x / 100) * (area.width - zonePadding)) + zonePadding;
        const zoneY = area.y + ((zone.y / 100) * (area.height - zonePadding)) + zonePadding;
        const zoneWidth = ((zone.width / 100) * (area.width - zonePadding)) - zonePadding;
        const zoneHeight = ((zone.height / 100) * (area.height - zonePadding)) - zonePadding;
        return roundedRect(zoneX, zoneY, zoneWidth, zoneHeight);
    }

    function matchZoneInLayout(client, layout) {
        if (!checkFilter(client))
            return -1;

        const layoutIndex = clampLayoutIndex(layout);
        const targets = effectiveZoneTargets(layoutIndex, clientOutput(client), Workspace.currentDesktop, Workspace.currentActivity);
        for (let i = 0; i < targets.length; i++) {
            const target = targets[i];
            const geometry = targetGeometry(target);
            if (geometry && rectsClose(client.frameGeometry, geometry)) {
                client.zone = target.zone;
                client.layout = layoutIndex;
                client.desktop = Workspace.currentDesktop;
                client.activity = Workspace.currentActivity;
                client.magnetileTiled = true;
                client.zones = normalizeZoneList(layoutIndex, target.zones);
                client.magnetileMergedZone = target.type === "merge" ? target.id : "";
                return target.zone;
            }
        }

        const zones = config.layouts[layoutIndex].zones;
        // loop through zones and compare with the geometries of the client
        for (let i = 0; i < zones.length; i++) {
            const geometry = zoneGeometry(layoutIndex, i, clientOutput(client));
            if (rectsClose(client.frameGeometry, geometry)) {
                // zone found, set it and exit the loop
                client.zone = i;
                client.layout = layoutIndex;
                client.desktop = Workspace.currentDesktop;
                client.activity = Workspace.currentActivity;
                client.magnetileTiled = true;
                client.zones = [i];
                client.magnetileMergedZone = "";
                return i;
            }
        }
        return -1;
    }

    function matchResizeZoneInLayout(client, layout) {
        if (!checkFilter(client))
            return -1;

        if (clientZones(client).length > 1)
            return -1;

        const layoutIndex = clampLayoutIndex(layout);
        const output = clientOutput(client);
        if (client.magnetileTiled === true && validZoneIndex(layoutIndex, client.zone) && client.layout === layoutIndex) {
            const geometry = zoneGeometry(layoutIndex, client.zone, output);
            if (rectsClose(client.frameGeometry, geometry))
                return client.zone;

        }

        const zones = config.layouts[layoutIndex].zones;
        for (let i = 0; i < zones.length; i++) {
            const geometry = configuredZoneGeometry(layoutIndex, i, output);
            if (rectsClose(client.frameGeometry, geometry)) {
                client.zone = i;
                client.layout = layoutIndex;
                client.desktop = Workspace.currentDesktop;
                client.activity = Workspace.currentActivity;
                client.magnetileTiled = true;
                client.zones = [i];
                client.magnetileMergedZone = "";
                return i;
            }
        }
        return -1;
    }

    function matchZone(client) {
        if (!checkFilter(client))
            return -1;

        if (!workspaceGeometryReady(clientOutput(client)))
            return -1;

        refreshClientAreaForClient(client);
        client.zone = -1;
        matchZoneInLayout(client, currentLayout);
        return client.zone;
    }

    function matchZoneAnyLayout(client, preferredLayout) {
        if (!checkFilter(client))
            return -1;

        refreshClientAreaForClient(client);
        client.zone = -1;
        const layoutsToCheck = [];
        const preferred = clampLayoutIndex(preferredLayout !== undefined ? preferredLayout : currentLayout);
        layoutsToCheck.push(preferred);
        for (let i = 0; i < config.layouts.length; i++) {
            if (layoutsToCheck.indexOf(i) === -1)
                layoutsToCheck.push(i);

        }
        for (let i = 0; i < layoutsToCheck.length; i++) {
            const zone = matchZoneInLayout(client, layoutsToCheck[i]);
            if (zone !== -1)
                return zone;

        }
        return -1;
    }

    function getWindowsInZone(zone, layout) {
        const windows = [];
        const activeWindow = Workspace.activeWindow;
        const output = clientOutput(activeWindow);
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (!checkFilter(client) || client.minimized || !clientInCurrentScope(client, output, Workspace.currentDesktop, Workspace.currentActivity))
                continue;

            recoverClientZone(client, layout, true);
            if (client.layout === layout && clientZones(client).indexOf(zone) !== -1 && windows.indexOf(client) === -1)
                windows.push(client);

        }
        return windows;
    }

    function switchWindowInZone(zone, layout, reverse) {
        const clientsInZone = getWindowsInZone(zone, layout);
        if (reverse)
            clientsInZone.reverse();

        // cycle through clients in zone
        if (clientsInZone.length > 0) {
            const index = clientsInZone.indexOf(Workspace.activeWindow);
            let nextIndex = 0;
            if (index === -1)
                nextIndex = 0;
            else
                nextIndex = (index + 1) % clientsInZone.length;

            const nextClient = clientsInZone[nextIndex];
            Workspace.activeWindow = nextClient;
            Utils.osd("Zone " + (zone + 1) + ": " + (nextIndex + 1) + "/" + clientsInZone.length + " " + clientStackLabel(nextClient));
            return nextClient;
        }
        Utils.osd("No other windows in zone " + (zone + 1));
        return null;
    }

    function moveClientToZone(client, zone) {
        if (!checkFilter(client))
            return ;

        if (!canMutateWindowGeometry(client)) {
            Utils.log("Skipping move while output geometry is not stable");
            return ;
        }

        Utils.log("Moving client " + client.resourceClass.toString() + " to zone " + zone);
        refreshClientAreaForClient(client);
        // move client to zone
        if (zone != -1) {
            if (zone < 0 || zone >= config.layouts[currentLayout].zones.length)
                return;

            moveClientToTarget(client, effectiveTargetForZone(currentLayout, zone, clientOutput(client), Workspace.currentDesktop, Workspace.currentActivity));
        } else {
            saveClientProperties(client, zone);
        }
    }

    function moveClientToTarget(client, target) {
        if (!checkFilter(client) || !target)
            return;

        if (!canMutateWindowGeometry(client)) {
            Utils.log("Skipping target move while output geometry is not stable");
            return;
        }

        const geometry = targetGeometry(target);
        if (!geometry)
            return;

        refreshClientAreaForClient(client);
        Utils.log("Moving client " + client.resourceClass.toString() + " to target " + target.id + " with geometry " + JSON.stringify(geometry));
        clearClientsOverlappingTarget(client, target);
        saveClientTargetProperties(client, target);
        client.magnetileFreeMove = false;
        client.setMaximize(false, false);
        client.frameGeometry = geometry;
    }

    function freeClient(client) {
        if (!checkFilter(client))
            return;

        client.zone = -1;
        client.layout = -1;
        client.desktop = Workspace.currentDesktop;
        client.activity = Workspace.currentActivity;
        client.magnetileFreeMove = true;
        client.magnetileTiled = false;
        client.magnetileResizeSnapshot = null;
        clearClientTargetProperties(client);
    }

    function toggleFreeClient(client) {
        if (!checkFilter(client))
            return false;

        if (client.magnetileFreeMove === true) {
            client.magnetileFreeMove = false;
            return false;
        }

        freeClient(client);
        return true;
    }

    function saveClientProperties(client, zone) {
        Utils.log("Saving geometry for client " + client.resourceClass.toString());
        // save current geometry
        if (config.rememberWindowGeometries) {
            const geometry = {
                "x": client.frameGeometry.x,
                "y": client.frameGeometry.y,
                "width": client.frameGeometry.width,
                "height": client.frameGeometry.height
            };
            if (zone != -1) {
                if (client.zone == -1)
                    client.oldGeometry = geometry;

            }
        }
        // save zone
        client.zone = zone;
        client.layout = currentLayout;
        client.desktop = Workspace.currentDesktop;
        client.activity = Workspace.currentActivity;
        client.magnetileTiled = zone !== -1;
        if (zone === -1)
            clearClientTargetProperties(client);
        else {
            client.zones = [zone];
            client.magnetileMergedZone = "";
        }
    }

    function saveClientTargetProperties(client, target) {
        if (!client || !target)
            return;

        saveClientProperties(client, target.zone);
        client.layout = target.layout;
        client.zones = normalizeZoneList(target.layout, target.zones);
        client.magnetileMergedZone = target.type === "merge" ? target.id : "";
        client.magnetileTiled = true;
    }

    function clearClientsOverlappingTarget(activeClient, target) {
        const targetZones = normalizeZoneList(target.layout, target.zones);
        if (targetZones.length === 0)
            return;

        const output = target.output || clientOutput(activeClient);
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client === activeClient || !checkFilter(client) || client.minimized)
                continue;

            if (!clientInCurrentScope(client, output, Workspace.currentDesktop, Workspace.currentActivity))
                continue;

            if (client.layout !== target.layout)
                continue;

            if (!zonesOverlap(clientZones(client), targetZones))
                continue;

            client.zone = -1;
            client.layout = -1;
            client.desktop = Workspace.currentDesktop;
            client.activity = Workspace.currentActivity;
            client.magnetileTiled = false;
            client.magnetileResizeSnapshot = null;
            clearClientTargetProperties(client);
        }
    }

    function moveClientToClosestZone(client) {
        if (!checkFilter(client))
            return null;

        if (!canMutateWindowGeometry(client)) {
            Utils.log("Skipping snap while output geometry is not stable");
            return null;
        }

        Utils.log("Moving client " + client.resourceClass.toString() + " to closest zone");
        refreshClientAreaForClient(client);
        const centerPointOfClient = {
            "x": client.frameGeometry.x + (client.frameGeometry.width / 2),
            "y": client.frameGeometry.y + (client.frameGeometry.height / 2)
        };
        const targets = effectiveZoneTargets(currentLayout, clientOutput(client), Workspace.currentDesktop, Workspace.currentActivity);
        let closestTarget = null;
        let closestDistance = Infinity;
        for (let i = 0; i < targets.length; i++) {
            const target = targets[i];
            const geometry = targetGeometry(target);
            if (!geometry)
                continue;

            const zoneCenter = {
                "x": geometry.x + geometry.width / 2,
                "y": geometry.y + geometry.height / 2
            };
            const distance = Math.sqrt(Math.pow(centerPointOfClient.x - zoneCenter.x, 2) + Math.pow(centerPointOfClient.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                closestTarget = target;
                closestDistance = distance;
            }
        }
        if (closestTarget && (client.zone !== closestTarget.zone || client.layout !== currentLayout || client.magnetileMergedZone !== (closestTarget.type === "merge" ? closestTarget.id : "")))
            moveClientToTarget(client, closestTarget);

        return closestTarget ? closestTarget.zone : null;
    }

    function findClientSpecularZone(client, isVerticalAxis = false) {
        if (!checkFilter(client))
            return null;

        refreshClientAreaForClient(client);
        const centerPointOfClient = {
            "x": client.frameGeometry.x + (client.frameGeometry.width / 2),
            "y": client.frameGeometry.y + (client.frameGeometry.height / 2)
        };
        const zones = config.layouts[currentLayout].zones;
        let currentZoneIndex = null;
        let closestDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            let zoneCenter = {
                "x": (zone.x + zone.width / 2) / 100 * clientArea.width + clientArea.x,
                "y": (zone.y + zone.height / 2) / 100 * clientArea.height + clientArea.y
            };
            const distance = Math.sqrt(Math.pow(centerPointOfClient.x - zoneCenter.x, 2) + Math.pow(centerPointOfClient.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                currentZoneIndex = i;
                closestDistance = distance;
            }
        }
        if (currentZoneIndex === null)
            return null;

        const currentZone = zones[currentZoneIndex];
        const currentZoneCenter = {
            "x": currentZone.x + currentZone.width / 2,
            "y": currentZone.y + currentZone.height / 2
        };
        let specularZoneIndex = null;
        let minDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            if (i === currentZoneIndex)
                continue;

            const zone = zones[i];
            const zoneCenter = {
                "x": zone.x + zone.width / 2,
                "y": zone.y + zone.height / 2
            };
            let isSpecular = false;
            if (isVerticalAxis)
                isSpecular = Math.abs(zoneCenter.x - currentZoneCenter.x) < 5 && Math.abs((zoneCenter.y - 50) - (50 - currentZoneCenter.y)) < 5;
            else
                isSpecular = Math.abs(zoneCenter.y - currentZoneCenter.y) < 5 && Math.abs((zoneCenter.x - 50) - (50 - currentZoneCenter.x)) < 5;
            if (isSpecular) {
                const specularPoint = {
                    "x": !isVerticalAxis ? (100 - currentZoneCenter.x) : currentZoneCenter.x,
                    "y": isVerticalAxis ? (100 - currentZoneCenter.y) : currentZoneCenter.y
                };
                const distance = Math.sqrt(Math.pow(zoneCenter.x - specularPoint.x, 2) + Math.pow(zoneCenter.y - specularPoint.y, 2));
                if (distance < minDistance) {
                    specularZoneIndex = i;
                    minDistance = distance;
                }
            }
        }
        return specularZoneIndex !== null ? specularZoneIndex : currentZoneIndex;
    }

    function moveAllClientsToClosestZone() {
        if (!canMutateWindowGeometry(null)) {
            Utils.log("Skipping snap-all while output geometry is not stable");
            return 0;
        }

        Utils.log("Moving all clients to closest zone");
        let count = 0;
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.move)
                continue;

            moveClientToClosestZone(client) && count++;
        }
        Utils.log("Moved " + count + " clients to closest zone");
        return count;
    }

    function handleOutputGeometryChanged(reason) {
        if (disposing)
            return;

        outputsSettling = true;
        resizedZoneGeometries = new Object();
        mergedZones = new Object();
        hideDialogSurface(debugDialog);
        hideDialogSurface(mainDialog);
        zoneSelector.expanded = false;
        zoneSelector.near = false;
        highlightedZone = -1;
        highlightedTarget = null;
        selectingMergedZones = false;
        mergedZoneSelectionArmed = false;
        pendingMergeZones = [];
        refreshClientArea(activeScreen || Workspace.activeScreen);
        outputSettleTimer.restart();
        Utils.log("Output geometry changed: " + reason);
    }

    function moveClientToNeighbour(client, direction) {
        if (!checkFilter(client))
            return null;

        Utils.log("Moving client " + client.resourceClass.toString() + " to neighbour " + direction);
        refreshClientAreaForClient(client);
        const zones = config.layouts[currentLayout].zones;
        const currentZoneIndex = recoverClientZone(client, currentLayout, true);
        if (currentZoneIndex === -1)
            return null;

        const currentZone = zones[client.zone];
        let targetZoneIndex = -1;
        let minDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            if (i === client.zone)
                continue;

            const zone = zones[i];
            let isNeighbour = false;
            let distance = Infinity;
            switch (direction) {
            case "left":
                if (zone.x + zone.width <= currentZone.x && zone.y < currentZone.y + currentZone.height && zone.y + zone.height > currentZone.y) {
                    isNeighbour = true;
                    distance = currentZone.x - (zone.x + zone.width);
                }
                break;
            case "right":
                if (zone.x >= currentZone.x + currentZone.width && zone.y < currentZone.y + currentZone.height && zone.y + zone.height > currentZone.y) {
                    isNeighbour = true;
                    distance = zone.x - (currentZone.x + currentZone.width);
                }
                break;
            case "up":
                if (zone.y + zone.height <= currentZone.y && zone.x < currentZone.x + currentZone.width && zone.x + zone.width > currentZone.x) {
                    isNeighbour = true;
                    distance = currentZone.y - (zone.y + zone.height);
                }
                break;
            case "down":
                if (zone.y >= currentZone.y + currentZone.height && zone.x < currentZone.x + currentZone.width && zone.x + zone.width > currentZone.x) {
                    isNeighbour = true;
                    distance = zone.y - (currentZone.y + currentZone.height);
                }
                break;
            }
            if (isNeighbour && distance < minDistance) {
                minDistance = distance;
                targetZoneIndex = i;
            }
        }
        if (targetZoneIndex !== -1) {
            moveClientToZone(client, targetZoneIndex);
        } else if (!config.trackLayoutPerScreen) {
            const toScreenMap = {
                "left": "slotWindowToPrevScreen",
                "right": "slotWindowToNextScreen",
                "up": "slotWindowToAboveScreen",
                "down": "slotWindowToBelowScreen"
            };
            if (Workspace[toScreenMap[direction]]) {
                const isVerticalAxis = direction === "up" || direction === "down";
                const specularZone = findClientSpecularZone(client, isVerticalAxis);
                Workspace[toScreenMap[direction]]();
                moveClientToZone(client, specularZone);
            }
        }
        return targetZoneIndex;
    }

    function getLayoutKey() {
        const parts = [];
        if (config.trackLayoutPerScreen) {
            parts.push(outputName(activeScreen || Workspace.activeScreen));
            parts.push(outputOrientation(activeScreen || Workspace.activeScreen));
        }

        if (config.trackLayoutPerDesktop)
            parts.push(Workspace.currentDesktop.id);

        return parts.join(':');
    }

    function getCurrentLayout() {
        if (config.trackLayoutPerScreen || config.trackLayoutPerDesktop) {
            const key = getLayoutKey();
            if (screenLayouts[key] === undefined)
                screenLayouts[key] = config.trackLayoutPerScreen ? configuredLayoutForOutput(activeScreen || Workspace.activeScreen) : 0;

            return clampLayoutIndex(screenLayouts[key]);
        }
        return currentLayout;
    }

    function setCurrentLayout(layout) {
        if (config.trackLayoutPerScreen || config.trackLayoutPerDesktop)
            screenLayouts[getLayoutKey()] = clampLayoutIndex(layout);

        currentLayout = clampLayoutIndex(layout);
    }

    function osdLayoutName() {
        const name = config.layouts[currentLayout].name;
        const parts = [];
        if (config.trackLayoutPerScreen)
            parts.push(outputName(activeScreen || Workspace.activeScreen));

        if (config.trackLayoutPerDesktop)
            parts.push(Workspace.currentDesktop.name);

        if (parts.length > 0)
            return `${name} (${parts.join(' / ')})`;

        return name;
    }

    function osdLayoutSelection() {
        return `Layout ${currentLayout + 1}: ${osdLayoutName()}`;
    }

    function checkFilter(client) {
        // filter out abnormal windows like docks, panels, etc...
        if (!client)
            return false;

        if (isProtectedCaptureClient(client))
            return false;

        if (!client.normalWindow)
            return false;

        if (client.popupWindow)
            return false;

        if (client.skipTaskbar)
            return false;

        // read filter from config and check if the client's resource class matches the filter
        const filter = config.filterList.split(/\r?\n/);
        if (config.filterList.length > 0) {
            if (config.filterMode == 0)
                return filter.includes(clientResourceClass(client));

            if (config.filterMode == 1)
                return !filter.includes(clientResourceClass(client));

        }
        return true;
    }

    function tiledClientsForResize(client, layout, output, desktop, activity) {
        const clients = [];
        const skipped = [];
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const window = Workspace.stackingOrder[i];
            if (!checkFilter(window)) {
                skipped.push(clientDebugName(window) + ": filtered");
                continue;
            }

            if (window === client)
                continue;

            if (clientOutput(window) !== output) {
                skipped.push(clientDebugName(window) + ": different output");
                continue;
            }

            if (!sameDesktop(window, desktop)) {
                skipped.push(clientDebugName(window) + ": different desktop");
                continue;
            }

            if (clientActivity(window) !== activity) {
                skipped.push(clientDebugName(window) + ": different activity");
                continue;
            }

            if (matchResizeZoneInLayout(window, layout) === -1 || window.layout !== layout) {
                skipped.push(clientDebugName(window) + ": no layout zone");
                continue;
            }

            clients.push(window);
        }
        resizeDebugInfo.skipped = skipped;
        return clients;
    }

    function resizeZoneStacks(snapshots) {
        const stacks = {};
        for (let i = 0; i < snapshots.length; i++) {
            const item = snapshots[i];
            const key = "z" + (item.zone + 1);
            if (!stacks[key])
                stacks[key] = [];

            stacks[key].push(clientStackLabel(item.client));
        }
        return stacks;
    }

    function snapshotResizeGroup(client) {
        let layout = validLayoutIndex(client.layout) ? client.layout : currentLayout;
        if (matchResizeZoneInLayout(client, layout) === -1)
            return null;

        if (client.zone === undefined || client.zone === -1 || !validLayoutIndex(layout))
            return null;

        layout = clampLayoutIndex(layout);
        const output = clientOutput(client);
        const desktop = Workspace.currentDesktop;
        const activity = Workspace.currentActivity;
        const zoneGeometries = snapshotZoneGeometries(layout, output);
        const windows = tiledClientsForResize(client, layout, output, desktop, activity);
        const snapshots = [];
        for (let i = 0; i < windows.length; i++) {
            const window = windows[i];
            snapshots.push({
                "client": window,
                "zone": window.zone,
                "layout": window.layout,
                "geometry": Qt.rect(window.frameGeometry.x, window.frameGeometry.y, window.frameGeometry.width, window.frameGeometry.height),
                "logicalGeometry": zoneGeometry(layout, window.zone, output)
            });
        }

        const participantNames = snapshots.map(item => clientStackLabel(item.client) + " z" + (item.zone + 1));
        const zoneStacks = resizeZoneStacks(snapshots);
        resizeDebugInfo = {
            "active": true,
            "client": clientDebugName(client),
            "layout": layout,
            "zone": client.zone,
            "output": outputName(output),
            "desktop": desktop && desktop.name ? desktop.name : "",
            "activity": activity || "",
            "participants": participantNames,
            "participantCount": snapshots.length,
            "zoneStacks": zoneStacks,
            "skipped": resizeDebugInfo.skipped || [],
            "appliedCount": 0,
            "lastApplied": false
        };
        Utils.log("Resize group: " + resizeDebugInfo.client + " layout " + (layout + 1) + " zone " + (client.zone + 1) + " on " + (resizeDebugInfo.output || "<output>") + "; participants: " + (participantNames.length ? participantNames.join(", ") : "none"));
        if (resizeDebugInfo.skipped.length > 0)
            Utils.log("Resize skipped: " + resizeDebugInfo.skipped.join("; "));

        return {
            "zone": client.zone,
            "layout": layout,
            "output": output,
            "desktop": desktop,
            "activity": activity,
            "geometry": Qt.rect(client.frameGeometry.x, client.frameGeometry.y, client.frameGeometry.width, client.frameGeometry.height),
            "logicalGeometry": zoneGeometry(layout, client.zone, output),
            "zoneGeometries": zoneGeometries,
            "windows": snapshots
        };
    }

    function updateRuntimeLayoutGeometry(snapshot, finalGeometry) {
        if (!snapshot || !snapshot.zoneGeometries || snapshot.zone === undefined || snapshot.zone === -1)
            return;

        const layoutIndex = clampLayoutIndex(snapshot.layout);
        const zones = config.layouts[layoutIndex].zones;
        const oldTarget = rectEdges(snapshot.zoneGeometries[snapshot.zone] || snapshot.logicalGeometry || snapshot.geometry);
        const newTarget = rectEdges(finalGeometry);
        const resizeTolerance = resizeGapTolerance(config.layouts[layoutIndex]);
        const minSize = Math.max(1, geometryTolerance);
        const changed = {
            "left": Math.abs(newTarget.left - oldTarget.left) > geometryTolerance,
            "right": Math.abs(newTarget.right - oldTarget.right) > geometryTolerance,
            "top": Math.abs(newTarget.top - oldTarget.top) > geometryTolerance,
            "bottom": Math.abs(newTarget.bottom - oldTarget.bottom) > geometryTolerance
        };

        clearRuntimeLayoutGeometry(layoutIndex, snapshot.output, snapshot.desktop, snapshot.activity);

        for (let i = 0; i < zones.length; i++) {
            const oldZoneGeometry = snapshot.zoneGeometries[i];
            if (!oldZoneGeometry)
                continue;

            if (i === snapshot.zone) {
                storeRuntimeZoneGeometry(layoutIndex, i, snapshot.output, snapshot.desktop, snapshot.activity, finalGeometry);
                continue;
            }

            const oldZone = rectEdges(oldZoneGeometry);
            let nextLeft = oldZone.left;
            let nextTop = oldZone.top;
            let nextRight = oldZone.right;
            let nextBottom = oldZone.bottom;
            const overlapsY = rangesOverlap(oldTarget.top, oldTarget.bottom, oldZone.top, oldZone.bottom);
            const overlapsX = rangesOverlap(oldTarget.left, oldTarget.right, oldZone.left, oldZone.right);
            const rightGap = oldZone.left - oldTarget.right;
            const leftGap = oldTarget.left - oldZone.right;
            const bottomGap = oldZone.top - oldTarget.bottom;
            const topGap = oldTarget.top - oldZone.bottom;
            const rightAdjacent = isResizeAdjacent(rightGap, resizeTolerance) && overlapsY;
            const leftAdjacent = isResizeAdjacent(leftGap, resizeTolerance) && overlapsY;
            const bottomAdjacent = isResizeAdjacent(bottomGap, resizeTolerance) && overlapsX;
            const topAdjacent = isResizeAdjacent(topGap, resizeTolerance) && overlapsX;
            const sameColumn = edgesAligned(oldZone.left, oldTarget.left) && edgesAligned(oldZone.right, oldTarget.right);
            const sameRow = edgesAligned(oldZone.top, oldTarget.top) && edgesAligned(oldZone.bottom, oldTarget.bottom);

            if (changed.right && rightAdjacent)
                nextLeft = newTarget.right + preservedResizeGap(rightGap);
            else if (changed.right && sameColumn)
                nextRight = newTarget.right;

            if (changed.left && leftAdjacent)
                nextRight = newTarget.left - preservedResizeGap(leftGap);
            else if (changed.left && sameColumn)
                nextLeft = newTarget.left;

            if (changed.bottom && bottomAdjacent)
                nextTop = newTarget.bottom + preservedResizeGap(bottomGap);
            else if (changed.bottom && sameRow)
                nextBottom = newTarget.bottom;

            if (changed.top && topAdjacent)
                nextBottom = newTarget.top - preservedResizeGap(topGap);
            else if (changed.top && sameRow)
                nextTop = newTarget.top;

            const nextWidth = Math.round(nextRight - nextLeft);
            const nextHeight = Math.round(nextBottom - nextTop);
            if (nextWidth < minSize || nextHeight < minSize)
                storeRuntimeZoneGeometry(layoutIndex, i, snapshot.output, snapshot.desktop, snapshot.activity, oldZoneGeometry);
            else
                storeRuntimeZoneGeometry(layoutIndex, i, snapshot.output, snapshot.desktop, snapshot.activity, roundedRect(nextLeft, nextTop, nextWidth, nextHeight));

        }
    }

    function connectedResize(client) {
        if (!canMutateWindowGeometry(client))
            return false;

        const snapshot = client.magnetileResizeSnapshot;
        if (!snapshot || snapshot.zone === undefined || snapshot.zone === -1)
            return false;

        const oldGeometry = rectEdges(snapshot.geometry);
        const oldLogicalGeometry = rectEdges(snapshot.logicalGeometry || snapshot.geometry);
        let newGeometry = rectEdges(client.frameGeometry);
        const resizeTolerance = resizeGapTolerance(config.layouts[clampLayoutIndex(snapshot.layout)]);
        const minSize = Math.max(1, geometryTolerance);
        const changed = {
            "left": Math.abs(newGeometry.left - oldGeometry.left) > geometryTolerance,
            "right": Math.abs(newGeometry.right - oldGeometry.right) > geometryTolerance,
            "top": Math.abs(newGeometry.top - oldGeometry.top) > geometryTolerance,
            "bottom": Math.abs(newGeometry.bottom - oldGeometry.bottom) > geometryTolerance
        };

        if (!changed.left && !changed.right && !changed.top && !changed.bottom)
            return false;

        let applied = false;
        let constrainedLeft = newGeometry.left;
        let constrainedTop = newGeometry.top;
        let constrainedRight = newGeometry.right;
        let constrainedBottom = newGeometry.bottom;
        for (let i = 0; i < snapshot.windows.length; i++) {
            const item = snapshot.windows[i];
            const oldOther = rectEdges(item.geometry);
            const oldOtherLogical = rectEdges(item.logicalGeometry || item.geometry);
            const overlapsOldY = rangesOverlap(oldGeometry.top, oldGeometry.bottom, oldOther.top, oldOther.bottom);
            const overlapsOldX = rangesOverlap(oldGeometry.left, oldGeometry.right, oldOther.left, oldOther.right);
            const overlapsLogicalY = rangesOverlap(oldLogicalGeometry.top, oldLogicalGeometry.bottom, oldOtherLogical.top, oldOtherLogical.bottom);
            const overlapsLogicalX = rangesOverlap(oldLogicalGeometry.left, oldLogicalGeometry.right, oldOtherLogical.left, oldOtherLogical.right);
            const rightGap = oldOther.left - oldGeometry.right;
            const leftGap = oldGeometry.left - oldOther.right;
            const bottomGap = oldOther.top - oldGeometry.bottom;
            const topGap = oldGeometry.top - oldOther.bottom;
            const logicalRightGap = oldOtherLogical.left - oldLogicalGeometry.right;
            const logicalLeftGap = oldLogicalGeometry.left - oldOtherLogical.right;
            const logicalBottomGap = oldOtherLogical.top - oldLogicalGeometry.bottom;
            const logicalTopGap = oldLogicalGeometry.top - oldOtherLogical.bottom;
            const rightAdjacent = (isResizeAdjacent(rightGap, resizeTolerance) && overlapsOldY) || (isResizeAdjacent(logicalRightGap, resizeTolerance) && overlapsLogicalY);
            const leftAdjacent = (isResizeAdjacent(leftGap, resizeTolerance) && overlapsOldY) || (isResizeAdjacent(logicalLeftGap, resizeTolerance) && overlapsLogicalY);
            const bottomAdjacent = (isResizeAdjacent(bottomGap, resizeTolerance) && overlapsOldX) || (isResizeAdjacent(logicalBottomGap, resizeTolerance) && overlapsLogicalX);
            const topAdjacent = (isResizeAdjacent(topGap, resizeTolerance) && overlapsOldX) || (isResizeAdjacent(logicalTopGap, resizeTolerance) && overlapsLogicalX);
            const preservedRightGap = isResizeAdjacent(rightGap, resizeTolerance) && overlapsOldY ? preservedResizeGap(rightGap) : preservedResizeGap(logicalRightGap);
            const preservedLeftGap = isResizeAdjacent(leftGap, resizeTolerance) && overlapsOldY ? preservedResizeGap(leftGap) : preservedResizeGap(logicalLeftGap);
            const preservedBottomGap = isResizeAdjacent(bottomGap, resizeTolerance) && overlapsOldX ? preservedResizeGap(bottomGap) : preservedResizeGap(logicalBottomGap);
            const preservedTopGap = isResizeAdjacent(topGap, resizeTolerance) && overlapsOldX ? preservedResizeGap(topGap) : preservedResizeGap(logicalTopGap);

            if (changed.right && rightAdjacent)
                constrainedRight = Math.min(constrainedRight, oldOther.right - preservedRightGap - minSize);

            if (changed.left && leftAdjacent)
                constrainedLeft = Math.max(constrainedLeft, oldOther.left + preservedLeftGap + minSize);

            if (changed.bottom && bottomAdjacent)
                constrainedBottom = Math.min(constrainedBottom, oldOther.bottom - preservedBottomGap - minSize);

            if (changed.top && topAdjacent)
                constrainedTop = Math.max(constrainedTop, oldOther.top + preservedTopGap + minSize);
        }

        const constrainedWidth = Math.round(constrainedRight - constrainedLeft);
        const constrainedHeight = Math.round(constrainedBottom - constrainedTop);
        if (constrainedWidth >= minSize && constrainedHeight >= minSize) {
            newGeometry = rectEdges(roundedRect(constrainedLeft, constrainedTop, constrainedWidth, constrainedHeight));
            if (!rectsClose(client.frameGeometry, Qt.rect(newGeometry.left, newGeometry.top, newGeometry.width, newGeometry.height))) {
                client.setMaximize(false, false);
                client.frameGeometry = Qt.rect(newGeometry.left, newGeometry.top, newGeometry.width, newGeometry.height);
                applied = true;
                resizeDebugInfo.appliedCount = (resizeDebugInfo.appliedCount || 0) + 1;
            }
        }

        for (let i = 0; i < snapshot.windows.length; i++) {
            const item = snapshot.windows[i];
            const window = item.client;
            if (!checkFilter(window) || window.minimized)
                continue;

            const oldOther = rectEdges(item.geometry);
            const oldOtherLogical = rectEdges(item.logicalGeometry || item.geometry);
            let nextLeft = oldOther.left;
            let nextTop = oldOther.top;
            let nextRight = oldOther.right;
            let nextBottom = oldOther.bottom;
            const overlapsOldY = rangesOverlap(oldGeometry.top, oldGeometry.bottom, oldOther.top, oldOther.bottom);
            const overlapsOldX = rangesOverlap(oldGeometry.left, oldGeometry.right, oldOther.left, oldOther.right);
            const overlapsLogicalY = rangesOverlap(oldLogicalGeometry.top, oldLogicalGeometry.bottom, oldOtherLogical.top, oldOtherLogical.bottom);
            const overlapsLogicalX = rangesOverlap(oldLogicalGeometry.left, oldLogicalGeometry.right, oldOtherLogical.left, oldOtherLogical.right);

            const rightGap = oldOther.left - oldGeometry.right;
            const leftGap = oldGeometry.left - oldOther.right;
            const bottomGap = oldOther.top - oldGeometry.bottom;
            const topGap = oldGeometry.top - oldOther.bottom;
            const logicalRightGap = oldOtherLogical.left - oldLogicalGeometry.right;
            const logicalLeftGap = oldLogicalGeometry.left - oldOtherLogical.right;
            const logicalBottomGap = oldOtherLogical.top - oldLogicalGeometry.bottom;
            const logicalTopGap = oldLogicalGeometry.top - oldOtherLogical.bottom;
            const rightAdjacent = (isResizeAdjacent(rightGap, resizeTolerance) && overlapsOldY) || (isResizeAdjacent(logicalRightGap, resizeTolerance) && overlapsLogicalY);
            const leftAdjacent = (isResizeAdjacent(leftGap, resizeTolerance) && overlapsOldY) || (isResizeAdjacent(logicalLeftGap, resizeTolerance) && overlapsLogicalY);
            const bottomAdjacent = (isResizeAdjacent(bottomGap, resizeTolerance) && overlapsOldX) || (isResizeAdjacent(logicalBottomGap, resizeTolerance) && overlapsLogicalX);
            const topAdjacent = (isResizeAdjacent(topGap, resizeTolerance) && overlapsOldX) || (isResizeAdjacent(logicalTopGap, resizeTolerance) && overlapsLogicalX);
            const sameLogicalColumn = edgesAligned(oldOtherLogical.left, oldLogicalGeometry.left) && edgesAligned(oldOtherLogical.right, oldLogicalGeometry.right);
            const sameLogicalRow = edgesAligned(oldOtherLogical.top, oldLogicalGeometry.top) && edgesAligned(oldOtherLogical.bottom, oldLogicalGeometry.bottom);
            const preservedRightGap = isResizeAdjacent(rightGap, resizeTolerance) && overlapsOldY ? preservedResizeGap(rightGap) : preservedResizeGap(logicalRightGap);
            const preservedLeftGap = isResizeAdjacent(leftGap, resizeTolerance) && overlapsOldY ? preservedResizeGap(leftGap) : preservedResizeGap(logicalLeftGap);
            const preservedBottomGap = isResizeAdjacent(bottomGap, resizeTolerance) && overlapsOldX ? preservedResizeGap(bottomGap) : preservedResizeGap(logicalBottomGap);
            const preservedTopGap = isResizeAdjacent(topGap, resizeTolerance) && overlapsOldX ? preservedResizeGap(topGap) : preservedResizeGap(logicalTopGap);

            if (changed.right && rightAdjacent)
                nextLeft = newGeometry.right + preservedRightGap;
            else if (changed.right && sameLogicalColumn)
                nextRight = newGeometry.right;

            if (changed.left && leftAdjacent)
                nextRight = newGeometry.left - preservedLeftGap;
            else if (changed.left && sameLogicalColumn)
                nextLeft = newGeometry.left;

            if (changed.bottom && bottomAdjacent)
                nextTop = newGeometry.bottom + preservedBottomGap;
            else if (changed.bottom && sameLogicalRow)
                nextBottom = newGeometry.bottom;

            if (changed.top && topAdjacent)
                nextBottom = newGeometry.top - preservedTopGap;
            else if (changed.top && sameLogicalRow)
                nextTop = newGeometry.top;

            const nextWidth = Math.round(nextRight - nextLeft);
            const nextHeight = Math.round(nextBottom - nextTop);
            if (nextWidth < minSize || nextHeight < minSize)
                continue;

            const nextGeometry = roundedRect(nextLeft, nextTop, nextWidth, nextHeight);
            if (rectsClose(window.frameGeometry, nextGeometry))
                continue;

            window.setMaximize(false, false);
            window.frameGeometry = nextGeometry;
            window.zone = item.zone;
            window.layout = item.layout;
            window.desktop = snapshot.desktop;
            window.activity = snapshot.activity;
            window.magnetileTiled = true;
            applied = true;
            resizeDebugInfo.appliedCount = (resizeDebugInfo.appliedCount || 0) + 1;
        }

        client.zone = snapshot.zone;
        client.layout = snapshot.layout;
        client.desktop = snapshot.desktop;
        client.activity = snapshot.activity;
        client.magnetileTiled = true;
        updateRuntimeLayoutGeometry(snapshot, client.frameGeometry);
        resizeDebugInfo.lastApplied = applied;
        resizeDebugInfo = Object.assign({}, resizeDebugInfo);
        return applied;
    }

    function disconnectSignals(client) {
        const handlers = client && client.magnetileSignalHandlers;
        if (!handlers)
            return;

        try {
            if (handlers.started)
                client.onInteractiveMoveResizeStarted.disconnect(handlers.started);
            if (handlers.stepped)
                client.onInteractiveMoveResizeStepped.disconnect(handlers.stepped);
            if (handlers.finished)
                client.onInteractiveMoveResizeFinished.disconnect(handlers.finished);
            if (handlers.fullscreen)
                client.onFullScreenChanged.disconnect(handlers.fullscreen);
        } catch (error) {
            Utils.log("Signal disconnect skipped: " + error);
        }
        client.magnetileSignalHandlers = null;
        if (client.magnetileSignalToken === signalToken)
            client.magnetileSignalToken = "";
    }

    function connectSignals(client) {
        if (!checkFilter(client))
            return ;

        disconnectSignals(client);
        const connectedToken = signalToken;
        function signalIsCurrent() {
            return client && client.magnetileSignalToken === connectedToken;
        }

        function onInteractiveMoveResizeStarted() {
            if (!signalIsCurrent())
                return;

            if (!canMutateWindowGeometry(client))
                return;

            Utils.log("Interactive move/resize started for client " + client.resourceClass.toString());
            if (client.resizeable && checkFilter(client)) {
                if (client.move && checkFilter(client)) {
                    refreshClientAreaForClient(client);
                    cachedClientArea = clientArea;
                    if (config.fadeWindowsWhileMoving) {
                        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                            const client = Workspace.stackingOrder[i];
                            client.previousOpacity = client.opacity;
                            if (client.move || !client.normalWindow)
                                continue;

                            client.opacity = 0.5;
                        }
                    }
                    if (config.rememberWindowGeometries && validZoneIndex(client.layout, client.zone)) {
                        if (client.oldGeometry) {
                            const geometry = client.oldGeometry;
                            const zone = config.layouts[client.layout].zones[client.zone];
                            const zoneCenterX = (zone.x + zone.width / 2) / 100 * cachedClientArea.width + cachedClientArea.x;
                            const zoneX = ((zone.x / 100) * cachedClientArea.width + cachedClientArea.x);
                            const newGeometry = Qt.rect(Math.round(Workspace.cursorPos.x - geometry.width / 2), Math.round(client.frameGeometry.y), Math.round(geometry.width), Math.round(geometry.height));
                            client.frameGeometry = newGeometry;
                        }
                    }
                    moving = true;
                    moved = false;
                    resizing = false;
                    freeMoving = client.magnetileFreeMove === true;
                    highlightedTarget = null;
                    selectingMergedZones = mergedZoneSelectionArmed;
                    mergedZoneSelectionArmed = false;
                    pendingMergeZones = [];
                    if (selectingMergedZones)
                        Utils.osd("Multi-zone selection started");

                    Utils.log("Move start " + client.resourceClass.toString());
                    if (freeMoving)
                        mainDialog.hide();
                    else
                        mainDialog.show();
                }
                if (client.resize) {
                    refreshClientAreaForClient(client);
                    if (client.zone === undefined || client.zone === -1)
                        matchZone(client);

                    resizeDebugInfo = new Object();
                    client.magnetileResizeSnapshot = snapshotResizeGroup(client);
                    moving = false;
                    moved = false;
                    resizing = true;
                    freeMoving = false;
                    updateDebugDialog();
                }
            }
        }

        function onInteractiveMoveResizeStepped() {
            if (!signalIsCurrent())
                return;

            if (client.resizeable) {
                if (moving && checkFilter(client))
                    moved = true;

                if (resizing && checkFilter(client) && client.magnetileResizeSnapshot)
                    connectedResize(client);

            }
        }

        function onInteractiveMoveResizeFinished() {
            if (!signalIsCurrent())
                return;

            Utils.log("Interactive move/resize finished for client " + client.resourceClass.toString());
            if (config.fadeWindowsWhileMoving) {
                for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                    const client = Workspace.stackingOrder[i];
                    client.opacity = client.previousOpacity || 1;
                }
            }
            if (moving) {
                Utils.log("Move end " + client.resourceClass.toString());
                if (moved) {
                    if (freeMoving) {
                        freeClient(client);
                    } else if (mainDialog.visible) {
                        const target = selectingMergedZones && pendingMergeZones.length > 1 ? mergeZones(currentLayout, pendingMergeZones, clientOutput(client), Workspace.currentDesktop, Workspace.currentActivity) : highlightedTarget;
                        if (target)
                            moveClientToTarget(client, target);
                        else if (highlightedTarget)
                            moveClientToTarget(client, highlightedTarget);
                        else
                            moveClientToZone(client, highlightedZone);
                    } else {
                        saveClientProperties(client, -1);
                    }
                }
                mainDialog.hide();
            } else if (resizing) {
                connectedResize(client);
                if (!client.magnetileResizeSnapshot)
                    matchZone(client);

                Utils.log("Resizing end: Connected resize for client " + client.resourceClass.toString() + " at layout.zone " + client.layout + " " + client.zone);
                client.magnetileResizeSnapshot = null;
                resizeDebugInfo.active = false;
                resizeDebugInfo = Object.assign({}, resizeDebugInfo);
            }
            moving = false;
            moved = false;
            resizing = false;
            freeMoving = false;
            updateDebugDialog();
        }

        // fix from https://github.com/gerritdevriese/kzones/pull/25
        function onFullScreenChanged() {
            if (!signalIsCurrent())
                return;

            if (!canMutateWindowGeometry(client))
                return;

            Utils.log("Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + client.fullScreen + ")");
            if (client.fullScreen == true) {
                recoverClientZone(client, validLayoutIndex(client.layout) ? client.layout : currentLayout, true);
                Utils.log("onFullscreenChanged: Client zone: " + client.zone + " layout: " + client.layout);
                if (validZoneIndex(client.layout, client.zone)) {
                    //check if fullscreen is enabled for layout or for zone
                    const layout = config.layouts[client.layout];
                    const zone = layout.zones[client.zone];
                    Utils.log("Layout.fullscreen: " + layout.fullscreen + " Zone.fullscreen: " + zone.fullscreen);
                    if (layout.fullscreen == true || zone.fullscreen == true) {
                        const target = clientZones(client).length > 1 ? mergeTargetFromZones(client.layout, clientZones(client), clientOutput(client), Workspace.currentDesktop, Workspace.currentActivity) : effectiveTargetForZone(client.layout, client.zone, clientOutput(client), Workspace.currentDesktop, Workspace.currentActivity);
                        const newGeometry = targetGeometry(target);
                        if (newGeometry) {
                            Utils.log("Fullscreen client " + client.resourceClass.toString() + " to zone " + client.zone + " with geometry " + JSON.stringify(newGeometry));
                            client.setMaximize(false, false);
                            client.frameGeometry = newGeometry;
                        }
                    }
                }
            }
            mainDialog.hide();
        }

        Utils.log("Connecting signals for client " + client.resourceClass.toString());
        client.magnetileSignalToken = connectedToken;
        client.magnetileSignalHandlers = {
            "started": onInteractiveMoveResizeStarted,
            "stepped": onInteractiveMoveResizeStepped,
            "finished": onInteractiveMoveResizeFinished,
            "fullscreen": onFullScreenChanged
        };
        client.onInteractiveMoveResizeStarted.connect(onInteractiveMoveResizeStarted);
        client.onInteractiveMoveResizeStepped.connect(onInteractiveMoveResizeStepped);
        client.onInteractiveMoveResizeFinished.connect(onInteractiveMoveResizeFinished);
        client.onFullScreenChanged.connect(onFullScreenChanged);
    }

    Component.onCompleted: {
        Utils.log("Loading script (" + Qt.resolvedUrl("./main.qml") + ")");
        Core.init(KWin, Workspace);
        Core.registerQMLComponent("root", root);
        Core.loadConfig();
        refreshClientArea();
        // match all clients to zones and connect signals
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            matchZone(Workspace.stackingOrder[i]);
            connectSignals(Workspace.stackingOrder[i]);
        }
        Utils.log("Everything loaded successfully");
    }

    Component.onDestruction: {
        disposing = true;
        try {
            for (let i = 0; i < Workspace.stackingOrder.length; i++)
                disconnectSignals(Workspace.stackingOrder[i]);
        } catch (error) {
            Utils.log("Workspace cleanup skipped: " + error);
        }

        hideDialogSurface(debugDialog);
        hideDialogSurface(mainDialog);
        Utils.log("Script disposed");
    }

    Timer {
        id: outputSettleTimer

        interval: 1200
        repeat: false
        onTriggered: {
            if (disposing)
                return;

            outputsSettling = false;
            refreshClientArea(activeScreen || Workspace.activeScreen);
            for (let i = 0; i < Workspace.stackingOrder.length; i++) {
                matchZone(Workspace.stackingOrder[i]);
                connectSignals(Workspace.stackingOrder[i]);
            }
            updateDebugDialog();
            Utils.log("Output geometry settled");
        }
    }

    PlasmaCore.Dialog {
        id: debugDialog

        title: "Magnetile Debug"
        location: PlasmaCore.Types.Desktop
        type: PlasmaCore.Dialog.OnScreenDisplay
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
        hideOnWindowDeactivate: false
        visible: false
        outputOnly: true
        opacity: 1
        x: clientArea.x || 0
        y: clientArea.y || 0
        width: 1
        height: 1

        Item {
            width: debugDialog.width
            height: debugDialog.height

            Components.Debug {
                info: debugInfo()
                config: root.config
            }
        }
    }

    PlasmaCore.Dialog {
        id: mainDialog

        function show() {
            refreshClientArea(activeScreen || Workspace.activeScreen);
            resizeDialogToClientArea(mainDialog);
            mainDialog.visible = true;
        }

        function hide() {
            hideDialogSurface(mainDialog);
            zoneSelector.expanded = false;
            zoneSelector.near = false;
            highlightedZone = -1;
            highlightedTarget = null;
            selectingMergedZones = false;
            pendingMergeZones = [];
            showZoneOverlay = config.zoneOverlayShowWhen == 0;
        }

        title: "Magnetile Overlay"
        location: PlasmaCore.Types.Desktop
        type: PlasmaCore.Dialog.OnScreenDisplay
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
        hideOnWindowDeactivate: true
        visible: false
        outputOnly: true
        opacity: 1
        x: clientArea.x || 0
        y: clientArea.y || 0
        width: 1
        height: 1

            Item {
                id: mainItem

                property alias repeaterLayout: repeaterLayout
                property var targetsByLayout: []

                width: mainDialog.width
                height: mainDialog.height

                Components.ColorHelper {
                    id: mainColorHelper
                }

                function refreshTargets() {
                    const nextTargets = [];
                    for (let i = 0; i < config.layouts.length; i++)
                        nextTargets.push(root.effectiveZoneTargets(i, root.activeScreen));

                    targetsByLayout = nextTargets;
                }

            // main polling timer
            Timer {
                id: timer

                triggeredOnStart: true
                interval: config.pollingRate
                running: mainDialog.visible
                repeat: true
                onTriggered: {
                    refreshClientArea();
                    resizeDialogToClientArea(mainDialog);
                    mainItem.refreshTargets();
                    let hoveringZone = -1;
                    let hoveringTarget = null;
                    // zone overlay
                    const currentZones = repeaterLayout.itemAt(currentLayout);
                    if (config.enableZoneOverlay && showZoneOverlay && !zoneSelector.expanded && currentZones)
                        currentZones.repeater.model.forEach((target, targetIndex) => {
                        const targetItem = currentZones.repeater.itemAt(targetIndex);
                        if (targetItem && Utils.isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, target.geometry)) {
                            hoveringZone = target.zone;
                            hoveringTarget = target;
                        }

                    });

                    // zone selector
                    if (config.enableZoneSelector) {
                        if (!zoneSelector.animating && zoneSelector.expanded) {
                            zoneSelector.repeater.model.forEach((layout, layoutIndex) => {
                                const layoutItem = zoneSelector.repeater.itemAt(layoutIndex);
                                layout.zones.forEach((zone, zoneIndex) => {
	                                    const zoneItem = layoutItem.children[zoneIndex];
	                                    if (Utils.isHovering(zoneItem)) {
	                                        hoveringZone = zoneIndex;
	                                        hoveringTarget = singleZoneTarget(layoutIndex, zoneIndex, activeScreen, Workspace.currentDesktop, Workspace.currentActivity);
	                                        setCurrentLayout(layoutIndex);
	                                    }
	                                });
                            });
                        }
                        // set zoneSelector expansion state
                        zoneSelector.expanded = Utils.isHovering(zoneSelector) && (Workspace.cursorPos.y - clientArea.y) >= 0;
                        // set zoneSelector near state
                        const triggerDistance = config.zoneSelectorTriggerDistance * 50 + 25;
                        zoneSelector.near = (Workspace.cursorPos.y - clientArea.y) < zoneSelector.y + zoneSelector.height + triggerDistance;
                    }
                    // edge snapping
                    if (config.enableEdgeSnapping) {
                        const triggerDistance = (config.edgeSnappingTriggerDistance + 1) * 10;
                        if (Workspace.cursorPos.x <= clientArea.x + triggerDistance || Workspace.cursorPos.x >= clientArea.x + clientArea.width - triggerDistance || Workspace.cursorPos.y <= clientArea.y + triggerDistance || Workspace.cursorPos.y >= clientArea.y + clientArea.height - triggerDistance) {
                            const padding = config.layouts[currentLayout].padding || 0;
                            const halfPadding = padding / 2;
	                            const targets = effectiveZoneTargets(currentLayout, activeScreen, Workspace.currentDesktop, Workspace.currentActivity);
	                            targets.forEach((target) => {
	                                const geometry = targetGeometry(target);
	                                if (!geometry)
	                                    return;

	                                let expandedZoneGeometry = {
	                                    "x": geometry.x - padding / 2,
	                                    "y": geometry.y - padding / 2,
                                    "width": geometry.width + padding,
                                    "height": geometry.height + padding
                                };
                                //adjust most left edge
                                if (expandedZoneGeometry.x <= clientArea.x + halfPadding) {
                                    expandedZoneGeometry.x = clientArea.x;
                                    expandedZoneGeometry.width += padding;
                                }
                                //adjust most top edge
                                if (expandedZoneGeometry.y <= clientArea.y + halfPadding) {
                                    expandedZoneGeometry.y = clientArea.y;
                                    expandedZoneGeometry.height += padding;
                                }
                                //adjust most right edge
                                if (expandedZoneGeometry.x + expandedZoneGeometry.width >= clientArea.x + clientArea.width - halfPadding)
                                    expandedZoneGeometry.width += halfPadding;

                                //adjust most bottom edge
                                if (expandedZoneGeometry.y + expandedZoneGeometry.height >= clientArea.y + clientArea.height - halfPadding)
                                    expandedZoneGeometry.height += halfPadding;

	                                // check if cursor is inside the zone geometry
	                                if (Utils.isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, expandedZoneGeometry)) {
	                                    hoveringZone = target.zone;
	                                    hoveringTarget = target;
	                                }

	                            });
	                        }
	                    }
	                    // if hovering zone changed from the last frame
	                    if (hoveringZone != highlightedZone || (hoveringTarget && highlightedTarget && hoveringTarget.id != highlightedTarget.id) || (hoveringTarget && !highlightedTarget) || (!hoveringTarget && highlightedTarget)) {
	                        Utils.log("Highlighting zone " + hoveringZone + " in layout " + currentLayout);
	                        highlightedZone = hoveringZone;
	                        highlightedTarget = hoveringTarget;
	                    }
                    if (selectingMergedZones && hoveringTarget)
                        addZonesToPendingMerge(hoveringTarget.zones);
		                }
		            }

            Item {
                x: 0
                y: 0
                width: clientArea.width || 0
                height: clientArea.height || 0
                clip: true

                Components.Debug {
                    info: debugInfo()
                    config: root.config
                }

                Repeater {
                    id: repeaterLayout

                    model: config.layouts

                    Components.Zones {
                        id: zones

                        config: root.config
                        currentLayout: root.currentLayout
                        highlightedZone: root.highlightedZone
                        highlightedTarget: root.highlightedTarget
                        layoutIndex: index
                        targets: mainItem.targetsByLayout[index] || []
                        visible: index == root.currentLayout
                    }

                }

                Components.Selector {
                    id: zoneSelector

                    config: root.config
                    currentLayout: root.currentLayout
                    highlightedZone: root.highlightedZone
                }

            }

        }

    }

    Components.Shortcuts {
        onCycleLayouts: {
            setCurrentLayout((currentLayout + 1) % config.layouts.length);
            highlightedZone = -1;
            Utils.osd(osdLayoutSelection());
        }
        onCycleLayoutsReversed: {
            setCurrentLayout((currentLayout - 1 + config.layouts.length) % config.layouts.length);
            highlightedZone = -1;
            Utils.osd(osdLayoutSelection());
        }
        onMoveActiveWindowToNextZone: {
            const client = Workspace.activeWindow;
            if (!client || !checkFilter(client))
                return;

            refreshClientAreaForClient(client);
            if (recoverClientZone(client, currentLayout, true) === -1)
                return;

            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone + 1) % zonesLength);
        }
        onMoveActiveWindowToPreviousZone: {
            const client = Workspace.activeWindow;
            if (!client || !checkFilter(client))
                return;

            refreshClientAreaForClient(client);
            if (recoverClientZone(client, currentLayout, true) === -1)
                return;

            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone - 1 + zonesLength) % zonesLength);
        }
        onToggleZoneOverlay: {
            if (!config.enableZoneOverlay)
                Utils.osd("Zone overlay is disabled");
            else if (moving)
                showZoneOverlay = !showZoneOverlay;
            else
                Utils.osd("The overlay can only be shown while moving a window");
        }
        onToggleMergedZoneSelection: {
            toggleMergedZoneSelection();
        }
        onSwitchToNextWindowInCurrentZone: {
            const client = Workspace.activeWindow;
            if (!client || !checkFilter(client))
                return;

            refreshClientAreaForClient(client);
            const zone = recoverClientZone(client, currentLayout, true);
            if (zone !== -1)
                switchWindowInZone(zone, currentLayout);
        }
        onSwitchToPreviousWindowInCurrentZone: {
            const client = Workspace.activeWindow;
            if (!client || !checkFilter(client))
                return;

            refreshClientAreaForClient(client);
            const zone = recoverClientZone(client, currentLayout, true);
            if (zone !== -1)
                switchWindowInZone(zone, currentLayout, true);
        }
        onMoveActiveWindowToZone: function(zone) {
            refreshClientAreaForClient(Workspace.activeWindow);
            moveClientToZone(Workspace.activeWindow, zone);
        }
        onActivateLayout: function(layout) {
            if (Workspace.activeWindow)
                refreshClientAreaForClient(Workspace.activeWindow);
            else
                refreshClientArea(activeScreen || Workspace.activeScreen);

            if (layout <= config.layouts.length - 1) {
                setCurrentLayout(layout);
                highlightedZone = -1;
                Utils.osd(osdLayoutSelection());
            } else {
                Utils.osd(`Layout ${layout + 1} does not exist`);
            }
        }
        onMoveActiveWindowUp: {
            moveClientToNeighbour(Workspace.activeWindow, "up");
        }
        onMoveActiveWindowDown: {
            moveClientToNeighbour(Workspace.activeWindow, "down");
        }
        onMoveActiveWindowLeft: {
            moveClientToNeighbour(Workspace.activeWindow, "left");
        }
        onMoveActiveWindowRight: {
            moveClientToNeighbour(Workspace.activeWindow, "right");
        }
        onSnapActiveWindow: {
            moveClientToClosestZone(Workspace.activeWindow);
        }
        onSnapAllWindows: {
            moveAllClientsToClosestZone();
        }
        onFreeActiveWindow: {
            const client = Workspace.activeWindow;
            if (!client || !checkFilter(client))
                return;

            const enabled = toggleFreeClient(client);
            if (moving && client.move) {
                freeMoving = enabled;
                highlightedZone = -1;
                if (enabled)
                    mainDialog.hide();
                else
                    mainDialog.show();
            }
            Utils.osd(enabled ? "Free movement enabled" : "Free movement disabled");
        }
        onResetCurrentLayout: {
            resetCurrentLayoutGeometry();
        }
    }

    DBusCall {
        id: dbusCall

        function exec(service, path, method, arguments = []) {
            this.service = service;
            this.path = path;
            this.method = method;
            this.arguments = arguments;
            this.call();
        }

        Component.onCompleted: {
            Core.registerQMLComponent("dbusCall", dbusCall);
        }
    }

    // workspace connection
    Connections {
        function onCurrentDesktopChanged() {
            if (disposing)
                return;

            if (config.trackLayoutPerDesktop)
                currentLayout = getCurrentLayout();

        }

        function onScreensChanged() {
            handleOutputGeometryChanged("screens changed");
        }

        function onVirtualScreenSizeChanged() {
            handleOutputGeometryChanged("virtual screen size changed");
        }

        function onVirtualScreenGeometryChanged() {
            handleOutputGeometryChanged("virtual screen geometry changed");
        }

        function onWindowAdded(client) {
            if (disposing)
                return;

            if (isProtectedCaptureClient(client)) {
                Utils.log("Ignoring protected capture client " + clientResourceClass(client));
                return;
            }

            connectSignals(client);
            if (!workspaceGeometryReady(clientOutput(client)))
                return;

            // check if client is in a zone application list
            const resourceClass = clientResourceClass(client);
            config.layouts[currentLayout].zones.forEach((zone, zoneIndex) => {
                if (zone.applications && zone.applications.includes(resourceClass)) {
                    moveClientToZone(client, zoneIndex);
                    return ;
                }
            });
            // auto snap to closest zone
            if (config.autoSnapAllNew && checkFilter(client))
                moveClientToClosestZone(client);

            // check if new window spawns in a zone
            if (client.zone == undefined || client.zone == -1)
                matchZone(client);

        }

        target: Workspace
    }

    Connections {
        //! still not working, hopefully it will at some point 😐
        function onConfigChanged() {
            if (disposing)
                return;

            resizedZoneGeometries = new Object();
            Core.loadConfig();
            refreshClientArea();
            updateDebugDialog();
        }

        target: Options
    }

}
