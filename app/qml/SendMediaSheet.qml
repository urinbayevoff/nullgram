// Pre-send media preview & options sheet (Telegram-iOS/Android style, bottom sheet with safe.bottom & osk.h).
// Features: preview of selected photos/videos/files, thumbnail strip with reorder (long-press drag or <- / ->)
// and remove, caption input with inline emoji tray, Compress vs Original quality (file), Spoiler (Veil),
// Album vs Separate, View-once (private 1-on-1 chats only), Silent & Scheduled send (long-press Send),
// and full-resolution 90-degree rotate + aspect crop via Python QImage (ink.editPhoto).
pragma ComponentBehavior: Bound
import QtQuick
import "Emoji.js" as EmojiData

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 16

    property bool open: false
    property var items: []              // [{ path, origPath, name, size, kind, w, h, spoiler, rot, cx, cy, cw, ch, cropKey }]
    property int activeIndex: 0
    property bool asFiles: false
    property bool apart: false
    property bool spoiler: false
    property bool viewOnce: false
    property bool isPrivate: false      // true only for regular 1-on-1 private chats (not group/channel/saved/bot)
    property bool canOnline: false      // true when "Onlayn bo'lganda yuborish" is available
    property bool textBarred: false
    property var rights: null
    property string initialMode: ""     // "" | "silent" | "schedule" | "online"
    property bool cropMode: false
    property bool emojiOpen: false
    property bool sendMenuOpen: false
    property int dragIdx: -1
    property real dragStartX: 0

    property alias captionText: captionField.text

    signal sendBatch(var picked, var caption, var opts)
    signal refused(string text)

    readonly property real bottomLift: Math.max(osk.h, safe.bottom)
    readonly property bool mayPhotos: !rights || rights.photos
    readonly property bool mayVideos: !rights || rights.videos
    readonly property bool mayFiles: !rights || rights.files
    readonly property var current: (activeIndex >= 0 && activeIndex < items.length) ? items[activeIndex] : null
    readonly property bool currentIsGif: !!(current && current.kind === "photo" && (current.path || "").toLowerCase().endsWith(".gif"))
    readonly property bool currentEditablePhoto: !!(current && current.kind === "photo" && !currentIsGif && !asFiles)
    readonly property bool hasVisualMedia: items.some((f) => f.kind === "photo" || f.kind === "video")
    readonly property bool hasPhotoOrVideo: items.some((f) => (f.kind === "photo" && !(f.path || "").toLowerCase().endsWith(".gif")) || f.kind === "video")
    readonly property int albumEligibleCount: items.filter((f) => (f.kind === "photo" && !(f.path || "").toLowerCase().endsWith(".gif")) || f.kind === "video").length
    readonly property bool canViewOnce: isPrivate && !asFiles && hasPhotoOrVideo
    readonly property bool canAlbumToggle: !asFiles && !viewOnce && albumEligibleCount >= 2

    readonly property var quickEmojis: {
        const raw = (EmojiData.categories && EmojiData.categories.length) ? EmojiData.categories[0].list : ""
        return raw ? raw.split(" ").slice(0, 32) : ["😀", "😂", "❤️", "🔥", "👍", "😍", "🎉", "🙏"]
    }

    readonly property var sendMenuItems: {
        const a = [
            { key: "silent", text: Tr.t("Ovozsiz yuborish"), icon: "belloff" },
            { key: "schedule", text: Tr.t("Rejalashtirish"), icon: "timer" }
        ]
        if (canOnline)
            a.push({ key: "online", text: Tr.t("Onlayn bo'lganda yuborish"), icon: "person" })
        return a
    }

    function show(picked, initialCaption, initAsFiles, initApart, initMode) {
        const list = (picked || []).filter((f) => f && f.path).map((f) => ({
            path: f.path,
            origPath: f.path,
            name: f.name || (f.path.split("/").pop() || "file"),
            size: f.size || 0,
            kind: f.kind || "file",
            w: f.w || 0,
            h: f.h || 0,
            spoiler: !!f.spoiler,
            rot: 0,
            cx: 0.0, cy: 0.0, cw: 1.0, ch: 1.0,
            cropKey: "orig"
        }))
        if (!list.length)
            return
        items = list
        activeIndex = 0
        const hasVis = list.some((f) => f.kind === "photo" || f.kind === "video")
        asFiles = !!initAsFiles || !hasVis
        apart = !!initApart
        spoiler = !asFiles && list.some((f) => f.spoiler)
        viewOnce = false
        initialMode = initMode || ""
        cropMode = false
        emojiOpen = false
        sendMenuOpen = false
        dragIdx = -1
        captionField.text = textBarred ? "" : (initialCaption || "")
        fall.stop()
        rise.stop()
        open = true
        visible = true
        panel.y = height
        rise.to = height - panel.height
        rise.restart()
        shade.restart()
    }

    function close() {
        if (!open)
            return
        open = false
        cropMode = false
        emojiOpen = false
        sendMenuOpen = false
        captionField.focus = false
        if (osk.h > 0)
            osk.hide()
        rise.stop()
        fall.to = height
        fall.restart()
    }

    function closeNow() {
        open = false
        cropMode = false
        emojiOpen = false
        sendMenuOpen = false
        captionField.focus = false
        rise.stop()
        fall.stop()
        dim.opacity = 0
        visible = false
    }

    function moveItem(from, to) {
        if (from < 0 || from >= items.length || to < 0 || to >= items.length || from === to)
            return
        const arr = items.slice()
        const moved = arr.splice(from, 1)[0]
        arr.splice(to, 0, moved)
        items = arr
        activeIndex = to
    }

    function removeItem(idx) {
        if (idx < 0 || idx >= items.length)
            return
        const arr = items.slice()
        arr.splice(idx, 1)
        if (!arr.length) {
            items = []
            close()
            return
        }
        items = arr
        if (activeIndex >= arr.length)
            activeIndex = arr.length - 1
        if (!hasPhotoOrVideo && viewOnce)
            viewOnce = false
        if (!hasVisualMedia) {
            asFiles = true
            spoiler = false
            cropMode = false
        }
    }

    function rotateActive() {
        if (!currentEditablePhoto)
            return
        const arr = items.slice()
        const it = Object.assign({}, arr[activeIndex])
        it.rot = (it.rot + 90) % 360
        it.cx = 0.0; it.cy = 0.0; it.cw = 1.0; it.ch = 1.0; it.cropKey = "orig"
        arr[activeIndex] = it
        items = arr
    }

    function setCropPreset(key) {
        if (!currentEditablePhoto)
            return
        const arr = items.slice()
        const it = Object.assign({}, arr[activeIndex])
        const swapped = (it.rot === 90 || it.rot === 270)
        const rw = Math.max(1, swapped ? (it.h || 960) : (it.w || 1280))
        const rh = Math.max(1, swapped ? (it.w || 1280) : (it.h || 960))
        const imgAspect = rw / rh
        let target = 0
        if (key === "1:1") target = 1.0
        else if (key === "4:3") target = 4.0 / 3.0
        else if (key === "16:9") target = 16.0 / 9.0
        else if (key === "3:4") target = 3.0 / 4.0
        if (!target) {
            it.cx = 0.0; it.cy = 0.0; it.cw = 1.0; it.ch = 1.0; it.cropKey = "orig"
        } else if (target > imgAspect) {
            const ch = Math.max(0.1, Math.min(1.0, imgAspect / target))
            it.cx = 0.0; it.cw = 1.0
            it.cy = (1.0 - ch) / 2.0; it.ch = ch
            it.cropKey = key
        } else {
            const cw = Math.max(0.1, Math.min(1.0, target / imgAspect))
            it.cy = 0.0; it.ch = 1.0
            it.cx = (1.0 - cw) / 2.0; it.cw = cw
            it.cropKey = key
        }
        arr[activeIndex] = it
        items = arr
    }

    function toggleAsFiles() {
        if (!asFiles) {
            if (!mayFiles) {
                refused(rights && rights.mine
                        ? Tr.f("Adminlar sizga bu guruhda %1 yuborishni cheklagan", Tr.t("fayl"))
                        : Tr.f("Bu guruhda %1 yuborib bo'lmaydi", Tr.t("fayl")))
                return
            }
            asFiles = true
            spoiler = false
            viewOnce = false
            cropMode = false
        } else {
            if (!hasVisualMedia)
                return
            if (!mayPhotos && !mayVideos) {
                refused(rights && rights.mine
                        ? Tr.f("Adminlar sizga bu guruhda %1 yuborishni cheklagan", Tr.t("media"))
                        : Tr.f("Bu guruhda %1 yuborib bo'lmaydi", Tr.t("media")))
                return
            }
            asFiles = false
        }
    }

    function toggleSpoiler() {
        if (asFiles || !hasVisualMedia)
            return
        spoiler = !spoiler
    }

    function toggleApart() {
        if (!canAlbumToggle)
            return
        apart = !apart
    }

    function toggleViewOnce() {
        if (!canViewOnce)
            return
        viewOnce = !viewOnce
        if (viewOnce)
            apart = true
    }

    function insertEmoji(e) {
        if (textBarred || !e)
            return
        const pos = captionField.cursorPosition
        const t = captionField.text
        captionField.text = t.slice(0, pos) + e + t.slice(pos)
        captionField.cursorPosition = pos + e.length
    }

    function formatSize(bytes) {
        if (!bytes || bytes <= 0)
            return ""
        if (bytes < 1024)
            return bytes + " B"
        if (bytes < 1048576)
            return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / 1048576).toFixed(1) + " MB"
    }

    function commitSend(modeOverride) {
        if (!items.length)
            return
        const mode = modeOverride !== undefined && modeOverride !== "" ? modeOverride : initialMode
        const out = []
        for (let k = 0; k < items.length; k++) {
            const it = items[k]
            let finalPath = it.origPath
            let fw = it.w
            let fh = it.h
            const isPhoto = it.kind === "photo" && !(it.origPath || "").toLowerCase().endsWith(".gif")
            const edited = isPhoto && (it.rot !== 0 || it.cx > 0.001 || it.cy > 0.001 || it.cw < 0.999 || it.ch < 0.999)
            if (!asFiles && edited && typeof ink !== "undefined" && ink.editPhoto) {
                const res = ink.editPhoto(it.origPath, it.rot, it.cx, it.cy, it.cw, it.ch)
                if (res && res.path) {
                    finalPath = res.path
                    if (res.w > 0) fw = res.w
                    if (res.h > 0) fh = res.h
                }
            }
            out.push({
                path: finalPath,
                name: it.name,
                size: it.size,
                kind: it.kind,
                w: fw,
                h: fh,
                spoiler: !asFiles && spoiler && (it.kind === "photo" || it.kind === "video")
            })
        }
        const rawCap = textBarred ? "" : captionField.text.trim()
        const cap = rawCap ? { text: rawCap, marks: [] } : null
        const opts = {
            asFiles: asFiles,
            apart: apart || viewOnce,
            viewOnce: canViewOnce && viewOnce,
            mode: mode
        }
        if (mode === "schedule")
            closeNow()
        else
            close()
        sendBatch(out, cap, opts)
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (sheet.sendMenuOpen)
                    sheet.sendMenuOpen = false
                else if (sheet.cropMode)
                    sheet.cropMode = false
                else
                    sheet.close()
            }
        }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.5; duration: 260 }

    Rectangle {
        id: panel
        width: parent.width
        height: Math.min(parent.height - 24, Math.round(parent.height * 0.88))
        y: sheet.open ? parent.height - height : parent.height
        radius: 16
        color: Theme.bg
        clip: true
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (sheet.sendMenuOpen)
                    sheet.sendMenuOpen = false
            }
        }

        // Top drag handle
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            width: 36; height: 4.5; radius: 2.25
            color: Theme.separator
        }

        // Header bar
        Item {
            id: head
            x: 0; y: 14
            width: parent.width; height: 44

            Icon {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                name: sheet.cropMode ? "back" : "cross"
                color: Theme.grey
                MouseArea {
                    anchors.fill: parent; anchors.margins: -10
                    onClicked: {
                        if (sheet.cropMode)
                            sheet.cropMode = false
                        else
                            sheet.close()
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 150
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: sheet.cropMode ? Tr.t("Qirqish")
                      : sheet.items.length > 1 ? Tr.f("%1 ta tanlandi", sheet.items.length)
                      : (sheet.current ? sheet.current.name : Tr.t("Yuborish"))
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }

            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: sheet.currentEditablePhoto

                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: rotHit.pressed ? Theme.highlight : "transparent"
                    Icon { anchors.centerIn: parent; width: 20; height: 20; name: "rotate"; color: Theme.accent }
                    MouseArea {
                        id: rotHit
                        anchors.fill: parent; anchors.margins: -4
                        onClicked: sheet.rotateActive()
                    }
                }

                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: sheet.cropMode ? Theme.accent : (cropHit.pressed ? Theme.highlight : "transparent")
                    Icon {
                        anchors.centerIn: parent; width: 19; height: 19
                        name: "crop"
                        color: sheet.cropMode ? "white" : Theme.accent
                    }
                    MouseArea {
                        id: cropHit
                        anchors.fill: parent; anchors.margins: -4
                        onClicked: {
                            sheet.emojiOpen = false
                            sheet.sendMenuOpen = false
                            sheet.cropMode = !sheet.cropMode
                        }
                    }
                }
            }
        }

        // Main Preview Stage
        Item {
            id: stage
            anchors.top: head.bottom; anchors.topMargin: 4
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.bottom: lowerArea.top; anchors.bottomMargin: 8
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: Theme.dark ? "#16181c" : "#eef1f5"
            }

            // Visual preview (photo / GIF / video thumbnail)
            Item {
                id: picHolder
                anchors.fill: parent; anchors.margins: 8
                visible: !!(sheet.current && (sheet.current.kind === "photo" || sheet.current.kind === "video"))

                Image {
                    id: previewImg
                    anchors.centerIn: parent
                    readonly property bool swapped: !!(sheet.current && (sheet.current.rot === 90 || sheet.current.rot === 270))
                    width: swapped ? parent.height : parent.width
                    height: swapped ? parent.width : parent.height
                    rotation: sheet.current ? sheet.current.rot : 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(720, 720)
                    source: sheet.current ? ("image://thumb/" + sheet.current.origPath) : ""

                    // Crop overlay frame (shown in cropMode or when a crop preset is active)
                    Item {
                        id: cropOverlay
                        readonly property real pw: previewImg.paintedWidth
                        readonly property real ph: previewImg.paintedHeight
                        readonly property bool hasCrop: !!(sheet.current && sheet.current.cropKey !== "orig")
                        visible: sheet.currentEditablePhoto && pw > 2 && ph > 2 && (sheet.cropMode || hasCrop)
                        anchors.centerIn: parent
                        // Account for image rotation when mapping normalized crop rect (which is in post-rotation space)
                        width: previewImg.swapped ? ph : pw
                        height: previewImg.swapped ? pw : ph
                        rotation: -(sheet.current ? sheet.current.rot : 0)

                        readonly property real rx: sheet.current ? sheet.current.cx * width : 0
                        readonly property real ry: sheet.current ? sheet.current.cy * height : 0
                        readonly property real rw: sheet.current ? sheet.current.cw * width : width
                        readonly property real rh: sheet.current ? sheet.current.ch * height : height

                        // Dark masks outside crop area
                        Rectangle { x: 0; y: 0; width: parent.width; height: parent.ry; color: Qt.rgba(0, 0, 0, 0.55) }
                        Rectangle { x: 0; y: parent.ry + parent.rh; width: parent.width; height: Math.max(0, parent.height - y); color: Qt.rgba(0, 0, 0, 0.55) }
                        Rectangle { x: 0; y: parent.ry; width: parent.rx; height: parent.rh; color: Qt.rgba(0, 0, 0, 0.55) }
                        Rectangle { x: parent.rx + parent.rw; y: parent.ry; width: Math.max(0, parent.width - x); height: parent.rh; color: Qt.rgba(0, 0, 0, 0.55) }

                        Rectangle {
                            x: parent.rx; y: parent.ry; width: parent.rw; height: parent.rh
                            color: "transparent"
                            border.color: "white"; border.width: 2
                        }
                    }
                }

                // Spoiler shimmer veil over preview
                Loader {
                    anchors.fill: parent
                    active: !sheet.asFiles && sheet.spoiler && !sheet.cropMode && !!sheet.current && (sheet.current.kind === "photo" || sheet.current.kind === "video")
                    sourceComponent: Veil {
                        corner: "12"
                        pic: sheet.current ? sheet.current.origPath : ""
                        live: sheet.visible
                    }
                }

                // Video play emblem
                Rectangle {
                    visible: !!(sheet.current && sheet.current.kind === "video" && !sheet.asFiles && !sheet.spoiler)
                    anchors.centerIn: parent
                    width: 48; height: 48; radius: 24
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Icon { anchors.centerIn: parent; width: 22; height: 22; name: "play"; color: "white" }
                }

                // Top-left status badges (index, rotation, crop, GIF, file mode)
                Row {
                    x: 4; y: 4
                    spacing: 6
                    Rectangle {
                        visible: sheet.items.length > 1
                        width: idxLbl.implicitWidth + 14; height: 22; radius: 11
                        color: Qt.rgba(0, 0, 0, 0.58)
                        Text {
                            id: idxLbl
                            anchors.centerIn: parent
                            text: (sheet.activeIndex + 1) + " / " + sheet.items.length
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: sheet.asFiles
                        width: fileBadgeLbl.implicitWidth + 14; height: 22; radius: 11
                        color: Qt.rgba(0, 0, 0, 0.65)
                        Text {
                            id: fileBadgeLbl
                            anchors.centerIn: parent
                            text: Tr.t("Fayl (asl sifat)")
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: !!(sheet.current && sheet.current.rot > 0 && !sheet.asFiles)
                        width: rotLbl.implicitWidth + 12; height: 22; radius: 11
                        color: Qt.rgba(0, 0, 0, 0.58)
                        Text {
                            id: rotLbl
                            anchors.centerIn: parent
                            text: sheet.current ? (sheet.current.rot + "°") : ""
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                    Rectangle {
                        visible: !!(sheet.current && sheet.current.cropKey !== "orig" && !sheet.asFiles)
                        width: cropLbl.implicitWidth + 12; height: 22; radius: 11
                        color: Theme.accent
                        Text {
                            id: cropLbl
                            anchors.centerIn: parent
                            text: sheet.current ? sheet.current.cropKey : ""
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                }

                // View-once badge in top-right of preview
                Rectangle {
                    visible: sheet.canViewOnce && sheet.viewOnce
                    anchors.right: parent.right; anchors.rightMargin: 4
                    y: 4
                    width: voLbl.implicitWidth + 18; height: 24; radius: 12
                    color: Theme.accent
                    Text {
                        id: voLbl
                        anchors.centerIn: parent
                        text: "① " + Tr.t("Bir martalik")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                }
            }

            // Non-media file card preview
            Column {
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 10
                visible: !!(sheet.current && sheet.current.kind !== "photo" && sheet.current.kind !== "video")
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64; radius: 32
                    color: Theme.accent
                    Icon { anchors.centerIn: parent; width: 28; height: 28; name: "clip"; color: "white" }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: sheet.current ? sheet.current.name : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: sheet.current ? sheet.formatSize(sheet.current.size) : ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
        }

        // Lower controls area (crop presets OR thumbnail strip + options + emoji tray + caption bar)
        Column {
            id: lowerArea
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: sheet.bottomLift

            // Crop preset toolbar (only when cropMode is active)
            Item {
                visible: sheet.cropMode && sheet.currentEditablePhoto
                width: parent.width; height: 54
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Repeater {
                        model: [
                            { key: "orig", label: Tr.t("Asl") },
                            { key: "1:1", label: "1:1" },
                            { key: "4:3", label: "4:3" },
                            { key: "16:9", label: "16:9" },
                            { key: "3:4", label: "3:4" }
                        ]
                        Rectangle {
                            id: cropBtn
                            required property var modelData
                            readonly property bool on: !!(sheet.current && sheet.current.cropKey === modelData.key)
                            width: Math.max(46, cropBtnText.implicitWidth + 18); height: 32; radius: 16
                            color: on ? Theme.accent : Theme.highlight
                            Text {
                                id: cropBtnText
                                anchors.centerIn: parent
                                text: cropBtn.modelData.label
                                color: cropBtn.on ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; onClicked: sheet.setCropPreset(cropBtn.modelData.key) }
                        }
                    }
                    Rectangle {
                        width: doneCropText.implicitWidth + 20; height: 32; radius: 16
                        color: Theme.accent
                        Text {
                            id: doneCropText
                            anchors.centerIn: parent
                            text: Tr.t("Tayyor")
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        MouseArea { anchors.fill: parent; onClicked: sheet.cropMode = false }
                    }
                }
            }

            // Thumbnail strip + reorder (<- / ->) buttons (hidden when keyboard open or cropMode)
            Item {
                id: stripWrap
                visible: !sheet.cropMode && osk.h === 0 && sheet.items.length > 0
                width: parent.width
                height: sheet.items.length > 1 ? 82 : 76

                // Reorder left button (when 2+ items)
                Rectangle {
                    id: moveLeftBtn
                    visible: sheet.items.length > 1
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 52; radius: 10
                    color: Theme.highlight
                    opacity: sheet.activeIndex > 0 ? (mlHit.pressed ? 0.55 : 1) : 0.32
                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold
                    }
                    MouseArea {
                        id: mlHit
                        anchors.fill: parent
                        enabled: sheet.activeIndex > 0
                        onClicked: sheet.moveItem(sheet.activeIndex, sheet.activeIndex - 1)
                    }
                }

                // Reorder right button (when 2+ items)
                Rectangle {
                    id: moveRightBtn
                    visible: sheet.items.length > 1
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 52; radius: 10
                    color: Theme.highlight
                    opacity: sheet.activeIndex < sheet.items.length - 1 ? (mrHit.pressed ? 0.55 : 1) : 0.32
                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold
                    }
                    MouseArea {
                        id: mrHit
                        anchors.fill: parent
                        enabled: sheet.activeIndex < sheet.items.length - 1
                        onClicked: sheet.moveItem(sheet.activeIndex, sheet.activeIndex + 1)
                    }
                }

                ListView {
                    id: thumbList
                    anchors.top: parent.top; anchors.topMargin: 6
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    anchors.left: moveLeftBtn.visible ? moveLeftBtn.right : parent.left
                    anchors.leftMargin: moveLeftBtn.visible ? 8 : 12
                    anchors.right: moveRightBtn.visible ? moveRightBtn.left : parent.right
                    anchors.rightMargin: moveRightBtn.visible ? 8 : 12
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    interactive: sheet.dragIdx < 0
                    model: sheet.items
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: 64; height: 64
                        readonly property bool active: index === sheet.activeIndex
                        scale: sheet.dragIdx === index ? 1.07 : 1.0
                        Behavior on scale { ScaleAnimator { duration: 120 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Theme.highlight
                            border.color: cell.active ? Theme.accent : Theme.separator
                            border.width: cell.active ? 2.5 : 0.8
                            clip: true

                            Image {
                                anchors.fill: parent; anchors.margins: cell.active ? 2 : 1
                                visible: cell.modelData.kind === "photo" || cell.modelData.kind === "video"
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                rotation: cell.modelData.rot || 0
                                sourceSize: Qt.size(128, 128)
                                source: "image://thumb/" + cell.modelData.origPath
                            }

                            Icon {
                                visible: cell.modelData.kind !== "photo" && cell.modelData.kind !== "video"
                                anchors.centerIn: parent
                                width: 22; height: 22
                                name: "clip"
                                color: Theme.accent
                            }

                            Rectangle {
                                anchors.fill: parent; anchors.margins: 2
                                radius: 8
                                visible: !sheet.asFiles && sheet.spoiler && (cell.modelData.kind === "photo" || cell.modelData.kind === "video")
                                color: Qt.rgba(0, 0, 0, 0.45)
                                Icon {
                                    anchors.centerIn: parent
                                    width: 18; height: 18
                                    name: "eyeoff"
                                    color: "white"
                                }
                            }

                            // Order number badge (top-left)
                            Rectangle {
                                x: 4; y: 4
                                width: 18; height: 18; radius: 9
                                color: cell.active ? Theme.accent : Qt.rgba(0, 0, 0, 0.55)
                                Text {
                                    anchors.centerIn: parent
                                    text: cell.index + 1
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }

                            // Video play mini badge
                            Rectangle {
                                visible: cell.modelData.kind === "video"
                                x: 4; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                width: 18; height: 14; radius: 7
                                color: Qt.rgba(0, 0, 0, 0.58)
                                Icon { anchors.centerIn: parent; width: 9; height: 9; name: "play"; color: "white" }
                            }

                            MouseArea {
                                anchors.fill: parent
                                pressAndHoldInterval: 320
                                onClicked: sheet.activeIndex = cell.index
                                onPressAndHold: (m) => {
                                    sheet.activeIndex = cell.index
                                    sheet.dragIdx = cell.index
                                    sheet.dragStartX = mapToItem(thumbList, m.x, m.y).x
                                }
                                onPositionChanged: (m) => {
                                    if (sheet.dragIdx < 0)
                                        return
                                    const curX = mapToItem(thumbList, m.x, m.y).x
                                    const dx = curX - sheet.dragStartX
                                    if (dx > 38 && sheet.dragIdx < sheet.items.length - 1) {
                                        sheet.moveItem(sheet.dragIdx, sheet.dragIdx + 1)
                                        sheet.dragIdx = sheet.activeIndex
                                        sheet.dragStartX = curX
                                    } else if (dx < -38 && sheet.dragIdx > 0) {
                                        sheet.moveItem(sheet.dragIdx, sheet.dragIdx - 1)
                                        sheet.dragIdx = sheet.activeIndex
                                        sheet.dragStartX = curX
                                    }
                                }
                                onReleased: sheet.dragIdx = -1
                                onCanceled: sheet.dragIdx = -1
                            }

                            // Remove item (X) button (top-right)
                            Rectangle {
                                anchors.right: parent.right; anchors.rightMargin: 3
                                y: 3
                                width: 20; height: 20; radius: 10
                                color: Qt.rgba(0, 0, 0, 0.65)
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: "white"
                                    font.pixelSize: 10; font.weight: Font.Bold
                                }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -4
                                    onClicked: sheet.removeItem(cell.index)
                                }
                            }
                        }
                    }
                }
            }

            // Options chips bar (Compress/File, Spoiler, Album/Separate, View-once)
            Flickable {
                id: optFlick
                visible: !sheet.cropMode
                width: parent.width; height: 42
                contentWidth: optRow.implicitWidth + 24
                flickableDirection: Flickable.HorizontalFlick
                clip: true

                Row {
                    id: optRow
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Quality: Siqib yuborish / Asl sifatda (fayl)
                    Rectangle {
                        id: qualityChip
                        visible: sheet.hasVisualMedia
                        width: qRow.implicitWidth + 14; height: 30; radius: 15
                        color: sheet.asFiles ? Theme.accent : Theme.highlight
                        Row {
                            id: qRow
                            anchors.centerIn: parent
                            spacing: 4
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13; height: 13
                                name: sheet.asFiles ? "clip" : "expand"
                                color: sheet.asFiles ? "white" : Theme.text
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: sheet.asFiles ? Tr.t("Asl sifatda (fayl)") : Tr.t("Siqib yuborish")
                                color: sheet.asFiles ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: sheet.toggleAsFiles() }
                    }

                    // Spoiler
                    Rectangle {
                        id: spoilerChip
                        visible: !sheet.asFiles && sheet.hasVisualMedia
                        width: spRow.implicitWidth + 14; height: 30; radius: 15
                        color: sheet.spoiler ? Theme.accent : Theme.highlight
                        Row {
                            id: spRow
                            anchors.centerIn: parent
                            spacing: 4
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13; height: 13
                                name: "eyeoff"
                                color: sheet.spoiler ? "white" : Theme.text
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Tr.t("Spoiler bilan")
                                color: sheet.spoiler ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: sheet.toggleSpoiler() }
                    }

                    // Album vs Separate (2+ media)
                    Rectangle {
                        id: albumChip
                        visible: sheet.canAlbumToggle
                        width: albRow.implicitWidth + 14; height: 30; radius: 15
                        color: sheet.apart ? Theme.accent : Theme.highlight
                        Row {
                            id: albRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: sheet.apart ? Tr.t("Alohida") : Tr.t("Albom qilib")
                                color: sheet.apart ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: sheet.toggleApart() }
                    }

                    // View-once (private 1-on-1 chat only, photo/video only)
                    Rectangle {
                        id: viewOnceChip
                        visible: sheet.canViewOnce
                        width: voRow.implicitWidth + 14; height: 30; radius: 15
                        color: sheet.viewOnce ? Theme.accent : Theme.highlight
                        Row {
                            id: voRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "①"
                                color: sheet.viewOnce ? "white" : Theme.accent
                                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Tr.t("Bir martalik")
                                color: sheet.viewOnce ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: sheet.toggleViewOnce() }
                    }
                }
            }

            // Inline quick emoji tray (toggled by smiley button)
            Rectangle {
                visible: sheet.emojiOpen && !sheet.cropMode && !sheet.textBarred
                width: parent.width; height: 46
                color: Theme.highlight
                Flickable {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                    contentWidth: emoRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    Row {
                        id: emoRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: sheet.quickEmojis
                            Rectangle {
                                id: emoCell
                                required property string modelData
                                width: 38; height: 38; radius: 19
                                color: emoHit.pressed ? Theme.separator : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: emoCell.modelData
                                    font.pixelSize: 22
                                }
                                MouseArea {
                                    id: emoHit
                                    anchors.fill: parent
                                    onClicked: sheet.insertEmoji(emoCell.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Separator above caption bar
            Rectangle {
                width: parent.width; height: 0.5
                color: Theme.separator
            }

            // Caption + Emoji + Send bar
            Item {
                id: composeBar
                width: parent.width
                height: Math.max(56, captionBox.height + 16)

                Rectangle {
                    id: captionBox
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.right: sendBtn.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.min(92, Math.max(40, captionField.contentHeight + 18))
                    radius: 20
                    color: Theme.highlight
                    opacity: sheet.textBarred ? 0.5 : 1

                    // Emoji toggle button
                    Item {
                        id: emoToggle
                        visible: !sheet.textBarred
                        x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        width: 24; height: 24
                        Text {
                            anchors.centerIn: parent
                            text: "☺"
                            color: sheet.emojiOpen ? Theme.accent : Theme.grey
                            font.pixelSize: 20
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            onClicked: {
                                sheet.sendMenuOpen = false
                                sheet.emojiOpen = !sheet.emojiOpen
                            }
                        }
                    }

                    Flickable {
                        anchors.left: emoToggle.visible ? emoToggle.right : parent.left
                        anchors.leftMargin: emoToggle.visible ? 6 : 14
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.topMargin: 8; anchors.bottomMargin: 8
                        contentWidth: width
                        contentHeight: captionField.contentHeight
                        clip: true
                        TextEdit {
                            id: captionField
                            width: parent.width
                            enabled: !sheet.textBarred
                            color: Theme.text
                            selectionColor: Theme.accent
                            font.family: Theme.font; font.pixelSize: 15
                            wrapMode: TextEdit.Wrap
                            onActiveFocusChanged: if (activeFocus) { sheet.emojiOpen = false; sheet.sendMenuOpen = false }
                            Text {
                                visible: captionField.text.length === 0
                                text: Tr.t("Izoh qo'shish…")
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 15
                            }
                        }
                    }
                }

                // Send button (tap: send, long-press: Silent / Schedule / Send when online)
                Rectangle {
                    id: sendBtn
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    width: 40; height: 40; radius: 20
                    color: Theme.accent
                    scale: sendHit.pressed ? 0.92 : 1.0
                    Behavior on scale { ScaleAnimator { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "↑"
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold
                    }

                    Timer {
                        id: sendHoldTimer
                        interval: 380
                        onTriggered: {
                            sendHit.held = true
                            sheet.emojiOpen = false
                            sheet.sendMenuOpen = true
                        }
                    }

                    MouseArea {
                        id: sendHit
                        property bool held: false
                        anchors.fill: parent; anchors.margins: -4
                        onPressed: {
                            held = false
                            sendHoldTimer.restart()
                        }
                        onReleased: sendHoldTimer.stop()
                        onCanceled: sendHoldTimer.stop()
                        onClicked: {
                            if (held)
                                return
                            sheet.commitSend("")
                        }
                    }
                }
            }
        }

        // Send long-press menu (Silent, Schedule, Send When Online)
        MouseArea {
            anchors.fill: parent
            visible: sheet.sendMenuOpen
            onClicked: sheet.sendMenuOpen = false
        }
        Rectangle {
            id: sendPopup
            visible: sheet.sendMenuOpen
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: sheet.bottomLift + composeBar.height + 6
            width: 268
            height: sendPopupCol.implicitHeight
            radius: 14
            color: Theme.menu
            border.color: Theme.separator; border.width: 0.5
            clip: true

            Column {
                id: sendPopupCol
                width: parent.width
                Repeater {
                    model: sheet.sendMenuItems
                    Rectangle {
                        id: spItem
                        required property var modelData
                        required property int index
                        width: sendPopupCol.width; height: 46
                        color: spHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { visible: spItem.index > 0; width: parent.width; height: 0.5; color: Theme.separator }
                        Icon {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            name: spItem.modelData.icon
                            color: Theme.text
                        }
                        Text {
                            x: 44; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 54
                            elide: Text.ElideRight
                            text: spItem.modelData.text
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 15
                        }
                        MouseArea {
                            id: spHit
                            anchors.fill: parent
                            onClicked: {
                                sheet.sendMenuOpen = false
                                sheet.commitSend(spItem.modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }

    YAnimator {
        id: rise
        target: panel
        duration: 360
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]
    }
    ParallelAnimation {
        id: fall
        property alias to: down.to
        YAnimator { id: down; target: panel; duration: 220; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 220 }
        onFinished: sheet.visible = false
    }
}
