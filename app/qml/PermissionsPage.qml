// Permissions (Telegram-iOS's ChannelPermissionsController): «BU GURUH A'ZOLARI NIMA QILA OLADI?» — a switch for each
// chatPermissions field, red when off; «Media yuborish N/M» opens its ten (photos … polls, reactions); then «Xabarlar
// uchun yulduz» (when the group may: setChatPaidMessageStarCount), «SEKIN REJIM» (Off…1h, setChatSlowModeDelay),
// «Bloklanganlar», «ISTISNOLAR» (who has their own: getSupergroupMembers Restricted; «Istisno qo'shish»).
// The group's switches go 0.6 s after the last tap (setChatPermissions).
// With `userId`: one member's exception (iOS's ChannelBannedMemberController) — what the group lets, each can be taken
// from them; «Saqlash» (setChatMemberStatus Restricted), «Istisnoni olib tashlash» (back to a member).
// Slow mode and exceptions need a supergroup: a basic group is made one first (store.upgrade).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property bool follows: true
    property var userId: 0              // (one member's exception)
    property var member: null           // (their chatMember, when they have one)
    readonly property bool one: !!userId
    readonly property var chat: (store.seen, store.chats[chatId])
    readonly property bool superg: !!chat && chat.type["@type"] === "chatTypeSupergroup"
    readonly property var group: (store.seen, store.groupOf(chat))
    readonly property var u: (store.seen, store.users[userId])
    readonly property var media: ["can_send_photos", "can_send_videos", "can_send_other_messages", "can_send_audios",
        "can_send_documents", "can_send_voice_notes", "can_send_video_notes", "can_add_link_previews", "can_send_polls",
        "can_react_to_messages"]
    readonly property var rest: ["can_invite_users", "can_pin_messages", "can_edit_tag", "can_change_info"]
        .concat(group && group.is_forum ? ["can_create_topics"] : [])
    readonly property var names: ({
        can_send_basic_messages: "Xabar yuborish", can_send_photos: "Rasmlar", can_send_videos: "Videolar",
        can_send_other_messages: "Stiker va GIF", can_send_audios: "Musiqa", can_send_documents: "Fayllar",
        can_send_voice_notes: "Ovozli xabarlar", can_send_video_notes: "Video xabarlar",
        can_add_link_previews: "Havola ko'rinishlari", can_send_polls: "So'rovnomalar", can_react_to_messages: "Reaksiyalar",
        can_invite_users: "A'zo qo'shish", can_pin_messages: "Xabarlarni qadash", can_edit_tag: "O'z yorlig'ini o'zgartirish",
        can_change_info: "Guruh ma'lumotini o'zgartirish", can_create_topics: "Mavzu ochish" })
    readonly property var groupPerms: chat ? chat.permissions : ({})
    property var on: ({})
    property bool expanded: false       // the media's ten shown
    property var full: null
    property var exceptions: []
    property int slow: 0
    readonly property var slowSteps: [0, 5, 10, 30, 60, 300, 900, 3600]
    readonly property var starSteps: [1, 5, 10, 50, 100, 500, 1000, 10000]
    readonly property int starsNow: (store.seen, page.group ? page.group.paid_message_star_count || 0 : 0)
    property int starIdx: 2
    onStarsNowChanged: if (starsNow > 0 && starSteps.indexOf(starsNow) >= 0) starIdx = starSteps.indexOf(starsNow)
    property int lasts: 0
    readonly property var times: [{ t: Tr.t("1 kun"), v: 86400 }, { t: Tr.t("1 hafta"), v: 604800 },
                                  { t: Tr.t("1 oy"), v: 2592000 }, { t: Tr.t("Cheklanmagan"), v: 0 }]
    readonly property int mediaOn: (on, media.filter((k) => on[k]).length)
    title: one ? Tr.t(member ? "Istisno" : "Yangi istisno") : Tr.t("Ruxsatlar")
    action: one ? Tr.t("Saqlash") : ""
    actionBold: true
    onActed: saveOne()

    Component.onCompleted: {
        const from = one && member && member.status.permissions ? member.status.permissions : groupPerms
        const o = {}
        for (const k of ["can_send_basic_messages"].concat(media, rest))
            o[k] = !!from[k] && (!one || !!groupPerms[k])
        on = o
        if (one && member && member.status.restricted_until_date > 0)
            lasts = -1
        if (one && !u)
            store.send({ "@type": "getUser", user_id: userId }, () => {})
        load()
    }
    onVisibleChanged: if (visible && !one) load()      // (back from an exception)
    onChatIdChanged: load()
    function load() {
        if (one || !chat)
            return
        if (!superg) {
            full = { slow_mode_delay: 0 }
            exceptions = []
            return
        }
        store.send({ "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }, (r) => {
            if (r["@type"] === "error")
                return
            page.full = r
            page.slow = Math.max(0, page.slowSteps.indexOf(r.slow_mode_delay))
        })
        store.send({ "@type": "getSupergroupMembers", supergroup_id: chat.type.supergroup_id,
                     filter: { "@type": "supergroupMembersFilterRestricted", query: "" }, offset: 0, limit: 200 }, (r) => {
            if (r["@type"] === "chatMembers")
                page.exceptions = r.members
        })
    }

    function perms() {
        const p = { "@type": "chatPermissions" }
        for (const k of ["can_send_basic_messages"].concat(page.media, page.rest))
            p[k] = !!on[k]
        if (!("can_create_topics" in p))       // (no topics: as it was)
            p.can_create_topics = !!groupPerms.can_create_topics
        return p
    }
    function flip(keys, want) {
        if (one && keys.some((k) => !groupPerms[k]))
            return nav.say(Tr.t("Bu guruhda hammaga taqiqlangan — avval guruh ruxsatlarida yoqing."))
        const o = Object.assign({}, on)
        for (const k of keys)
            o[k] = want
        on = o
        if (!one)
            soon.restart()
    }
    Timer {
        id: soon
        interval: 600
        onTriggered: store.send({ "@type": "setChatPermissions", chat_id: page.chatId, permissions: page.perms() }, (r) => {
            if (r["@type"] === "error")
                page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
        })
    }
    function setSlow(i) {
        slow = i
        slowSoon.restart()
    }
    Timer {
        id: slowSoon
        interval: 600
        onTriggered: {
            const secs = page.slowSteps[page.slow]
            if (!page.superg && !secs)
                return
            store.upgrade(page.chatId, page.nav, (id) => store.send({ "@type": "setChatSlowModeDelay", chat_id: id, slow_mode_delay: secs }, (r) => {
                if (r["@type"] === "error")
                    page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            }))
        }
    }
    function paid(count) {
        if (!full || !full.can_enable_paid_messages)
            return nav.say(Tr.t("Guruh yetarlicha katta emas — bu imkoniyat hali yopiq."))
        store.send({ "@type": "setChatPaidMessageStarCount", chat_id: chatId, paid_message_star_count: count }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
        })
    }
    Timer {
        id: starSoon
        interval: 600
        onTriggered: page.paid(page.starSteps[page.starIdx])
    }
    function saveOne() {
        const until = lasts > 0 ? Math.floor(Date.now() / 1000) + lasts : lasts < 0 && member ? member.status.restricted_until_date : 0
        store.upgrade(chatId, nav, (id) => store.send({ "@type": "setChatMemberStatus", chat_id: id,
                member_id: { "@type": "messageSenderUser", user_id: page.userId },
                status: { "@type": "chatMemberStatusRestricted", is_member: true, restricted_until_date: until, permissions: page.perms() } }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t("Istisno saqlandi"))
            page.nav.pop()
        }))
    }
    function dropOne() {
        store.send({ "@type": "setChatMemberStatus", chat_id: chatId, member_id: { "@type": "messageSenderUser", user_id: userId },
                     status: { "@type": "chatMemberStatusMember", member_until_date: 0 } }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.pop()
        })
    }
    function addException() {
        store.upgrade(chatId, nav, (id) => page.nav.push(Qt.createComponent("MembersPage.qml"),
                                                         { chatId: id, mode: "members", restrict: true }))
    }
    function openException(m) {
        nav.push(Qt.createComponent("PermissionsPage.qml"), { chatId: chatId, userId: m.member_id.user_id, member: m })
    }
    // what an exception takes away, in a few words
    function taken(m) {
        const p = m.status.permissions || {}
        const no = ["can_send_basic_messages"].concat(media, rest).filter((k) => groupPerms[k] && !p[k])
        const s = !no.length ? Tr.t("hamma narsa mumkin")
                : no.length === 1 ? Tr.f("mumkin emas: %1", Tr.t(names[no[0]]).toLowerCase())
                : Tr.n("%1 ta cheklov", no.length)
        return m.status.restricted_until_date > 0
            ? s + " · " + Tr.f("%1 gacha", Qt.formatDateTime(new Date(m.status.restricted_until_date * 1000), "dd.MM.yyyy hh:mm")) : s
    }

    // ---- one member: who ----
    SettingsGroup {
        visible: page.one
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
                text: (store.seen, store.userStatus(page.u, Date.now() / 1000)) || Tr.t("a'zo")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
        }
    }

    // ---- what members (or this one) may do ----
    SettingsGroup {
        title: Tr.t(page.one ? "Bu a'zo nima qila oladi?" : "Bu guruh a'zolari nima qila oladi?")
        SettingsRow {
            text: Tr.t(page.names.can_send_basic_messages)
            toggle: true; chevron: false; redOff: true
            dim: page.one && !page.groupPerms.can_send_basic_messages
            on: !!page.on.can_send_basic_messages
            onClicked: page.flip(["can_send_basic_messages"], !on)
        }
        Item {          // «Media yuborish 10/10 ⌄»: the left opens the ten, the switch all of them
            id: mediaRow
            width: parent.width; height: 46
            readonly property bool all: page.mediaOn === page.media.length
            Rectangle { anchors.fill: parent; color: Theme.highlight; visible: openHit.pressed }
            Row {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                    text: Tr.t("Media yuborish")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.mediaOn + "/" + page.media.length
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12; height: 12
                    name: "chevron"
                    rotation: page.expanded ? 180 : 0
                    color: Theme.text
                    Behavior on rotation { NumberAnimation { duration: 200 } }
                }
            }
            MouseArea { id: openHit; width: parent.width - 80; height: parent.height; onClicked: page.expanded = !page.expanded }
            Switch {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                on: page.mediaOn > 0
                redOff: true
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: page.flip(page.media.filter((k) => !page.one || page.groupPerms[k]), page.mediaOn === 0) }
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
        }
        Repeater {
            model: page.expanded ? page.media : []
            SettingsRow {
                required property var modelData
                x: 20; width: parent.width - 20
                text: Tr.t(page.names[modelData])
                toggle: true; chevron: false
                dim: page.one && !page.groupPerms[modelData]
                on: !!page.on[modelData]
                onClicked: page.flip([modelData], !on)
            }
        }
        Repeater {
            model: page.rest
            SettingsRow {
                required property var modelData
                required property int index
                text: Tr.t(page.names[modelData])
                toggle: true; chevron: false; redOff: true
                dim: page.one && !page.groupPerms[modelData]
                last: index === page.rest.length - 1
                on: !!page.on[modelData]
                onClicked: page.flip([modelData], !on)
            }
        }
    }

    // ---- the group's: paid messages, slow mode, removed, exceptions ----
    SettingsGroup {
        visible: !page.one && page.superg
        note: Tr.t("Yoqilsa, oddiy a'zolar guruhga xabar yuborish uchun yulduz to'laydi.")
        SettingsRow {
            text: Tr.t("Xabarlar uchun yulduz")
            value: page.starsNow > 0 ? "⭐ " + store.count(page.starsNow) : ""
            toggle: true; chevron: false; last: page.starsNow <= 0
            dim: !page.full || !page.full.can_enable_paid_messages
            on: page.starsNow > 0
            onClicked: page.paid(page.starsNow <= 0 ? page.starSteps[page.starIdx] : 0)
        }
        StepSlider {
            visible: page.starsNow > 0
            labels: ["1", "5", "10", "50", "100", "500", "1K", "10K"]
            value: page.starIdx
            onMoved: (v) => { page.starIdx = v; starSoon.restart() }
        }
    }
    SettingsGroup {
        visible: !page.one
        title: Tr.t("Sekin rejim")
        note: Tr.t("Har bir a'zo keyingi xabarini yuborishdan oldin qancha kutishini tanlang.")
        StepSlider {
            labels: [Tr.t("Yo'q"), "5s", "10s", "30s", "1m", "5m", "15m", "1h"]
            value: page.slow
            onMoved: (v) => page.setSlow(v)
        }
    }
    SettingsGroup {
        visible: !page.one && page.superg
        SettingsRow {
            text: Tr.t("Bloklanganlar")
            value: page.full && page.full.banned_count ? String(page.full.banned_count) : ""
            last: true
            onClicked: page.nav.push(Qt.createComponent("MembersPage.qml"), { chatId: page.chatId, mode: "banned" })
        }
    }
    SettingsGroup {
        visible: !page.one
        title: Tr.t("Istisnolar")
        SettingsRow {
            icon: "person"; tint: Theme.accent; accent: true; chevron: false
            last: page.exceptions.length === 0
            text: Tr.t("Istisno qo'shish")
            onClicked: page.addException()
        }
        Repeater {
            model: page.exceptions
            Rectangle {
                id: ex
                required property var modelData
                required property int index
                readonly property var who: modelData.member_id
                readonly property var eu: (store.seen, store.users[who.user_id])
                property string photo: ""
                width: parent.width; height: 56
                color: exHit.pressed ? Theme.highlight : "transparent"
                Component.onCompleted: if (eu) store.userPhoto(eu, (p) => ex.photo = p)
                Avatar {
                    x: 14; y: 8; width: 40; height: 40
                    source: ex.photo
                    letters: store.letters(store.senderName(ex.who, false))
                    tint: store.tints[Math.abs(ex.who.user_id || 0) % store.tints.length]
                }
                Text {
                    x: 66; y: 8; width: parent.width - x - 14
                    elide: Text.ElideRight
                    text: store.senderName(ex.who, false) || Tr.t("O'chirilgan hisob")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    x: 66; y: 30; width: parent.width - x - 14
                    elide: Text.ElideRight
                    text: page.taken(ex.modelData)
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Rectangle {
                    visible: ex.index < page.exceptions.length - 1
                    x: 66; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator
                }
                MouseArea { id: exHit; anchors.fill: parent; onClicked: page.openException(ex.modelData) }
            }
        }
    }

    SettingsGroup {
        visible: page.one
        title: Tr.t("Amal qilish muddati")
        note: Tr.t("Shu muddat tugagach, a'zo guruhning umumiy ruxsatlariga qaytadi.")
        Flow {
            x: 12; width: parent.width - 24
            topPadding: 12; bottomPadding: 12
            spacing: 8
            Repeater {
                model: (page.member && page.member.status.restricted_until_date > 0
                        ? [{ t: Tr.f("%1 gacha", Qt.formatDateTime(new Date(page.member.status.restricted_until_date * 1000), "dd.MM.yyyy hh:mm")), v: -1 }] : [])
                       .concat(page.times)
                Rectangle {
                    required property var modelData
                    readonly property bool on: page.lasts === modelData.v
                    width: chipText.width + 24; height: 32; radius: 16
                    color: on ? Theme.accent : Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06)
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        color: parent.on ? "white" : Theme.text
                        font.family: Theme.font; font.pixelSize: 15
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.lasts = parent.modelData.v }
                }
            }
        }
    }
    SettingsGroup {
        visible: page.one && !!page.member
        SettingsRow { text: Tr.t("Istisnoni olib tashlash"); danger: true; chevron: false; last: true; onClicked: page.dropOne() }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
