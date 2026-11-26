// The field's 🙂: emoji, stickers and GIFs where the keyboard was (Telegram-iOS's EntityKeyboard,
// TelegramUI/Components/EntityKeyboard): search bar at the top on Stickers/GIFs, the packs or categories
// in a strip under it, the grid under that, the three tabs at the foot (⌫ beside them on Emoji).
// An emoji goes into the field; a sticker or a GIF is sent at once, the panel staying open (as on iOS).
// What TDLib has is asked the first time the panel opens: the recent and favourite stickers, the installed
// packs and each pack's stickers, the saved GIFs. TGS (Lottie) stickers show their first frame (libtlottie);
// they play in the chat and in StickerSetSheet.
import QtQuick
import QtQuick.Window
import "Emoji.js" as Emoji

Rectangle {
    id: panel
    property var store
    property var chatId: 0
    property bool emojiOk: true         // the field takes text (not barred)
    property bool stickersOk: true      // stickers and GIFs may be sent here (rights.other)
    property string barredText: ""      // why not, when not
    property string tab: "emoji"        // emoji, stickers, gifs
    signal emoji(string e)
    signal backspace()
    signal sticker(var st)
    signal gif(var anim)
    signal inlineGif(string queryId, string resultId, var anim)
    signal openStickerSet(string setId)
    signal say(string text)

    color: Theme.keys
    Rectangle { width: parent.width; height: 0.5; color: Theme.separator }

    readonly property real safeBottom: (typeof osk !== "undefined" && osk && osk.h > 0)
                                       ? 0 : (typeof safe !== "undefined" && safe ? safe.bottom : 0)

    // ---- what TDLib has, asked once ----------------------------------------------
    property bool loaded: false
    property var sets: []               // [{ id, title, icon (a sticker), stickers }] in the order shown
    property var gifs: []
    property var paths: ({})            // file id -> its local path, once here (a delegate's picture binds to it)
    property int got: 0                 // bumped when `paths` grows

    function loadSets() {
        if (!store)
            return
        let faves = [], recent = [], installed = null
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
                out.push({ id: s.id, title: s.title, stickers: [], cover: s.covers && s.covers[0] })
            sets = out
            // each pack's stickers, one by one in the order shown (the strip and the rows fill as they come)
            for (const s of installed || [])
                store.send({ "@type": "getStickerSet", set_id: s.id }, (r) => {
                    if (!panel || r["@type"] !== "stickerSet")
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
    }

    function load() {
        if (loaded || !store)
            return
        loaded = true
        loadSets()
        store.send({ "@type": "getSavedAnimations" }, (r) => { if (panel) panel.gifs = r.animations || [] })
    }

    Connections {
        target: panel.store
        enabled: !!panel.store && panel.loaded
        function onInstalledStickerSetsChanged(_stickerType, _setIds) {
            panel.loadSets()
            if (panel.foundRemoteSets.length)
                panel.syncInstalledBadges(_setIds)
        }
    }

    function syncInstalledBadges(setIds) {
        if (!Array.isArray(setIds))
            return
        const map = {}
        for (const id of setIds)
            map[String(id)] = true
        foundRemoteSets = foundRemoteSets.map((s) => Object.assign({}, s, { is_installed: !!map[String(s.id)] }))
    }

    // ---- search state (Stickers & GIFs) ------------------------------------------
    property string searchQuery: ""
    property bool searching: false
    property int _searchSeq: 0
    property var foundLocalStickers: []
    property var foundRemoteSets: []
    property var foundSavedGifs: []
    property var foundInlineGifs: []
    property var _installing: ({})
    readonly property bool searchActive: (tab === "stickers" || tab === "gifs") && stickersOk && searchQuery !== ""
    readonly property alias searchInput: searchField

    function blurSearch() {
        searchField.focus = false
    }

    function clearSearch() {
        searchField.text = ""
        searchQuery = ""
        _searchSeq += 1
        searchDebounce.stop()
        searching = false
        foundLocalStickers = []
        foundRemoteSets = []
        foundSavedGifs = []
        foundInlineGifs = []
    }

    function dismissSearch() {
        if (searchField.activeFocus || searchField.text !== "") {
            clearSearch()
            searchField.focus = false
            if (typeof osk !== "undefined" && osk && osk.h > 0)
                osk.hide()
            return true
        }
        return false
    }

    function onSearchTextChanged() {
        const q = searchField.text.trim()
        searchQuery = q
        _searchSeq += 1
        if (!q) {
            searchDebounce.stop()
            searching = false
            foundLocalStickers = []
            foundRemoteSets = []
            foundSavedGifs = []
            foundInlineGifs = []
            return
        }
        searching = true
        searchDebounce.restart()
    }

    Timer {
        id: searchDebounce
        interval: 400
        repeat: false
        onTriggered: panel.runSearch()
    }

    function _stickerKey(st) {
        if (!st)
            return ""
        if (st.id && String(st.id) !== "0")
            return "id:" + String(st.id)
        if (st.sticker && st.sticker.id)
            return "f:" + String(st.sticker.id)
        return ""
    }

    function _dedupeStickers(lists) {
        const seen = {}
        const out = []
        for (const list of lists) {
            for (const st of (list || [])) {
                const k = _stickerKey(st)
                if (k && seen[k])
                    continue
                if (k)
                    seen[k] = true
                out.push(st)
            }
        }
        return out
    }

    function _installedSetMap() {
        const map = {}
        for (const s of sets)
            if (s && s.id && s.id !== "faves" && s.id !== "recent")
                map[String(s.id)] = true
        return map
    }

    function runSearch() {
        if (!store)
            return
        const q = searchQuery
        if (!q) {
            searching = false
            return
        }
        const seq = _searchSeq
        const curTab = tab
        if (curTab === "stickers") {
            const ql = q.toLowerCase()
            const mem = []
            for (const s of sets) {
                const titleHit = s.title && s.title.toLowerCase().indexOf(ql) >= 0
                for (const st of (s.stickers || [])) {
                    if (titleHit || (st.emoji && st.emoji.indexOf(q) >= 0))
                        mem.push(st)
                }
            }
            let localRes = []
            let remoteRes = []
            let pending = 3
            const mergeStickers = () => {
                panel.foundLocalStickers = panel._dedupeStickers([localRes, mem, remoteRes])
            }
            const doneOne = () => {
                if (!panel || seq !== panel._searchSeq || panel.tab !== "stickers")
                    return
                if (--pending <= 0)
                    panel.searching = false
            }
            const isEmojiQuery = Emo.hint.test(q)
            store.searchStickersLocal(q, chatId, 40, (list) => {
                if (!panel || seq !== panel._searchSeq || panel.tab !== "stickers")
                    return
                localRes = list || []
                mergeStickers()
                doneOne()
            })
            store.searchStickersRemote(isEmojiQuery ? q : "", isEmojiQuery ? "" : q, 0, 30, (list) => {
                if (!panel || seq !== panel._searchSeq || panel.tab !== "stickers")
                    return
                remoteRes = list || []
                mergeStickers()
                doneOne()
            })
            store.searchStickerSets(q, (setList) => {
                if (!panel || seq !== panel._searchSeq || panel.tab !== "stickers")
                    return
                const mine = panel._installedSetMap()
                panel.foundRemoteSets = (setList || []).map((s) => Object.assign({}, s, {
                    is_installed: !!(s.is_installed || mine[String(s.id)])
                }))
                doneOne()
            })
        } else if (curTab === "gifs") {
            const ql = q.toLowerCase()
            foundSavedGifs = (gifs || []).filter((a) => {
                if (!a)
                    return false
                const fn = (a.file_name || "").toLowerCase()
                const tg = (a._tags || "").toLowerCase()
                return (fn && fn.indexOf(ql) >= 0) || (tg && tg.indexOf(ql) >= 0)
            })
            store.searchGifInline(chatId, q, "", (_qid, items, _next, _err) => {
                if (!panel || seq !== panel._searchSeq || panel.tab !== "gifs")
                    return
                panel.foundInlineGifs = (items || []).map((it) => Object.assign({ _inline: true }, it))
                panel.searching = false
            })
        } else {
            searching = false
        }
    }

    function installFoundSet(setObj) {
        if (!store || !setObj || !setObj.id || setObj.is_installed)
            return
        const sid = String(setObj.id)
        if (_installing[sid])
            return
        _installing[sid] = true
        store.changeStickerSet(sid, true, (ok, err) => {
            delete panel._installing[sid]
            if (!ok) {
                panel.say(err || Tr.t("Bo'lmadi"))
                return
            }
            panel.foundRemoteSets = panel.foundRemoteSets.map((s) =>
                String(s.id) === sid ? Object.assign({}, s, { is_installed: true }) : s)
            panel.loadSets()
            panel.say(Tr.t("Stiker to'plami qo'shildi"))
        })
    }

    // a sticker's or a GIF's still: its thumbnail, a WEBP sticker itself; brought down when first shown
    function stillOf(st) {
        if (!st)
            return null
        const th = st.thumbnail
        const f = th && th.format && th.format["@type"]
        if (f === "thumbnailFormatWebp" || f === "thumbnailFormatJpeg" || f === "thumbnailFormatPng" || f === "thumbnailFormatTgs")
            return th.file
        return st.format && st.format["@type"] === "stickerFormatWebp" ? st.sticker : null
    }
    // the still drawn: a TGS thumbnail (a small Lottie) its first frame, by libtlottie; any other the picture itself
    function stillUrl(path) {
        return /\.tgs$/i.test(path) ? "image://lottie/0/-/" + path : "image://thumb/" + path
    }
    function want(f) {
        if (!f || !store || paths[f.id] !== undefined)
            return
        paths[f.id] = ""
        store.fetch(f, 2, (path) => {
            panel.paths[f.id] = path
            panel.got++
        })
    }
    function pathOf(f, _tick) {
        return f ? (paths[f.id] || "") : ""
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
    onVisibleChanged: {
        if (visible)
            recentEmoji = Prefs.recentEmoji ? Prefs.recentEmoji.split(" ") : []
        else
            blurSearch()
    }
    // [{ head, items, pack }]; `starts`: the row each section begins at (the strip jumps there)
    readonly property var rows: {
        const out = [], starts = []
        const add = (title, items, per) => {
            starts.push(out.length)
            if (title)
                out.push({ head: title, items: [], pack: null })
            for (let k = 0; k < items.length; k += per)
                out.push({ head: "", items: items.slice(k, k + per), pack: null })
        }
        if (tab === "emoji") {
            add(Tr.t("Yaqinda ishlatilgan"), recentEmoji.length ? recentEmoji : ["😂", "❤️", "👍", "😍", "🔥", "😭", "🙏", "😊"], 8)
            for (const c of Emoji.categories)
                add(Tr.t(c.title), c.list.split(" "), 8)
        } else if (tab === "stickers") {
            if (searchActive) {
                if (foundLocalStickers.length)
                    add(Tr.t("Stikerlar"), foundLocalStickers, 5)
                if (foundRemoteSets.length) {
                    starts.push(out.length)
                    out.push({ head: Tr.t("Stiker to'plamlari"), items: [], pack: null })
                    for (const s of foundRemoteSets)
                        out.push({ head: "", items: [], pack: s })
                }
            } else {
                for (const s of sets)
                    add(s.title, s.stickers, 5)
            }
        } else {
            if (searchActive) {
                if (foundSavedGifs.length)
                    add(Tr.t("Saqlangan GIFlar"), foundSavedGifs, 3)
                if (foundInlineGifs.length)
                    add(Tr.t("GIFlar"), foundInlineGifs, 3)
            } else {
                add("", gifs, 3)
            }
        }
        return { list: out, starts: starts }
    }
    // the strip's marks: an emoji category's, a pack's first sticker (or ⭐, 🕘)
    readonly property var marks: tab === "emoji" ? [{ t: "🕘" }].concat(Emoji.categories.map((c) => ({ t: c.icon })))
                               : tab === "stickers" ? sets.map((s) => s.mark ? { t: s.mark } : { st: s.stickers[0] || s.cover || null })
                               : []
    property int section: 0             // the strip's lit mark: the section at the grid's top
    onTabChanged: {
        clearSearch()
        blurSearch()
        grid.positionViewAtBeginning()
        section = 0
    }

    // ---- search field at the top (Stickers & GIFs, Telegram-iOS style) -----------
    Item {
        id: searchWrap
        y: 0.5
        width: parent.width
        visible: (panel.tab === "stickers" || panel.tab === "gifs") && panel.stickersOk
        height: visible ? 36 : 0
        Rectangle {
            id: searchBox
            x: 8; y: 4
            width: parent.width - 16; height: 28; radius: 14
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            MouseArea {
                anchors.fill: parent
                onClicked: searchField.forceActiveFocus()
            }
            Icon {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 15; height: 15
                name: "search"
                color: Theme.grey
            }
            Text {
                visible: searchField.text === ""
                x: 30; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 42
                elide: Text.ElideRight
                text: panel.tab === "gifs" ? Tr.t("GIFlarni qidirish") : Tr.t("Stikerlarni qidirish")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
            TextInput {
                id: searchField
                x: 30; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (text !== "" ? (panel.searching ? 60 : 40) : 38)
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: "white"
                font.family: Theme.font; font.pixelSize: 14
                clip: true
                onTextChanged: panel.onSearchTextChanged()
                Keys.onEscapePressed: panel.dismissSearch()
            }
            Ring {
                visible: panel.searching && searchField.text !== ""
                anchors.right: clearBtn.left; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14
                value: 0.72
                thickness: 1.8
                cross: false
                color: Theme.grey
            }
            Item {
                id: clearBtn
                visible: searchField.text !== ""
                anchors.right: parent.right; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14)
                    Icon {
                        anchors.centerIn: parent
                        width: 10; height: 10
                        name: "cross"
                        color: Theme.text
                    }
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -4
                    onClicked: panel.clearSearch()
                }
            }
        }
    }

    Item {               // the strip: tapped, the grid goes to that section
        id: strip
        y: searchWrap.y + searchWrap.height
        width: parent.width
        height: panel.tab === "gifs" || (panel.tab === "stickers" && panel.searchActive) ? 0
              : panel.tab === "stickers" && panel.stickersOk ? 36 : 40
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
                width: 40; height: strip.height
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
                    readonly property string p: panel.pathOf(f, panel.got)
                    source: p ? panel.stillUrl(p) : ""
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
        width: parent.width - 12; height: Math.max(0, tabs.y - y)
        clip: true
        visible: panel.tab === "emoji" ? panel.emojiOk : panel.stickersOk
        model: panel.rows.list
        cacheBuffer: 200
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: {
            if (panel.searchActive)
                return
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
            readonly property var packData: modelData.pack || null
            readonly property bool isPack: packData !== null
            readonly property var packCovers: isPack && packData.covers ? packData.covers.slice(0, 5) : []
            width: grid.width
            height: modelData.head ? (panel.tab === "stickers" && !panel.searchActive ? 26 : 30)
                  : isPack ? (42 + (packCovers.length ? panel.cell : 0) + 4)
                  : panel.tab === "gifs" ? panel.cell * 0.8 : panel.cell

            // Section header
            Text {
                visible: !!rowItem.modelData.head
                x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                text: rowItem.modelData.head
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
            }

            // Remote sticker pack card (searchStickerSets)
            Item {
                visible: rowItem.isPack
                anchors.fill: parent
                Item {
                    id: packHead
                    width: parent.width; height: 40
                    Column {
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - addPackBtn.width - 22
                        spacing: 1
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: rowItem.packData ? (rowItem.packData.title || "") : ""
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: rowItem.packData ? Tr.n("%1 ta stiker", rowItem.packData.size || 0) : ""
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        x: 0; y: 0; width: parent.width - addPackBtn.width - 14; height: parent.height
                        onClicked: if (rowItem.packData) panel.openStickerSet(String(rowItem.packData.id))
                    }
                    Rectangle {
                        id: addPackBtn
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool installed: !!(rowItem.packData && rowItem.packData.is_installed)
                        width: addPackTxt.implicitWidth + 22; height: 28; radius: 14
                        color: installed ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                             : addPackHit.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                        Text {
                            id: addPackTxt
                            anchors.centerIn: parent
                            text: addPackBtn.installed ? Tr.t("Qo'shilgan") : Tr.t("Qo'shish")
                            color: addPackBtn.installed ? Theme.grey : "white"
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: addPackHit
                            anchors.fill: parent
                            enabled: !addPackBtn.installed
                            onClicked: panel.installFoundSet(rowItem.packData)
                        }
                    }
                }
                Row {
                    visible: rowItem.packCovers.length > 0
                    y: 40
                    Repeater {
                        model: rowItem.packCovers
                        delegate: Item {
                            id: cov
                            required property var modelData
                            width: panel.cell; height: panel.cell
                            readonly property var f: panel.stillOf(modelData)
                            Component.onCompleted: panel.want(f)
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 2; radius: 8
                                color: covHit.pressed ? Theme.highlight : "transparent"
                            }
                            Image {
                                anchors.fill: parent; anchors.margins: 4
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                sourceSize: Qt.size(Math.round(width) * 2, Math.round(height) * 2)
                                readonly property string path: panel.pathOf(cov.f, panel.got)
                                source: path ? panel.stillUrl(path) : ""
                            }
                            MouseArea {
                                id: covHit
                                anchors.fill: parent
                                onClicked: panel.sticker(cov.modelData)
                            }
                        }
                    }
                }
            }

            // Regular grid row (emoji / stickers / saved GIFs / inline GIFs)
            Row {
                visible: !rowItem.modelData.head && !rowItem.isPack
                Repeater {
                    model: rowItem.modelData.items
                    delegate: Item {
                        id: one
                        required property var modelData
                        width: panel.cell; height: rowItem.height
                        readonly property bool isEmoji: typeof modelData === "string"
                        readonly property bool isInlineGif: !isEmoji && !!modelData && !!modelData._inline
                        readonly property var gifAnim: isInlineGif ? modelData.animation : modelData
                        // a GIF's or a sticker's still (the thumbnail, a WEBP sticker itself)
                        readonly property var f: isEmoji ? null : panel.tab === "gifs"
                            ? (gifAnim && gifAnim.thumbnail ? gifAnim.thumbnail.file : null) : panel.stillOf(modelData)
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
                            source: panel.tab === "gifs" && one.gifAnim && one.gifAnim.minithumbnail
                                    ? "image://pic/8/" + Math.round(width) + "/mini/" + one.gifAnim.minithumbnail.data : ""
                            sourceSize: Qt.size(width, height)
                        }
                        Image {
                            id: pic
                            visible: !one.isEmoji
                            anchors.fill: parent; anchors.margins: panel.tab === "gifs" ? 2 : 4
                            fillMode: panel.tab === "gifs" ? Image.Stretch : Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize: Qt.size(Math.round(width) * 2, Math.round(height) * 2)
                            readonly property string path: panel.pathOf(one.f, panel.got)
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
                                    if (one.isInlineGif)
                                        panel.inlineGif(one.modelData.queryId || "", one.modelData.id || "", one.modelData.animation)
                                    else
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
            : panel.searchActive && panel.searching ? Tr.t("Qidirilmoqda…")
            : panel.searchActive ? (panel.tab === "gifs" ? Tr.t("GIF topilmadi") : Tr.t("Stiker topilmadi"))
            : panel.tab === "stickers" ? Tr.t("Stikerlar to'plami yo'q") : Tr.t("Saqlangan GIF yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    Item {               // the foot: the three tabs, ⌫ on Emoji; clears safe.bottom when OSK is closed
        id: tabs
        y: parent.height - height
        width: parent.width; height: 44 + panel.safeBottom
        Item {
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
}
