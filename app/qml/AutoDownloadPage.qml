// Mobil internetda / Wi-Fi orqali (Telegram-iOS's AutoDownloadConnectionTypeController): «Mediani avtomatik
// yuklash», the DATA USAGE slider Low / Medium / High (TDLib's getAutoDownloadSettingsPresets: what each lets come
// down), then the kinds (photos, videos, files) with which chats and how big -> AutoMediaPage. Prefs.dl[network].
import QtQuick

SubPage {
    id: page
    property string network: "mobile"
    title: network === "mobile" ? Tr.t("Mobil internetda") : Tr.t("Wi-Fi orqali")
    readonly property var n: Prefs.dl[network]
    property var presets: null
    Component.onCompleted: store.send({ "@type": "getAutoDownloadSettingsPresets" }, (r) => {
        if (r["@type"] === "autoDownloadSettingsPresets")
            page.presets = r
    })
    function put(changes) {
        const v = JSON.parse(JSON.stringify(n))
        Object.assign(v, changes)
        Prefs.setDl(network, v)
    }
    function level(i) {
        const p = presets ? [presets.low, presets.medium, presets.high][i] : null
        const all = (on) => ({ contacts: on, others: on, groups: on, channels: on })
        // (without the presets: iOS's own, 1 / 10 / 25 MB of video, files from Medium)
        const video = p ? p.max_video_file_size : [0, 10485760, 26214400][i]
        const other = p ? p.max_other_file_size : [0, 1048576, 3145728][i]
        const photo = p ? p.max_photo_file_size > 0 : true
        put({ level: i, photo: all(photo), video: all(video > 0), file: all(other > 0),
              videoMax: video > 0 ? video : n.videoMax, fileMax: other > 0 ? other : n.fileMax })
    }
    function summary(kind) {
        const k = n[kind]
        const on = ["contacts", "others", "groups", "channels"].filter((w) => k[w])
        const size = kind === "video" ? n.videoMax : kind === "file" ? n.fileMax : 0
        if (!on.length)
            return Tr.t("Barcha chatlarda o'chiq")
        const where = on.length === 4 ? Tr.t("barcha chatlarda")
                    : on.map((w) => ({ contacts: Tr.t("kontaktlar"), others: Tr.t("boshqa shaxsiy chatlar"),
                                       groups: Tr.t("guruhlar"), channels: Tr.t("kanallar") })[w]).join(", ")
        return size ? Tr.f("%1 gacha, %2", store.size(size), where) : Tr.f("Yoqiq: %1", where)
    }
    function open(kind, name) {
        page.nav.push(Qt.createComponent("AutoMediaPage.qml"), { network: network, kind: kind, heading: name })
    }

    SettingsGroup {
        SettingsRow { text: Tr.t("Mediani avtomatik yuklash"); toggle: true; on: page.n.on; last: true; onClicked: page.put({ on: !page.n.on }) }
    }
    SettingsGroup {
        title: Tr.t("TRAFIK SARFI")
        StepSlider {
            labels: [Tr.t("Kam"), Tr.t("O'rtacha"), Tr.t("Ko'p")]
            value: page.n.level
            enabled2: page.n.on
            onMoved: (v) => page.level(v)
        }
    }
    SettingsGroup {
        title: Tr.t("MEDIA TURLARI")
        note: Tr.t("Ovozli xabarlar juda kichik, ular doim avtomatik yuklanadi.")
        opacity: page.n.on ? 1 : 0.5
        SettingsRow { art: "photos"; text: Tr.t("Rasmlar"); sub: page.summary("photo"); onClicked: page.open("photo", text) }
        SettingsRow { art: "videos"; text: Tr.t("Videolar"); sub: page.summary("video"); onClicked: page.open("video", text) }
        SettingsRow { art: "files"; text: Tr.t("Fayllar"); sub: page.summary("file"); last: true; onClicked: page.open("file", text) }
    }
    Item { width: 1; height: 20 }
}
