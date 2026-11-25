// Quvvat tejash, as Telegram-iOS's EnergySavingSettingsScreen: «QUVVAT TEJASH REJIMI» (with «(yoqilgan)» or
// «(o'chiq)» while it depends on the battery) over EnergyUsageBatteryLevelItem — «O'chiq» and «Yoqilgan» at the
// sides (13, grey, 15 down, 18 in), in the middle «15% dan past bo'lsa» (16, 11 down) and the battery drawn after
// it (red at 20 and under, else the switches' green), a slider under them (36 down, 15 in) from 4 («Doim o'chiq»)
// to 96 («Doim yoqilgan»); iOS's words for each under the card. Then «KO'P QUVVAT OLADIGAN JARAYONLAR», each a
// switch with its words under it; while saving they show off, half seen, and a tap says why (iOS's tooltip).
// Ours are the ones Nullgram has: GIFs, stickers, an emoji alone, the effects (iOS's autoplay of videos, its
// «Extended Background Time» and «Preload Media» have nothing here to turn off). The battery: nullgram_app.py's Battery.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Quvvat tejash")

    readonly property int below: Prefs.saveBelow
    readonly property bool never: below <= 4
    readonly property bool always: below >= 96
    readonly property bool locked: Prefs.saving

    SettingsGroup {
        title: Tr.t("Quvvat tejash rejimi") + (page.never || page.always ? ""
               : " (" + (Prefs.saving ? Tr.t("yoqilgan") : Tr.t("o'chiq")) + ")")
        note: page.never ? Tr.t("Batareya kam qolganda ham ko'p quvvat oladigan jarayonlar o'chirilmasin.")
            : page.always ? Tr.t("Batareya qancha bo'lishidan qat'i nazar, ko'p quvvat oladigan jarayonlarni doim o'chirish.")
            : Tr.t("Batareya %1% dan kam qolganda ko'p quvvat oladigan jarayonlarni o'zi o'chirish.").arg(page.below)

        Item {               // EnergyUsageBatteryLevelItem
            id: level
            width: parent.width; height: 88
            Text {
                x: 18; y: 15
                text: Tr.t("O'chiq")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 18; y: 15
                text: Tr.t("Yoqilgan")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            TextMetrics {        // the middle's place measured with «99», so it stays put as the number changes
                id: widest
                font: middle.font
                text: Tr.t("%1% dan kam").arg(99)
            }
            Text {
                id: middle
                x: Math.round((parent.width - (page.never || page.always ? implicitWidth : widest.advanceWidth) - 4 - pile.width) / 2)
                y: 11
                text: page.never ? Tr.t("Doim o'chiq") : page.always ? Tr.t("Doim yoqilgan")
                      : Tr.t("%1% dan kam").arg(page.below)
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
            }
            Item {               // Settings/UsageBatteryFrame: its frame, the charge in it as wide as the level
                id: pile
                x: middle.x + (page.never || page.always ? middle.implicitWidth : widest.advanceWidth) + 4
                anchors.verticalCenter: middle.verticalCenter
                width: 28; height: 13
                Rectangle {
                    width: 25; height: 13; radius: 3.5
                    color: "transparent"
                    border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4); border.width: 1
                    Rectangle {
                        x: 2; y: 2; height: 9; radius: 1.5
                        width: 21 * page.below / 100
                        color: page.below <= 20 ? "#ff3b30" : "#34c759"
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
                Rectangle {
                    x: 26; anchors.verticalCenter: parent.verticalCenter
                    width: 2; height: 4; radius: 1
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.4)
                }
            }
            Item {               // the slider (SliderComponent): 4..96 over its whole width
                id: slider
                x: 15; y: 36
                width: parent.width - 30; height: 44
                readonly property real pos: (page.below - 4) / 92
                Rectangle {
                    id: track
                    x: 14; width: parent.width - 28
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4; radius: 2
                    color: Theme.dark ? "#39393d" : "#e9e9ea"
                    Rectangle {
                        width: slider.pos * parent.width; height: parent.height; radius: 2
                        color: Theme.accent
                    }
                }
                Rectangle {
                    x: track.x + slider.pos * track.width - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 14
                    color: "white"
                    border.color: Qt.rgba(0, 0, 0, 0.06); border.width: 0.5
                    Rectangle {      // its shadow
                        z: -1; anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: -2
                        radius: 14; color: Qt.rgba(0, 0, 0, 0.12)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    function set(mx) {
                        const p = Math.max(0, Math.min(1, (mx - track.x) / track.width))
                        Prefs.saveBelow = Math.round(4 + 92 * p)
                    }
                    onPressed: (e) => set(e.x)
                    onPositionChanged: (e) => set(e.x)
                }
            }
        }
    }

    SettingsGroup {
        title: Tr.t("Ko'p quvvat oladigan jarayonlar")
        Repeater {
            model: [{ art: "gifs", k: "autoGif", t: Tr.t("GIF'larni o'zi o'ynatish"),
                      s: Tr.t("Chatlardagi GIF'lar o'zi o'ynab, takrorlanadi.") },
                    { art: "stickersgreen", k: "loopStickers", t: Tr.t("Stiker animatsiyalari"),
                      s: Tr.t("Jonli stikerlar takror-takror o'ynaydi.") },
                    { art: "emoji", k: "loopEmoji", t: Tr.t("Emoji animatsiyalari"),
                      s: Tr.t("Xabardagi yolg'iz emoji jonli bo'lib o'ynaydi.") },
                    { art: "effects", k: "effects", t: Tr.t("Interfeys effektlari"),
                      s: Tr.t("Xabar menyusi ortidagi xiralik, emoji bosilganda chiqadigan effektlar.") }]
            SettingsRow {
                required property var modelData
                required property int index
                art: modelData.art
                text: modelData.t
                sub: modelData.s
                toggle: true
                on: Prefs[modelData.k] && !page.locked
                dim: page.locked
                last: index === 3
                onClicked: {
                    if (page.locked)
                        tip.show(page.always ? Tr.t("Bu sozlamalarni o'zgartirish uchun quvvat tejashni o'chiring.")
                                 : Tr.t("Bu sozlamalarni o'zgartirish uchun quvvat tejashni o'chiring yoki telefonni quvvatlang."))
                    else
                        Prefs[modelData.k] = !Prefs[modelData.k]
                }
            }
        }
    }

    Rectangle {              // iOS's tooltip (UndoOverlayController): over the foot for 5 s
        id: tip
        parent: page
        z: 50
        x: 12; width: page.width - 24
        y: page.height - height - 96
        height: tipText.height + 26; radius: 14
        color: Qt.rgba(0.11, 0.11, 0.12, 0.92)
        opacity: 0; visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        function show(t) {
            tipText.text = t
            opacity = 1
            tipTimer.restart()
        }
        Timer { id: tipTimer; interval: 5000; onTriggered: tip.opacity = 0 }
        Text {
            id: tipText
            x: 16; y: 13; width: parent.width - 32
            wrapMode: Text.Wrap
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
        MouseArea { anchors.fill: parent; onClicked: tip.opacity = 0 }
    }
}
