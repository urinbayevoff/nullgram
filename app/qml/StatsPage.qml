// Statistics (Telegram-iOS's ChannelStatsController, the short way): OVERVIEW tiles (a channel: subscribers, notifications
// on, views and shares per post, reactions per post; a group: members, messages, viewers, senders) with the change
// against the period before; the subscribers' (members') curve; a channel's recent posts with views and shares.
// getChatStatistics; a graph that comes as statisticalGraphAsync is left out (asking for it: not yet).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property var chat: store.chats[chatId]
    property var stats: null
    property string error: ""
    property var posts: ({})            // message id -> message
    title: Tr.t("Statistika")
    Component.onCompleted: store.send({ "@type": "getChatStatistics", chat_id: chatId, is_dark: Theme.dark }, (r) => {
        if (r["@type"] === "error")
            return page.error = r.message
        page.stats = r
        for (const i of (r.recent_interactions || []))
            if (i.object_type["@type"] === "chatStatisticsObjectTypeMessage")
                store.send({ "@type": "getMessage", chat_id: page.chatId, message_id: i.object_type.message_id }, (m) => {
                    if (m["@type"] === "message") {
                        const o = Object.assign({}, page.posts)
                        o[m.id] = m
                        page.posts = o
                    }
                })
    })
    readonly property bool channel: !!stats && stats["@type"] === "chatStatisticsChannel"
    readonly property var tiles: {
        const s = stats
        if (!s)
            return []
        if (channel)
            return [{ v: s.member_count, k: Tr.t("Obunachilar") },
                    { pct: s.enabled_notifications_percentage, k: Tr.t("Bildirishnoma yoqilgan") },
                    { v: s.mean_message_view_count, k: Tr.t("Postdagi ko'rishlar") },
                    { v: s.mean_message_share_count, k: Tr.t("Postdagi ulashishlar") },
                    { v: s.mean_message_reaction_count, k: Tr.t("Postdagi reaksiyalar") }]
        return [{ v: s.member_count, k: Tr.t("A'zolar") }, { v: s.message_count, k: Tr.t("Xabarlar") },
                { v: s.viewer_count, k: Tr.t("Ko'ruvchilar") }, { v: s.sender_count, k: Tr.t("Yozganlar") }]
    }
    function big(n) {
        n = Math.round(n)
        return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e4 ? (n / 1e3).toFixed(1) + "K" : String(n)
    }
    readonly property var curve: {          // [[x...], [y...]] of the members' graph, if it came whole
        const g = stats ? stats.member_count_graph : null
        if (!g || g["@type"] !== "statisticalGraphData")
            return null
        try {
            const d = JSON.parse(g.json_data)
            const x = d.columns.find((c) => c[0] === "x"), y = d.columns.find((c) => c[0] !== "x")
            return x && y ? [x.slice(1), y.slice(1)] : null
        } catch (e) { return null }
    }

    Text {
        visible: page.error !== "" || !page.stats
        x: 32; width: parent.width - 64
        topPadding: 30
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.error ? Tr.f("Statistikani olib bo'lmadi: %1", page.error) : Tr.t("Yuklanmoqda…")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    SettingsGroup {
        visible: !!page.stats
        title: Tr.t("Umumiy ko'rinish")
        note: page.stats ? Qt.formatDate(new Date(page.stats.period.start_date * 1000), "dd.MM.yyyy") + " – "
                           + Qt.formatDate(new Date(page.stats.period.end_date * 1000), "dd.MM.yyyy") : ""
        Grid {
            id: tilesGrid
            x: 16; width: parent.width - 32
            topPadding: 12; bottomPadding: 12
            columns: 2; rowSpacing: 14
            Repeater {
                model: page.tiles
                Column {
                    required property var modelData
                    readonly property var v: modelData.v
                    readonly property real growth: v ? v.value - v.previous_value : 0
                    width: tilesGrid.width / 2
                    spacing: 2
                    Row {
                        spacing: 6
                        Text {
                            text: parent.parent.modelData.pct !== undefined ? parent.parent.modelData.pct.toFixed(1) + "%"
                                  : page.big(parent.parent.v.value)
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: !!parent.parent.v && parent.parent.growth !== 0
                            anchors.baseline: parent.children[0].baseline
                            text: !parent.parent.v ? "" : (parent.parent.growth > 0 ? "+" : "−") + page.big(Math.abs(parent.parent.growth))
                                  + " (" + Math.abs(parent.parent.v.growth_rate_percentage).toFixed(1) + "%)"
                            color: parent.parent.growth > 0 ? "#34c759" : Theme.danger
                            font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    Text {
                        text: parent.modelData.k
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
            }
        }
    }
    SettingsGroup {
        visible: !!page.curve
        title: Tr.t(page.channel ? "Obunachilar o'sishi" : "A'zolar o'sishi")
        Canvas {
            id: plot
            width: parent.width; height: 180
            onPaint: {
                const c = getContext("2d"), cv = page.curve
                c.reset()
                if (!cv || cv[1].length < 2)
                    return
                const ys = cv[1], lo = Math.min(...ys), hi = Math.max(...ys), pad = 16
                const X = (i) => pad + (width - 2 * pad) * i / (ys.length - 1)
                const Y = (v) => height - pad - (height - 2 * pad) * (hi === lo ? 0.5 : (v - lo) / (hi - lo))
                c.strokeStyle = Theme.separator; c.lineWidth = 0.5
                for (let k = 0; k < 4; k++) {
                    const y = pad + (height - 2 * pad) * k / 3
                    c.beginPath(); c.moveTo(pad, y); c.lineTo(width - pad, y); c.stroke()
                }
                c.strokeStyle = Theme.accent; c.lineWidth = 2; c.lineJoin = "round"
                c.beginPath()
                ys.forEach((v, i) => i ? c.lineTo(X(i), Y(v)) : c.moveTo(X(i), Y(v)))
                c.stroke()
                c.fillStyle = Theme.grey; c.font = "11px sans-serif"
                c.fillText(page.big(hi), pad, pad - 4)
                c.fillText(page.big(lo), pad, height - 3)
            }
            Connections { target: page; function onCurveChanged() { plot.requestPaint() } }
            Connections { target: Theme; function onDarkChanged() { plot.requestPaint() } }
        }
    }
    SettingsGroup {
        visible: page.channel && (page.stats.recent_interactions || []).length > 0
        title: Tr.t("So'nggi postlar")
        Repeater {
            model: page.channel ? page.stats.recent_interactions || [] : []
            Item {
                required property var modelData
                required property int index
                readonly property var m: page.posts[modelData.object_type.message_id]
                width: parent.width; height: 58
                Text {
                    x: 16; y: 10; width: parent.width - x - viewsText.width - 28
                    elide: Text.ElideRight
                    text: parent.m ? store.preview(parent.m.content, page.chat) : "…"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15
                }
                Text {
                    x: 16; y: 32
                    text: parent.m ? Qt.formatDateTime(new Date(parent.m.date * 1000), "dd.MM hh:mm") : ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    id: viewsText
                    anchors.right: parent.right; anchors.rightMargin: 16; y: 10
                    text: Tr.n("%1 ko'rish", parent.modelData.view_count, page.big(parent.modelData.view_count))
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 16; y: 32
                    text: Tr.n("%1 ulashish", parent.modelData.forward_count) + (parent.modelData.reaction_count
                          ? " · " + Tr.n("%1 reaksiya", parent.modelData.reaction_count) : "")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Rectangle {
                    visible: parent.index < page.stats.recent_interactions.length - 1
                    x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator
                }
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
