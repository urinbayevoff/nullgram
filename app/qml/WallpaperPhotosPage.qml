// «Galereyadan tanlash»: the phone's own pictures (td.recent's, newest first) in three columns, as the attach sheet's;
// one tapped opens before it is set as the chats' background (WallpaperPreview, inputBackgroundLocal).
import QtQuick

SubPage {
    id: page
    title: Tr.t("Galereyadan tanlash")
    property var photos: []
    property var maker: null
    property var chatId: 0              // one chat's (WallpaperPage's): handed on to the preview
    property Item home: null
    Component.onCompleted: photos = td.recent().filter((f) => f.kind === "photo" && !f.path.toLowerCase().endsWith(".gif"))
    function preview(path) {
        if (!maker)
            maker = Qt.createComponent("WallpaperPreview.qml")
        nav.push(maker, { local: path, chatId: chatId, home: home, type: { "@type": "backgroundTypeWallpaper", is_blurred: false, is_moving: false } })
    }

    Text {
        visible: !page.photos.length
        x: 32; width: parent.width - 64
        topPadding: 80
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: Tr.t("Telefonda rasm topilmadi")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    Grid {
        x: 0; width: parent.width
        columns: 3
        spacing: 2
        readonly property real cell: (width - 4) / 3
        Repeater {
            model: page.photos
            Image {
                required property var modelData
                width: parent.cell; height: parent.cell
                source: "image://thumb/" + modelData.path
                sourceSize: Qt.size(240, 240)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true
                MouseArea { anchors.fill: parent; onClicked: page.preview(parent.modelData.path) }
            }
        }
    }
    Item { width: 1; height: 20 }
}
