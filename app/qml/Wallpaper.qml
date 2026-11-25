// A chat's background, as Telegram-iOS's WallpaperBackgroundNode: its fill at once (a few pixels, drawn
// large), then the whole of it (pattern or picture) at the size it is shown, drawn off the UI thread by
// nullgram_app.py's Wallpaper provider. `spec`: "<fill>;<intensity>;<kind>;<path>" (Store.wallSpec), the
// app's own by default; `radius`: its corners rounded (the grids' tiles).
import QtQuick

Item {
    id: wall
    property string spec: Theme.wall
    property real radius: 0
    readonly property var parts: spec.split(";")
    readonly property bool ready: whole.status === Image.Ready
    readonly property string round: radius > 0 && width > 0 ? "r" + (radius / width).toFixed(4) + "|" : ""

    Image {                 // the fill alone: small, at once
        anchors.fill: parent
        source: "image://wallpaper/" + encodeURIComponent(wall.round + wall.parts[0] + ";" + (wall.parts[1] || 0) + ";;")
        sourceSize: wall.radius > 0 ? Qt.size(Math.ceil(wall.width), Math.ceil(wall.height)) : Qt.size(30, 63)
        asynchronous: true
        smooth: true
        visible: !wall.ready
    }
    Image {                 // all of it, when drawn (the last ones kept: a page coming back has it at once)
        id: whole
        anchors.fill: parent
        source: wall.width > 0 && wall.height > 0 ? "image://wallpaper/" + encodeURIComponent(wall.round + wall.spec) : ""
        sourceSize: Qt.size(Math.ceil(wall.width), Math.ceil(wall.height))
        asynchronous: true
        cache: false
        smooth: true
    }
}
