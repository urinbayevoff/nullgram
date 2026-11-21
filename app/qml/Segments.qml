// iOS's segmented control as a pill: `items` the words, `index` the chosen; picked(i) on a tap
import QtQuick

Rectangle {
    id: seg
    property var items: []
    property int index: 0
    signal picked(int i)
    readonly property real cell: (width - 4) / Math.max(1, items.length)
    height: 32; radius: 16
    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)
    Rectangle {
        x: 2 + seg.index * seg.cell; y: 2
        width: seg.cell; height: parent.height - 4; radius: height / 2
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : "white"
        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }
    Row {
        x: 2
        Repeater {
            model: seg.items
            Text {
                required property string modelData
                required property int index
                width: seg.cell; height: seg.height
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: modelData
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                MouseArea { anchors.fill: parent; onClicked: { seg.index = parent.index; seg.picked(parent.index) } }
            }
        }
    }
}
