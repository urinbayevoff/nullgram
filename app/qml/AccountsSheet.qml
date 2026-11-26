// The Sozlamalar tab held (0.9.7; Telegram Android's MainTabsActivity.openAccountSelector, iOS's held Settings
// tab): a small menu over the tab bar's right end — «Hisob qo'shish» (while fewer than 4 are signed in; past the
// limit Store says why), then the accounts, the shown one ticked, the others' unread chats on red. A tap on one
// switches to it (Store.switchAccount); anywhere else closes it.
import QtQuick
import QtQuick.Effects

Item {
    id: sheet
    property bool open: false
    property real floor: 0              // the tab bar's top, from the bottom (HomePage)
    property var nav: null
    property var alert: null
    anchors.fill: parent
    visible: open || card.opacity > 0
    z: 50

    Rectangle {             // the page dimmed under it (Android's ItemOptions scrim)
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.4 : 0.18)
        opacity: card.opacity
    }
    MouseArea {
        anchors.fill: parent
        enabled: sheet.open
        onClicked: sheet.open = false
    }
    Rectangle {
        id: card
        width: 250
        x: parent.width - width - 16
        y: parent.height - sheet.floor - height - 8
        height: rows.height
        radius: 16
        color: Theme.menu
        border.color: Theme.glassEdge; border.width: 0.5
        clip: true
        opacity: sheet.open ? 1 : 0
        scale: sheet.open ? 1 : 0.9
        transformOrigin: Item.BottomRight
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        RectangularShadow {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            blur: 24; offset.y: 4
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.15)
        }
        Column {
            id: rows
            width: parent.width
            AccountRow {
                add: true
                visible: accounts.count < 4
                last: false
                onClicked: { sheet.open = false; store.addAccount(sheet.nav, sheet.alert) }
            }
            Repeater {
                model: accounts.list
                AccountRow {
                    required property var modelData
                    required property int index
                    account: modelData
                    tick: true
                    last: index === accounts.count - 1
                    onClicked: { sheet.open = false; store.switchAccount(modelData.slot) }
                }
            }
        }
    }
}
