// Thin link preview bar above the chat input field (reply/edit bar pattern).
// Shows site name, title/description, optional small thumbnail, and a ✕ button to disable preview.
// Tapping the bar opens the preview options menu (above/below text, small/large photo).
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: bar
    property var info: null
    property string picPath: ""
    property bool showSeparator: false

    signal optionsRequested()
    signal dismissed()

    readonly property bool hasThumb: !!(info && info.hasMedia && (picPath !== "" || (info.mini || "") !== ""))
    readonly property bool isVideo: !!(info && info.isVideo)
    readonly property string line1: info ? (info.site || info.displayUrl || info.url || "") : ""
    readonly property string line2: info ? ((info.title || info.desc || info.url || "").replace(/\s+/g, " ")) : ""

    height: 46

    Rectangle {
        visible: bar.showSeparator
        x: 14
        y: 0
        width: parent.width - 28
        height: 0.5
        color: Theme.separator
    }

    Rectangle {
        x: 14
        y: 8
        width: 2
        height: 30
        radius: 1
        color: Theme.accent
    }

    Image {
        id: thumb
        visible: bar.hasThumb
        x: 22
        y: 8
        width: 30
        height: 30
        asynchronous: true
        smooth: true
        sourceSize: Qt.size(30, 30)
        source: !bar.hasThumb ? ""
              : bar.picPath !== "" ? "image://pic/5/30/" + bar.picPath
              : "image://pic/5/30/mini/" + bar.info.mini
    }

    Rectangle {
        visible: bar.hasThumb && bar.isVideo
        x: thumb.x + 7
        y: thumb.y + 7
        width: 16
        height: 16
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.55)
        Icon {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 0.5
            width: 8
            height: 8
            name: "play"
            color: "white"
        }
    }

    Text {
        x: bar.hasThumb ? 60 : 24
        y: 7
        width: Math.max(20, parent.width - x - 44)
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        text: bar.line1
        color: Theme.accent
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Text {
        x: bar.hasThumb ? 60 : 24
        y: 24
        width: Math.max(20, parent.width - x - 44)
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        text: bar.line2
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: 13
    }

    MouseArea {
        id: optHit
        x: 0
        y: 0
        width: Math.max(0, parent.width - 42)
        height: parent.height
        onClicked: bar.optionsRequested()
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "✕"
        color: Theme.grey
        font.family: Theme.font
        font.pixelSize: 18
        MouseArea {
            anchors.fill: parent
            anchors.margins: -12
            onClicked: bar.dismissed()
        }
    }
}
