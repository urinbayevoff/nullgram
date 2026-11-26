// One account in the accounts' lists (0.9.7): Sozlamalar's group under the profile (Telegram-iOS's
// SettingsController accounts) and the Sozlamalar tab's held menu (AccountsSheet, Android's
// MainTabsActivity.openAccountSelector): its letters on its colour, its name, its unread chats on red
// (none known: none), the shown one ticked. `add`: «Hisob qo'shish» instead, a + in the accent.
import QtQuick

Item {
    id: row
    property var account: null          // AccountList's: { slot, name, username, userId, premium, active, unread }
    property bool add: false
    property bool last: false
    property bool tick: false           // the shown one's ✓ (the menu; Sozlamalar has it as the profile above)
    signal clicked()
    width: parent ? parent.width : 300
    height: 46

    Rectangle {
        anchors.fill: parent
        color: Theme.highlight
        visible: hit.pressed
    }
    Avatar {
        visible: !row.add
        x: 14; anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30
        letters: row.account ? store.letters(row.account.name || "?") : ""
        tint: row.account ? store.tints[Math.abs(row.account.userId) % store.tints.length] : Theme.accent
    }
    Icon {
        visible: row.add
        x: 17; anchors.verticalCenter: parent.verticalCenter
        width: 24; height: 24
        name: "plus"
        color: Theme.accent
    }
    Text {
        id: label
        x: 56
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (badge.visible ? badge.width + 24 : 0) - (row.tick ? 40 : 16)
        elide: Text.ElideRight
        text: row.add ? Tr.t("Hisob qo'shish") : row.account ? (row.account.name || Tr.t("Hisob")) : ""
        color: row.add ? Theme.accent : Theme.text
        font.family: Theme.font; font.pixelSize: 16
    }
    Rectangle {
        id: badge
        readonly property int n: row.account && !row.account.active ? row.account.unread : 0
        visible: n > 0
        anchors.right: parent.right; anchors.rightMargin: row.tick ? 40 : 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(20, count.implicitWidth + 10); height: 20; radius: 10
        // (not kept on, «Barcha hisoblardan» off: the last count known, grey)
        color: row.account && row.account.watched === false ? Theme.mutedBadge : Theme.danger
        Text {
            id: count
            anchors.centerIn: parent
            text: badge.n > 999 ? Math.floor(badge.n / 1000) + "K" : String(badge.n)
            color: "white"
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }
    Icon {
        visible: row.tick && row.account && row.account.active
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20
        name: "check"
        color: Theme.accent
    }
    Rectangle {
        visible: !row.last
        x: 56; y: parent.height - height
        width: parent.width - x; height: 0.5
        color: Theme.separator
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        onClicked: row.clicked()
    }
}
