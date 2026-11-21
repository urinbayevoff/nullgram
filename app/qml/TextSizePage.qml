// «Matn o'lchami» (iOS's «Text Size»), as Telegram-iOS's TextSizeSelectionController: a chat in small over the chats'
// background, its words at the size picked; the slider (ThemeSettingsFontSizeItem: a small «A», seven stops, a big «A»)
// and «Tizim matn o'lchamidan foydalanish» (iOS's «Use System Text Size»: on, the slider dimmed at the system's size).
// The sample shows each change at once; the chat's words take it on «O'rnatish» (iOS's «Set»); ‹ leaves them as they were.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Matn o'lchami")
    action: Tr.t("O'rnatish")
    actionBold: true
    onActed: { Prefs.textSize = page.system ? 0 : Prefs.textSizes[page.stop]; nav.pop() }

    readonly property var sizes: Prefs.textSizes
    property bool system: Prefs.textSize === 0
    property int stop: Math.max(0, sizes.indexOf(Prefs.chatSize))
    readonly property int size: system ? Prefs.systemTextSize : sizes[stop]
    readonly property string clock: Qt.formatTime(new Date(), "HH:mm")

    // ---- the chat in small ----
    Item {
        width: parent.width; height: Math.max(300, sample.height + 32)
        clip: true
        Wallpaper { anchors.fill: parent }
        ChatSample {
            id: sample
            anchors.bottom: parent.bottom; anchors.bottomMargin: 14
            size: page.size
            messages: [{ text: Tr.t("Xayrli tong! 👋"), time: page.clock },
                       { text: Tr.t("Soat necha bo'lganini bilasizmi?"), time: page.clock },
                       { out: true, text: Tr.t("Tokioda hozir tong 😎"), time: page.clock,
                         reply: { name: "Bob Harris", text: Tr.t("Soat necha bo'lganini bilasizmi?") } },
                       { text: Tr.t("Matn o'lchamini pastdagi slayder bilan o'zgartiring."), time: page.clock }]
        }
    }

    // ---- the slider: a small «A», the stops, a big «A» ----
    SettingsGroup {
        Item {
            id: slider
            width: parent.width; height: 56
            opacity: page.system ? 0.4 : 1
            Text {
                id: small
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: "A"; color: Theme.text
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                id: big
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                text: "A"; color: Theme.text
                font.family: Theme.font; font.pixelSize: 23
            }
            Item {
                id: track
                x: small.x + small.width + 22
                width: big.x - 22 - x; height: parent.height
                readonly property real step: width / (page.sizes.length - 1)
                Rectangle {         // the line, the accent up to the knob
                    y: (parent.height - height) / 2
                    width: parent.width; height: 2; radius: 1
                    color: Theme.separator
                }
                Rectangle {
                    y: (parent.height - height) / 2
                    width: knob.x + knob.width / 2; height: 2; radius: 1
                    color: page.system ? Theme.grey : Theme.accent
                }
                Repeater {          // the stops
                    model: page.sizes.length
                    Rectangle {
                        required property int index
                        x: index * track.step - 1; y: (track.height - height) / 2
                        width: 2; height: 10; radius: 1
                        color: index <= page.stop && !page.system ? Theme.accent : Theme.separator
                    }
                }
                Rectangle {         // the knob's shadow (iOS's: a white knob on a white card)
                    x: knob.x - 1; y: knob.y; width: knob.width + 2; height: knob.height + 2; radius: height / 2
                    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.4 : 0.12)
                }
                Rectangle {
                    id: knob
                    x: (page.system ? Math.max(0, page.sizes.indexOf(Prefs.systemTextSize)) : page.stop) * track.step - width / 2
                    y: (parent.height - height) / 2
                    width: 28; height: 28; radius: 14
                    color: "#ffffff"
                    border.width: 0.5; border.color: Qt.rgba(0, 0, 0, 0.2)
                    Behavior on x { enabled: !drag.pressed; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                enabled: !page.system
                function pick(mx) {
                    page.stop = Math.min(page.sizes.length - 1, Math.max(0, Math.round((mx - track.x) / track.step)))
                }
                onPressed: (m) => pick(m.x)
                onPositionChanged: (m) => pick(m.x)
            }
        }
    }
    SettingsGroup {         // (a row of its own: the Uzbek words take two lines, SettingsRow's are cut)
        Item {
            width: parent.width; height: Math.max(46, label.height + 22)
            Text {
                id: label
                x: 16; width: parent.width - 16 - 76
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                text: Tr.t("Tizim matn o'lchamidan foydalanish")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
            }
            Switch {
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                on: page.system
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (page.system)        // off: the slider from the system's size
                        page.stop = Math.max(0, page.sizes.indexOf(Prefs.systemTextSize))
                    page.system = !page.system
                }
            }
        }
    }
    Item { width: 1; height: 20 }
}
