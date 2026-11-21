// A word over the foot of every page, as Telegram-iOS's UndoOverlayController (UndoOverlayControllerNode):
// the screen's width but 12 on each side, 50 high at least, its corners 25, dark glass, the words white 14
// (two lines at most) after a 50 pt place on the left for its picture; 12 over what is at the page's foot
// (a chat's field, the tab bar: the top page's `toastFloor`). In: faded in 0.3 s from 0.96 of its size
// (0.5 s, the spring); one already up is replaced by the new one rising from below (0.35 s). Out after
// 3 s: faded in 0.25 s, to 0.96. Now only for the speed (.audioRate: its badge, 1X / 1.5X / 2X).
import QtQuick

Item {
    id: toast
    property real floor: 0              // the top page's foot: the panel stands 12 over it
    anchors.fill: parent
    z: 50

    property string text: ""
    property string badge: ""           // «1.5X» drawn in its frame on the left (Telegram's anim_voice1_5x)

    function show(words, mark) {
        const replacing = box.opacity > 0.5 && !out.running
        text = words
        badge = mark || ""
        out.stop()
        if (replacing) {
            rise.restart()
        } else {
            box.lift = 0
            grow.restart()
        }
        hide.restart()
    }
    Timer { id: hide; interval: 3000; onTriggered: { grow.stop(); rise.stop(); out.restart() } }

    Rectangle {
        id: box
        property real lift: 0           // pushed down (a replacement rising from under the screen's foot)
        x: 12; width: parent.width - 24
        height: Math.max(50, words.implicitHeight + 20)
        y: parent.height - toast.floor - 12 - height + lift
        radius: 25
        color: Qt.rgba(0.11, 0.11, 0.12, 0.92)
        opacity: 0
        visible: opacity > 0
        transformOrigin: Item.Center

        Rectangle {     // the speed in its frame (iOS draws it with an animation: «1.5X» outlined)
            visible: toast.badge !== ""
            x: 25 - width / 2; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(26, badgeText.implicitWidth + 8); height: 18; radius: 4
            color: "transparent"
            border.color: "white"; border.width: 1.5
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: toast.badge
                color: "white"
                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold
            }
        }
        Text {
            id: words
            x: 50; width: parent.width - 50 - 16
            anchors.verticalCenter: parent.verticalCenter
            text: toast.text
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
    }

    ParallelAnimation {
        id: grow
        OpacityAnimator { target: box; from: 0; to: 1; duration: 300 }
        ScaleAnimator { target: box; from: 0.96; to: 1; duration: 500; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: rise
        PropertyAction { target: box; property: "opacity"; value: 1 }
        PropertyAction { target: box; property: "scale"; value: 1 }
        NumberAnimation { target: box; property: "lift"; from: toast.floor + 12 + box.height; to: 0; duration: 350
                          easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: out
        OpacityAnimator { target: box; to: 0; duration: 250; easing.type: Easing.OutQuad }
        ScaleAnimator { target: box; to: 0.96; duration: 500; easing.type: Easing.OutCubic }
    }
}
