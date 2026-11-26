// My Profile edited (Telegram-iOS's PeerInfoScreen editing oneself): «Rasmni o'zgartirish» (the phone's pictures,
// AttachSheet → setProfilePhoto); first and last name; bio with what is left of its 70 (Premium 140); «Tug'ilgan kun»
// — the date wheel opens under it, «Tug'ilgan kunni olib tashlash», who sees it (PrivacyRulePage); Raqam,
// Foydalanuvchi nomi (UsernamePage), Sizning rangingiz (YourColorPage), Chat avtomatlashtirish; «Boshqa hisob
// qo'shish»; «Chiqish». «Tayyor» keeps the changed (setName, setBio, setBirthdate); ‹ with changes asks first.
import QtQuick
import "Privacy.js" as P

SubPage {
    id: page
    property var full: null                 // ProfilePage's getUserFullInfo
    readonly property var me: (store.seen, store.me)
    property string photo: ""
    readonly property int bioMax: me && me.is_premium ? 140 : 70
    readonly property var wasBirth: full && full.birthdate ? full.birthdate : null
    property var birth: null                // {day, month, year} or null
    property bool wheelOpen: false
    property var birthRule: null            // Privacy.js read of userPrivacySettingShowBirthdate
    property string botName: ""             // Chat Automation's bot, when one is connected
    readonly property bool birthChanged: JSON.stringify(birth) !== JSON.stringify(wasBirth ? { day: wasBirth.day, month: wasBirth.month, year: wasBirth.year } : null)
    readonly property bool dirty: !!me && (first.text.trim() !== me.first_name || last.text.trim() !== me.last_name
                                           || bio.text !== (full && full.bio ? full.bio.text : "") || birthChanged)

    title: ""
    action: Tr.t("Tayyor")
    actionBold: true
    actionOn: first.text.trim() !== ""
    onActed: save()
    guard: () => {
        if (sheet && sheet.open) {
            sheet.close()
            return true
        }
        if (!dirty)
            return false
        alert.title = ""
        alert.text = Tr.t("O'zgarishlar saqlanmasinmi?")
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Saqlamaslik"), red: true, run: () => page.nav.pop() }]
        alert.open = true
        return true
    }

    Component.onCompleted: {
        if (me) {
            first.text = me.first_name
            last.text = me.last_name
            store.userPhoto(me, (p) => page.photo = p)
        }
        bio.text = full && full.bio ? full.bio.text : ""
        birth = wasBirth ? { day: wasBirth.day, month: wasBirth.month, year: wasBirth.year } : null
        readRule()
        store.send({ "@type": "getBusinessConnectedBot" }, (r) => {
            if (r["@type"] === "businessConnectedBot") {
                const u = store.users[r.bot_user_id]
                page.botName = u ? (u.first_name + " " + u.last_name).trim() : Tr.t("Ulangan")
            }
        })
    }
    function readRule() {
        store.send({ "@type": "getUserPrivacySettingRules", setting: { "@type": "userPrivacySettingShowBirthdate" } }, (r) => {
            if (r["@type"] === "userPrivacySettingRules")
                page.birthRule = P.read(r)
        })
    }
    function ruleText(r) {
        if (!r)
            return ""
        const base = r.base === 0 ? Tr.t("Hamma") : r.base === 1 ? Tr.t("Kontaktlarim") : Tr.t("Hech kim")
        const n = P.counts(r), w = []
        if (n.minus)
            w.push("−" + n.minus)
        if (n.plus)
            w.push("+" + n.plus)
        return base + (w.length ? " (" + w.join(", ") + ")" : "")
    }
    function save() {
        let left = 0
        const fail = (r) => { if (r["@type"] === "error") page.nav.say(Tr.f("Bo'lmadi: %1", r.message)) }
        const done = (r) => { fail(r); if (--left <= 0) page.nav.pop() }
        const f = first.text.trim(), l = last.text.trim()
        if (f !== me.first_name || l !== me.last_name) {
            left++
            store.send({ "@type": "setName", first_name: f, last_name: l }, done)
        }
        if (bio.text !== (full && full.bio ? full.bio.text : "")) {
            left++
            store.send({ "@type": "setBio", bio: bio.text }, done)
        }
        if (birthChanged) {
            left++
            store.send({ "@type": "setBirthdate", birthdate: birth ? Object.assign({ "@type": "birthdate" }, birth) : null }, done)
        }
        if (!left)
            nav.pop()
    }
    function open(file, props) {
        const c = Qt.createComponent(file)
        if (c.status === Component.Error)
            return console.warn("nullgram:", c.errorString())
        return nav.push(c, props || {})
    }
    function setPhoto(path) {
        page.photo = path
        nav.say(Tr.t("Rasm yuklanmoqda…"))
        store.send({ "@type": "setProfilePhoto", is_public: false,
                     photo: { "@type": "inputChatPhotoStatic", photo: { "@type": "inputFileLocal", path: path } } }, (r) => {
            page.nav.say(r["@type"] === "error" ? Tr.f("Bo'lmadi: %1", r.message) : Tr.t("Profil rasmi yangilandi"))
        })
    }
    function askLogOut() {
        alert.title = Tr.t("Chiqish")
        alert.text = Tr.t("Rostdan ham hisobdan chiqmoqchimisiz?") +
                     (accounts.count > 1 ? "\n" + Tr.t("Faqat shu hisobdan chiqasiz. Boshqa hisoblaringiz qoladi.") : "")
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Chiqish"), red: true, run: () => store.logOut() }]
        alert.open = true
    }

    // ---- the picture ----
    Item { width: 1; height: 8 }
    Column {
        width: parent.width
        spacing: 10
        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100; height: 100
            source: page.photo
            letters: store.letters(first.text + " " + last.text)
            tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
            MouseArea { anchors.fill: parent; onClicked: page.pickPhoto() }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Rasmni o'zgartirish")
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 17
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: page.pickPhoto() }
        }
        Item { width: 1; height: 4 }
    }

    // ---- the name ----
    component Field: Item {
        property alias input: box
        property string hint: ""
        property bool line: true
        width: parent.width; height: 48
        TextInput {
            id: box
            x: 16; width: parent.width - 32
            anchors.verticalCenter: parent.verticalCenter
            maximumLength: 64
            color: Theme.text; selectionColor: Theme.accent
            font.family: Theme.font; font.pixelSize: 17
            clip: true
        }
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            visible: !box.text
            text: parent.hint
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 17
        }
        Rectangle { visible: parent.line; x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }
    SettingsGroup {
        note: Tr.t("Ismingizni kiriting va ixtiyoriy profil rasmini qo'shing.")
        Field { id: firstF; hint: Tr.t("Ism") }
        Field { id: lastF; hint: Tr.t("Familiya"); line: false }
    }
    property alias first: firstF.input
    property alias last: lastF.input

    // ---- bio ----
    SettingsGroup {
        note: Tr.t("Profilingizga bir necha so'z qo'shing: masalan, kasbingiz yoki yoshingiz.")
        Item {
            width: parent.width; height: Math.max(48, bio.contentHeight + 26)
            TextEdit {
                id: bio
                x: 16; y: 13; width: parent.width - 64
                wrapMode: TextEdit.Wrap
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                onTextChanged: if (length > page.bioMax) remove(page.bioMax, length)
            }
            Text {
                x: 16; y: 13
                visible: !bio.text
                text: Tr.t("Bio")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16; y: 15
                text: page.bioMax - bio.length
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
        }
    }

    // ---- birthday ----
    SettingsGroup {
        note: page.birthRule ? Tr.f("Tug'ilgan kuningizni kim ko'radi: %1.", page.ruleText(page.birthRule)) : ""
        SettingsRow {
            art: "birthday"
            text: Tr.t("Tug'ilgan kun")
            chevron: false
            accent: false
            value: page.birth ? Tr.date(page.birth.day, page.birth.month, page.birth.year) : Tr.t("Qo'shish")
            last: !page.wheelOpen && !page.birth
            onClicked: {
                if (!page.birth)
                    page.birth = { day: 1, month: 1, year: 0 }
                page.wheelOpen = !page.wheelOpen
                if (page.wheelOpen)
                    wheel.set(page.birth.day, page.birth.month, page.birth.year)
            }
        }
        Item {
            visible: page.wheelOpen
            width: parent.width; height: visible ? wheel.height + 12 : 0
            DateWheel {
                id: wheel
                y: 6
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 340)
                onChanged: page.birth = { day: wheel.day, month: wheel.month, year: wheel.year }
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
        }
        SettingsRow {
            visible: !!page.birth
            text: Tr.t("Tug'ilgan kunni olib tashlash")
            danger: true
            chevron: false
            last: true
            onClicked: { page.birth = null; page.wheelOpen = false }
        }
    }
    SettingsGroup {
        SettingsRow {
            art: "privacy"
            text: Tr.t("Kim ko'radi")
            value: page.ruleText(page.birthRule)
            last: true
            onClicked: {
                if (!page.birthRule)
                    return
                const p = page.open("PrivacyRulePage.qml", { key: "userPrivacySettingShowBirthdate", heading: Tr.t("Tug'ilgan kun"), r: page.birthRule })
                if (p)
                    p.changed.connect((r) => page.birthRule = r)
            }
        }
    }

    // ---- number, username, colour, automation ----
    SettingsGroup {
        SettingsRow {
            art: "calls"
            text: Tr.t("Raqam")
            value: page.me && page.me.phone_number ? "+" + page.me.phone_number : ""
            onClicked: page.nav.say(Tr.t("Raqamni o'zgartirish hali yo'q — Telegram'ning boshqa ilovasida o'zgartiring"))
        }
        SettingsRow {
            art: "profile"
            text: Tr.t("Foydalanuvchi nomi")
            value: page.me && page.me.usernames && page.me.usernames.editable_username ? "@" + page.me.usernames.editable_username : ""
            onClicked: page.open("UsernamePage.qml", {})
        }
        SettingsRow {
            art: "color"
            text: Tr.t("Sizning rangingiz")
            onClicked: page.open("YourColorPage.qml", {})
        }
        SettingsRow {
            art: "business"
            text: Tr.t("Chat avtomatlashtirish")
            value: page.botName || Tr.t("O'chiq")
            last: true
            onClicked: page.nav.say(Tr.t("Chat-botni ulash uchun Telegram Business kerak — hali yo'q"))
        }
    }
    SettingsGroup {
        note: Tr.t("Bir nechta hisobni ulab, ular orasida tez almashishingiz mumkin.")
        SettingsRow {
            text: Tr.t("Boshqa hisob qo'shish")
            accent: true
            chevron: false
            last: true
            onClicked: page.nav.say(Tr.t("Bir nechta hisob hali yo'q"))
        }
    }
    SettingsGroup {
        SettingsRow {
            text: Tr.t("Chiqish")
            danger: true
            chevron: false
            last: true
            onClicked: page.askLogOut()
        }
    }
    Item { width: 1; height: 32 }

    Alert { id: alert; parent: page; anchors.fill: parent }

    // the phone's pictures: made on the page itself (not in SubPage's column), the first time it is wanted
    property var sheet: null
    function pickPhoto() {
        if (!sheet)
            sheet = sheetMaker.createObject(page)
        sheet.show()
    }
    Component {
        id: sheetMaker
        AttachSheet {
            rights: ({ photos: true, videos: false, files: false, music: false, other: false, voice: false, round: false })
            onRefused: (text) => page.nav.say(Tr.t("Faqat rasm tanlang"))
            onSend: (picked) => {
                const p = picked.find((f) => f.kind === "photo")
                if (p)
                    page.setPhoto(p.path)
            }
        }
    }
}
