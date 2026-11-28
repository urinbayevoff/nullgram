// A Telegram custom emoji (0.9.9): WebP static image, TGS Lottie animation, or WebM video sticker,
// backed by Store's batched getCustomEmojiStickers cache. Fast static thumbnail shows immediately;
// TGS/WebM animates only while visible, running (not scrolling / page visible), Prefs.emoji is on,
// and a global animation slot (Emo.maxCustomAnim <= 12) is acquired; otherwise shows its first frame.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

Item {
    id: root
    required property var store
    property string emojiId: ""
    property string fallback: ""
    property int size: 20
    property bool running: true
    property bool animate: true
    property color tintColor: "transparent"

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property var entry: store && emojiId !== "" && emojiId !== "0"
        ? (store.customEmojiRev >= 0 ? store.customEmoji(emojiId) : null) : null
    readonly property string fmt: entry ? entry.format : ""
    readonly property string stillUrl: store && emojiId !== "" && emojiId !== "0"
        ? (store.customEmojiRev >= 0 ? store.customEmojiStill(emojiId) : "") : ""
    readonly property string animPath: entry && (fmt === "tgs" || fmt === "webm") ? entry.filePath : ""
    readonly property bool needsTint: !!entry && !!entry.needsRepainting && tintColor.a > 0
    readonly property bool canAnimate: !_dead && animate && running && visible && Prefs.emoji && animPath !== ""
    readonly property bool isPlaying: hasSlot && canAnimate && animLoader.active

    property int _token: 0
    property bool _dead: false
    property bool hasSlot: false

    function syncSlot() {
        if (_dead)
            return
        if (canAnimate) {
            if (_token === 0)
                _token = Emo.nextCeToken()
            hasSlot = Emo.acquireCeSlot(_token)
        } else if (hasSlot) {
            hasSlot = false
            Emo.releaseCeSlot(_token)
        }
    }

    onCanAnimateChanged: syncSlot()
    Component.onCompleted: syncSlot()
    Component.onDestruction: {
        _dead = true
        if (hasSlot) {
            hasSlot = false
            Emo.releaseCeSlot(_token)
        }
    }

    Connections {
        target: Emo
        enabled: !root._dead && root.canAnimate && !root.hasSlot
        function onCustomAnimRevChanged() { root.syncSlot() }
    }

    Item {
        id: visual
        anchors.fill: parent
        layer.enabled: tintLoader.active
        opacity: tintLoader.active ? 0 : 1

        Text {
            visible: root.stillUrl === "" && !animLoader.animReady && root.fallback !== ""
            anchors.centerIn: parent
            text: root.fallback
            font.family: Theme.font
            font.pixelSize: Math.max(10, Math.round(root.size * 0.85))
            color: root.tintColor.a > 0 ? root.tintColor : Theme.text
        }

        Image {
            id: stillImg
            anchors.fill: parent
            asynchronous: true
            smooth: true
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(Math.max(32, Math.round(root.width * 2)), Math.max(32, Math.round(root.height * 2)))
            source: root.stillUrl
            visible: root.stillUrl !== "" && !(animLoader.active && animLoader.animReady)
        }

        Loader {
            id: animLoader
            anchors.fill: parent
            property bool animReady: false
            active: root.hasSlot && root.canAnimate
            onActiveChanged: if (!active) animReady = false
            sourceComponent: root.fmt === "tgs" ? tgsComp : root.fmt === "webm" ? webmComp : null

            Component {
                id: tgsComp
                Lottie {
                    anchors.fill: parent
                    path: root.animPath
                    running: root.hasSlot && root.canAnimate
                    most: Math.min(128, Math.max(48, Math.round(root.size * 3)))
                    onShownChanged: animLoader.animReady = shown
                    Component.onCompleted: animLoader.animReady = shown
                }
            }

            Component {
                id: webmComp
                InlineVideo {
                    anchors.fill: parent
                    path: root.animPath
                    running: root.hasSlot && root.canAnimate
                    sound: false
                    loop: true
                    radius: 0
                    onShowingChanged: animLoader.animReady = showing
                    Component.onCompleted: animLoader.animReady = showing
                }
            }
        }
    }

    Loader {
        id: tintLoader
        anchors.fill: parent
        active: root.needsTint && (root.stillUrl !== "" || animLoader.animReady)
        sourceComponent: MultiEffect {
            source: visual
            colorization: 1.0
            colorizationColor: root.tintColor
        }
    }
}
