// A question over the page, as Telegram-iOS's textAlertController (TextAlertController): 270 wide, corners 14,
// the title semibold 17 and the words 13 under it, then its answers — two side by side (the second the one
// that acts), more one under another (`vertical`). An answer is { t, red, bold, run }. Faded in from 1.1 of
// its size. Put over a page: `parent: page; anchors.fill: parent`.
import QtQuick

Item {
    id: alert
    z: 40
    property bool open: false
    property string title: ""
    property string text: ""
    property var answers: []
    property bool vertical: false
    readonly property bool side: !vertical && answers.length === 2
    function show(title, text, answers, vertical) {
        alert.title = title || ""
        alert.text = text || ""
        alert.answers = answers
        alert.vertical = !!vertical
        open = true
    }
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4) }
    MouseArea { anchors.fill: parent; onClicked: alert.open = false }
    Rectangle {
        anchors.centerIn: parent
        scale: alert.open ? 1 : 1.1
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        width: 270; height: words.y + words.height + 20 + (alert.side ? 44 : alert.answers.length * 44)
        radius: 14
        color: Theme.menu
        MouseArea { anchors.fill: parent }
        Column {
            id: words
            x: 16; y: 20; width: parent.width - 32
            spacing: 4
            Text {
                visible: alert.title !== ""
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: alert.title
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                visible: alert.text !== ""
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: alert.text
                color: Theme.text
                font.family: Theme.font; font.pixelSize: alert.title !== "" ? 13 : 15
            }
        }
        Repeater {
            model: alert.answers
            Rectangle {
                required property var modelData
                required property int index
                x: alert.side ? index * parent.width / 2 : 0
                y: words.y + words.height + 20 + (alert.side ? 0 : index * 44)
                width: alert.side ? parent.width / 2 : parent.width; height: 44
                color: hit.pressed ? Theme.highlight : "transparent"
                Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                Rectangle { visible: alert.side && parent.index === 1; width: 0.5; height: parent.height; color: Theme.separator }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 13      // (as UIKit's alert shrinks a long one)
                    text: parent.modelData.t
                    color: parent.modelData.red ? Theme.danger : Theme.accent
                    font.family: Theme.font; font.pixelSize: 17
                    font.weight: parent.modelData.bold ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    onClicked: {
                        alert.open = false
                        if (parent.modelData.run)
                            parent.modelData.run()
                    }
                }
            }
        }
    }
}
