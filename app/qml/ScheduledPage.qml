// Scheduled messages page for a chat (getChatScheduledMessages): messages grouped by their scheduled
// date (or «Onlayn bo'lganda»), each with Send Now (editMessageSchedulingState -> null),
// Reschedule (editMessageSchedulingState -> new date/online), and Delete (deleteMessages with confirmation).
// Includes a bottom compose bar so new text or attached files can also be scheduled right from here.
import QtQuick
import QtQuick.Window

Page {
    id: page
    required property var chatId
    readonly property real dpr: Screen.devicePixelRatio
    readonly property var chat: store.seen >= 0 ? store.chats[chatId] : null
    readonly property bool canOnline: store.seen >= 0 ? store.canScheduleOnline(chat) : false
    readonly property bool channel: !!chat && chat.type["@type"] === "chatTypeSupergroup" && chat.type.is_channel
    readonly property bool silent: channel && Prefs.silent.split(",").indexOf(String(chatId)) >= 0
    readonly property real barLift: Math.max(osk.h, safe.bottom)
    readonly property real toastFloor: barLift + inputBar.height
    readonly property var menuSpring: [0.0333, 0.0, 0.0667, 0.1058, 0.1, 0.2201, 0.14, 0.3573, 0.18, 0.5086,
                                       0.22, 0.6252, 0.28, 0.8001, 0.34, 0.9024, 0.4, 0.9553, 0.4833, 1.0287,
                                       0.5667, 1.024, 0.65, 1.0199, 0.7667, 1.0141, 0.8833, 1.0032, 1, 1.0]

    property bool loading: true
    property var rawMessages: []        // TDLib message objects
    property var activeMsg: null        // message whose action menu is open
    property var pendingAction: null    // { kind: "reschedule"|"text"|"files", ... }
    property string wallSpec: ""
    property real wallDim: 0
    property var _wallOf: null

    readonly property alias schedList: items
    readonly property var scheduleSheet: scheduleSheetLoader.item
    readonly property var attachSheet: attachSheetLoader.item
    readonly property var confirmAlert: confirmAlertLoader.item

    ListModel { id: items }             // newest/latest scheduled date first (index 0 at bottom in BottomToTop ListView)

    function rewall() {
        const c = chat
        const key = c ? JSON.stringify([c.background, c.theme, Theme.dark]) : ""
        if (key === _wallOf)
            return
        _wallOf = key
        wallSpec = Theme.wall
        store.chatWall(c, Theme.dark, (s, dim) => {
            if (page && _wallOf === key) {
                wallSpec = s
                wallDim = dim
            }
        })
    }
    Connections { target: Theme; function onDarkChanged() { page.rewall() } }

    Component.onCompleted: {
        rewall()
        reload()
    }

    function reload() {
        loading = true
        store.scheduledMessages(chatId, (got, failed) => {
            if (!page)
                return
            page.loading = false
            if (!failed) {
                page.rawMessages = got || []
                page.rebuild()
            }
        })
    }

    function sendDateOf(m) {
        const st = m && m.scheduling_state
        if (st && st["@type"] === "messageSchedulingStateSendAtDate")
            return st.send_date || m.date || 0
        return 0
    }

    function isWhenOnline(m) {
        const st = m && m.scheduling_state
        return !!st && st["@type"] === "messageSchedulingStateSendWhenOnline"
    }

    function dayKeyOf(m) {
        if (isWhenOnline(m))
            return "online"
        const sec = sendDateOf(m)
        if (!sec)
            return ""
        const d = new Date(sec * 1000)
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    function dayTitleOf(m) {
        if (isWhenOnline(m))
            return Tr.t("Onlayn bo'lganda")
        const sec = sendDateOf(m)
        if (!sec)
            return ""
        const now = new Date()
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const d = new Date(sec * 1000)
        const target = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const diff = Math.round((target - today) / 86400000)
        if (diff === 0)
            return Tr.t("Bugun")
        if (diff === 1)
            return Tr.t("Ertaga")
        return Tr.date(d.getDate(), d.getMonth() + 1, d.getFullYear() !== now.getFullYear() ? d.getFullYear() : 0)
    }

    function timeLabelOf(m) {
        if (isWhenOnline(m))
            return Tr.t("Onlayn")
        const sec = sendDateOf(m)
        return sec ? Qt.formatTime(new Date(sec * 1000), "HH:mm") : ""
    }

    function previewOf(m) {
        const c = m && m.content
        if (!c)
            return { text: "", kind: "text", fileName: "", fileSize: 0, thumb: "" }
        const t = c["@type"]
        if (t === "messageText")
            return { text: c.text ? c.text.text : "", kind: "text", fileName: "", fileSize: 0, thumb: "" }
        if (t === "messagePhoto") {
            let p = ""
            const sizes = c.photo && c.photo.sizes ? c.photo.sizes : []
            for (let i = sizes.length - 1; i >= 0; i--) {
                const lf = sizes[i].photo && sizes[i].photo.local
                if (lf && lf.path) { p = lf.path; break }
            }
            return { text: c.caption ? c.caption.text : "", kind: "photo", fileName: Tr.t("Rasm"), fileSize: 0, thumb: p }
        }
        if (t === "messageVideo") {
            const th = c.video && c.video.thumbnail && c.video.thumbnail.file && c.video.thumbnail.file.local
                       ? c.video.thumbnail.file.local.path : ""
            return { text: c.caption ? c.caption.text : "", kind: "video", fileName: c.video ? (c.video.file_name || Tr.t("Video")) : Tr.t("Video"),
                     fileSize: c.video && c.video.video ? c.video.video.expected_size || 0 : 0, thumb: th }
        }
        if (t === "messageDocument") {
            const doc = c.document || {}
            return { text: c.caption ? c.caption.text : "", kind: "file",
                     fileName: doc.file_name || Tr.t("Fayl"),
                     fileSize: doc.document ? doc.document.expected_size || doc.document.size || 0 : 0, thumb: "" }
        }
        return { text: store.preview(c, chat) || Tr.t("Xabar"), kind: "other", fileName: "", fileSize: 0, thumb: "" }
    }

    function rebuild() {
        // Order: BottomToTop ListView puts index 0 at the bottom.
        // Put dated messages chronologically (earliest at top, latest at bottom), and "when online" at the very bottom.
        const sorted = rawMessages.slice().sort((a, b) => {
            const ao = isWhenOnline(a), bo = isWhenOnline(b)
            if (ao !== bo)
                return ao ? -1 : 1
            const da = sendDateOf(a), db = sendDateOf(b)
            if (da !== db)
                return db - da
            return (b.id || 0) - (a.id || 0)
        })
        items.clear()
        for (let i = 0; i < sorted.length; i++) {
            const m = sorted[i]
            const dk = dayKeyOf(m)
            const prevDk = i + 1 < sorted.length ? dayKeyOf(sorted[i + 1]) : ""
            const p = previewOf(m)
            items.append({
                msgId: m.id,
                sendDate: sendDateOf(m),
                whenOnline: isWhenOnline(m),
                dayKey: dk,
                dayTitle: dk !== prevDk ? dayTitleOf(m) : "",
                timeText: timeLabelOf(m),
                bodyText: p.text,
                kind: p.kind,
                fileName: p.fileName,
                fileSize: p.fileSize,
                thumb: p.thumb
            })
        }
    }

    function openItemMenu(idx) {
        if (idx < 0 || idx >= items.count)
            return
        const r = items.get(idx)
        activeMsg = { id: r.msgId, sendDate: r.sendDate, whenOnline: r.whenOnline }
        osk.hide()
        actionMenu.show()
    }

    function doSendNow(msgId) {
        actionMenu.visible = false
        store.sendScheduledNow(chatId, msgId, (r) => {
            if (!page)
                return
            if (r && r["@type"] === "error")
                return page.toast(r.message || Tr.t("Bo'lmadi"))
            page.rawMessages = page.rawMessages.filter((m) => m.id !== msgId)
            page.rebuild()
            page.toast(Tr.t("Xabar yuborildi"))
        })
    }

    function openReschedule(msg) {
        actionMenu.visible = false
        pendingAction = { kind: "reschedule", msgId: msg.id }
        scheduleSheetLoader.active = true
        scheduleSheetLoader.item.show(msg.sendDate, true, canOnline)
    }

    function askDelete(msgId) {
        actionMenu.visible = false
        confirmAlertLoader.active = true
        confirmAlert.title = Tr.t("Xabarni o'chirish")
        confirmAlert.text = Tr.t("Rejalashtirilgan xabar o'chirilsinmi?")
        confirmAlert.answers = [
            { t: Tr.t("Bekor qilish") },
            { t: Tr.t("O'chirish"), red: true, run: () => {
                store.deleteScheduledMessages(page.chatId, [msgId], (r) => {
                    if (!page)
                        return
                    if (r && r["@type"] === "error")
                        return page.toast(r.message || Tr.t("Bo'lmadi"))
                    page.rawMessages = page.rawMessages.filter((m) => m.id !== msgId)
                    page.rebuild()
                    page.toast(Tr.t("Xabar o'chirildi"))
                })
            } }
        ]
        confirmAlert.open = true
    }

    function scheduleFieldText() {
        const t = composeField.text.trim()
        if (!t)
            return
        osk.hide()
        pendingAction = { kind: "text", text: t }
        scheduleSheetLoader.active = true
        scheduleSheetLoader.item.show(0, false, canOnline)
    }

    function openAttach() {
        osk.hide()
        attachSheetLoader.active = true
        attachSheetLoader.item.show()
    }

    function toast(text) {
        schedToastText.text = text
        schedToastBox.opacity = 1
        schedToastAway.restart()
    }

    function dismiss() {
        if (confirmAlert && confirmAlert.open) {
            confirmAlert.open = false
            return true
        }
        if (scheduleSheet && scheduleSheet.open) {
            scheduleSheet.close(true)
            return true
        }
        if (attachSheet && attachSheet.open) {
            attachSheet.close()
            return true
        }
        if (actionMenu.visible) {
            actionMenu.visible = false
            return true
        }
        return false
    }

    Connections {
        target: store
        function onScheduledMessage(m) {
            if (m.chat_id !== page.chatId)
                return
            const next = page.rawMessages.filter((x) => x.id !== m.id)
            next.push(m)
            page.rawMessages = next
            page.rebuild()
        }
        function onScheduledChanged(cid, oldId, m) {
            if (cid !== page.chatId)
                return
            const next = page.rawMessages.filter((x) => x.id !== oldId && x.id !== m.id)
            next.push(m)
            page.rawMessages = next
            page.rebuild()
        }
        function onScheduledDeleted(cid, ids) {
            if (cid !== page.chatId)
                return
            const before = page.rawMessages.length
            page.rawMessages = page.rawMessages.filter((m) => ids.indexOf(m.id) < 0)
            if (page.rawMessages.length !== before)
                page.rebuild()
        }
        function onScheduledSent(cid, oldId) {
            if (cid !== page.chatId)
                return
            const before = page.rawMessages.length
            page.rawMessages = page.rawMessages.filter((m) => m.id !== oldId)
            if (page.rawMessages.length !== before)
                page.rebuild()
        }
    }

    Wallpaper {
        anchors.fill: parent
        spec: page.wallSpec || Theme.wall
    }
    Rectangle {
        anchors.fill: parent
        visible: page.wallDim > 0
        color: "black"
        opacity: page.wallDim
    }

    ListView {
        id: list
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: inputBar.top
        clip: true
        verticalLayoutDirection: ListView.BottomToTop
        spacing: 4
        topMargin: 12
        bottomMargin: 12
        model: items

        delegate: Item {
            id: rowItem
            required property int index
            required property var msgId
            required property int sendDate
            required property bool whenOnline
            required property string dayTitle
            required property string timeText
            required property string bodyText
            required property string kind
            required property string fileName
            required property real fileSize
            required property string thumb

            width: list.width
            height: col.implicitHeight + 4

            Column {
                id: col
                width: parent.width
                spacing: 6

                Rectangle {
                    visible: rowItem.dayTitle !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: dayLabel.implicitWidth + 20
                    height: 24
                    radius: 12
                    color: Theme.dayPill
                    Text {
                        id: dayLabel
                        anchors.centerIn: parent
                        text: rowItem.dayTitle
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }

                Item {
                    width: parent.width
                    height: bubble.height

                    Item {
                        id: bubble
                        readonly property real maxW: Math.min(280, parent.width - 48)
                        width: Math.min(maxW, Math.max(96, contentCol.implicitWidth + 24))
                        height: contentCol.implicitHeight + 18
                        anchors.right: parent.right; anchors.rightMargin: 10
                        opacity: bubbleHit.pressed ? 0.85 : 1

                        BorderImage {
                            readonly property real d: page.dpr
                            readonly property int r: Prefs.bubbleR
                            readonly property int b: Prefs.bubbleB
                            width: (parent.width + 6) * d; height: parent.height * d
                            scale: 1 / d; transformOrigin: Item.TopLeft
                            border { left: r * d; right: (b + 6) * d; top: r * d; bottom: b * d }
                            source: "image://bubble/out/b/t/" + String(Theme.bubbleOut).slice(1) + "/" + d + "/" + r + "/" + Prefs.bubbleS
                            smooth: true
                        }

                        Column {
                            id: contentCol
                            x: 12; y: 8
                            width: Math.min(bubble.maxW - 24, Math.max(mediaBox.visible ? mediaBox.width : 0,
                                                                      fileRow.visible ? fileRow.width : 0,
                                                                      bodyLbl.visible ? bodyLbl.implicitWidth : 0,
                                                                      metaRow.implicitWidth))
                            spacing: 4

                            Item {
                                id: mediaBox
                                visible: rowItem.kind === "photo" || rowItem.kind === "video"
                                width: Math.min(bubble.maxW - 24, 220)
                                height: 132
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: Theme.highlight
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        visible: rowItem.thumb !== ""
                                        source: rowItem.thumb ? "image://thumb/" + rowItem.thumb : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: rowItem.thumb === ""
                                        text: rowItem.fileName
                                        color: Theme.grey
                                        font.family: Theme.font; font.pixelSize: 14
                                    }
                                    Rectangle {
                                        visible: rowItem.kind === "video"
                                        anchors.centerIn: parent
                                        width: 36; height: 36; radius: 18
                                        color: Qt.rgba(0, 0, 0, 0.5)
                                        Icon { anchors.centerIn: parent; width: 18; height: 18; name: "play"; color: "white" }
                                    }
                                }
                            }

                            FileRow {
                                id: fileRow
                                visible: rowItem.kind === "file"
                                width: Math.min(bubble.maxW - 24, 240)
                                name: rowItem.fileName
                                size: rowItem.fileSize
                                here: true
                            }

                            Text {
                                id: bodyLbl
                                visible: rowItem.bodyText !== ""
                                width: Math.min(bubble.maxW - 24, implicitWidth)
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: rowItem.bodyText
                                color: Theme.outText
                                font.family: Theme.font; font.pixelSize: Prefs.chatSize
                            }

                            Row {
                                id: metaRow
                                anchors.right: parent.right
                                spacing: 4
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 12; height: 12
                                    name: "timer"
                                    color: Theme.outMeta
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: rowItem.timeText
                                    color: Theme.outMeta
                                    font.family: Theme.font; font.pixelSize: 11
                                }
                            }
                        }

                        MouseArea {
                            id: bubbleHit
                            anchors.fill: parent
                            onClicked: page.openItemMenu(rowItem.index)
                            onPressAndHold: page.openItemMenu(rowItem.index)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: !page.loading && items.count === 0
        anchors.centerIn: list
        width: emptyText.implicitWidth + 32
        height: emptyText.implicitHeight + 20
        radius: 16
        color: Theme.dayPill
        Text {
            id: emptyText
            anchors.centerIn: parent
            text: Tr.t("Rejali xabarlar yo'q")
            color: "white"
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    Rectangle {
        id: schedToastBox
        z: 20
        anchors.horizontalCenter: parent.horizontalCenter
        y: header.height + 12
        width: schedToastText.implicitWidth + 28
        height: schedToastText.implicitHeight + 16
        radius: height / 2
        color: Qt.rgba(0.12, 0.12, 0.13, 0.88)
        opacity: 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Text {
            id: schedToastText
            anchors.centerIn: parent
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
        Timer { id: schedToastAway; interval: 2200; onTriggered: schedToastBox.opacity = 0 }
    }

    Ring {
        visible: page.loading && items.count === 0
        anchors.centerIn: list
        width: 28; height: 28
        value: 0.25
        cross: false
        color: Theme.accent
    }

    // Header
    Rectangle {
        id: header
        width: parent.width; height: 56
        color: Theme.bar
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea { id: backHit; width: 64; height: parent.height; onClicked: page.nav.pop() }
        Column {
            anchors.centerIn: parent
            width: parent.width - 128
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Tr.t("Rejali xabarlar")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: text !== ""
                text: page.chat ? page.chat.title : ""
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
    }

    // Bottom compose bar (clears safe.bottom / keyboard; background extends to bottom edge)
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: inputBar.top; anchors.bottom: parent.bottom
        color: Theme.bar
    }
    Item {
        id: inputBar
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: page.barLift
        height: Math.min(120, Math.max(60, composeField.contentHeight + 36))

        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }

        Glass {
            x: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            width: 44; height: 44
            opacity: schedClipHit.pressed ? 0.6 : 1
            Icon { anchors.centerIn: parent; width: 26; height: 26; name: "clip"; color: Theme.text }
            MouseArea { id: schedClipHit; anchors.fill: parent; onClicked: page.openAttach() }
        }

        Glass {
            x: 58; y: 8
            width: parent.width - x - 58; height: parent.height - 16
            radius: 22
            TextEdit {
                id: composeField
                x: 14; y: 11
                width: parent.width - 28
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
                Text {
                    visible: !composeField.text && !composeField.preeditText
                    text: Tr.t("Rejali xabar")
                    color: Theme.grey
                    font: composeField.font
                }
            }
        }

        Rectangle {
            id: schedSendBtn
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            width: 44; height: 44; radius: 22
            color: composeField.text.trim() !== "" ? Theme.accent : Theme.mutedBadge
            opacity: schedSendHit.pressed ? 0.75 : 1
            Text {
                anchors.centerIn: parent
                text: "↑"
                color: "white"
                font.pixelSize: 20; font.weight: Font.Bold
            }
            MouseArea {
                id: schedSendHit
                anchors.fill: parent; anchors.margins: -6
                onClicked: page.scheduleFieldText()
            }
        }
    }

    // Item action menu (Send Now / Reschedule / Delete)
    Item {
        id: actionMenu
        anchors.fill: parent
        visible: false
        z: 25
        function show() {
            visible = true
            menuCard.scale = 0.01
            menuGrow.start()
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.28)
            MouseArea { anchors.fill: parent; onClicked: actionMenu.visible = false }
        }
        Rectangle {
            id: menuCard
            anchors.centerIn: parent
            width: 244; height: menuCol.implicitHeight
            radius: 16
            color: Theme.menu
            clip: true
            ScaleAnimator {
                id: menuGrow; target: menuCard; from: 0.01; to: 1; duration: 360
                easing.type: Easing.BezierSpline; easing.bezierCurve: page.menuSpring
            }
            Column {
                id: menuCol
                width: parent.width
                Repeater {
                    model: [
                        { key: "now", text: Tr.t("Hozir yuborish"), icon: "", glyph: "↑", danger: false },
                        { key: "time", text: Tr.t("Vaqtni o'zgartirish"), icon: "timer", glyph: "", danger: false },
                        { key: "del", text: Tr.t("O'chirish"), icon: "trash", glyph: "", danger: true }
                    ]
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: menuCol.width; height: 46
                        color: actHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { visible: index > 0; width: parent.width; height: 0.5; color: Theme.separator }
                        Icon {
                            visible: modelData.icon !== ""
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            name: modelData.icon || "timer"
                            color: modelData.danger ? Theme.danger : Theme.text
                        }
                        Text {
                            visible: modelData.glyph !== ""
                            x: 14; width: 24; anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.glyph
                            color: modelData.danger ? Theme.danger : Theme.text
                            font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold
                        }
                        Text {
                            x: 48; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 62
                            elide: Text.ElideRight
                            text: modelData.text
                            color: modelData.danger ? Theme.danger : Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        MouseArea {
                            id: actHit
                            anchors.fill: parent
                            onClicked: {
                                actionMenu.visible = false
                                const m = page.activeMsg
                                if (!m)
                                    return
                                if (modelData.key === "now")
                                    page.doSendNow(m.id)
                                else if (modelData.key === "time")
                                    page.openReschedule(m)
                                else if (modelData.key === "del")
                                    page.askDelete(m.id)
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: scheduleSheetLoader
        z: 31
        active: false
        anchors.fill: parent
        sourceComponent: ScheduleSheet {
            onPicked: (st) => {
                const act = page.pendingAction
                page.pendingAction = null
                if (!act)
                    return
                if (act.kind === "reschedule") {
                    store.rescheduleMessage(page.chatId, act.msgId, st, (r) => {
                        if (!page)
                            return
                        if (r && r["@type"] === "error")
                            return page.toast(r.message || Tr.t("Bo'lmadi"))
                        // Update local copy immediately (TDLib may also push an update)
                        page.rawMessages = page.rawMessages.map((m) => {
                            if (m.id !== act.msgId)
                                return m
                            const copy = Object.assign({}, m)
                            copy.scheduling_state = st
                            if (st["@type"] === "messageSchedulingStateSendAtDate")
                                copy.date = st.send_date
                            return copy
                        })
                        page.rebuild()
                        page.toast(Tr.t("Vaqt o'zgartirildi"))
                        // a scheduled message's id holds its send date: TDLib gives it a new one (updateNewMessage
                        // with the new id, the old one never said gone) -- the list anew, quietly, or it showed twice
                        store.scheduledMessages(page.chatId, (got, failed) => {
                            if (!page || failed)
                                return
                            page.rawMessages = got || []
                            page.rebuild()
                        })
                    })
                } else if (act.kind === "text") {
                    store.sendText(page.chatId, act.text, 0, 0, page.silent, [], 0, 0, st)
                    composeField.text = ""
                    page.toast(st["@type"] === "messageSchedulingStateSendWhenOnline"
                               ? Tr.t("Onlayn bo'lganda yuboriladi") : Tr.t("Xabar rejalashtirildi"))
                } else if (act.kind === "files") {
                    store.sendFiles(page.chatId, act.picked, act.caption, 0, act.asFiles, 0, page.silent, act.apart, 0, 0, st)
                    composeField.text = ""
                    page.toast(st["@type"] === "messageSchedulingStateSendWhenOnline"
                               ? Tr.t("Onlayn bo'lganda yuboriladi") : Tr.t("Xabar rejalashtirildi"))
                }
            }
            onCancelled: page.pendingAction = null
        }
    }

    Loader {
        id: attachSheetLoader
        z: 30
        active: false
        anchors.fill: parent
        sourceComponent: AttachSheet {
            onRefused: (text) => page.toast(text)
            onSend: (picked, asFiles, apart) => {
                const cap = composeField.text.trim() ? { text: composeField.text.trim(), marks: [] } : null
                page.pendingAction = { kind: "files", picked: picked, asFiles: asFiles, apart: apart, caption: cap }
                scheduleSheetLoader.active = true
                scheduleSheetLoader.item.show(0, false, page.canOnline)
            }
        }
    }

    Loader {
        id: confirmAlertLoader
        z: 35
        active: false
        anchors.fill: parent
        sourceComponent: Alert { anchors.fill: parent }
    }
}
