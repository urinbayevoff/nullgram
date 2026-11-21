// «Ikki bosqichli tasdiqlash» (Telegram-iOS's TwoFactorAuth screens, kept to what works without e-mail codes): the
// state (getPasswordState) — on: «Parolni o'zgartirish», «Parolni o'chirish», whether a recovery e-mail is set; off:
// «Parol o'rnatish». Each opens this page's form (`form`): the current password, the new one twice, a hint →
// setPassword (no recovery e-mail changed: set_recovery_email_address false). Wrong password: said under the fields.
import QtQuick

SubPage {
    id: page
    property var pw: null               // passwordState
    property string form: ""            // "", "set", "change", "off"
    property string error: ""
    property bool busy: false
    title: form === "set" ? Tr.t("Parol o'rnatish") : form === "change" ? Tr.t("Parolni o'zgartirish")
         : form === "off" ? Tr.t("Parolni o'chirish") : Tr.t("Ikki bosqichli tasdiqlash")
    action: form ? (form === "off" ? Tr.t("O'chirish") : Tr.t("Saqlash")) : ""
    actionBold: true
    actionOn: !busy && (form === "off" ? old.text.length > 0
                        : (form !== "change" || old.text.length > 0) && fresh.text.length > 0 && fresh.text === again.text)
    onActed: submit()
    guard: () => {
        if (!form)
            return false
        form = ""
        return true
    }
    onFormChanged: {
        error = ""
        old.text = ""; fresh.text = ""; again.text = ""; hint.text = ""
        if (form)
            (form === "set" ? fresh : old).take()
    }

    function reload() {
        store.send({ "@type": "getPasswordState" }, (r) => { if (r["@type"] === "passwordState") page.pw = r })
    }
    function submit() {
        if (!actionOn)
            return
        busy = true
        error = ""
        store.send({ "@type": "setPassword", old_password: form === "set" ? "" : old.text,
                     new_password: form === "off" ? "" : fresh.text, new_hint: form === "off" ? "" : hint.text,
                     set_recovery_email_address: false, new_recovery_email_address: "" }, (r) => {
            page.busy = false
            if (r["@type"] === "error") {
                page.error = r.message.indexOf("PASSWORD_HASH_INVALID") >= 0 ? Tr.t("Parol noto'g'ri.")
                           : r.message.indexOf("PASSWORD_TOO_FRESH") >= 0 ? Tr.t("Parol yaqinda o'zgargan, keyinroq urinib ko'ring.")
                           : r.message
                return
            }
            const said = page.form === "off" ? Tr.t("Qo'shimcha parol o'chirildi.")
                       : page.form === "set" ? Tr.t("Qo'shimcha parol o'rnatildi.") : Tr.t("Parol o'zgartirildi.")
            page.form = ""
            if (r["@type"] === "passwordState")
                page.pw = r
            else
                page.reload()
            page.nav.say(said)
        })
    }

    component Field: Item {
        id: f
        property alias text: input.text
        property string hintText: ""
        property bool secret: true
        property bool last: false
        function take() { input.forceActiveFocus() }
        width: parent ? parent.width : 300; height: 48
        TextInput {
            id: input
            x: 16; width: parent.width - 32
            anchors.verticalCenter: parent.verticalCenter
            echoMode: f.secret ? TextInput.Password : TextInput.Normal
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17
            selectionColor: Theme.accent
            clip: true
            onAccepted: page.submit()
        }
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            text: f.hintText
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 17
        }
        Rectangle { visible: !f.last; x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }

    // ---- the state ----
    Column {
        visible: !page.form
        width: parent.width
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.pw && page.pw.has_password ? "🔐" : "🔑"
            font.pixelSize: 72
        }
        Text {
            x: 32; width: parent.width - 64
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: page.pw && page.pw.has_password ? Tr.t("Qo'shimcha parol yoqilgan") : Tr.t("Ikki bosqichli tasdiqlash")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 21; font.weight: Font.DemiBold
        }
        Text {
            x: 32; width: parent.width - 64
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: page.pw && page.pw.has_password
                  ? Tr.t("Hisobingiz qo'shimcha parol bilan himoyalangan: yangi qurilmada kirishda SMS kodidan keyin u ham so'raladi.")
                  : Tr.t("Yangi qurilmada kirishda SMS kodidan tashqari so'raladigan parol o'rnatishingiz mumkin.")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }
    SettingsGroup {
        visible: !page.form && !!page.pw && page.pw.has_password
        note: page.pw && page.pw.password_hint ? Tr.f("Maslahat: %1", page.pw.password_hint) : ""
        SettingsRow { text: Tr.t("Parolni o'zgartirish"); onClicked: page.form = "change" }
        SettingsRow { text: Tr.t("Parolni o'chirish"); danger: true; chevron: false; last: true; onClicked: page.form = "off" }
    }
    SettingsGroup {
        visible: !page.form && !!page.pw && page.pw.has_password
        note: Tr.t("Parolni unutsangiz, uni tiklash kodi shu e-pochtaga keladi.")
        SettingsRow {
            text: Tr.t("Tiklash e-pochtasi"); chevron: false; last: true
            value: page.pw && page.pw.has_recovery_email_address ? Tr.t("O'rnatilgan") : Tr.t("Yo'q")
        }
    }
    SettingsGroup {
        visible: !page.form && !!page.pw && !page.pw.has_password
        SettingsRow { text: Tr.t("Parol o'rnatish"); accent: true; chevron: false; last: true; onClicked: page.form = "set" }
    }

    // ---- the form ----
    SettingsGroup {
        visible: page.form === "change" || page.form === "off"
        note: page.pw && page.pw.password_hint ? Tr.f("Maslahat: %1", page.pw.password_hint) : ""
        Field { id: old; hintText: Tr.t("Joriy parol"); last: true }
    }
    SettingsGroup {
        visible: page.form === "set" || page.form === "change"
        note: fresh.text && again.text && fresh.text !== again.text ? Tr.t("Parollar mos kelmadi.")
              : Tr.t("Maslahat parolni eslashga yordam beradi; uni kirishda hamma ko'radi.")
        Field { id: fresh; hintText: Tr.t("Yangi parol") }
        Field { id: again; hintText: Tr.t("Yangi parolni takrorlang") }
        Field { id: hint; hintText: Tr.t("Maslahat (ixtiyoriy)"); secret: false; last: true }
    }
    Text {
        visible: page.error !== ""
        x: 32; width: parent.width - 64
        wrapMode: Text.Wrap
        text: page.error
        color: Theme.danger
        font.family: Theme.font; font.pixelSize: 15
    }
}
