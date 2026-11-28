// Telegram statistical graph renderer (1.0): renders statisticalGraphData JSON (columns, types,
// names, colors, stacked, percentage, y_scaled) using QtQuick.Shapes (benchmarked >12x faster
// than Canvas on phone offscreen/GPU). Supports statisticalGraphAsync via getStatisticalGraph,
// lazy viewport-only loading and rendering, multi-series toggle pills, day/night theme colors,
// touch/mouse point scrubber, and error/empty states.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property var store: null
    property var chatId: 0
    property var graph: null            // TDLib StatisticalGraph (Data / Async / Error)
    property Flickable flick: null      // enclosing SubPage.flick for viewport-only draw & load
    property string chartTitle: ""

    property bool inView: false
    property bool loading: false
    property bool asyncRequested: false
    property string errorText: ""
    property var loadedData: null       // statisticalGraphData (inline or fetched)
    property var hiddenSeries: ({})     // series key -> true when toggled off
    property int hiddenTick: 0
    property int selectedIdx: -1
    property int _reqId: 0

    readonly property var fallbackColors: Theme.dark
        ? ["#5ac8fa", "#30d158", "#ff9f0a", "#bf5af2", "#ff453a", "#ffd60a", "#64d2ff", "#ff375f"]
        : ["#007aff", "#34c759", "#ff9500", "#af52de", "#ff3b30", "#ffcc00", "#32ade6", "#ff2d55"]

    // Parse Telegram chart JSON once per loadedData change
    readonly property var parsed: {
        const g = loadedData
        if (!g || g["@type"] !== "statisticalGraphData" || !g.json_data)
            return null
        try {
            const d = typeof g.json_data === "string" ? JSON.parse(g.json_data) : g.json_data
            if (!d || !Array.isArray(d.columns) || d.columns.length < 2)
                return null
            const xCol = d.columns.find((c) => Array.isArray(c) && c[0] === "x")
            if (!xCol || xCol.length < 3)       // need header + at least 2 points
                return null
            const xs = xCol.slice(1).map((v) => Number(v))
            const types = d.types || ({})
            const names = d.names || ({})
            const colors = d.colors || ({})
            const series = []
            for (const col of d.columns) {
                if (!Array.isArray(col) || col.length < 3 || col[0] === "x")
                    continue
                const key = String(col[0])
                const kind = String(types[key] || "line").toLowerCase()
                const vals = col.slice(1).map((v) => {
                    const n = Number(v)
                    return isFinite(n) ? n : 0
                })
                if (vals.length !== xs.length)
                    continue
                series.push({
                    key: key,
                    kind: (kind === "bar" || kind === "area" || kind === "step") ? kind : "line",
                    name: names[key] ? String(names[key]) : (d.columns.length === 2 && chartTitle ? chartTitle : key),
                    rawColor: colors[key] ? String(colors[key]) : "",
                    values: vals
                })
            }
            if (!series.length)
                return null
            return {
                xs: xs,
                series: series,
                stacked: !!d.stacked,
                percentage: !!d.percentage,
                yScaled: !!d.y_scaled
            }
        } catch (e) {
            return null
        }
    }

    readonly property var activeSeries: {
        void hiddenTick
        if (!parsed)
            return []
        return parsed.series.filter((s) => !hiddenSeries[s.key])
    }

    readonly property bool isEmpty: !loading && errorText === "" && loadedData !== null && parsed === null
    readonly property bool hasLegend: !!parsed && parsed.series.length > 1
    readonly property real plotH: 184
    readonly property real padL: 14
    readonly property real padR: 14
    readonly property real padT: 22
    readonly property real padB: 24
    readonly property real drawW: Math.max(40, width - padL - padR)
    readonly property real drawH: Math.max(40, plotH - padT - padB)

    implicitHeight: (loading || errorText !== "" || isEmpty)
        ? 110
        : plotH + (hasLegend ? legendFlow.implicitHeight + 14 : 6)
    height: implicitHeight

    function resolveColor(raw, idx) {
        const dark = Theme.dark
        if (raw && raw.length) {
            const m = dark ? /DARK\s*(#[0-9a-fA-F]{6,8})/i.exec(raw) : /LIGHT\s*(#[0-9a-fA-F]{6,8})/i.exec(raw)
            if (m)
                return m[1]
            const h = /#[0-9a-fA-F]{6,8}/.exec(raw)
            if (h)
                return h[0]
        }
        return fallbackColors[idx % fallbackColors.length]
    }

    function fmtNum(n) {
        if (!isFinite(n))
            return "0"
        const abs = Math.abs(n)
        const sgn = n < 0 ? "−" : ""
        if (abs >= 1e6)
            return sgn + (abs / 1e6).toFixed(1) + "M"
        if (abs >= 1e4)
            return sgn + (abs / 1e3).toFixed(1) + "K"
        return sgn + String(Math.round(abs))
    }

    function fmtX(v) {
        if (!isFinite(v))
            return ""
        if (v > 1e11)
            return Qt.formatDate(new Date(v), "dd.MM")
        if (v > 1e8)
            return Qt.formatDate(new Date(v * 1000), "dd.MM")
        return String(Math.round(v))
    }

    function fmtXFull(v) {
        if (!isFinite(v))
            return ""
        if (v > 1e11)
            return Qt.formatDate(new Date(v), "dd.MM.yyyy")
        if (v > 1e8)
            return Qt.formatDate(new Date(v * 1000), "dd.MM.yyyy")
        return String(Math.round(v))
    }

    function toggleSeries(key) {
        if (!parsed || parsed.series.length < 2)
            return
        const next = Object.assign({}, hiddenSeries)
        if (next[key]) {
            delete next[key]
        } else {
            // Keep at least one series visible
            const visibleCount = parsed.series.filter((s) => !next[s.key]).length
            if (visibleCount <= 1)
                return
            next[key] = true
        }
        hiddenSeries = next
        hiddenTick++
    }

    function checkVisible() {
        if (!flick) {
            if (!inView) {
                inView = true
                maybeLoadAsync()
            }
            return
        }
        if (flick.height <= 0 || flick.contentHeight <= 0)
            return
        const pt = root.mapToItem(flick.contentItem, 0, 0)
        // Wait until Column layout has positioned this chart (or if it's genuinely near the top)
        const top = pt.y
        const bot = top + Math.max(80, root.height)
        const viewTop = flick.contentY - 60
        const viewBot = flick.contentY + flick.height + 60
        const vis = bot >= viewTop && top <= viewBot
        if (vis !== inView)
            inView = vis
        if (vis)
            maybeLoadAsync()
    }

    Timer {
        id: viewCheckTimer
        interval: 90
        onTriggered: root.checkVisible()
    }

    function syncGraph() {
        _reqId++
        loading = false
        asyncRequested = false
        errorText = ""
        loadedData = null
        hiddenSeries = ({})
        hiddenTick++
        selectedIdx = -1
        if (!graph)
            return
        const gt = graph["@type"]
        if (gt === "statisticalGraphData") {
            loadedData = graph
        } else if (gt === "statisticalGraphError") {
            errorText = graph.error_message || Tr.t("Grafikni yuklab bo'lmadi")
        } else if (gt === "statisticalGraphAsync") {
            if (inView)
                maybeLoadAsync()
        }
    }

    function maybeLoadAsync() {
        if (!graph || graph["@type"] !== "statisticalGraphAsync")
            return
        if (asyncRequested || loadedData || !store)
            return
        asyncRequested = true
        loading = true
        errorText = ""
        const req = ++_reqId
        store.getStatisticalGraph(chatId, graph.token, 0, (data, err) => {
            if (!root || req !== root._reqId)
                return
            root.loading = false
            if (data) {
                root.loadedData = data
            } else {
                root.errorText = err || Tr.t("Grafikni yuklab bo'lmadi")
            }
        })
    }

    function retry() {
        asyncRequested = false
        errorText = ""
        maybeLoadAsync()
    }

    onGraphChanged: syncGraph()
    onHeightChanged: viewCheckTimer.restart()
    Component.onCompleted: {
        syncGraph()
        viewCheckTimer.restart()
    }

    Connections {
        target: root.flick
        enabled: root.flick !== null
        function onContentYChanged() { root.checkVisible() }
        function onHeightChanged() { viewCheckTimer.restart() }
        function onContentHeightChanged() { viewCheckTimer.restart() }
    }

    // Geometry & SVG paths built only when visible in viewport and data is ready
    readonly property var geom: {
        void Theme.dark
        if (!inView || !parsed || !activeSeries.length || drawW <= 0 || drawH <= 0)
            return null
        const xs = parsed.xs
        const n = xs.length
        const ser = activeSeries
        const isBarAll = ser.every((s) => s.kind === "bar")
        const isAreaPct = parsed.percentage && ser.every((s) => s.kind === "area")
        const stacked = parsed.stacked && (isBarAll || isAreaPct)

        // Compute Y scale
        let lo = Infinity, hi = -Infinity
        const perSeriesScale = []
        if (isAreaPct) {
            lo = 0; hi = 100
        } else if (stacked) {
            lo = 0; hi = 0
            for (let i = 0; i < n; i++) {
                let sum = 0
                for (let s = 0; s < ser.length; s++)
                    sum += Math.max(0, ser[s].values[i])
                if (sum > hi) hi = sum
            }
        } else if (parsed.yScaled && ser.length > 1) {
            for (let s = 0; s < ser.length; s++) {
                let slo = Infinity, shi = -Infinity
                for (const v of ser[s].values) {
                    if (v < slo) slo = v
                    if (v > shi) shi = v
                }
                if (slo === shi) { slo -= 1; shi += 1 }
                perSeriesScale.push({ lo: slo, hi: shi })
            }
            lo = perSeriesScale[0].lo
            hi = perSeriesScale[0].hi
        } else {
            for (let s = 0; s < ser.length; s++) {
                for (const v of ser[s].values) {
                    if (v < lo) lo = v
                    if (v > hi) hi = v
                }
            }
            if (isBarAll && lo > 0)
                lo = 0
        }
        if (!isFinite(lo) || !isFinite(hi)) { lo = 0; hi = 1 }
        if (hi === lo) { hi = lo + 1 }

        const xOf = (i) => {
            if (isBarAll)
                return padL + (i + 0.5) * drawW / n
            return padL + (n > 1 ? drawW * i / (n - 1) : drawW / 2)
        }
        const yOfVal = (v, slo, shi) => padT + drawH - drawH * ((v - slo) / (shi - slo))

        // Build per-series vector paths
        const shapes = []
        const cumPrev = stacked ? new Array(n).fill(0) : null
        const totals = isAreaPct ? xs.map((_, i) => {
            let t = 0
            for (const s of ser) t += Math.max(0, s.values[i])
            return t > 0 ? t : 1
        }) : null
        const slotW = isBarAll ? drawW / n : 0
        const barW = isBarAll
            ? (stacked ? Math.max(2, slotW * 0.72) : Math.max(1.5, (slotW * 0.78) / ser.length))
            : 0

        for (let si = 0; si < ser.length; si++) {
            const s = ser[si]
            const origIdx = parsed.series.findIndex((o) => o.key === s.key)
            const col = resolveColor(s.rawColor, origIdx >= 0 ? origIdx : si)
            const slo = perSeriesScale.length ? perSeriesScale[si].lo : lo
            const shi = perSeriesScale.length ? perSeriesScale[si].hi : hi
            const ptsY = []
            let svg = ""

            if (s.kind === "bar") {
                const parts = []
                for (let i = 0; i < n; i++) {
                    const val = Math.max(0, s.values[i])
                    const base = stacked ? cumPrev[i] : 0
                    const topVal = base + val
                    if (stacked)
                        cumPrev[i] = topVal
                    const yTop = yOfVal(topVal, lo, hi)
                    const yBot = yOfVal(base, lo, hi)
                    const h = Math.max(0.5, yBot - yTop)
                    const cx = stacked
                        ? padL + i * slotW + (slotW - barW) / 2
                        : padL + i * slotW + (slotW - barW * ser.length) / 2 + si * barW
                    parts.push("M " + cx.toFixed(1) + " " + yTop.toFixed(1)
                               + " h " + barW.toFixed(1) + " v " + h.toFixed(1)
                               + " h " + (-barW).toFixed(1) + " Z")
                    ptsY.push(yTop)
                }
                svg = parts.join(" ")
            } else if (s.kind === "area" && isAreaPct) {
                const topPts = []
                const botPts = []
                for (let i = 0; i < n; i++) {
                    const pct = 100 * Math.max(0, s.values[i]) / totals[i]
                    const base = cumPrev[i]
                    const topVal = Math.min(100, base + pct)
                    cumPrev[i] = topVal
                    const px = xOf(i)
                    const yt = yOfVal(topVal, 0, 100)
                    const yb = yOfVal(base, 0, 100)
                    topPts.push(px.toFixed(1) + " " + yt.toFixed(1))
                    botPts.push(px.toFixed(1) + " " + yb.toFixed(1))
                    ptsY.push(yt)
                }
                botPts.reverse()
                svg = "M " + topPts.join(" L ") + " L " + botPts.join(" L ") + " Z"
            } else {
                const parts = []
                for (let i = 0; i < n; i++) {
                    const px = xOf(i)
                    const py = yOfVal(s.values[i], slo, shi)
                    ptsY.push(py)
                    if (i === 0) {
                        parts.push("M " + px.toFixed(1) + " " + py.toFixed(1))
                    } else if (s.kind === "step") {
                        parts.push("H " + px.toFixed(1) + " V " + py.toFixed(1))
                    } else {
                        parts.push("L " + px.toFixed(1) + " " + py.toFixed(1))
                    }
                }
                svg = parts.join(" ")
            }
            shapes.push({
                key: s.key,
                name: s.name,
                kind: s.kind,
                filled: s.kind === "bar" || (s.kind === "area" && isAreaPct),
                color: col,
                svg: svg,
                ptsY: ptsY,
                values: s.values
            })
        }

        // Horizontal grid SVG (4 levels)
        const gridParts = []
        const yLabels = []
        for (let k = 0; k < 4; k++) {
            const gy = padT + drawH * k / 3
            gridParts.push("M " + padL.toFixed(1) + " " + gy.toFixed(1) + " H " + (padL + drawW).toFixed(1))
            const v = hi - (hi - lo) * k / 3
            yLabels.push({ y: gy, text: isAreaPct ? Math.round(v) + "%" : fmtNum(v) })
        }

        // X axis ticks (up to 4 evenly spaced)
        const xTicks = []
        const tickCount = Math.min(4, n)
        for (let k = 0; k < tickCount; k++) {
            const idx = tickCount > 1 ? Math.round(k * (n - 1) / (tickCount - 1)) : 0
            xTicks.push({ x: xOf(idx), text: fmtX(xs[idx]), align: k === 0 ? 0 : k === tickCount - 1 ? 2 : 1 })
        }

        return {
            n: n,
            xs: xs,
            isBarAll: isBarAll,
            isAreaPct: isAreaPct,
            shapes: shapes,
            gridSvg: gridParts.join(" "),
            yLabels: yLabels,
            xTicks: xTicks
        }
    }

    function indexFromX(mx) {
        if (!geom || geom.n < 1)
            return -1
        const frac = Math.max(0, Math.min(1, (mx - padL) / drawW))
        const idx = geom.isBarAll
            ? Math.min(geom.n - 1, Math.floor(frac * geom.n))
            : Math.round(frac * (geom.n - 1))
        return Math.max(0, Math.min(geom.n - 1, idx))
    }

    function xPosOf(idx) {
        if (!geom || idx < 0 || idx >= geom.n)
            return padL
        if (geom.isBarAll)
            return padL + (idx + 0.5) * drawW / geom.n
        return padL + (geom.n > 1 ? drawW * idx / (geom.n - 1) : drawW / 2)
    }

    // Loading state
    Row {
        visible: root.loading
        anchors.centerIn: parent
        spacing: 10
        Ring {
            width: 18; height: 18
            value: 0.7
            color: Theme.accent
            cross: false
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: Tr.t("Yuklanmoqda…")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Error state with Retry button
    Column {
        visible: !root.loading && root.errorText !== ""
        anchors.centerIn: parent
        width: parent.width - 32
        spacing: 8
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Tr.f("Grafikni yuklab bo'lmadi: %1", root.errorText)
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 13
        }
        Rectangle {
            visible: !!root.graph && root.graph["@type"] === "statisticalGraphAsync"
            anchors.horizontalCenter: parent.horizontalCenter
            width: retryLbl.implicitWidth + 24; height: 30; radius: 15
            color: retryHit.pressed ? Theme.highlight : Theme.bg
            Text {
                id: retryLbl
                anchors.centerIn: parent
                text: Tr.t("Qayta urinish")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            MouseArea {
                id: retryHit
                anchors.fill: parent
                onClicked: root.retry()
            }
        }
    }

    // Empty / invalid data state
    Text {
        visible: root.isEmpty
        anchors.centerIn: parent
        text: Tr.t("Ma'lumot yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 14
    }

    // Plot area (drawn only when in viewport and data parsed)
    Item {
        id: plotArea
        visible: !!root.geom
        width: root.width
        height: root.plotH

        // Horizontal grid lines
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: Theme.separator
                strokeWidth: 0.75
                fillColor: "transparent"
                PathSvg { path: root.geom ? root.geom.gridSvg : "" }
            }
        }

        // Y axis value labels
        Repeater {
            model: root.geom ? root.geom.yLabels : []
            Text {
                required property var modelData
                z: 2
                x: root.padL
                y: modelData.y - height - 2
                text: modelData.text
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 10
            }
        }

        // Series vector paths (1 Shape per visible series)
        Repeater {
            model: root.geom ? root.geom.shapes : []
            Shape {
                id: serShape
                required property var modelData
                anchors.fill: parent
                ShapePath {
                    strokeColor: serShape.modelData.filled ? "transparent" : serShape.modelData.color
                    strokeWidth: serShape.modelData.filled ? 0 : 2
                    fillColor: serShape.modelData.filled ? serShape.modelData.color : "transparent"
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: serShape.modelData.svg }
                }
            }
        }

        // X axis date/index labels
        Repeater {
            model: root.geom ? root.geom.xTicks : []
            Text {
                required property var modelData
                x: modelData.align === 0 ? root.padL
                 : modelData.align === 2 ? root.width - root.padR - width
                 : Math.max(root.padL, Math.min(root.width - root.padR - width, modelData.x - width / 2))
                y: root.plotH - root.padB + 5
                text: modelData.text
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 10
            }
        }

        // Scrubber vertical hairline + point markers
        Rectangle {
            visible: root.geom !== null && root.selectedIdx >= 0 && root.selectedIdx < root.geom.n
            x: root.xPosOf(root.selectedIdx) - 0.5
            y: root.padT
            width: 1
            height: root.drawH
            color: Theme.grey
            opacity: 0.65
        }
        Repeater {
            model: (root.geom && root.selectedIdx >= 0 && root.selectedIdx < root.geom.n) ? root.geom.shapes : []
            Rectangle {
                required property var modelData
                readonly property real py: (root.selectedIdx >= 0 && root.selectedIdx < modelData.ptsY.length)
                    ? modelData.ptsY[root.selectedIdx] : 0
                x: root.xPosOf(root.selectedIdx) - 4.5
                y: py - 4.5
                width: 9; height: 9; radius: 4.5
                color: Theme.card
                border.color: modelData.color
                border.width: 2.5
            }
        }

        // Floating tooltip card showing date & series values at selectedIdx
        Rectangle {
            id: tipCard
            visible: root.geom !== null && root.selectedIdx >= 0 && root.selectedIdx < root.geom.n
            readonly property real selX: root.xPosOf(root.selectedIdx)
            x: selX + 10 + width <= root.width - root.padR
               ? selX + 10
               : Math.max(root.padL, selX - width - 10)
            y: 4
            width: Math.min(root.width - 28, Math.max(108, tipCol.implicitWidth + 20))
            height: tipCol.implicitHeight + 12
            radius: 10
            color: Theme.menu
            border.color: Theme.separator
            border.width: 0.75
            z: 4
            Column {
                id: tipCol
                x: 10; y: 6
                spacing: 3
                Text {
                    text: (root.geom && root.selectedIdx >= 0 && root.selectedIdx < root.geom.n)
                        ? root.fmtXFull(root.geom.xs[root.selectedIdx]) : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Repeater {
                    model: (root.geom && root.selectedIdx >= 0 && root.selectedIdx < root.geom.n) ? root.geom.shapes : []
                    Row {
                        required property var modelData
                        spacing: 6
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            anchors.verticalCenter: parent.verticalCenter
                            color: parent.modelData.color
                        }
                        Text {
                            text: parent.modelData.name
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 11
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 110)
                        }
                        Text {
                            text: (root.selectedIdx >= 0 && root.selectedIdx < parent.modelData.values.length)
                                ? root.fmtNum(parent.modelData.values[root.selectedIdx]) : ""
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        // Touch & mouse point scrubber (yields vertical drag to SubPage.flick)
        MouseArea {
            id: scrubHit
            anchors.fill: parent
            property real pressX: 0
            property real pressY: 0
            property bool scrubbing: false
            preventStealing: scrubbing
            onPressed: (m) => {
                pressX = m.x
                pressY = m.y
                scrubbing = false
            }
            onPositionChanged: (m) => {
                if (!pressed)
                    return
                if (!scrubbing) {
                    const dx = Math.abs(m.x - pressX)
                    const dy = Math.abs(m.y - pressY)
                    if (dx > 8 && dx >= dy)
                        scrubbing = true
                    else
                        return
                }
                root.selectedIdx = root.indexFromX(m.x)
            }
            onClicked: (m) => {
                const idx = root.indexFromX(m.x)
                root.selectedIdx = (root.selectedIdx === idx && !scrubbing) ? -1 : idx
            }
            onReleased: scrubbing = false
            onCanceled: scrubbing = false
        }
    }

    // Series legend pills (tap to toggle series on/off)
    Flow {
        id: legendFlow
        visible: root.hasLegend && !!root.geom
        x: 14; y: root.plotH + 4
        width: root.width - 28
        spacing: 6
        Repeater {
            model: root.parsed ? root.parsed.series : []
            Rectangle {
                required property var modelData
                required property int index
                readonly property bool off: root.hiddenTick >= 0 && !!root.hiddenSeries[modelData.key]
                readonly property color pillColor: root.resolveColor(modelData.rawColor, index)
                width: pillRow.implicitWidth + 18
                height: 26
                radius: 13
                color: off ? "transparent" : pillColor
                border.color: pillColor
                border.width: 1.5
                opacity: pillHit.pressed ? 0.7 : 1
                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        visible: !parent.parent.off
                        text: "✓"
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold
                    }
                    Text {
                        text: parent.parent.modelData.name
                        color: parent.parent.off ? parent.parent.pillColor : "white"
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: pillHit
                    anchors.fill: parent
                    onClicked: root.toggleSeries(parent.modelData.key)
                }
            }
        }
    }
}
