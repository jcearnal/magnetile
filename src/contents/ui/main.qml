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
    property var clientArea: new Object()
    property var cachedClientArea: new Object()
    property var displaySize: new Object()
    property int currentLayout: 0
    property var screenLayouts: new Object()
    property int highlightedZone: -1
    property var activeScreen: null
    property bool showZoneOverlay: config.zoneOverlayShowWhen == 0
    property int geometryTolerance: 3

    function clientOutput(client) {
        return client && (client.output || client.screen || Workspace.activeScreen);
    }

    function outputName(screen) {
        return screen && screen.name ? screen.name : "";
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

    function configuredLayoutForOutput(screen) {
        const name = outputName(screen);
        if (!name || !config.monitorLayouts)
            return 0;

        const assigned = config.monitorLayouts[name];
        if (assigned === undefined || assigned === null || assigned === "")
            return 0;

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
        return 0;
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

    function refreshClientArea(screen) {
        activeScreen = screen || Workspace.activeScreen;
        clientArea = Workspace.clientArea(KWin.FullScreenArea, activeScreen, Workspace.currentDesktop);
        displaySize = Workspace.virtualScreenSize;
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

    function zoneGeometry(layoutIndex, zoneIndex, screen) {
        const layout = config.layouts[clampLayoutIndex(layoutIndex)];
        const zone = layout.zones[zoneIndex];
        const zonePadding = layout.padding || 0;
        const area = Workspace.clientArea(KWin.FullScreenArea, screen || activeScreen || Workspace.activeScreen, Workspace.currentDesktop);
        const zoneX = area.x + ((zone.x / 100) * (area.width - zonePadding)) + zonePadding;
        const zoneY = area.y + ((zone.y / 100) * (area.height - zonePadding)) + zonePadding;
        const zoneWidth = ((zone.width / 100) * (area.width - zonePadding)) - zonePadding;
        const zoneHeight = ((zone.height / 100) * (area.height - zonePadding)) - zonePadding;
        return roundedRect(zoneX, zoneY, zoneWidth, zoneHeight);
    }

    function matchZone(client) {
        if (!checkFilter(client))
            return -1;

        refreshClientAreaForClient(client);
        client.zone = -1;
        // get all zones in the current layout
        const zones = config.layouts[currentLayout].zones;
        // loop through zones and compare with the geometries of the client
        for (let i = 0; i < zones.length; i++) {
            const geometry = zoneGeometry(currentLayout, i, clientOutput(client));
            if (rectsClose(client.frameGeometry, geometry)) {
                // zone found, set it and exit the loop
                client.zone = i;
                client.layout = currentLayout;
                break;
            }
        }
        return client.zone;
    }

    function getWindowsInZone(zone, layout) {
        const windows = [];
        const activeWindow = Workspace.activeWindow;
        const output = clientOutput(activeWindow);
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const client = Workspace.stackingOrder[i];
            if (client.zone === zone && client.layout === layout && sameDesktop(client, Workspace.currentDesktop) && clientActivity(client) === Workspace.currentActivity && clientOutput(client) === output && checkFilter(client))
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
            if (index === -1)
                Workspace.activeWindow = clientsInZone[0];
            else
                Workspace.activeWindow = clientsInZone[(index + 1) % clientsInZone.length];
        }
    }

    function moveClientToZone(client, zone) {
        if (!checkFilter(client))
            return ;

        Utils.log("Moving client " + client.resourceClass.toString() + " to zone " + zone);
        refreshClientAreaForClient(client);
        // move client to zone
        if (zone != -1) {
            if (zone < 0 || zone >= config.layouts[currentLayout].zones.length)
                return;

            const newGeometry = zoneGeometry(currentLayout, zone, clientOutput(client));
            Utils.log("Moving client " + client.resourceClass.toString() + " to zone " + zone + " with geometry " + JSON.stringify(newGeometry));
            saveClientProperties(client, zone);
            client.setMaximize(false, false);
            client.frameGeometry = newGeometry;
        } else {
            saveClientProperties(client, zone);
        }
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
    }

    function moveClientToClosestZone(client) {
        if (!checkFilter(client))
            return null;

        Utils.log("Moving client " + client.resourceClass.toString() + " to closest zone");
        refreshClientAreaForClient(client);
        const centerPointOfClient = {
            "x": client.frameGeometry.x + (client.frameGeometry.width / 2),
            "y": client.frameGeometry.y + (client.frameGeometry.height / 2)
        };
        const zones = config.layouts[currentLayout].zones;
        let closestZone = null;
        let closestDistance = Infinity;
        for (let i = 0; i < zones.length; i++) {
            const zone = zones[i];
            const zoneCenter = {
                "x": (zone.x + zone.width / 2) / 100 * clientArea.width + clientArea.x,
                "y": (zone.y + zone.height / 2) / 100 * clientArea.height + clientArea.y
            };
            const distance = Math.sqrt(Math.pow(centerPointOfClient.x - zoneCenter.x, 2) + Math.pow(centerPointOfClient.y - zoneCenter.y, 2));
            if (distance < closestDistance) {
                closestZone = i;
                closestDistance = distance;
            }
        }
        if (client.zone !== closestZone || client.layout !== currentLayout)
            moveClientToZone(client, closestZone);

        return closestZone;
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

    function moveClientToNeighbour(client, direction) {
        if (!checkFilter(client))
            return null;

        Utils.log("Moving client " + client.resourceClass.toString() + " to neighbour " + direction);
        refreshClientAreaForClient(client);
        const zones = config.layouts[currentLayout].zones;
        if (client.zone === -1 || client.layout !== currentLayout) {
            moveClientToClosestZone(client);
            return client.zone;
        }
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
        if (config.trackLayoutPerScreen)
            parts.push(outputName(activeScreen || Workspace.activeScreen));

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

    function checkFilter(client) {
        // filter out abnormal windows like docks, panels, etc...
        if (!client)
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
                return filter.includes(client.resourceClass.toString());

            if (config.filterMode == 1)
                return !filter.includes(client.resourceClass.toString());

        }
        return true;
    }

    function tiledClientsForResize(client, layout, output, desktop, activity) {
        const clients = [];
        for (let i = 0; i < Workspace.stackingOrder.length; i++) {
            const window = Workspace.stackingOrder[i];
            if (!checkFilter(window))
                continue;

            if (window === client || window.zone === undefined || window.zone === -1)
                continue;

            if (window.layout !== layout)
                continue;

            if (clientOutput(window) !== output || !sameDesktop(window, desktop) || clientActivity(window) !== activity)
                continue;

            clients.push(window);
        }
        return clients;
    }

    function snapshotResizeGroup(client) {
        const layout = client.layout !== undefined ? client.layout : currentLayout;
        if (client.zone === undefined || client.zone === -1 || layout === undefined || layout === -1)
            return null;

        const output = clientOutput(client);
        const desktop = Workspace.currentDesktop;
        const activity = Workspace.currentActivity;
        const windows = tiledClientsForResize(client, layout, output, desktop, activity);
        const snapshots = [];
        for (let i = 0; i < windows.length; i++) {
            const window = windows[i];
            snapshots.push({
                "client": window,
                "zone": window.zone,
                "layout": window.layout,
                "geometry": Qt.rect(window.frameGeometry.x, window.frameGeometry.y, window.frameGeometry.width, window.frameGeometry.height)
            });
        }

        return {
            "zone": client.zone,
            "layout": layout,
            "output": output,
            "desktop": desktop,
            "activity": activity,
            "geometry": Qt.rect(client.frameGeometry.x, client.frameGeometry.y, client.frameGeometry.width, client.frameGeometry.height),
            "windows": snapshots
        };
    }

    function connectedResize(client) {
        const snapshot = client.magnetileResizeSnapshot;
        if (!snapshot || snapshot.zone === undefined || snapshot.zone === -1)
            return;

        const oldGeometry = rectEdges(snapshot.geometry);
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
            return;

        let constrainedLeft = newGeometry.left;
        let constrainedTop = newGeometry.top;
        let constrainedRight = newGeometry.right;
        let constrainedBottom = newGeometry.bottom;
        for (let i = 0; i < snapshot.windows.length; i++) {
            const item = snapshot.windows[i];
            const oldOther = rectEdges(item.geometry);
            const overlapsOldY = rangesOverlap(oldGeometry.top, oldGeometry.bottom, oldOther.top, oldOther.bottom);
            const overlapsOldX = rangesOverlap(oldGeometry.left, oldGeometry.right, oldOther.left, oldOther.right);
            const rightGap = oldOther.left - oldGeometry.right;
            const leftGap = oldGeometry.left - oldOther.right;
            const bottomGap = oldOther.top - oldGeometry.bottom;
            const topGap = oldGeometry.top - oldOther.bottom;

            if (changed.right && isResizeAdjacent(rightGap, resizeTolerance) && overlapsOldY)
                constrainedRight = Math.min(constrainedRight, oldOther.right - preservedResizeGap(rightGap) - minSize);

            if (changed.left && isResizeAdjacent(leftGap, resizeTolerance) && overlapsOldY)
                constrainedLeft = Math.max(constrainedLeft, oldOther.left + preservedResizeGap(leftGap) + minSize);

            if (changed.bottom && isResizeAdjacent(bottomGap, resizeTolerance) && overlapsOldX)
                constrainedBottom = Math.min(constrainedBottom, oldOther.bottom - preservedResizeGap(bottomGap) - minSize);

            if (changed.top && isResizeAdjacent(topGap, resizeTolerance) && overlapsOldX)
                constrainedTop = Math.max(constrainedTop, oldOther.top + preservedResizeGap(topGap) + minSize);
        }

        const constrainedWidth = Math.round(constrainedRight - constrainedLeft);
        const constrainedHeight = Math.round(constrainedBottom - constrainedTop);
        if (constrainedWidth >= minSize && constrainedHeight >= minSize) {
            newGeometry = rectEdges(roundedRect(constrainedLeft, constrainedTop, constrainedWidth, constrainedHeight));
            if (!rectsClose(client.frameGeometry, Qt.rect(newGeometry.left, newGeometry.top, newGeometry.width, newGeometry.height))) {
                client.setMaximize(false, false);
                client.frameGeometry = Qt.rect(newGeometry.left, newGeometry.top, newGeometry.width, newGeometry.height);
            }
        }

        for (let i = 0; i < snapshot.windows.length; i++) {
            const item = snapshot.windows[i];
            const window = item.client;
            if (!checkFilter(window) || window.minimized)
                continue;

            const oldOther = rectEdges(item.geometry);
            let nextLeft = oldOther.left;
            let nextTop = oldOther.top;
            let nextRight = oldOther.right;
            let nextBottom = oldOther.bottom;
            const overlapsOldY = rangesOverlap(oldGeometry.top, oldGeometry.bottom, oldOther.top, oldOther.bottom);
            const overlapsOldX = rangesOverlap(oldGeometry.left, oldGeometry.right, oldOther.left, oldOther.right);

            const rightGap = oldOther.left - oldGeometry.right;
            const leftGap = oldGeometry.left - oldOther.right;
            const bottomGap = oldOther.top - oldGeometry.bottom;
            const topGap = oldGeometry.top - oldOther.bottom;

            if (changed.right && isResizeAdjacent(rightGap, resizeTolerance) && overlapsOldY)
                nextLeft = newGeometry.right + preservedResizeGap(rightGap);

            if (changed.left && isResizeAdjacent(leftGap, resizeTolerance) && overlapsOldY)
                nextRight = newGeometry.left - preservedResizeGap(leftGap);

            if (changed.bottom && isResizeAdjacent(bottomGap, resizeTolerance) && overlapsOldX)
                nextTop = newGeometry.bottom + preservedResizeGap(bottomGap);

            if (changed.top && isResizeAdjacent(topGap, resizeTolerance) && overlapsOldX)
                nextBottom = newGeometry.top - preservedResizeGap(topGap);

            const nextWidth = Math.round(nextRight - nextLeft);
            const nextHeight = Math.round(nextBottom - nextTop);
            if (nextWidth < minSize || nextHeight < minSize)
                continue;

            if (Math.abs(nextLeft - oldOther.left) <= geometryTolerance &&
                    Math.abs(nextTop - oldOther.top) <= geometryTolerance &&
                    Math.abs(nextRight - oldOther.right) <= geometryTolerance &&
                    Math.abs(nextBottom - oldOther.bottom) <= geometryTolerance)
                continue;

            window.setMaximize(false, false);
            window.frameGeometry = roundedRect(nextLeft, nextTop, nextWidth, nextHeight);
            window.zone = item.zone;
            window.layout = item.layout;
            window.desktop = snapshot.desktop;
            window.activity = snapshot.activity;
        }

        client.zone = snapshot.zone;
        client.layout = snapshot.layout;
        client.desktop = snapshot.desktop;
        client.activity = snapshot.activity;
    }

    function connectSignals(client) {
        function onInteractiveMoveResizeStarted() {
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
                    if (config.rememberWindowGeometries && client.zone != -1) {
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
                    Utils.log("Move start " + client.resourceClass.toString());
                    mainDialog.show();
                }
                if (client.resize) {
                    refreshClientAreaForClient(client);
                    if (client.zone === undefined || client.zone === -1)
                        matchZone(client);

                    client.magnetileResizeSnapshot = snapshotResizeGroup(client);
                    moving = false;
                    moved = false;
                    resizing = true;
                }
            }
        }

        function onInteractiveMoveResizeStepped() {
            if (client.resizeable) {
                if (moving && checkFilter(client))
                    moved = true;

            }
        }

        function onInteractiveMoveResizeFinished() {
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
                    if (mainDialog.visible)
                        moveClientToZone(client, highlightedZone);
                    else
                        saveClientProperties(client, -1);
                }
                mainDialog.hide();
            } else if (resizing) {
                connectedResize(client);
                if (!client.magnetileResizeSnapshot)
                    matchZone(client);

                Utils.log("Resizing end: Connected resize for client " + client.resourceClass.toString() + " at layout.zone " + client.layout + " " + client.zone);
                client.magnetileResizeSnapshot = null;
            }
            moving = false;
            moved = false;
            resizing = false;
        }

        // fix from https://github.com/gerritdevriese/kzones/pull/25
        function onFullScreenChanged() {
            Utils.log("Client fullscreen: " + client.resourceClass.toString() + " (fullscreen " + client.fullScreen + ")");
            if (client.fullScreen == true) {
                Utils.log("onFullscreenChanged: Client zone: " + client.zone + " layout: " + client.layout);
                if (client.zone != -1 && client.layout != -1) {
                    //check if fullscreen is enabled for layout or for zone
                    const layout = config.layouts[client.layout];
                    const zone = layout.zones[client.zone];
                    Utils.log("Layout.fullscreen: " + layout.fullscreen + " Zone.fullscreen: " + zone.fullscreen);
                    if (layout.fullscreen == true || zone.fullscreen == true) {
                        const newGeometry = zoneGeometry(client.layout, client.zone, clientOutput(client));
                        Utils.log("Fullscreen client " + client.resourceClass.toString() + " to zone " + client.zone + " with geometry " + JSON.stringify(newGeometry));
                        client.setMaximize(false, false);
                        client.frameGeometry = newGeometry;
                    }
                }
            }
            mainDialog.hide();
        }

        if (!checkFilter(client))
            return ;

        Utils.log("Connecting signals for client " + client.resourceClass.toString());
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

    PlasmaCore.Dialog {
        id: mainDialog

        function show() {
            mainDialog.visible = true;
            mainDialog.setWidth(Workspace.virtualScreenSize.width);
            mainDialog.setHeight(Workspace.virtualScreenSize.height);
            refreshClientArea();
        }

        function hide() {
            mainDialog.visible = false;
            zoneSelector.expanded = false;
            zoneSelector.near = false;
            highlightedZone = -1;
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
        width: displaySize.width
        height: displaySize.height

        Item {
            id: mainItem

            property alias repeaterLayout: repeaterLayout

            width: mainDialog.width
            height: mainDialog.height

            // main polling timer
            Timer {
                id: timer

                triggeredOnStart: true
                interval: config.pollingRate
                running: mainDialog.visible
                repeat: true
                onTriggered: {
                    refreshClientArea();
                    let hoveringZone = -1;
                    // zone overlay
                    const currentZones = repeaterLayout.itemAt(currentLayout);
                    if (config.enableZoneOverlay && showZoneOverlay && !zoneSelector.expanded && currentZones)
                        currentZones.repeater.model.forEach((zone, zoneIndex) => {
                        if (Utils.isHovering(currentZones.repeater.itemAt(zoneIndex).children[config.zoneOverlayHighlightTarget]))
                            hoveringZone = zoneIndex;

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
                            config.layouts[currentLayout].zones.forEach((zone, zoneIndex) => {
                                const geometry = zoneGeometry(currentLayout, zoneIndex, activeScreen);
                                let zoneGeometry = {
                                    "x": geometry.x - padding / 2,
                                    "y": geometry.y - padding / 2,
                                    "width": geometry.width + padding,
                                    "height": geometry.height + padding
                                };
                                //adjust most left edge
                                if (zoneGeometry.x <= clientArea.x + halfPadding) {
                                    zoneGeometry.x = clientArea.x;
                                    zoneGeometry.width += padding;
                                }
                                //adjust most top edge
                                if (zoneGeometry.y <= clientArea.y + halfPadding) {
                                    zoneGeometry.y = clientArea.y;
                                    zoneGeometry.height += padding;
                                }
                                //adjust most right edge
                                if (zoneGeometry.x + zoneGeometry.width >= clientArea.x + clientArea.width - halfPadding)
                                    zoneGeometry.width += halfPadding;

                                //adjust most bottom edge
                                if (zoneGeometry.y + zoneGeometry.height >= clientArea.y + clientArea.height - halfPadding)
                                    zoneGeometry.height += halfPadding;

                                // check if cursor is inside the zone geometry
                                if (Utils.isPointInside(Workspace.cursorPos.x, Workspace.cursorPos.y, zoneGeometry))
                                    hoveringZone = zoneIndex;

                            });
                        }
                    }
                    // if hovering zone changed from the last frame
                    if (hoveringZone != highlightedZone) {
                        Utils.log("Highlighting zone " + hoveringZone + " in layout " + currentLayout);
                        highlightedZone = hoveringZone;
                    }
                }
            }

            Item {
                x: clientArea.x || 0
                y: clientArea.y || 0
                width: clientArea.width || 0
                height: clientArea.height || 0
                clip: true

                Components.Debug {
                    info: ({
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
                        "screenLayouts": screenLayouts
                    })
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
                        layoutIndex: index
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
            Utils.osd(osdLayoutName());
        }
        onCycleLayoutsReversed: {
            setCurrentLayout((currentLayout - 1 + config.layouts.length) % config.layouts.length);
            highlightedZone = -1;
            Utils.osd(osdLayoutName());
        }
        onMoveActiveWindowToNextZone: {
            const client = Workspace.activeWindow;
            if (client.zone == -1)
                moveClientToClosestZone(client);

            const zonesLength = config.layouts[currentLayout].zones.length;
            moveClientToZone(client, (client.zone + 1) % zonesLength);
        }
        onMoveActiveWindowToPreviousZone: {
            const client = Workspace.activeWindow;
            if (client.zone == -1)
                moveClientToClosestZone(client);

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
        onSwitchToNextWindowInCurrentZone: {
            switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout);
        }
        onSwitchToPreviousWindowInCurrentZone: {
            switchWindowInZone(Workspace.activeWindow.zone, Workspace.activeWindow.layout, true);
        }
        onMoveActiveWindowToZone: {
            moveClientToZone(Workspace.activeWindow, zone);
        }
        onActivateLayout: {
            if (layout <= config.layouts.length - 1) {
                setCurrentLayout(layout);
                highlightedZone = -1;
                Utils.osd(osdLayoutName());
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
            if (config.trackLayoutPerDesktop)
                currentLayout = getCurrentLayout();

        }

        function onWindowAdded(client) {
            connectSignals(client);
            // check if client is in a zone application list
            config.layouts[currentLayout].zones.forEach((zone, zoneIndex) => {
                if (zone.applications && zone.applications.includes(client.resourceClass.toString())) {
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
            Core.loadConfig();
        }

        target: Options
    }

}
