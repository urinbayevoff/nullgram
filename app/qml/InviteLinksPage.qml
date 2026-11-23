// Invite Links (Telegram-iOS's InviteLinkListController): the primary link (Nusxa / Bekor qilish), «Yangi havola
// yaratish», our other links (name or link, who joined, when it ends; a tap: copy, edit, revoke), the revoked ones
// (delete one or all). getChatInviteLinks; the editor is InviteLinkEditPage.
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property var chat: store.chats[chatId]
    property var primary: null
    property var links: []
    property var revoked: []
    title: Tr.t("Taklif havolalari")

    Component.onCompleted: load()
    onVisibleChanged: if (visible) load()
    function load() {
        const me = store.me ? store.me.id : 0
        const ask = (gone, done) => store.send({ "@type": "getChatInviteLinks", chat_id: chatId, creator_user_id: me, is_revoked: gone,
                                                 offset_date: 0, offset_invite_link: "", limit: 100 }, (r) => {
            if (r["@type"] === "chatInviteLinks")
                done(r.invite_links)
        })
        ask(false, (l) => { page.primary = l.find((x) => x.is_primary) || null; page.links = l.filter((x) => !x.is_primary) })
        ask(true, (l) => page.revoked = l)
    }
    function edit(link) {
        const p = nav.push(Qt.createComponent("InviteLinkEditPage.qml"), { chatId: chatId, link: link })
    }
    TextEdit { id: clip; visible: false }
    property string sharedUrl: ""
    function copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        nav.say(Tr.t("Havola nusxalandi"))
    }
    function share(text) {
        sharedUrl = text
        forward.show()
    }
    function dismiss() {
        if (forward.open) {
            forward.close()
            return true
        }
        return false
    }
    function revoke(l) {
        store.send({ "@type": "revokeChatInviteLink", chat_id: chatId, invite_link: l.invite_link }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.load()
        })
    }
    function ask(text, answers) {
        alert.title = ""
        alert.text = text
        alert.vertical = answers.length > 2
        alert.answers = answers
        alert.open = true
    }
    function tap(l) {
        if (l.is_revoked)
            return ask(l.name || l.invite_link, [{ t: Tr.t("O'chirish"), red: true, run: () => store.send(
                { "@type": "deleteRevokedChatInviteLink", chat_id: chatId, invite_link: l.invite_link }, () => page.load()) },
                                                 { t: Tr.t("Bekor qilish") }])
        const out = [{ t: Tr.t("Nusxa olish"), run: () => page.copy(l.invite_link) },
                     { t: Tr.t("Ulashish"), run: () => page.share(l.invite_link) }]
        if (!l.is_primary)
            out.push({ t: Tr.t("Tahrirlash"), run: () => page.edit(l) })
        out.push({ t: Tr.t("Havolani bekor qilish"), red: true, run: () => l.is_primary
                   ? store.send({ "@type": "replacePrimaryChatInviteLink", chat_id: chatId }, () => page.load()) : page.revoke(l) })
        out.push({ t: Tr.t("Bekor qilish") })
        ask(l.name || l.invite_link.replace("https://", ""), out)
    }
    function about(l) {
        const now = Date.now() / 1000
        const parts = [l.member_count ? Tr.n("%1 kishi qo'shildi", l.member_count) : Tr.t("hali hech kim qo'shilmadi")]
        if (l.pending_join_request_count)
            parts.push(Tr.n("%1 ta so'rov", l.pending_join_request_count))
        if (l.is_revoked)
            parts.push(Tr.t("bekor qilingan"))
        else if (l.expiration_date && l.expiration_date < now)
            parts.push(Tr.t("muddati tugagan"))
        else if (l.expiration_date)
            parts.push(Tr.f("%1 gacha", Qt.formatDateTime(new Date(l.expiration_date * 1000), "dd.MM.yyyy hh:mm")))
        if (l.member_limit)
            parts.push(Tr.f("%1 dan %2", l.member_count, l.member_limit))
        return parts.join(" · ")
    }

    component LinkRow: Rectangle {
        id: row
        property var l: null
        property bool last: false
        width: parent ? parent.width : 300; height: 60
        color: hit.pressed ? Theme.highlight : "transparent"
        Rectangle {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 17
            color: row.l && row.l.is_revoked ? Theme.grey : row.l && row.l.creates_join_request ? "#ff9500" : Theme.accent
            Icon { anchors.centerIn: parent; width: 18; height: 18; name: "clip"; color: "white" }
        }
        Text {
            x: 60; y: 10; width: parent.width - x - 16
            elide: Text.ElideMiddle
            text: row.l ? row.l.name || row.l.invite_link.replace("https://", "") : ""
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
        }
        Text {
            x: 60; y: 33; width: parent.width - x - 16
            elide: Text.ElideRight
            text: row.l ? page.about(row.l) : ""
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
        Rectangle { visible: !row.last; x: 60; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
        MouseArea { id: hit; anchors.fill: parent; onClicked: page.tap(row.l) }
    }

    // ---- the primary link: big, two buttons under it ----
    SettingsGroup {
        title: Tr.t("Asosiy havola")
        note: Tr.t("Shu havola orqali har kim qo'shila oladi.")
        Item {
            width: parent.width; height: 116
            Rectangle {
                x: 16; y: 14; width: parent.width - 32; height: 44; radius: 10
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                Text {
                    anchors.centerIn: parent; width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: page.primary ? page.primary.invite_link.replace("https://", "") : "…"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                }
                MouseArea { anchors.fill: parent; onClicked: if (page.primary) page.tap(page.primary) }
            }
            Row {
                x: 16; y: 66; spacing: 10
                Repeater {
                    model: [{ t: Tr.t("Nusxa olish"), run: () => page.primary && page.copy(page.primary.invite_link) },
                            { t: Tr.t("Ulashish"), run: () => page.primary && page.share(page.primary.invite_link) }]
                    Rectangle {
                        required property var modelData
                        width: (page.width - 32 - 32 - 10) / 2; height: 40; radius: 10
                        color: btn.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.t
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                        }
                        MouseArea { id: btn; anchors.fill: parent; onClicked: parent.modelData.run() }
                    }
                }
            }
        }
    }

    SettingsGroup {
        title: Tr.t("Qo'shimcha havolalar")
        note: Tr.t("Masalan, so'rov bilan qo'shiladigan yoki ma'lum muddat ishlaydigan havola yarating.")
        SettingsRow { text: Tr.t("Yangi havola yaratish"); accent: true; icon: "clip"; tint: Theme.accent; chevron: false
                      last: page.links.length === 0; onClicked: page.edit(null) }
        Repeater {
            model: page.links
            LinkRow { required property var modelData; required property int index; l: modelData; last: index === page.links.length - 1 }
        }
    }

    SettingsGroup {
        visible: page.revoked.length > 0
        title: Tr.t("Bekor qilingan havolalar")
        SettingsRow {
            text: Tr.t("Barchasini o'chirish"); danger: true; chevron: false
            onClicked: page.ask(Tr.t("Barcha bekor qilingan havolalar o'chirilsinmi?"), [
                { t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () => store.send(
                    { "@type": "deleteAllRevokedChatInviteLinks", chat_id: page.chatId, creator_user_id: store.me ? store.me.id : 0 },
                    () => page.load()) }])
        }
        Repeater {
            model: page.revoked
            LinkRow { required property var modelData; required property int index; l: modelData; last: index === page.revoked.length - 1 }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
    ForwardSheet {
        id: forward
        parent: page.nav || page
        z: 100
        store: page.store
        onPicked: (to, title) => {
            store.sendText(to, page.sharedUrl, 0)
            page.nav.say(store.isSaved(store.chats[to]) ? Tr.t("Havola Saqlangan xabarlarga yuborildi") : Tr.f("Havola %1ga yuborildi", title))
        }
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
