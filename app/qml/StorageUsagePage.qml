// Xotiradan foydalanish (Telegram-iOS's StorageUsageScreen): the ring of what the cache holds by kind, its size in
// the middle, the share of the free disk; the kinds ✓ (all at first) with their share and size; «Keshni tozalash N»
// clears the ticked kinds (optimizeStorage by file type; chats stay). AUTO-REMOVE CACHED MEDIA per kind of chat and
// the largest cache (Prefs.keep / maxCache, Store.keepClean). Then the chats by their cache (getStorageStatistics
// by_chat); a tap asks and clears that chat's files.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Xotira sarfi")
    property var stats: null
    property real db: 0
    property var disk: [0, 0]
    property var off: ({})          // the kinds unticked
    property bool busy: false
    property int got: 0             // (photos come)
    property var photos: ({})
    // the kinds as iOS groups TDLib's file types, with its colours
    readonly property var kinds: [
        { k: "video", t: Tr.t("Videolar"), c: "#3478f6", types: ["fileTypeVideo", "fileTypeAnimation", "fileTypeVideoStory"] },
        { k: "photo", t: Tr.t("Rasmlar"), c: "#5ac8fa", types: ["fileTypePhoto", "fileTypePhotoStory"] },
        { k: "file", t: Tr.t("Fayllar"), c: "#34c759", types: ["fileTypeDocument"] },
        { k: "music", t: Tr.t("Musiqa"), c: "#ff3b30", types: ["fileTypeAudio"] },
        { k: "voice", t: Tr.t("Ovozli xabarlar"), c: "#af52de", types: ["fileTypeVoiceNote", "fileTypeVideoNote"] },
        { k: "sticker", t: Tr.t("Stikerlar"), c: "#5856d6", types: ["fileTypeSticker"] },
        { k: "avatar", t: Tr.t("Profil rasmlari"), c: "#ffcc00", types: ["fileTypeProfilePhoto"] },
        { k: "misc", t: Tr.t("Boshqa"), c: "#ff9500", types: [] }]
    // kind -> bytes, from the stats (a type none above names: «Boshqa»)
    readonly property var bytes: {
        const out = {}
        for (const k of kinds)
            out[k.k] = 0
        if (!stats)
            return out
        for (const c of stats.by_chat)
            for (const f of c.by_file_type) {
                const k = kinds.find((x) => x.types.indexOf(f.file_type["@type"]) >= 0)
                out[k ? k.k : "misc"] += f.size
            }
        return out
    }
    readonly property real total: stats ? stats.size : 0
    readonly property var shown: kinds.filter((k) => bytes[k.k] > 0)
    readonly property real chosen: { let t = 0; for (const k of shown) if (!off[k.k]) t += bytes[k.k]; return t }
    readonly property var chats: stats ? stats.by_chat.filter((c) => c.chat_id !== 0 && c.size > 0).sort((a, b) => b.size - a.size) : []

    Component.onCompleted: refresh()
    function refresh() {
        try { disk = td.disk() } catch (e) { disk = [0, 0] }      // (the desk's td has none)
        store.send({ "@type": "getStorageStatistics", chat_limit: 100 }, (r) => {
            if (r["@type"] === "storageStatistics")
                page.stats = r
        })
        store.send({ "@type": "getStorageStatisticsFast" }, (r) => { if (r.database_size !== undefined) page.db = r.database_size })
    }
    function clearFiles(types, chatIds) {
        busy = true
        store.send({ "@type": "optimizeStorage", size: 0, ttl: 0, count: 0, immunity_delay: 0,
                     file_types: types.map((t) => ({ "@type": t })), chat_ids: chatIds, exclude_chat_ids: [],
                     return_deleted_file_statistics: false, chat_limit: 0 }, (r) => {
            page.busy = false
            page.refresh()
        })
    }
    function clearChosen() {
        // every ticked kind's types; «Boshqa» ticked: all the types not named above as well
        const named = [], types = []
        for (const k of kinds)
            for (const t of k.types)
                named.push(t)
        for (const k of shown)
            if (!off[k.k])
                for (const t of k.types)
                    types.push(t)
        if (!off.misc && bytes.misc > 0 && stats)
            for (const c of stats.by_chat)
                for (const f of c.by_file_type)
                    if (named.indexOf(f.file_type["@type"]) < 0 && types.indexOf(f.file_type["@type"]) < 0)
                        types.push(f.file_type["@type"])
        if (types.length)
            alert.show("", Tr.f("Tanlangan kesh tozalansinmi (%1)? Media Telegram bulutida qoladi va kerak bo'lsa qayta yuklanadi.", store.size(chosen)),
                       [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Tozalash"), red: true, run: () => page.clearFiles(types, []) }])
    }
    function keepName(s) {
        return s === 86400 ? Tr.t("1 kun") : s === 604800 ? Tr.t("1 hafta") : s === 2592000 ? Tr.t("1 oy") : Tr.t("Hech qachon")
    }
    function openKeep(g, name) {
        const p = page.nav.push(Qt.createComponent("ChoicePage.qml"), {
            heading: name, groupTitle: Tr.t("KESHDAGI MEDIANI O'CHIRISH"),
            note: Tr.t("Shuncha vaqt ochilmagan rasm, video va fayllar telefondan o'chiriladi (bulutda qoladi)."),
            choices: [{ t: Tr.t("1 kun"), v: 86400 }, { t: Tr.t("1 hafta"), v: 604800 }, { t: Tr.t("1 oy"), v: 2592000 },
                      { t: Tr.t("Hech qachon"), v: 0 }],
            value: Prefs.keep[g] || 0 })
        p.chosen.connect((v) => {
            const k = JSON.parse(JSON.stringify(Prefs.keep))
            k[g] = v
            Prefs.keepMedia = JSON.stringify(k)
            store.keepClean()
        })
    }
    function openMax() {
        const p = page.nav.push(Qt.createComponent("ChoicePage.qml"), {
            heading: Tr.t("Keshning eng katta hajmi"),
            note: Tr.t("Kesh shundan oshsa, eng uzoq ochilmagan fayllar o'chiriladi."),
            choices: [{ t: "5 GB", v: 5 }, { t: "16 GB", v: 16 }, { t: "32 GB", v: 32 }, { t: Tr.t("Cheksiz"), v: 0 }],
            value: Prefs.maxCache })
        p.chosen.connect((v) => { Prefs.maxCache = v; store.keepClean() })
    }
    function photoOf(c) {
        got
        if (photos[c.chat_id] !== undefined)
            return photos[c.chat_id]
        photos[c.chat_id] = ""
        const ch = store.chats[c.chat_id]
        if (ch && ch.photo && ch.photo.small)
            store.fetch(ch.photo.small, 1, (p) => { page.photos[c.chat_id] = p; page.got++ })
        return ""
    }

    // ---- the ring and its heading ----
    Item {
        width: parent.width; height: 330
        Donut {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter; y: 6
            width: 200; height: 200
            parts: page.shown.map((k) => ({ v: page.off[k.k] ? 0 : page.bytes[k.k], color: k.c }))
            center: page.stats ? store.size(page.chosen) : "..."
        }
        Text {
            id: head
            anchors.horizontalCenter: parent.horizontalCenter; y: ring.y + ring.height + 18
            text: Tr.t("Xotira sarfi")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
        }
        Text {
            id: share
            x: 24; width: parent.width - 48; y: head.y + head.height + 6
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: page.disk[0] > 0 ? Tr.f("Telegram bo'sh joyingizning %1% ini egallaydi.", ((page.total + page.db) / page.disk[0] * 100).toFixed(1))
                                   : Tr.f("Ma'lumotlar bazasi: %1", store.size(page.db))
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 13
        }
        Rectangle {         // the share as a thin bar
            anchors.horizontalCenter: parent.horizontalCenter; y: share.y + share.height + 10
            width: 200; height: 3; radius: 1.5
            color: Theme.separator
            Rectangle {
                height: parent.height; radius: 1.5; color: Theme.accent
                width: page.disk[1] > 0 ? Math.max(3, parent.width * (page.disk[1] - page.disk[0]) / page.disk[1]) : 0
            }
            Rectangle {
                height: parent.height; radius: 1.5; color: "#34c759"
                width: page.disk[1] > 0 ? Math.max(3, parent.width * (page.total + page.db) / page.disk[1]) : 0
            }
        }
    }

    // ---- the kinds ✓ and the button ----
    SettingsGroup {
        note: Tr.t("Barcha media Telegram bulutida qoladi va kerak bo'lsa qayta yuklanadi.")
        visible: page.shown.length > 0
        Repeater {
            model: page.shown
            Item {
                id: kind
                required property var modelData
                required property int index
                width: parent.width; height: 48
                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: page.off[kind.modelData.k] ? "transparent" : kind.modelData.c
                    border.width: page.off[kind.modelData.k] ? 1.5 : 0; border.color: Theme.separator
                    Icon { anchors.centerIn: parent; name: "check"; width: 14; height: 14; color: "white"; visible: !page.off[kind.modelData.k] }
                }
                Text {
                    x: 52; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - kindSize.width - 28
                    elide: Text.ElideRight
                    text: kind.modelData.t + "  <font color='" + Theme.grey + "'>"
                          + (page.total > 0 ? (page.bytes[kind.modelData.k] / page.total * 100).toFixed(1) : "0") + "%</font>"
                    textFormat: Text.StyledText
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17
                }
                Text {
                    id: kindSize
                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                    text: store.size(page.bytes[kind.modelData.k])
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 17
                }
                Rectangle { x: 52; width: parent.width - 52; height: 0.5; anchors.bottom: parent.bottom; color: Theme.separator }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const o = Object.assign({}, page.off)
                        o[kind.modelData.k] = !o[kind.modelData.k]
                        page.off = o
                    }
                }
            }
        }
        Item {
            width: parent.width; height: 70
            Rectangle {
                x: 16; width: parent.width - 32; height: 50; radius: 12
                anchors.verticalCenter: parent.verticalCenter
                color: page.chosen > 0 && !page.busy ? Theme.accent : Theme.grey
                opacity: clearHit.pressed ? 0.7 : 1
                Text {
                    anchors.centerIn: parent
                    text: page.busy ? Tr.t("Tozalanmoqda...")
                        : page.chosen >= page.total ? Tr.f("Barcha keshni tozalash  %1", store.size(page.chosen))
                        : Tr.f("Keshni tozalash  %1", store.size(page.chosen))
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea { id: clearHit; anchors.fill: parent; enabled: page.chosen > 0 && !page.busy; onClicked: page.clearChosen() }
            }
        }
    }
    SettingsGroup {
        title: Tr.t("KESHDAGI MEDIANI AVTOMATIK O'CHIRISH")
        SettingsRow { art: "private"; text: Tr.t("Shaxsiy chatlar"); value: page.keepName(Prefs.keep.private || 0); onClicked: page.openKeep("private", text) }
        SettingsRow { art: "groups"; text: Tr.t("Guruhlar"); value: page.keepName(Prefs.keep.groups || 0); onClicked: page.openKeep("groups", text) }
        SettingsRow { art: "channels"; text: Tr.t("Kanallar"); value: page.keepName(Prefs.keep.channels || 0); last: true; onClicked: page.openKeep("channels", text) }
    }
    SettingsGroup {
        title: Tr.t("KESHNING ENG KATTA HAJMI")
        note: Tr.t("Kesh shundan oshsa, eng uzoq ochilmagan fayllar o'chiriladi.")
        SettingsRow { text: Tr.t("Eng katta hajm"); value: Prefs.maxCache > 0 ? Prefs.maxCache + " GB" : Tr.t("Cheksiz"); last: true; onClicked: page.openMax() }
    }

    // ---- the chats by their cache ----
    SettingsGroup {
        title: Tr.t("CHATLAR")
        note: Tr.t("Chatni bossangiz, uning keshi tozalanadi.")
        visible: page.chats.length > 0
        Repeater {
            model: page.chats
            Item {
                id: chat
                required property var modelData
                required property int index
                readonly property var c: store.chats[modelData.chat_id]
                readonly property string name: c ? store.title(c) : String(modelData.chat_id)
                width: parent.width; height: 52
                Avatar {
                    id: av
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36
                    source: page.photoOf(chat.modelData)
                    letters: store.letters(chat.name)
                    tint: store.tints[Math.abs(Number(chat.modelData.chat_id)) % store.tints.length]
                    saved: !!(chat.c && store.me && chat.c.type.user_id === store.me.id)
                }
                Text {
                    x: 64; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - sizeText.width - 32
                    elide: Text.ElideRight
                    text: chat.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
                }
                Text {
                    id: sizeText
                    anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                    text: store.size(chat.modelData.size)
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
                Rectangle {
                    x: 64; width: parent.width - 64; height: 0.5; anchors.bottom: parent.bottom; color: Theme.separator
                    visible: chat.index < page.chats.length - 1
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: alert.show(chat.name, Tr.f("Bu chatning keshi tozalansinmi (%1)?", store.size(chat.modelData.size)),
                                          [{ t: Tr.t("Bekor qilish") },
                                           { t: Tr.t("Tozalash"), red: true, run: () => page.clearFiles([], [chat.modelData.chat_id]) }])
                }
            }
        }
    }
    Item { width: 1; height: 20 }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
