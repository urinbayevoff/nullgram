// The mini player as Telegram-iOS 26 has it (the owner's iPad, #26403/#26408: under a chat's header, and
// in the chat list under the folder chips, in their capsule): play/pause on the left, what plays in the
// middle (the sender or the song, under it «Ovozli xabar» or the performer; a tap goes to it), a voice
// note's speed (1X → 1.5X → 2X), ✕; how far it is, a thin line along the bottom. 44 pt while the
// Player has something, else 0.
import QtQuick

Item {
    id: mini
    property var player
    signal opened()                      // what plays was tapped
    readonly property bool on: !!player && player.msgId !== 0
    readonly property bool voice: on && player.kind === "voice"
    width: parent ? parent.width : 300
    height: on ? 44 : 0
    visible: on
    clip: true

    Item {          // play / pause
        width: 44; height: 44
        Icon {
            anchors.centerIn: parent
            width: 18; height: 18
            name: mini.on && mini.player.playing ? "pause" : "play"
            color: Theme.text
        }
        MouseArea { anchors.fill: parent; onClicked: mini.player.toggle() }
    }
    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * 92
        opacity: openHit.pressed ? 0.5 : 1
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: mini.on ? mini.player.title : ""
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            visible: text !== ""
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: mini.on ? mini.player.sub : ""
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 11
        }
    }
    MouseArea { id: openHit; x: 44; width: parent.width - 132; height: parent.height; onClicked: mini.opened() }
    Rectangle {     // a voice note's speed: a tap, the next one (iOS: 1X in a small frame)
        visible: mini.voice
        anchors.right: parent.right; anchors.rightMargin: 46
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(26, rateText.implicitWidth + 8); height: 18; radius: 4
        color: "transparent"
        border.color: rateText.color; border.width: 1.2
        opacity: rateHit.pressed ? 0.5 : 1
        Text {
            id: rateText
            anchors.centerIn: parent
            text: mini.on ? mini.player.rateText(mini.player.rate).toUpperCase() : "1X"
            color: mini.on && mini.player.rate !== 1 ? Theme.accent : Theme.grey
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
        }
        MouseArea { id: rateHit; anchors.fill: parent; anchors.margins: -10; onClicked: mini.player.nextRate() }
    }
    Item {          // ✕: stopped and gone
        anchors.right: parent.right
        width: 44; height: 44
        Icon {
            anchors.centerIn: parent
            width: 16; height: 16
            name: "cross"
            color: Theme.text
        }
        MouseArea { anchors.fill: parent; onClicked: mini.player.stop() }
    }
    Rectangle {     // how far
        anchors.bottom: parent.bottom
        height: 1.5
        width: mini.on && mini.player.duration > 0 ? parent.width * Math.min(1, mini.player.position / mini.player.duration) : 0
        color: Theme.text
        opacity: 0.8
    }
}
