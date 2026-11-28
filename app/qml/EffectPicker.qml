pragma ComponentBehavior: Bound
// Message effect picker bottom sheet (1.0): lists effects from TDLib's updateAvailableMessageEffects
// (reaction_effect_ids + sticker_effect_ids), loads each via getMessageEffect, shows static icon or
// emoji preview, marks Premium effects with a lock for non-Premium users, and emits picked(effectId).
// Respects safe.bottom and day/night ztMETRO Theme.
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 32

    property var store: null
    property bool isPremium: false
    property real safeBottom: 0
    property bool open: false

    property var entries: []            // [{ id, emoji, isPremium, iconPath, loading }]
    property var iconPaths: ({})        // effectId -> local file path
    property int iconTick: 0
    property bool loading: false
    property int _reqId: 0

    signal picked(string effectId)
    signal premiumNeeded()
    signal closed()

    function show() {
        open = true
        visible = true
        fall.stop()
        shade.stop()
        panelSlide.y = panel.height
        dim.opacity = 0
        rise.from = panel.height
        rise.restart()
        shade.restart()
        loadEffects()
    }

    function close() {
        if (!open)
            return
        open = false
        _reqId++
        rise.stop()
        shade.stop()
        fallY.to = panel.height
        fall.restart()
        closed()
    }

    function dismiss() {
        if (open) {
            close()
            return true
        }
        return false
    }

    function loadEffects() {
        if (!store)
            return
        const ids = store.availableEffectIds || []
        const rSet = ({})
        for (const rid of (store.reactionEffectIds || []))
            rSet[String(rid)] = true
        if (!ids.length) {
            entries = []
            loading = false
            return
        }
        const req = ++_reqId
        let pending = 0
        const list = ids.map((rawId) => {
            const id = String(rawId)
            const cached = store.cachedMessageEffect(id)
            if (cached)
                maybeFetchIcon(id, cached)
            else
                pending++
            return {
                id: id,
                emoji: cached && cached.emoji ? String(cached.emoji) : "✨",
                isPremium: cached ? !!cached.is_premium : !rSet[id],
                ready: !!cached
            }
        })
        entries = list
        loading = pending > 0

        for (const id of ids) {
            const sid = String(id)
            if (store.cachedMessageEffect(sid))
                continue
            store.getMessageEffect(sid, (eff, err) => {
                if (!sheet || req !== sheet._reqId || !sheet.open)
                    return
                if (eff)
                    sheet.maybeFetchIcon(sid, eff)
                // (gathered, and the grid's model replaced once a frame, not once an answer: with
                // Telegram's ~100 effects one replace each rebuilt every cell ~100 times -- seconds
                // of a big core and ~150 MB, more on the phone's GPU)
                sheet._came[sid] = eff || null
                if (!sheet._flushQueued) {
                    sheet._flushQueued = true
                    Qt.callLater(sheet._flush, req)
                }
            })
        }
    }

    property var _came: ({})            // effectId -> its messageEffect (null: failed), not yet in entries
    property bool _flushQueued: false
    property bool _tickQueued: false
    function _flush(req) {
        _flushQueued = false
        if (req !== _reqId || !open)
            return
        const came = _came
        _came = ({})
        const next = entries.map((e) => {
            if (!(e.id in came))
                return e
            const eff = came[e.id]
            return { id: e.id, emoji: eff && eff.emoji ? String(eff.emoji) : e.emoji,
                     isPremium: eff ? !!eff.is_premium : e.isPremium, ready: true }
        })
        entries = next
        if (next.every((e) => e.ready))
            loading = false
    }

    function maybeFetchIcon(id, eff) {
        if (!store || !eff || iconPaths[id] !== undefined)
            return
        const st = eff.static_icon
        let f = null
        if (st && st.sticker && st.format && st.format["@type"] === "stickerFormatWebp")
            f = st.sticker
        else if (st && st.thumbnail && st.thumbnail.file)
            f = st.thumbnail.file
        if (!f)
            return
        iconPaths[id] = ""
        store.fetch(f, 8, (path) => {
            if (!sheet || !path)
                return
            sheet.iconPaths[id] = path
            if (!sheet._tickQueued) { sheet._tickQueued = true; Qt.callLater(() => { if (sheet) { sheet._tickQueued = false; sheet.iconTick++ } }) }
        })
    }

    function tapEffect(item) {
        if (!item)
            return
        if (item.isPremium && !isPremium) {
            premiumNeeded()
            return
        }
        const id = item.id
        close()
        picked(id)
    }

    Connections {
        target: sheet.store
        enabled: sheet.open && sheet.store !== null
        function onMsgEffectsRevChanged() {
            if (sheet.open && sheet.entries.length === 0 && (sheet.store.availableEffectIds || []).length > 0)
                sheet.loadEffects()
        }
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        readonly property real gridContentH: Math.min(280, Math.max(96, grid.contentHeight))
        height: Math.min(sheet.height * 0.72, 92 + (sheet.entries.length ? gridContentH : 76) + 18 + sheet.safeBottom)
        radius: 18
        color: Theme.bg
        clip: true
        transform: Translate { id: panelSlide; y: panel.height }

        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 18; color: Theme.bg
        }
        MouseArea { anchors.fill: parent }

        // Handle pill
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8; width: 36; height: 4; radius: 2
            color: Theme.grey; opacity: 0.35
        }

        // Header
        Item {
            id: hdr
            x: 16; y: 20
            width: parent.width - 32; height: 52
            Column {
                anchors.left: parent.left
                anchors.right: closeBtn.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: Tr.t("Xabar effekti")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Tr.t("Suhbatdosh xabarni ochganda effekt ko'rinadi")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            Rectangle {
                id: closeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: closeHit.pressed ? Theme.highlight : Theme.card
                Icon { anchors.centerIn: parent; width: 14; height: 14; name: "cross"; color: Theme.grey }
                MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.close() }
            }
        }

        // Empty state
        Text {
            visible: sheet.entries.length === 0 && !sheet.loading
            anchors.horizontalCenter: parent.horizontalCenter
            y: hdr.y + hdr.height + 24
            text: Tr.t("Effektlar mavjud emas")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }

        // Effects grid (4 columns)
        GridView {
            id: grid
            visible: sheet.entries.length > 0
            x: 12; y: hdr.y + hdr.height + 8
            width: parent.width - 24
            height: panel.height - y - 12 - sheet.safeBottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: Math.floor(width / 4)
            cellHeight: 74
            model: sheet.entries
            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property string iconUrl: (sheet.iconTick >= 0 && sheet.iconPaths[modelData.id])
                    ? "file://" + sheet.iconPaths[modelData.id] : ""
                readonly property bool locked: !!modelData.isPremium && !sheet.isPremium

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 14
                    color: cellHit.pressed ? Theme.highlight : Theme.card
                    opacity: cell.locked ? 0.72 : 1

                    Image {
                        visible: cell.iconUrl !== "" && status === Image.Ready
                        anchors.centerIn: parent
                        width: 40; height: 40
                        source: cell.iconUrl
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }
                    Text {
                        visible: cell.iconUrl === ""
                        anchors.centerIn: parent
                        text: cell.modelData.emoji
                        font.family: Theme.font; font.pixelSize: 30
                    }

                    // Premium lock pill in corner when user is not Premium
                    Rectangle {
                        visible: cell.locked
                        anchors.right: parent.right; anchors.rightMargin: 5
                        anchors.top: parent.top; anchors.topMargin: 5
                        width: 18; height: 18; radius: 9
                        color: "#af52de"
                        Icon { anchors.centerIn: parent; width: 10; height: 10; name: "lock"; color: "white" }
                    }

                    // Subtle star dot for Premium effects when unlocked
                    Rectangle {
                        visible: !!cell.modelData.isPremium && sheet.isPremium
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.top: parent.top; anchors.topMargin: 6
                        width: 8; height: 8; radius: 4
                        color: "#af52de"
                    }

                    MouseArea {
                        id: cellHit
                        anchors.fill: parent
                        onClicked: sheet.tapEffect(cell.modelData)
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: rise
        target: panelSlide; property: "y"
        to: 0; duration: 280
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: shade
        target: dim; property: "opacity"
        to: 1; duration: 220
    }
    ParallelAnimation {
        id: fall
        NumberAnimation { id: fallY; target: panelSlide; property: "y"; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 180 }
        onFinished: if (!sheet.open) sheet.visible = false
    }
}
