// The field's 🙂: emoji, stickers and GIFs where the keyboard was (Telegram-iOS's EntityKeyboard,
// TelegramUI/Components/EntityKeyboard): the packs or categories in a strip at the top, the grid under
// it, the three tabs at the foot (⌫ beside them on Emoji). An emoji goes into the field; a sticker or a
// GIF is sent at once, the panel staying open (as on iOS). What TDLib has is asked the first time the
// panel opens: the recent and favourite stickers, the installed packs and each pack's stickers, the
// saved GIFs. TGS (Lottie) stickers show their first frame (libtlottie); they play in the chat.
import QtQuick
import QtQuick.Window
import "Emoji.js" as Emoji

Rectangle {
    id: panel
    property var store
    property bool emojiOk: true         // the field takes text (not barred)
    property bool stickersOk: true      // stickers and GIFs may be sent here (rights.other)
    property string barredText: ""      // why not, when not
    property string tab: "emoji"        // emoji, stickers, gifs
    signal emoji(string e)
    signal backspace()
    signal sticker(var st)
    signal gif(var anim)

    color: Theme.keys
    Rectangle { width: parent.width; height: 0.5; color: Theme.separator }

    // ---- what TDLib has, asked once ----------------------------------------------
    property bool loaded: false
    property var sets: []               // [{ id, title, icon (a sticker), stickers }] in the order shown
    property var gifs: []
    property var paths: ({})            // file id -> its local path, once here (a delegate's picture binds to it)
    property int got: 0                 // bumped when `paths` grows
    function load() {
        if (loaded || !store)
            return
        loaded = true
        let faves = [], recent = [], installed = null
        const byId = {}
        let waiting = 3
        const built = () => {
            if (--waiting > 0)
                return
            const out = []
            if (faves.length)
                out.push({ id: "faves", title: Tr.t("Sevimlilar"), mark: "⭐", stickers: faves })
            if (recent.length)
                out.push({ id: "recent", title: Tr.t("Yaqinda ishlatilgan"), mark: "🕘", stickers: recent.slice(0, 20) })
            for (const s of installed || [])
                out.push(byId[s.id] || { id: s.id, title: s.title, stickers: [], cover: s.covers && s.covers[0] })
            sets = out
            // each pack's stickers, one by one in the order shown (the strip and the rows fill as they come)
            for (const s of installed || [])
                store.send({ "@type": "getStickerSet", set_id: s.id }, (r) => {
                    if (r["@type"] !== "stickerSet")
                        return
                    const k = panel.sets.findIndex((x) => x.id === r.id)
                    if (k < 0)
                        return
                    const copy = panel.sets.slice()
                    copy[k] = { id: r.id, title: r.title, stickers: r.stickers }
                    panel.sets = copy
                })
        }
        store.send({ "@type": "getFavoriteStickers" }, (r) => { faves = r.stickers || []; built() })
        store.send({ "@type": "getRecentStickers", is_attached: false }, (r) => { recent = r.stickers || []; built() })
        store.send({ "@type": "getInstalledStickerSets", sticker_type: { "@type": "stickerTypeRegular" } },
                   (r) => { installed = r.sets || []; built() })
        store.send({ "@type": "getSavedAnimations" }, (r) => { panel.gifs = r.animations || [] })
    }

    // a sticker's or a GIF's still: its thumbnail, a WEBP sticker itself; brought down when first shown
    function stillOf(st) {
        const th = st.thumbnail
        const f = th && th.format["@type"]
        if (f === "thumbnailFormatWebp" || f === "thumbnailFormatJpeg" || f === "thumbnailFormatPng" || f === "thumbnailFormatTgs")
            return th.file
        return st.format && st.format["@type"] === "stickerFormatWebp" ? st.sticker : null
    }
    // the still drawn: a TGS thumbnail (a small Lottie) its first frame, by libtlottie; any other the picture itself
    function stillUrl(path) {
        return /\.tgs$/i.test(path) ? "image://lottie/0/-/" + path : "image://thumb/" + path
    }
    function want(f) {
        if (!f || paths[f.id] !== undefined)
            return
        paths[f.id] = ""
        store.fetch(f, 2, (path) => {
            panel.paths[f.id] = path
            panel.got++
        })
    }

    // ---- the rows the grid shows: a title, then cells ----------------------------
    readonly property real cell: (width - 12) / (tab === "emoji" ? 8 : tab === "stickers" ? 5 : 3)
    // «Yaqinda» as it was when the panel opened: kept still while it is open (the grid made again under
    // the finger at each pick would lose its place, and the cell tapped with it)
    property var recentEmoji: []
    function remember(e) {
        const r = (Prefs.recentEmoji ? Prefs.recentEmoji.split(" ") : []).filter((x) => x !== e)
        r.unshift(e)
        Prefs.recentEmoji = r.slice(0, 24).join(" ")
    }
    onVisibleChanged: if (visible) recentEmoji = Prefs.recentEmoji ? Prefs.recentEmoji.split(" ") : []
    // [{ head, items, section }]; `starts`: the row each section begins at (the strip jumps there)
    readonly property var rows: {
        const out = [], starts = []
        const add = (title, items, per) => {
            starts.push(out.length)
            if (title)
                out.push({ head: title, items: [] })
            for (let k = 0; k < items.length; k += per)
                out.push({ head: "", items: items.slice(k, k + per) })
        }
        if (tab === "emoji") {
            add(Tr.t("Yaqinda ishlatilgan"), recentEmoji.length ? recentEmoji : ["😂", "❤️", "👍", "😍", "🔥", "😭", "🙏", "😊"], 8)
            for (const c of Emoji.categories)
                add(Tr.t(c.title), c.list.split(" "), 8)
        } else if (tab === "stickers") {
            for (const s of sets)
                add(s.title, s.stickers, 5)
        } else {
            add("", gifs, 3)
        }
        return { list: out, starts: starts }
    }
    // the strip's marks: an emoji category's, a pack's first sticker (or ⭐, 🕘)
    readonly property var marks: tab === "emoji" ? [{ t: "🕘" }].concat(Emoji.categories.map((c) => ({ t: c.icon })))
                               : tab === "stickers" ? sets.map((s) => s.mark ? { t: s.mark } : { st: s.stickers[0] || s.cover || null })
                               : []
    property int section: 0             // the strip's lit mark: the section at the grid's top
    onTabChanged: { grid.positionViewAtBeginning(); section = 0 }

    Item {               // the strip: tapped, the grid goes to that section
        id: strip
        y: 0.5
        width: parent.width; height: panel.tab === "gifs" ? 0 : 40
        visible: height > 0
        ListView {
            id: stripList
            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
            orientation: ListView.Horizontal
            model: panel.marks
            clip: true
            delegate: Item {
                required property var modelData
                required property int index
                width: 40; height: 40
                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32; radius: 9
                    color: index === panel.section ? Theme.highlight : "transparent"
                }
                Image {          // the category mark as an Apple image (Modified for OmonullOS, 2026-11)
                    id: markImg
                    visible: !!modelData.t && source != ""
                    anchors.centerIn: parent
                    width: 24; height: 24
                    sourceSize: Qt.size(Math.ceil(24 * Screen.devicePixelRatio), Math.ceil(24 * Screen.devicePixelRatio))
                    asynchronous: true
                    source: modelData.t ? Emo.fileUrl(modelData.t) : ""
                    opacity: index === panel.section ? 1 : 0.55
                }
                Text {
                    visible: !!modelData.t && !markImg.visible
                    anchors.centerIn: parent
                    text: modelData.t || ""
                    font.pixelSize: 20
                    opacity: index === panel.section ? 1 : 0.55
                }
                Image {
                    visible: !modelData.t
                    anchors.centerIn: parent
                    width: 26; height: 26
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(Math.ceil(26 * Screen.devicePixelRatio), Math.ceil(26 * Screen.devicePixelRatio))
                    readonly property var f: modelData.st ? panel.stillOf(modelData.st) : null
                    source: f && (panel.got, panel.paths[f.id]) ? panel.stillUrl(panel.paths[f.id]) : ""
                    Component.onCompleted: panel.want(f)
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        panel.section = index
                        grid.positionViewAtIndex(panel.rows.starts[index] || 0, ListView.Beginning)
                    }
                }
            }
        }
    }

    ListView {           // the grid, by rows (a ListView of rows: only the rows in sight are made)
        id: grid
        x: 6; y: strip.y + strip.height
        width: parent.width - 12; height: tabs.y - y
        clip: true
        visible: panel.tab === "emoji" ? panel.emojiOk : panel.stickersOk
        model: panel.rows.list
        cacheBuffer: 200
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: {
            const at = indexAt(10, contentY + 4)
            if (at < 0)
                return
            const s = panel.rows.starts
            let k = 0
            while (k + 1 < s.length && s[k + 1] <= at)
                k++
            panel.section = k
            stripList.positionViewAtIndex(k, ListView.Contain)
        }
        delegate: Item {
            id: rowItem
            required property var modelData
            width: grid.width
            height: modelData.head ? 30 : panel.tab === "gifs" ? panel.cell * 0.8 : panel.cell
            Text {
                visible: !!modelData.head
                x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                text: modelData.head
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
            }
            Row {
                visible: !modelData.head
                Repeater {
                    model: modelData.items
                    delegate: Item {
                        id: one
                        required property var modelData
                        width: panel.cell; height: rowItem.height
                        readonly property bool isEmoji: typeof modelData === "string"
                        // a GIF's or a sticker's still (the thumbnail, a WEBP sticker itself)
                        readonly property var f: isEmoji ? null : panel.tab === "gifs"
                            ? (modelData.thumbnail ? modelData.thumbnail.file : null) : panel.stillOf(modelData)
                        Component.onCompleted: panel.want(f)
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 2
                            radius: 8
                            color: hit.pressed ? Theme.highlight : panel.tab === "gifs" ? Qt.rgba(0.5, 0.5, 0.5, 0.15) : "transparent"
                        }
                        Image {          // the emoji as an Apple image (Modified for OmonullOS, 2026-11)
                            id: emoImg
                            visible: one.isEmoji && source != ""
                            anchors.centerIn: parent
                            width: 30; height: 30
                            sourceSize: Qt.size(Math.ceil(30 * Screen.devicePixelRatio), Math.ceil(30 * Screen.devicePixelRatio))
                            asynchronous: true
                            source: one.isEmoji ? Emo.fileUrl(one.modelData) : ""
                        }
                        Text {           // fallback: the system font, when the Apple set has no such emoji
                            visible: one.isEmoji && !emoImg.visible
                            anchors.centerIn: parent
                            text: one.isEmoji ? one.modelData : ""
                            font.pixelSize: 28
                        }
                        Image {          // a GIF's tiny preview first
                            visible: panel.tab === "gifs" && status === Image.Ready && pic.status !== Image.Ready
                            anchors.fill: parent; anchors.margins: 2
                            source: panel.tab === "gifs" && one.modelData.minithumbnail
                                    ? "image://pic/8/" + Math.round(width) + "/mini/" + one.modelData.minithumbnail.data : ""
                            sourceSize: Qt.size(width, height)
                        }
                        Image {
                            id: pic
                            visible: !one.isEmoji
                            anchors.fill: parent; anchors.margins: panel.tab === "gifs" ? 2 : 4
                            fillMode: panel.tab === "gifs" ? Image.Stretch : Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize: Qt.size(Math.round(width) * 2, Math.round(height) * 2)
                            readonly property string path: one.f ? (panel.got, panel.paths[one.f.id] || "") : ""
                            source: !path ? "" : panel.tab === "gifs"
                                    ? "image://pic/8/" + Math.round(width) + "/" + path : panel.stillUrl(path)
                        }
                        MouseArea {
                            id: hit
                            anchors.fill: parent
                            onClicked: {
                                if (one.isEmoji) {
                                    panel.emoji(one.modelData)
                                    panel.remember(one.modelData)
                                } else if (panel.tab === "gifs") {
                                    panel.gif(one.modelData)
                                } else {
                                    panel.sticker(one.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Text {               // nothing to show: why
        anchors.centerIn: grid
        width: parent.width - 48
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: !grid.visible || (panel.loaded && panel.tab !== "emoji" && panel.rows.list.length === 0)
        text: !grid.visible ? (panel.tab === "emoji" ? Tr.t("Bu yerda matn yozib bo'lmaydi") : panel.barredText)
            : panel.tab === "stickers" ? Tr.t("Stikerlar to'plami yo'q") : Tr.t("Saqlangan GIF yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    Item {               // the foot: the three tabs, ⌫ on Emoji
        id: tabs
        y: parent.height - height
        width: parent.width; height: 44
        Row {
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: [{ k: "emoji", t: Tr.t("Emoji") }, { k: "stickers", t: Tr.t("Stikerlar") }, { k: "gifs", t: "GIF" }]
                Rectangle {
                    required property var modelData
                    width: word.implicitWidth + 24; height: 30; radius: 15
                    color: panel.tab === modelData.k ? Theme.highlight : "transparent"
                    Text {
                        id: word
                        anchors.centerIn: parent
                        text: parent.modelData.t
                        color: panel.tab === parent.modelData.k ? Theme.text : Theme.grey
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.tab = parent.modelData.k }
                }
            }
        }
        Text {
            visible: panel.tab === "emoji" && panel.emojiOk
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: "⌫"
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 22
            MouseArea {
                anchors.fill: parent; anchors.margins: -12
                onPressed: panel.backspace()
                onPressAndHold: wipe.start()
                onReleased: wipe.stop()
                onCanceled: wipe.stop()
            }
            Timer { id: wipe; interval: 90; repeat: true; onTriggered: panel.backspace() }
        }
    }
}
