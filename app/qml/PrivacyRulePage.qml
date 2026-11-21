// One privacy setting (Telegram-iOS's SelectivePrivacySettingsController): «Kim …?» — Hamma / Kontaktlarim / Hech kim
// (✓), what it means, then «ISTISNOLAR»: «Doim ruxsat berish» (not under «Hamma») and «Hech qachon ruxsat bermaslik»
// (not under «Hech kim») — people and groups picked in FolderChatsPage. Each change goes at once
// (setUserPrivacySettingRules) and changed(r) tells the list. Extras as iOS's: the phone number's «Meni raqamim orqali
// kim topa oladi?» (userPrivacySettingAllowFindingByPhoneNumber); «So'nggi faollik»'s «O'qilgan vaqtni yashirish».
import QtQuick
import "Privacy.js" as P

SubPage {
    id: page
    property string key: ""
    property string heading: ""
    property var r: null                // Privacy.read(...)
    property int finding: -1            // (the phone number: 0 everybody, 1 my contacts)
    property int readDate: -1           // (last seen: 1 the read time shown)
    signal changed(var r)
    title: heading

    readonly property var asks: ({
        userPrivacySettingShowPhoneNumber: "Telefon raqamimni kim ko'ra oladi?",
        userPrivacySettingShowStatus: "So'nggi faolligimni kim ko'ra oladi?",
        userPrivacySettingShowProfilePhoto: "Profil rasmlarimni kim ko'ra oladi?",
        userPrivacySettingShowBio: "Biomni kim ko'ra oladi?",
        userPrivacySettingAutosaveGifts: "Sovg'alarimni kim ko'ra oladi?",
        userPrivacySettingShowBirthdate: "Tug'ilgan kunimni kim ko'ra oladi?",
        userPrivacySettingShowProfileAudio: "Saqlangan musiqamni kim ko'ra oladi?",
        userPrivacySettingShowLinkInForwardedMessages: "Uzatilgan xabarlarimda hisobimga havolani kim qo'sha oladi?",
        userPrivacySettingAllowCalls: "Menga kim qo'ng'iroq qila oladi?",
        userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages: "Menga kim ovozli va video xabar yubora oladi?",
        userPrivacySettingAllowChatInvites: "Meni guruh va kanallarga kim qo'sha oladi?"
    })
    readonly property var notes: ({
        userPrivacySettingShowStatus: "Kimgadir so'nggi faolligingizni ko'rsatmasangiz, siz ham ularnikini ko'rmaysiz. Taxminiy vaqt (yaqinda, shu hafta, shu oy) baribir ko'rinadi.",
        userPrivacySettingShowLinkInForwardedMessages: "Xabarlaringiz uzatilganda, cheklangan odamlar uchun ular hisobingizga havola bo'lmaydi.",
        userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages: "Ovozli va video xabarlarni cheklash uchun Telegram Premium kerak.",
        userPrivacySettingAllowChatInvites: "Sizni qo'sha olmaganlar uchun shaxsiy taklif havolasi yuborish taklif qilinadi."
    })

    Component.onCompleted: {
        if (key === "userPrivacySettingShowPhoneNumber")
            store.send({ "@type": "getUserPrivacySettingRules", setting: { "@type": "userPrivacySettingAllowFindingByPhoneNumber" } },
                       (x) => { if (x["@type"] === "userPrivacySettingRules") page.finding = P.read(x).base === 0 ? 0 : 1 })
        if (key === "userPrivacySettingShowStatus")
            store.send({ "@type": "getReadDatePrivacySettings" },
                       (x) => { if (x["@type"] === "readDatePrivacySettings") page.readDate = x.show_read_date ? 1 : 0 })
    }

    function apply(next) {
        const was = r
        r = next
        store.send({ "@type": "setUserPrivacySettingRules", setting: { "@type": key }, rules: P.make(next) }, (x) => {
            if (x["@type"] === "error") {
                console.warn("nullgram: privacy", key, x.message)
                page.r = was
                page.nav.say(x.message.indexOf("PREMIUM") >= 0 ? Tr.t("Buning uchun Telegram Premium kerak.") : x.message)
                return
            }
            page.changed(page.r)
        })
    }
    function setBase(b) {
        if (r && r.base !== b)
            apply(Object.assign({}, r, { base: b }))
    }
    function setFinding(v) {
        finding = v
        store.send({ "@type": "setUserPrivacySettingRules", setting: { "@type": "userPrivacySettingAllowFindingByPhoneNumber" },
                     rules: P.make({ base: v === 0 ? 0 : 1, allowUsers: [], allowChats: [], denyUsers: [], denyChats: [] }) }, () => {})
    }
    function setReadDate(on) {
        readDate = on ? 1 : 0
        store.send({ "@type": "setReadDatePrivacySettings", settings: { "@type": "readDatePrivacySettings", show_read_date: on } }, () => {})
    }
    function count(n) { return n ? Tr.f("%1 ta", n) : Tr.t("Qo'shish") }
    // the people and groups of one list picked again (a private chat's id is its user's)
    function pick(allow) {
        const users = allow ? r.allowUsers : r.denyUsers, chats = allow ? r.allowChats : r.denyChats
        const p = nav.push(Qt.createComponent("FolderChatsPage.qml"), {
            heading: allow ? Tr.t("Doim ruxsat berish") : Tr.t("Hech qachon ruxsat bermaslik"),
            chosen: users.concat(chats),
            pool: (c) => !store.isSaved(c) && !(c.type["@type"] === "chatTypeSupergroup" && c.type.is_channel) })
        if (!p)
            return
        p.done.connect((flags, ids) => {
            const u = [], g = []
            for (const id of ids) {
                const c = store.chats[id]
                if (c && c.type["@type"] === "chatTypePrivate")
                    u.push(c.type.user_id)
                else if (c || id < 0)
                    g.push(id)
                else
                    u.push(id)
            }
            const next = Object.assign({}, page.r)
            if (allow) { next.allowUsers = u; next.allowChats = g }
            else { next.denyUsers = u; next.denyChats = g }
            // (one in both lists: the newest list wins, as iOS removes it from the other)
            const other = allow ? ["denyUsers", "denyChats"] : ["allowUsers", "allowChats"]
            next[other[0]] = next[other[0]].filter((x) => u.indexOf(x) < 0)
            next[other[1]] = next[other[1]].filter((x) => g.indexOf(x) < 0)
            page.apply(next)
        })
    }

    SettingsGroup {
        visible: !!page.r
        title: Tr.t(page.asks[page.key] || "")
        note: page.notes[page.key] ? Tr.t(page.notes[page.key]) : ""
        Repeater {
            model: [[0, "Hamma"], [1, "Kontaktlarim"], [2, "Hech kim"]]
            SettingsRow {
                required property var modelData
                required property int index
                text: Tr.t(modelData[1]); chevron: false; last: index === 2
                tick: !!page.r && page.r.base === modelData[0]
                onClicked: page.setBase(modelData[0])
            }
        }
    }
    SettingsGroup {
        visible: page.key === "userPrivacySettingShowPhoneNumber" && page.finding >= 0 && !!page.r && page.r.base !== 0
        title: Tr.t("Meni raqamim orqali kim topa oladi?")
        note: Tr.t("Raqamingizni kontaktlariga saqlagan foydalanuvchilar uni Telegram'da ham ko'radi.")
        SettingsRow { text: Tr.t("Hamma"); chevron: false; tick: page.finding === 0; onClicked: page.setFinding(0) }
        SettingsRow { text: Tr.t("Kontaktlarim"); chevron: false; tick: page.finding === 1; last: true; onClicked: page.setFinding(1) }
    }
    SettingsGroup {
        visible: !!page.r
        title: Tr.t("Istisnolar")
        note: Tr.t("Bu sozlamalar yuqoridagi tanlovdan ustun turadi.")
        SettingsRow {
            visible: !!page.r && page.r.base !== 0
            text: Tr.t("Doim ruxsat berish"); last: !!page.r && page.r.base === 2
            value: page.r ? page.count(page.r.allowUsers.length + page.r.allowChats.length) : ""
            onClicked: page.pick(true)
        }
        SettingsRow {
            visible: !!page.r && page.r.base !== 2
            text: Tr.t("Hech qachon ruxsat bermaslik"); last: true
            value: page.r ? page.count(page.r.denyUsers.length + page.r.denyChats.length) : ""
            onClicked: page.pick(false)
        }
    }
    SettingsGroup {
        visible: page.key === "userPrivacySettingShowStatus" && page.readDate >= 0
        note: Tr.t("Yoqilsa, xabaringizni qachon o'qiganingiz boshqalarga ko'rinmaydi va siz ham ularnikini ko'rmaysiz.")
        SettingsRow { text: Tr.t("O'qilgan vaqtni yashirish"); toggle: true; on: page.readDate === 0; last: true; onClicked: page.setReadDate(page.readDate === 0) }
    }
}
