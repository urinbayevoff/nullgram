// My username (Telegram-iOS's UsernameSetupController): the field, checked as it is typed (checkChatUsername on
// my own chat, 0.4 s after the last letter), the rules, and the t.me link that opens a chat with me (tapped:
// copied). «Tayyor» sets it (setUsername; empty takes it away).
import QtQuick

SubPage {
    id: page
    readonly property var me: (store.seen, store.me)
    readonly property string was: me && me.usernames ? me.usernames.editable_username || "" : ""
    property string check: ""               // checkChatUsername's answer (its @type's tail), "" not yet
    title: Tr.t("Foydalanuvchi nomi")
    action: Tr.t("Tayyor")
    actionBold: true
    actionOn: uname.text === "" || uname.text === was || check === "Ok"
    onActed: save()
    Component.onCompleted: {
        uname.text = was
        uname.forceActiveFocus()
    }

    function save() {
        if (uname.text === was)
            return nav.pop()
        store.send({ "@type": "setUsername", username: uname.text }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.pop()
        })
    }
    Timer {
        id: soon
        interval: 400
        onTriggered: {
            const name = uname.text
            if (name.length < 5 || name === page.was) {
                page.check = ""
                return
            }
            store.send({ "@type": "checkChatUsername", chat_id: page.me.id, username: name }, (r) => {
                if (uname.text === name)
                    page.check = r["@type"] === "error" ? "Invalid" : r["@type"].replace("checkChatUsernameResult", "")
            })
        }
    }
    readonly property string checkText: {
        const t = uname.text
        if (t === "" || t === was)
            return ""
        if (!/^[A-Za-z0-9_]*$/.test(t))
            return Tr.t("Faqat a–z, 0–9 va _ ishlatish mumkin.")
        if (/^[0-9_]/.test(t))
            return Tr.t("Nom harf bilan boshlanishi kerak.")
        if (t.length < 5)
            return Tr.t("Nom kamida 5 belgidan iborat bo'lishi kerak.")
        switch (check) {
        case "Ok": return Tr.f("%1 bo'sh.", t)
        case "UsernameOccupied": return Tr.t("Bu nom band.")
        case "UsernamePurchasable": return Tr.t("Bu nomni Fragment'da sotib olish mumkin.")
        case "": return Tr.t("Tekshirilmoqda…")
        default: return Tr.t("Nom noto'g'ri.")
        }
    }
    TextEdit { id: clip; visible: false }

    Item { width: 1; height: 16 }
    SettingsGroup {
        title: Tr.t("FOYDALANUVCHI NOMI")
        Item {
            width: parent.width; height: 48
            Text {
                id: at
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: "@"
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
            TextInput {
                id: uname
                x: at.x + at.width + 2; width: parent.width - x - 16
                anchors.verticalCenter: parent.verticalCenter
                maximumLength: 32
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhPreferLatin
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                clip: true
                onTextChanged: { page.check = ""; soon.restart() }
            }
            Text {
                x: uname.x; anchors.verticalCenter: parent.verticalCenter
                visible: !uname.text
                text: Tr.t("foydalanuvchi_nomi")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
        }
    }
    Text {
        x: 32; width: parent.width - 64
        visible: page.checkText !== ""
        topPadding: 8
        wrapMode: Text.Wrap
        text: page.checkText
        color: page.check === "Ok" ? "#34c759" : page.checkText === Tr.t("Tekshirilmoqda…") ? Theme.grey : Theme.danger
        font.family: Theme.font; font.pixelSize: 13
    }
    Text {
        x: 32; width: parent.width - 64
        topPadding: 8
        wrapMode: Text.Wrap
        text: Tr.t("Telegram'da foydalanuvchi nomi tanlashingiz mumkin. Shunda odamlar sizni shu nom orqali topib, raqamingizni bilmasdan yozishi mumkin.")
              + "\n\n" + Tr.t("a–z, 0–9 va pastki chiziq ishlatish mumkin. Eng kami 5 belgi.")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 13
    }
    Text {
        x: 32; width: parent.width - 64
        visible: uname.text.length >= 5
        topPadding: 12
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: Tr.t("Bu havola siz bilan chatni ochadi:") + "<br><font color='" + Theme.accent + "'>https://t.me/" + uname.text + "</font>"
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 13
        MouseArea {
            anchors.fill: parent
            onClicked: {
                clip.text = "https://t.me/" + uname.text
                clip.selectAll()
                clip.copy()
                page.nav.say(Tr.t("Havola nusxalandi"))
            }
        }
    }
}
