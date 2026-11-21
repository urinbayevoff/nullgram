// Ko'rinish › Emoji (ours, Added for OmonullOS, 2026-11): which emoji Nullgram draws — Apple's pictures or the
// system's font — and the Apple set itself, which is not in the package (Apple's pictures): the user downloads it
// here at their own wish (emoji_get.py, ~85 MB from iamcal/emoji-data). The download runs in its own process, so it
// goes on with the page or the app closed; this page reads how far it is twice a second (td.emojiStatus): the
// share, the megabytes, the speed and the time left. Stopped, it goes on from where it was.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Emoji")

    property var st: ({ state: "none", have: false })
    readonly property bool running: st.state === "start" || st.state === "download"
    readonly property bool have: !!st.have
    readonly property real share: st.total > 0 ? st.done / st.total : 0
    // Apple's drawn now: chosen here, or left to omonullOS Settings (Emo.use)
    readonly property bool apple: Emo.use && have

    function look() { st = td.emojiStatus() }
    Component.onCompleted: look()
    Timer { interval: 500; repeat: true; running: page.visible; onTriggered: page.look() }

    function mb(n) { return (n / 1048576).toFixed(1) }
    function clock(s) {
        if (s < 0)
            return ""
        s = Math.max(1, Math.round(s))
        return s >= 60 ? Tr.f("%1 daq %2 s", Math.floor(s / 60), s % 60) : Tr.f("%1 s", s)
    }
    function start() {
        alert.show(Tr.t("Apple emojisini yuklab olish"),
                   Tr.t("Bu rasmlar Apple'niki va Nullgram ichida kelmaydi. Ularni o'z xohishingiz bilan ochiq manbadan (iamcal/emoji-data) yuklab olasiz: taxminan 85 MB."),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Yuklab olish"), bold: true, run: () => {
                       td.emojiStart(); Prefs.emojiSet = "apple"; page.st = Object.assign({}, page.st, { state: "start" }) } }])
    }
    function remove() {
        alert.show("", Tr.t("Apple emoji to'plami o'chirilsinmi? Nullgram tizimdagi emojiga qaytadi."),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () => {
                       td.emojiRemove(); if (Prefs.emojiSet === "apple") Prefs.emojiSet = ""; page.look() } }])
    }

    SettingsGroup {
        title: Tr.t("Emoji ko'rinishi")
        note: page.have ? "" : Tr.t("Apple emojisini tanlash uchun avval uni pastda yuklab oling.")
        SettingsRow {
            text: "Apple"; chevron: false; tick: page.apple; dim: !page.have
            onClicked: page.have ? Prefs.emojiSet = "apple" : page.start()
        }
        SettingsRow {
            text: Tr.t("Tizim"); chevron: false; tick: !page.apple; last: true
            onClicked: Prefs.emojiSet = "system"
        }
    }

    SettingsGroup {
        title: Tr.t("Apple emoji to'plami")
        note: page.running ? Tr.t("Yuklash fonda davom etadi: sahifani yoki Nullgram'ni yopsangiz ham to'xtamaydi.")
            : page.st.state === "error" ? (page.st.error === "space" ? Tr.t("Telefonda joy yetmadi: taxminan 140 MB bo'sh joy kerak.")
                                                                      : Tr.t("Internet bilan muammo bo'ldi. Yuklanganlari saqlandi — qayta urinib ko'ring."))
            : page.have ? Tr.t("Rasmlar Apple'niki, ochiq manbadan (iamcal/emoji-data) o'zingiz yuklab olgansiz.")
            : Tr.t("Rasmlar Apple'niki va Nullgram ichida kelmaydi: xohlasangiz, ochiq manbadan (iamcal/emoji-data) o'zingiz yuklab olasiz. Taxminan 85 MB, 3 783 ta rasm.")

        // while it comes down: the share, a bar, and how much / how fast / how long
        Item {
            visible: page.running || ((page.st.state === "stopped" || page.st.state === "error") && page.st.done > 0 && !page.have)
            width: parent.width; height: visible ? 82 : 0
            Text {
                x: 16; y: 12
                text: page.running ? (page.st.state === "start" ? Tr.t("Boshlanmoqda…") : Tr.f("Yuklanmoqda… %1%", Math.floor(page.share * 100)))
                                   : Tr.f("To'xtatilgan: %1%", Math.floor(page.share * 100))
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16; y: 14
                visible: page.running && page.st.left > 0
                text: Tr.f("~%1 qoldi", page.clock(page.st.left))
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
            Rectangle {
                x: 16; y: 42; width: parent.width - 32; height: 6; radius: 3
                color: Theme.highlight
                Rectangle {
                    width: Math.max(parent.height, parent.width * page.share); height: parent.height; radius: 3
                    color: page.running ? Theme.accent : Theme.grey
                    Behavior on width { NumberAnimation { duration: 450 } }
                }
            }
            Text {
                x: 16; y: 56
                text: Tr.f("%1 / %2 rasm", page.st.done || 0, page.st.total || "…")
                      + " · " + page.mb(page.st.bytes || 0) + (page.st.est > 0 ? " / ~" + page.mb(page.st.est) : "") + " MB"
                      + (page.running && page.st.speed > 0 ? " · " + Math.round(page.st.speed / 1024) + " KB/s" : "")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator }
        }
        SettingsRow {
            visible: page.running
            text: Tr.t("To'xtatish"); chevron: false; danger: true; last: true
            onClicked: { td.emojiStop(); page.st = Object.assign({}, page.st, { state: "stopped" }) }
        }
        SettingsRow {
            visible: !page.running && !page.have
            text: page.st.done > 0 && page.st.part ? (page.st.state === "error" ? Tr.t("Qayta urinish") : Tr.t("Davom ettirish"))
                                                  : Tr.t("Apple emojisini yuklab olish")
            chevron: false; accent: true; last: !(page.st.done > 0 && page.st.part)
            onClicked: page.st.done > 0 && page.st.part ? td.emojiStart() : page.start()
        }
        SettingsRow {
            visible: !page.running && (page.have || (page.st.done > 0 && page.st.part))
            text: page.have ? Tr.t("To'plamni o'chirish") : Tr.t("Yuklanganini o'chirish")
            chevron: false; danger: true; last: true
            onClicked: page.remove()
        }
    }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
