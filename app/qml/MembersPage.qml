// Who is in a channel or group we run (Telegram-iOS's ChannelAdminsController, ChannelMembersController,
// ChannelBlacklistController): mode "admins" (owner, admins with their titles; «Admin qo'shish»), "members"
// (search; a tap: make admin, remove), "banned" (a tap: let back). getSupergroupMembers by its filter; a person's
// rights in AdminRightsPage. `promote`: picking someone to make an admin (the admins page's «Admin qo'shish»);
// `ban`: someone to remove (the removed page's «Foydalanuvchini chiqarish»);
// `restrict`: someone to give an exception (PermissionsPage's «Istisno qo'shish»). A group's members: «A'zolarni
// yashirish» (toggleSupergroupHasHiddenMembers, when it may), «A'zo qo'shish» (addChatMembers), «Havola orqali taklif
// qilish». A basic group: its members all come with getBasicGroupFullInfo (searched here; none removed).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    property string mode: "members"
    property bool promote: false
    property bool restrict: false
    property bool ban: false
    readonly property bool follows: true
    readonly property var chat: store.chats[chatId]
    readonly property bool channel: !!chat && !!chat.type.is_channel
    readonly property bool superg: !!chat && chat.type["@type"] === "chatTypeSupergroup"
    readonly property bool picking: promote || restrict || ban
    readonly property var group: (store.seen, store.groupOf(chat))
    property var full: null             // (a supergroup's: may its members be hidden)
    readonly property var st: group ? group.status : null
    readonly property bool owner: !!st && st["@type"] === "chatMemberStatusCreator"
    function can(r) { return owner || (!!st && !!st.rights && !!st.rights[r]) }
    property var people: []
    property int total: 0
    property real now: Date.now() / 1000
    title: promote ? Tr.t("Admin qo'shish") : restrict ? Tr.t("Istisno qo'shish") : ban ? Tr.t("Foydalanuvchini chiqarish") : mode === "admins" ? Tr.t("Administratorlar")
         : mode === "banned" ? Tr.t(channel ? "Chetlatilganlar" : "Bloklanganlar") : Tr.t(channel ? "Obunachilar" : "A'zolar")

    Component.onCompleted: load()
    onVisibleChanged: if (visible) load()
    onChatIdChanged: load()
    function load() {
        const q = query.text.trim()
        if (!superg) {
            store.send({ "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id }, (r) => {
                if (r["@type"] === "error")
                    return
                const words = q.toLowerCase()
                const all = (r.members || []).filter((m) => {
                    const k = m.status["@type"]
                    if (page.mode === "admins")
                        return k === "chatMemberStatusCreator" || k === "chatMemberStatusAdministrator"
                    if (page.mode === "banned")
                        return false
                    return !words || store.senderName(m.member_id, false).toLowerCase().indexOf(words) >= 0
                })
                page.total = all.length
                page.people = all
            })
            return
        }
        if (mode === "members" && !channel && !picking)
            store.send({ "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }, (r) => {
                if (r["@type"] !== "error")
                    page.full = r
            })
        const filter = mode === "admins" ? { "@type": "supergroupMembersFilterAdministrators" }
                     : mode === "banned" ? { "@type": "supergroupMembersFilterBanned", query: q }
                     : q ? { "@type": "supergroupMembersFilterSearch", query: q } : { "@type": "supergroupMembersFilterRecent" }
        store.send({ "@type": "getSupergroupMembers", supergroup_id: chat.type.supergroup_id, filter: filter, offset: 0, limit: 200 }, (r) => {
            if (r["@type"] !== "chatMembers")
                return
            page.total = r.total_count
            page.people = r.members
        })
    }
    Timer { id: soon; interval: 350; onTriggered: page.load() }

    function role(m) {
        const s = m.status
        if (s["@type"] === "chatMemberStatusCreator")
            return s.custom_title || Tr.t("egasi")
        if (s["@type"] === "chatMemberStatusAdministrator") {
            const by = m.inviter_user_id && store.users[m.inviter_user_id] ? store.users[m.inviter_user_id].first_name : ""
            return (s.custom_title || Tr.t("admin")) + (by ? " · " + Tr.f("%1 tayinlagan", by) : "")
        }
        if (s["@type"] === "chatMemberStatusBanned") {
            const by = m.inviter_user_id && store.users[m.inviter_user_id] ? store.users[m.inviter_user_id].first_name : ""
            return by ? Tr.f("%1 chetlatgan", by) : Tr.t("chetlatilgan")
        }
        return ""
    }
    function userOf(m) { return m.member_id["@type"] === "messageSenderUser" ? m.member_id.user_id : 0 }
    function profile(m) {
        const uid = userOf(m)
        if (!uid)
            return
        store.send({ "@type": "createPrivateChat", user_id: uid, force: false }, (r) => {
            if (r["@type"] === "chat")
                page.nav.push(Qt.createComponent("ChatInfoPage.qml"), { chatId: r.id })
        })
    }
    function hide() {
        if (!full || !(full.can_hide_members || full.has_hidden_members))
            return nav.say(Tr.t("A'zolarni yashirish 100 dan ortiq a'zosi bo'lgan guruhlarda mumkin."))
        const want = !full.has_hidden_members
        full = Object.assign({}, full, { has_hidden_members: want })
        store.send({ "@type": "toggleSupergroupHasHiddenMembers", supergroup_id: chat.type.supergroup_id, has_hidden_members: want }, (r) => {
            if (r["@type"] === "error") {
                page.full = Object.assign({}, page.full, { has_hidden_members: !want })
                page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            }
        })
    }
    function add() { store.addMembers(chatId, nav, () => page.load()) }
    function rights(m, adding) {
        nav.push(Qt.createComponent("AdminRightsPage.qml"), { chatId: chatId, userId: userOf(m), member: adding ? null : m })
    }
    function setStatus(m, status, said) {
        store.send({ "@type": "setChatMemberStatus", chat_id: chatId, member_id: m.member_id, status: status }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(said)
            page.load()
        })
    }
    function tap(m) {
        const k = m.status["@type"], uid = userOf(m), mine = store.me && uid === store.me.id
        const name = store.senderName(m.member_id, false)
        if (promote)
            return rights(m, k !== "chatMemberStatusAdministrator")
        if (ban) {
            if (k === "chatMemberStatusCreator" || k === "chatMemberStatusAdministrator" || mine)
                return nav.say(Tr.t("Adminni chiqarib bo'lmaydi — avval adminlikdan oling"))
            alert.title = ""
            alert.text = Tr.f(channel ? "%1 kanaldan chiqarilsinmi? U havola orqali qaytib kira olmaydi."
                                      : "%1 guruhdan chiqarilsinmi? U havola orqali qaytib qo'shila olmaydi.", name)
            alert.vertical = false
            alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Chiqarish"), red: true, run: () => store.send(
                { "@type": "setChatMemberStatus", chat_id: page.chatId, member_id: m.member_id,
                  status: { "@type": "chatMemberStatusBanned", banned_until_date: 0 } }, (r) => {
                    if (r["@type"] === "error")
                        return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                    page.nav.say(Tr.f("%1 chetlatildi", name))
                    page.nav.pop()
                }) }]
            alert.open = true
            return
        }
        if (restrict) {
            if (k === "chatMemberStatusCreator" || k === "chatMemberStatusAdministrator" || mine)
                return nav.say(Tr.t("Adminlarni cheklab bo'lmaydi"))
            return nav.push(Qt.createComponent("PermissionsPage.qml"), { chatId: chatId, userId: uid,
                                                                         member: k === "chatMemberStatusRestricted" ? m : null })
        }
        if (mode === "admins" && k === "chatMemberStatusAdministrator" && (owner || m.status.can_be_edited) && !mine)
            return rights(m, false)
        const out = []
        if (uid)
            out.push({ t: Tr.t("Profilni ochish"), run: () => page.profile(m) })
        if (mode === "banned" && can("can_restrict_members"))
            out.push({ t: Tr.t("Blokdan chiqarish"), run: () => page.setStatus(m, { "@type": "chatMemberStatusLeft" },
                                                                               Tr.f("%1 blokdan chiqarildi", name)) })
        if (mode === "members" && !mine && k === "chatMemberStatusMember") {
            if (can("can_promote_members") && uid)
                out.push({ t: Tr.t("Admin qilish"), run: () => page.rights(m, true) })
            if (can("can_restrict_members"))
                out.push({ t: Tr.t(channel ? "Kanaldan chiqarish" : "Guruhdan chiqarish"), red: true, run: () => page.setStatus(m,
                           { "@type": "chatMemberStatusBanned", banned_until_date: 0 }, Tr.f("%1 chetlatildi", name)) })
        }
        if (!out.length)
            return
        out.push({ t: Tr.t("Bekor qilish") })
        alert.title = ""
        alert.text = name
        alert.vertical = true
        alert.answers = out
        alert.open = true
    }

    SettingsGroup {
        visible: page.mode !== "admins"
        Item {
            width: parent.width; height: 40
            Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "search"; color: Theme.grey }
            TextInput {
                id: query
                x: 38; width: parent.width - 50
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                onTextChanged: soon.restart()
            }
            Text {
                x: 38; anchors.verticalCenter: parent.verticalCenter
                visible: !query.text
                text: Tr.t("Qidirish")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
        }
    }

    // ---- a group's: hide them, add some, a link ----
    SettingsGroup {
        id: groupRows
        visible: page.mode === "members" && !page.channel && !page.picking
        readonly property bool mayHide: !!page.full && (page.full.can_hide_members || page.full.has_hidden_members)
        SettingsRow {
            visible: page.owner || page.can("can_restrict_members")
            text: Tr.t("A'zolarni yashirish")
            sub: Tr.t("Yoqilsa, guruh a'zolari ro'yxati yashiriladi. Adminlar ko'rinib turadi.")
            toggle: true; chevron: false
            dim: !groupRows.mayHide
            on: !!page.full && !!page.full.has_hidden_members
            onClicked: page.hide()
        }
        SettingsRow {
            visible: page.can("can_invite_users") || !!(page.chat && page.chat.permissions && page.chat.permissions.can_invite_users)
            icon: "person"; tint: Theme.accent; accent: true; chevron: false
            text: Tr.t("A'zo qo'shish")
            onClicked: page.add()
        }
        SettingsRow {
            visible: page.can("can_invite_users")
            icon: "clip"; tint: Theme.accent; accent: true; chevron: false; last: true
            text: Tr.t("Havola orqali taklif qilish")
            onClicked: page.nav.push(Qt.createComponent("InviteLinksPage.qml"), { chatId: page.chatId })
        }
    }

    SettingsGroup {
        note: page.mode === "admins" ? Tr.t(page.channel ? "Adminlar kanalni boshqarishda yordam beradi. Har birining huquqlarini alohida sozlang."
                                                         : "Adminlar guruhni boshqarishda yordam beradi. Har birining huquqlarini alohida sozlang.")
            : page.mode === "banned" ? Tr.t(page.channel ? "Chetlatilganlar havola orqali qaytib obuna bo'la olmaydi."
                                                         : "Bloklanganlar havola orqali qaytib qo'shila olmaydi.")
            : page.people.length < page.total ? Tr.f("Faqat so'nggi %1 kishi ko'rinadi; qolganini qidiring.", page.people.length) : ""
        SettingsRow {
            visible: page.mode === "banned" && page.can("can_restrict_members")
            icon: "person"; tint: Theme.danger; danger: true; chevron: false
            last: page.people.length === 0
            text: Tr.t("Foydalanuvchini chiqarish")
            onClicked: page.nav.push(Qt.createComponent("MembersPage.qml"), { chatId: page.chatId, mode: "members", ban: true })
        }
        SettingsRow {
            visible: page.mode === "admins" && !page.promote && page.can("can_promote_members")
            icon: "person"; tint: Theme.accent; accent: true; chevron: false
            text: Tr.t("Admin qo'shish")
            onClicked: page.nav.push(Qt.createComponent("MembersPage.qml"), { chatId: page.chatId, mode: "members", promote: true })
        }
        Repeater {
            model: page.people
            Rectangle {
                id: person
                required property var modelData
                required property int index
                readonly property var who: modelData.member_id
                readonly property var u: who["@type"] === "messageSenderUser" ? (store.seen, store.users[who.user_id]) : null
                readonly property string name: store.senderName(who, false) || Tr.t("O'chirilgan hisob")
                width: parent.width; height: 56
                color: hit.pressed ? Theme.highlight : "transparent"
                property string photo: ""
                Component.onCompleted: {
                    if (u)
                        store.userPhoto(u, (p) => person.photo = p)
                    else if (store.chats[who.chat_id] && store.chats[who.chat_id].photo)
                        store.fetch(store.chats[who.chat_id].photo.small, 1, (p) => person.photo = p)
                }
                Avatar {
                    x: 14; y: 8
                    width: 40; height: 40
                    source: person.photo
                    letters: store.letters(person.name)
                    tint: store.tints[Math.abs(person.who.user_id || person.who.chat_id) % store.tints.length]
                }
                Text {
                    x: 66; y: 8
                    width: parent.width - x - 14
                    elide: Text.ElideRight
                    text: person.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    x: 66; y: 30
                    width: parent.width - x - 14
                    elide: Text.ElideRight
                    text: page.role(person.modelData) || (store.seen, store.userStatus(person.u, page.now))
                    color: text === Tr.t("onlayn") ? Theme.accent : Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Rectangle {
                    visible: person.index < page.people.length - 1
                    x: 66; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator
                }
                MouseArea { id: hit; anchors.fill: parent; onClicked: page.tap(person.modelData) }
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
