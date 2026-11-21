// «Xabar burchaklari» (iOS's «Message Corners»), as Telegram-iOS's BubbleSettingsController: a chat in small over the
// chats' background, its bubbles' corners as picked; «Qo'shni burchaklarni moslash» (iOS's «Adjust Adjacent Corners»:
// small corners where a sender's messages run together, else all big) and the corners' slider (BubbleSettingsRadiusItem,
// no icons; its stops Prefs.cornerStops, 3..17: wider than iOS's 8..16, to be seen). The sample shows each change at once; the chat takes it on
// «O'rnatish» (iOS's «Set»); ‹ leaves it as it was.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Xabar burchaklari")
    action: Tr.t("O'rnatish")
    actionBold: true
    onActed: { Prefs.corners = page.corners; Prefs.mergeCorners = page.merge; nav.pop() }

    readonly property var values: Prefs.cornerStops
    readonly property int stops: values.length
    property int stop: Math.max(0, values.indexOf(Prefs.nearCorner(Prefs.corners)))
    readonly property int corners: values[stop]
    property bool merge: Prefs.mergeCorners
    readonly property string clock: Qt.formatTime(new Date(), "HH:mm")

    // ---- the chat in small ----
    Item {
        width: parent.width; height: Math.max(300, sample.height + 32)
        clip: true
        Wallpaper { anchors.fill: parent }
        ChatSample {
            id: sample
            anchors.bottom: parent.bottom; anchors.bottomMargin: 14
            radius: page.corners
            small: Prefs.bubbleSmall(page.corners, page.merge)
            messages: [{ text: Tr.t("Xayrli tong! 👋"), time: page.clock },
                       { text: Tr.t("Soat necha bo'lganini bilasizmi?"), time: page.clock },
                       { out: true, text: Tr.t("Tokioda hozir tong 😎"), time: page.clock,
                         reply: { name: "Bob Harris", text: Tr.t("Soat necha bo'lganini bilasizmi?") } },
                       { out: true, text: Tr.t("Burchaklarni pastdagi slayder bilan o'zgartiring."), time: page.clock }]
        }
    }

    SettingsGroup {
        Item {              // (a row of its own: the Uzbek words take two lines, SettingsRow's are cut)
            width: parent.width; height: Math.max(46, label.height + 22)
            Text {
                id: label
                x: 16; width: parent.width - 16 - 76
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                text: Tr.t("Qo'shni burchaklarni moslash")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
            }
            Switch {
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                on: page.merge
            }
            MouseArea { anchors.fill: parent; onClicked: page.merge = !page.merge }
        }
        Rectangle { x: 16; width: parent.width - 16; height: 0.5; color: Theme.separator }

        // ---- the slider: nine stops, the corners 8..16 ----
        Item {
            width: parent.width; height: 56
            Item {
                id: track
                x: 30; width: parent.width - 60; height: parent.height
                readonly property real step: width / (page.stops - 1)
                Rectangle {         // the line, the accent up to the knob
                    y: (parent.height - height) / 2
                    width: parent.width; height: 2; radius: 1
                    color: Theme.separator
                }
                Rectangle {
                    y: (parent.height - height) / 2
                    width: knob.x + knob.width / 2; height: 2; radius: 1
                    color: Theme.accent
                }
                Repeater {          // the stops
                    model: page.stops
                    Rectangle {
                        required property int index
                        x: index * track.step - 1; y: (track.height - height) / 2
                        width: 2; height: 10; radius: 1
                        color: index <= page.stop ? Theme.accent : Theme.separator
                    }
                }
                Rectangle {         // the knob's shadow (iOS's: a white knob on a white card)
                    x: knob.x - 1; y: knob.y; width: knob.width + 2; height: knob.height + 2; radius: height / 2
                    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.4 : 0.12)
                }
                Rectangle {
                    id: knob
                    x: page.stop * track.step - width / 2
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
                function pick(mx) {
                    page.stop = Math.min(page.stops - 1, Math.max(0, Math.round((mx - track.x) / track.step)))
                }
                onPressed: (m) => pick(m.x)
                onPositionChanged: (m) => pick(m.x)
            }
        }
    }
    Item { width: 1; height: 20 }
}
