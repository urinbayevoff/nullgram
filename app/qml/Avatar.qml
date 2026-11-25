// A round picture (cut round once, off the UI thread: image://round/ in nullgram_app.py),
// over the chat's colour until it comes (the initials on it when there is none).
import QtQuick
import QtQuick.Window
import "Icons.js" as Icons

Rectangle {
    id: av
    property string source: ""          // a local file's path
    property string letters: ""
    property color tint: "#2a9ef1"
    property bool saved: false          // Saved Messages: the bookmark on blue, no picture
    property bool ghost: false          // a deleted account: Telegram-iOS's ghost on grey, no picture
    width: 56; height: 56
    radius: width / 2
    color: saved ? "#2a9ef1" : ghost ? "#b8b8bd" : pic.status !== Image.Ready ? tint : "transparent"

    // the initials only for one with no picture (or one that failed): a Text made for every face in a flick
    // through a group, its font set up, cost more than the rest of the avatar; a picture coming shows the
    // tint until it is here (from nullgram_app.py's kept pictures: at once, mostly)
    Loader {
        anchors.centerIn: parent
        readonly property string letters: av.letters
        readonly property real side: av.width
        source: !av.saved && !av.ghost && (av.source === "" || pic.status === Image.Error) ? "AvatarLetters.qml" : ""
    }
    Image {
        id: pic
        anchors.centerIn: parent
        width: av.saved ? av.width * 0.5 : av.ghost ? av.width * 0.55 : av.width
        height: width
        source: av.saved ? Icons.uri("bookmark", Qt.rgba(1, 1, 1, 1))
              : av.ghost ? Icons.uri("ghost", Qt.rgba(1, 1, 1, 1))
              : av.source ? "image://round/" + av.source : ""
        // in points: Qt asks the provider for these times the pixel ratio (4 on the S10). Times 4 here
        // as well, a 34-point face in a group came at 544 px, sixteen times the pixels it shows
        sourceSize: av.saved || av.ghost
                  ? Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                  : Qt.size(av.width, av.height)
        asynchronous: !av.saved && !av.ghost
        smooth: true
    }
}
