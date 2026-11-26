// Scrollable real-chat preview inside ChatMenu (long-press peek on ChatListPage / ArchivePage).
// Read-only: uses only getChatHistory (local-first, then chunked older loads on scroll-up),
// never sends viewMessages or openChat, so unread counts remain untouched.
// Reuses Wallpaper, image://bubble, Words, AlbumTile/Mosaic, AudioRow, FileRow, PollView, Avatar, Veil.
import QtQuick
import QtQuick.Window
import "Mosaic.js" as Mosaic

Item {
    id: peek
    property var store
    property var chatId: 0
    property bool active: true
    property real topInset: 0
    property real cardRadius: 0
    signal picked(var chatId, var messageId)

    readonly property real dpr: Screen.devicePixelRatio
    readonly property var chat: (store && store.seen >= 0 && chatId) ? store.chats[chatId] : null
    function isGroupChat(c) {
        return !!c && (c.type["@type"] === "chatTypeBasicGroup"
                       || (c.type["@type"] === "chatTypeSupergroup" && !c.type.is_channel))
    }
    function isChannelChat(c) {
        return !!c && c.type["@type"] === "chatTypeSupergroup" && !!c.type.is_channel
    }
    readonly property bool group: isGroupChat(chat)
    readonly property bool channel: isChannelChat(chat)
    readonly property real readUpTo: chat ? (chat.last_read_outbox_message_id || 0) : 0

    // Chat wallpaper (same resolution chain as ChatPage: chat.background -> chat.theme -> app wall)
    property string wallSpec: ""
    property real wallDim: 0
    property var _wallOf: null
    function rewall() {
        const c = chat
        const key = c ? JSON.stringify([c.background, c.theme, Theme.dark]) : ""
        if (key === _wallOf)
            return
        _wallOf = key
        if (!store)
            return
        store.chatWall(c, Theme.dark, (s, dim) => {
            if (peek && _wallOf === key) {
                wallSpec = s
                wallDim = dim
            }
        })
    }
    Connections { target: Theme; function onDarkChanged() { peek.rewall() } }

    // History state
    ListModel { id: messages }      // newest first (index 0 at bottom in BottomToTop ListView)
    readonly property alias messageList: messages
    readonly property alias view: peekList
    property int loadGen: 0
    property bool loadingInitial: false
    property bool loadingOlder: false
    property bool more: true
    property bool ready: false
    property bool userScrolled: false
    property var firstUnread: 0
    property var pressedMsgId: 0

    // Caches per preview instance
    property var rowAt: ({})
    property var quotes: ({})
    property var askedQuotes: ({})
    property var sendersAsked: ({})
    property var picFiles: ({})
    property var albums: ({})
    property string albumKey: ""
    property int albumRev: 0
    property int albumTick: 0
    property var laidOut: ({})

    readonly property int tzSec: new Date().getTimezoneOffset() * 60
    readonly property var pictured: ["messagePhoto", "messageVideo", "messageAnimation", "messageSticker",
                                     "messageAnimatedEmoji", "messageVideoNote", "messageVoiceNote",
                                     "messageAudio", "messageDocument", "messagePoll",
                                     "messageLocation", "messageVenue", "messageLiveLocation"]

    Component.onCompleted: {
        rewall()
        if (chatId && store)
            loadInitial()
    }
    onChatIdChanged: {
        rewall()
        if (chatId && store)
            loadInitial()
    }

    function resetState() {
        loadGen++
        messages.clear()
        rowAt = ({})
        quotes = ({})
        askedQuotes = ({})
        sendersAsked = ({})
        picFiles = ({})
        albums = ({})
        albumKey = ""
        albumRev = 0
        albumTick = 0
        laidOut = ({})
        loadingInitial = false
        loadingOlder = false
        more = true
        ready = false
        userScrolled = false
        firstUnread = 0
        pressedMsgId = 0
    }

    function loadInitial() {
        resetState()
        const id = chatId
        const gen = loadGen
        if (!store || !id)
            return
        loadingInitial = true
        const c = store.chats[id]
        if (c && c.last_message) {
            appendBatch([c.last_message])
            positionAtBottom()
        }
        // Fast local-first chunk (only_local: true), then network fallback if local cache has < 12 messages
        const localLimit = 15
        store.history(id, 0, localLimit, (got, failed) => {
            if (!peek || gen !== peek.loadGen || peek.chatId !== id)
                return
            if (got && got.length)
                appendBatch(got)
            if (!failed && got && got.length >= 12) {
                peek.loadingInitial = false
                peek.ready = true
                peek.positionAtBottom()
                return
            }
            // Local had fewer than a screenful: fetch first network chunk
            const netLimit = 20
            store.history(id, 0, netLimit, (netGot, netFailed) => {
                if (!peek || gen !== peek.loadGen || peek.chatId !== id)
                    return
                if (netGot && netGot.length)
                    appendBatch(netGot)
                peek.loadingInitial = false
                peek.ready = true
                if (!netFailed && (!netGot || netGot.length < netLimit))
                    peek.more = false
                peek.positionAtBottom()
            }, null, 0, 0, false)
        }, null, 0, 0, true)
    }

    function loadOlder() {
        if (loadingOlder || loadingInitial || !more || !messages.count || !store || !chatId)
            return
        loadingOlder = true
        const id = chatId
        const gen = loadGen
        const oldestId = messages.get(messages.count - 1).msgId
        const chunkLimit = 20
        store.history(id, oldestId, chunkLimit, (got, failed) => {
            if (!peek || gen !== peek.loadGen || peek.chatId !== id)
                return
            peek.loadingOlder = false
            if (failed)
                return
            if (!got || !got.length) {
                peek.more = false
                return
            }
            const added = appendBatch(got)
            if (got.length < chunkLimit || added === 0)
                peek.more = false
        }, null, 0, 0, false)
    }

    function nearTop() {
        if (!ready || loadingOlder || loadingInitial || !more || !messages.count)
            return
        const top = peekList.indexAt(peekList.width / 2, peekList.contentY + 12)
        if (top >= 0 ? top >= messages.count - 5 : (userScrolled && peekList.atYEnd))
            loadOlder()
    }

    function positionAtBottom() {
        if (userScrolled)
            return
        Qt.callLater(() => {
            if (peek && !peek.userScrolled && messages.count > 0) {
                peekList.forceLayout()
                peekList.positionViewAtBeginning()
            }
        })
    }

    function appendBatch(list) {
        if (!list || !list.length)
            return 0
        for (const m of list)
            remember(m)
        const prevLast = messages.count - 1
        let added = 0
        const fresh = []
        for (const m of list) {
            if (rowAt[m.id] !== undefined)
                continue
            rowAt[m.id] = -2    // placeholder until inserted
            fresh.push(m)
        }
        if (!fresh.length)
            return 0
        // If batch contains messages newer than index 0 (rare: seed vs network), insert in newest-first order
        const newestNow = messages.count > 0 ? messages.get(0).msgId : 0
        const olderRows = []
        for (const m of fresh) {
            const r = buildRow(m)
            if (newestNow && m.id > newestNow) {
                let at = 0
                while (at < messages.count && messages.get(at).msgId > m.id)
                    at++
                messages.insert(at, r)
            } else {
                olderRows.push(r)
            }
            added++
        }
        if (olderRows.length)
            messages.append(olderRows)
        rebuildIndexAndAlbums()
        if (prevLast >= 0 && prevLast < messages.count)
            messages.setProperty(prevLast, "edge", messages.get(prevLast).edge + 1)
        updateFirstUnread()
        return added
    }

    function updateFirstUnread() {
        const c = store && chatId ? store.chats[chatId] : null
        const lastRead = c ? (c.last_read_inbox_message_id || 0) : 0
        if (!c || (c.unread_count || 0) <= 0 || !lastRead) {
            firstUnread = 0
            return
        }
        let found = 0
        for (let k = messages.count - 1; k >= 0; k--) {
            const r = messages.get(k)
            if (r.msgId > lastRead && !r.out) {
                found = r.msgId
                break
            }
        }
        firstUnread = found
    }

    function remember(m) {
        if (!m || !m.content || !store)
            return
        const c = store.chats[chatId] || null
        quotes[m.id] = {
            name: m.is_outgoing ? Tr.t("Siz") : (store.senderName(m.sender_id, false) || (c ? c.title : "")),
            text: store.preview(m.content, c)
        }
    }

    function wantQuote(id) {
        if (!id || askedQuotes[id] || !store)
            return
        askedQuotes[id] = true
        const gen = loadGen
        store.send({ "@type": "getMessage", chat_id: chatId, message_id: id }, (m) => {
            if (!peek || gen !== peek.loadGen)
                return
            if (m && m["@type"] === "message")
                peek.remember(m)
            else
                peek.quotes[id] = { name: "", text: Tr.t("O'chirilgan xabar") }
            const q = peek.quotes[id]
            for (let i = 0; i < messages.count; i++) {
                if (messages.get(i).replyId === id) {
                    messages.setProperty(i, "quoteName", q.name)
                    messages.setProperty(i, "quoteText", q.text)
                }
            }
        })
    }

    function nameOf(sender) {
        if (!sender || !store)
            return ""
        const name = store.senderName(sender, false)
        if (name)
            return name
        const key = JSON.stringify(sender)
        if (sendersAsked[key])
            return ""
        sendersAsked[key] = true
        const gen = loadGen
        const req = sender.user_id ? { "@type": "getUser", user_id: sender.user_id } : { "@type": "getChat", chat_id: sender.chat_id }
        store.send(req, (r) => {
            if (!peek || gen !== peek.loadGen)
                return
            if (r["@type"] === "chat" && !store.chats[r.id])
                store.chats[r.id] = r
            else if (r["@type"] === "user" && !store.users[r.id])
                store.users[r.id] = r
            const got = store.senderName(sender, false)
            if (!got)
                return
            for (let i = 0; i < messages.count; i++) {
                const r0 = messages.get(i)
                if (r0.senderKey === key && !r0.out)
                    messages.setProperty(i, "sender", got)
            }
        })
        return ""
    }

    function still(th) {
        const f = th && th.format ? th.format["@type"] : ""
        return f === "thumbnailFormatJpeg" || f === "thumbnailFormatWebp" || f === "thumbnailFormatPng" || f === "thumbnailFormatGif"
               ? th.file : null
    }

    function extractMedia(c) {
        const t = c["@type"]
        const r = { picKind: "", picW: 1, picH: 1, mini: "", dur: 0, file: null, main: null, rowKind: "",
                    fileName: "", wave: "", title: "", sub: "", spoiler: !!c.has_spoiler, heard: true }
        if (t === "messagePhoto" && c.photo && c.photo.sizes && c.photo.sizes.length) {
            const sizes = c.photo.sizes
            let best = sizes[sizes.length - 1]
            for (const z of sizes)
                if (z.width >= 320) {
                    best = z
                    break
                }
            Object.assign(r, { picKind: "photo", picW: best.width || 1, picH: best.height || 1, file: best.photo,
                               mini: c.photo.minithumbnail ? c.photo.minithumbnail.data : "" })
        } else if (t === "messageVideo" || t === "messageAnimation") {
            const v = t === "messageVideo" ? c.video : c.animation
            Object.assign(r, { picKind: t === "messageVideo" ? "video" : "gif", picW: v.width || 1, picH: v.height || 1,
                               dur: v.duration || 0, file: still(v.thumbnail), mini: v.minithumbnail ? v.minithumbnail.data : "",
                               main: t === "messageVideo" ? v.video : v.animation, fileName: v.file_name || "" })
        } else if (t === "messageSticker" && c.sticker) {
            const st = c.sticker
            Object.assign(r, { picKind: "sticker", picW: st.width || 1, picH: st.height || 1,
                               file: st.format && st.format["@type"] === "stickerFormatWebp" ? st.sticker : still(st.thumbnail) })
        } else if (t === "messageAnimatedEmoji" && c.animated_emoji && c.animated_emoji.sticker) {
            const st = c.animated_emoji.sticker
            const th = still(st.thumbnail)
            if (th)
                Object.assign(r, { picKind: "sticker", picW: st.width || 512, picH: st.height || 512, file: th })
        } else if (t === "messageVideoNote" && c.video_note) {
            const v = c.video_note
            Object.assign(r, { picKind: "round", picW: 1, picH: 1, dur: v.duration || 0, file: still(v.thumbnail),
                               mini: v.minithumbnail ? v.minithumbnail.data : "", heard: !!c.is_viewed })
        } else if (t === "messageVoiceNote" && c.voice_note) {
            const v = c.voice_note
            Object.assign(r, { rowKind: "voice", dur: v.duration || 0, wave: v.waveform || "", main: v.voice, heard: !!c.is_listened })
        } else if (t === "messageAudio" && c.audio) {
            const a = c.audio
            Object.assign(r, { rowKind: "audio", dur: a.duration || 0, main: a.audio, fileName: a.file_name || "",
                               title: a.title || a.file_name || Tr.t("Musiqa"), sub: a.performer || "" })
        } else if (t === "messageDocument" && c.document) {
            const d = c.document
            Object.assign(r, { rowKind: "file", main: d.document, fileName: d.file_name || "", file: still(d.thumbnail) })
        } else if (t === "messagePoll") {
            r.rowKind = "poll"
        } else if (t === "messageLocation" || t === "messageVenue" || t === "messageLiveLocation") {
            Object.assign(r, { picKind: "map", picW: 300, picH: 180 })
        }
        return r
    }

    function loadPic(id) {
        const f = picFiles[id]
        if (!f || !store)
            return
        const gen = loadGen
        store.fetch(f, 1, (path) => {
            if (!peek || gen !== peek.loadGen)
                return
            const i = peek.indexOf(id)
            if (i >= 0) {
                messages.setProperty(i, "pic", path)
                if (messages.get(i).album)
                    peek.albumTick++
            }
        })
    }

    function buildRow(m) {
        const ch = store && chatId ? store.chats[chatId] : null
        const grp = isGroupChat(ch)
        const chan = isChannelChat(ch)
        const c = m.content || { "@type": "" }
        const t = c["@type"]
        const words = store.plain(c)
        const v = t === "messageVenue" ? c.venue : null
        const ft = v ? { "@type": "formattedText", text: v.title + (v.address ? "\n" + v.address : ""),
                         entities: [{ "@type": "textEntity", offset: 0, length: v.title.length, type: { "@type": "textEntityTypeBold" } }] }
                     : store.formatted(c)
        const text = words !== null ? words : v ? (v.title + (v.address ? "\n" + v.address : ""))
                   : t === "messageLiveLocation" ? Tr.t("Jonli joylashuv") : (c.caption ? c.caption.text : "")
        const kind = words !== null || pictured.indexOf(t) >= 0 ? "" : store.kindOf(t)
        const p = extractMedia(c)
        if (p.file && (p.picKind !== "photo" || store.autoOk("photo", 0, chatId) || p.file.local.is_downloading_completed))
            picFiles[m.id] = p.file
        const r = m.reply_to && m.reply_to["@type"] === "messageReplyToMessage" ? m.reply_to : null
        let quote = null
        if (r && r.chat_id === chatId) {
            quote = quotes[r.message_id]
            if (!quote)
                wantQuote(r.message_id)
        } else if (r && r.content) {
            quote = { name: "", text: store.preview(r.content, store.chats[r.chat_id]) }
        }
        const sender = grp && !m.is_outgoing ? nameOf(m.sender_id) : ""
        const senderKey = JSON.stringify(m.sender_id || {})
        const sid = m.sender_id ? (m.sender_id.user_id || m.sender_id.chat_id || 0) : 0
        const rich = p.picKind === "sticker" && t === "messageAnimatedEmoji" ? "" : store.rich(ft, false)
        const plainWords = p.picKind === "sticker" && t === "messageAnimatedEmoji" ? "" : text
        const reacts = store.reactions(m.interaction_info, ch)
        return {
            msgId: m.id,
            out: !!m.is_outgoing,
            date: m.date || 0,
            text: plainWords,
            rich: rich,
            kind: kind,
            said: store.service(m, ch) || "",
            sender: sender,
            senderKey: senderKey,
            sending: !!m.sending_state,
            tint: store.tints[Math.abs(sid) % store.tints.length],
            time: m.date ? Qt.formatTime(new Date(m.date * 1000), "HH:mm") : "",
            views: m.interaction_info ? (m.interaction_info.view_count || 0) : 0,
            edited: (m.edit_date || 0) > 0,
            replyId: r ? r.message_id : 0,
            quoteName: quote ? quote.name : "",
            quoteText: quote ? quote.text : (r ? "..." : ""),
            picKind: p.picKind,
            picW: p.picW,
            picH: p.picH,
            mini: p.mini,
            dur: p.dur,
            edge: 0,
            pic: p.file && p.file.local && p.file.local.is_downloading_completed ? p.file.local.path : "",
            rowKind: p.rowKind,
            fileName: p.fileName,
            fileSize: p.main ? (p.main.size || p.main.expected_size || 0) : 0,
            wave: p.wave,
            title: p.title,
            sub: p.sub,
            path: p.main && p.main.local && p.main.local.is_downloading_completed ? p.main.local.path : "",
            jumbo: Prefs.largeEmoji && words !== null && !m.forward_info && p.picKind === "" ? store.emojiCount(words.trim()) : 0,
            fwd: store.origin(m.forward_info),
            reacts: reacts.length ? JSON.stringify(reacts) : "[]",
            isPinned: !!m.is_pinned,
            poll: t === "messagePoll" && c.poll ? JSON.stringify(c.poll) : "",
            album: m.media_album_id && m.media_album_id !== "0" && (p.picKind === "photo" || p.picKind === "video")
                   ? String(m.media_album_id) : "",
            veiled: p.spoiler,
            heard: p.heard || chan
        }
    }

    function indexOf(id) {
        const k = rowAt[id]
        if (k !== undefined && k >= 0 && k < messages.count && messages.get(k).msgId === id)
            return k
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).msgId === id)
                return i
        return -1
    }

    function rebuildIndexAndAlbums() {
        const g = {}
        const at = {}
        for (let i = 0; i < messages.count; i++) {
            const r = messages.get(i)
            at[r.msgId] = i
            if (!r.album)
                continue
            const a = g[r.album] || (g[r.album] = { ids: [], main: 0, words: 0 })
            a.ids.push(r.msgId)
            if (r.text && !a.words)
                a.words = r.msgId
        }
        for (const k in g) {
            g[k].ids.sort((a, b) => a - b)
            g[k].main = g[k].words || g[k].ids[0]
        }
        rowAt = at
        const key = JSON.stringify(g)
        if (key !== albumKey) {
            albumKey = key
            albums = g
            laidOut = {}
            albumRev++
        }
    }

    function beyond(index, step, album) {
        let k = index + step
        while (k >= 0 && k < messages.count && messages.get(k).album === album)
            k += step
        return k >= 0 && k < messages.count ? messages.get(k) : undefined
    }

    function cellOf(id) {
        const i = indexOf(id)
        if (i < 0)
            return null
        const r = messages.get(i)
        return { picKind: r.picKind, picW: r.picW, picH: r.picH, mini: r.mini, pic: r.pic, dur: r.dur,
                 got: -1, path: r.path, fileSize: r.fileSize, sending: r.sending, veiled: r.veiled,
                 rowKind: r.rowKind, fileName: r.fileName, wave: r.wave, title: r.title, sub: r.sub,
                 text: r.text, rich: r.rich, out: r.out }
    }

    function tilesOf(g, wide) {
        const key = g.ids.join(",") + "/" + Math.floor(wide) + "/" + Prefs.bubbleR
        if (laidOut[key])
            return laidOut[key]
        const cells = g.ids.map((id) => ({ id: id, c: cellOf(id) })).filter((x) => x.c)
        const lay = Mosaic.layout(cells.map((x) => ({ w: x.c.picW, h: x.c.picH })), Math.floor(wide), 54, 2)
        const round = (it, a, b) => it.sides.indexOf(a) >= 0 && it.sides.indexOf(b) >= 0
                                    ? Math.max(1, Prefs.bubbleR - 3) : Math.min(3, Math.max(1, Prefs.bubbleR - 3))
        lay.items.forEach((it, k) => {
            it.id = cells[k].id
            it.corner = [round(it, "t", "l"), round(it, "t", "r"), round(it, "b", "r"), round(it, "b", "l")].join(",")
        })
        if (cells.length === g.ids.length)
            laidOut[key] = lay
        return lay
    }

    function otherDay(other, date) {
        return !other || Math.floor((other.date - tzSec) / 86400) !== Math.floor((date - tzSec) / 86400)
    }

    function dayName(unix) {
        const d = new Date(unix * 1000), now = new Date()
        if (d.toDateString() === now.toDateString())
            return Tr.t("Bugun")
        if (d.toDateString() === new Date(now - 86400000).toDateString())
            return Tr.t("Kecha")
        return Tr.date(d.getDate(), d.getMonth() + 1, d.getFullYear() !== now.getFullYear() ? d.getFullYear() : 0)
    }

    function apart(other, senderKey, date) {
        return !other || other.senderKey !== senderKey || Math.abs(other.date - date) > 600
    }

    function clock(secs) {
        return Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0")
    }

    // Hit-test viewport coordinates (vx, vy) inside peekList -> message id, or 0 for empty wallpaper
    function msgAt(vx, vy) {
        const cy = vy + peekList.contentY
        const row = peekList.itemAt(vx, cy)
        if (!row || row.tucked || !row.hitBubble)
            return 0
        return row.hitBubble(vx - row.x, cy - row.y)
    }

    // ---- Background (same Wallpaper + night dim as ChatPage, rounded to cardRadius) ----
    Wallpaper {
        anchors.fill: parent
        radius: peek.cardRadius
        spec: peek.wallSpec || Theme.wall
    }
    Rectangle {
        anchors.fill: parent
        radius: peek.cardRadius
        color: "black"
        opacity: Theme.dark && peek.wallSpec ? peek.wallDim : 0
        visible: opacity > 0
    }

    // ---- Scrollable message list (BottomToTop, chunked history on scroll up) ----
    ListView {
        id: peekList
        anchors.fill: parent
        anchors.topMargin: peek.topInset
        clip: true
        model: messages
        verticalLayoutDirection: ListView.BottomToTop
        boundsBehavior: Flickable.DragOverBounds
        cacheBuffer: 400
        maximumFlickVelocity: 5000
        flickDeceleration: 2200
        header: Item { width: 1; height: 12 }
        footer: Item {
            width: peekList.width
            height: peek.loadingOlder ? 34 : 10
            Ring {
                visible: peek.loadingOlder
                anchors.centerIn: parent
                width: 20; height: 20
                color: "white"
                value: 0.72
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    running: peek.loadingOlder && peek.visible
                }
            }
        }
        onDragStarted: peek.userScrolled = true
        onContentYChanged: peek.nearTop()
        onMovementEnded: peek.nearTop()

        delegate: Item {
            id: shell
            required property int index
            required property var msgId
            required property bool out
            required property string text
            required property string rich
            required property string kind
            required property string said
            required property string sender
            required property string senderKey
            required property string tint
            required property string time
            required property bool sending
            required property int views
            required property int date
            required property bool edited
            required property var replyId
            required property string quoteName
            required property string quoteText
            required property string picKind
            required property int picW
            required property int picH
            required property string mini
            required property string pic
            required property int dur
            required property int edge
            required property string rowKind
            required property string fileName
            required property real fileSize
            required property string wave
            required property string title
            required property string sub
            required property string path
            required property int jumbo
            required property string fwd
            required property string reacts
            required property bool isPinned
            required property string poll
            required property string album
            required property bool veiled
            required property bool heard

            readonly property var group: album !== "" && peek.albumRev >= 0 ? (peek.albums[album] || null) : null
            readonly property bool grouped: group !== null && group.ids.length > 1
            readonly property bool tucked: grouped && group.main !== msgId
            readonly property bool media: picKind !== ""
            readonly property bool simpleText: !tucked && said === "" && picKind === "" && rowKind === ""
                && jumbo === 0 && rich === "" && kind === "" && fwd === ""
                && reacts.length <= 2 && views === 0 && peek.firstUnread !== msgId

            function hitBubble(lx, ly) {
                return look.item && look.item.hitBubble ? look.item.hitBubble(lx, ly) : 0
            }

            Component.onCompleted: {
                if ((media || rowKind === "file") && !pic)
                    peek.loadPic(msgId)
            }

            width: peekList.width
            height: look.item ? look.item.height : 0
            visible: !tucked

            Loader {
                id: look
                active: !shell.tucked
                width: shell.width
                readonly property Item rowShell: shell
                sourceComponent: shell.said !== "" ? saidRowComp
                               : shell.simpleText ? simpleTextRowComp
                               : richRowComp
            }
        }

        // Single list-level tap handler (scroll drags are stolen smoothly by ListView)
        MouseArea {
            id: peekHit
            anchors.fill: parent
            enabled: peek.active
            property real x0: 0
            property real y0: 0
            property bool moved: false
            onPressed: (m) => {
                x0 = m.x; y0 = m.y; moved = false
                peek.pressedMsgId = peek.msgAt(m.x, m.y)
            }
            onPositionChanged: (m) => {
                if (!moved && Math.hypot(m.x - x0, m.y - y0) > 10) {
                    moved = true
                    peek.pressedMsgId = 0
                }
            }
            onCanceled: {
                moved = false
                peek.pressedMsgId = 0
            }
            onReleased: {
                peek.pressedMsgId = 0
            }
            onClicked: (m) => {
                if (moved)
                    return
                const id = peek.msgAt(m.x, m.y)
                peek.picked(peek.chatId, id)
            }
        }
    }

    // Empty / loading placeholder
    Rectangle {
        visible: messages.count === 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, emptyLbl.implicitWidth + 28)
        height: emptyLbl.implicitHeight + 16
        radius: 14
        color: Theme.dayPill
        Text {
            id: emptyLbl
            anchors.centerIn: parent
            text: peek.loadingInitial ? Tr.t("Xabarlar yuklanmoqda…") : Tr.t("Xabarlar yo'q")
            color: "white"
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
        }
    }

    // ---- Shared lightweight components for delegates ----
    Component {
        id: dayPillComp
        Rectangle {
            readonly property Item msg: parent.msg
            width: dayText.implicitWidth + 16; height: 22; radius: 11
            color: Theme.dayPill
            Text {
                id: dayText
                anchors.centerIn: parent
                text: peek.dayName(parent.msg.shell.date)
                color: "white"
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }
    }

    Component {
        id: unreadBarComp
        Rectangle {
            x: 8; width: parent ? parent.width - 16 : 0; height: parent ? parent.height : 24
            radius: 10
            color: Theme.bar
            Text {
                anchors.centerIn: parent
                text: Tr.t("O'qilmagan xabarlar")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    Component {
        id: faceComp
        Avatar {
            id: msgFace
            readonly property Item host: parent
            width: 30; height: 30
            letters: peek.store ? peek.store.letters(host.name) : ""
            tint: host.tint
            Component.onCompleted: {
                if (!peek.store)
                    return
                const s = JSON.parse(host.key)
                const u = s.user_id && peek.store.users[s.user_id]
                if (u && u.type && u.type["@type"] === "userTypeDeleted")
                    msgFace.ghost = true
                else if (s.user_id)
                    peek.store.userPhoto(peek.store.users[s.user_id], (path) => { if (msgFace) msgFace.source = path })
                else if (peek.store.chats[s.chat_id]) {
                    peek.store.watchPhoto(peek.store.chats[s.chat_id])
                    msgFace.source = peek.store.photoPath(peek.store.chats[s.chat_id])
                }
            }
        }
    }

    Component {
        id: quoteComp
        Rectangle {
            id: answer
            readonly property Item item: parent.msg
            readonly property Item sh: item.shell
            readonly property color ink: item.bare ? "white" : sh.out ? Theme.check : Theme.accent
            readonly property real wants: Math.max(quoteWho.implicitWidth, Math.min(quoteWhat.implicitWidth, 200)) + 20
            radius: 6
            color: item.bare ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(ink.r, ink.g, ink.b, 0.12)
            clip: true
            Rectangle { width: 3; height: parent.height; color: answer.ink }
            Text {
                id: quoteWho
                x: 10; y: 3
                width: parent.width - 14
                elide: Text.ElideRight
                text: answer.sh.quoteName
                color: answer.ink
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            Text {
                id: quoteWhat
                x: 10; y: 19
                width: parent.width - 14
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.StyledText
                text: Emo.emojify(peek.store ? peek.store.escaped(answer.sh.quoteText.replace(/\s+/g, " ")) : "", 15)
                color: answer.item.bare ? "white" : answer.sh.out ? Theme.outText : Theme.inText
                font.family: Theme.font; font.pixelSize: 13
            }
        }
    }

    // Read-only rich text block renderer for Words.qml (no MouseAreas -> taps reach peekHit cleanly)
    Component {
        id: peekRichComp
        Item {
            id: richWrap
            required property Item words
            width: words ? words.width : 0
            height: col.height
            readonly property real wants: col.wants
            readonly property real last: col.last

            Column {
                id: col
                width: parent.width
                spacing: 4
                property real wants: 0
                readonly property real last: {
                    const it = partsRep.count ? partsRep.itemAt(partsRep.count - 1) : null
                    return it ? it.last : 0
                }
                function recalc() {
                    let w = 0
                    for (let i = 0; i < partsRep.count; i++) {
                        const it = partsRep.itemAt(i)
                        if (it)
                            w = Math.max(w, it.wants)
                    }
                    wants = w
                }
                Repeater {
                    id: partsRep
                    model: richWrap.words ? richWrap.words.list : []
                    Item {
                        id: part
                        required property var modelData
                        readonly property string q: modelData.q || ""
                        readonly property bool boxed: q !== ""
                        readonly property real padL: boxed ? 10 : 0
                        readonly property real padR: boxed ? 10 : 0
                        readonly property real padV: boxed ? 6 : 0
                        readonly property real room: Math.max(20, (richWrap.words ? richWrap.words.room : 200) - padL - padR)
                        readonly property real wants: Math.min(richWrap.words ? richWrap.words.room : 200,
                                                               (txt.lineCount > 1 ? room : txt.contentWidth) + padL + padR)
                        property real last: 0
                        width: richWrap.width
                        height: txt.implicitHeight + padV * 2
                        onWantsChanged: col.recalc()
                        Component.onCompleted: col.recalc()

                        Rectangle {
                            visible: part.boxed
                            anchors.fill: parent
                            radius: 6
                            color: richWrap.words ? Qt.rgba(richWrap.words.tint.r, richWrap.words.tint.g, richWrap.words.tint.b, 0.12) : "transparent"
                            clip: true
                            Rectangle {
                                visible: part.q !== "pre"
                                width: 3; height: parent.height
                                color: richWrap.words ? richWrap.words.tint : Theme.accent
                            }
                        }
                        Text {
                            id: txt
                            x: part.padL; y: part.padV
                            width: part.room
                            wrapMode: Text.Wrap
                            maximumLineCount: part.q === "fold" ? 3 : 0
                            elide: part.q === "fold" ? Text.ElideRight : Text.ElideNone
                            textFormat: Text.StyledText
                            // Mask spoilers in preview so hidden text is not revealed
                            text: (part.modelData.h || "").replace(/<a href="spoiler">.*?<\/a>/g, "••••")
                            color: richWrap.words ? richWrap.words.ink : Theme.text
                            linkColor: richWrap.words ? richWrap.words.tint : Theme.accent
                            font.family: part.q === "pre" ? "monospace" : Theme.font
                            font.pixelSize: richWrap.words ? (part.q === "pre" ? Math.max(12, richWrap.words.size - 2) : richWrap.words.size) : 15
                            onLineLaidOut: (line) => { if (line.isLast) part.last = line.implicitWidth + part.padL + part.padR }
                        }
                    }
                }
            }
        }
    }

    // ---- Service message row (centered pill, same as ChatPage) ----
    Component {
        id: saidRowComp
        Item {
            id: saidItem
            readonly property Item shell: parent.rowShell
            readonly property bool newDay: {
                void shell.edge
                return peek.otherDay(messages.get(shell.index + 1), shell.date)
            }
            readonly property real above: (newDay ? 34 : 0) + 6
            function hitBubble(lx, ly) {
                return (lx >= pill.x - 6 && lx <= pill.x + pill.width + 6
                        && ly >= pill.y - 6 && ly <= pill.y + pill.height + 6) ? shell.msgId : 0
            }
            width: shell.width
            height: above + pill.height + 6

            Loader {
                active: saidItem.newDay
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                readonly property Item msg: saidItem
                sourceComponent: dayPillComp
            }
            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                y: saidItem.above
                width: Math.min(parent.width - 36, saidTxt.implicitWidth + 18)
                height: saidTxt.implicitHeight + 8
                radius: height / 2
                color: Theme.dayPill
                opacity: peek.pressedMsgId === saidItem.shell.msgId ? 0.72 : 1
                Text {
                    id: saidTxt
                    anchors.centerIn: parent
                    width: parent.width - 18
                    text: saidItem.shell.said
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
        }
    }

    // ---- Fast plain-text bubble row (same BorderImage & layout as ChatPage simpleTextRowComp) ----
    Component {
        id: simpleTextRowComp
        Item {
            id: item
            readonly property Item shell: parent.rowShell
            readonly property bool out: shell.out
            readonly property bool bare: false
            readonly property string sender: shell.sender
            readonly property bool first: {
                void shell.edge
                return peek.apart(messages.get(shell.index + 1), shell.senderKey, shell.date)
            }
            readonly property bool last: peek.apart(messages.get(shell.index - 1), shell.senderKey, shell.date)
            readonly property bool newDay: {
                void shell.edge
                return peek.otherDay(messages.get(shell.index + 1), shell.date)
            }
            readonly property bool faced: sender !== ""
            readonly property real most: width * 0.80
            readonly property real above: (newDay ? 34 : 0) + (first ? 7 : 2)
            function hitBubble(lx, ly) {
                return (lx >= bubble.x - 6 && lx <= bubble.x + bubble.width + 6
                        && ly >= bubble.y - 6 && ly <= bubble.y + bubble.height + 6) ? shell.msgId : 0
            }
            width: shell.width
            height: bubble.height + above

            Loader {
                active: item.newDay
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                readonly property Item msg: item
                sourceComponent: dayPillComp
            }
            Loader {
                active: item.faced && item.last
                x: 8; y: bubble.y + bubble.height - 30
                width: 30; height: 30
                readonly property string name: item.sender
                readonly property string key: item.shell.senderKey
                readonly property string tint: item.shell.tint
                sourceComponent: faceComp
            }
            Item {
                id: bubble
                y: item.above
                x: item.out ? item.width - width - 12 : 12 + (item.faced ? 36 : 0)
                opacity: peek.pressedMsgId === item.shell.msgId ? 0.78 : 1
                readonly property real room: item.most - 22
                readonly property real bodyW: body.lineCount > body.paragraphs ? room : body.contentWidth
                readonly property real stampRoom: stamp.implicitWidth + 8
                readonly property bool stampUnder: body.last + stampRoom > room
                width: Math.min(item.most, Math.max(bodyW, who.visible ? who.implicitWidth : 0,
                                                    quote.visible ? quote.wants : 0,
                                                    stampUnder ? stamp.implicitWidth : body.last + stampRoom) + 22)
                height: body.y + body.implicitHeight + (stampUnder ? 22 : 8)

                BorderImage {
                    readonly property real d: peek.dpr
                    x: item.out ? 0 : -6
                    width: (parent.width + 6) * d; height: parent.height * d
                    scale: 1 / d; transformOrigin: Item.TopLeft
                    readonly property int r: Prefs.bubbleR
                    readonly property int b: Prefs.bubbleB
                    border { left: (item.out ? r : b + 6) * d; right: (item.out ? b + 6 : r) * d; top: r * d; bottom: b * d }
                    source: "image://bubble/" + (item.out ? "out/" : "in/") + (item.first ? "b/" : "s/") + (item.last ? "t/" : "s/")
                          + String(item.out ? Theme.bubbleOut : Theme.bubbleIn).slice(1) + "/" + d
                          + "/" + r + "/" + Prefs.bubbleS
                    smooth: true
                }
                Text {
                    id: who
                    visible: item.faced && item.first
                    x: 11; y: 6
                    width: Math.min(implicitWidth, bubble.room)
                    elide: Text.ElideRight
                    text: visible ? item.sender : ""
                    color: item.shell.tint
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Loader {
                    id: quote
                    active: item.shell.replyId !== 0
                    visible: active
                    readonly property real wants: quote.item ? quote.item.wants : 0
                    x: 7; y: who.visible ? who.y + who.height + 3 : 7
                    width: bubble.width - 14; height: visible ? 38 : 0
                    readonly property Item msg: item
                    sourceComponent: quoteComp
                }
                Text {
                    id: body
                    readonly property real boxW: Math.min(bubble.bodyW, bubble.room)
                    x: 11 + (effectiveHorizontalAlignment === Text.AlignRight ? boxW - width : 0)
                    y: quote.visible ? quote.y + quote.height + 4 : who.visible ? who.y + who.height + 2 : 7
                    width: bubble.room
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    property real last: 0
                    onLineLaidOut: (line) => { if (line.isLast) last = line.implicitWidth }
                    text: item.shell.text
                    readonly property int paragraphs: text.indexOf("\n") < 0 && text.indexOf("\u2028") < 0 ? 1 : text.split(/[\n\u2028]/).length
                    color: item.out ? Theme.outText : Theme.inText
                    font.family: Theme.font; font.pixelSize: Prefs.chatSize
                }
                Text {
                    id: stamp
                    anchors.right: parent.right; anchors.rightMargin: 9
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                    textFormat: item.out && !item.shell.sending ? Text.StyledText : Text.PlainText
                    text: (item.shell.isPinned ? "📌 " : "") + (item.shell.edited ? Tr.t("tahrirlandi") + " " : "") + item.shell.time
                          + (item.out ? (item.shell.sending ? " ◷" : " <font color='" + Theme.check + "'>" + (item.shell.msgId <= peek.readUpTo ? "✓✓" : "✓") + "</font>") : "")
                    color: item.out ? Theme.outMeta : Theme.inMeta
                    font.family: Theme.font; font.pixelSize: 11
                }
            }
        }
    }

    // ---- Full media / rich / attachment / album row ----
    Component {
        id: richRowComp
        Item {
            id: item
            readonly property Item shell: parent.rowShell
            readonly property bool out: shell.out
            readonly property string sender: shell.sender
            readonly property var group: shell.group
            readonly property bool grouped: shell.grouped
            readonly property bool mosaic: grouped && group.main === shell.msgId
            readonly property var tiles: mosaic ? peek.tilesOf(group, wide) : null
            readonly property var ids: grouped ? group.ids : [shell.msgId]
            readonly property bool media: shell.picKind !== ""
            readonly property bool bare: shell.picKind === "sticker" || shell.picKind === "round" || shell.jumbo > 0
            readonly property real aspect: shell.picH / Math.max(shell.picW, 1)
            readonly property real wide: Math.min(width * 0.72, 232)
            readonly property real pw: mosaic ? tiles.width
                                     : shell.picKind === "round" ? 156
                                     : shell.picKind === "sticker" ? 128 * Math.min(1, 1 / aspect)
                                     : aspect * wide > 260 ? Math.max(120, 260 / aspect) : wide
            readonly property real ph: mosaic ? tiles.height
                                     : shell.picKind === "round" ? 156
                                     : shell.picKind === "sticker" ? 128 * Math.min(1, aspect)
                                     : Math.max(96, Math.min(260, aspect * wide))
            readonly property var reactList: shell.reacts.length > 2 ? JSON.parse(shell.reacts) : []
            readonly property bool reacted: reactList.length > 0
            readonly property bool overlaid: media && shell.text === "" && !reacted
            readonly property bool first: {
                void shell.edge
                return grouped ? peek.apart(peek.beyond(shell.index, 1, shell.album), shell.senderKey, shell.date)
                               : peek.apart(messages.get(shell.index + 1), shell.senderKey, shell.date)
            }
            readonly property bool last: grouped ? peek.apart(peek.beyond(shell.index, -1, shell.album), shell.senderKey, shell.date)
                                                 : peek.apart(messages.get(shell.index - 1), shell.senderKey, shell.date)
            readonly property bool newDay: {
                void shell.edge
                return grouped ? peek.otherDay(peek.beyond(shell.index, 1, shell.album), shell.date)
                               : peek.otherDay(messages.get(shell.index + 1), shell.date)
            }
            readonly property bool unreadBar: peek.firstUnread !== 0
                                              && (shell.msgId === peek.firstUnread || (grouped && ids.indexOf(peek.firstUnread) >= 0))
            readonly property bool faced: sender !== ""
            readonly property real most: width * 0.80
            readonly property real above: (newDay ? 34 : 0) + (unreadBar ? 32 : 0) + (first ? 7 : 2)

            function hitBubble(lx, ly) {
                if (lx < bubble.x - 6 || lx > bubble.x + bubble.width + 6
                        || ly < bubble.y - 6 || ly > bubble.y + bubble.height + 6)
                    return 0
                if (mosaic && picture.item && picture.item.tileAt) {
                    const t = picture.item.tileAt(lx - bubble.x - picture.x, ly - bubble.y - picture.y)
                    if (t && t.msgId)
                        return t.msgId
                }
                return shell.msgId
            }

            width: shell.width
            height: bubble.height + above

            Loader {
                active: item.newDay
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                readonly property Item msg: item
                sourceComponent: dayPillComp
            }
            Loader {
                active: item.unreadBar
                y: (item.newDay ? 34 : 0) + 4
                width: parent.width; height: 24
                sourceComponent: unreadBarComp
            }
            Loader {
                active: item.faced && item.last
                x: 8; y: bubble.y + bubble.height - 30
                width: 30; height: 30
                readonly property string name: item.sender
                readonly property string key: item.shell.senderKey
                readonly property string tint: item.shell.tint
                sourceComponent: faceComp
            }

            Item {
                id: bubble
                y: item.above
                x: item.out ? item.width - width - 12 : 12 + (item.faced ? 36 : 0)
                opacity: peek.pressedMsgId !== 0 && item.ids.indexOf(peek.pressedMsgId) >= 0 ? 0.78 : 1
                readonly property real stampRoom: stamp.implicitWidth + 8
                readonly property bool stampUnder: !item.overlaid && body.last + stampRoom > (item.media ? width : item.most) - 22
                readonly property bool hasWho: item.faced && item.first && !item.bare
                readonly property bool hasFwd: item.shell.fwd !== "" && !item.bare
                readonly property real headW: Math.max(hasWho ? whoTxt.implicitWidth : 0, hasFwd ? fwdCol.implicitWidth : 0)
                width: item.shell.jumbo ? Math.max(body.implicitWidth, stamp.implicitWidth + 12) + 8
                     : item.bare ? item.pw
                     : item.media ? item.pw + 6
                     : Math.min(item.most, Math.max(body.implicitWidth, headW, quote.visible ? quote.wants : 0,
                                                    attach.visible ? attach.attW : 0,
                                                    item.reacted ? reactFlow.implicitWidth + stamp.implicitWidth + 6 : 0,
                                                    stampUnder ? stamp.implicitWidth : body.last + stampRoom) + 22)
                height: item.shell.jumbo ? body.y + body.height + 24
                      : item.overlaid ? picture.y + item.ph + (item.bare ? 0 : 3)
                      : item.reacted ? reactFlow.y + reactFlow.height + 6
                      : body.y + body.height + (stampUnder ? 22 : 8)

                BorderImage {
                    readonly property real d: peek.dpr
                    x: item.out ? 0 : -6
                    width: (parent.width + 6) * d; height: parent.height * d
                    scale: 1 / d; transformOrigin: Item.TopLeft
                    readonly property int r: Prefs.bubbleR
                    readonly property int b: Prefs.bubbleB
                    border { left: (item.out ? r : b + 6) * d; right: (item.out ? b + 6 : r) * d; top: r * d; bottom: b * d }
                    source: item.bare ? ""
                          : "image://bubble/" + (item.out ? "out/" : "in/") + (item.first ? "b/" : "s/") + (item.last ? "t/" : "s/")
                            + String(item.out ? Theme.bubbleOut : Theme.bubbleIn).slice(1) + "/" + d
                            + "/" + r + "/" + Prefs.bubbleS
                    smooth: true
                    visible: !item.bare
                }

                Text {
                    id: whoTxt
                    visible: bubble.hasWho
                    x: 11; y: 6
                    width: Math.min(implicitWidth, bubble.width - 22)
                    elide: Text.ElideRight
                    text: visible ? item.sender : ""
                    color: item.shell.tint
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Column {
                    id: fwdCol
                    visible: bubble.hasFwd
                    x: 11; y: whoTxt.visible ? whoTxt.y + whoTxt.height + 1 : 6
                    Text {
                        width: Math.min(implicitWidth, bubble.width - 22)
                        elide: Text.ElideRight
                        text: Tr.t("Uzatilgan xabar")
                        color: item.out ? Theme.check : Theme.accent
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Text {
                        width: Math.min(implicitWidth, bubble.width - 22)
                        elide: Text.ElideRight
                        text: item.shell.fwd
                        color: item.out ? Theme.check : Theme.accent
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                readonly property real headBottom: fwdCol.visible ? fwdCol.y + fwdCol.height
                                                 : whoTxt.visible ? whoTxt.y + whoTxt.height : 0

                Loader {
                    id: quote
                    active: item.shell.replyId !== 0
                    visible: active
                    readonly property real wants: quote.item ? quote.item.wants : 0
                    x: item.bare ? 0 : 7
                    y: bubble.headBottom > 0 ? bubble.headBottom + 3 : 7
                    width: Math.max(60, bubble.width - (item.bare ? 0 : 14))
                    height: visible ? 38 : 0
                    readonly property Item msg: item
                    sourceComponent: quoteComp
                }

                // Media: single photo/video/gif/sticker/round/map OR mosaic album
                Loader {
                    id: picture
                    visible: item.media
                    active: item.media && !item.shell.tucked
                    x: item.bare ? 0 : 3
                    y: item.bare ? 0 : quote.visible ? quote.y + quote.height + 4 : bubble.headBottom > 0 ? bubble.headBottom + 4 : 3
                    width: item.pw; height: visible ? item.ph : 0
                    readonly property string corner: item.shell.picKind === "round" ? "-1" : item.bare ? "0" : String(Math.max(1, Prefs.bubbleR - 3))
                    readonly property Item msg: item
                    sourceComponent: item.mosaic ? albumTilesComp : singlePicComp
                }

                // Attachments: AudioRow (voice/audio), FileRow (document), PollView (poll, read-only)
                Loader {
                    id: attach
                    visible: item.shell.rowKind !== ""
                    active: !item.shell.tucked && item.shell.rowKind !== "" && (item.shell.rowKind !== "poll" || item.shell.poll !== "")
                    x: 11
                    y: quote.visible ? quote.y + quote.height + 5 : bubble.headBottom > 0 ? bubble.headBottom + 4 : 6
                    readonly property Item msg: item
                    readonly property real attW: attach.item ? attach.item.width : 0
                    readonly property real attH: attach.item ? attach.item.height : 0
                    sourceComponent: item.shell.rowKind === "voice" || item.shell.rowKind === "audio" ? audioRowComp
                                   : item.shell.rowKind === "poll" ? pollRowComp
                                   : item.shell.rowKind === "file" ? fileRowComp : null
                }

                Words {
                    id: body
                    richComponent: peekRichComp
                    visible: !item.overlaid
                    x: item.shell.jumbo ? 4 : 11
                    y: item.media ? picture.y + picture.height + 5
                     : attach.visible ? attach.y + attach.attH + (text || parts ? 4 : 0)
                     : quote.visible && !item.bare ? quote.y + quote.height + 4
                     : bubble.headBottom > 0 ? bubble.headBottom + 2 : item.shell.jumbo ? 0 : 7
                    height: (attach.visible || item.media) && !text && !parts ? 0 : implicitHeight
                    width: item.media ? bubble.width - 22
                         : attach.visible ? Math.max(attach.attW, Math.min(implicitWidth, item.most - 22))
                         : Math.min(implicitWidth, item.most - 22)
                    live: false
                    room: item.media ? bubble.width - 22
                        : attach.visible ? Math.max(attach.attW, item.most - 22) : item.most - 22
                    text: (item.shell.kind ? "[" + item.shell.kind + "] " : "") + item.shell.text
                    parts: item.shell.kind ? "" : item.shell.rich
                    ink: item.out ? Theme.outText : Theme.inText
                    tint: item.out ? Theme.check : Theme.accent
                    size: item.shell.jumbo === 1 ? 68 : item.shell.jumbo === 2 ? 56 : item.shell.jumbo === 3 ? 46 : Prefs.chatSize
                }

                // Read-only reaction pills
                Flow {
                    id: reactFlow
                    visible: item.reacted
                    x: item.bare ? 0 : 9
                    y: body.y + body.height + (body.height ? 5 : 3)
                    width: Math.max(40, bubble.width - x - 9)
                    spacing: 4
                    height: visible ? implicitHeight + 16 : 0
                    Repeater {
                        model: item.reactList
                        Rectangle {
                            required property var modelData
                            readonly property color ink: item.bare ? "white" : item.out ? Theme.check : Theme.accent
                            width: rTxt.implicitWidth + 14; height: 24; radius: 12
                            color: modelData.mine ? ink : item.bare ? Theme.dayPill : Qt.rgba(ink.r, ink.g, ink.b, 0.15)
                            Text {
                                id: rTxt
                                anchors.centerIn: parent
                                text: (modelData.paid ? "⭐ " : (modelData.e || "") + " ") + (modelData.n || 1)
                                color: modelData.mine ? (item.bare ? "#1c1c1e" : "white") : parent.ink
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // Dark pill behind stamp when overlaid on photo/sticker/jumbo
                Rectangle {
                    visible: item.overlaid || item.shell.jumbo > 0 || item.bare
                    z: 0.5
                    anchors.fill: stamp
                    anchors.margins: -3; anchors.leftMargin: -6; anchors.rightMargin: -6
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.42)
                }
                Row {
                    id: stamp
                    z: 1
                    anchors.right: parent.right; anchors.rightMargin: item.overlaid || item.shell.jumbo ? (item.bare ? 8 : 11) : 9
                    anchors.bottom: parent.bottom; anchors.bottomMargin: item.overlaid || item.shell.jumbo ? (item.bare ? 6 : 9) : 5
                    spacing: 2
                    readonly property color ink: item.overlaid || item.shell.jumbo || item.bare ? "white" : item.out ? Theme.outMeta : Theme.inMeta
                    Icon {
                        visible: item.shell.views > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13; height: 13
                        name: "eye"; color: stamp.ink
                    }
                    Text {
                        visible: item.shell.views > 0
                        text: peek.store ? peek.store.short(item.shell.views) + " " : ""
                        color: stamp.ink
                        font.family: Theme.font; font.pixelSize: 11
                    }
                    Text {
                        textFormat: item.out && !item.shell.sending ? Text.StyledText : Text.PlainText
                        text: (item.shell.isPinned ? "📌 " : "") + (item.shell.edited ? Tr.t("tahrirlandi") + " " : "") + item.shell.time
                              + (item.out ? (item.shell.sending ? " ◷" : " <font color='" + (item.overlaid || item.shell.jumbo ? "white" : Theme.check) + "'>" + (item.shell.msgId <= peek.readUpTo ? "✓✓" : "✓") + "</font>") : "")
                        color: stamp.ink
                        font.family: Theme.font; font.pixelSize: 11
                    }
                }
            }
        }
    }

    Component {
        id: singlePicComp
        Item {
            id: block
            readonly property Item host: parent
            readonly property Item item: host.msg
            readonly property Item sh: item.shell
            readonly property string corner: host.corner

            Image {
                anchors.fill: parent
                visible: block.sh.mini !== "" && full.status !== Image.Ready
                asynchronous: true
                sourceSize: Qt.size(12, Math.max(8, 12 * block.item.ph / Math.max(block.item.pw, 1)))
                source: block.sh.mini ? "image://pic/" + block.corner + "/" + Math.round(block.item.pw) + "/mini/" + block.sh.mini : ""
                smooth: true
            }
            Image {
                id: full
                anchors.fill: parent
                asynchronous: true
                sourceSize: Qt.size(Math.round(block.item.pw), Math.round(block.item.ph))
                source: block.sh.pic ? "image://pic/" + block.corner + "/" + Math.round(block.item.pw) + "/" + block.sh.pic : ""
                opacity: status === Image.Ready ? 1 : 0
                smooth: true
            }
            Loader {
                anchors.fill: parent
                active: block.sh.veiled
                sourceComponent: Veil {
                    corner: block.corner
                    mini: block.sh.mini
                    pic: block.sh.pic
                    live: false
                }
            }
            Rectangle {
                visible: block.sh.picKind === "video" || block.sh.picKind === "round" || block.sh.picKind === "gif"
                anchors.centerIn: parent
                width: 40; height: 40; radius: 20
                color: Qt.rgba(0, 0, 0, 0.45)
                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1.5
                    width: 20; height: 20
                    name: "play"
                    color: "white"
                }
            }
            Icon {
                visible: block.sh.picKind === "map"
                x: (parent.width - width) / 2; y: parent.height / 2 - height + 3
                width: 34; height: 34
                name: "place"
                color: Theme.danger
            }
            Rectangle {
                visible: block.sh.picKind === "video" || block.sh.picKind === "gif" || block.sh.picKind === "round"
                x: 6; y: block.sh.picKind === "round" ? parent.height - 24 : 6
                width: lenTxt.implicitWidth + 10; height: 18; radius: 9
                color: Qt.rgba(0, 0, 0, 0.45)
                Text {
                    id: lenTxt
                    anchors.centerIn: parent
                    text: block.sh.picKind === "gif" ? "GIF" : peek.clock(block.sh.dur)
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 11
                }
            }
        }
    }

    Component {
        id: albumTilesComp
        Item {
            id: tilesView
            readonly property Item item: parent.msg
            function tileAt(x, y) {
                const t = tilesView.childAt(x, y)
                return t && t.msgId ? t : null
            }
            Repeater {
                model: tilesView.item && tilesView.item.tiles ? tilesView.item.tiles.items : []
                AlbumTile {
                    required property var modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    msgId: modelData.id
                    corner: modelData.corner
                    cell: {
                        void peek.albumTick
                        void peek.albumRev
                        return peek.cellOf(modelData.id)
                    }
                    live: false
                    inSight: true
                    lowRes: false
                    Component.onCompleted: if (!pic) peek.loadPic(msgId)
                }
            }
        }
    }

    Component {
        id: audioRowComp
        AudioRow {
            readonly property Item sh: parent.msg.shell
            width: Math.min(220, parent.msg.most - 22)
            dpr: peek.dpr
            kind: sh.rowKind === "audio" ? "audio" : "voice"
            out: sh.out
            wave: sh.wave
            dur: sh.dur
            title: sh.title
            sub: sh.sub
            got: -1
            here: sh.path !== ""
            fresh: !sh.heard
        }
    }

    Component {
        id: fileRowComp
        FileRow {
            readonly property Item sh: parent.msg.shell
            width: Math.min(220, parent.msg.most - 22)
            out: sh.out
            name: sh.fileName
            size: sh.fileSize
            got: -1
            here: sh.path !== ""
            thumb: sh.pic
        }
    }

    Component {
        id: pollRowComp
        PollView {
            readonly property Item sh: parent.msg.shell
            width: Math.min(230, parent.msg.most - 22)
            enabled: false
            out: sh.out
            poll: JSON.parse(sh.poll)
        }
    }
}
