// Three-column photo/video grid for global search Media tab: virtualized GridView backed by a
// ListModel so appended pagination chunks do not destroy or flicker existing thumbnails.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property var store
    property var model
    property var messages: []
    property bool loading: false
    property bool more: false
    property real bottomPad: 12
    property var unveiled: ({})
    property int unveiledTick: 0

    signal picked(var tile, var msg)
    signal needMore()
    signal scrolled()

    readonly property alias grid: grid

    function toTop() {
        grid.positionViewAtBeginning()
    }

    function cellFile(m) {
        if (!m || !m.content)
            return null
        const c = m.content
        if (c["@type"] === "messagePhoto") {
            const sizes = (c.photo && c.photo.sizes) || []
            for (const z of sizes)
                if (z.width >= 240)
                    return z.photo
            return sizes.length ? sizes[sizes.length - 1].photo : null
        }
        const v = c.video
        return v && v.thumbnail && v.thumbnail.format && v.thumbnail.format["@type"] === "thumbnailFormatJpeg"
             ? v.thumbnail.file : null
    }

    function clock(s) {
        const sec = Math.max(0, Math.floor(s || 0))
        return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0")
    }

    GridView {
        id: grid
        anchors.fill: parent
        clip: true
        readonly property real gap: 1.5
        cellWidth: width > 0 ? width / 3 : 120
        cellHeight: cellWidth
        bottomMargin: root.bottomPad
        model: root.model
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        onMovementStarted: root.scrolled()
        onContentYChanged: {
            if (!root.visible || root.loading || !root.more || count === 0)
                return
            if (contentY > 0 && contentY + height >= contentHeight - cellHeight * 2)
                root.needMore()
        }

        delegate: Item {
            id: cell
            required property int index
            required property string msgKey
            required property bool isVideo
            required property int duration
            required property bool hasSpoiler
            required property string mini

            width: grid.cellWidth
            height: grid.cellHeight

            Item {
                id: tile
                width: Math.max(1, parent.width - grid.gap)
                height: Math.max(1, parent.height - grid.gap)
                clip: true

                property string path: ""
                property bool downloading: false
                property string _loadedKey: ""

                function loadThumb() {
                    if (_loadedKey === cell.msgKey)
                        return
                    _loadedKey = cell.msgKey
                    path = ""
                    downloading = false
                    const m = root.messages[cell.index]
                    const f = root.cellFile(m)
                    if (!f || !root.store)
                        return
                    const k = cell.msgKey
                    root.store.fetch(f, 4, (p) => {
                        if (tile && tile._loadedKey === k)
                            tile.path = p
                    })
                }

                Component.onCompleted: loadThumb()
                Connections {
                    target: cell
                    function onMsgKeyChanged() { tile.loadThumb() }
                }

                Rectangle { anchors.fill: parent; color: Theme.highlight }

                Image {
                    anchors.fill: parent
                    visible: full.status !== Image.Ready
                    asynchronous: true
                    sourceSize: Qt.size(12, 12)
                    source: cell.mini ? "image://pic/0/" + Math.round(tile.width) + "/mini/" + cell.mini : ""
                }

                Image {
                    id: full
                    anchors.fill: parent
                    asynchronous: true
                    sourceSize: Qt.size(Math.round(tile.width), Math.round(tile.height))
                    source: tile.path ? "image://pic/0/" + Math.round(tile.width) + "/" + tile.path : ""
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { OpacityAnimator { duration: 150 } }
                }

                Loader {
                    anchors.fill: parent
                    active: cell.hasSpoiler && !(root.unveiledTick, root.unveiled[cell.msgKey])
                    sourceComponent: Veil {
                        corner: "0"
                        mini: cell.mini
                        pic: tile.path
                        live: root.visible
                    }
                }

                Rectangle {
                    visible: cell.isVideo
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 5
                    width: len.implicitWidth + 10
                    height: 18
                    radius: 9
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text {
                        id: len
                        anchors.centerIn: parent
                        text: cell.isVideo ? root.clock(cell.duration) : ""
                        color: "white"
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: tile.downloading
                    color: Qt.rgba(0, 0, 0, 0.35)
                    Ring {
                        anchors.centerIn: parent
                        value: 0.3
                        cross: false
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const m = root.messages[cell.index]
                        if (m)
                            root.picked(tile, m)
                    }
                }
            }
        }

        footer: Item {
            width: grid.width
            height: (root.loading || root.more) && grid.count > 0 ? 48 : 0
            visible: height > 0
            Text {
                anchors.centerIn: parent
                text: Tr.t(root.loading ? "yuklanmoqda..." : "Yana")
                color: root.loading ? Theme.grey : Theme.accent
                font.family: Theme.font
                font.pixelSize: 15
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.more && !root.loading
                onClicked: root.needMore()
            }
        }
    }
}
