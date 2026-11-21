// A page opened from the settings: ‹ and its title over a grouped list (iOS's grouped background).
import QtQuick

Page {
    id: sub
    property string title: ""
    default property alias content: column.data
    readonly property alias flick: flick
    property real clear: 0              // 0..1: the bar gone, its ‹ white (over a picture under it)
    property string action: ""          // a word on the bar's right (iOS's «Edit», «Done»): tapped, acted()
    property bool actionOn: true        // (false: grey, not tappable)
    property bool actionBold: false     // (iOS: «Done» bold, «Edit» not)
    property string actionIcon: ""      // or an icon there (Icon's name): tapped, acted() too
    property var guard: null            // ‹ tapped: a function that may hold the page (true: it did, e.g. it asks first)
    property bool backable: true        // false: no ‹ (the app's first page, nothing under it)
    signal acted()
    color: Theme.grouped

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: bar.height
        contentHeight: column.height + 40 + safe.bottom     // (the end clear of ztMETRO's nav line)
        Column {
            id: column
            y: 16
            width: parent.width
            spacing: 22
        }
    }
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: Qt.rgba(Theme.grouped.r, Theme.grouped.g, Theme.grouped.b, 1 - sub.clear)
        Text {
            visible: sub.backable
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Qt.rgba(Theme.accent.r + (1 - Theme.accent.r) * sub.clear, Theme.accent.g + (1 - Theme.accent.g) * sub.clear,
                           Theme.accent.b + (1 - Theme.accent.b) * sub.clear, 1)
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea { id: backHit; enabled: sub.backable; width: 72; height: parent.height; onClicked: if (!(sub.guard && sub.guard())) sub.nav.pop() }
        Text {
            id: actText
            visible: sub.action !== ""
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: sub.action
            color: !sub.actionOn ? Theme.grey
                 : Qt.rgba(Theme.accent.r + (1 - Theme.accent.r) * sub.clear, Theme.accent.g + (1 - Theme.accent.g) * sub.clear,
                           Theme.accent.b + (1 - Theme.accent.b) * sub.clear, 1)
            opacity: actHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 17; font.weight: sub.actionBold ? Font.DemiBold : Font.Normal
        }
        Icon {
            visible: sub.actionIcon !== ""
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            name: sub.actionIcon
            color: Theme.accent
            opacity: actHit.pressed ? 0.4 : 1
        }
        MouseArea {
            id: actHit
            visible: actText.visible || sub.actionIcon !== ""
            enabled: sub.actionOn
            anchors.right: parent.right
            width: (actText.visible ? actText.width : 24) + 32; height: parent.height
            onClicked: sub.acted()
        }
        Text {
            anchors.centerIn: parent
            opacity: 1 - sub.clear
            text: sub.title
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
    }
}
