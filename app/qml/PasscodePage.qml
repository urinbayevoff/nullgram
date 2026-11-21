// «Kod-parol» (Telegram-iOS's PasscodeOptionsController): off — a lock, what it does, «Kod-parolni yoqish» (the pad
// twice); on — asked for first, then «Kod-parolni o'chirish», «Kod-parolni o'zgartirish», «Avtomatik qulflash». It is
// this app's alone (Prefs.passcode, kept in its settings file); Main locks at the start and after the minutes away.
import QtQuick

SubPage {
    id: page
    property string doing: ""           // the pad over the window: "in" (asked on the way in), "set", "change"
    title: Tr.t("Kod-parol")
    Component.onCompleted: if (Prefs.passcode) doing = "in"

    function lockName(m) {
        return m === 0 ? Tr.t("Faqat ochilganda") : m < 60 ? Tr.f("%1 daqiqadan keyin", m) : Tr.f("%1 soatdan keyin", m / 60)
    }
    function openLock() {
        const p = nav.push(Qt.createComponent("ChoicePage.qml"), {
            heading: Tr.t("Avtomatik qulflash"), value: Prefs.autoLock,
            choices: [0, 1, 5, 60, 300].map((m) => ({ t: page.lockName(m), v: m })),
            note: Tr.t("Ilova shuncha vaqt ekranda bo'lmasa, qaytganda kod-parol so'raladi.") })
        if (p)
            p.chosen.connect((v) => Prefs.autoLock = v)
    }

    Item {              // off: the lock, what it is, the button
        visible: !Prefs.passcode
        width: parent.width; height: offCol.height + 30
        Column {
            id: offCol
            width: parent.width
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🔐"
                font.pixelSize: 84
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Kod-parol")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
            }
            Text {
                x: 32; width: parent.width - 64
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.t("Kod-parol o'rnatilsa, ilova ochilganda va bir muddat ishlatilmaganda u so'raladi.")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
            Item { width: 1; height: 8 }
            Rectangle {
                x: 24; width: parent.width - 48; height: 50
                radius: 12
                color: onHit.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Kod-parolni yoqish")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea { id: onHit; anchors.fill: parent; onClicked: page.doing = "set" }
            }
            Text {
                x: 32; width: parent.width - 64
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.t("Diqqat: kod-parolni unutsangiz, Nullgram sozlamalarini tozalash va qayta kirish kerak bo'ladi.")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
        }
    }
    SettingsGroup {
        visible: !!Prefs.passcode
        SettingsRow { text: Tr.t("Kod-parolni o'chirish"); accent: true; chevron: false; onClicked: Prefs.passcode = "" }
        SettingsRow { text: Tr.t("Kod-parolni o'zgartirish"); accent: true; chevron: false; last: true; onClicked: page.doing = "change" }
    }
    SettingsGroup {
        visible: !!Prefs.passcode
        note: Tr.t("Ilova shuncha vaqt ekranda bo'lmasa, qaytganda kod-parol so'raladi.")
        SettingsRow { text: Tr.t("Avtomatik qulflash"); value: page.lockName(Prefs.autoLock); last: true; onClicked: page.openLock() }
    }

    PasscodePad {
        id: pad
        parent: page.nav || page
        z: 900
        visible: page.doing !== "" && page.visible
        mode: page.doing === "in" ? "check" : "set"
        cancel: true
        onPassed: page.doing = ""
        onCancelled: {
            const leave = page.doing === "in"
            page.doing = ""
            if (leave)
                page.nav.pop()
        }
    }
}
