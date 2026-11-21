// A ring of parts (Telegram-iOS's StorageUsageScreen / DataUsageScreen pie: the parts round a hole, each's share
// written on it, the whole in the middle): `parts` [{ v, color }], `center` the words in the hole.
import QtQuick

Item {
    id: donut
    property var parts: []
    property string center: ""
    property real thickness: 46
    width: 200; height: 200
    readonly property real total: { let t = 0; for (const p of parts) t += Math.max(0, p.v); return t }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const r = width / 2 - donut.thickness / 2, cx = width / 2, cy = height / 2
            ctx.lineWidth = donut.thickness
            if (donut.total <= 0) {
                ctx.strokeStyle = Theme.separator
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
                return
            }
            let a = -Math.PI / 2
            const gap = donut.parts.filter((p) => p.v > 0).length > 1 ? 0.012 : 0
            for (const p of donut.parts) {
                if (!(p.v > 0))
                    continue
                const sweep = Math.PI * 2 * p.v / donut.total
                // (a part thinner than the gaps: smaller gaps; the end never before the start, or the arc
                // would go the long way round and paint the whole ring in this part's colour)
                const g = Math.min(gap, sweep / 3)
                ctx.strokeStyle = p.color
                ctx.beginPath()
                ctx.arc(cx, cy, r, a + g, a + Math.max(sweep - g, g + 0.004))
                ctx.stroke()
                a += sweep
            }
        }
    }
    onPartsChanged: canvas.requestPaint()
    Connections { target: Theme; function onDarkChanged() { canvas.requestPaint() } }

    Repeater {          // the shares on the ring (only those wide enough to hold them)
        model: donut.parts
        Text {
            required property var modelData
            required property int index
            readonly property real before: { let t = 0; for (let i = 0; i < index; i++) t += Math.max(0, donut.parts[i].v); return t }
            readonly property real share: donut.total > 0 ? Math.max(0, modelData.v) / donut.total : 0
            readonly property real mid: -Math.PI / 2 + Math.PI * 2 * (before + Math.max(0, modelData.v) / 2) / Math.max(donut.total, 1e-9)
            readonly property real rr: donut.width / 2 - donut.thickness / 2
            visible: share >= 0.03
            x: donut.width / 2 + rr * Math.cos(mid) - width / 2
            y: donut.height / 2 + rr * Math.sin(mid) - height / 2
            text: (share * 100).toFixed(1) + "%"
            color: "white"
            font.family: Theme.font; font.pixelSize: share >= 0.08 ? 13 : 9; font.weight: Font.DemiBold
        }
    }
    Text {
        anchors.centerIn: parent
        text: donut.center
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold
    }
}
