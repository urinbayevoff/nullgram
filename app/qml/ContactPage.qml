// A contact's names and our notes on them, as Telegram-iOS's PeerInfoScreen edits a contact (Edit → its
// editingItems) and adds one (openAddContact): the picture, «Ism» and «Familiya» on a card, «Eslatma qo'shish»
// (PeerInfoScreenNoteListItem) with «Eslatmalar faqat sizga ko'rinadi.» under it; adding, «Telefon raqamimni
// ulashish» when they cannot see our number (need_phone_number_privacy_exception); editing, «Kontaktni o'chirish»
// in red (asked first, as requestDeleteContact). «Tayyor» on the bar: addContact (it renames a contact too, the
// notes with it) — then back to their page. Editing, as iOS's, between the notes and «Kontaktni o'chirish»: «Tug'ilgan
// kunni taklif qilish» (no birthday known: a date wheel, «Taklif qilish» → suggestUserBirthdate), «X uchun rasm taklif
// qilish» (a picture of the phone's → suggestUserProfilePhoto), «X uchun rasm o'rnatish» (one only we see:
// setUserPersonalProfilePhoto; set: «Asl rasmga qaytarish» takes it away).
import QtQuick

SubPage {
    id: page
    property var userId: 0
    property var full: null            // their userFullInfo (the note, need_phone_number_privacy_exception)
    property bool adding: false
    property bool byPhone: false       // adding a new contact by phone number (importContacts)
    property string photo: ""
    property bool saving: false
    property string errorText: ""
    readonly property var user: byPhone ? null : (store.seen, store.users[userId])
    readonly property string phoneText: {
        const n = user && user.phone_number ? user.phone_number : ""
        const m = /^998(\d{2})(\d{3})(\d{2})(\d{2})$/.exec(n)
        return !n ? "" : m ? "+998 " + m.slice(1).join(" ") : "+" + n
    }
    readonly property string firstOf: first.text.trim() || (user ? user.first_name : "")
    signal said(string text)            // a word for their page's note
    signal added(var userId)            // emitted after byPhone importContacts succeeds

    title: byPhone ? Tr.t("Yangi kontakt") : adding ? Tr.t("Kontakt qo'shish") : ""
    action: byPhone && saving ? "" : byPhone ? Tr.t("Yaratish") : Tr.t("Tayyor")
    actionBold: true
    actionOn: byPhone ? (first.text.trim() !== "" && phoneInput.text.trim() !== "" && !saving)
                      : (first.text.trim() !== "" && !saving)
    onActed: save()

    Component.onCompleted: {
        if (!user)
            return
        first.text = user.first_name || ""
        last.text = user.last_name || ""
        notes.text = full && full.note ? full.note.text : ""
        store.userPhoto(user, (p) => page.photo = p)
    }

    function save() {
        if (!actionOn)
            return
        if (byPhone) {
            const raw = phoneInput.text.trim()
            const digits = raw.replace(/[^0-9]/g, "")
            if (/[a-zA-Z\u0400-\u04FF]/.test(raw) || digits.length < 7 || digits.length > 15) {
                errorText = Tr.t("Raqam noto'g'ri. Qaytadan tekshiring.")
                return
            }
            saving = true
            errorText = ""
            phoneInput.focus = false
            first.focus = false
            last.focus = false
            if (osk.h > 0)
                osk.hide()
            store.importContact("+" + digits, first.text.trim(), last.text.trim(), (uid, err) => {
                if (!page)
                    return
                page.saving = false
                if (err) {
                    page.errorText = err.indexOf("PHONE_NUMBER_INVALID") >= 0
                        ? Tr.t("Raqam noto'g'ri. Qaytadan tekshiring.")
                        : err
                    return
                }
                if (!uid) {
                    page.errorText = Tr.t("Bu raqam Telegram'da ro'yxatdan o'tmagan.")
                    return
                }
                page.added(uid)
                page.nav.say(Tr.f("%1 endi kontaktlaringiz ro'yxatida.", first.text.trim()))
                page.nav.pop()
            })
            return
        }
        saving = true
        const note = { "@type": "formattedText", text: notes.text.trim(), entities: [] }
        store.send({ "@type": "addContact", user_id: userId,
                     contact: { "@type": "importedContact", phone_number: user.phone_number || "",
                                first_name: first.text.trim(), last_name: last.text.trim(), note: note },
                     share_phone_number: share.on && share.visible }, (r) => {
            page.saving = false
            if (r["@type"] === "error") {
                console.warn("nullgram: addContact", r.code, r.message)
                return page.said(r.message)
            }
            // (an existing contact's notes: addContact may leave them; setUserNote says it once more)
            if (!page.adding && note.text !== (page.full && page.full.note ? page.full.note.text : ""))
                store.send({ "@type": "setUserNote", user_id: page.userId, note: note }, store.check)
            if (page.adding)
                page.said(Tr.f("%1 endi kontaktlaringiz ro'yxatida.", first.text.trim()))
            page.nav.pop()
        })
    }
    function askDelete() {
        sheetMode = "delete"
        sheet.open = true
    }
    function askStartSecret() {
        sheetMode = "secret"
        sheet.open = true
    }
    function startSecret() {
        store.startSecretChat(userId, (cid, err) => {
            if (!page)
                return
            if (cid)
                page.nav.openCreatedChat(cid)
            else if (err)
                page.said(err)
        })
    }
    function remove() {
        store.send({ "@type": "removeContacts", user_ids: [userId] }, (r) => {
            if (r["@type"] === "error")
                return page.said(r.message)
            page.said(Tr.t("Kontakt o'chirildi"))
            page.nav.pop()
        })
    }

    // ---- spinner for byPhone importContacts ----
    Ring {
        parent: page
        z: 10
        visible: page.byPhone && page.saving
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 17
        width: 22; height: 22
        value: 0.72
        cross: false
        color: Theme.accent
        thickness: 2.2
    }

    // ---- the picture, their number under it ----
    Column {
        width: parent.width
        spacing: 8
        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100; height: 100
            source: page.photo
            letters: page.store.letters(((first.text || "") + " " + (last.text || "")).trim() || "?")
            tint: page.byPhone ? Theme.accent : page.store.tints[Math.abs(page.userId) % page.store.tints.length]
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.phoneText !== ""
            text: page.phoneText
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    // ---- the names ----
    SettingsGroup {
        Item {
            width: parent.width; height: 46
            TextInput {
                id: first
                x: 16; width: parent.width - 32; height: 46
                verticalAlignment: TextInput.AlignVCenter
                enabled: !page.saving
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
                maximumLength: 64
                onAccepted: last.forceActiveFocus()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !first.text
                    text: Tr.t("Ism")
                    color: Theme.grey
                    font: first.font
                }
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator }
        }
        Item {
            width: parent.width; height: 46
            TextInput {
                id: last
                x: 16; width: parent.width - 32; height: 46
                verticalAlignment: TextInput.AlignVCenter
                enabled: !page.saving
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
                maximumLength: 64
                onAccepted: page.byPhone ? phoneInput.forceActiveFocus() : notes.forceActiveFocus()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !last.text
                    text: Tr.t("Familiya")
                    color: Theme.grey
                    font: last.font
                }
            }
        }
    }

    // ---- phone number (byPhone mode: importContacts) ----
    SettingsGroup {
        visible: page.byPhone
        note: Tr.t("Telefon raqamini mamlakat kodi bilan kiriting (masalan, +998 90 123 45 67).")
        Item {
            width: parent.width; height: 46
            TextInput {
                id: phoneInput
                x: 16; width: parent.width - 32; height: 46
                verticalAlignment: TextInput.AlignVCenter
                enabled: !page.saving
                inputMethodHints: Qt.ImhDialableCharactersOnly
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                maximumLength: 24
                clip: true
                onTextChanged: page.errorText = ""
                onAccepted: page.save()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !phoneInput.text
                    text: Tr.t("Telefon raqami")
                    color: Theme.grey
                    font: phoneInput.font
                }
            }
        }
    }
    Text {
        visible: page.byPhone && page.errorText !== ""
        x: 32; width: parent.width - 64
        wrapMode: Text.Wrap
        text: page.errorText
        color: Theme.danger
        font.family: Theme.font; font.pixelSize: 14
    }

    // ---- our notes on them (only we see them) ----
    SettingsGroup {
        visible: !page.byPhone
        note: Tr.t("Eslatmalar faqat sizga ko'rinadi.")
        Item {
            width: parent.width
            height: Math.max(46, notes.contentHeight + 24)
            TextEdit {
                id: notes
                x: 16; y: 12
                width: parent.width - 32
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
                Text {
                    visible: !notes.text
                    text: Tr.t("Eslatma qo'shish")
                    color: Theme.grey
                    font: notes.font
                }
            }
        }
    }

    // ---- editing: a birthday or a picture suggested to them, a picture of them for us only ----
    readonly property bool canSuggest: !adding && !!user && user.type["@type"] === "userTypeRegular"
    property bool wheelOpen: false
    property string photoFor: ""        // the picture being picked: "suggest" | "personal"
    property var sheet2: null
    function pickPhoto(why) {
        photoFor = why
        if (!sheet2)
            sheet2 = pickMaker.createObject(page)
        sheet2.show()
    }
    function usePhoto(path) {
        const photo = { "@type": "inputChatPhotoStatic", photo: { "@type": "inputFileLocal", path: path } }
        const suggest = photoFor === "suggest"
        if (!suggest)
            page.photo = path
        page.said(Tr.t("Rasm yuklanmoqda…"))
        store.send({ "@type": suggest ? "suggestUserProfilePhoto" : "setUserPersonalProfilePhoto", user_id: userId, photo: photo }, (r) => {
            page.said(r["@type"] === "error" ? Tr.f("Bo'lmadi: %1", r.message)
                      : suggest ? Tr.f("Rasm %1ga taklif qilindi", page.firstOf) : Tr.f("%1 rasmi endi faqat sizga ko'rinadi", page.firstOf))
        })
    }
    function resetPhoto() {
        store.send({ "@type": "setUserPersonalProfilePhoto", user_id: userId, photo: null }, (r) => {
            if (r["@type"] === "error")
                return page.said(r.message)
            page.said(Tr.t("Asl rasm qaytarildi"))
            if (page.full)
                page.full = Object.assign({}, page.full, { personal_photo: null })
            store.userPhoto(page.user, (p) => page.photo = p)
        })
    }
    function suggestBirth() {
        const b = { "@type": "birthdate", day: wheel.day, month: wheel.month, year: wheel.year }
        store.send({ "@type": "suggestUserBirthdate", user_id: userId, birthdate: b }, (r) => {
            if (r["@type"] === "error")
                return page.said(Tr.f("Bo'lmadi: %1", r.message))
            page.wheelOpen = false
            page.said(Tr.f("Tug'ilgan kun %1ga taklif qilindi", page.firstOf))
        })
    }
    Component {
        id: pickMaker
        AttachSheet {
            rights: ({ photos: true, videos: false, files: false, music: false, other: false, voice: false, round: false })
            onRefused: (text) => page.said(Tr.t("Faqat rasm tanlang"))
            onSend: (picked) => {
                const p = picked.find((f) => f.kind === "photo")
                if (p)
                    page.usePhoto(p.path)
            }
        }
    }
    SettingsGroup {
        visible: page.canSuggest
        note: Tr.f("%1 rasmini faqat o'zingiz ko'radigan boshqa rasm bilan almashtirishingiz mumkin.", page.firstOf)
        SettingsRow {
            visible: !(page.full && page.full.birthdate)
            icon: "gift"; bare: true
            text: Tr.t("Tug'ilgan kunni taklif qilish")
            accent: true; chevron: false
            onClicked: {
                page.wheelOpen = !page.wheelOpen
                if (page.wheelOpen)
                    wheel.set(1, 1, 0)
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
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
        }
        SettingsRow {
            visible: page.wheelOpen
            text: Tr.t("Taklifni yuborish")
            accent: true; chevron: false
            onClicked: page.suggestBirth()
        }
        SettingsRow {
            icon: "camera"; bare: true
            text: Tr.f("%1 uchun rasm taklif qilish", page.firstOf)
            accent: true; chevron: false
            onClicked: page.pickPhoto("suggest")
        }
        SettingsRow {
            icon: "camera"; bare: true
            text: Tr.f("%1 uchun rasm o'rnatish", page.firstOf)
            accent: true; chevron: false
            last: !(page.full && page.full.personal_photo)
            onClicked: page.pickPhoto("personal")
        }
        SettingsRow {
            visible: !!(page.full && page.full.personal_photo)
            text: Tr.t("Asl rasmga qaytarish")
            accent: true; chevron: false; last: true
            onClicked: page.resetPhoto()
        }
    }

    // ---- adding: our number for them; editing: away with the contact ----
    SettingsGroup {
        visible: share.visible
        note: Tr.f("Raqamingizni %1 ko'ra oladi.", page.firstOf)
        SettingsRow {
            id: share
            visible: page.adding && !!page.full && !!page.full.need_phone_number_privacy_exception
            text: Tr.t("Telefon raqamimni ulashish")
            toggle: true
            on: true
            last: true
            onClicked: on = !on
        }
    }
    SettingsGroup {
        visible: page.adding && !page.byPhone && !page.phoneText
        Text {
            x: 16; width: parent.width - 32
            topPadding: 12; bottomPadding: 12
            wrapMode: Text.Wrap
            text: Tr.f("Telefon raqami %1 sizni kontaktlariga qo'shganda ko'rinadi.", page.firstOf)
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
    }
    SettingsGroup {
        visible: page.canSuggest && !(page.store.me && page.userId === page.store.me.id)
        SettingsRow {
            icon: "lock"; bare: true
            text: Tr.t("Maxfiy chat boshlash")
            accent: true; chevron: false; last: true
            onClicked: page.askStartSecret()
        }
    }
    SettingsGroup {
        visible: !page.adding && !page.byPhone
        SettingsRow {
            text: Tr.t("Kontaktni o'chirish")
            danger: true
            chevron: false
            last: true
            onClicked: page.askDelete()
        }
    }
    Item {
        visible: page.byPhone
        width: 1; height: Math.max(osk.h, safe.bottom) + 16
    }

    property string sheetMode: "delete" // "delete" | "secret"
    // iOS's action sheet: «Kontaktni o'chirish» in red (or «Maxfiy chat boshlash») on a card, «Bekor qilish» under it
    Item {
        id: sheet
        parent: page
        anchors.fill: parent
        z: 30
        property bool open: false
        visible: dim.opacity > 0
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: sheet.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: sheet.open ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0] } }
            spacing: 8
            Repeater {
                model: page.sheetMode === "secret"
                    ? [{ t: Tr.t("Maxfiy chat boshlash"), act: "secret", red: false }, { t: Tr.t("Bekor qilish"), act: "", red: false }]
                    : [{ t: Tr.t("Kontaktni o'chirish"), act: "delete", red: true }, { t: Tr.t("Bekor qilish"), act: "", red: false }]
                Rectangle {
                    required property var modelData
                    width: parent.width; height: 57
                    radius: 14
                    color: sheetHit.pressed ? Theme.highlight : Theme.menu
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        color: parent.modelData.red ? Theme.danger : Theme.accent
                        font.family: Theme.font; font.pixelSize: 20; font.weight: parent.modelData.act ? Font.Normal : Font.DemiBold
                    }
                    MouseArea {
                        id: sheetHit
                        anchors.fill: parent
                        onClicked: {
                            sheet.open = false
                            page.runSheetAct(parent.modelData.act)
                        }
                    }
                }
            }
        }
    }
    function runSheetAct(act) {
        if (act === "delete") remove()
        else if (act === "secret") startSecret()
    }
    // the shell's back: the sheet closes first
    function dismiss() {
        if (sheet2 && sheet2.open) {
            sheet2.close()
            return true
        }
        if (sheet.open) {
            sheet.open = false
            return true
        }
        return false
    }
}
