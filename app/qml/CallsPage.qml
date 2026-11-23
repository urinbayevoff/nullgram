// «So'nggi qo'ng'iroqlar» (Telegram-iOS's CallListController, as the owner's #26455–56): Hammasi / O'tkazib yuborilgan,
// then the calls (searchCallMessages, 50 at a time, more as the list nears its end): the avatar, who (red: a call we missed),
// a small handset and how it went (Chiquvchi / Kiruvchi / O'tkazib yuborilgan / Bekor qilingan, video too) with how long,
// when, ⓘ → the person's profile. Calls one after another with the same person, the same way, on the same day are one row
// «Ism (3)», as iOS has them. A row tapped opens the chat: calling itself (tgcalls) Nullgram doesn't have yet.
import QtQuick

SubPage {
    id: page
    property bool missed: false
    property var rows: []               // [{ m: the newest message, n: how many, key }]
    property var seen: ({})             // message ids already in rows
    property string next: ""
    property bool loading: false
    property bool loaded: false
    property var photos: ({})
    property int got: 0
    title: Tr.t("So'nggi qo'ng'iroqlar")

    function load(more) {
        if (loading || (more && !next))
            return
        loading = true
        const was = missed
        store.send({ "@type": "searchCallMessages", offset: more ? next : "", limit: 50, only_missed: was }, (r) => {
            page.loading = false
            if (r["@type"] !== "foundMessages" || was !== page.missed)
                return
            page.rows = page.fold(more ? page.rows : [], r.messages || [])
            page.next = r.next_offset || ""
            page.loaded = true
        })
    }
    onMissedChanged: { rows = []; seen = {}; next = ""; loaded = false; loading = false; load(false) }
    Component.onCompleted: if (visible) load(false)
    onVisibleChanged: if (visible && !loaded && !loading) load(false)
    Connections {
        target: page.flick
        function onContentYChanged() {
            if (page.flick.contentY + page.flick.height > page.flick.contentHeight - 400)
                page.load(true)
        }
    }

    function kind(m) {                  // "out", "in", "missed" (theirs, not taken), "cancelled" (ours, not taken)
        const c = m.content, why = c.discard_reason ? c.discard_reason["@type"] : ""
        const lost = why === "callDiscardReasonMissed" || why === "callDiscardReasonDeclined"
        return m.is_outgoing ? (lost ? "cancelled" : "out") : (lost ? "missed" : "in")
    }
    function day(m) { const d = new Date(m.date * 1000); return d.getFullYear() * 400 + d.getMonth() * 32 + d.getDate() }
    function fold(old, list) {
        const out = old.slice(), s = Object.assign({}, seen)
        for (const m of list) {
            if (!m.content || m.content["@type"] !== "messageCall" || s[m.id])
                continue
            s[m.id] = true
            const key = m.chat_id + ":" + kind(m) + ":" + (m.content.is_video ? 1 : 0) + ":" + day(m)
            const last = out.length ? out[out.length - 1] : null
            if (last && last.key === key)
                out[out.length - 1] = { m: last.m, n: last.n + 1, key: key }
            else
                out.push({ m: m, n: 1, key: key })
        }
        seen = s
        return out
    }
    function name(m) { const c = store.chats[m.chat_id]; return c ? c.title : "…" }
    function photoOf(m) {
        got
        const c = store.chats[m.chat_id]
        if (!c)
            return ""
        if (photos[c.id] !== undefined)
            return photos[c.id]
        photos[c.id] = ""
        const u = c.type["@type"] === "chatTypePrivate" ? store.users[c.type.user_id] : null
        if (u)
            store.userPhoto(u, (p) => { page.photos[c.id] = p; page.got++ })
        else
            photos[c.id] = store.photoPath(c)
        return photos[c.id]
    }
    function how(m) {
        const k = kind(m), v = m.content.is_video
        const w = k === "out" ? (v ? "Chiquvchi video" : "Chiquvchi")
                : k === "in" ? (v ? "Kiruvchi video" : "Kiruvchi")
                : k === "missed" ? (v ? "O'tkazib yuborilgan video" : "O'tkazib yuborilgan")
                : (v ? "Bekor qilingan video" : "Bekor qilingan")
        const d = m.content.duration
        return Tr.t(w) + (d > 0 ? " (" + (d >= 3600 ? Math.floor(d / 3600) + ":" + String(Math.floor(d / 60) % 60).padStart(2, "0")
                                                     : Math.floor(d / 60)) + ":" + String(d % 60).padStart(2, "0") + ")" : "")
    }
    function when(m) {
        const d = new Date(m.date * 1000), now = new Date(), loc = Qt.locale(Tr.en ? "en_US" : "uz_UZ")
        if (d.toDateString() === now.toDateString())
            return d.toLocaleTimeString(loc, "HH:mm")
        const y = new Date(now.getTime() - 86400000)
        if (d.toDateString() === y.toDateString())
            return Tr.t("kecha")
        if (now - d < 6 * 86400000)
            return d.toLocaleDateString(loc, "ddd")
        return d.toLocaleDateString(loc, d.getFullYear() === now.getFullYear() ? "d MMM" : "dd.MM.yy")
    }

    Segments {
        x: 16; width: parent.width - 32
        items: [Tr.t("Hammasi"), Tr.t("O'tkazib yuborilgan")]
        index: page.missed ? 1 : 0
        onPicked: (i) => page.missed = i === 1
    }
    SettingsGroup {
        visible: page.backable
        note: Tr.t("Yoqilsa, pastki panelda «Qo'ng'iroqlar» yorlig'i paydo bo'ladi.")
        SettingsRow {
            text: Tr.t("Qo'ng'iroqlar yorlig'ini ko'rsatish")
            toggle: true; chevron: false; last: true
            on: Prefs.callsTab
            onClicked: Prefs.callsTab = !Prefs.callsTab
        }
    }
    SettingsGroup {
        note: page.rows.length > 0 && !page.next ? Tr.t("Nullgram'dan qo'ng'iroq qilish hali yo'q — qator bosilsa chat ochiladi.") : ""
        SettingsRow {
            icon: "phone"; tint: Theme.accent; accent: true; bare: true; chevron: false
            last: page.rows.length === 0
            text: Tr.t("Yangi qo'ng'iroq")
            onClicked: page.nav.say(Tr.t("Nullgram'da ovozli va video qo'ng'iroqlar hali yo'q"))
        }
        Repeater {
            model: page.rows
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property var m: modelData.m
                readonly property string k: page.kind(m)
                width: parent ? parent.width : 300; height: 56
                Rectangle { anchors.fill: parent; color: Theme.highlight; visible: rowHit.pressed }
                MouseArea {
                    id: rowHit
                    anchors.fill: parent
                    onClicked: page.nav.push(Qt.createComponent("ChatPage.qml"), { chatId: row.m.chat_id })
                }
                Avatar {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: page.photoOf(row.m)
                    letters: store.letters(page.name(row.m))
                    tint: store.tints[Math.abs(Number(row.m.chat_id)) % store.tints.length]
                }
                Column {
                    x: 68; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - right.width - 24
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: page.name(row.m) + (row.modelData.n > 1 ? " (" + row.modelData.n + ")" : "")
                        color: row.k === "missed" ? Theme.danger : Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Row {
                        spacing: 4
                        width: parent.width
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.m.is_outgoing
                            width: 13; height: 13
                            name: row.m.content.is_video ? "camera" : "phone"
                            color: Theme.grey
                        }
                        Text {
                            width: parent.width - 17; elide: Text.ElideRight
                            text: page.how(row.m)
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 14
                        }
                    }
                }
                Row {
                    id: right
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.when(row.m)
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 15
                    }
                    Item {
                        width: 28; height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        Icon { anchors.centerIn: parent; width: 22; height: 22; name: "info"; color: Theme.accent; opacity: infoHit.pressed ? 0.4 : 1 }
                        MouseArea {
                            id: infoHit
                            anchors.fill: parent; anchors.margins: -8
                            onClicked: page.nav.push(Qt.createComponent("ChatInfoPage.qml"), { chatId: row.m.chat_id })
                        }
                    }
                }
                Rectangle { visible: row.index < page.rows.length - 1; x: 68; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
            }
        }
    }
    Text {
        visible: page.loaded && !page.rows.length
        x: 32; width: parent.width - 64
        topPadding: 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.missed ? Tr.t("O'tkazib yuborilgan qo'ng'iroqlar yo'q") : Tr.t("Hali qo'ng'iroqlar yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    Item { width: 1; height: page.backable ? 0 : 72 }
}
