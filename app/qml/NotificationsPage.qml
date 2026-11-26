// Notifications and sounds, as Telegram-iOS's NotificationsAndSoundsController: «XABAR BILDIRISHNOMALARI» — private chats, groups,
// channels (NotificationsCategoryItemListItem: its icon, the name, «N ta istisno» under it, Yoqilgan / O'chiq), stories (Top 5),
// reactions (Xabarlar, Hikoyalar: updateReactionNotificationSettings) — each its page (NotifyScopePage); «ILOVA ICHIDAGI BILDIRISHNOMALAR»: the banners' sound and the
// banners themselves while the app is in front; the names in banners; «NISHON HISOBLAGICHI»: the Start tile's count (channels in
// it, messages or chats); «Yangi kontaktlar» (disable_contact_registered_notifications); «Barcha bildirishnomalarni tiklash»
// (asked: resetAllNotificationSettings); with 2+ accounts «Barcha hisoblardan» (the others kept on, notifying). The scopes' settings from TDLib (getScopeNotificationSettings, kept by Store.scopes).
// (iOS's «In-App Vibrate»: no vibrator the app can reach on the phone yet — not here.)
import QtQuick

SubPage {
    id: page
    title: Tr.t("Bildirishnomalar va ovozlar")
    readonly property var kinds: [["notificationSettingsScopePrivateChats", "private", Tr.t("Shaxsiy chatlar")],
                                  ["notificationSettingsScopeGroupChats", "groups", Tr.t("Guruhlar")],
                                  ["notificationSettingsScopeChannelChats", "channels", Tr.t("Kanallar")]]
    property var exceptions: ({})       // scope -> its exceptions' count
    readonly property var reactions: store.reactionSettings
    property bool joined: true          // «Yangi kontaktlar»

    function load() {
        for (const k of kinds) {
            store.send({ "@type": "getScopeNotificationSettings", scope: { "@type": k[0] } }, (r) => {
                if (!page || r["@type"] !== "scopeNotificationSettings")
                    return
                delete r["@extra"]
                const s = Object.assign({}, store.scopes)
                s[k[0]] = r
                store.scopes = s
            })
            store.send({ "@type": "getChatNotificationSettingsExceptions", scope: { "@type": k[0] }, compare_sound: false }, (r) => {
                if (!page || !r.chat_ids)
                    return
                const e = Object.assign({}, page.exceptions)
                e[k[0]] = r.chat_ids.length
                page.exceptions = e
            })
        }
        store.send({ "@type": "getOption", name: "disable_contact_registered_notifications" }, (r) => {
            if (page && r["@type"] === "optionValueBoolean")
                page.joined = !r.value
        })
    }
    Component.onCompleted: load()
    onVisibleChanged: if (visible) load()          // (back from a scope's page)

    function scope(k) {
        return store.scopes[k] || null
    }
    function on(k) {
        const s = scope(k)
        return !!s && s.mute_for === 0
    }
    // Notifications_CategoryExceptions
    function excepted(k) {
        const n = exceptions[k] || 0
        return n ? Tr.n("%1 ta istisno", n) : ""
    }
    // Stories: on, off, or the five chats written to most (iOS's Top 5: TDLib's use_default_mute_stories)
    readonly property string stories: {
        const s = scope("notificationSettingsScopePrivateChats")
        return !s ? "" : s.use_default_mute_stories ? Tr.t("Top 5") : s.mute_stories ? Tr.t("O'chiq") : Tr.t("Yoqilgan")
    }
    readonly property string reacted: {
        const r = reactions
        if (!r)
            return ""
        const w = []
        if (r.message_reaction_source["@type"] !== "reactionNotificationSourceNone")
            w.push(Tr.t("Xabarlar"))
        if (r.story_reaction_source["@type"] !== "reactionNotificationSourceNone")
            w.push(Tr.t("Hikoyalar"))
        return w.join(", ")
    }
    property Component maker: null
    function open(kind) {
        if (!maker)
            maker = Qt.createComponent("NotifyScopePage.qml")
        nav.push(maker, { kind: kind })
    }
    function setJoined(v) {
        joined = v
        store.send({ "@type": "setOption", name: "disable_contact_registered_notifications",
                     value: { "@type": "optionValueBoolean", value: !v } }, store.check)
    }
    function askReset() {
        alert.show("", Tr.t("Barcha bildirishnoma sozlamalarini odatiy holatga qaytarasizmi?"),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Tiklash"), red: true, run: () => page.reset() }])
    }
    function reset() {
        store.send({ "@type": "resetAllNotificationSettings" }, (r) => {
            if (!page)
                return
            store.check(r)
            page.exceptions = ({})
            page.load()
        })
    }
    function dismiss() {
        if (!alert.open)
            return false
        alert.open = false
        return true
    }

    SettingsGroup {
        title: Tr.t("Xabar bildirishnomalari")
        Repeater {
            model: page.kinds
            SettingsRow {
                required property var modelData
                art: modelData[1]; text: modelData[2]
                sub: page.excepted(modelData[0])
                value: page.scope(modelData[0]) ? (page.on(modelData[0]) ? Tr.t("Yoqilgan") : Tr.t("O'chiq")) : ""
                onClicked: page.open(modelData[1])
            }
        }
        SettingsRow { art: "stories"; text: Tr.t("Hikoyalar"); value: page.stories; onClicked: page.open("stories") }
        SettingsRow {
            art: "reactions"; text: Tr.t("Reaksiyalar"); last: true
            sub: page.reacted
            value: page.reactions ? (page.reacted ? Tr.t("Yoqilgan") : Tr.t("O'chiq")) : ""
            onClicked: page.open("reactions")
        }
    }

    // (0.9.7, 2+ accounts: Telegram-iOS's «SHOW NOTIFICATIONS FROM · All Accounts»; off: the others not kept on at all)
    SettingsGroup {
        visible: accounts.count > 1
        title: Tr.t("Bildirishnomalar manbasi")
        note: Tr.t("O'chirilsa, bildirishnomalar faqat hozir ochiq hisobdan keladi, boshqa hisoblar fonda ishlamaydi.")
        SettingsRow {
            text: Tr.t("Barcha hisoblardan"); toggle: true; on: Prefs.allAccounts; last: true
            onClicked: {
                Prefs.allAccounts = !Prefs.allAccounts
                accounts.watch(Prefs.allAccounts, Tr.lang)
            }
        }
    }

    SettingsGroup {
        title: Tr.t("Ilova ichidagi bildirishnomalar")
        SettingsRow {
            text: Tr.t("Ilova ichidagi ovozlar"); toggle: true; on: Prefs.inAppSounds
            onClicked: Prefs.inAppSounds = !Prefs.inAppSounds
        }
        SettingsRow {
            text: Tr.t("Ilova ichida ko'rsatish"); toggle: true; on: Prefs.inAppPreview; last: true
            onClicked: Prefs.inAppPreview = !Prefs.inAppPreview
        }
    }

    SettingsGroup {
        note: Tr.t("Bildirishnomalarda, qulf ekranida ham, chat va yuboruvchi nomini ko'rsatish. O'chirilsa, faqat «Nullgram» yoziladi.")
        SettingsRow {
            text: Tr.t("Bildirishnomalarda ismlar"); toggle: true; on: Prefs.lockNames; last: true
            onClicked: Prefs.lockNames = !Prefs.lockNames
        }
    }

    SettingsGroup {
        title: Tr.t("Nishon hisoblagichi")
        note: Prefs.badgeMessages ? Tr.t("Start ekrandagi plitkada o'qilmagan chatlar o'rniga o'qilmagan xabarlar soni ko'rsatiladi. O'chirilsa — chatlar soni.")
                                  : Tr.t("Yoqilsa, Start ekrandagi plitkada o'qilmagan chatlar o'rniga o'qilmagan xabarlar soni ko'rsatiladi.")
        SettingsRow {
            text: Tr.t("Kanallarni qo'shish"); toggle: true; on: Prefs.badgeChannels
            onClicked: { Prefs.badgeChannels = !Prefs.badgeChannels; store.retile() }
        }
        SettingsRow {
            text: Tr.t("Xabarlarni sanash"); toggle: true; on: Prefs.badgeMessages; last: true
            onClicked: { Prefs.badgeMessages = !Prefs.badgeMessages; store.retile() }
        }
    }

    SettingsGroup {
        note: Tr.t("Kontaktlaringizdan biri Telegram'ga qo'shilganda bildirishnoma olish.")
        SettingsRow {
            text: Tr.t("Yangi kontaktlar"); toggle: true; on: page.joined; last: true
            onClicked: page.setJoined(!page.joined)
        }
    }

    SettingsGroup {
        note: Tr.t("Barcha kontaktlar, guruhlar va kanallar uchun maxsus bildirishnoma sozlamalarini bekor qilish.")
        SettingsRow {
            text: Tr.t("Barcha bildirishnomalarni tiklash"); danger: true; chevron: false; last: true
            onClicked: page.askReset()
        }
    }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
