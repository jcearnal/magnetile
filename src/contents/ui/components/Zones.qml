import QtQuick
import QtQuick.Layouts
import "../components" as Components

Item {
    id: zones

    property var config
    property int currentLayout
    property int highlightedZone
    property var highlightedTarget
    property int layoutIndex
    property var targets: []
    readonly property color highlightColor: "#00d5ff"
    property alias repeater: repeater

    Repeater {
        id: repeater

        model: targets

        // zone
        Item {
            id: zone

            property int zoneIndex: modelData.zone
            property int zonePadding: config.layouts[layoutIndex].padding || 0
            property var sourceZone: config.layouts[layoutIndex].zones[zoneIndex] || {}
            property var renderZones: config.zoneOverlayIndicatorDisplay == 1 ? [sourceZone] : config.layouts[layoutIndex].zones
            property int activeIndex: config.zoneOverlayIndicatorDisplay == 1 ? 0 : zoneIndex
            property var indicatorPos: (sourceZone && sourceZone.indicator && sourceZone.indicator.position) || "center"
            property bool active: ((highlightedTarget && highlightedTarget.id == modelData.id) || (!highlightedTarget && highlightedZone == zoneIndex)) && currentLayout == layoutIndex

            x: modelData.geometry ? modelData.geometry.x - clientArea.x : ((sourceZone.x / 100) * (clientArea.width - zonePadding)) + zonePadding
            y: modelData.geometry ? modelData.geometry.y - clientArea.y : ((sourceZone.y / 100) * (clientArea.height - zonePadding)) + zonePadding
            implicitWidth: modelData.geometry ? modelData.geometry.width : ((sourceZone.width / 100) * (clientArea.width - zonePadding)) - zonePadding
            implicitHeight: modelData.geometry ? modelData.geometry.height : ((sourceZone.height / 100) * (clientArea.height - zonePadding)) - zonePadding

            // zone indicator
            Rectangle {
                id: zoneIndicator

                width: 160
                height: 100
                color: colorHelper.backgroundColor
                radius: 10
                border.color: colorHelper.getBorderColor(color)
                border.width: 1
                opacity: !showZoneOverlay ? 0 : (zoneSelector.expanded) ? 0 : (active ? 0.6 : 1)
                scale: active ? 1.1 : 1
                visible: config.enableZoneOverlay
                // position
                anchors.left: (indicatorPos === "top-left" || indicatorPos === "left-center" || indicatorPos === "bottom-left") ? parent.left : undefined
                anchors.right: (indicatorPos === "top-right" || indicatorPos === "right-center" || indicatorPos === "bottom-right") ? parent.right : undefined
                anchors.top: (indicatorPos === "top-left" || indicatorPos === "top-center" || indicatorPos === "top-right") ? parent.top : undefined
                anchors.bottom: (indicatorPos === "bottom-left" || indicatorPos === "bottom-center" || indicatorPos === "bottom-right") ? parent.bottom : undefined
                anchors.horizontalCenter: (indicatorPos === "center" || indicatorPos === "top-center" || indicatorPos === "bottom-center") ? parent.horizontalCenter : undefined
                anchors.verticalCenter: (indicatorPos === "center" || indicatorPos === "left-center" || indicatorPos === "right-center") ? parent.verticalCenter : undefined
                // margin
                anchors.leftMargin: (sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.left) || 0
                anchors.rightMargin: (sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.right) || 0
                anchors.topMargin: (sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.top) || 0
                anchors.bottomMargin: (sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.bottom) || 0
                // offset
                anchors.horizontalCenterOffset: ((sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.left) || 0) - ((sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.right) || 0)
                anchors.verticalCenterOffset: ((sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.top) || 0) - ((sourceZone && sourceZone.indicator && sourceZone.indicator.margin && sourceZone.indicator.margin.bottom) || 0)

                Components.Indicator {
                    zones: renderZones
                    activeZone: activeIndex
                    anchors.centerIn: parent
                    width: parent.width - 20
                    height: parent.height - 20
                    hovering: (active)
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: zoneSelector.expanded ? 0 : 150
                    }

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }

                }

            }

            // zone border
            Rectangle {
                id: zoneBorder

                anchors.fill: parent
                color: "transparent"
                border.color: active ? highlightColor : "transparent"
                border.width: 3
                radius: 8
            }

            // zone background
            Rectangle {
                id: zoneBackground

                opacity: active ? 0.1 : 0
                anchors.fill: parent
                color: highlightColor
                radius: 8
            }

            // indicator shadow
            Components.Shadow {
                target: zoneIndicator
                visible: zoneIndicator.visible
            }

            Components.ColorHelper {
                id: colorHelper
            }

        }

    }

}
