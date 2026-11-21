// A round picture (cut round once, off the UI thread: image://round/ in nullgram.py),
// over the initials on the chat's colour until it comes.
import QtQuick

Item {
    id: av
    property string source: ""          // a local file's path
    property string letters: ""
    property color tint: "#2a9ef1"
    property bool saved: false          // Saved Messages: the bookmark on blue, no picture
    property bool ghost: false          // a deleted account: Telegram-iOS's ghost on grey, no picture
    width: 56; height: 56

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: av.saved ? "#2a9ef1" : av.ghost ? "#b8b8bd" : av.tint
        visible: av.saved || av.ghost || pic.status !== Image.Ready
        Icon {
            visible: av.saved
            anchors.centerIn: parent
            width: av.width * 0.5; height: width
            name: "bookmark"
            color: "white"
        }
        Icon {
            visible: av.ghost
            anchors.centerIn: parent
            width: av.width * 0.55; height: width
            name: "ghost"
            color: "white"
        }
        Text {
            visible: !av.saved && !av.ghost
            anchors.centerIn: parent
            text: av.letters
            color: "white"
            font.family: Theme.font
            font.pixelSize: Math.round(av.width * 0.38)
            font.weight: Font.DemiBold
        }
    }
    Image {
        id: pic
        anchors.fill: parent
        visible: !av.saved && !av.ghost
        source: av.source && !av.saved && !av.ghost ? "image://round/" + av.source : ""
        // in points: Qt asks the provider for these times the pixel ratio (4 on the S10). Times 4 here
        // as well, a 34-point face in a group came at 544 px, sixteen times the pixels it shows
        sourceSize.width: av.width
        sourceSize.height: av.height
        asynchronous: true
        smooth: true
    }
}
