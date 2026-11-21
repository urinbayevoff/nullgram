// «Stikerlar va emoji» (iOS's «Stickers and Emoji»), as Telegram-iOS's InstalledStickerPacksController: «Trenddagi
// stikerlar» (the same page with `trending`: TDLib's getTrendingStickerSets, «Qo'shish» on each — changeStickerSet),
// «Katta emoji» (one to three emoji alone big, no bubble — Prefs.largeEmoji), then «STIKER TO'PLAMLARI»: the installed
// ones (getInstalledStickerSets) — the cover, the title, how many. «Tahrirlash» on the bar: a red ⊖ to remove one
// (asked first; changeStickerSet is_installed false) and ≡ to drag it to another place (reorderInstalledStickerSets).
// iOS's Archived, Masks, Emoji packs, Quick Reaction, Suggest by Emoji and Dynamic Pack Order wait.
import QtQuick

SubPage {
    id: page
    property bool trending: false
    property bool editing: false
    property var sets: []               // stickerSetInfo, in Telegram's order
    property var trend: []              // (the main page: the trending ones, for their count)
    property var paths: ({})            // file id -> its local path, once here
    property int got: 0
    title: trending ? Tr.t("Trenddagi stikerlar") : Tr.t("Stikerlar va emoji")
    action: trending || !sets.length ? "" : editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")
    actionBold: editing
    onActed: editing = !editing

    function load() {
        if (trending)
            store.send({ "@type": "getTrendingStickerSets", sticker_type: { "@type": "stickerTypeRegular" }, offset: 0, limit: 50 },
                       (r) => { page.sets = r.sets || [] })
        else {
            store.send({ "@type": "getInstalledStickerSets", sticker_type: { "@type": "stickerTypeRegular" } },
                       (r) => { page.sets = r.sets || [] })
            store.send({ "@type": "getTrendingStickerSets", sticker_type: { "@type": "stickerTypeRegular" }, offset: 0, limit: 50 },
                       (r) => { page.trend = r.sets || [] })
        }
    }
    Component.onCompleted: load()

    // a set's cover: its thumbnail, else its first sticker's still (StickerPanel's way)
    function coverOf(s) {
        if (s.thumbnail)
            return s.thumbnail.file
        const st = s.covers && s.covers[0]
        if (!st)
            return null
        const th = st.thumbnail
        return th ? th.file : st.format && st.format["@type"] === "stickerFormatWebp" ? st.sticker : null
    }
    function want(f) {
        if (!f || paths[f.id] !== undefined)
            return
        paths[f.id] = ""
        store.fetch(f, 2, (path) => { page.paths[f.id] = path; page.got++ })
    }
    function install(s, on) {
        store.send({ "@type": "changeStickerSet", set_id: s.id, is_installed: on, is_archived: false }, (r) => {
            if (r["@type"] === "error")
                return console.warn("nullgram: sticker set", r.message)
            if (trending)
                page.sets = page.sets.map((x) => x.id === s.id ? Object.assign({}, x, { is_installed: on }) : x)
            else if (!on)
                page.sets = page.sets.filter((x) => x.id !== s.id)
        })
    }
    function remove(s) {
        alert.show("", Tr.f("«%1» to'plami stikerlaringizdan o'chirilsinmi?", s.title),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () => page.install(s, false) }])
    }
    function move(from, to) {
        if (from === to || to < 0 || to >= sets.length)
            return
        const l = sets.slice()
        l.splice(to, 0, l.splice(from, 1)[0])
        sets = l
        store.send({ "@type": "reorderInstalledStickerSets", sticker_type: { "@type": "stickerTypeRegular" },
                     sticker_set_ids: l.map((x) => x.id) }, () => {})
    }

    SettingsGroup {
        visible: !page.trending
        SettingsRow {
            text: Tr.t("Trenddagi stikerlar"); last: true
            value: page.trend.length ? page.trend.length : ""
            onClicked: page.nav.push(Qt.createComponent("StickersPage.qml"), { trending: true })
        }
    }
    SettingsGroup {
        visible: !page.trending
        note: Tr.t("Bittadan uchtagacha yolg'iz emoji katta, pufakchasiz ko'rinadi.")
        SettingsRow { text: Tr.t("Katta emoji"); toggle: true; on: Prefs.largeEmoji; last: true; onClicked: Prefs.largeEmoji = !Prefs.largeEmoji }
    }
    SettingsGroup {
        visible: page.sets.length > 0
        title: page.trending ? "" : Tr.t("Stiker to'plamlari")
        note: page.trending ? "" : Tr.t("Tartibini o'zgartirish yoki o'chirish uchun «Tahrirlash»ni bosing.")
        Column {
            id: list
            width: parent.width
            Repeater {
                model: page.sets
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var cover: page.coverOf(modelData)
                    readonly property string path: { page.got; return cover ? page.paths[cover.id] || "" : "" }
                    Component.onCompleted: page.want(cover)
                    width: list.width; height: 58
                    z: grip.active ? 2 : 0
                    Rectangle {
                        anchors.fill: parent
                        color: grip.active ? Theme.card : "transparent"
                        Rectangle {     // ⊖
                            id: minus
                            x: page.editing ? 14 : -30; anchors.verticalCenter: parent.verticalCenter
                            Behavior on x { NumberAnimation { duration: 200 } }
                            width: 22; height: 22; radius: 11
                            color: "#ff3b30"
                            Rectangle { anchors.centerIn: parent; width: 10; height: 2; color: "white" }
                            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.remove(row.modelData) }
                        }
                        Image {
                            id: pic
                            x: page.editing ? 48 : 16; anchors.verticalCenter: parent.verticalCenter
                            Behavior on x { NumberAnimation { duration: 200 } }
                            width: 36; height: 36
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize: Qt.size(72, 72)
                            source: !row.path ? "" : /\.tgs$/i.test(row.path) ? "image://lottie/0/-/" + row.path : "image://thumb/" + row.path
                        }
                        Text {
                            id: name
                            x: pic.x + 50; y: 10
                            width: parent.width - x - (page.trending ? 100 : page.editing ? 50 : 16)
                            elide: Text.ElideRight
                            text: row.modelData.title
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        Text {
                            x: name.x; y: 32
                            text: Tr.n("%1 ta stiker", row.modelData.size)
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        Rectangle {     // «Qo'shish» (the trending page)
                            visible: page.trending
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            width: addText.implicitWidth + 24; height: 28; radius: 14
                            color: row.modelData.is_installed ? "transparent" : Theme.accent
                            Text {
                                id: addText
                                anchors.centerIn: parent
                                text: row.modelData.is_installed ? Tr.t("Qo'shilgan") : Tr.t("Qo'shish")
                                color: row.modelData.is_installed ? Theme.grey : "white"
                                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; enabled: !row.modelData.is_installed; onClicked: page.install(row.modelData, true) }
                        }
                        Text {          // ≡ — drag it up or down
                            visible: page.editing
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            text: "≡"
                            color: Theme.grey
                            font.pixelSize: 26
                            DragHandler {
                                id: grip
                                target: null
                                yAxis.enabled: true; xAxis.enabled: false
                                onActiveChanged: {
                                    if (active)
                                        return
                                    const to = Math.max(0, Math.min(page.sets.length - 1, row.index + Math.round(row.lift / row.height)))
                                    row.lift = 0
                                    page.move(row.index, to)
                                }
                                onTranslationChanged: row.lift = translation.y
                            }
                        }
                        Rectangle {
                            visible: row.index < page.sets.length - 1
                            x: name.x; anchors.bottom: parent.bottom
                            width: parent.width - x; height: 0.5
                            color: Theme.separator
                        }
                    }
                    property real lift: 0
                    transform: Translate { y: row.lift }
                }
            }
        }
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
