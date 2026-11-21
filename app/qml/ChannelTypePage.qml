// Channel Type (Telegram-iOS's ChannelVisibilityController): Public or Private; public — its t.me/ name, checked as it
// is typed (checkChatUsername); private — the primary invite link (copy, revoke). «Tarkibni himoyalash» (Restrict
// Saving Content: toggleChatHasProtectedContent). «Saqlash» sets the name (setSupergroupUsername; "" = private).
// A group: «Taklif havolalarini boshqarish», «Yangi a'zolarni tasdiqlash» (toggleSupergroupJoinByRequest, its links
// too); a basic group made public (or asking approval) becomes a supergroup first (store.upgrade).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property bool follows: true
    readonly property var chat: (store.seen, store.chats[chatId])
    readonly property bool channel: !!chat && !!chat.type.is_channel
    readonly property bool superg: !!chat && chat.type["@type"] === "chatTypeSupergroup"
    readonly property var group: (store.seen, store.groupOf(chat))
    property bool approve: !!group && !!group.join_by_request
    readonly property string was: group && group.usernames && group.usernames.active_usernames.length
                                  ? group.usernames.editable_username || group.usernames.active_usernames[0] : ""
    property bool pub: was !== ""
    property string check: ""           // checkChatUsername's answer (its @type's tail), "" not yet
    property string link: ""            // the primary invite link
    property int joined: -1             // how many came by it (-1: not known)
    property bool shielded: !!chat && !!chat.has_protected_content
    readonly property bool ready: !pub || (uname.text === was && was !== "") || check === "Ok"
    title: Tr.t(channel ? "Kanal turi" : "Guruh turi")
    action: Tr.t("Saqlash")
    actionBold: true
    actionOn: ready && (pub ? uname.text !== was : was !== "")
    onActed: save()

    Component.onCompleted: {
        uname.text = was
        store.send(superg ? { "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }
                          : { "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id }, (r) => {
            if (r.invite_link) {
                page.link = r.invite_link.invite_link
                page.joined = r.invite_link.member_count || 0
            }
        })
    }
    Timer {
        id: soon
        interval: 400
        onTriggered: {
            const name = uname.text
            if (name === "" || name === page.was) {
                page.check = ""
                return
            }
            store.send({ "@type": "checkChatUsername", chat_id: page.chatId, username: name }, (r) => {
                if (uname.text === name)
                    page.check = r["@type"] === "error" ? "Invalid" : r["@type"].replace("checkChatUsernameResult", "")
            })
        }
    }
    readonly property string checkText: {
        if (!pub || uname.text === "" || uname.text === was)
            return ""
        if (uname.text.length < 4)
            return Tr.t("Nom kamida 4 belgidan iborat bo'lishi kerak.")
        switch (check) {
        case "Ok": return Tr.f("%1 bo'sh.", uname.text)
        case "UsernameOccupied": return Tr.t("Bu nom band.")
        case "UsernamePurchasable": return Tr.t("Bu nomni Fragment'da sotib olish mumkin.")
        case "PublicChatsTooMany": return Tr.t("Ommaviy kanal va guruhlaringiz juda ko'p — avval birining nomini olib tashlang.")
        case "PublicGroupsUnavailable": return Tr.t("Hozir ommaviy qilib bo'lmaydi.")
        case "": return Tr.t("Tekshirilmoqda…")
        default: return Tr.t("Nom noto'g'ri: faqat a–z, 0–9 va _.")
        }
    }
    function save() {
        const name = pub ? uname.text : ""
        store.upgrade(chatId, nav, (id) => store.send({ "@type": "setSupergroupUsername",
                                                         supergroup_id: store.chats[id].type.supergroup_id, username: name }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.pop()
        }))
    }
    function setApprove() {
        const want = !approve
        approve = want
        store.upgrade(chatId, nav, (id) => store.send({ "@type": "toggleSupergroupJoinByRequest",
                supergroup_id: store.chats[id].type.supergroup_id, join_by_request: want, guard_bot_user_id: 0,
                apply_to_invite_links: true }, (r) => {
            if (r["@type"] === "error") {
                page.approve = !want
                page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            }
        }))
    }
    TextEdit { id: clip; visible: false }
    function copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        nav.say(Tr.t("Havola nusxalandi"))
    }
    function askRevoke() {
        alert.title = ""
        alert.text = Tr.t("Havolani bekor qilasizmi? Eski havola ishlamay qoladi, yangisi yaratiladi.")
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Havolani bekor qilish"), red: true, run: () => {
            store.send({ "@type": "replacePrimaryChatInviteLink", chat_id: page.chatId }, (r) => {
                if (r["@type"] === "chatInviteLink")
                    page.link = r.invite_link
                else
                    page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            })
        } }]
        alert.open = true
    }

    SettingsGroup {
        title: Tr.t(channel ? "Kanal turi" : "Guruh turi")
        note: Tr.t(page.pub ? (page.channel ? "Ommaviy kanalni qidiruvda topish mumkin, unga istalgan kishi obuna bo'la oladi."
                                            : "Ommaviy guruhni qidiruvda topish mumkin, unga istalgan kishi qo'shila oladi.")
                            : (page.channel ? "Shaxsiy kanalga faqat taklif havolasi orqali obuna bo'lish mumkin."
                                            : "Shaxsiy guruhga faqat taklif havolasi orqali qo'shilish mumkin."))
        SettingsRow { text: Tr.t("Ommaviy"); chevron: false; tick: page.pub; onClicked: page.pub = true }
        SettingsRow { text: Tr.t("Shaxsiy"); chevron: false; tick: !page.pub; last: true; onClicked: page.pub = false }
    }

    SettingsGroup {
        visible: page.pub
        title: Tr.t("Ommaviy havola")
        note: page.checkText || Tr.t("Havolani boshqalarga yuborsangiz, ular kanalingizni topadi.")
        Item {
            width: parent.width; height: 48
            Text {
                id: pre
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: "t.me/"
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
            TextInput {
                id: uname
                x: pre.x + pre.width; width: parent.width - x - 16
                anchors.verticalCenter: parent.verticalCenter
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhPreferLowercase
                validator: RegularExpressionValidator { regularExpression: /[A-Za-z0-9_]{0,32}/ }
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                clip: true
                onTextChanged: { page.check = ""; soon.restart() }
            }
        }
    }
    SettingsGroup {
        visible: !page.pub
        title: Tr.t("Taklif havolasi")
        note: Tr.t("Shu havola orqali odamlar qo'shila oladi. Havolani istalgan vaqtda bekor qilishingiz mumkin.")
        Item {
            width: parent.width; height: 52
            Text {
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                text: page.link.replace("https://", "") || "…"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
        }
        SettingsRow {
            visible: page.joined >= 0
            text: page.joined > 0 ? Tr.n("%1 kishi qo'shildi", page.joined) : Tr.t("hali hech kim qo'shilmadi")
            chevron: false
            onClicked: page.nav.push(Qt.createComponent("InviteLinksPage.qml"), { chatId: page.chatId })
        }
        SettingsRow { text: Tr.t("Havolani nusxalash"); accent: true; chevron: false; onClicked: if (page.link) page.copy(page.link) }
        SettingsRow { text: Tr.t("Havolani bekor qilish"); danger: true; chevron: false; last: true; onClicked: page.askRevoke() }
    }
    SettingsGroup {
        visible: !page.pub
        note: Tr.t("Muddati yoki odam soni cheklangan qo'shimcha havolalar yaratishingiz mumkin.")
        SettingsRow {
            icon: "clip"; tint: Theme.accent; accent: true; chevron: false; last: true
            text: Tr.t("Taklif havolalarini boshqarish")
            onClicked: page.nav.push(Qt.createComponent("InviteLinksPage.qml"), { chatId: page.chatId })
        }
    }
    SettingsGroup {
        visible: !page.channel
        note: Tr.t("Yoqilsa, yangi a'zolar admin tasdiqlagandan keyingina xabar yoza oladi.")
        SettingsRow {
            text: Tr.t("Yangi a'zolarni tasdiqlash")
            toggle: true; chevron: false; last: true
            on: page.approve
            onClicked: page.setApprove()
        }
    }

    SettingsGroup {
        title: Tr.t("Tarkibni saqlash")
        note: Tr.t(page.channel ? "Obunachilar postlarni nusxalay, saqlay va uzata olmaydi."
                                : "A'zolar xabarlarni nusxalay, saqlay va uzata olmaydi.")
        SettingsRow {
            text: Tr.t("Tarkibni himoyalash")
            toggle: true; chevron: false; last: true
            on: page.shielded
            onClicked: {
                const want = !page.shielded
                page.shielded = want
                store.send({ "@type": "toggleChatHasProtectedContent", chat_id: page.chatId, has_protected_content: want }, (r) => {
                    if (r["@type"] === "error") {
                        page.shielded = !want
                        page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                    }
                })
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
