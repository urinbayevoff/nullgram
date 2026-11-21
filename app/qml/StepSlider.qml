// A slider of a few stops with a word over each (Telegram-iOS's auto-download «Data Usage»: Low / Medium / High;
// MessageCornersPage's look): `labels`, `value` the stop; moved(v) as it is dragged to another
import QtQuick

Item {
    id: sl
    property var labels: []
    property int value: 0
    property bool enabled2: true
    signal moved(int v)
    readonly property int stops: labels.length
    width: parent ? parent.width : 300; height: 74
    opacity: enabled2 ? 1 : 0.5
    Item {
        id: track
        x: 24; width: parent.width - 48; y: 22; height: parent.height - 22
        readonly property real step: width / Math.max(1, sl.stops - 1)
        Repeater {
            model: sl.labels
            Text {
                required property string modelData
                required property int index
                y: -18
                x: index === 0 ? -8 : index === sl.stops - 1 ? track.width - width + 8 : index * track.step - width / 2
                text: modelData
                color: index === sl.value ? Theme.text : Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
        }
        Rectangle { y: (parent.height - height) / 2; width: parent.width; height: 2; radius: 1; color: Theme.separator }
        Rectangle { y: (parent.height - height) / 2; width: knob.x + knob.width / 2; height: 2; radius: 1; color: Theme.accent }
        Repeater {
            model: sl.stops
            Rectangle {
                required property int index
                x: index * track.step - 1; y: (track.height - height) / 2
                width: 2; height: 8; radius: 1
                color: index <= sl.value ? Theme.accent : Theme.separator
            }
        }
        Rectangle {
            x: knob.x - 1; y: knob.y; width: knob.width + 2; height: knob.height + 2; radius: height / 2
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.4 : 0.12)
        }
        Rectangle {
            id: knob
            x: sl.value * track.step - width / 2
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
        enabled: sl.enabled2
        function pick(mx) {
            const v = Math.min(sl.stops - 1, Math.max(0, Math.round((mx - track.x) / track.step)))
            if (v !== sl.value) {
                sl.value = v
                sl.moved(v)
            }
        }
        onPressed: (m) => pick(m.x)
        onPositionChanged: (m) => pick(m.x)
    }
}
