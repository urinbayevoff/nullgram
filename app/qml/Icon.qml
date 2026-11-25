// Our own line-art icons, drawn as paths on a 24-point grid (no icon font: the
// emoji ones come in colour and in another style): person, chats, settings, search, and the
// media ones (play, pause, down, cross, mic, clip, expand). Those in `lines` are strokes, not fills.
import QtQuick
import QtQuick.Window
import "Icons.js" as Icons

Image {
    id: icon
    property string name: ""
    property color color: Theme.text
    width: 24; height: 24

    // an SVG picture (Icons.uri: image://svg, drawn at sourceSize — a data: URL was read at 24 px and stretched), made only once it shows: a list's rows have a dozen icons, most of
    // them hidden; drawn as shapes, each was six objects and a draw call of its own
    // (once shown it stays: `visible` is false too while the page it is on is hidden under another, and every
    // icon of the page let its picture go and asked for it again as the page hid and showed)
    property bool shown: false
    onVisibleChanged: if (visible) shown = true
    Component.onCompleted: if (visible) shown = true
    source: (shown || visible) && name !== "" ? Icons.uri(name, color) : ""
    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
    smooth: true
    // (not asynchronous: the svg provider is Python's (nullgram_app.py Svg), and asked from Qt's picture thread
    // it waits for Python's lock -- the desk hung that way, 1 run in 2; once shown, an icon keeps its picture)
}
