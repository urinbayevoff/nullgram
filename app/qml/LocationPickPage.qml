// Pick Location page (Telegram-iOS LocationPickerController):
// Uses Telegram's own getMapThumbnailFile (same source/pattern as ChatPage's place card),
// center pin with drag-to-pan (Web Mercator coordinates), zoom +/-, and «Shu joyni yuborish».
// OmonullOS currently has no geoclue/gpsd daemon, so by default hasGps is false (starts at
// Prefs.place = Toshkent, hides live location & "Mening joylashuvim"). When real device GPS
// is available (hasGps: true), also offers «Mening joylashuvim» and live location (15m / 1h / 8h).
pragma ComponentBehavior: Bound
import QtQuick

Page {
    id: page
    required property var chatId

    property real lat: Prefs.place && Prefs.place.length >= 2 ? Prefs.place[0] : 41.3111
    property real lon: Prefs.place && Prefs.place.length >= 2 ? Prefs.place[1] : 69.2797
    property int zoom: 15
    property bool hasGps: false
    property var gpsPlace: null         // [lat, lon, accuracy] when device GPS exists
    property string mapPath: ""
    property bool loadingMap: false
    property bool dragging: false
    property real panX: 0
    property real panY: 0
    property bool liveSheetOpen: false
    property int _mapSeq: 0

    signal pickedLocation(real latitude, real longitude, real accuracy)
    signal pickedLiveLocation(real latitude, real longitude, real accuracy, int livePeriod)

    readonly property string coordsText: lat.toFixed(5) + ", " + lon.toFixed(5)

    Component.onCompleted: {
        if (hasGps && gpsPlace && gpsPlace.length >= 2) {
            lat = gpsPlace[0]
            lon = gpsPlace[1]
        }
        requestMap()
    }

    function clampLat(v) { return Math.max(-85, Math.min(85, v)) }
    function wrapLon(v) {
        let x = v
        while (x > 180) x -= 360
        while (x < -180) x += 360
        return x
    }

    // Shift center by pixel drag delta (dx > 0 = dragged map right -> center moves West;
    // dy > 0 = dragged map down -> center moves North)
    function applyDragDelta(dx, dy) {
        const degPerPxLon = 360.0 / (256.0 * Math.pow(2, zoom))
        const cosLat = Math.max(0.15, Math.cos(lat * Math.PI / 180.0))
        const degPerPxLat = degPerPxLon * cosLat
        lat = clampLat(lat + dy * degPerPxLat)
        lon = wrapLon(lon - dx * degPerPxLon)
    }

    function requestMap() {
        const seq = ++_mapSeq
        loadingMap = true
        const w = Math.max(240, Math.min(512, Math.round(mapBox.width || 360)))
        const h = Math.max(240, Math.min(512, Math.round(mapBox.height || 360)))
        store.getMapThumbnail(chatId, lat, lon, zoom, w, h, 2, (path) => {
            if (!page || seq !== page._mapSeq)
                return
            page.loadingMap = false
            page.panX = 0
            page.panY = 0
            if (path) {
                // Force reload when same file path is returned in desk
                if (page.mapPath === path)
                    page.mapPath = ""
                page.mapPath = path
            }
        })
    }

    function zoomBy(delta) {
        const next = Math.max(13, Math.min(18, zoom + delta))
        if (next === zoom)
            return
        zoom = next
        requestMap()
    }

    function recenterGps() {
        if (!hasGps || !gpsPlace || gpsPlace.length < 2)
            return
        lat = clampLat(gpsPlace[0])
        lon = wrapLon(gpsPlace[1])
        requestMap()
    }

    function sendCurrent() {
        const acc = hasGps && gpsPlace && gpsPlace.length >= 3 ? gpsPlace[2] : 0
        pickedLocation(lat, lon, acc)
    }

    function sendLive(period) {
        if (!hasGps)
            return
        liveSheetOpen = false
        const acc = gpsPlace && gpsPlace.length >= 3 ? gpsPlace[2] : 0
        pickedLiveLocation(lat, lon, acc, period)
    }

    function dismiss() {
        if (liveSheetOpen) {
            liveSheetOpen = false
            return true
        }
        return false
    }

    Timer {
        id: mapDebounce
        interval: 220
        onTriggered: page.requestMap()
    }

    // ---- Top bar ----
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: Theme.bg
        z: 10
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea { id: backHit; width: 72; height: parent.height; onClicked: page.nav.pop() }
        Text {
            anchors.centerIn: parent
            text: Tr.t("Joylashuv")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
    }

    // ---- Map viewport ----
    Rectangle {
        id: mapBox
        y: bar.height
        width: parent.width
        height: parent.height - bar.height - bottomCard.height
        color: Theme.dark ? "#1b242c" : "#dce7ee"
        clip: true

        // Subtle grid behind map while loading / panning past tile edge
        Image {
            id: mapImg
            width: parent.width + 80
            height: parent.height + 80
            x: -40 + Math.max(-40, Math.min(40, page.panX))
            y: -40 + Math.max(-40, Math.min(40, page.panY))
            fillMode: Image.PreserveAspectCrop
            source: page.mapPath ? "file://" + page.mapPath : ""
            asynchronous: true
            cache: false
        }

        // Drag handler to pick any point on the map
        MouseArea {
            id: mapDrag
            anchors.fill: parent
            property real lastX: 0
            property real lastY: 0
            onPressed: (mouse) => {
                page.dragging = true
                lastX = mouse.x
                lastY = mouse.y
                mapDebounce.stop()
            }
            onPositionChanged: (mouse) => {
                if (!page.dragging)
                    return
                const dx = mouse.x - lastX
                const dy = mouse.y - lastY
                lastX = mouse.x
                lastY = mouse.y
                page.panX += dx
                page.panY += dy
                page.applyDragDelta(dx, dy)
            }
            onReleased: {
                page.dragging = false
                mapDebounce.restart()
            }
            onCanceled: {
                page.dragging = false
                mapDebounce.restart()
            }
        }

        // Ground shadow under center pin
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            width: page.dragging ? 16 : 10
            height: page.dragging ? 7 : 5
            radius: 4
            color: Qt.rgba(0, 0, 0, page.dragging ? 0.22 : 0.35)
            Behavior on width { NumberAnimation { duration: 150 } }
            Behavior on height { NumberAnimation { duration: 150 } }
        }

        // Center pin (lifts while dragging, like Telegram-iOS)
        Item {
            id: centerPin
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: page.dragging ? -26 : -18
            width: 36; height: 42
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 34; height: 34; radius: 17
                color: "#ff3b30"
                border.color: "white"; border.width: 2.5
                Icon {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    name: "place"
                    color: "white"
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 31
                width: 4; height: 10; radius: 2
                color: "#ff3b30"
            }
        }

        // Coordinate pill at top-left of map
        Rectangle {
            x: 12; y: 12
            width: coordPillText.implicitWidth + 18; height: 28; radius: 14
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.88)
            border.color: Theme.separator; border.width: 0.5
            Text {
                id: coordPillText
                anchors.centerIn: parent
                text: page.coordsText
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
            }
        }

        // Floating zoom (+/-) and GPS recenter buttons on right side
        Column {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.bottom: parent.bottom; anchors.bottomMargin: 14
            spacing: 8
            Rectangle {
                width: 40; height: 80; radius: 20
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)
                border.color: Theme.separator; border.width: 0.5
                clip: true
                Rectangle {
                    width: 40; height: 40
                    color: zoomInHit.pressed ? Theme.highlight : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: page.zoom < 18 ? Theme.text : Theme.grey
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Medium
                    }
                    MouseArea { id: zoomInHit; anchors.fill: parent; onClicked: page.zoomBy(1) }
                }
                Rectangle { y: 40; width: 40; height: 0.5; color: Theme.separator }
                Rectangle {
                    y: 40; width: 40; height: 40
                    color: zoomOutHit.pressed ? Theme.highlight : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: page.zoom > 13 ? Theme.text : Theme.grey
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Medium
                    }
                    MouseArea { id: zoomOutHit; anchors.fill: parent; onClicked: page.zoomBy(-1) }
                }
            }
            Rectangle {
                visible: page.hasGps
                width: 40; height: 40; radius: 20
                color: gpsHit.pressed ? Theme.highlight : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)
                border.color: Theme.separator; border.width: 0.5
                Icon {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    name: "locate"
                    color: Theme.accent
                }
                MouseArea { id: gpsHit; anchors.fill: parent; onClicked: page.recenterGps() }
            }
        }
    }

    // ---- Bottom action card (above safe.bottom) ----
    Rectangle {
        id: bottomCard
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: cardCol.height + 16 + safe.bottom
        color: Theme.bg
        z: 5

        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }

        Column {
            id: cardCol
            width: parent.width
            topPadding: 8

            // Primary: "Shu joyni yuborish"
            Rectangle {
                width: parent.width; height: 64
                color: sendLocHit.pressed ? Theme.highlight : "transparent"
                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 42; height: 42; radius: 21
                    color: "#34c759"
                    Icon {
                        anchors.centerIn: parent
                        width: 22; height: 22
                        name: "place"
                        color: "white"
                    }
                }
                Column {
                    x: 70; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 16
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tr.t("Shu joyni yuborish")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: page.coordsText
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                Rectangle {
                    visible: page.hasGps
                    x: 70; anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
                MouseArea {
                    id: sendLocHit
                    anchors.fill: parent
                    onClicked: page.sendCurrent()
                }
            }

            // Live location (ONLY when real device GPS is present)
            Rectangle {
                visible: page.hasGps
                width: parent.width; height: visible ? 64 : 0
                color: liveLocHit.pressed ? Theme.highlight : "transparent"
                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 42; height: 42; radius: 21
                    color: Theme.accent
                    Icon {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        name: "locate"
                        color: "white"
                    }
                }
                Column {
                    x: 70; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 16
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tr.t("Jonli joylashuvni ulashish")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tr.t("15 daqiqa, 1 soat yoki 8 soat")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: liveLocHit
                    anchors.fill: parent
                    onClicked: page.liveSheetOpen = true
                }
            }

            // Subtle hint when device GPS is unavailable
            Text {
                visible: !page.hasGps
                x: 16; width: parent.width - 32
                topPadding: 4; bottomPadding: 6
                wrapMode: Text.Wrap
                text: Tr.t("Qurilmada GPS topilmadi. Xaritani surib kerakli nuqtani tanlang.")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
        }
    }

    // ---- Live Location Duration Sheet (only reachable when hasGps) ----
    Item {
        id: liveSheet
        anchors.fill: parent
        z: 30
        visible: liveDim.opacity > 0
        Rectangle {
            id: liveDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: page.liveSheetOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; onClicked: page.liveSheetOpen = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: page.liveSheetOpen ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            spacing: 8
            Rectangle {
                width: parent.width
                height: liveCol.height
                radius: 14
                color: Theme.menu
                clip: true
                Column {
                    id: liveCol
                    width: parent.width
                    Item {
                        width: parent.width; height: 42
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Jonli joylashuv davomiyligi")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
                    }
                    Repeater {
                        model: [
                            { label: Tr.t("15 daqiqa"), secs: 900 },
                            { label: Tr.t("1 soat"), secs: 3600 },
                            { label: Tr.t("8 soat"), secs: 28800 }
                        ]
                        Rectangle {
                            id: durRow
                            required property int index
                            required property var modelData
                            width: liveCol.width; height: 50
                            color: dHit.pressed ? Theme.highlight : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: durRow.modelData.label
                                color: Theme.accent
                                font.family: Theme.font; font.pixelSize: 17
                            }
                            Rectangle {
                                visible: durRow.index < 2
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 0.5
                                color: Theme.separator
                            }
                            MouseArea {
                                id: dHit
                                anchors.fill: parent
                                onClicked: page.sendLive(durRow.modelData.secs)
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 52; radius: 14
                color: cancelLiveHit.pressed ? Theme.highlight : Theme.menu
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea { id: cancelLiveHit; anchors.fill: parent; onClicked: page.liveSheetOpen = false }
            }
        }
    }
}
