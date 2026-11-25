// One picture of an album's mosaic (ChatPage): its message's photo or video in its place, its
// outer corners round as the bubble's, the inner ones nearly square (Telegram-iOS). It answers to
// what ChatPage asks of a message's picture (tapMedia, view, openMedia, the viewer's flight).
import QtQuick

Item {
    id: tile
    property var msgId: 0
    property var cell: null             // ChatPage.cellOf: its row's media, copied
    property string corner: "14"        // Pic's radii: "tl,tr,br,bl"
    property bool live: true            // on the screen (a spoiler's dust moves only then)
    property bool inSight: true         // near or on screen (eligible to upgrade from low-res to full)
    property bool lowRes: false         // list is moving: start at 1/4 size, upgrade once settled
    property bool readyInit: false
    property bool startedFast: false
    property bool sharp: false
    readonly property bool wantSharp: !lowRes && inSight
    onWantSharpChanged: if (readyInit && wantSharp) sharp = true
    Component.onCompleted: {
        if (lowRes) {
            startedFast = true
            sharp = false
        } else {
            sharp = true
        }
        readyInit = true
    }
    signal unveiled()                   // its spoiler blown off (the page keeps it off)
    // «Tanlash»: a mark in its corner, each picture picked alone (Telegram-iOS)
    property bool marks: false          // the mark made (while picking, and as it goes)
    property bool picking: false        // it shows
    property bool picked: false

    readonly property string picKind: cell ? cell.picKind : ""
    readonly property string rowKind: ""
    readonly property bool media: true
    readonly property string pic: cell ? cell.pic : ""
    readonly property string mini: cell ? cell.mini : ""
    readonly property real got: cell ? cell.got : -1
    readonly property string path: cell ? cell.path : ""
    readonly property bool sending: cell ? cell.sending : false
    readonly property int dur: cell ? cell.dur : 0
    readonly property real fileSize: cell ? cell.fileSize : 0
    readonly property bool veiled: cell ? !!cell.veiled : false        // a spoiler, until tapped
    function blow(x, y) {
        if (veil.item)
            veil.item.blow(x === undefined ? width / 2 : x, y === undefined ? height / 2 : y)
    }
    readonly property real aspect: cell ? cell.picH / Math.max(cell.picW, 1) : 1     // its own shape, full screen
    readonly property real pw: width
    readonly property Item picFace: tile
    readonly property Item face: tile

    Image {
        anchors.fill: parent
        visible: tile.mini !== "" && full.status !== Image.Ready && low.status !== Image.Ready
        asynchronous: true
        sourceSize: Qt.size(12, 12 * tile.height / Math.max(tile.width, 1))
        source: tile.mini ? "image://pic/" + tile.corner + "/" + Math.round(tile.width) + "/mini/" + tile.mini : ""
        smooth: true
    }
    Image {
        id: low
        anchors.fill: parent
        visible: tile.startedFast && full.status !== Image.Ready
        asynchronous: true
        sourceSize: Qt.size(Math.max(16, Math.round(tile.width / 4)), Math.max(16, Math.round(tile.height / 4)))
        source: tile.readyInit && tile.startedFast && (!tile.sharp || status === Image.Ready) && full.status !== Image.Ready && tile.pic
                ? "image://pic/" + tile.corner + "/" + Math.round(tile.width) + "/" + tile.pic : ""
        opacity: status === Image.Ready ? 1 : 0
        smooth: true
    }
    Image {
        id: full
        anchors.fill: parent
        asynchronous: true
        sourceSize: Qt.size(Math.round(tile.width), Math.round(tile.height))
        source: tile.readyInit && tile.sharp && tile.pic
                ? "image://pic/" + tile.corner + "/" + Math.round(tile.width) + "/" + tile.pic : ""
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { enabled: low.status !== Image.Ready; OpacityAnimator { duration: 150 } }
    }
    Loader {            // a spoiler: blurred under its dust until tapped, each picture its own
        id: veil
        anchors.fill: parent
        active: tile.veiled
        sourceComponent: Veil {
            corner: tile.corner
            mini: tile.mini
            pic: tile.pic
            live: tile.live
            onGone: tile.unveiled()
        }
    }
    // a video's: play over it (the ring while it comes) and its length; made only for one (an album of
    // photos made a hidden circle, icon, ring and text in every picture)
    Loader {
        id: videoBits
        anchors.fill: parent
        active: tile.picKind === "video" || tile.got >= 0
        sourceComponent: Item {
            Rectangle {
                anchors.centerIn: parent
                readonly property real d: Math.min(44, tile.width - 12, tile.height - 12)
                width: d; height: d; radius: d / 2
                color: Qt.rgba(0, 0, 0, 0.45)
                Icon {
                    visible: tile.got < 0
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1.5
                    width: parent.d * 0.5; height: width
                    name: "play"
                    color: "white"
                }
                Ring {
                    visible: tile.got >= 0
                    anchors.fill: parent
                    value: tile.got
                }
            }
            Rectangle {         // its length
                visible: tile.picKind === "video" && tile.width > 60
                x: 6; y: 6
                width: len.implicitWidth + 12; height: 20; radius: 10
                color: Qt.rgba(0, 0, 0, 0.45)
                Text {
                    id: len
                    anchors.centerIn: parent
                    text: Math.floor(tile.dur / 60) + ":" + String(tile.dur % 60).padStart(2, "0")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }
    Loader {            // «Tanlash»'s mark, in the top right corner (iOS: 28 pt, 2 in)
        id: mark
        active: tile.marks
        readonly property real side: tile.width <= 60 ? 22 : 26
        x: tile.width - side - 4; y: 4
        sourceComponent: Check {
            width: mark.side; height: mark.side
            on: tile.picking
            checked: tile.picked
        }
    }
}
