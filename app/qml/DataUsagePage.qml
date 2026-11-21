// Trafik (Telegram-iOS's DataUsageScreen): what Telegram sent and got (getNetworkStatistics), as a ring by kind,
// the total in the middle and since when it is counted; Hammasi / Mobil / Wi-Fi (TDLib counts by the network type
// Store.tellNetwork gives it); the kinds with their share and size; the total sent and received; «Statistikani
// tiklash» (resetNetworkStatistics, asked first).
import QtQuick

SubPage {
    id: page
    title: Tr.t("Trafik")
    property var stats: null
    property int tab: 0                 // 0 all, 1 mobile, 2 Wi-Fi
    readonly property var kinds: [
        { k: "msg", t: Tr.t("Xabarlar"), c: "#5856d6", art: "data", types: ["", "fileTypeNone", "fileTypeUnknown", "fileTypeThumbnail", "fileTypeProfilePhoto", "fileTypeWallpaper", "fileTypeSecretThumbnail"] },
        { k: "video", t: Tr.t("Videolar"), c: "#3478f6", art: "videos", types: ["fileTypeVideo", "fileTypeAnimation", "fileTypeVideoStory", "fileTypeVideoNote"] },
        { k: "file", t: Tr.t("Fayllar"), c: "#34c759", art: "files", types: ["fileTypeDocument", "fileTypeSecure", "fileTypeSecret"] },
        { k: "call", t: Tr.t("Qo'ng'iroqlar"), c: "#30b0c7", art: "calls", types: [] },
        { k: "music", t: Tr.t("Musiqa"), c: "#ff3b30", art: "reactions", types: ["fileTypeAudio", "fileTypeNotificationSound"] },
        { k: "photo", t: Tr.t("Rasmlar"), c: "#5ac8fa", art: "photos", types: ["fileTypePhoto", "fileTypePhotoStory"] },
        { k: "sticker", t: Tr.t("Stikerlar"), c: "#ff9500", art: "stickers", types: ["fileTypeSticker"] },
        { k: "voice", t: Tr.t("Ovozli xabarlar"), c: "#af52de", art: "private", types: ["fileTypeVoiceNote"] }]
    function inTab(n) {
        const t = n ? n["@type"] : ""
        return tab === 0 || (tab === 1 && (t === "networkTypeMobile" || t === "networkTypeMobileRoaming")) || (tab === 2 && t === "networkTypeWiFi")
    }
    // kind -> { sent, got } in the chosen network
    readonly property var sums: {
        const out = {}
        for (const k of kinds)
            out[k.k] = { sent: 0, got: 0 }
        if (!stats)
            return out
        for (const e of stats.entries) {
            if (!inTab(e.network_type))
                continue
            let k = "call"
            if (e["@type"] === "networkStatisticsEntryFile") {
                const t = e.file_type ? e.file_type["@type"] : ""
                const f = kinds.find((x) => x.types.indexOf(t) >= 0)
                k = f ? f.k : "msg"
            }
            out[k].sent += e.sent_bytes
            out[k].got += e.received_bytes
        }
        return out
    }
    readonly property real sent: { let t = 0; for (const k of kinds) t += sums[k.k].sent; return t }
    readonly property real got: { let t = 0; for (const k of kinds) t += sums[k.k].got; return t }
    readonly property real total: sent + got

    Component.onCompleted: refresh()
    function refresh() {
        store.send({ "@type": "getNetworkStatistics", only_current: false }, (r) => {
            if (r["@type"] === "networkStatistics")
                page.stats = r
        })
    }
    function since() {
        if (!stats || !stats.since_date)
            return ""
        const d = new Date(stats.since_date * 1000)
        return Tr.f("Hisob %1 dan boshlangan", d.toLocaleDateString(Qt.locale(Tr.en ? "en_US" : "uz_UZ"), "d MMMM yyyy") + ", "
                    + d.toLocaleTimeString(Qt.locale(), "HH:mm"))
    }

    Item {
        width: parent.width; height: 320
        Donut {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter; y: 6
            width: 200; height: 200
            parts: page.kinds.map((k) => ({ v: page.sums[k.k].sent + page.sums[k.k].got, color: k.c }))
            center: page.stats ? store.size(page.total) : "..."
        }
        Text {
            id: head
            anchors.horizontalCenter: parent.horizontalCenter; y: ring.y + ring.height + 18
            text: Tr.t("Trafik")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
        }
        Text {
            id: sub
            x: 24; width: parent.width - 48; y: head.y + head.height + 6
            horizontalAlignment: Text.AlignHCenter
            text: page.since()
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 13
        }
        Segments {
            anchors.horizontalCenter: parent.horizontalCenter; y: sub.y + sub.height + 14
            width: 250
            items: [Tr.t("Hammasi"), Tr.t("Mobil"), "Wi-Fi"]
            index: page.tab
            onPicked: (i) => page.tab = i
        }
    }

    SettingsGroup {
        note: Tr.t("Turlar bo'yicha: yuborilgan va qabul qilingan birga.")
        Repeater {
            model: page.kinds
            SettingsRow {
                required property var modelData
                required property int index
                readonly property real v: page.sums[modelData.k].sent + page.sums[modelData.k].got
                art: modelData.art
                text: modelData.t + (v > 0 && page.total > 0 ? "  " + (v / page.total * 100).toFixed(1) + "%" : "")
                value: v > 0 ? store.size(v) : "0 B"
                chevron: false
                last: index === page.kinds.length - 1
            }
        }
    }
    SettingsGroup {
        title: Tr.t("JAMI TRAFIK")
        SettingsRow { art: "data"; text: Tr.t("Yuborilgan"); value: store.size(page.sent); chevron: false }
        SettingsRow { art: "traffic"; text: Tr.t("Qabul qilingan"); value: store.size(page.got); chevron: false; last: true }
    }
    SettingsGroup {
        SettingsRow {
            text: Tr.t("Statistikani tiklash"); danger: true; chevron: false; last: true
            onClicked: alert.show("", Tr.t("Trafik statistikasi nolga qaytarilsinmi?"),
                                  [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Tiklash"), red: true, run: () =>
                                      store.send({ "@type": "resetNetworkStatistics" }, () => page.refresh()) }])
        }
    }
    Item { width: 1; height: 20 }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
