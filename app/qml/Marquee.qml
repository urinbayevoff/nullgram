// One line that slides to the left when it is longer than its room, round and round with a gap, a pause at
// its start each time (Telegram-iOS's profile song row under the buttons). Short: it stands, as wide as it is.
import QtQuick

Item {
    id: box
    property string text: ""
    property int textFormat: Text.PlainText
    property color color: Theme.text
    property alias font: one.font
    readonly property real textWidth: one.implicitWidth
    readonly property bool long: one.implicitWidth > width + 0.5
    readonly property real gap: 40
    implicitWidth: one.implicitWidth
    implicitHeight: one.implicitHeight
    clip: long

    Row {
        id: row
        spacing: box.gap
        Text { id: one; text: box.text; textFormat: box.textFormat; color: box.color }
        Text { visible: box.long; text: box.text; textFormat: box.textFormat; color: box.color; font: one.font }
    }
    SequentialAnimation {
        running: box.long && box.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running) row.x = 0
        PropertyAction { target: row; property: "x"; value: 0 }
        PauseAnimation { duration: 1600 }
        NumberAnimation {
            target: row; property: "x"
            from: 0; to: -(one.implicitWidth + box.gap)
            duration: (one.implicitWidth + box.gap) * 28        // ~36 pt a second
        }
    }
}
