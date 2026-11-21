// Settings, laid out as Telegram-iOS's (IMG_0298, the owner's #26428–29): QR · 🔍 · «Tahrirlash» floating on top, who is
// signed in, then rounded groups of rows with Telegram's own coloured icons, in iOS's order: My Profile | Saved Messages,
// Recent Calls, Devices, Chat Folders | Notifications … Language | Premium, My Stars, Business, Send a Gift | Ask a Question,
// FAQ, Features. QR: our t.me link as a code (QrSheet). 🔍: the settings searched by their names (`index`). «Chiqish» at the
// bottom asks first, then logOut: TDLib closes, the app starts again at the sign-in.
import QtQuick

Page {
    id: page
    color: Theme.grouped
    property string photo: ""
    property string tdVersion: ""
    property int devices: 0
    property bool searching: false
    property string query: ""
    onVisibleChanged: if (visible) {
        if (!photo && store.me)
            store.userPhoto(store.me, (path) => page.photo = path)
        if (!tdVersion)
            store.send({ "@type": "getOption", name: "version" }, (r) => {
                if (r.value)
                    page.tdVersion = r.value
            })
        store.send({ "@type": "getActiveSessions" }, (r) => {
            if (r.sessions)
                page.devices = r.sessions.length
        })
    }
    readonly property var me: store.me
    readonly property string username: me && me.usernames && me.usernames.active_usernames.length ? me.usernames.active_usernames[0] : ""

    function open(component) {
        nav.push(component, {})
    }
    function openQml(file, props) {
        nav.push(Qt.createComponent(file), props || {})
    }
    function saved() {
        if (page.me)
            store.chatWith(page.me.id, (id) => page.nav.push(chatPage, { chatId: id }))
    }
    function sendGift() {        // iOS: a person picked, then the gifts for them
        const p = nav.push(Qt.createComponent("FolderChatsPage.qml"), {
            heading: Tr.t("Hadya yuborish"), chosen: [],
            pool: (c) => c.type["@type"] === "chatTypePrivate" && !store.isSaved(c) && !!store.users[c.type.user_id]
                         && store.users[c.type.user_id].type["@type"] === "userTypeRegular" })
        if (p)
            p.done.connect((flags, ids) => {
                if (!ids.length)
                    return
                gift.chatId = ids[0]
                Qt.callLater(() => gift.show())
            })
    }
    function business() {
        alert.show("Telegram Business", Tr.t("Biznes uchun imkoniyatlar (ish vaqti, joylashuv, tezkor javoblar, chat-botlar) Telegram Business obunasi bilan keladi. Uni Nullgram'da sotib olib bo'lmaydi — Telegram'ning boshqa ilovasidan oling."),
                   [{ t: Tr.t("Yopish") }])
    }
    function ask() {             // iOS's alert before the support chat
        alert.show(Tr.t("Savol berish"), Tr.t("Telegram yordami ko'ngillilar tomonidan amalga oshiriladi. Imkon qadar tez javob berishga harakat qilamiz, lekin bu biroz vaqt olishi mumkin.\n\nTelegram FAQ'ni ko'rib chiqing: unda ko'p savollarga javob va muammolarni hal qilish bo'yicha muhim maslahatlar bor."),
                   [{ t: Tr.t("FAQ"), run: page.faq },
                    { t: Tr.t("Ko'ngillidan so'rash"), run: () => store.send({ "@type": "getSupportUser" }, (u) => {
                        if (u["@type"] === "user")
                            store.chatWith(u.id, (id) => page.nav.push(chatPage, { chatId: id }))
                        else
                            page.nav.say(Tr.f("Bo'lmadi: %1", u.message || ""))
                    }) }], true)
    }
    function faq() { Qt.openUrlExternally(Tr.en ? "https://telegram.org/faq" : "https://telegram.org/faq") }
    function features() {        // iOS: the @TelegramTips channel
        store.send({ "@type": "searchPublicChat", username: "TelegramTips" }, (c) => {
            if (c["@type"] === "chat")
                page.nav.push(chatPage, { chatId: c.id })
            else
                page.nav.say(Tr.f("Bo'lmadi: %1", c.message || ""))
        })
    }
    function edit() { openQml("ProfileEditPage.qml") }

    // what 🔍 finds: [words, icon, what it opens]; the rows and the pages under them people look for most
    readonly property var index: [
        [Tr.t("Mening profilim"), "profile", () => page.open(profilePage)],
        [Tr.t("Tahrirlash"), "profile", page.edit],
        [Tr.t("Foydalanuvchi nomi"), "profile", () => page.openQml("UsernamePage.qml")],
        [Tr.t("Saqlangan xabarlar"), "saved", page.saved],
        [Tr.t("So'nggi qo'ng'iroqlar"), "calls", () => page.openQml("CallsPage.qml")],
        [Tr.t("Qurilmalar"), "devices", () => page.open(devicesPage)],
        [Tr.t("Chat papkalari"), "folders", () => page.open(foldersPage)],
        [Tr.t("Bildirishnomalar va ovozlar"), "notifications", () => page.open(notificationsPage)],
        [Tr.t("Maxfiylik va xavfsizlik"), "privacy", () => page.openQml("PrivacyPage.qml")],
        [Tr.t("Bloklangan foydalanuvchilar"), "block", () => page.openQml("BlockedPage.qml")],
        [Tr.t("Kod-parol"), "passcode", () => page.openQml("PasscodePage.qml")],
        [Tr.t("Ikki bosqichli tasdiqlash"), "privacy", () => page.openQml("TwoStepPage.qml")],
        [Tr.t("Ma'lumotlar va xotira"), "data", () => page.open(storagePage)],
        [Tr.t("Xotira sarfi"), "storage", () => page.openQml("StorageUsagePage.qml")],
        [Tr.t("Trafik"), "traffic", () => page.openQml("DataUsagePage.qml")],
        [Tr.t("Proksi"), "proxy", () => page.openQml("ProxyPage.qml")],
        [Tr.t("Ko'rinish"), "appearance", () => page.open(appearancePage)],
        [Tr.t("Chat fon rasmi"), "appearance", () => page.openQml("WallpaperPage.qml")],
        [Tr.t("Chat mavzulari"), "appearance", () => page.openQml("ChatThemesPage.qml")],
        [Tr.t("Matn o'lchami"), "appearance", () => page.openQml("TextSizePage.qml")],
        [Tr.t("Sizning rangingiz"), "color", () => page.openQml("YourColorPage.qml")],
        [Tr.t("Stikerlar va emoji"), "stickers", () => page.open(stickersPage)],
        [Tr.t("Quvvat tejash"), "powersaving", () => page.open(powerPage)],
        [Tr.t("Til"), "language", () => page.open(languagePage)],
        ["Telegram Premium", "premium", () => page.openQml("PremiumPage.qml")],
        [Tr.t("Mening yulduzlarim"), "stars", () => page.openQml("StarsPage.qml")],
        ["Telegram Business", "business", page.business],
        [Tr.t("Hadya yuborish"), "gift", page.sendGift],
        [Tr.t("Savol berish"), "support", page.ask],
        ["Telegram FAQ", "faq", page.faq],
        [Tr.t("Telegram imkoniyatlari"), "tips", page.features],
        [Tr.t("Chiqish"), "", () => leave.visible = true]
    ]
    readonly property var found: {
        const q = query.trim().toLowerCase()
        return q ? index.filter((e) => e[0].toLowerCase().indexOf(q) >= 0) : []
    }

    Flickable {
        id: list
        anchors.fill: parent
        visible: !page.searching
        contentHeight: column.height + 120 + safe.bottom
        Column {
            id: column
            width: parent.width
            spacing: 22
            Item {           // who is signed in (under the floating buttons)
                width: parent.width; height: 236
                Avatar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 58
                    width: 96; height: 96
                    source: page.photo
                    letters: page.me ? store.letters(page.me.first_name + " " + page.me.last_name) : ""
                    tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 164
                    text: page.me ? (page.me.first_name + " " + page.me.last_name).trim() : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 198
                    text: !page.me ? "" : ("+" + page.me.phone_number) +
                          (page.me.usernames && page.me.usernames.active_usernames.length
                           ? "  ·  @" + page.me.usernames.active_usernames[0] : "")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
            }

            SettingsGroup {
                SettingsRow { art: "profile"; text: Tr.t("Mening profilim"); last: true; onClicked: page.open(profilePage) }
            }
            SettingsGroup {
                SettingsRow { art: "saved"; text: Tr.t("Saqlangan xabarlar"); onClicked: page.saved() }
                SettingsRow { art: "calls"; text: Tr.t("So'nggi qo'ng'iroqlar"); onClicked: page.openQml("CallsPage.qml") }
                SettingsRow { art: "devices"; text: Tr.t("Qurilmalar"); value: page.devices ? page.devices : ""; onClicked: page.open(devicesPage) }
                SettingsRow { art: "folders"; text: Tr.t("Chat papkalari"); value: store.folders.length ? store.folders.length : ""; last: true; onClicked: page.open(foldersPage) }
            }
            SettingsGroup {
                SettingsRow { art: "notifications"; text: Tr.t("Bildirishnomalar va ovozlar"); onClicked: page.open(notificationsPage) }
                SettingsRow { art: "privacy"; text: Tr.t("Maxfiylik va xavfsizlik"); onClicked: page.openQml("PrivacyPage.qml") }
                SettingsRow { art: "data"; text: Tr.t("Ma'lumotlar va xotira"); onClicked: page.open(storagePage) }
                SettingsRow { art: "appearance"; text: Tr.t("Ko'rinish"); value: Theme.dark ? Tr.t("Tungi") : Tr.t("Kunduzgi"); onClicked: page.open(appearancePage) }
                SettingsRow { art: "powersaving"; text: Tr.t("Quvvat tejash"); value: Prefs.saving ? Tr.t("Yoqilgan") : Tr.t("O'chiq"); onClicked: page.open(powerPage) }
                SettingsRow { art: "language"; text: Tr.t("Til"); value: Tr.en ? "English" : Tr.t("O'zbekcha"); last: true; onClicked: page.open(languagePage) }
            }
            SettingsGroup {
                SettingsRow { art: "premium"; text: "Telegram Premium"; onClicked: page.openQml("PremiumPage.qml") }
                SettingsRow {
                    art: "stars"; text: Tr.t("Mening yulduzlarim")
                    value: store.stars > 0 ? Math.floor(store.stars).toLocaleString(Qt.locale(), "f", 0) : ""
                    onClicked: page.openQml("StarsPage.qml")
                }
                SettingsRow { art: "business"; text: "Telegram Business"; onClicked: page.business() }
                SettingsRow { art: "gift"; text: Tr.t("Hadya yuborish"); last: true; onClicked: page.sendGift() }
            }
            SettingsGroup {
                SettingsRow { art: "support"; text: Tr.t("Savol berish"); onClicked: page.ask() }
                SettingsRow { art: "faq"; text: "Telegram FAQ"; onClicked: page.faq() }
                SettingsRow { art: "tips"; text: Tr.t("Telegram imkoniyatlari"); last: true; onClicked: page.features() }
            }
            SettingsGroup {
                note: Tr.t("Nullgram — OmonullOS uchun Telegram (Qt Quick + TDLib).")
                SettingsRow {
                    text: Tr.t("Ilova haqida"); chevron: false; last: true
                    value: "0.9" + (page.tdVersion ? " · TDLib " + page.tdVersion : "")
                }
            }
            SettingsGroup {
                SettingsRow { text: Tr.t("Chiqish"); danger: true; chevron: false; last: true; onClicked: leave.visible = true }
            }
        }
    }

    Rectangle {          // what scrolls under the buttons fades out (iOS 26's edge)
        width: parent.width; height: 74
        opacity: page.searching ? 1 : Math.min(1, Math.max(0, list.contentY - 20) / 40)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.grouped }
            GradientStop { position: 0.75; color: Theme.grouped }
            GradientStop { position: 1; color: Qt.rgba(Theme.grouped.r, Theme.grouped.g, Theme.grouped.b, 0) }
        }
    }
    // QR · 🔍 · «Tahrirlash», floating over the list (iOS 26's glass); 🔍 turns them into the search field
    Item {
        id: top
        x: 16; y: 10
        width: parent.width - 32; height: 44
        Glass {
            visible: !page.searching
            width: 44; height: 44
            opacity: qrHit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; name: "qr"; color: Theme.text }
            MouseArea { id: qrHit; anchors.fill: parent; onClicked: qr.show() }
        }
        Glass {
            visible: !page.searching
            x: editPill.x - width - 10
            width: 44; height: 44
            opacity: findHit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; name: "search"; color: Theme.text }
            MouseArea {
                id: findHit
                anchors.fill: parent
                onClicked: { field.text = ""; page.query = ""; page.searching = true; field.forceActiveFocus() }
            }
        }
        Glass {
            id: editPill
            visible: !page.searching
            anchors.right: parent.right
            width: editWord.implicitWidth + 32; height: 44
            opacity: editHit.pressed ? 0.7 : 1
            Text {
                id: editWord
                anchors.centerIn: parent
                text: Tr.t("Tahrirlash")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            MouseArea { id: editHit; anchors.fill: parent; onClicked: page.edit() }
        }
        Glass {             // the search field
            visible: page.searching
            width: parent.width - cancel.width - 12; height: 44
            Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "search"; color: Theme.grey }
            TextInput {
                id: field
                x: 40; width: parent.width - 52
                anchors.verticalCenter: parent.verticalCenter
                onTextEdited: page.query = text
                color: Theme.text
                clip: true
                font.family: Theme.font; font.pixelSize: 17
                Text {
                    visible: !parent.text
                    text: Tr.t("Qidiruv")
                    color: Theme.grey
                    font: parent.font
                }
            }
        }
        Text {
            id: cancel
            visible: page.searching
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: Tr.t("Bekor qilish")
            color: Theme.accent
            opacity: cancelHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 17
            MouseArea {
                id: cancelHit
                anchors.fill: parent; anchors.margins: -8
                onClicked: { page.searching = false; page.query = ""; field.focus = false; Qt.inputMethod.hide() }
            }
        }
    }
    Flickable {          // what the search found
        visible: page.searching
        anchors.fill: parent
        anchors.topMargin: 66
        contentHeight: results.height + 120 + Math.max(osk.h, safe.bottom)
        Column {
            id: results
            width: parent.width
            spacing: 22
            SettingsGroup {
                visible: page.found.length > 0
                Repeater {
                    model: page.found
                    SettingsRow {
                        required property var modelData
                        required property int index
                        art: modelData[1]
                        text: modelData[0]
                        danger: modelData[1] === ""
                        last: index === page.found.length - 1
                        onClicked: {
                            const go = modelData[2]
                            page.searching = false; page.query = ""; field.focus = false; Qt.inputMethod.hide()
                            go()
                        }
                    }
                }
            }
            Text {
                visible: page.query.trim() !== "" && !page.found.length
                x: 32; width: parent.width - 64
                topPadding: 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.t("Hech narsa topilmadi")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
        }
    }

    QrSheet {
        id: qr
        parent: page.nav || page
        z: 100
        store: page.store
        photo: page.photo
        username: page.username
        onWantName: page.openQml("UsernamePage.qml")
        onCopied: page.nav.say(Tr.t("Havola nusxalandi"))
    }
    Item {               // (the gift sheet over the whole window, as ChatInfoPage's overlay)
        parent: page.nav || page
        anchors.fill: parent
        z: 99
        GiftSheet {
            id: gift
            store: page.store
            onSay: (text) => page.nav.say(text)
        }
    }
    Alert { id: alert; parent: page.nav || page; anchors.fill: parent; z: 100 }

    Item {               // «Chiqish»: asked first, as Telegram-iOS's alert
        id: leave
        parent: page.nav || page         // (over the whole window: the tab bar too)
        anchors.fill: parent
        z: 100
        visible: false
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4) }
        MouseArea { anchors.fill: parent; onClicked: leave.visible = false }
        Rectangle {
            anchors.centerIn: parent
            width: 280; height: leaveText.height + 32 + 2 * 46
            radius: 14
            color: Theme.menu
            MouseArea { anchors.fill: parent }
            Text {
                id: leaveText
                x: 16; y: 18; width: parent.width - 32
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.StyledText
                text: "<b>" + Tr.t("Hisobdan chiqasizmi?") + "</b><br>" + Tr.t("Kirish uchun raqamingiz yoki QR kod kerak bo'ladi.")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
            Repeater {
                model: [{ t: Tr.t("Chiqish"), go: true }, { t: Tr.t("Bekor qilish"), go: false }]
                Rectangle {
                    required property var modelData
                    required property int index
                    y: leaveText.y + leaveText.height + 14 + index * 46
                    width: parent.width; height: 46
                    color: leaveHit.pressed ? Theme.highlight : "transparent"
                    radius: index === 1 ? 14 : 0
                    Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        color: parent.modelData.go ? Theme.danger : Theme.accent
                        font.family: Theme.font; font.pixelSize: 17
                        font.weight: parent.modelData.go ? Font.Normal : Font.DemiBold
                    }
                    MouseArea {
                        id: leaveHit
                        anchors.fill: parent
                        onClicked: {
                            leave.visible = false
                            if (parent.modelData.go)
                                store.logOut()
                        }
                    }
                }
            }
        }
    }

    Component { id: chatPage; ChatPage {} }
    Component { id: profilePage; ProfilePage {} }
    Component { id: devicesPage; DevicesPage {} }
    Component { id: foldersPage; FoldersPage {} }
    Component { id: notificationsPage; NotificationsPage {} }
    Component { id: storagePage; StoragePage {} }
    Component { id: appearancePage; AppearancePage {} }
    Component { id: stickersPage; StickersPage {} }
    Component { id: languagePage; LanguagePage {} }
    Component { id: powerPage; PowerPage {} }
}
