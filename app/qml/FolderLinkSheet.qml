pragma ComponentBehavior: Bound
// Bottom sheet for t.me/addlist/<slug> folder invite links (TDLib 1.8.68:
// checkChatFolderInviteLink -> chatFolderInviteLinkInfo -> confirmation Alert ->
// addChatFolderByInviteLink). Respects safe.bottom and day/night ztMETRO Theme.
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 32

    property var store: null
    property bool open: false
    property real safeBottom: 0

    property string inviteLink: ""
    property bool loading: false
    property bool busy: false
    property string errorText: ""
    property int folderId: 0
    property string folderName: ""
    property var missingIds: []
    property var addedIds: []
    property var selected: ({})         // chatId -> bool
    property int selTick: 0
    property int known: 0
    property int _reqId: 0

    signal added(string name)
    signal errorSaid(string msg)
    signal closed()

    readonly property var allRows: {
        const out = []
        for (const id of missingIds)
            out.push({ id: id, already: false })
        for (const id of addedIds)
            out.push({ id: id, already: true })
        return out
    }
    readonly property int pickedCount: {
        void selTick
        let n = 0
        for (const id of missingIds)
            if (selected[id])
                n++
        return n
    }

    function show(link) {
        const u = String(link || "").trim()
        if (!u)
            return
        inviteLink = u
        loading = true
        busy = false
        errorText = ""
        folderId = 0
        folderName = ""
        missingIds = []
        addedIds = []
        selected = {}
        selTick++
        open = true
        visible = true
        fall.stop()
        shade.stop()
        panelSlide.y = panel.height
        dim.opacity = 0
        rise.from = panel.height
        rise.restart()
        shade.restart()
        loadLink()
    }

    function close() {
        if (!open)
            return
        alert.open = false
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

    function dismiss() {
        if (alert.open) {
            alert.open = false
            return true
        }
        if (open) {
            close()
            return true
        }
        return false
    }

    function loadLink() {
        if (!store || !inviteLink)
            return
        _reqId += 1
        const req = _reqId
        loading = true
        errorText = ""
        store.checkFolderInviteLink(inviteLink, (info, err) => {
            if (!sheet || req !== sheet._reqId || !sheet.open)
                return
            sheet.loading = false
            if (!info) {
                sheet.errorText = /INVITE_SLUG|NOT_FOUND|INVALID|EXPIRED/i.test(err || "")
                    ? Tr.t("Havola yaroqsiz yoki muddati o'tgan")
                    : (err || Tr.t("Havola yaroqsiz yoki muddati o'tgan"))
                return
            }
            const fi = info.chat_folder_info || {}
            sheet.folderId = fi.id || 0
            sheet.folderName = (fi.name && fi.name.text && fi.name.text.text) ? fi.name.text.text : Tr.t("Papka")
            const miss = info.missing_chat_ids || []
            const add = info.added_chat_ids || []
            const sel = {}
            for (const id of miss)
                sel[id] = true
            sheet.selected = sel
            sheet.missingIds = miss
            sheet.addedIds = add
            sheet.selTick++
            sheet.fetchChats(miss.concat(add))
        })
    }

    function fetchChats(ids) {
        if (!store)
            return
        for (const id of ids) {
            if (!store.chats[id]) {
                store.send({ "@type": "getChat", chat_id: id }, () => {
                    if (sheet)
                        sheet.known++
                })
            }
        }
    }

    function peer(id, _k) {
        const c = store ? store.chats[id] : null
        return c ? {
            title: store.isSaved(c) ? Tr.t("Saqlangan xabarlar") : store.title(c),
            photo: store.photoPath(c),
            letters: store.letters(c.title),
            tint: store.tints[Math.abs(id) % store.tints.length],
            saved: store.isSaved(c)
        } : { title: "…", photo: "", letters: "", tint: Theme.grey, saved: false }
    }

    function toggleChat(id) {
        const next = Object.assign({}, selected)
        next[id] = !next[id]
        selected = next
        selTick++
    }

    function isSelected(id, _tick) {
        return !!selected[id]
    }

    function pickedIds() {
        const out = []
        for (const id of missingIds)
            if (selected[id])
                out.push(id)
        return out
    }

    function askConfirm() {
        if (busy || loading || errorText !== "")
            return
        const ids = pickedIds()
        if (folderId > 0 && ids.length === 0) {
            close()
            return
        }
        const msg = ids.length > 0
            ? Tr.f("«%1» papkasi va tanlangan %2 ta chat qo'shilsinmi?", folderName, ids.length)
            : Tr.f("«%1» papkasi qo'shilsinmi?", folderName)
        alert.show(Tr.t("Papka qo'shish"), msg, [
            { t: Tr.t("Bekor qilish") },
            { t: Tr.t("Qo'shish"), bold: true, run: () => sheet.doAdd(ids) }
        ])
    }

    function doAdd(ids) {
        if (!store || busy)
            return
        busy = true
        const fname = folderName
        store.addFolderByInviteLink(inviteLink, ids, (ok, err) => {
            if (!sheet)
                return
            sheet.busy = false
            if (!ok) {
                sheet.errorSaid(err || Tr.t("Papkani qo'shib bo'lmadi"))
                return
            }
            sheet.added(fname)
            sheet.close()
        })
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
        readonly property real maxH: Math.max(360, Math.round(sheet.height * 0.76))
        height: Math.min(maxH, Math.max(300 + sheet.safeBottom, Math.round(sheet.height * 0.62) + sheet.safeBottom))
        radius: 16
        color: Theme.dark ? "#111113" : Theme.grouped
        MouseArea { anchors.fill: parent }

        // Flat bottom extension under safe.bottom
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 20
            color: panel.color
        }

        // Drag handle
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

        // Header: folder icon + name + chat count
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16
            width: parent.width - 96
            spacing: 2
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    name: "folder"
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: sheet.folderName || Tr.t("Papka havolasi")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
            }
            Text {
                visible: !sheet.loading && sheet.errorText === "" && sheet.allRows.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Tr.n("%1 ta chat", sheet.allRows.length)
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }

        Rectangle {
            x: 0; y: 60
            width: parent.width; height: 0.5
            color: Theme.separator
        }

        // Loading state
        Text {
            visible: sheet.loading
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -16
            text: Tr.t("Yuklanmoqda…")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }

        // Error state
        Column {
            visible: !sheet.loading && sheet.errorText !== ""
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -16
            width: parent.width - 48
            spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: sheet.errorText
                color: Theme.danger
                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
            }
        }

        // Chat selection list
        ListView {
            id: chatList
            visible: !sheet.loading && sheet.errorText === ""
            x: 12; y: 68
            width: parent.width - 24
            height: Math.max(80, actionBtn.y - y - 12)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: sheet.allRows
            delegate: Rectangle {
                id: crow
                required property var modelData
                required property int index
                readonly property var cid: modelData.id
                readonly property bool already: !!modelData.already
                readonly property bool checked: already || sheet.isSelected(cid, sheet.selTick)
                readonly property var p: sheet.peer(cid, sheet.known)
                width: chatList.width
                height: 54
                radius: 10
                color: rowHit.pressed && !already ? Theme.highlight : "transparent"

                Check {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                    on: true
                    checked: crow.checked
                    opacity: crow.already ? 0.45 : 1
                    hollow: panel.color
                    ring: Theme.grey
                    ringChecked: Theme.accent
                }
                Avatar {
                    x: 42; anchors.verticalCenter: parent.verticalCenter
                    width: 38; height: 38
                    source: crow.p.photo
                    letters: crow.p.letters
                    tint: crow.p.tint
                    saved: crow.p.saved
                }
                Column {
                    x: 90; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 12
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: crow.p.title
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
                    }
                    Text {
                        visible: crow.already
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tr.t("Allaqachon qo'shilgan")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Rectangle {
                    visible: crow.index < sheet.allRows.length - 1
                    x: 90; anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
                MouseArea {
                    id: rowHit
                    anchors.fill: parent
                    enabled: !crow.already
                    onClicked: sheet.toggleChat(crow.cid)
                }
            }
        }

        // Primary action button (above safe.bottom)
        Rectangle {
            id: actionBtn
            visible: !sheet.loading
            x: 16
            width: parent.width - 32
            height: 46
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16 + sheet.safeBottom
            radius: 12
            color: sheet.errorText !== "" ? Theme.highlight : Theme.accent
            opacity: sheet.busy ? 0.55 : (actHit.pressed ? 0.78 : 1)
            Text {
                anchors.centerIn: parent
                text: sheet.errorText !== "" ? Tr.t("Yopish")
                    : sheet.folderId > 0
                        ? (sheet.pickedCount > 0 ? Tr.n("Papkani yangilash (+%1)", sheet.pickedCount) : Tr.t("Barcha chatlar qo'shilgan"))
                    : sheet.pickedCount > 0 ? Tr.n("Papka qo'shish (%1 chat)", sheet.pickedCount)
                    : Tr.t("Papka qo'shish")
                color: sheet.errorText !== "" ? Theme.text : "white"
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            MouseArea {
                id: actHit
                anchors.fill: parent
                enabled: !sheet.busy
                onClicked: {
                    if (sheet.errorText !== "")
                        sheet.close()
                    else
                        sheet.askConfirm()
                }
            }
        }
    }

    NumberAnimation {
        id: rise
        target: panelSlide
        property: "y"
        to: 0
        duration: 280
        easing.type: Easing.OutCubic
    }
    ParallelAnimation {
        id: fall
        NumberAnimation { id: fallY; target: panelSlide; property: "y"; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 220 }
        onFinished: sheet.visible = false
    }

    Alert {
        id: alert
        z: 45
        anchors.fill: parent
    }
}
