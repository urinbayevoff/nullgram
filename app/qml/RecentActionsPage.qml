// Recent Actions (Telegram-iOS's ChatRecentActionsController, as a plain list): the admins' doings of the last
// 48 hours from getChatEventLog — who, what (about 30 chatEventAction kinds in words), when; newest first.
// «Filtr» (iOS's «Settings» sheet): by kind — members and admins, the chat's settings, messages — and by admin;
// «Qo'llash» asks again with those chatEventLogFilters and user_ids.
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property var chat: store.chats[chatId]
    readonly property bool channel: !!chat && chat.type.is_channel
    property var events: []
    property bool loaded: false
    property bool filtering: false
    property var kinds: ({ members: true, settings: true, messages: true })
    property var admins: []             // chatMembers
    property var picked: null           // admins' user ids shown; null: all
    readonly property var kindKeys: ({
        members: ["member_joins", "member_leaves", "member_invites", "member_promotions", "member_restrictions", "member_tag_changes"],
        settings: ["info_changes", "setting_changes", "invite_link_changes", "video_chat_changes", "forum_changes", "subscription_extensions"],
        messages: ["message_edits", "message_deletions", "message_pins"] })
    readonly property bool narrowed: !kinds.members || !kinds.settings || !kinds.messages || picked !== null
    title: Tr.t("So'nggi amallar")
    action: filtering ? "" : Tr.t("Filtr")
    onActed: filtering = true
    Component.onCompleted: {
        load()
        store.send({ "@type": "getSupergroupMembers", supergroup_id: chat.type.supergroup_id,
                     filter: { "@type": "supergroupMembersFilterAdministrators" }, offset: 0, limit: 50 }, (r) => {
            if (r["@type"] === "chatMembers")
                page.admins = r.members.filter((m) => m.member_id["@type"] === "messageSenderUser")
        })
    }
    function load() {
        let filters = null
        if (!kinds.members || !kinds.settings || !kinds.messages) {
            filters = { "@type": "chatEventLogFilters" }
            for (const k in kindKeys)
                for (const f of kindKeys[k])
                    filters[f] = !!kinds[k]
        }
        store.send({ "@type": "getChatEventLog", chat_id: chatId, query: "", from_event_id: 0, limit: 100,
                     filters: filters, user_ids: picked || [] }, (r) => {
            page.loaded = true
            if (r["@type"] === "chatEvents")
                page.events = r.events
        })
    }
    function flipKind(k) {
        const o = Object.assign({}, kinds)
        o[k] = !o[k]
        kinds = o
    }
    function flipAdmin(uid) {
        const all = admins.map((m) => m.member_id.user_id)
        let now = picked === null ? all.slice() : picked.slice()
        const i = now.indexOf(uid)
        if (i >= 0)
            now.splice(i, 1)
        else
            now.push(uid)
        picked = now.length === all.length ? null : now
    }
    function apply() {
        if (!kinds.members && !kinds.settings && !kinds.messages)
            return nav.say(Tr.t("Kamida bitta turni tanlang"))
        if (picked !== null && !picked.length)
            return nav.say(Tr.t("Kamida bitta adminni tanlang"))
        filtering = false
        loaded = false
        load()
    }
    function who(id) { return store.senderName(id, false) || Tr.t("O'chirilgan hisob") }
    function said(a) {
        const t = a["@type"].replace("chatEvent", "")
        const short = (m) => m && m.content && m.content.text ? "«" + m.content.text.text.slice(0, 60) + "»" : ""
        switch (t) {
        case "TitleChanged": return Tr.f("nomini «%1»ga o'zgartirdi", a.new_title)
        case "DescriptionChanged": return a.new_description ? Tr.f("tavsifni o'zgartirdi: «%1»", a.new_description) : Tr.t("tavsifni olib tashladi")
        case "UsernameChanged": return a.new_username ? Tr.f("havolani t.me/%1 qildi", a.new_username) : Tr.t("havolani olib tashladi")
        case "PhotoChanged": return a.new_photo ? Tr.t("rasmni o'zgartirdi") : Tr.t("rasmni olib tashladi")
        case "MessagePinned": return Tr.f("xabarni qadadi %1", short(a.message))
        case "MessageUnpinned": return Tr.f("xabarni qadashdan oldi %1", short(a.message))
        case "MessageDeleted": return Tr.f("xabarni o'chirdi %1", short(a.message))
        case "MessageEdited": return Tr.f("xabarni tahrirladi %1", short(a.new_message))
        case "MemberJoined": return Tr.t(channel ? "kanalga obuna bo'ldi" : "guruhga qo'shildi")
        case "MemberJoinedByInviteLink": return Tr.t("taklif havolasi orqali qo'shildi")
        case "MemberJoinedByRequest": return Tr.t("so'rov orqali qo'shildi")
        case "MemberLeft": return Tr.t(channel ? "obunani bekor qildi" : "guruhdan chiqdi")
        case "MemberInvited": return Tr.f("%1ni qo'shdi", who({ "@type": "messageSenderUser", user_id: a.user_id }))
        case "MemberPromoted": return a.new_status["@type"] === "chatMemberStatusAdministrator"
                                      ? Tr.f("%1ni admin qildi", who({ "@type": "messageSenderUser", user_id: a.user_id }))
                                      : Tr.f("%1ni adminlikdan oldi", who({ "@type": "messageSenderUser", user_id: a.user_id }))
        case "MemberRestricted": return a.new_status["@type"] === "chatMemberStatusBanned" ? Tr.f("%1ni chetlatdi", who(a.member_id))
                                      : a.new_status["@type"] === "chatMemberStatusLeft" ? Tr.f("%1ni blokdan chiqardi", who(a.member_id))
                                      : Tr.f("%1ning huquqlarini o'zgartirdi", who(a.member_id))
        case "InviteLinkEdited": return Tr.t("taklif havolasini tahrirladi")
        case "InviteLinkRevoked": return Tr.t("taklif havolasini bekor qildi")
        case "InviteLinkDeleted": return Tr.t("taklif havolasini o'chirdi")
        case "LinkedChatChanged": return a.new_linked_chat_id ? Tr.t("muhokama guruhini bog'ladi") : Tr.t("muhokama guruhini ajratdi")
        case "SignMessagesToggled": return Tr.t(a.sign_messages ? "imzolarni yoqdi" : "imzolarni o'chirdi")
        case "HasProtectedContentToggled": return Tr.t(a.has_protected_content ? "tarkibni himoyalashni yoqdi" : "tarkibni himoyalashni o'chirdi")
        case "AvailableReactionsChanged": return Tr.t("reaksiyalarni o'zgartirdi")
        case "MessageAutoDeleteTimeChanged": return a.new_message_auto_delete_time
                                                    ? Tr.f("avto-o'chirishni %1 qildi", store.lasting(a.new_message_auto_delete_time))
                                                    : Tr.t("avto-o'chirishni o'chirdi")
        case "PollStopped": return Tr.t("so'rovnomani to'xtatdi")
        case "VideoChatCreated": return Tr.t("jonli efir boshladi")
        case "VideoChatEnded": return Tr.t("jonli efirni tugatdi")
        case "SlowModeDelayChanged": return Tr.t("sekin rejimni o'zgartirdi")
        case "PermissionsChanged": return Tr.t("a'zolar huquqlarini o'zgartirdi")
        case "ActiveUsernamesChanged": return Tr.t("havolalarni o'zgartirdi")
        case "AccentColorChanged": case "ProfileAccentColorChanged": case "BackgroundChanged": case "EmojiStatusChanged":
            return Tr.t("ko'rinishini o'zgartirdi")
        default: return t
        }
    }
    function when(d) {
        const x = new Date(d * 1000), today = new Date()
        return x.toDateString() === today.toDateString() ? Qt.formatTime(x, "hh:mm") : Qt.formatDateTime(x, "dd.MM hh:mm")
    }

    // ---- the filter (iOS: «Filter actions by type», «Filter actions by admins») ----
    SettingsGroup {
        visible: page.filtering
        title: Tr.t("Amal turi bo'yicha")
        Repeater {
            model: [{ k: "members", t: "A'zolar va adminlar" }, { k: "settings", t: "Guruh sozlamalari" }, { k: "messages", t: "Xabarlar" }]
            SettingsRow {
                required property var modelData
                required property int index
                text: Tr.t(page.channel && modelData.k === "settings" ? "Kanal sozlamalari" : page.channel && modelData.k === "members"
                           ? "Obunachilar va adminlar" : modelData.t)
                chevron: false
                tick: !!page.kinds[modelData.k]
                last: index === 2
                onClicked: page.flipKind(modelData.k)
            }
        }
    }
    SettingsGroup {
        visible: page.filtering && page.admins.length > 0
        title: Tr.t("Adminlar bo'yicha")
        SettingsRow {
            text: Tr.t("Barcha adminlarning amallari")
            chevron: false
            tick: page.picked === null
            onClicked: page.picked = page.picked === null ? [] : null
        }
        Repeater {
            model: page.admins
            SettingsRow {
                required property var modelData
                required property int index
                text: store.senderName(modelData.member_id, false)
                chevron: false
                tick: page.picked === null || page.picked.indexOf(modelData.member_id.user_id) >= 0
                last: index === page.admins.length - 1
                onClicked: page.flipAdmin(modelData.member_id.user_id)
            }
        }
    }
    SettingsGroup {
        visible: page.filtering
        SettingsRow { text: Tr.t("Qo'llash"); accent: true; chevron: false; onClicked: page.apply() }
        SettingsRow { text: Tr.t("Bekor qilish"); chevron: false; last: true; onClicked: page.filtering = false }
    }

    Text {
        visible: !page.filtering
        x: 32; width: parent.width - 64
        topPadding: 4; bottomPadding: 16
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.loaded && !page.events.length ? Tr.t(page.narrowed ? "Tanlangan filtr bo'yicha so'nggi 48 soatda amal yo'q."
                                                                      : "So'nggi 48 soatda adminlar hech narsa qilmadi.")
             : Tr.t(page.narrowed ? "Filtrlangan: adminlarning so'nggi 48 soatdagi amallari." : "Adminlarning so'nggi 48 soatdagi amallari.")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 14
    }
    SettingsGroup {
        visible: page.events.length > 0 && !page.filtering
        Repeater {
            model: page.events
            Rectangle {
                id: ev
                required property var modelData
                required property int index
                readonly property string name: page.who(modelData.member_id)
                width: parent.width; height: Math.max(58, what.y + what.height + 10)
                color: "transparent"
                property string photo: ""
                Component.onCompleted: {
                    const id = modelData.member_id
                    if (id["@type"] === "messageSenderUser" && store.users[id.user_id])
                        store.userPhoto(store.users[id.user_id], (p) => ev.photo = p)
                }
                Avatar {
                    x: 14; y: 9; width: 36; height: 36
                    source: ev.photo
                    letters: store.letters(ev.name)
                    tint: store.tints[Math.abs(ev.modelData.member_id.user_id || ev.modelData.member_id.chat_id || 0) % store.tints.length]
                }
                Text {
                    id: nameText
                    x: 62; y: 9; width: parent.width - x - timeText.width - 22
                    elide: Text.ElideRight
                    text: ev.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    id: timeText
                    anchors.right: parent.right; anchors.rightMargin: 14; y: 10
                    text: page.when(ev.modelData.date)
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    id: what
                    x: 62; y: 30; width: parent.width - x - 14
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: page.said(ev.modelData.action)
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Rectangle {
                    visible: ev.index < page.events.length - 1
                    x: 62; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator
                }
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
