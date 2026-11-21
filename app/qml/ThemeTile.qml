// A chat theme in the Ko'rinish page's row, as Telegram-iOS's ThemeCarouselThemeIconItemNode: its background in small
// (82 × 108, corners 14), our bubble and theirs over it, its emoji at the foot; chosen: a ring of the accent round it.
// `set`: the theme's themeSettings for the day or the night (null: the app's own — its base and accent, Store.ownLook).
import QtQuick

Item {
    id: tile
    property var store
    property var set: null
    property string emoji: "🏠"
    property bool chosen: false
    signal clicked()
    width: 90; height: 120

    property string spec: ""
    function load() {
        if (!store)
            return
        const dark = Theme.dark
        const put = (s) => { if (s && dark === Theme.dark) tile.spec = s }
        if (set && set.background)
            store.wallOf(set.background, set.background.type, put)
        else
            store.wallOfLook(own, put)
    }
    readonly property var own: { Prefs.dayBase; Prefs.nightBase; Prefs.accents; return store ? store.ownLook(Theme.dark) : ({}) }
    onOwnChanged: if (!set) load()
    onSetChanged: load()
    onStoreChanged: load()
    Component.onCompleted: load()
    Connections { target: Theme; function onDarkChanged() { tile.load() } }

    readonly property color outColor: set ? (store ? store.fillColor(set.outgoing_message_fill) : "#e1ffc7")
                                      : own.out ? own.out : Theme.dark ? "#3e88f7" : "#e1ffc7"
    readonly property color inColor: set ? Theme.bubbleIn : own.bubbleIn ? own.bubbleIn : own.tint ? own.tint.bubbleIn : Theme.dark ? "#1d1d1d" : "#ffffff"

    Rectangle {         // the ring
        x: 1; y: 3; width: 88; height: 114; radius: 17
        color: "transparent"
        border.width: 2; border.color: Theme.accent
        visible: tile.chosen
    }
    Wallpaper {
        id: wall
        x: 4; y: 6; width: 82; height: 108
        radius: 14
        spec: tile.spec || Theme.wall
    }
    Rectangle { x: 4 + 82 - 9 - 48; y: 6 + 12; width: 48; height: 22; radius: 11; color: tile.outColor }
    Rectangle { x: 4 + 9; y: 6 + 40; width: 48; height: 22; radius: 11; color: tile.inColor }
    Image {
        id: pic
        x: 33; y: 79; width: 24; height: 24
        source: Emo.fileUrl(tile.emoji)
        sourceSize: Qt.size(96, 96)
        visible: source != ""
    }
    Text {
        visible: !pic.visible
        x: 0; y: 78; width: 90; height: 26
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        text: tile.emoji
        font.pixelSize: 20
    }
    MouseArea { anchors.fill: parent; onClicked: tile.clicked() }
}
