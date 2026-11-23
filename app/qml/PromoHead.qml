// The top of Telegram-iOS's Premium and Stars screens (PremiumIntroScreen, StarsTransactionsScreen): a big star in its
// gradient over a field of small sparkles of the same colours (fainter downwards), the title, the words under it.
// `stops`: the star's colours from its bottom-left to its top-right; `bold` words come in <b>…</b>.
// When the page opens (after its slide-in finishes) and whenever the star is tapped, the star spins 360° in 3D with a
// spring bounce while the sparkle field and 16 burst stars fly outward from behind it and twinkle into place.
// Drawn once onto GPU textures (Canvas painted once), animated by Qt Quick transforms so every frame runs at 60 fps.
import QtQuick

Item {
    id: head
    property var stops: ["#6b93ff", "#8878ff", "#e46ace"]
    property string title: ""
    property string text: ""
    property real burst: 1              // 0..1: burst sparkles flying out from behind the star
    width: parent ? parent.width : 360
    height: words.y + words.height + 8

    function play() {
        introAnim.restart()
    }
    Timer {
        id: startTimer
        interval: 380                   // after the page's push transition (Main.qml slide) has brought it on screen
        running: true
        onTriggered: head.play()
    }
    onStopsChanged: {
        field.requestPaint()
        star.requestPaint()
    }

    ParallelAnimation {
        id: introAnim
        // 1. Background sparkle field expands outward from the star's center
        SequentialAnimation {
            PropertyAction { target: field; property: "scale"; value: 0.18 }
            NumberAnimation { target: field; property: "scale"; from: 0.18; to: 1.08; duration: 620; easing.type: Easing.OutCubic }
            NumberAnimation { target: field; property: "scale"; from: 1.08; to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
        }
        SequentialAnimation {
            PropertyAction { target: field; property: "opacity"; value: 0.0 }
            NumberAnimation { target: field; property: "opacity"; from: 0.0; to: 1.0; duration: 420; easing.type: Easing.OutQuad }
        }
        // 2. 16 burst stars fly out and twinkle
        SequentialAnimation {
            PropertyAction { target: head; property: "burst"; value: 0.0 }
            NumberAnimation { target: head; property: "burst"; from: 0.0; to: 1.0; duration: 1150; easing.type: Easing.OutCubic }
        }
        // 3. The big star's 3D 360° Y-flip with overshoot
        SequentialAnimation {
            PropertyAction { target: starFlip; property: "angle"; value: 0 }
            NumberAnimation { target: starFlip; property: "angle"; from: 0; to: 360; duration: 1050; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
        }
        // 4. The big star's spring scale bounce (0.35 -> 1.24 -> 0.92 -> 1.0)
        SequentialAnimation {
            PropertyAction { target: starWrap; property: "scale"; value: 0.35 }
            NumberAnimation { target: starWrap; property: "scale"; from: 0.35; to: 1.24; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: starWrap; property: "scale"; from: 1.24; to: 0.92; duration: 280; easing.type: Easing.InOutQuad }
            NumberAnimation { target: starWrap; property: "scale"; from: 0.92; to: 1.0; duration: 350; easing.type: Easing.OutBack }
        }
        // 5. The big star's tilt wobble (-20° -> +10° -> -4° -> 0°)
        SequentialAnimation {
            PropertyAction { target: starWrap; property: "rotation"; value: -20 }
            NumberAnimation { target: starWrap; property: "rotation"; from: -20; to: 10; duration: 420; easing.type: Easing.OutQuad }
            NumberAnimation { target: starWrap; property: "rotation"; from: 10; to: -4; duration: 320; easing.type: Easing.InOutQuad }
            NumberAnimation { target: starWrap; property: "rotation"; from: -4; to: 0; duration: 310; easing.type: Easing.OutCubic }
        }
    }

    Canvas {            // the sparkles: painted once, scaled outward from the star on open/tap
        id: field
        width: parent.width; height: 200
        transformOrigin: Item.Center
        onPaint: {
            const g = getContext("2d")
            g.reset()
            let s = 7
            const rnd = () => { s = (s * 16807) % 2147483647; return s / 2147483647 }
            for (let i = 0; i < 150; i++) {
                const x = rnd() * width, y = rnd() * height
                const r = 2 + rnd() * 4
                if (Math.abs(x - width / 2) < 70 && y > 20 && y < 160 && rnd() < 0.8)
                    continue            // (clear around the star)
                g.globalAlpha = (0.4 + rnd() * 0.6) * (1 - y / height * 0.6)
                g.fillStyle = head.stops[Math.floor(rnd() * head.stops.length)]
                g.beginPath()
                if (rnd() < 0.55) {
                    g.moveTo(x, y - r); g.quadraticCurveTo(x, y, x + r, y)
                    g.quadraticCurveTo(x, y, x, y + r); g.quadraticCurveTo(x, y, x - r, y)
                    g.quadraticCurveTo(x, y, x, y - r)
                } else
                    g.arc(x, y, r / 2.5, 0, Math.PI * 2)
                g.fill()
            }
        }
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }

    // 16 animated sparkle icons bursting outward from behind the star and twinkling
    Item {
        width: parent.width; height: 200
        Repeater {
            model: 16
            Icon {
                required property int index
                readonly property real ang: index * Math.PI / 8 + (index % 2) * 0.18
                readonly property real dist: 58 + (index % 4) * 24
                readonly property real p: head.burst
                readonly property real cx: parent.width / 2
                readonly property real cy: 83
                readonly property real sz: (index % 3 === 0 ? 14 : index % 2 === 0 ? 11 : 9)
                width: sz; height: sz
                x: cx + Math.cos(ang) * dist * (0.15 + 0.85 * p) - width / 2
                y: cy + Math.sin(ang) * dist * 0.68 * (0.15 + 0.85 * p) - height / 2
                scale: p >= 1 ? 0.85 : (0.3 + 0.95 * Math.sin(p * Math.PI)) * (0.75 + 0.35 * Math.sin(p * Math.PI * 4 + index))
                rotation: (1 - p) * (index % 2 ? 180 : -180)
                opacity: p >= 1 ? 0.55 : Math.min(1, p * 3.5) * (0.55 + 0.45 * Math.sin(p * Math.PI))
                name: index % 4 === 0 ? "star" : "sparkle"
                color: head.stops[index % head.stops.length]
            }
        }
    }

    Item {
        id: starWrap
        anchors.horizontalCenter: parent.horizontalCenter
        y: 22; width: 128; height: 122
        transform: Rotation {
            id: starFlip
            origin.x: 64; origin.y: 61
            axis { x: 0.12; y: 1; z: 0.08 }
            angle: 0
        }
        Canvas {        // rounded star with left-wing notch, drawn by hand after Telegram-iOS's Telegram Star, gradient fill and top light
            id: star
            anchors.fill: parent
            onPaint: {
                const g = getContext("2d")
                g.reset()
                const s = 5.4, ox = (width - 24 * s) / 2, oy = (height - 24 * s) / 2
                const px = (x) => ox + x * s, py = (y) => oy + y * s
                const grad = g.createLinearGradient(14, height - 10, width - 14, 10)
                for (let i = 0; i < head.stops.length; i++)
                    grad.addColorStop(i / (head.stops.length - 1), head.stops[i])
                g.beginPath()
                g.moveTo(px(12), py(2.4))
                g.bezierCurveTo(px(12.7), py(2.4), px(13.2), py(3.0), px(13.6), py(3.9))
                g.lineTo(px(15.1), py(7.3))
                g.bezierCurveTo(px(15.4), py(7.9), px(15.9), py(8.3), px(16.6), py(8.4))
                g.lineTo(px(20.5), py(8.9))
                g.bezierCurveTo(px(21.8), py(9.1), px(22.3), py(10.4), px(21.4), py(11.3))
                g.lineTo(px(18.1), py(14.3))
                g.bezierCurveTo(px(17.6), py(14.7), px(17.4), py(15.3), px(17.5), py(16.0))
                g.lineTo(px(18.2), py(19.9))
                g.bezierCurveTo(px(18.4), py(21.1), px(17.2), py(22.0), px(16.1), py(21.4))
                g.lineTo(px(12.7), py(19.4))
                g.bezierCurveTo(px(12.2), py(19.1), px(11.7), py(19.1), px(11.2), py(19.4))
                g.lineTo(px(7.7), py(21.3))
                g.bezierCurveTo(px(6.6), py(21.9), px(5.5), py(21.0), px(5.7), py(19.8))
                g.lineTo(px(6.1), py(17.6))
                g.bezierCurveTo(px(6.3), py(16.4), px(7.1), py(15.4), px(8.3), py(14.8))
                g.lineTo(px(12.4), py(12.9))
                g.bezierCurveTo(px(12.7), py(12.75), px(12.7), py(12.3), px(12.3), py(12.35))
                g.lineTo(px(6.6), py(13.15))
                g.bezierCurveTo(px(5.6), py(13.3), px(4.7), py(12.9), px(3.9), py(12.2))
                g.lineTo(px(2.4), py(10.9))
                g.bezierCurveTo(px(1.6), py(10.2), px(2.0), py(9.0), px(3.1), py(8.85))
                g.lineTo(px(7.3), py(8.4))
                g.bezierCurveTo(px(8.0), py(8.3), px(8.6), py(7.9), px(8.9), py(7.3))
                g.lineTo(px(10.4), py(3.9))
                g.bezierCurveTo(px(10.8), py(3.0), px(11.3), py(2.4), px(12), py(2.4))
                g.closePath()
                g.fillStyle = grad
                g.fill()
                const shine = g.createLinearGradient(0, 8, 0, height - 10)
                shine.addColorStop(0, Qt.rgba(1, 1, 1, 0.35)); shine.addColorStop(0.55, Qt.rgba(1, 1, 1, 0))
                g.fillStyle = shine
                g.fill()
            }
            Component.onCompleted: requestPaint()
        }
    }
    MouseArea {
        anchors.fill: starWrap
        anchors.margins: -24
        onClicked: head.play()
    }
    Text {
        id: name
        anchors.horizontalCenter: parent.horizontalCenter
        y: starWrap.y + starWrap.height + 10
        text: head.title
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 28; font.weight: Font.Bold
    }
    Text {
        id: words
        x: 28; width: parent.width - 56
        y: name.y + name.height + 10
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: head.text
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 16
    }
}
