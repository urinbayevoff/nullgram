// Ma'lumotlar va xotira (Telegram-iOS's DataAndStorageSettingsController): Storage Usage and Data Usage with their
// sizes, AUTOMATIC MEDIA DOWNLOAD (Using Cellular / Using Wi-Fi, Reset), SAVE TO PHOTOS (private / groups /
// channels -> ~/Downloads here), OTHER (Pause Music While Recording; our GIF and voice switches), CONNECTION TYPE
// (Proxy). iOS's Use Less Data for Calls, Share Sheet, Save Edited Photos and Raise to Listen are left out: no calls,
// no share sheet or photo editor, no proximity sensor here.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Ma'lumotlar va xotira")
    property real stored: -1
    property real traffic: -1
    property var proxy: null            // the enabled one, if any
    Component.onCompleted: refresh()
    function refresh() {
        store.send({ "@type": "getStorageStatisticsFast" }, (r) => {
            if (r["@type"] === "storageStatisticsFast")
                page.stored = r.files_size + r.database_size
        })
        store.send({ "@type": "getNetworkStatistics", only_current: false }, (r) => {
            if (r["@type"] !== "networkStatistics")
                return
            let t = 0
            for (const e of r.entries)
                t += e.sent_bytes + e.received_bytes
            page.traffic = t
        })
        store.send({ "@type": "getProxies" }, (r) => {
            page.proxy = null
            for (const p of r.proxies || [])
                if (p.is_enabled)
                    page.proxy = p
        })
    }
    // the shown words of one network's auto-download: «Media (2.5 MB), Fayllar (3.0 MB)», «O'chiq»
    function dlSummary(n) {
        if (!n.on)
            return Tr.t("O'chiq")
        const any = (k) => n[k].contacts || n[k].others || n[k].groups || n[k].channels
        const out = []
        if (any("photo") || any("video"))
            out.push(any("video") ? Tr.f("Media (%1)", store.size(n.videoMax)) : Tr.t("Media"))
        if (any("file"))
            out.push(Tr.f("Fayllar (%1)", store.size(n.fileMax)))
        return out.length ? out.join(", ") : Tr.t("O'chiq")
    }
    function saveSummary(g) {
        const w = Prefs.saveTo[g]
        if (!w || (!w.photo && !w.video))
            return Tr.t("O'chiq")
        return w.photo && w.video ? Tr.t("Rasm va video") : w.photo ? Tr.t("Rasmlar") : Tr.t("Videolar")
    }
    function openDl(network) {
        page.nav.push(Qt.createComponent("AutoDownloadPage.qml"), { network: network })
    }
    function openSave(g, name) {
        page.nav.push(Qt.createComponent("SaveMediaPage.qml"), { group: g, heading: name })
    }

    SettingsGroup {
        SettingsRow {
            art: "storage"; text: Tr.t("Xotira sarfi")
            value: page.stored >= 0 ? store.size(page.stored) : ""
            onClicked: page.nav.push(Qt.createComponent("StorageUsagePage.qml"), {})
        }
        SettingsRow {
            art: "traffic"; text: Tr.t("Trafik"); last: true
            value: page.traffic >= 0 ? store.size(page.traffic) : ""
            onClicked: page.nav.push(Qt.createComponent("DataUsagePage.qml"), {})
        }
    }
    SettingsGroup {
        title: Tr.t("MEDIANI AVTOMATIK YUKLASH")
        SettingsRow { art: "cellular"; text: Tr.t("Mobil internetda"); sub: page.dlSummary(Prefs.dl.mobile); onClicked: page.openDl("mobile") }
        SettingsRow { art: "wifi"; text: Tr.t("Wi-Fi orqali"); sub: page.dlSummary(Prefs.dl.wifi); onClicked: page.openDl("wifi") }
        SettingsRow {
            text: Tr.t("Avto-yuklashni tiklash"); chevron: false; last: true
            dim: Prefs.autoDl === ""
            accent: Prefs.autoDl !== ""
            onClicked: if (Prefs.autoDl !== "")
                alert.show("", Tr.t("Avtomatik yuklash sozlamalari odatiy holatiga qaytarilsinmi?"),
                           [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Tiklash"), red: true, run: () => Prefs.autoDl = "" }])
        }
    }
    SettingsGroup {
        title: Tr.t("GALEREYAGA SAQLASH")
        note: Tr.t("Shu chatlarga kelgan yangi rasm va videolar Downloads jildiga o'zi saqlanadi.")
        SettingsRow { art: "private"; text: Tr.t("Shaxsiy chatlar"); value: page.saveSummary("private"); onClicked: page.openSave("private", text) }
        SettingsRow { art: "groups"; text: Tr.t("Guruhlar"); value: page.saveSummary("groups"); onClicked: page.openSave("groups", text) }
        SettingsRow { art: "channels"; text: Tr.t("Kanallar"); value: page.saveSummary("channels"); last: true; onClicked: page.openSave("channels", text) }
    }
    SettingsGroup {
        title: Tr.t("BOSHQA")
        note: Tr.t("GIF va video-stikerlar; ovozli xabarlar va dumaloq videolar. O'chirilsa, bosilgandagina yuklanadi.")
        SettingsRow { text: Tr.t("Yozishda musiqa to'xtasin"); toggle: true; on: Prefs.pauseMusic; onClicked: Prefs.pauseMusic = !Prefs.pauseMusic }
        SettingsRow { text: Tr.t("GIF'lar o'zi o'ynasin"); toggle: true; on: Prefs.autoGif; onClicked: Prefs.autoGif = !Prefs.autoGif }
        SettingsRow { text: Tr.t("Ovozli va dumaloq videolar"); toggle: true; on: Prefs.autoVoice; last: true; onClicked: Prefs.autoVoice = !Prefs.autoVoice }
    }
    SettingsGroup {
        title: Tr.t("ULANISH TURI")
        SettingsRow {
            art: "proxy"; text: Tr.t("Proksi")
            value: page.proxy ? page.proxy.server : Tr.t("Yo'q")
            onClicked: {
                const p = page.nav.push(Qt.createComponent("ProxyPage.qml"), {})
                if (p)
                    p.changed.connect(page.refresh)
            }
        }
        SettingsRow {
            art: "passcode"; text: Tr.t("API kaliti"); last: true
            value: td.keySource === "own" ? Tr.t("O'zingizniki") : Tr.t("Nullgram'niki")
            onClicked: page.nav.push(Qt.createComponent("ApiKeyPage.qml"), {})
        }
    }
    Item { width: 1; height: 20 }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
