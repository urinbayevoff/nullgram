// A channel or a group we run, edited (Telegram-iOS's PeerInfoScreen in its editing state, ChannelInfoController):
// its picture and name, the description; Channel Type, Invite Links, Discussion, Reactions, Sign Messages; then
// Administrators, Subscribers, Join Requests, Removed Users, Recent Actions, Statistics; Delete Channel (the owner).
// A group (a basic one too, made a supergroup when a setting needs it): Group Type, Chat History; Invite Links,
// Reactions, Topics; Members, Permissions, Administrators, Removed Users, Recent Actions; Delete Group.
// «Tayyor» keeps a changed name and description (setChatTitle, setChatDescription). The rows open their own pages.
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property var chat: store.chats[chatId]
    readonly property bool superg: !!chat && chat.type["@type"] === "chatTypeSupergroup"
    readonly property bool channel: superg && chat.type.is_channel
    readonly property bool follows: true        // (a basic group made a supergroup: this page goes on with it)
    readonly property var group: (store.seen, store.groupOf(chat))
    readonly property var st: group ? group.status : null
    readonly property bool owner: !!st && st["@type"] === "chatMemberStatusCreator"
    readonly property var rights: owner ? null : st && st.rights ? st.rights : ({})
    function can(r) { return owner || (!!rights && !!rights[r]) }
    readonly property bool publicOne: !!group && !!group.usernames && group.usernames.active_usernames.length > 0
    property var full: null
    property string photo: ""
    property var reactions: null            // chat.available_reactions
    property int links: 0                   // our invite links that work (iOS: «Invite Links 1»)
    // a basic group's full info has no counts: its members say them
    readonly property int admins: !full ? 0 : superg ? full.administrator_count
        : (full.members || []).filter((m) => m.status["@type"] === "chatMemberStatusCreator" || m.status["@type"] === "chatMemberStatusAdministrator").length
    readonly property int people: superg ? (full ? full.member_count : 0) : (group ? group.member_count : 0)
    // how many of what members may do are let (Permissions' «11/15»)
    readonly property var permKeys: ["can_send_basic_messages", "can_send_photos", "can_send_videos", "can_send_other_messages",
        "can_send_audios", "can_send_documents", "can_send_voice_notes", "can_send_video_notes", "can_add_link_previews",
        "can_send_polls", "can_react_to_messages", "can_invite_users", "can_pin_messages", "can_edit_tag", "can_change_info"]
    readonly property string permText: {
        const p = (store.seen, chat ? chat.permissions : null)
        if (!p)
            return ""
        const keys = permKeys.concat(group && group.is_forum ? ["can_create_topics"] : [])
        return keys.filter((k) => p[k]).length + "/" + keys.length
    }
    readonly property bool dirty: !!full && (name.text.trim() !== (chat ? chat.title : "") || about.text !== (full.description || ""))

    title: Tr.t("Tahrirlash")
    action: Tr.t("Tayyor")
    actionBold: true
    actionOn: name.text.trim() !== ""
    onActed: save()
    guard: () => {
        if (!dirty)
            return false
        alert.title = ""
        alert.text = Tr.t("O'zgarishlar saqlanmasinmi?")
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Saqlamaslik"), red: true, run: () => page.nav.pop() }]
        alert.open = true
        return true
    }

    Component.onCompleted: {
        load()
        if (chat && chat.photo)
            store.fetch(chat.photo.small, 1, (p) => page.photo = p)
    }
    onVisibleChanged: if (visible) load()       // (back from a row's page: its counts)
    onChatIdChanged: load()
    function load() {
        if (!chat)
            return
        store.send(superg ? { "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }
                          : { "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id }, (r) => {
            if (r["@type"] === "error")
                return
            const first = !page.full
            page.full = r
            if (first) {
                name.text = page.chat.title
                about.text = r.description || ""
            }
        })
        store.send({ "@type": "getChat", chat_id: chatId }, (r) => { if (r["@type"] === "chat") page.reactions = r.available_reactions })
        if (can("can_invite_users") && store.me)
            store.send({ "@type": "getChatInviteLinks", chat_id: chatId, creator_user_id: store.me.id, is_revoked: false,
                         offset_date: 0, offset_invite_link: "", limit: 100 }, (r) => {
                if (r["@type"] === "chatInviteLinks")
                    page.links = r.invite_links.length
            })
        if (full && full.linked_chat_id && !store.chats[full.linked_chat_id])
            store.send({ "@type": "getChat", chat_id: full.linked_chat_id }, () => {})
    }
    function save() {
        const t = name.text.trim(), d = about.text
        let left = 0
        const fail = (r) => { if (r["@type"] === "error") page.nav.say(Tr.f("Bo'lmadi: %1", r.message)) }
        const done = () => { if (--left <= 0) page.nav.pop() }
        if (t !== chat.title) {
            left++
            store.send({ "@type": "setChatTitle", chat_id: chatId, title: t }, (r) => { fail(r); done() })
        }
        if (full && d !== (full.description || "")) {
            left++
            store.send({ "@type": "setChatDescription", chat_id: chatId, description: d }, (r) => { fail(r); done() })
        }
        if (!left)
            nav.pop()
    }
    function open(file, props) {
        const c = Qt.createComponent(file)
        if (c.status === Component.Error)
            return console.warn("nullgram:", c.errorString())
        props.chatId = chatId
        return nav.push(c, props)
    }
    function reactionsText() {
        const r = reactions
        if (!r || r["@type"] === "chatAvailableReactionsAll")
            return Tr.t("Hammasi")
        return r.reactions.length ? Tr.n("%1 ta", r.reactions.length) : Tr.t("O'chiq")
    }
    function askDelete() {
        alert.title = Tr.t(channel ? "Kanalni o'chirish" : "Guruhni o'chirish")
        alert.text = Tr.t(channel ? "Kanal va undagi barcha postlar hamma uchun o'chadi. Buni qaytarib bo'lmaydi."
                                  : "Guruh va undagi barcha xabarlar hamma uchun o'chadi. Buni qaytarib bo'lmaydi.")
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () => {
            store.send({ "@type": "deleteChat", chat_id: page.chatId }, (r) => {
                if (r["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                page.nav.say(Tr.t(page.channel ? "Kanal o'chirildi" : "Guruh o'chirildi"))
                page.nav.popHome()
            })
        } }]
        alert.open = true
    }

    // ---- the picture, the name and the description ----
    Item { width: 1; height: 8 }
    Column {
        width: parent.width
        spacing: 10
        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100; height: 100
            source: page.photo
            letters: store.letters(name.text || (page.chat ? page.chat.title : ""))
            tint: store.tints[Math.abs(page.chatId) % store.tints.length]
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Rasmni o'zgartirish")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 17
            MouseArea {
                anchors.fill: parent; anchors.margins: -8
                onClicked: page.nav.say(Tr.t("Rasm tanlash hali yo'q — Telegram'ning boshqa ilovasida o'zgartiring"))
            }
        }
        Item { width: 1; height: 4 }
    }
    SettingsGroup {
        note: Tr.t("Ixtiyoriy tavsif yozishingiz mumkin.")
        Item {
            width: parent.width; height: 48
            TextInput {
                id: name
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                enabled: page.can("can_change_info")
                maximumLength: 128
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                clip: true
            }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                visible: !name.text
                text: Tr.t(page.channel ? "Kanal nomi" : "Guruh nomi")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
        }
        Item {
            width: parent.width; height: Math.max(48, about.contentHeight + 26)
            TextEdit {
                id: about
                x: 16; y: 13; width: parent.width - 32
                enabled: page.can("can_change_info")
                wrapMode: TextEdit.Wrap
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                onTextChanged: if (length > 255) remove(255, length)
            }
            Text {
                x: 16; y: 13
                visible: !about.text
                text: Tr.t("Tavsif")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
        }
    }

    // ---- what it is: its type (a group: who sees its history), links, discussion, reactions, topics, signatures ----
    SettingsGroup {
        visible: !page.channel && page.can("can_change_info")
        SettingsRow {
            icon: "globe"; tint: "#3478f6"
            last: page.publicOne
            text: Tr.t("Guruh turi")
            value: Tr.t(page.publicOne ? "Ommaviy" : "Shaxsiy")
            onClicked: page.open("ChannelTypePage.qml", {})
        }
        SettingsRow {
            icon: "chats"; tint: "#34c759"
            visible: !page.publicOne
            last: true
            text: Tr.t("Chat tarixi")
            value: Tr.t(!page.superg || !page.full || page.full.is_all_history_available ? "Ko'rinadi" : "Yashirin")
            onClicked: page.open("ChatHistoryPage.qml", { shown: !page.superg || !page.full || page.full.is_all_history_available })
        }
    }
    SettingsGroup {
        note: !page.channel && page.can("can_change_info") ? Tr.t("Guruh chati admin yoki a'zolar ochadigan mavzularga bo'linadi.") : ""
        SettingsRow {
            icon: "globe"; tint: "#3478f6"
            visible: page.channel && page.can("can_change_info")
            text: Tr.t("Kanal turi")
            value: Tr.t(page.publicOne ? "Ommaviy" : "Shaxsiy")
            onClicked: page.open("ChannelTypePage.qml", {})
        }
        SettingsRow {
            icon: "clip"; tint: "#3478f6"
            visible: page.can("can_invite_users")
            text: Tr.t("Taklif havolalari")
            value: page.links ? String(page.links) : ""
            onClicked: page.open("InviteLinksPage.qml", {})
        }
        SettingsRow {
            icon: "chats"; tint: "#34c759"
            visible: page.channel && page.can("can_change_info")
            text: Tr.t("Muhokama")
            value: (store.seen, page.full && page.full.linked_chat_id && store.chats[page.full.linked_chat_id]
                    ? store.chats[page.full.linked_chat_id].title : Tr.t("Qo'shish"))
            onClicked: page.open("DiscussionPage.qml", { linkedId: page.full ? page.full.linked_chat_id : 0 })
        }
        SettingsRow {
            art: "reactions"
            visible: page.can("can_change_info")
            text: Tr.t("Reaksiyalar")
            value: page.reactionsText()
            onClicked: {
                const p = page.open("ReactionsPage.qml", { allowed: page.reactions })
                if (p)
                    p.changed.connect((r) => page.reactions = r)
            }
        }
        SettingsRow {
            icon: "chats"; tint: "#5856d6"
            visible: !page.channel && page.can("can_change_info")
            last: true
            text: Tr.t("Mavzular")
            value: Tr.t(page.group && page.group.is_forum ? "Yoqilgan" : "O'chiq")
            onClicked: page.open("TopicsPage.qml", {})
        }
        SettingsRow {
            icon: "quote"; tint: "#ff9500"
            visible: page.channel && page.can("can_change_info")
            last: true
            text: Tr.t("Xabarlarni imzolash")
            toggle: true; chevron: false
            on: !!page.group && !!page.group.sign_messages
            onClicked: store.send({ "@type": "toggleSupergroupSignMessages", supergroup_id: page.chat.type.supergroup_id,
                                    sign_messages: !on, show_message_sender: false }, (r) => {
                if (r["@type"] === "error")
                    page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            })
        }
    }

    // ---- who is in it ----
    SettingsGroup {
        SettingsRow {
            icon: "person"; tint: "#3478f6"
            visible: !page.channel
            text: Tr.t("A'zolar")
            value: page.full ? String(page.people) : ""
            onClicked: page.open("MembersPage.qml", { mode: "members" })
        }
        SettingsRow {
            icon: "lock"; tint: "#ff9500"
            visible: !page.channel && page.can("can_restrict_members")
            text: Tr.t("Ruxsatlar")
            value: page.permText
            onClicked: page.open("PermissionsPage.qml", {})
        }
        SettingsRow {
            icon: "star"; tint: "#34c759"
            text: Tr.t("Administratorlar")
            value: page.full ? String(page.admins) : ""
            onClicked: page.open("MembersPage.qml", { mode: "admins" })
        }
        SettingsRow {
            icon: "person"; tint: "#34c759"
            visible: page.channel && (page.can("can_invite_users") || page.can("can_restrict_members") || page.owner)
            text: Tr.t("Obunachilar")
            value: page.full ? String(page.people) : ""
            onClicked: page.open("MembersPage.qml", { mode: "members" })
        }
        SettingsRow {
            icon: "hand"; tint: "#3478f6"
            visible: page.can("can_invite_users") && (page.channel || (store.seen, !!page.chat && !!page.chat.pending_join_requests
                                                                       && page.chat.pending_join_requests.total_count > 0))
            text: Tr.t("Qo'shilish so'rovlari")
            value: (store.seen, page.chat && page.chat.pending_join_requests ? String(page.chat.pending_join_requests.total_count) : "")
            onClicked: page.open("JoinRequestsPage.qml", {})
        }
        SettingsRow {
            art: "block"
            visible: page.superg && page.can("can_restrict_members")
            text: Tr.t(page.channel ? "Chetlatilganlar" : "Bloklanganlar")
            value: page.full && page.full.banned_count ? String(page.full.banned_count) : ""
            onClicked: page.open("MembersPage.qml", { mode: "banned" })
        }
        SettingsRow {
            icon: "timer"; tint: "#ffcc00"
            visible: page.superg
            last: !(page.full && page.full.can_get_statistics)
            text: Tr.t("So'nggi amallar")
            onClicked: page.open("RecentActionsPage.qml", {})
        }
        SettingsRow {
            icon: "data"; tint: "#af52de"
            visible: !!page.full && !!page.full.can_get_statistics
            last: true
            text: Tr.t("Statistika")
            onClicked: page.open("StatsPage.qml", {})
        }
    }

    SettingsGroup {
        visible: page.owner
        SettingsRow {
            text: Tr.t(page.channel ? "Kanalni o'chirish" : "Guruhni o'chirish")
            danger: true; chevron: false; last: true
            onClicked: page.askDelete()
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
