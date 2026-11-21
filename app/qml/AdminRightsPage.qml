// An admin's rights (Telegram-iOS's ChannelAdminController): who (picture, name), what they may do — a switch for
// each chatAdministratorRights field a channel (or a group) has, the ones we lack ourselves dim; a group's admin
// also a title; «Saqlash» (setChatMemberStatus Administrator), «Adminlikdan olish» (back to a member). A basic group
// is made a supergroup first (its admins' rights can't be chosen one by one).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    property var userId: 0
    property var member: null           // chatMember (an admin now), null: being made one
    readonly property bool follows: true
    readonly property var chat: store.chats[chatId]
    readonly property bool channel: !!chat && !!chat.type.is_channel
    readonly property var group: (store.seen, store.groupOf(chat))
    readonly property bool owner: !!group && group.status["@type"] === "chatMemberStatusCreator"
    readonly property var u: (store.seen, store.users[userId])
    readonly property var keys: channel
        ? ["can_change_info", "can_post_messages", "can_edit_messages", "can_delete_messages", "can_invite_users",
           "can_manage_direct_messages", "can_manage_video_chats", "can_post_stories", "can_edit_stories", "can_delete_stories",
           "can_promote_members"]
        : ["can_change_info", "can_delete_messages", "can_restrict_members", "can_invite_users", "can_pin_messages",
           "can_manage_video_chats", "can_post_stories", "can_edit_stories", "can_delete_stories", "is_anonymous",
           "can_promote_members"]
    readonly property var names: ({
        can_change_info: channel ? "Kanal ma'lumotini o'zgartirish" : "Guruh ma'lumotini o'zgartirish",
        can_post_messages: "Post joylash", can_edit_messages: "Postlarni tahrirlash",
        can_delete_messages: channel ? "Postlarni o'chirish" : "Xabarlarni o'chirish",
        can_invite_users: channel ? "Obunachi qo'shish" : "Foydalanuvchi qo'shish",
        can_manage_direct_messages: "Kanal xabarlarini boshqarish",
        can_restrict_members: "Foydalanuvchilarni bloklash", can_pin_messages: "Xabarlarni qadash",
        can_manage_video_chats: "Jonli efirlarni boshqarish", can_post_stories: "Hikoya joylash",
        can_edit_stories: "Hikoyalarni tahrirlash", can_delete_stories: "Hikoyalarni o'chirish",
        is_anonymous: "Anonim qolish", can_promote_members: "Yangi admin qo'shish" })
    property var on: ({})
    title: Tr.t(member ? "Admin huquqlari" : "Yangi admin")
    action: Tr.t("Saqlash")
    actionBold: true
    onActed: save()
    Component.onCompleted: {
        const r = member ? member.status.rights : null, o = {}
        for (const k of keys)
            o[k] = r ? !!r[k] : k !== "is_anonymous" && k !== "can_promote_members" && mayGive(k)
        on = o
        if (member)
            titleIn.text = member.status.custom_title || ""
        if (!u)
            store.send({ "@type": "getUser", user_id: userId }, () => {})
    }
    function mayGive(k) { return owner || (!!group && !!group.status.rights && !!group.status.rights[k]) }
    function flip(k) {
        if (!mayGive(k))
            return nav.say(Tr.t("Sizda bu huquq yo'q, shuning uchun bera olmaysiz."))
        const o = Object.assign({}, on)
        o[k] = !o[k]
        on = o
    }
    function save() {
        const rights = { "@type": "chatAdministratorRights", can_manage_chat: true }
        for (const k of keys)
            rights[k] = !!on[k]
        store.upgrade(chatId, nav, (id) => store.send({ "@type": "setChatMemberStatus", chat_id: id,
                     member_id: { "@type": "messageSenderUser", user_id: userId },
                     status: { "@type": "chatMemberStatusAdministrator", custom_title: channel ? "" : titleIn.text.trim(),
                               can_be_edited: true, rights: rights } }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(page.member ? "Huquqlar saqlandi" : "Admin qo'shildi"))
            page.nav.pop()
        }))
    }
    function dismiss() {
        alert.title = ""
        alert.text = Tr.f("%1 adminlikdan olinsinmi?", u ? u.first_name : "")
        alert.vertical = false
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Olish"), red: true, run: () => store.send(
            { "@type": "setChatMemberStatus", chat_id: page.chatId, member_id: { "@type": "messageSenderUser", user_id: page.userId },
              status: { "@type": "chatMemberStatusMember", member_until_date: 0 } }, (r) => {
                if (r["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                page.nav.pop()
            }) }]
        alert.open = true
    }

    SettingsGroup {
        Item {
            id: who
            width: parent.width; height: 68
            property string photo: ""
            Component.onCompleted: if (page.u) store.userPhoto(page.u, (p) => who.photo = p)
            Avatar {
                x: 14; y: 10; width: 48; height: 48
                source: who.photo
                letters: store.letters(page.u ? page.u.first_name + " " + page.u.last_name : "")
                tint: store.tints[Math.abs(page.userId) % store.tints.length]
            }
            Text {
                x: 74; y: 14; width: parent.width - x - 14
                elide: Text.ElideRight
                text: page.u ? (page.u.first_name + " " + page.u.last_name).trim() : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                x: 74; y: 38
                text: page.member ? Tr.t("admin") : Tr.t(page.channel ? "obunachi" : "a'zo")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
        }
    }
    SettingsGroup {
        title: Tr.t("Bu admin nimalar qila oladi?")
        Repeater {
            model: page.keys
            SettingsRow {
                required property var modelData
                required property int index
                text: Tr.t(page.names[modelData])
                toggle: true; chevron: false
                dim: !page.mayGive(modelData)
                on: !!page.on[modelData]
                last: index === page.keys.length - 1
                onClicked: page.flip(modelData)
            }
        }
    }
    SettingsGroup {
        visible: !page.channel
        title: Tr.t("Admin unvoni")
        note: Tr.t("Guruhda bu adminning xabarlari yonida «admin» o'rniga shu so'z chiqadi.")
        Item {
            width: parent.width; height: 48
            TextInput {
                id: titleIn
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                maximumLength: 16
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
            }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                visible: !titleIn.text
                text: Tr.t("admin")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
        }
    }
    Item { width: 1; height: page.channel ? 0 : 24 }
    SettingsGroup {
        visible: !!page.member
        SettingsRow { text: Tr.t("Adminlikdan olish"); danger: true; chevron: false; last: true; onClicked: page.dismiss() }
    }
    Item { width: 1; height: 30 + safe.bottom }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
