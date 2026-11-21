// The top of Telegram-iOS's Premium and Stars screens (PremiumIntroScreen, StarsTransactionsScreen): a big star in its
// gradient over a field of small sparkles of the same colours (fainter downwards), the title, the words under it.
// `stops`: the star's colours from its bottom-left to its top-right; `bold` words come in <b>…</b>.
import QtQuick

Item {
    id: head
    property var stops: ["#6b93ff", "#8878ff", "#e46ace"]
    property string title: ""
    property string text: ""
    width: parent ? parent.width : 360
    height: words.y + words.height + 8

    Canvas {            // the sparkles: the same every time (a seeded walk), 4-point stars and dots
        id: field
        width: parent.width; height: 200
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
    Canvas {            // the star: five points, its corners rounded by a stroke of the same fill, a light on its top
        id: star
        anchors.horizontalCenter: parent.horizontalCenter
        y: 22; width: 128; height: 122
        onPaint: {
            const g = getContext("2d")
            g.reset()
            const cx = width / 2, cy = height / 2 + 6, R = 50, r = 25
            const grad = g.createLinearGradient(16, height - 10, width - 16, 10)
            for (let i = 0; i < head.stops.length; i++)
                grad.addColorStop(i / (head.stops.length - 1), head.stops[i])
            g.beginPath()
            for (let i = 0; i < 10; i++) {
                const a = -Math.PI / 2 + i * Math.PI / 5 - 0.12
                const d = i % 2 ? r : R
                if (i) g.lineTo(cx + d * Math.cos(a), cy + d * Math.sin(a))
                else g.moveTo(cx + d * Math.cos(a), cy + d * Math.sin(a))
            }
            g.closePath()
            g.fillStyle = grad; g.strokeStyle = grad
            g.lineJoin = "round"; g.lineWidth = 16
            g.stroke(); g.fill()
            const shine = g.createLinearGradient(0, 0, 0, height)
            shine.addColorStop(0, Qt.rgba(1, 1, 1, 0.35)); shine.addColorStop(0.55, Qt.rgba(1, 1, 1, 0))
            g.fillStyle = shine
            g.fill()
        }
        Component.onCompleted: requestPaint()
    }
    Text {
        id: name
        anchors.horizontalCenter: parent.horizontalCenter
        y: star.y + star.height + 10
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
