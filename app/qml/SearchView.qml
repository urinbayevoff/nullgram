// Global search over the chat list, as Telegram-iOS's: the box at the top with "Bekor", under it
// horizontal filter chips (Chatlar, Media, Havolalar, Fayllar, Musiqa, Ovozli). "Chatlar" searches
// local chats, TDLib/server chats, public chats ("Global qidiruv") and messages across every chat
// (Latin/Cyrillic via Store.fold). The other tabs call TDLib searchMessages with the matching
// searchMessagesFilter* (even on an empty query, showing the latest across all chats) and page by
// string offset. Tapping a chat or message opens it in ChatPage; tapping media opens PhotoViewer.
import QtQuick

Rectangle {
    id: view
    property var store
    property bool open: false
    signal picked(var chatId, var messageId)

    color: Theme.bg
    opacity: 0
    visible: opacity > 0
    NumberAnimation on opacity { id: fade; duration: 160; running: false }      // (an Animator would set it only at the end, and visible goes by it)

    readonly property var tabs: [
        { key: "chats", name: Tr.t("Chatlar"), filter: "" },
        { key: "media", name: Tr.t("Media"), filter: "searchMessagesFilterPhotoAndVideo" },
        { key: "links", name: Tr.t("Havolalar"), filter: "searchMessagesFilterUrl" },
        { key: "files", name: Tr.t("Fayllar"), filter: "searchMessagesFilterDocument" },
        { key: "music", name: Tr.t("Musiqa"), filter: "searchMessagesFilterAudio" },
        { key: "voice", name: Tr.t("Ovozli"), filter: "searchMessagesFilterVoiceNote" }
    ]
    property string tab: "chats"

    // Chats tab state
    property var chatIds: []
    property var globalIds: []
    property var found: []
    property int now: Date.now() / 1000
    property string asked: ""       // the query the results are for (a message's words that have it are lit)

    // Filtered tabs state (Media, Havolalar, Fayllar, Musiqa, Ovozli)
    property var tabItems: []       // raw TDLib message objects for the active filtered tab
    property var tabSeen: ({})      // "chatId:msgId" -> true (dedup across pages)
    property string tabNextOffset: ""
    property bool tabMore: false
    property bool tabLoading: false
    property int tabSeq: 0

    // Media viewer state (PhotoViewer loaded lazily on first media tap)
    property var shownMedia: null
    property var unveiled: ({})
    property int unveiledTick: 0
    readonly property bool viewerOpen: !!(viewerLoader.item && viewerLoader.item.open)
    readonly property real bottomPad: Math.max(osk.h, safe.bottom) + 12

    function show() {
        open = true
        now = Date.now() / 1000
        tab = "chats"
        asked = ""
        chatIds = []; globalIds = []; found = []
        tabItems = []; tabSeen = ({}); tabNextOffset = ""; tabMore = false; tabLoading = false
        tabSeq++
        unveiled = ({}); unveiledTick++
        results.clear()
        tabRows.clear()
        mediaRows.clear()
        field.text = ""
        later.stop()
        fade.from = opacity; fade.to = 1; fade.restart()
        field.forceActiveFocus()
    }
    // (Qt.inputMethod.hide() does nothing under the shell: the field let go of, the shell told at once)
    function keyboardDown() {
        field.focus = false
        if (osk.h > 0)
            osk.hide()
    }
    function close(force) {
        if (!force && viewerLoader.item && viewerLoader.item.open) {
            viewerLoader.item.close()
            return
        }
        if (viewerLoader.item && viewerLoader.item.open)
            viewerLoader.item.close()
        open = false
        tabSeq++
        later.stop()
        keyboardDown()
        fade.from = opacity; fade.to = 0; fade.restart()
    }

    function selectTab(key) {
        if (key === tab)
            return
        tab = key
        later.stop()
        run(field.text.trim())
    }

    function setQuery(q) {
        field.text = q || ""
        later.stop()
        run(field.text.trim())
    }

    Timer { id: later; interval: 250; onTriggered: view.run(field.text.trim()) }

    function run(q) {
        asked = q
        if (tab === "chats") {
            tabSeq++
            tabLoading = false
            chatIds = []; globalIds = []; found = []
            if (!q) {
                rebuild()
                return
            }
            store.searchChats(q, (kind, ids) => {
                if (kind === "chats")
                    view.chatIds = ids
                else
                    view.globalIds = ids
                view.rebuild()
            })
            if (q.length >= 2)
                store.searchMessages(q, (msgs) => { view.found = msgs; view.rebuild() })
            return
        }
        tabItems = []
        tabSeen = ({})
        tabNextOffset = ""
        tabMore = false
        tabRows.clear()
        mediaRows.clear()
        if (tab === "media")
            mediaGrid.toTop()
        else
            tabList.positionViewAtBeginning()
        fetchTab(false)
    }

    function loadMore() {
        if (tab !== "chats")
            fetchTab(true)
    }

    function fetchTab(append) {
        const t = tabs.find((x) => x.key === tab)
        if (!t || !t.filter)
            return
        if (append && (tabLoading || !tabMore || !tabNextOffset))
            return
        const seq = ++tabSeq
        const key = tab
        const q = asked
        const off = append ? tabNextOffset : ""
        const lim = key === "media" ? 30 : 25
        tabLoading = true
        store.searchMessagesFiltered(q, t.filter, off, lim, (msgs, nextOff) => {
            if (!view.open || seq !== view.tabSeq || view.tab !== key)
                return
            view.tabLoading = false
            const added = []
            for (const m of msgs || []) {
                if (!m || !m.content)
                    continue
                const mk = m.chat_id + ":" + m.id
                if (view.tabSeen[mk])
                    continue
                view.tabSeen[mk] = true
                added.push(m)
            }
            if (added.length) {
                const startIdx = view.tabItems.length
                view.tabItems = view.tabItems.concat(added)
                if (key === "media") {
                    for (let i = 0; i < added.length; i++)
                        mediaRows.append(view.mediaRowOf(added[i]))
                } else {
                    for (let i = 0; i < added.length; i++)
                        tabRows.append(view.tabRowOf(key, added[i], startIdx + i))
                }
            }
            view.tabNextOffset = nextOff || ""
            view.tabMore = !!nextOff && nextOff !== off && (msgs || []).length > 0
        })
    }

    function rebuild() {
        results.clear()
        const chatRow = (id, sub) => {
            const c = store.chats[id]
            results.append({ kind: "chat", chatId: id, msgId: 0, title: store.title(c), sub: sub, time: "",
                             photo: store.photoPath(c), letters: store.letters(c.title),
                             tint: store.tints[Math.abs(id) % store.tints.length] })
        }
        if (chatIds.length) {
            results.append({ kind: "head", title: Tr.t("Chatlar") })
            for (const id of chatIds)
                chatRow(id, store.status(store.chats[id], now))
        }
        if (globalIds.length) {
            results.append({ kind: "head", title: Tr.t("Global qidiruv") })
            for (const id of globalIds.slice(0, 5))       // (a few, as iOS shows them: the messages follow)
                chatRow(id, username(store.chats[id]) || store.status(store.chats[id], now))
        }
        if (found.length) {
            results.append({ kind: "head", title: Tr.t("Xabarlar") })
            for (const m of found) {
                const c = store.chats[m.chat_id]
                if (!c)
                    continue
                results.append({ kind: "message", chatId: m.chat_id, msgId: m.id, title: store.title(c),
                                 sub: store.preview(m.content, c).replace(/\s+/g, " "), time: store.stamp(m.date),
                                 photo: store.photoPath(c), letters: store.letters(c.title),
                                 tint: store.tints[Math.abs(m.chat_id) % store.tints.length] })
            }
        }
    }

    function clock(s) {
        const sec = Math.max(0, Math.floor(s || 0))
        return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0")
    }

    function miniOf(m) {
        if (!m || !m.content)
            return ""
        const c = m.content
        const t = c["@type"] === "messagePhoto" ? (c.photo && c.photo.minithumbnail)
                : c["@type"] === "messageVideo" ? (c.video && c.video.minithumbnail) : null
        return t && t.data ? t.data : ""
    }

    function mediaRowOf(m) {
        const c = m.content
        const isVid = c["@type"] === "messageVideo"
        return {
            msgKey: m.chat_id + ":" + m.id,
            isVideo: isVid,
            duration: isVid && c.video ? (c.video.duration || 0) : 0,
            hasSpoiler: !!c.has_spoiler,
            mini: miniOf(m)
        }
    }

    function extractLink(m) {
        const c = m.content
        const ft = c.text || c.caption
        if (ft) {
            for (const e of ft.entities || []) {
                if (e.type["@type"] === "textEntityTypeTextUrl" && e.type.url)
                    return e.type.url
                if (e.type["@type"] === "textEntityTypeUrl")
                    return ft.text.substr(e.offset, e.length)
            }
        }
        if (c.link_preview && c.link_preview.url)
            return c.link_preview.url
        if (ft && ft.text) {
            const match = ft.text.match(/(?:https?:\/\/|t\.me\/)\S+/i)
            if (match)
                return match[0]
        }
        return ""
    }

    function domainOf(url) {
        return (url || "").replace(/^[a-z]+:\/\//i, "").replace(/^www\./i, "").split(/[\/?#]/)[0] || ""
    }

    function hashTint(s) {
        let h = 0
        for (let i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) | 0
        return store.tints[Math.abs(h) % store.tints.length]
    }

    function extColor(ext) {
        if (ext === "PDF")
            return "#e53935"
        if (ext === "ZIP" || ext === "RAR" || ext === "7Z" || ext === "TAR" || ext === "GZ")
            return "#fb8c00"
        if (ext === "XLS" || ext === "XLSX" || ext === "CSV")
            return "#43a047"
        if (ext === "DOC" || ext === "DOCX" || ext === "TXT" || ext === "MD")
            return "#1e88e5"
        if (ext === "APK" || ext === "EXE" || ext === "DMG")
            return "#8e24aa"
        return String(Theme.accent)
    }

    function tabRowOf(key, m, idx) {
        const c = store.chats[m.chat_id]
        const chatTitle = c ? store.title(c) : (store.senderName(m.sender_id, false) || "")
        const ct = m.content
        const time = store.stamp(m.date)
        if (key === "links") {
            const url = extractLink(m)
            const dom = domainOf(url)
            const lp = ct.link_preview
            const ft = ct.text || ct.caption
            const rawText = ft ? ft.text.replace(/\s+/g, " ").trim() : ""
            const head = (lp && (lp.title || lp.site_name)) || dom || chatTitle || Tr.t("Havola")
            const sub = chatTitle + (rawText && rawText !== url && rawText !== head ? " · " + rawText : "")
            return {
                kind: "links", chatId: m.chat_id, msgId: m.id, itemIdx: idx,
                title: head, linkUrl: url || Tr.t("havola"), sub: sub, time: time,
                badge: dom ? dom.charAt(0).toUpperCase() : "L",
                badgeTint: dom ? hashTint(dom) : String(Theme.accent), icon: ""
            }
        }
        if (key === "files") {
            const d = ct.document
            const fname = (d && d.file_name) || Tr.t("Fayl")
            const dot = fname.lastIndexOf(".")
            const ext = dot > 0 && dot < fname.length - 1 ? fname.slice(dot + 1).toUpperCase().slice(0, 4) : Tr.t("FAYL")
            const sz = d && d.document ? store.size(d.document.size || 0) : ""
            const cap = ct.caption && ct.caption.text ? ct.caption.text.replace(/\s+/g, " ").trim() : ""
            const parts = [sz, chatTitle, cap].filter((x) => x !== "")
            return {
                kind: "files", chatId: m.chat_id, msgId: m.id, itemIdx: idx,
                title: fname, linkUrl: "", sub: parts.join(" · "), time: time,
                badge: ext, badgeTint: extColor(ext), icon: ""
            }
        }
        if (key === "music") {
            const a = ct.audio
            const title = (a && (a.title || a.file_name)) || Tr.t("Musiqa")
            const perf = (a && a.performer) || Tr.t("Noma'lum ijrochi")
            const dur = clock(a ? a.duration : 0)
            const parts = [perf, dur, chatTitle].filter((x) => x !== "")
            return {
                kind: "music", chatId: m.chat_id, msgId: m.id, itemIdx: idx,
                title: title, linkUrl: "", sub: parts.join(" · "), time: time,
                badge: "", badgeTint: String(Theme.accent), icon: "play"
            }
        }
        // voice (messageVoiceNote or fallback messageVideoNote)
        const vn = ct.voice_note || ct.video_note
        const who = store.origin(m.forward_info) || (m.is_outgoing ? Tr.t("Siz")
                    : store.senderName(m.sender_id, false) || chatTitle || Tr.t("Ovozli xabar"))
        const dur = clock(vn ? vn.duration : 0)
        const parts = [Tr.t("Ovozli xabar"), dur, chatTitle && chatTitle !== who ? chatTitle : ""].filter((x) => x !== "")
        return {
            kind: "voice", chatId: m.chat_id, msgId: m.id, itemIdx: idx,
            title: who, linkUrl: "", sub: parts.join(" · "), time: time,
            badge: "", badgeTint: String(Theme.accent), icon: "mic"
        }
    }

    function unveil(key) {
        if (!unveiled[key]) {
            unveiled[key] = true
            unveiledTick++
        }
    }

    function viewMedia(tile, m) {
        if (!m || !m.content)
            return
        keyboardDown()
        if (!viewerLoader.active)
            viewerLoader.active = true
        const v = viewerLoader.item
        if (!v || v.open)
            return
        unveil(m.chat_id + ":" + m.id)
        const c = m.content
        const side = Math.round(tile.width || 120)
        const small = miniOf(m)
        const src = tile.path ? "image://pic/0/" + side + "/" + tile.path
                  : small ? "image://pic/0/" + side + "/mini/" + small : ""
        if (c["@type"] === "messagePhoto") {
            const sizes = (c.photo && c.photo.sizes) || []
            if (!sizes.length)
                return
            const big = sizes[sizes.length - 1]
            shownMedia = { file: big.photo, name: "photo_" + m.id + ".jpg" }
            v.show(tile, big.width ? big.height / big.width : 1, src, "", 0)
            store.fetch(big.photo, 32, (path) => { if (v && v.open) v.better(path) })
            return
        }
        if (c["@type"] === "messageVideo") {
            const video = c.video
            if (!video || tile.downloading)
                return
            shownMedia = { file: video.video, name: video.file_name || "video_" + m.id + ".mp4" }
            const aspect = video.width ? video.height / video.width : 9 / 16
            tile.downloading = !(video.video.local && video.video.local.is_downloading_completed)
            store.fetch(video.video, 32, (path) => {
                if (tile)
                    tile.downloading = false
                if (view.open && v && !v.open)
                    v.show(tile, aspect, src, path, 0)
            })
        }
    }

    function saveShown() {
        if (!shownMedia || !shownMedia.file)
            return
        store.saveFile(shownMedia.file, shownMedia.name, (msg) => view.say(msg))
    }

    function say(text) {
        note.text = text
        noteBox.opacity = 1
        noteAway.restart()
    }

    function emptyTitle() {
        if (asked !== "")
            return Tr.t("Hech narsa topilmadi")
        if (tab === "media")
            return Tr.t("Media topilmadi")
        if (tab === "links")
            return Tr.t("Havolalar topilmadi")
        if (tab === "files")
            return Tr.t("Fayllar topilmadi")
        if (tab === "music")
            return Tr.t("Musiqa topilmadi")
        if (tab === "voice")
            return Tr.t("Ovozli xabarlar topilmadi")
        return Tr.t("Hech narsa topilmadi")
    }

    // A found message's line as Telegram-iOS's (ChatListItem, chatListSearchResult): the query's words where a word
    // of it starts lit (messageHighlightedTextColor: the text's own colour, the rest grey), and when the first is
    // over 24 letters in, the line starts «…» at a word more than 12 letters before it. Matched as Store.fold does
    // (case, Cyrillic/Latin), mapped back to the line's own letters. StyledText.
    function lit(line, q) {
        const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const words = store.fold(q).split(/\s+/).filter((w) => w.length > 0)
        if (!words.length)
            return esc(line)
        const chars = Array.from(line)
        let folded = "", at = []                // at[k]: the line's letter the folded string's k-th came from
        chars.forEach((ch, i) => {
            const f = store.fold(ch)
            folded += f
            for (let k = 0; k < f.length; k++)
                at.push(i)
        })
        const letter = (ch) => ch !== undefined && /[\p{L}\p{N}]/u.test(ch)
        const lit = new Array(chars.length).fill(false)
        let first = -1
        for (const w of words) {
            for (let k = folded.indexOf(w); k >= 0; k = folded.indexOf(w, k + 1)) {
                if (k > 0 && letter(folded[k - 1]))
                    continue                    // (inside a word: not where one starts)
                const a = at[k], b = at[k + w.length - 1]
                for (let i = a; i <= b; i++)
                    lit[i] = true
                if (first < 0 || a < first)
                    first = a
            }
        }
        let from = 0
        if (first > 24) {                       // the nearest word start more than 12 letters before it
            for (let i = first - 13; i > 0; i--)
                if (letter(chars[i]) && !letter(chars[i - 1])) {
                    from = i
                    break
                }
        }
        let out = from > 0 ? "\u2026" : "", on = false
        for (let i = from; i < chars.length; i++) {
            if (lit[i] !== on) {
                out += lit[i] ? "<font color=\"" + Theme.text + "\">" : "</font>"
                on = lit[i]
            }
            out += esc(chars[i])
        }
        return on ? out + "</font>" : out
    }

    function username(c) {
        let names = null
        if (c.type["@type"] === "chatTypeSupergroup") {
            const g = store.groups["s" + c.type.supergroup_id]
            names = g && g.usernames
        } else if (c.type["@type"] === "chatTypePrivate") {
            const u = store.users[c.type.user_id]
            names = u && u.usernames
        }
        return names && names.active_usernames.length ? "@" + names.active_usernames[0] : ""
    }

    ListModel { id: results }
    ListModel { id: tabRows }
    ListModel { id: mediaRows }

    MouseArea { anchors.fill: parent }      // nothing under it is touched while it is up

    Item {
        id: top
        width: parent.width; height: 60
        Rectangle {
            x: 14; y: 12
            width: parent.width - x - cancel.width - 28; height: 38; radius: 19
            color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
            Icon {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                name: "search"; width: 18; height: 18; color: Theme.grey
            }
            TextInput {
                id: field
                x: 38; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (clearBtn.visible ? 34 : 12)
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: if (view.open) later.restart()
                Text {
                    visible: !field.text
                    text: Tr.t("Qidiruv")
                    color: Theme.grey
                    font: field.font
                }
            }
            Rectangle {
                id: clearBtn
                visible: field.text !== ""
                anchors.right: parent.right; anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
                Icon {
                    anchors.centerIn: parent
                    name: "cross"; width: 11; height: 11
                    color: Theme.dark ? "#000000" : "#ffffff"
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    onClicked: {
                        field.text = ""
                        later.stop()
                        view.run("")
                    }
                }
            }
        }
        Text {
            id: cancel
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 21
            text: Tr.t("Bekor")
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 16
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: view.close(true) }
        }
    }

    SearchTabs {
        id: tabsBar
        y: top.height
        width: parent.width
        tabs: view.tabs
        current: view.tab
        onPicked: (key) => view.selectTab(key)
    }

    // ---- Chats tab (existing search results) ----
    ListView {
        id: list
        visible: view.tab === "chats"
        y: tabsBar.y + tabsBar.height
        width: parent.width; height: parent.height - y
        bottomMargin: view.bottomPad
        clip: true
        model: results
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        onMovementStarted: view.keyboardDown()          // looking through them: the keyboard goes

        delegate: Rectangle {
            id: row
            required property string kind
            required property var chatId
            required property var msgId
            required property string title
            required property string sub
            required property string time
            required property string photo
            required property string letters
            required property string tint
            width: list.width
            height: kind === "head" ? 34 : kind === "message" ? 66 : 58
            color: kind === "head" ? (Theme.dark ? "#1c1c1d" : "#f2f2f7") : tap.pressed ? Theme.highlight : Theme.bg

            Text {
                visible: row.kind === "head"
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: row.title.toUpperCase()
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Avatar {
                visible: row.kind !== "head"
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                source: row.kind !== "head" ? row.photo : ""
                letters: row.letters; tint: row.tint
            }
            Text {
                visible: row.kind !== "head"
                x: 70; y: row.kind === "message" ? 10 : 9
                width: parent.width - x - stamp.width - 20
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                id: stamp
                visible: row.kind === "message"
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 12
                text: row.kind === "message" ? row.time : ""
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                visible: row.kind !== "head"
                x: 70; y: row.kind === "message" ? 33 : 31
                width: parent.width - x - 14
                text: row.kind === "message" ? view.lit(row.sub, view.asked) : row.sub
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: row.kind === "message" ? Text.StyledText : Text.PlainText
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
            Rectangle {
                visible: row.kind !== "head"
                x: 70; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                enabled: row.kind !== "head"
                onClicked: {
                    view.keyboardDown()
                    view.picked(row.chatId, row.msgId)
                }
            }
        }
    }

    // ---- Media tab (3-column photo & video grid) ----
    SearchMediaGrid {
        id: mediaGrid
        visible: view.tab === "media"
        y: tabsBar.y + tabsBar.height
        width: parent.width; height: parent.height - y
        store: view.store
        model: mediaRows
        messages: view.tabItems
        loading: view.tabLoading
        more: view.tabMore
        bottomPad: view.bottomPad
        unveiled: view.unveiled
        unveiledTick: view.unveiledTick
        onPicked: (tile, msg) => view.viewMedia(tile, msg)
        onNeedMore: view.loadMore()
        onScrolled: view.keyboardDown()
    }

    // ---- Filtered list tabs (Havolalar, Fayllar, Musiqa, Ovozli) ----
    ListView {
        id: tabList
        visible: view.tab !== "chats" && view.tab !== "media"
        y: tabsBar.y + tabsBar.height
        width: parent.width; height: parent.height - y
        bottomMargin: view.bottomPad
        clip: true
        model: tabRows
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        onMovementStarted: view.keyboardDown()
        onContentYChanged: {
            if (!visible || view.tabLoading || !view.tabMore || count === 0)
                return
            if (contentY > 0 && contentY + height >= contentHeight - 240)
                view.loadMore()
        }

        delegate: Rectangle {
            id: trow
            required property string kind
            required property var chatId
            required property var msgId
            required property string title
            required property string linkUrl
            required property string sub
            required property string time
            required property string badge
            required property string badgeTint
            required property string icon
            width: tabList.width
            height: kind === "links" ? 76 : 66
            color: ttap.pressed ? Theme.highlight : Theme.bg

            Rectangle {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                radius: trow.kind === "music" || trow.kind === "voice" ? 22 : 10
                color: trow.badgeTint
                Text {
                    visible: trow.icon === ""
                    anchors.centerIn: parent
                    text: trow.badge
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: trow.kind === "files" ? 11 : 18
                    font.weight: Font.Bold
                }
                Icon {
                    visible: trow.icon !== ""
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: trow.icon === "play" ? 1.5 : 0
                    width: 20; height: 20
                    name: trow.icon
                    color: "white"
                }
            }

            Text {
                x: 70; y: trow.kind === "links" ? 9 : 11
                width: parent.width - x - tstamp.implicitWidth - 22
                text: trow.title
                elide: trow.kind === "files" ? Text.ElideMiddle : Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }

            Text {
                id: tstamp
                anchors.right: parent.right; anchors.rightMargin: 14
                y: trow.kind === "links" ? 11 : 13
                text: trow.time
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }

            Text {
                visible: trow.kind === "links"
                x: 70; y: 31
                width: parent.width - x - 14
                text: trow.linkUrl
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 13
            }

            Text {
                x: 70; y: trow.kind === "links" ? 50 : 34
                width: parent.width - x - 14
                text: view.asked ? view.lit(trow.sub, view.asked) : trow.sub
                textFormat: view.asked ? Text.StyledText : Text.PlainText
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }

            Rectangle {
                x: 70; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }

            MouseArea {
                id: ttap
                anchors.fill: parent
                onClicked: {
                    view.keyboardDown()
                    view.picked(trow.chatId, trow.msgId)
                }
            }
        }

        footer: Item {
            width: tabList.width
            height: (view.tabLoading || view.tabMore) && tabList.count > 0 ? 48 : 0
            visible: height > 0
            Text {
                anchors.centerIn: parent
                text: Tr.t(view.tabLoading ? "yuklanmoqda..." : "Yana")
                color: view.tabLoading ? Theme.grey : Theme.accent
                font.family: Theme.font; font.pixelSize: 15
            }
            MouseArea {
                anchors.fill: parent
                enabled: view.tabMore && !view.tabLoading
                onClicked: view.loadMore()
            }
        }
    }

    // ---- Initial loading indicator for filtered tabs ----
    Column {
        visible: view.open && view.tab !== "chats" && view.tabLoading && view.tabItems.length === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: tabsBar.y + tabsBar.height + 90
        spacing: 12
        Ring {
            anchors.horizontalCenter: parent.horizontalCenter
            value: 0.3
            color: Theme.accent
            cross: false
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("yuklanmoqda...")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
    }

    // ---- Empty state ----
    Column {
        readonly property bool chatsEmpty: view.tab === "chats" && field.text.trim() !== "" && results.count === 0 && !later.running
        readonly property bool tabEmpty: view.tab !== "chats" && !view.tabLoading && view.tabItems.length === 0 && !later.running
        visible: view.open && (chatsEmpty || tabEmpty)
        anchors.horizontalCenter: parent.horizontalCenter
        y: tabsBar.y + tabsBar.height + 96
        width: parent.width - 48
        spacing: 6
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "search"; width: 32; height: 32; color: Theme.grey
            opacity: 0.55
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: view.emptyTitle()
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
        }
        Text {
            visible: view.asked !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Tr.t("Boshqa so'z bilan qidirib ko'ring")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
    }

    // ---- Lazy PhotoViewer for Media tab ----
    Loader {
        id: viewerLoader
        anchors.fill: parent
        z: 30
        active: false
        sourceComponent: Component {
            PhotoViewer {
                store: view.store
                chatId: 0
                onSave: view.saveShown()
            }
        }
    }

    // ---- Lightweight pill toast (e.g., after saving media from PhotoViewer) ----
    Rectangle {
        id: noteBox
        z: 40
        anchors.horizontalCenter: parent.horizontalCenter
        y: 68
        width: Math.min(parent.width - 40, note.implicitWidth + 28)
        height: note.implicitHeight + 16
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.78)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: note
            anchors.centerIn: parent
            width: Math.min(implicitWidth, view.width - 68)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
    }
    Timer { id: noteAway; interval: 2200; onTriggered: noteBox.opacity = 0 }
}
