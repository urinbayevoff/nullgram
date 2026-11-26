// Horizontal filter chip bar under the global search box (Telegram-iOS's ChatListSearchFilters):
// Chats, Media, Links, Files, Music, Voice. Scrolls to keep the active chip in view.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property var tabs: []
    property string current: "chats"
    signal picked(string key)

    height: 42

    onCurrentChanged: {
        const i = tabs.findIndex((t) => t.key === current)
        if (i >= 0)
            bar.positionViewAtIndex(i, ListView.Contain)
    }

    ListView {
        id: bar
        anchors.fill: parent
        orientation: ListView.Horizontal
        leftMargin: 14
        rightMargin: 14
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.tabs

        delegate: Rectangle {
            id: chip
            required property var modelData
            required property int index
            readonly property bool on: root.current === modelData.key
            y: Math.round((bar.height - height) / 2)
            width: label.implicitWidth + 24
            height: 30
            radius: 15
            color: on ? Theme.accent
                 : tap.pressed ? Theme.highlight
                 : (Theme.dark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0.46, 0.46, 0.5, 0.12))

            Text {
                id: label
                anchors.centerIn: parent
                text: chip.modelData.name
                color: chip.on ? Theme.badgeText : Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: chip.on ? Font.DemiBold : Font.Normal
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                onClicked: root.picked(chip.modelData.key)
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 0.5
        color: Theme.separator
    }
}
