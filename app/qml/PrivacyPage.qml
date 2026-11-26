// «Maxfiylik va xavfsizlik» (Telegram-iOS's PrivacyAndSecurityController, the owner's #26469–73): «Bloklanganlar» (how
// many), «Kod-parol» (this app's lock: PasscodePage), «Ikki bosqichli tasdiqlash» (TwoStepPage), «Passkey'lar»,
// «Xabarlarni avto-o'chirish» (setDefaultMessageAutoDeleteTime), «Kirish e-pochtasi» (only its pattern); «MAXFIYLIK»: who
// sees or may do each thing (PrivacyRulePage, the value as iOS's «Hamma (−2)»), «Xabarlar» (getNewChatPrivacySettings);
// «Agar faol bo'lmasam» (setAccountTtl); «Ma'lumotlar sozlamalari» (this same page with `data`: frequent contacts,
// synced contacts and drafts cleared). iOS's «Open Links in» is not here (links go to the phone's browser).
import QtQuick
import "Privacy.js" as P

SubPage {
    id: page
    property bool data: false           // (the «Ma'lumotlar sozlamalari» page)
    property int blocked: -1
    property var rules: ({})            // setting -> Privacy.read(...)
    property var pw: null               // passwordState
    property int passkeys: -1
    property int autoDelete: -1
    property int ttl: -1
    property int unknownOk: -1          // «Xabarlar»: 1 everybody, 0 contacts and Premium
    property int topChats: -1           // «Tez-tez yozishadiganlar»: 1 on
    title: data ? Tr.t("Ma'lumotlar sozlamalari") : Tr.t("Maxfiylik va xavfsizlik")

    readonly property var settings: [
        ["userPrivacySettingShowPhoneNumber", "Telefon raqami"],
        ["userPrivacySettingShowStatus", "So'nggi faollik va onlayn"],
        ["userPrivacySettingShowProfilePhoto", "Profil rasmlari"],
        ["userPrivacySettingShowBio", "Bio"],
        ["userPrivacySettingAutosaveGifts", "Sovg'alar"],
        ["userPrivacySettingShowBirthdate", "Tug'ilgan kun"],
        ["userPrivacySettingShowProfileAudio", "Saqlangan musiqa"],
        ["userPrivacySettingShowLinkInForwardedMessages", "Uzatilgan xabarlar"],
        ["userPrivacySettingAllowCalls", "Qo'ng'iroqlar"],
        ["userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages", "Ovozli xabarlar"],
        ["messages", "Xabarlar"],
        ["userPrivacySettingAllowChatInvites", "Taklif qilish"]
    ]

    function load() {
        if (data) {
            store.send({ "@type": "getOption", name: "disable_top_chats" },
                       (r) => { page.topChats = r && r.value === true ? 0 : 1 })
            return
        }
        store.send({ "@type": "getBlockedMessageSenders", block_list: { "@type": "blockListMain" }, offset: 0, limit: 1 },
                   (r) => { page.blocked = r.total_count || 0 })
        store.send({ "@type": "getPasswordState" }, (r) => { if (r["@type"] === "passwordState") page.pw = r })
        store.send({ "@type": "getLoginPasskeys" }, (r) => { page.passkeys = r.passkeys ? r.passkeys.length : 0 })
        store.send({ "@type": "getDefaultMessageAutoDeleteTime" }, (r) => { page.autoDelete = r.time || 0 })
        store.send({ "@type": "getAccountTtl" }, (r) => { page.ttl = r.days || 0 })
        store.send({ "@type": "getNewChatPrivacySettings" },
                   (r) => { page.unknownOk = r["@type"] === "newChatPrivacySettings" ? (r.allow_new_chats_from_unknown_users ? 1 : 0) : -1 })
        for (const s of settings)
            if (s[0] !== "messages")
                readRules(s[0])
    }
    function readRules(key) {
        store.send({ "@type": "getUserPrivacySettingRules", setting: { "@type": key } }, (r) => {
            if (r["@type"] !== "userPrivacySettingRules")
                return
            const o = Object.assign({}, page.rules)
            o[key] = P.read(r)
            page.rules = o
        })
    }
    Component.onCompleted: load()
    onVisibleChanged: if (visible && !data) {           // (back from a page that may have changed something)
        store.send({ "@type": "getBlockedMessageSenders", block_list: { "@type": "blockListMain" }, offset: 0, limit: 1 },
                   (r) => { page.blocked = r.total_count || 0 })
        store.send({ "@type": "getPasswordState" }, (r) => { if (r["@type"] === "passwordState") page.pw = r })
    }

    function baseName(b) {
        return b === 0 ? Tr.t("Hamma") : b === 1 ? Tr.t("Kontaktlarim") : Tr.t("Hech kim")
    }
    function valueOf(key) {
        if (key === "messages")
            return unknownOk < 0 ? "" : unknownOk ? Tr.t("Hamma") : Tr.t("Kontaktlar va Premium")
        const r = rules[key]
        if (!r)
            return ""
        const n = P.counts(r)
        const w = []
        if (n.minus)
            w.push("−" + n.minus)
        if (n.plus)
            w.push("+" + n.plus)
        return baseName(r.base) + (w.length ? " (" + w.join(", ") + ")" : "")
    }
    function months(days) {
        return days >= 365 && days % 365 === 0 ? Tr.f("%1 oy", days / 365 * 12)
             : days === 548 ? Tr.f("%1 oy", 18) : Tr.f("%1 oy", Math.round(days / 30))
    }
    function timeName(t) {
        return t <= 0 ? Tr.t("O'chiq") : t === 86400 ? Tr.t("1 kun") : t === 604800 ? Tr.t("1 hafta")
             : t === 2678400 ? Tr.t("1 oy") : t % 86400 === 0 ? Tr.f("%1 kun", t / 86400) : Tr.f("%1 soat", Math.round(t / 3600))
    }

    function openRule(key, name) {
        if (key === "messages")
            return openMessages()
        if (!rules[key])
            return
        const p = nav.push(Qt.createComponent("PrivacyRulePage.qml"), { key: key, heading: Tr.t(name), r: rules[key] })
        if (p)
            p.changed.connect((r) => {
                const o = Object.assign({}, page.rules)
                o[key] = r
                page.rules = o
            })
    }
    function openMessages() {
        if (unknownOk < 0)
            return
        const p = nav.push(Qt.createComponent("ChoicePage.qml"), {
            heading: Tr.t("Xabarlar"), groupTitle: Tr.t("Menga kim yoza oladi?"), value: unknownOk,
            choices: [{ t: Tr.t("Hamma"), v: 1 }, { t: Tr.t("Kontaktlar va Premium"), v: 0 }],
            note: Tr.t("Kontaktingiz bo'lmagan foydalanuvchilar sizga yozishi uchun Telegram Premium kerak bo'lishini tanlashingiz mumkin.") })
        if (p)
            p.chosen.connect((v) => {
                store.send({ "@type": "setNewChatPrivacySettings", settings: { "@type": "newChatPrivacySettings",
                             allow_new_chats_from_unknown_users: v === 1, incoming_paid_message_star_count: 0 } }, (r) => {
                    if (r["@type"] === "error")
                        return console.warn("nullgram: new chat privacy", r.message)
                    page.unknownOk = v
                })
            })
    }
    function openAutoDelete() {
        if (autoDelete < 0)
            return
        const p = nav.push(Qt.createComponent("ChoicePage.qml"), {
            heading: Tr.t("Xabarlarni avto-o'chirish"), groupTitle: Tr.t("O'z-o'zini o'chirish taymeri"), value: autoDelete,
            choices: [0, 86400, 604800, 2678400].map((t) => ({ t: page.timeName(t), v: t })),
            note: Tr.t("Yoqilsa, siz boshlagan barcha yangi chatlarda xabarlar shu vaqtdan keyin hamma uchun o'chiriladi. Mavjud chatlarga ta'sir qilmaydi.") })
        if (p)
            p.chosen.connect((v) => {
                store.send({ "@type": "setDefaultMessageAutoDeleteTime",
                             message_auto_delete_time: { "@type": "messageAutoDeleteTime", time: v } }, (r) => {
                    if (r["@type"] === "error")
                        return console.warn("nullgram: auto-delete", r.message)
                    page.autoDelete = v
                })
            })
    }
    function openTtl() {
        if (ttl <= 0)
            return
        const days = [30, 90, 180, 365, 548, 730]
        const p = nav.push(Qt.createComponent("ChoicePage.qml"), {
            heading: Tr.t("Hisobni o'chirish"), groupTitle: Tr.t("Agar faol bo'lmasam"), value: ttl,
            choices: days.map((d) => ({ t: page.months(d), v: d })),
            note: Tr.t("Shu muddat ichida bir marta ham kirmasangiz, hisobingiz barcha xabarlar va kontaktlar bilan birga o'chiriladi.") })
        if (p)
            p.chosen.connect((v) => {
                store.send({ "@type": "setAccountTtl", ttl: { "@type": "accountTtl", days: v } }, (r) => {
                    if (r["@type"] === "error")
                        return console.warn("nullgram: account ttl", r.message)
                    page.ttl = v
                })
            })
    }
    function setTop(on) {
        store.send({ "@type": "setOption", name: "disable_top_chats", value: { "@type": "optionValueBoolean", value: !on } },
                   (r) => { if (r["@type"] !== "error") page.topChats = on ? 1 : 0 })
    }
    function askClear(what) {
        if (what === "contacts")
            alert.show("", Tr.t("Telefoningizdan sinxronlangan barcha kontaktlar Telegram serverlaridan o'chirilsinmi?"),
                       [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () =>
                           store.send({ "@type": "clearImportedContacts" }, () => page.nav.say(Tr.t("Sinxronlangan kontaktlar o'chirildi."))) }])
        else
            alert.show("", Tr.t("Barcha chatlardagi qoralamalar o'chirilsinmi?"),
                       [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () =>
                           store.send({ "@type": "clearAllDraftMessages", exclude_secret_chats: false }, () => page.nav.say(Tr.t("Qoralamalar o'chirildi."))) }])
    }

    // ---- the main page ----
    SettingsGroup {
        visible: !page.data
        note: Tr.t("Yangi chatlarda xabarlar ma'lum vaqtdan keyin hamma uchun avtomatik o'chirilishi mumkin.")
        SettingsRow {
            art: "block"; text: Tr.t("Bloklanganlar"); value: page.blocked > 0 ? page.blocked : page.blocked === 0 ? Tr.t("Yo'q") : ""
            onClicked: page.nav.push(Qt.createComponent("BlockedPage.qml"), {})
        }
        SettingsRow {
            art: "passcode"; text: Tr.t("Kod-parol"); value: Prefs.passcode ? Tr.t("Yoqilgan") : Tr.t("O'chiq")
            onClicked: page.nav.push(Qt.createComponent("PasscodePage.qml"), {})
        }
        SettingsRow {
            art: "privacy"; text: Tr.t("Ikki bosqichli parol")
            value: page.pw ? (page.pw.has_password ? Tr.t("Yoqilgan") : Tr.t("O'chiq")) : ""
            onClicked: if (page.pw) page.nav.push(Qt.createComponent("TwoStepPage.qml"), { pw: page.pw })
        }
        SettingsRow {
            art: "passkeys"; text: Tr.t("Passkey'lar"); value: page.passkeys > 0 ? page.passkeys : page.passkeys === 0 ? Tr.t("O'chiq") : ""
            onClicked: {
                const p = page.nav.push(Qt.createComponent("PasskeysPage.qml"), {})
                if (p)
                    p.counted.connect((n) => page.passkeys = n)
            }
        }
        SettingsRow {
            art: "timer"; text: Tr.t("Avto-o'chirish"); last: true
            value: page.autoDelete >= 0 ? page.timeName(page.autoDelete) : ""
            onClicked: page.openAutoDelete()
        }
    }
    SettingsGroup {
        visible: !page.data && !!page.pw && !!page.pw.login_email_address_pattern
        note: Tr.t("Telegram'ga kirish kodi SMS o'rniga shu e-pochtaga yuboriladi.")
        SettingsRow {
            art: "email"; text: Tr.t("E-pochta"); chevron: false; last: true
            value: page.pw ? page.pw.login_email_address_pattern : ""
        }
    }
    SettingsGroup {
        visible: !page.data
        title: Tr.t("Maxfiylik")
        note: Tr.t("Sizni guruh va kanallarga kim qo'sha olishini cheklashingiz mumkin.")
        Repeater {
            model: page.settings
            SettingsRow {
                required property var modelData
                required property int index
                text: Tr.t(modelData[1])
                value: page.valueOf(modelData[0])
                last: index === page.settings.length - 1
                onClicked: page.openRule(modelData[0], modelData[1])
            }
        }
    }
    SettingsGroup {
        visible: !page.data
        title: Tr.t("Hisobimni avtomatik o'chirish")
        note: Tr.t("Shu muddat ichida bir marta ham kirmasangiz, hisobingiz barcha xabarlar va kontaktlar bilan birga o'chiriladi.")
        SettingsRow { text: Tr.t("Agar faol bo'lmasam"); value: page.ttl > 0 ? page.months(page.ttl) : ""; last: true; onClicked: page.openTtl() }
    }
    SettingsGroup {
        visible: !page.data
        note: Tr.t("Bulutda qaysi ma'lumotlaringiz saqlanishini boshqaring.")
        SettingsRow {
            text: Tr.t("Ma'lumotlar sozlamalari"); last: true
            onClicked: page.nav.push(Qt.createComponent("PrivacyPage.qml"), { data: true })
        }
    }

    // ---- «Ma'lumotlar sozlamalari» ----
    SettingsGroup {
        visible: page.data
        title: Tr.t("Kontaktlar")
        note: Tr.t("Telefondagi kontaktlar shu hisob uchun Telegram serverlariga yuboriladi va yangilanib turadi. Boshqa hisoblarda alohida yoqiladi.")
        // (0.9.7: each account's own, Telegram Android's «Sync Contacts»; on: synced now and on each change)
        SettingsRow {
            text: Tr.t("Kontaktlarni sinxronlash"); toggle: true; on: accounts.sync
            onClicked: {
                accounts.setSync(!accounts.sync)
                if (accounts.sync) {
                    store.syncContacts()
                    page.nav.say(Tr.t("Kontaktlar sinxronlanmoqda…"))
                }
            }
        }
        SettingsRow { text: Tr.t("Sinxronlangan kontaktlarni o'chirish"); danger: true; chevron: false; last: true; onClicked: page.askClear("contacts") }
    }
    SettingsGroup {
        visible: page.data
        note: Tr.t("Qidiruvda tez-tez yozishadigan odamlaringizni ko'rsatish.")
        SettingsRow {
            text: Tr.t("Tez-tez yozishadiganlar"); toggle: true; on: page.topChats === 1; dim: page.topChats < 0; last: true
            onClicked: if (page.topChats >= 0) page.setTop(page.topChats !== 1)
        }
    }
    SettingsGroup {
        visible: page.data
        title: Tr.t("Chatlar")
        SettingsRow { text: Tr.t("Barcha qoralamalarni o'chirish"); danger: true; chevron: false; last: true; onClicked: page.askClear("drafts") }
    }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
