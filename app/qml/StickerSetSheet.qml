pragma ComponentBehavior: Bound
// Bottom sheet showing a sticker pack when a sticker in chat (or in search) is tapped:
// pack title, lazy-loaded grid of stickers (only visible cells download and play TGS/WebM),
// "Qo'shish (N stiker)" / "O'chirish" (changeStickerSet), tap a sticker to send to this chat,
// and safe.bottom clearance for ztMETRO's nav line.
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 32

    property var store: null
    property bool open: false
    property bool canSend: true
    property real safeBottom: 0
    property string setId: ""
    property var stickerSet: null
    property bool loading: false
    property bool busy: false
    property string errorText: ""
    property var paths: ({})
    property int got: 0
    property int _reqId: 0

    signal picked(var sticker)
    signal changed(string setId, bool installed)
    signal closed()

    function show(id) {
        const sid = id ? String(id) : ""
        if (!sid || sid === "0")
            return
        setId = sid
        stickerSet = null
        loading = true
        busy = false
        errorText = ""
        open = true
        visible = true
        grid.contentY = 0
        fall.stop()
        shade.stop()
        panelSlide.y = panel.height
        dim.opacity = 0
        rise.from = panel.height
        rise.restart()
        shade.restart()
        loadSet()
    }

    function close() {
        if (!open)
            return
        open = false
        _reqId += 1
        loading = false
        busy = false
        rise.stop()
        shade.stop()
        fallY.to = panel.height
        fall.restart()
        closed()
    }

    function loadSet() {
        if (!store || !setId)
            return
        _reqId += 1
        const req = _reqId
        loading = true
        errorText = ""
        store.getStickerSet(setId, (res, err) => {
            if (!sheet || req !== sheet._reqId || !sheet.open)
                return
            sheet.loading = false
            if (!res) {
                sheet.errorText = err || Tr.t("To'plam topilmadi")
                return
            }
            sheet.stickerSet = res
        })
    }

    function toggleInstall() {
        if (!store || !stickerSet || busy)
            return
        const sid = String(stickerSet.id || setId)
        const next = !stickerSet.is_installed
        busy = true
        store.changeStickerSet(sid, next, (ok, err) => {
            if (!sheet)
                return
            sheet.busy = false
            if (!ok) {
                sheet.errorText = err || Tr.t("Bo'lmadi")
                return
            }
            if (sheet.stickerSet && String(sheet.stickerSet.id) === sid)
                sheet.stickerSet = Object.assign({}, sheet.stickerSet, { is_installed: next })
            sheet.changed(sid, next)
        })
    }

    function stillOf(st) {
        if (!st)
            return null
        const th = st.thumbnail
        const f = th && th.format && th.format["@type"]
        if (f === "thumbnailFormatWebp" || f === "thumbnailFormatJpeg" || f === "thumbnailFormatPng" || f === "thumbnailFormatTgs")
            return th.file
        return st.format && st.format["@type"] === "stickerFormatWebp" ? st.sticker : null
    }

    function stillUrl(path) {
        return /\.tgs$/i.test(path) ? "image://lottie/0/-/" + path : "image://thumb/" + path
    }

    function want(f) {
        if (!f || !store || paths[f.id] !== undefined)
            return
        paths[f.id] = ""
        store.fetch(f, 2, (path) => {
            if (!sheet)
                return
            sheet.paths[f.id] = path
            sheet.got++
        })
    }

    function pathOf(f, _tick) {
        return f ? (paths[f.id] || "") : ""
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    NumberAnimation { id: shade; target: dim; property: "opacity"; from: 0; to: 0.4; duration: 240 }

    Rectangle {
        id: panel
        width: parent.width
        anchors.bottom: parent.bottom
        transform: Translate { id: panelSlide; y: 0 }
        readonly property real maxH: Math.max(360, Math.round(sheet.height * 0.72))
        height: Math.min(maxH, Math.max(340 + sheet.safeBottom, Math.round(sheet.height * 0.62) + sheet.safeBottom))
        radius: 16
        color: Theme.dark ? "#111113" : Theme.grouped
        MouseArea { anchors.fill: parent }

        // Flat bottom extension so the rounded sheet meets the bottom edge cleanly under safe.bottom
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 20
            color: panel.color
        }

        // Top drag handle
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 7; width: 36; height: 4; radius: 2
            color: Theme.separator
        }

        // Close button
        Icon {
            x: 16; y: 20
            width: 22; height: 22
            name: "cross"
            color: Theme.grey
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: sheet.close() }
        }

        // Title & count
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16
            width: parent.width - 96
            spacing: 1
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: sheet.stickerSet ? (sheet.stickerSet.title || Tr.t("Stiker to'plami")) : Tr.t("Stiker to'plami")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                visible: !!sheet.stickerSet && !!sheet.stickerSet.stickers
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: sheet.stickerSet && sheet.stickerSet.stickers ? Tr.n("%1 ta stiker", sheet.stickerSet.stickers.length) : ""
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }

        Rectangle {
            x: 0; y: 58
            width: parent.width; height: 0.5
            color: Theme.separator
        }

        // Virtualized sticker grid: only cells in view download and animate
        GridView {
            id: grid
            x: 10; y: 62
            width: parent.width - 20
            height: Math.max(80, actionBtn.y - y - 12)
            readonly property int cols: 4
            cellWidth: Math.floor(width / cols)
            cellHeight: cellWidth
            cacheBuffer: 80
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            visible: !sheet.loading && sheet.stickerSet !== null && sheet.errorText === ""
            model: sheet.stickerSet && sheet.stickerSet.stickers ? sheet.stickerSet.stickers : []

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: grid.cellWidth; height: grid.cellHeight

                readonly property string fmt: modelData && modelData.format ? modelData.format["@type"] : ""
                readonly property bool isTgs: fmt === "stickerFormatTgs"
                readonly property bool isWebm: fmt === "stickerFormatWebm"
                readonly property real rowTop: Math.floor(index / grid.cols) * grid.cellHeight
                readonly property bool inView: sheet.open && sheet.visible && grid.height > 0
                                               && (rowTop + grid.cellHeight) > grid.contentY
                                               && rowTop < (grid.contentY + grid.height)
                readonly property var thumbFile: sheet.stillOf(modelData)
                readonly property var animFile: (isTgs || isWebm) ? (modelData.sticker || null) : null
                readonly property string thumbPath: sheet.pathOf(thumbFile, sheet.got)
                readonly property string animPath: sheet.pathOf(animFile, sheet.got)

                onInViewChanged: {
                    if (inView) {
                        sheet.want(thumbFile)
                        if (animFile)
                            sheet.want(animFile)
                    }
                }
                Component.onCompleted: {
                    if (inView) {
                        sheet.want(thumbFile)
                        if (animFile)
                            sheet.want(animFile)
                    }
                }

                Rectangle {
                    anchors.fill: parent; anchors.margins: 3
                    radius: 10
                    color: cellHit.pressed ? Theme.highlight : "transparent"
                }

                Image {
                    id: thumbImg
                    anchors.fill: parent; anchors.margins: 6
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(Math.round(width) * 2, Math.round(height) * 2)
                    visible: !(animLoader.active && animLoader.animReady)
                    source: cell.thumbPath ? sheet.stillUrl(cell.thumbPath)
                          : (cell.isTgs && cell.animPath ? "image://lottie/0/-/" + cell.animPath : "")
                }

                Loader {
                    id: animLoader
                    property bool animReady: false
                    anchors.fill: parent; anchors.margins: 6
                    active: cell.inView && cell.animPath !== "" && Prefs.stickers && (cell.isTgs || cell.isWebm)
                    onActiveChanged: if (!active) animReady = false
                    sourceComponent: cell.isTgs ? tgsComp : webmComp
                    Component {
                        id: tgsComp
                        Lottie {
                            anchors.fill: parent
                            path: cell.animPath
                            running: cell.inView && sheet.open
                            most: 160
                            onShownChanged: animLoader.animReady = shown
                            Component.onCompleted: animLoader.animReady = shown
                        }
                    }
                    Component {
                        id: webmComp
                        InlineVideo {
                            anchors.fill: parent
                            path: cell.animPath
                            running: cell.inView && sheet.open
                            sound: false
                            loop: true
                            radius: 8
                            onShowingChanged: animLoader.animReady = showing
                            Component.onCompleted: animLoader.animReady = showing
                        }
                    }
                }

                MouseArea {
                    id: cellHit
                    anchors.fill: parent
                    onClicked: {
                        if (!sheet.canSend)
                            return
                        sheet.picked(cell.modelData)
                        sheet.close()
                    }
                }
            }
        }

        // Loading indicator
        Row {
            visible: sheet.loading
            anchors.centerIn: grid
            spacing: 10
            Ring {
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                value: 0.72
                thickness: 2
                cross: false
                color: Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Yuklanmoqda…")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
        }

        // Error state
        Column {
            visible: !sheet.loading && sheet.errorText !== ""
            anchors.centerIn: grid
            width: parent.width - 48
            spacing: 12
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: sheet.errorText
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: retryTxt.implicitWidth + 28; height: 34; radius: 17
                color: retryHit.pressed ? Theme.highlight : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                Text {
                    id: retryTxt
                    anchors.centerIn: parent
                    text: Tr.t("Qayta urinish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                MouseArea { id: retryHit; anchors.fill: parent; onClicked: sheet.loadSet() }
            }
        }

        // Bottom Add / Remove button (clear of ztMETRO's nav line via safe.bottom)
        Rectangle {
            id: actionBtn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + sheet.safeBottom
            width: parent.width - 32; height: 48; radius: 24
            readonly property bool ready: !sheet.loading && sheet.stickerSet !== null && !sheet.busy
            readonly property bool installed: !!(sheet.stickerSet && sheet.stickerSet.is_installed)
            color: installed ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, Theme.dark ? 0.22 : 0.12)
                             : Theme.accent
            opacity: !ready ? 0.45 : actionHit.pressed ? 0.8 : 1
            Text {
                anchors.centerIn: parent
                text: !sheet.stickerSet ? Tr.t("Yuklanmoqda…")
                    : actionBtn.installed ? Tr.t("O'chirish")
                    : Tr.f("Qo'shish (%1 stiker)", sheet.stickerSet.stickers ? sheet.stickerSet.stickers.length : 0)
                color: actionBtn.installed ? Theme.danger : "white"
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            MouseArea {
                id: actionHit
                anchors.fill: parent
                enabled: actionBtn.ready
                onClicked: sheet.toggleInstall()
            }
        }
    }

    NumberAnimation { id: rise; target: panelSlide; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
    ParallelAnimation {
        id: fall
        NumberAnimation { id: fallY; target: panelSlide; property: "y"; to: panel.height; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 220 }
        onFinished: if (!sheet.open) sheet.visible = false
    }
}
