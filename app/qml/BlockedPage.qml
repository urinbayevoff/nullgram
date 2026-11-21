// «Bloklanganlar» (Telegram-iOS's BlockedPeersController, #26472): «Foydalanuvchini bloklash…» (the chats with people,
// FolderChatsPage's picking — setMessageSenderBlockList blockListMain), then who is blocked (getBlockedMessageSenders);
// a row swiped left, or «Tahrirlash»'s ⊖, shows «Blokdan chiqarish» (the block list null).
import QtQuick

SubPage {
    id: page
    property var senders: []
    property int total: -1
    property string revealed: ""
    property bool editing: false
    property var photos: ({})
    property int got: 0
    title: Tr.t("Bloklanganlar")
    action: senders.length ? (editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")) : ""
    actionBold: editing
    onActed: { editing = !editing; revealed = "" }

    function load() {
        store.send({ "@type": "getBlockedMessageSenders", block_list: { "@type": "blockListMain" }, offset: 0, limit: 100 }, (r) => {
            page.senders = r.senders || []
            page.total = r.total_count || 0
            if (!page.senders.length)
                page.editing = false
        })
    }
    Component.onCompleted: load()

    function idOf(s) { return s["@type"] === "messageSenderUser" ? s.user_id : s.chat_id }
    function photoOf(s) {
        got
        const id = idOf(s)
        if (photos[id] !== undefined)
            return photos[id]
        photos[id] = ""
        if (s["@type"] === "messageSenderUser")
            store.userPhoto(store.users[id], (p) => { page.photos[id] = p; page.got++ })
        else {
            const c = store.chats[id]
            photos[id] = c ? store.photoPath(c) : ""
        }
        return photos[id]
    }
    function block(ids) {
        let left = ids.length
        for (const id of ids) {
            const c = store.chats[id]
            const uid = c && c.type["@type"] === "chatTypePrivate" ? c.type.user_id : id
            store.send({ "@type": "setMessageSenderBlockList", sender_id: { "@type": "messageSenderUser", user_id: uid },
                         block_list: { "@type": "blockListMain" } }, () => { if (--left === 0) page.load() })
        }
    }
    function unblock(s) {
        revealed = ""
        store.send({ "@type": "setMessageSenderBlockList", sender_id: s, block_list: null }, () => page.load())
    }
    function pick() {
        const blockedIds = senders.map(idOf)
        const p = nav.push(Qt.createComponent("FolderChatsPage.qml"), {
            heading: Tr.t("Foydalanuvchini bloklash"), chosen: [],
            pool: (c) => c.type["@type"] === "chatTypePrivate" && !store.isSaved(c) && blockedIds.indexOf(c.type.user_id) < 0 })
        if (p)
            p.done.connect((flags, ids) => { if (ids.length) page.block(ids) })
    }

    SettingsGroup {
        note: Tr.t("Bloklangan foydalanuvchilar sizga yoza olmaydi, sizni guruhlarga qo'sha olmaydi va profil rasmingiz, onlayn hamda so'nggi faollik holatingizni ko'rmaydi.")
        Item {          // «Foydalanuvchini bloklash…»
            width: parent.width; height: 48
            Rectangle { anchors.fill: parent; color: Theme.highlight; visible: addHit.pressed }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: "⊘  " + Tr.t("Foydalanuvchini bloklash…")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { id: addHit; anchors.fill: parent; onClicked: page.pick() }
        }
    }
    SettingsGroup {
        visible: page.senders.length > 0
        Repeater {
            model: page.senders
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property string key: String(page.idOf(modelData))
                readonly property real slide: page.revealed === key ? -unBtn.width : 0
                readonly property string name: store.senderName(modelData) || "…"
                width: parent ? parent.width : 300; height: 58
                clip: true
                Item {
                    id: inner
                    x: row.slide
                    width: parent.width; height: parent.height
                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
                    Rectangle {     // ⊖
                        x: page.editing ? 14 : -30; anchors.verticalCenter: parent.verticalCenter
                        Behavior on x { NumberAnimation { duration: 200 } }
                        width: 22; height: 22; radius: 11
                        color: "#ff3b30"
                        Rectangle { anchors.centerIn: parent; width: 10; height: 2; color: "white" }
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.revealed = page.revealed === row.key ? "" : row.key }
                    }
                    Avatar {
                        id: av
                        x: page.editing ? 48 : 16; anchors.verticalCenter: parent.verticalCenter
                        Behavior on x { NumberAnimation { duration: 200 } }
                        width: 40; height: 40
                        source: page.photoOf(row.modelData)
                        letters: store.letters(row.name)
                        tint: store.tints[Math.abs(Number(row.key)) % store.tints.length]
                    }
                    Text {
                        x: av.x + 50; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 16
                        elide: Text.ElideRight
                        text: row.name
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.leftMargin: page.editing ? 44 : 0
                    property real x0: 0
                    property real y0: 0
                    property bool swiped: false
                    onPressed: (m) => { x0 = m.x; y0 = m.y; preventStealing = false; swiped = false }
                    onPositionChanged: (m) => {
                        const dx = m.x - x0
                        if (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(m.y - y0))
                            preventStealing = swiped = true
                        if (dx < -30)
                            page.revealed = row.key
                        else if (dx > 30 && page.revealed === row.key)
                            page.revealed = ""
                    }
                    onClicked: if (!swiped && page.revealed !== "") page.revealed = ""
                }
                Rectangle {
                    id: unBtn
                    x: parent.width + row.slide
                    width: unText.implicitWidth + 32; height: parent.height
                    color: Theme.danger
                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
                    Text {
                        id: unText
                        anchors.centerIn: parent
                        text: Tr.t("Blokdan chiqarish")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.unblock(row.modelData) }
                }
                Rectangle {
                    visible: row.index < page.senders.length - 1
                    x: av.x + 50; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator
                }
            }
        }
    }
}
