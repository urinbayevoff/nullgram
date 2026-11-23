// One chat: the messages from the bottom up, a header over them and the field
// under them. It is `ready` once its newest messages are laid out, so the push
// moves a finished page. A long press on a message opens its menu (MessageMenu):
// reply, copy, edit, save, delete. Media: a GIF plays in its bubble, a video full screen
// (PhotoViewer), a voice note or a song with the page's one player, a file comes down with a
// ring round it; the clip sends pictures and files (AttachSheet), the mic held records a voice note.
import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import QtMultimedia
import "Mosaic.js" as Mosaic

Page {
    id: page
    required property var chatId
    property var target: 0              // open at this message (found by search) and light it up
    property var flashId: 0
    readonly property var chat: store.chats[chatId]
    // our messages up to this one are read by the other side (✓✓ by their time, as the chat list has it); TDLib's
    // updateChatReadOutbox moves it (Store.readOutbox; the chat object is changed in place, so not a binding)
    property real readUpTo: chat ? (chat.last_read_outbox_message_id || 0) : 0
    readonly property bool group: chat && (chat.type["@type"] === "chatTypeBasicGroup" ||
                                           (chat.type["@type"] === "chatTypeSupergroup" && !chat.type.is_channel))
    readonly property bool channel: chat && chat.type["@type"] === "chatTypeSupergroup" && chat.type.is_channel
    property bool canGift: false        // a gift may be sent to this channel (supergroupFullInfo.can_send_gift): 🎁 on its bar
    property var directChatId: 0        // a channel's direct messages chat (supergroupFullInfo.direct_messages_chat_id)
    property var directTopic: 0         // a subscriber's thread in an administered channel direct messages chat
    property var directSender: null     // MessageSender of that directTopic
    property bool directCanUnpaid: false
    property int paidMessageStars: 0    // Stars required per message in a subscriber DM / paid supergroup
    readonly property bool isDirectChat: (store.seen, store.isDirect(chat))
    readonly property bool isDirectAdmin: (store.seen, store.isDirectAdmin(chat))
    readonly property alias paidSheet: paidSheet
    readonly property alias messageList: messages
    // a channel we may write in (its owner, or an admin who posts); the others have its bar instead of the field
    readonly property bool canPost: {
        if (outside || blocked)
            return false
        if (!channel)
            return barred === ""
        const g = (store.seen, store.groups["s" + chat.type.supergroup_id])
        const st = g ? g.status : null
        return !!st && (st["@type"] === "chatMemberStatusCreator" ||
                        (st["@type"] === "chatMemberStatusAdministrator" && st.rights.can_post_messages))
    }
    // what a group's members may send: by its own rights, and ours where its admins restricted us; null
    // when it is not a group, or we own it or are its admin (anything). `some`: anything but text
    readonly property var rights: {
        if (!chat || channel || outside)
            return null
        const t = chat.type["@type"]
        if (t !== "chatTypeBasicGroup" && t !== "chatTypeSupergroup")
            return null
        const g = (store.seen, store.groups[t === "chatTypeBasicGroup" ? "b" + chat.type.basic_group_id : "s" + chat.type.supergroup_id])
        const k = g && g.status ? g.status["@type"] : ""
        if (!k || k === "chatMemberStatusCreator" || k === "chatMemberStatusAdministrator")
            return null
        const mine = k === "chatMemberStatusRestricted" ? g.status.permissions : null
        const may = (key, old) => [mine, chat.permissions].every((p) => !p || (p[key] !== undefined ? p[key] : old ? p[old] : true) !== false)
        const r = { mine: !!mine, text: may("can_send_basic_messages", "can_send_messages"), photos: may("can_send_photos"),
                    videos: may("can_send_videos"), voice: may("can_send_voice_notes"), round: may("can_send_video_notes"),
                    files: may("can_send_documents"), music: may("can_send_audios"), other: may("can_send_other_messages") }
        r.some = r.photos || r.videos || r.voice || r.round || r.files || r.music || r.other
        return r
    }
    // text barred, something else not (pictures, files...): the field stays, locked (Telegram-iOS's «Text not
    // allowed»); a tap on it says what may be sent, 📎 and the mic send what they may
    readonly property bool textBarred: !!rights && !rights.text && rights.some && !editing
    readonly property bool canAttach: !rights || rights.photos || rights.videos || rights.files || rights.music || rights.other
    readonly property bool canVoice: !rights || rights.voice
    readonly property bool canRound: !rights || rights.round
    // as Telegram-iOS words it (restrictedSendingContentsText): "only allow to send photos, videos and files"
    readonly property string allowedText: {
        const r = rights
        if (!r)
            return ""
        const kinds = [[r.text, "matnli xabar"], [r.photos, "rasm"], [r.videos, "video"], [r.voice, "ovozli xabar"],
                       [r.round, "video xabar"], [r.files, "fayl"], [r.music, "musiqa"], [r.other, "stiker/GIF"]]
                      .filter((k) => k[0]).map((k) => Tr.t(k[1]))
        if (!kinds.length)
            return Tr.t("Bu guruhda xabar yuborib bo'lmaydi")
        const list = kinds.length > 1 ? Tr.f("%1 va %2", kinds.slice(0, -1).join(", "), kinds[kinds.length - 1]) : kinds[0]
        return Tr.f(r.mine ? "Adminlar sizga faqat %1 yuborishga ruxsat bergan" : "Bu guruh adminlari faqat %1 yuborishga ruxsat bergan", list)
    }
    // why we may not write here — a group whose admins let only themselves (or have barred us), a deleted
    // account — said in the bar instead of the field; "" when we may (text or anything else)
    readonly property string barred: {
        if (!chat || channel || outside)
            return ""
        const t = chat.type["@type"]
        if (t === "chatTypePrivate") {
            const u = (store.seen, store.users[chat.type.user_id])
            return u && u.type["@type"] === "userTypeDeleted" ? Tr.t("O'chirilgan hisob") : ""
        }
        if (t !== "chatTypeBasicGroup" && t !== "chatTypeSupergroup")
            return ""
        const g = (store.seen, store.groups[t === "chatTypeBasicGroup" ? "b" + chat.type.basic_group_id : "s" + chat.type.supergroup_id])
        const k = g && g.status ? g.status["@type"] : ""
        if (!k || k === "chatMemberStatusCreator" || k === "chatMemberStatusAdministrator")
            return ""
        if (k === "chatMemberStatusBanned" || (k === "chatMemberStatusLeft" && !isDirectChat))
            return Tr.t("Siz bu guruh a'zosi emassiz")
        const r = rights
        if (!r || r.text || r.some)
            return ""
        return r.mine ? Tr.t("Adminlar sizga bu yerda yozishni cheklagan") : Tr.t("Bu guruhda faqat adminlar yoza oladi")
    }
    // a channel or a group we are not in (opened by a link): «Qo'shilish» in the bar
    // (a channel's Direct Messages chat cannot be joined explicitly — subscribers just send a message)
    readonly property bool outside: {
        if (!chat || thread || isDirectChat || chat.type["@type"] !== "chatTypeSupergroup")
            return false
        const g = (store.seen, store.groups["s" + chat.type.supergroup_id])
        return !!g && g.status["@type"] === "chatMemberStatusLeft"
    }
    // a post's comments: chatId is then the channel's discussion group and this its thread there
    property var thread: 0
    readonly property real foot: (selecting ? pickBar.height : searching ? findBar.height : input.visible ? input.height : chanBar.height) + safe.bottom    // what is under the messages
    readonly property real barLift: Math.max(kb, safe.bottom)    // the bars: over the keyboard, or clear of the shell's nav line
    readonly property real toastFloor: kb + foot    // (Main's Toast stands over it)
    function isMuted() {
        const n = chat ? chat.notification_settings : null
        return !!n && n.mute_for > 0
    }
    property bool muted: isMuted()
    // a user we have blocked (setMessageSenderBlockList): «Blokdan chiqarish» in the bar instead of the field,
    // as Telegram-iOS's chat input panel (Conversation_Unblock; a bot «Qayta ishga tushirish», which then sends
    // it /start — Bot_Restart). TDLib changes the chat in place: onChatChanged asks again.
    property bool blocked: isBlocked()
    function isBlocked() { return !!chat && chat.type["@type"] === "chatTypePrivate" && !!chat.block_list }
    readonly property bool bot: {
        const u = chat && chat.type["@type"] === "chatTypePrivate" ? (store.seen, store.users[chat.type.user_id]) : null
        return !!u && u.type["@type"] === "userTypeBot"
    }
    function unblock() {
        const bot = page.bot
        store.send({ "@type": "setMessageSenderBlockList", sender_id: { "@type": "messageSenderUser", user_id: chat.type.user_id },
                     block_list: null }, (r) => {
            if (r["@type"] === "error")
                return page.toast(r.message)
            page.blocked = false
            if (bot)
                store.send({ "@type": "sendMessage", chat_id: page.chatId, input_message_content: {
                    "@type": "inputMessageText", text: { "@type": "formattedText", text: "/start", entities: [] } } }, store.check)
        })
    }
    // a channel's posts without a sound for its subscribers (the field's 🔔, kept per channel as Telegram does)
    readonly property bool silent: channel && Prefs.silent.split(",").indexOf(String(chatId)) >= 0
    function setSilent(on) {
        const ids = Prefs.silent.split(",").filter((x) => x && x !== String(chatId))
        if (on)
            ids.push(String(chatId))
        Prefs.silent = ids.join(",")
        toast(on ? Tr.t("Obunachilar xabarni ovozsiz oladi") : Tr.t("Obunachilar xabarni ovoz bilan oladi"))
    }
    // who asked to join by a link that needs an admin (the panel under the header; × hides it until more ask)
    readonly property var asking: chat && chat.pending_join_requests && chat.pending_join_requests.total_count > 0
                                  ? chat.pending_join_requests : null
    property int askingHidden: 0
    // the field's ⏱: messages here go by themselves after a while (setChatMessageAutoDeleteTime); in a
    // private chat anyone sets it, in a group or channel its owner or an admin who may change its info
    readonly property int autoDelete: chat ? chat.message_auto_delete_time || 0 : 0
    readonly property bool canAutoDelete: {
        if (!chat || thread)
            return false
        const t = chat.type["@type"]
        if (t === "chatTypePrivate")
            return !store.isSaved(chat)
        const g = (store.seen, store.groups[(t === "chatTypeBasicGroup" ? "b" + chat.type.basic_group_id : "s" + chat.type.supergroup_id)])
        const st = g ? g.status : null
        return !!st && (st["@type"] === "chatMemberStatusCreator" ||
                        (st["@type"] === "chatMemberStatusAdministrator" && st.rights.can_change_info))
    }
    // the chat in Uzbek (the panel's "O'zbek tiliga tarjima qilish", Telegram-iOS's whole-chat translation):
    // each message as its row is made (only what is in sight is asked for), back as it was when turned off
    readonly property bool translatable: !!chat && !!chat.is_translatable && !thread && Prefs.translateChats
    property bool translating: false
    property var originals: ({})        // message id -> its own words { text, rich }, while shown translated
    property var translations: ({})     // message id -> the Uzbek { text, rich }, asked once
    property var ones: ({})             // message id -> true: that one alone in Uzbek (its menu's "Tarjima qilish")
    function translateId(id) {
        const i = indexOf(id)
        const one = !!ones[id]
        if (i < 0 || !(translating || one))
            return
        const done = translations[id]
        if (done === null) {
            if (one && !translating) {
                delete ones[id]
                toast(Tr.t("Bu xabar o'zbekcha"))
            }
            return
        }
        if (done !== undefined) {
            if (originals[id] === undefined)
                originals[id] = { text: messages.get(i).text, rich: messages.get(i).rich }
            if (done.text !== undefined)
                put(i, done)
            return
        }
        if (!messages.get(i).text)
            return
        translations[id] = {}       // (asked: not again while it comes)
        store.send({ "@type": "translateMessageText", chat_id: chatId, message_id: id, to_language_code: Tr.lang }, (r) => {
            if (r["@type"] !== "formattedText") {
                delete page.translations[id]
                if (page.ones[id] && !page.translating) {
                    delete page.ones[id]
                    page.toast(Tr.t("Tarjima qilib bo'lmadi") + (r.message ? ": " + r.message : ""))
                } else if (page.translating) {
                    page.translating = false
                    page.untranslate()
                    page.toast(Tr.t("Tarjima qilib bo'lmadi") + (r.message ? ": " + r.message : ""))
                }
                return
            }
            if (!r.text.trim()) {       // (Telegram sends nothing back for what is in Uzbek already)
                page.translations[id] = null
                page.translateId(id)
                return
            }
            // (the translator sometimes leaves the original's markup in the words: **, </b>; where it
            // has formatting of its own the words stay, its places in them would move)
            page.translations[id] = r.entities.length ? { text: r.text, rich: store.rich(r, false) }
                : { text: r.text.replace(/<\/?(b|i|u|s|code|pre)>/g, "").replace(/\*\*|__/g, ""), rich: "" }
            page.translateId(id)
        })
    }
    function put(i, words) {
        messages.setProperty(i, "text", words.text)
        messages.setProperty(i, "rich", words.rich)
        regroupAt(i)
    }
    function untranslateOne(id) {
        delete ones[id]
        const i = indexOf(id)
        if (i >= 0 && originals[id] !== undefined)
            put(i, originals[id])
        delete originals[id]
    }
    function untranslate() {
        ones = {}
        for (const id in originals) {
            const i = indexOf(Number(id))
            if (i >= 0)
                put(i, originals[id])
        }
        originals = {}
    }
    function setTranslating(on) {
        translating = on
        if (!on)
            untranslate()
        // (on: each row in sight asks for its own, see the delegate's translated)
    }
    onTranslatableChanged: if (!translatable && translating) setTranslating(false)   // (turned off on the Til page)
    function setAutoDelete(secs) {
        store.send({ "@type": "setChatMessageAutoDeleteTime", chat_id: chatId, message_auto_delete_time: secs }, (r) => {
            if (r["@type"] === "error")
                toast(Tr.t("O'zgartirib bo'lmadi"))
            else
                toast(secs ? Tr.f("Yangi xabarlar %1dan keyin o'chadi", store.lasting(secs)) : Tr.t("Avtomatik o'chirish o'chirildi"))
        })
    }
    readonly property bool askingShown: !!asking && asking.total_count !== askingHidden && !thread
    property string threadOf: ""        // the channel's name, under "Izohlar"
    property var threadRoot: []         // the post itself (its copy in the group): over the oldest comment
    // the post under the comments once they have all come (TDLib's thread history leaves it out)
    function withRoot(got, done) {
        if (!thread || !done)
            return got
        const root = threadRoot.filter((m) => !got.some((g) => g.id === m.id))
        threadRoot = []
        return got.concat(root)
    }
    ready: false
    property bool loading: false
    property bool more: true
    // opened at the first unread message: the newest are not loaded yet (they come as it is
    // scrolled down, or all at once from ↓), and new ones wait for them
    property bool gap: false
    property bool newering: false
    property var firstUnread: 0         // the "O'qilmagan xabarlar" bar goes over this message
    property var readTo: 0              // the newest message TDLib was told is seen
    property int unread: chat ? chat.unread_count : 0
    property bool away: false           // the newest are out of sight (↓ shows)

    ListModel { id: messages }       // newest first: the list runs bottom to top

    // the keyboard's height over us: the messages and the field go up with it, the header stays
    // (the shell moves the keyboard in that time and curve, and leaves the window where it is).
    // Moved, not resized: a list laid out again each frame could not keep up with it.
    // The emoji/sticker panel (🙂) stands where the keyboard was, as tall as it was: `kb` is either's.
    // From the panel to the keyboard the panel's height is held until the keyboard's comes (no dip).
    property real kb: kbTo
    readonly property real kbTo: Math.max(osk.h, panelOpen || panelHold ? panelH : 0)
    Behavior on kb { NumberAnimation { duration: osk.ms; easing.type: Easing.OutExpo } }
    property bool panelOpen: false
    property bool panelHold: false
    property real panelH: 280           // the keyboard's height once seen (at least 280: room for the grid)
    Connections { target: osk; function onChanged() { if (osk.h > 0) { page.panelH = Math.max(280, osk.h); page.panelHold = false } } }
    Timer { id: holdAway; interval: 700; onTriggered: page.panelHold = false }
    function showPanel() {
        if (page.kb > 0 && !panelOpen) {
            field.focus = false
            osk.hide()
        }
        panelOpen = true
        emojiPanel.load()
    }
    function keyboardUp() {          // from the panel: the field's focus brings the keyboard; held till it comes
        panelHold = panelOpen
        panelOpen = false
        holdAway.restart()
        field.forceActiveFocus()
    }

    property var flying: null       // the text just sent and where it was: its bubble starts there
    property bool lift: false
    NumberAnimation {
        id: scroll
        target: list; property: "contentY"; duration: 300
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.19919, 0.01064, 0.27921, 0.91025, 1.0, 1.0]
        onFinished: list.down = list.atYBeginning
    }
    Timer { id: landed; interval: 320; onTriggered: page.lift = false }
    property int now: Date.now() / 1000      // "N minutes ago" moves on by itself
    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }

    property var replying: null     // { id, name, text }: the next message answers this one
    property var editing: null      // { id }: the field holds this message's text to change
    property var quotes: ({})       // message id -> { name, text }, what a reply to it shows
    property var asked: ({})        // quotes asked of TDLib (not among the loaded messages)

    // the newest pinned message, in a bar under the header (a tap goes to it)
    property var pinned: null           // { id, text }
    function loadPinned() {
        if (thread)         // (the discussion group's pinned message is not the post's)
            return
        store.send({ "@type": "getChatPinnedMessage", chat_id: chatId }, (m) => {
            if (page)
                page.pinned = m["@type"] === "message" ? { id: m.id, text: store.preview(m.content, chat) } : null
        })
    }

    // a sender's name; one TDLib has not told us of yet (a channel writing in the group — its linked one —,
    // a member never seen) is asked for, and its rows get the name when it comes: without one they went
    // to the left edge with no name and no face (the owner's photo of «Premium karta savdo»)
    property var sendersAsked: ({})
    function nameOf(sender) {
        const name = store.senderName(sender, false)
        if (name)
            return name
        const key = JSON.stringify(sender)
        if (sendersAsked[key])
            return ""
        sendersAsked[key] = true
        const req = sender.user_id ? { "@type": "getUser", user_id: sender.user_id } : { "@type": "getChat", chat_id: sender.chat_id }
        store.send(req, (r) => {
            if (!page)
                return
            if (r["@type"] === "chat" && !store.chats[r.id])
                store.chats[r.id] = r
            else if (r["@type"] === "user" && !store.users[r.id])
                store.users[r.id] = r
            const got = store.senderName(sender, false)
            if (!got)
                return
            for (let i = 0; i < messages.count; i++) {
                const row = messages.get(i)
                if (row.senderKey === key && !row.out && row.msgId !== thread)
                    messages.setProperty(i, "sender", got)
            }
        })
        return ""
    }

    // a group's admins (getChatAdministrators): user id -> { title, owner }; their titles beside their names
    property var ranks: ({})
    function loadRanks() {
        if (!group || thread)
            return
        store.send({ "@type": "getChatAdministrators", chat_id: chatId }, (r) => {
            if (!page || r["@type"] !== "chatAdministrators")
                return
            const got = {}
            for (const a of r.administrators)
                got[a.user_id] = { title: a.custom_title, owner: a.is_owner }
            page.ranks = got
            for (let i = 0; i < messages.count; i++) {
                const s = JSON.parse(messages.get(i).senderKey)
                if (s.user_id && got[s.user_id] && messages.get(i).sender !== "") {
                    const k = rankOf({ sender_id: s, chat_id: chatId, author_signature: "", sender_tag: "" })
                    messages.setProperty(i, "rank", k.text)
                    messages.setProperty(i, "rankKind", k.kind)
                }
            }
        })
    }
    // what Telegram-iOS puts on the right of a group's sender's name (ChatMessageBubbleItemNode): the owner's
    // title or «ega» (purple), an admin's or «admin» (green), the group writing itself — an anonymous admin —
    // «admin», its signature instead when it has one; a channel's signature; else the member's tag (grey)
    function rankOf(m) {
        const s = m.sender_id
        let k = null
        if (s.user_id && ranks[s.user_id]) {
            const a = ranks[s.user_id]
            k = { text: a.title || Tr.t(a.owner ? "ega" : "admin"), kind: a.owner ? 2 : 1 }
        } else if (s.chat_id === chatId) {
            k = { text: Tr.t("admin"), kind: 1 }
        }
        if (s.chat_id && m.author_signature)
            k = { text: m.author_signature, kind: 0 }
        if (!k && m.sender_tag)
            k = { text: m.sender_tag, kind: 0 }
        return k
    }

    // the chat's own background (setChatBackground: chat.background), else its theme's (setChatTheme), else the app's;
    // by night a chosen one dimmed by its dark_theme_dimming (Telegram-iOS: WallpaperBackgroundNode's dimLayer)
    property string wallSpec: ""
    property real wallDim: 0
    property var _wallOf: null
    function rewall() {
        const c = chat
        const key = c ? JSON.stringify([c.background, c.theme, Theme.dark]) : ""
        if (key === _wallOf)
            return
        _wallOf = key
        store.chatWall(c, Theme.dark, (s, dim) => {
            if (_wallOf === key) {
                wallSpec = s
                wallDim = dim
            }
        })
    }
    Connections { target: Theme; function onDarkChanged() { page.rewall() } }
    Connections { target: store; function onEmojiThemesChanged() { page._wallOf = null; page.rewall() } }

    Component.onCompleted: {
        store.openChat = chatId
        rewall()
        loadPinned()
        loadRanks()
        if (td.devOpen)
            console.warn("nullgram: chat translatable", chat ? chat.is_translatable : "?", "premium", store.me ? store.me.is_premium : "?")
        store.send({ "@type": "openChat", chat_id: chatId })
        if (chat && chat.type["@type"] === "chatTypeSupergroup") {   // its update may not have the count; a channel's 🎁 & DM
            const g = store.groups["s" + chat.type.supergroup_id]
            if (!g || !g.member_count || channel || isDirectChat)
                store.send({ "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }, (r) => {
                    if (!page || r["@type"] === "error")
                        return
                    page.canGift = !!r.can_send_gift
                    page.directChatId = r.direct_messages_chat_id || 0
                    if (page.directChatId && !store.chats[page.directChatId])
                        store.send({ "@type": "getChat", chat_id: page.directChatId }, () => {})
                    const g = store.groups["s" + page.chat.type.supergroup_id]
                    if (g && r.member_count && !g.member_count) {
                        g.member_count = r.member_count
                        store.seen++
                    }
                    if (!page.isDirectAdmin && !page.channel)
                        page.paidMessageStars = r.outgoing_paid_message_star_count || (g ? g.paid_message_star_count || 0 : 0)
                })
        }
        readTo = chat ? chat.last_read_inbox_message_id : 0
        loadDraft()
        if (target)
            openAt(target, false)
        else if (chat && chat.unread_count > 0 && readTo && !thread)
            openAt(readTo, true)
        else
            fresh()
    }

    // the newest messages, the list at the bottom
    function fresh() {
        messages.clear()
        gap = false
        more = true
        list.down = true
        store.history(chatId, 0, 30, (got, failed) => {
            if (!page)          // closed before TDLib answered
                return
            page.add(page.withRoot(got, !failed && got.length < 30))
            // one that came meanwhile (sent as it opened) is laid out again with neighbours now, and
            // had scrolled to where the newest was before these: lay out, stop that, then go down
            list.forceLayout()
            scroll.stop()
            list.positionViewAtBeginning()
            page.ready = true
            Qt.callLater(page.seen)
            Qt.callLater(page.nearTop)          // a screen not yet full: more at once
        }, null, thread, directTopic)
    }

    // as Telegram opens a chat with unread messages: around the last one read, the first unread
    // under the bar at the top of the screen; or (`unread` false) around a message found, in the middle
    function openAt(id, unread) {
        store.send({ "@type": "getChatHistory", chat_id: chatId, from_message_id: id, offset: unread ? -30 : -20,
                     limit: unread ? 50 : 40, only_local: false }, (r) => {
            if (!page)
                return
            const got = r.messages || []
            if (!got.length) {
                page.fresh()
                return
            }
            const last = page.chat && page.chat.last_message
            page.gap = !(last && got[0].id >= last.id)
            if (unread)
                for (let k = got.length - 1; k >= 0; k--)
                    if (got[k].id > page.readTo && !got[k].is_outgoing) {
                        page.firstUnread = got[k].id
                        break
                    }
            page.add(got)
            if (!unread) {
                const t = page.indexOf(id)
                if (t >= 0)
                    page.centre(t)
                page.flashId = id
                unflash.restart()
            }
            const i = unread ? page.indexOf(page.firstUnread) : -1
            if (i >= 0)
                page.toTop(i, 0)
            list.down = false
            page.ready = true
            Qt.callLater(page.seen)
            Qt.callLater(page.nearTop)
            Qt.callLater(page.nearBottom)
        })
    }
    Component.onDestruction: {
        saveDraft()
        if (roundId)            // (its picture is this page's: it goes with it)
            player.stop()
        store.send({ "@type": "closeChat", chat_id: chatId })
        if (store.openChat === chatId)
            store.openChat = 0
    }

    // older messages at the end; their quotes first, so a reply within the batch needs no request
    function add(got) {
        const k = messages.count - 1
        // one that came as an update while these were asked for is here already
        got = got.filter((m) => rowAt[m.id] === undefined)
        for (const m of got)
            remember(m)
        // at once: one by one each told the list and the albums (a page of 40 held a flick for 0.4 s)
        if (got.length)
            messages.append(got.map((m) => row(m)))
        // the one that was the oldest has neighbours now: its day and run are worked out again
        if (k >= 0 && got.length)
            messages.setProperty(k, "edge", messages.get(k).edge + 1)
    }

    // older ones while the list may be moving: a few rows a frame, then `done` (a page of 40 at
    // once held a flick for 50 ms)
    property var feeding: []
    property var fed: null
    function addLater(got, done) {
        got = got.filter((m) => rowAt[m.id] === undefined)
        for (const m of got)
            remember(m)
        feeding = got
        fed = done
        feeder.restart()
    }
    function feed() {
        const t0 = td.fps ? Date.now() : 0
        const part = feeding.splice(0, 6)
        if (part.length) {
            const k = messages.count - 1
            const rows = part.map((m) => row(m))
            if (td.fps)
                td.mark("rowms", Date.now() - t0)
            messages.append(rows)
            if (k >= 0)
                messages.setProperty(k, "edge", messages.get(k).edge + 1)
        }
        if (td.fps) {
            td.mark("fed", part.length)
            td.mark("feedms", Date.now() - t0)
        }
        if (!feeding.length) {
            feeder.stop()
            const done = fed
            fed = null
            if (done)
                done()
        }
    }
    Timer { id: feeder; interval: 16; repeat: true; triggeredOnStart: true; onTriggered: page.feed() }

    function remember(m) {
        quotes[m.id] = { name: m.is_outgoing ? Tr.t("Siz") : store.senderName(m.sender_id, false) || (chat ? chat.title : ""),
                         text: store.preview(m.content, chat) }
    }

    readonly property var pictured: ["messagePhoto", "messageVideo", "messageAnimation", "messageSticker", "messageVideoNote",
                                     "messageVoiceNote", "messageAudio", "messageDocument", "messagePoll",
                                     "messageLocation", "messageVenue", "messageLiveLocation"]

    // its words and, when they are formatted, Store.rich's parts (a spoiler ░ until tapped: `bare`)
    property var spoilers: ({})      // message id -> the formatted text with a spoiler in it
    property var bared: ({})         // message id -> true: its spoilers shown
    property var unfolded: ({})      // message id -> true: its folding quotes shown whole
    function shown(content, id) {
        const t = content["@type"]
        const words = store.plain(content)
        // a venue: its name in bold over its address (Telegram-iOS's map bubble)
        const v = t === "messageVenue" ? content.venue : null
        const ft = v ? { "@type": "formattedText", text: v.title + (v.address ? "\n" + v.address : ""),
                         entities: [{ "@type": "textEntity", offset: 0, length: v.title.length, type: { "@type": "textEntityTypeBold" } }] }
                     : store.formatted(content)
        if (store.hasSpoiler(ft))
            spoilers[id] = ft
        return {
            rich: store.rich(ft, !!bared[id]),
            text: words !== null ? words : t === "messageVenue" ? content.venue.title + (content.venue.address ? "\n" + content.venue.address : "")
                : t === "messageLiveLocation" ? Tr.t("Jonli joylashuv") : (content.caption ? content.caption.text : ""),
            kind: words !== null || pictured.indexOf(t) >= 0 ? ""
                : store.kindOf(t)
        }
    }

    // a still picture TDLib can give for a thumbnail (not an animation or a video)
    function still(th) {
        const f = th && th.format["@type"]
        return f === "thumbnailFormatJpeg" || f === "thumbnailFormatWebp" || f === "thumbnailFormatPng" || f === "thumbnailFormatGif"
            ? th.file : null
    }

    // what a message shows as a picture: its kind, size, Telegram's tiny preview, and the file
    // to show (the photo's size nearest 640 px, else a video's or a sticker's still)
    property var files: ({})         // message id -> the picture's file
    property var bigFiles: ({})      // message id -> the photo's biggest size (full screen)
    function media(c) {
        const t = c["@type"]
        const r = { picKind: "", picW: 1, picH: 1, mini: "", dur: 0, file: null, main: null, rowKind: "",
                    fileName: "", wave: "", title: "", sub: "", anim: false, auto: false, emo: "", fitz: 0,
                    spoiler: !!c.has_spoiler,      // (a photo, video or GIF sent as a spoiler)
                    heard: true }                  // a voice note or a round video not yet played: false (the dot)
        if (t === "messagePhoto" && c.photo.sizes.length) {
            const sizes = c.photo.sizes      // small to big
            let best = sizes[sizes.length - 1]
            for (const z of sizes)
                if (z.width >= 640) {
                    best = z
                    break
                }
            Object.assign(r, { picKind: "photo", picW: best.width, picH: best.height, file: best.photo,
                               big: sizes[sizes.length - 1].photo, main: sizes[sizes.length - 1].photo,
                               mini: c.photo.minithumbnail ? c.photo.minithumbnail.data : "" })
        } else if (t === "messageVideo" || t === "messageAnimation") {
            const v = t === "messageVideo" ? c.video : c.animation
            Object.assign(r, { picKind: t === "messageVideo" ? "video" : "gif", picW: v.width || 1, picH: v.height || 1,
                               dur: v.duration, file: still(v.thumbnail), mini: v.minithumbnail ? v.minithumbnail.data : "",
                               main: t === "messageVideo" ? v.video : v.animation, fileName: v.file_name || "",
                               auto: t === "messageAnimation" ? Prefs.autoGif && (v.animation.size || v.animation.expected_size) < 8e6
                                     : store.autoOk("video", v.video.size || v.video.expected_size, page.chatId) })
        } else if (t === "messageSticker") {
            const st = c.sticker
            // a video sticker plays as a GIF does; a TGS one (Lottie) is drawn frame by frame (Lottie.qml)
            const moves = st.format["@type"] === "stickerFormatWebm" || st.format["@type"] === "stickerFormatTgs"
            Object.assign(r, { picKind: "sticker", picW: st.width || 1, picH: st.height || 1,
                               file: st.format["@type"] === "stickerFormatWebp" ? st.sticker : still(st.thumbnail),
                               main: moves ? st.sticker : null, anim: moves, auto: moves && Prefs.loopStickers })
        } else if (t === "messageAnimatedEmoji" && Prefs.loopEmoji && c.animated_emoji && c.animated_emoji.sticker
                   && c.animated_emoji.sticker.format["@type"] === "stickerFormatTgs") {
            // one emoji alone: Telegram's animated one (a TGS sticker), played once as the chat opens and then
            // still on its last frame (Lottie.qml), as big as a sticker -- Telegram-iOS's
            // ChatMessageAnimatedStickerItemNode; its skin tone as tlottie's fitz (TDLib's 2-6 -> 1-5)
            const st = c.animated_emoji.sticker, ft = c.animated_emoji.fitzpatrick_type || 0
            Object.assign(r, { picKind: "sticker", picW: st.width || 512, picH: st.height || 512, file: still(st.thumbnail),
                               main: st.sticker, anim: true, auto: true, emo: c.emoji, fitz: ft >= 2 ? ft - 1 : 0 })
        } else if (t === "messageVideoNote") {
            const v = c.video_note
            Object.assign(r, { picKind: "round", picW: 1, picH: 1, dur: v.duration, file: still(v.thumbnail),
                               mini: v.minithumbnail ? v.minithumbnail.data : "", main: v.video, auto: Prefs.autoVoice,
                               heard: !!c.is_viewed })
        } else if (t === "messageVoiceNote") {
            const v = c.voice_note
            Object.assign(r, { rowKind: "voice", dur: v.duration, wave: v.waveform || "", main: v.voice, auto: Prefs.autoVoice,
                               heard: !!c.is_listened })
        } else if (t === "messageAudio") {
            const a = c.audio
            Object.assign(r, { rowKind: "audio", dur: a.duration, main: a.audio, fileName: a.file_name || "",
                               auto: store.autoOk("file", a.audio.size || a.audio.expected_size, page.chatId),
                               title: a.title || a.file_name || Tr.t("Musiqa"), sub: a.performer || "" })
        } else if (t === "messageDocument") {
            const d = c.document
            Object.assign(r, { rowKind: "file", main: d.document, fileName: d.file_name || "", file: still(d.thumbnail),
                               auto: store.autoOk("file", d.document.size || d.document.expected_size, page.chatId) })
        } else if (t === "messagePoll") {
            r.rowKind = "poll"
        } else if (t === "messageLocation" || t === "messageVenue" || t === "messageLiveLocation") {
            // a map from Telegram's own servers (getMapThumbnailFile, loadPic asks for it), the pin over it;
            // a live one: `dur` is when it stops (unix time)
            Object.assign(r, { picKind: "map", picW: 300, picH: 180 })
        }
        return r
    }

    // pictures sent as spoilers (has_spoiler): blurred under dust until tapped (Veil), then shown
    // for as long as the page is open, as Telegram-iOS keeps them
    property var unveiled: ({})      // message id -> true: its spoiler taken off
    // animated emoji played once in this chat (Telegram-iOS's seenOneTimeAnimatedMedia): back on the
    // screen they stay on their last frame; the chat opened again, they play again
    property var seenEmo: ({})
    property int burstSeq: 0        // (an emoji's effects told apart)
    function unveil(id) {
        unveiled[id] = true
        const i = indexOf(id)
        if (i >= 0 && messages.get(i).veiled)
            messages.setProperty(i, "veiled", false)
    }

    // a photo full screen, out of its bubble; the biggest size comes in when downloaded
    property var held: ({})          // message id -> its photo not brought down by itself (Prefs.dl), till opened
    function view(item) {
        if (held[item.msgId]) {
            files[item.msgId] = held[item.msgId]
            delete held[item.msgId]
            loadPic(item.msgId)
        }
        const src = item.pic ? "image://pic/0/" + Math.round(item.pw) + "/" + item.pic
                  : item.mini ? "image://pic/0/" + Math.round(item.pw) + "/mini/" + item.mini : ""
        viewer.show(item.picFace, item.aspect, src, "", item.msgId)
        const f = bigFiles[item.msgId]
        if (f)
            store.fetch(f, 32, (path) => { if (page) viewer.better(path) })
    }

    // the message's own file (the video, the voice, the document...): how far it has come, and
    // its path once here. `mains` by message, `fileMsgs` the other way (updateFile names files)
    property var mains: ({})
    property var fileMsgs: ({})
    property var wantOpen: 0            // a tap asked for this one: it opens (plays) when it is here
    function own(id, f) {
        mains[id] = f
        const ids = fileMsgs[f.id] || []
        if (ids.indexOf(id) < 0)
            ids.push(id)
        fileMsgs[f.id] = ids
    }

    function download(id, open) {
        const f = mains[id]
        if (!f)
            return
        if (open)
            wantOpen = id
        const i = indexOf(id)
        if (i >= 0 && messages.get(i).got < 0)
            messages.setProperty(i, "got", 0)
        store.fetch(f, open ? 32 : 1, () => {})
    }

    function stop(id) {
        const f = mains[id]
        if (wantOpen === id)
            wantOpen = 0
        if (f)
            store.stopFile(f)
        const i = indexOf(id)
        if (i >= 0)
            messages.setProperty(i, "got", -1)
    }

    // an emoji alone tapped: one of its effects over it (Telegram-iOS's additionalAnimatedEmojiStickers, in every
    // chat). In a private chat TDLib picks it and tells the other one, who sees it too (updateAnimatedEmojiMessageClicked:
    // onEmojiClicked); elsewhere TDLib gives none (a 404), and so it is picked here from the same set (Store.emojiEffect)
    function clickEmoji(id) {
        const i = indexOf(id), emo = i >= 0 ? messages.get(i).emo : ""
        const here = () => store.emojiEffect(emo, (st) => burst(id, st))
        if (!chat || chat.type["@type"] !== "chatTypePrivate") {
            here()
            return
        }
        store.send({ "@type": "clickAnimatedEmojiMessage", chat_id: chatId, message_id: id }, (r) => {
            if (r["@type"] === "sticker")
                burst(id, r)
            else
                here()      // (the set not here yet, or taps too fast for TDLib)
        })
    }
    // the effect (a TGS sticker) brought down and played over message `id`'s emoji, if its row is still made
    function burst(id, st) {
        if (!st || !st.sticker || !st.format || st.format["@type"] !== "stickerFormatTgs")
            return
        store.fetch(st.sticker, 32, (path) => {
            const i = indexOf(id), shell = i >= 0 ? list.itemAtIndex(i) : null
            if (shell && shell.view && shell.view.emo)
                shell.view.burst(path)
        })
    }

    // a tap on a message's media: open, play, or bring it down first (a second tap stops that);
    // a spoiler is taken off first, from under the finger (x, y on the picture; its middle if not given)
    function tapMedia(item, x, y) {
        startAt = 0
        if (item.veiled) {
            item.blow(x, y)
            return
        }
        if (item.emo) {         // an animated emoji: once more (Telegram-iOS plays it again on a tap), and its effect
            item.replay()
            clickEmoji(item.msgId)
            return
        }
        const k = item.rowKind || item.picKind
        if (k === "map") {
            placeMenu.show(maps[item.msgId], item.text)
            return
        }
        if (k === "photo") {
            view(item)
            return
        }
        if (!mains[item.msgId])
            return
        if (item.got >= 0 && !item.path && !item.sending) {
            stop(item.msgId)
            return
        }
        if (!item.path) {
            download(item.msgId, true)
            return
        }
        openMedia(item)
    }

    // a timestamp in a message's words (textEntityTypeMediaTimestamp, «1:23»): its own video or sound from there,
    // else the one it answers (Telegram-iOS: a comment's 1:23 plays the post's video from 1:23); brought down
    // first if need be (it opens when here, from there). One not on the screen is gone to first.
    property real startAt: 0            // ms: where the next video or sound opened starts
    function playFrom(secs, id) {
        const i = indexOf(id)
        const answered = i >= 0 ? messages.get(i).replyId : 0
        for (const k of [id, answered]) {
            if (!k || !mains[k] || indexOf(k) < 0)
                continue
            const r = messages.get(indexOf(k))
            const kind = r.rowKind || r.picKind, mime = fileMime[k] || ""
            if (kind !== "video" && kind !== "voice" && kind !== "audio"
                    && !(kind === "file" && (mime.startsWith("video/") || mime.startsWith("audio/"))))
                continue
            const it = shownAt(k)
            if (!it) {
                jump(k)
                return
            }
            startAt = secs * 1000
            if (it.path)
                openMedia(it)
            else
                download(k, true)
            return
        }
    }

    function openMedia(item) {
        const k = item.rowKind || item.picKind
        const mime = (mains[item.msgId] && fileMime[item.msgId]) || ""
        if (k === "video" || k === "gif" || (k === "file" && mime.startsWith("video/"))) {
            const src = item.pic ? "image://pic/0/" + Math.round(item.pw) + "/" + item.pic
                      : item.mini ? "image://pic/0/" + Math.round(item.pw) + "/mini/" + item.mini : ""
            viewer.show(item.media ? item.picFace : item.face, item.media ? item.aspect : 9 / 16, src, item.path,
                        k === "video" ? item.msgId : 0, startAt)
            startAt = 0
            viewing = item.msgId
        } else if (k === "round") {
            play(item.msgId, item.path)
        } else if (k === "voice" || k === "audio" || (k === "file" && mime.startsWith("audio/"))) {
            play(item.msgId, item.path)
        } else if (k === "file" && mime.startsWith("image/")) {
            viewer.show(item.face, fileAspect[item.msgId] || 1, "file://" + item.path)
            viewing = item.msgId
        } else if (k === "file") {
            save(item.msgId)
        }
    }
    property var fileMime: ({})         // a document's mime type, by message
    property var fileAspect: ({})       // and a picture's height / width (its thumbnail's)
    property var viewing: 0             // the message full screen (its ↓ saves it)

    // into ~/Downloads (td.save), brought down first when it is not here
    function save(id) {
        const f = mains[id]
        if (!f)
            return
        const name = fileNames[id] || f.local.path.split("/").pop()
        store.fetch(f, 32, (path) => {
            const to = td.save(path, name)
            if (page)
                page.toast(to ? Tr.f("Saqlandi: Downloads/%1", to.split("/").pop()) : Tr.t("Saqlab bo'lmadi"))
        })
    }
    property var fileNames: ({})

    // a voice note or a round video played: Telegram told (the other side's dot goes, as ours does
    // when updateMessageContentOpened comes back) -- Telegram-iOS's markMessageContentAsConsumed
    function opened(id) {
        const i = indexOf(id)
        if (i < 0 || messages.get(i).heard)
            return
        messages.setProperty(i, "heard", true)
        store.send({ "@type": "openMessageContent", chat_id: chatId, message_id: id })
    }

    // the sound playing is Main's Player (it goes on when the page closes, the next one follows there):
    // a voice note or a song of this page, tapped, is played by it
    readonly property var soundId: player && player.chatId === chatId ? player.msgId : 0
    function play(id, path) {
        const from = startAt
        startAt = 0
        const i = indexOf(id), r = i >= 0 ? messages.get(i) : null
        const round = !!r && r.picKind === "round"
        const voice = !!r && (r.rowKind === "voice" || round)
        if (voice && !r.heard)
            messages.setProperty(i, "heard", true)      // (Player tells Telegram)
        player.start({ chatId: chatId, msgId: id, path: path || (r && r.path) || "", kind: round ? "round" : voice ? "voice" : "audio", from: from,
                       dur: r ? r.dur : 0,
                       title: !r ? "" : voice ? (r.out ? Tr.t("Siz") : r.sender || (chat ? chat.title : ""))
                                  : r.title || r.fileName,
                       sub: !r ? "" : round ? Tr.t("Video xabar") : voice ? Tr.t("Ovozli xabar") : r.sub })
    }
    // the round video playing in its bubble, big, with its sound: the Player's, when it is this chat's
    readonly property var roundId: player && player.round && player.chatId === chatId ? player.msgId : 0
    property bool roundSeen: true       // its bubble's middle on the screen (else the corner's circle plays it)
    // the queue went on to the next one here (a voice note or a round video after the last): the chat goes to it
    // when it is not all in sight (Telegram-iOS scrolls the list to the item playing)
    Connections {
        target: page.player
        function onMsgIdChanged() {
            const id = page.player.msgId
            if (!id || page.player.chatId !== page.chatId || page.player.kind === "audio")
                return
            const i = page.indexOf(id)
            if (i >= 0 && !messages.get(i).heard)
                messages.setProperty(i, "heard", true)     // (the Player told Telegram)
            seeing.id = id
            seeing.restart()        // (a round video: once it has grown)
        }
    }
    Timer { id: seeing; interval: 320; property var id: 0; onTriggered: if (page.player.msgId === id) page.seeAll(id) }
    function seeAll(id) {
        const i = indexOf(id)
        if (i < 0)
            return
        const it = list.itemAtIndex(i)
        if (it) {
            const top = it.mapToItem(page, 0, 0).y, bottom = top + it.height
            if (top >= bar.height + pinBar.height && bottom <= page.height - kb - foot)
                return
        }
        centre(i)
    }

    // a reaction chip's width: «👍 3», or 👍 and the faces of who chose it (24 pt, 12 apart: Telegram-iOS's
    // ReactionButtonComponent, 4 after the emoji, 2 before the chip's round end), or gold ⭐ paid reaction chip
    function chipWidth(r) {
        const n = r.who ? r.who.length : 0
        if (r.paid) {
            const facesW = n ? 4 + 20 + (n - 1) * 10 : 0
            return 8 + 16 + facesW + 4 + chipMetrics.advanceWidth(store.short(r.n)) + 9
        }
        return n ? 8 + chipMetrics.advanceWidth(r.e) + 4 + 24 + (n - 1) * 12 + 2 : chipMetrics.advanceWidth(r.e + " " + r.n) + 16
    }

    function clock(secs) { return Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0") }

    function toast(text) {
        toastText.text = text
        toastBox.opacity = 1
        toastAway.restart()
    }

    // a message's place (messageLocation, -Venue, -LiveLocation): its map is asked for once, then as a picture
    property var maps: ({})          // message id -> its location
    function loadMap(id) {
        const loc = maps[id]
        store.send({ "@type": "getMapThumbnailFile", location: { "@type": "location", latitude: loc.latitude, longitude: loc.longitude,
                                                                 horizontal_accuracy: 0 },
                     zoom: 15, width: 300, height: 180, scale: 3, chat_id: chatId }, (f) => {
            if (f["@type"] !== "file" || !page)
                return
            page.files[id] = f
            page.loadPic(id)
        })
    }
    function loadPic(id) {
        if (maps[id] && !files[id])
            return loadMap(id)
        const f = files[id]
        if (f)
            store.fetch(f, 1, (path) => {
                if (!page)
                    return
                const i = page.indexOf(id)
                if (i >= 0)
                    messages.setProperty(i, "pic", path)
            })
    }

    function row(m) {
        const s = shown(m.content, m.id)
        const p = media(m.content)
        const ct = m.content["@type"]
        if (p.picKind === "map") {
            const live = ct === "messageLiveLocation"
            maps[m.id] = ct === "messageVenue" ? m.content.venue.location : live ? m.content.location.location : m.content.location
            if (live)       // (its period from when it was sent; 0x7FFFFFFF: for good)
                p.dur = m.content.location.live_period >= 0x7FFFFFFF ? 0x7FFFFFFF : m.date + m.content.location.live_period
        }
        if (p.file && p.picKind === "photo" && !files[m.id] && !store.autoOk("photo", 0, chatId))
            held[m.id] = p.file             // (auto-download off for photos here: its tiny preview till it is opened)
        else if (p.file)
            files[m.id] = p.file
        if (p.big)
            bigFiles[m.id] = p.big
        if (p.main) {
            own(m.id, p.main)
            if (p.fileName)
                fileNames[m.id] = p.fileName
            const doc = m.content.document
            if (doc) {
                fileMime[m.id] = doc.mime_type || ""
                if (doc.thumbnail && doc.thumbnail.width)
                    fileAspect[m.id] = doc.thumbnail.height / doc.thumbnail.width
            }
        }
        const words = store.plain(m.content)
        // in a post's comments the post itself goes plain and an answer to it has no quote (as Telegram has them)
        const root = thread && m.id === thread
        const r = m.reply_to && m.reply_to["@type"] === "messageReplyToMessage" &&
                  !(thread && m.reply_to.message_id === thread) ? m.reply_to : null
        let quote = null
        if (r && r.chat_id === chatId) {
            quote = quotes[r.message_id]
            if (!quote)
                want(r.message_id)
        } else if (r && r.content) {        // a reply to a message in another chat comes with it
            quote = { name: "", text: store.preview(r.content, store.chats[r.chat_id]) }
        }
        const badge = page.group && !m.is_outgoing && !root ? rankOf(m) : null
        return {
            msgId: m.id, out: m.is_outgoing, date: m.date, text: p.emo ? "" : s.text, rich: p.emo ? "" : s.rich, kind: s.kind, said: store.service(m, chat) || "",
            sender: page.group && !m.is_outgoing && !root ? nameOf(m.sender_id) : "",
            senderKey: JSON.stringify(m.sender_id), sending: !!m.sending_state,
            rank: badge ? badge.text : "", rankKind: badge ? badge.kind : 0,
            tint: store.tints[Math.abs(m.sender_id.user_id || m.sender_id.chat_id || 0) % store.tints.length],
            time: Qt.formatTime(new Date(m.date * 1000), "HH:mm"),
            views: m.interaction_info ? m.interaction_info.view_count : 0,
            // a channel post with a discussion group: its comments (-1: none can be left)
            comments: m.is_channel_post && page.channel && m.interaction_info && m.interaction_info.reply_info
                      ? m.interaction_info.reply_info.reply_count : -1,
            // a group's message: how many answered it (Telegram-iOS's ↩ 9 by the time)
            replies: !m.is_channel_post && m.interaction_info && m.interaction_info.reply_info
                     ? m.interaction_info.reply_info.reply_count : 0,
            edited: m.edit_date > 0,
            replyId: r ? r.message_id : 0,
            quoteName: quote ? quote.name : "", quoteText: quote ? quote.text : (r ? "..." : ""),
            picKind: p.picKind, picW: p.picW, picH: p.picH, mini: p.mini, dur: p.dur, edge: 0,
            pic: p.file && p.file.local.is_downloading_completed ? p.file.local.path : "",
            rowKind: p.rowKind, fileName: p.fileName, fileSize: p.main ? (p.main.size || p.main.expected_size) : 0,
            wave: p.wave, title: p.title, sub: p.sub, anim: p.anim, auto: p.auto, emo: p.emo, fitz: p.fitz,
            got: p.main ? store.progress(p.main) : -1,
            path: p.main && p.main.local.is_downloading_completed ? p.main.local.path : "",
            jumbo: Prefs.largeEmoji && words !== null && !m.forward_info && !p.emo ? store.emojiCount(words.trim()) : 0,     // (Stikerlar va emoji: «Katta emoji»)
            fwd: root ? "" : store.origin(m.forward_info),
            reacts: JSON.stringify(store.reactions(m.interaction_info, page.chat)),
            isPinned: !!m.is_pinned,
            // sent together (one media_album_id): one bubble — photos and videos a mosaic, files or
            // songs one under another (Telegram keeps an album to one of the three)
            poll: m.content["@type"] === "messagePoll" ? JSON.stringify(m.content.poll) : "",
            album: m.media_album_id && m.media_album_id !== "0" && (p.picKind === "photo" || p.picKind === "video"
                                                                     || p.rowKind === "file" || p.rowKind === "audio")
                   ? String(m.media_album_id) : "",
            veiled: p.spoiler && !unveiled[m.id],
            heard: p.heard || page.channel      // (a channel's post is not marked played)
        }
    }

    // Albums (Telegram-iOS's grouped messages): each message stays a row of its own (its file, its
    // updates, deleting it), the album's main one — its caption's, else the oldest — draws them all
    // as a mosaic, the others (`tucked`) take no room. Worked out again as rows come, go or change.
    property var albums: ({})           // album -> { ids (oldest first), main, talk (comments), talkId }
    property string albumKey: ""
    property int albumRev: 0            // the albums' make-up changed (their mosaics are laid out again)
    property int albumTick: 0           // a member's row changed (its picture came, its file moves on)
    function tick() {
        if (td.fps)
            td.mark("tick", 1)
        albumTick++
    }
    // a row's caption or comments changed: when it is an album's, which one shows them may be another
    function regroupAt(i) {
        if (i >= 0 && i < messages.count && messages.get(i).album)
            Qt.callLater(page.regroup)
    }
    property var rowAt: ({})            // message id -> its row, as regroup last saw them (indexOf checks it)
    property var laidOut: ({})          // "ids/width" -> an album's mosaic (tilesOf)
    function regroup() {
        if (td.fps)
            td.mark("regroup", 1)
        const g = {}
        const at = {}
        for (let i = 0; i < messages.count; i++) {
            const r = messages.get(i)
            at[r.msgId] = i
            if (!r.album)
                continue
            const a = g[r.album] || (g[r.album] = { ids: [], main: 0, words: 0, talk: -1, talkId: 0 })
            a.ids.push(r.msgId)
            if (r.text && !a.words)
                a.words = r.msgId
            if (r.comments > a.talk) {
                a.talk = r.comments
                a.talkId = r.msgId
            }
        }
        for (const k in g) {
            g[k].ids.sort((a, b) => a - b)
            g[k].main = g[k].words || g[k].ids[0]
        }
        rowAt = at
        const key = JSON.stringify(g)
        if (key === albumKey)
            return false
        albumKey = key
        albums = g
        laidOut = {}
        albumRev++
        if (list.down || scroll.running)
            Qt.callLater(page.keepDown)
        return true
    }
    // older rows put at the end: only they are looked at (all of them each time took 11 ms a page)
    function regroupAdded(first, last) {
        let g = null
        const touched = []
        for (let i = first; i <= last; i++) {
            const r = messages.get(i)
            rowAt[r.msgId] = i
            if (!r.album)
                continue
            if (!g)
                g = Object.assign({}, albums)
            if (touched.indexOf(r.album) < 0) {
                touched.push(r.album)
                const was = g[r.album]
                g[r.album] = was ? { ids: was.ids.slice(), main: 0, words: was.words, talk: was.talk, talkId: was.talkId }
                                 : { ids: [], main: 0, words: 0, talk: -1, talkId: 0 }
            }
            const a = g[r.album]
            a.ids.push(r.msgId)
            if (r.text && !a.words)
                a.words = r.msgId
            if (r.comments > a.talk) {
                a.talk = r.comments
                a.talkId = r.msgId
            }
        }
        if (!g)
            return
        for (const k of touched) {
            g[k].ids.sort((a, b) => a - b)
            g[k].main = g[k].words || g[k].ids[0]
        }
        albumKey = JSON.stringify(g)
        albums = g
        laidOut = {}
        albumRev++
    }
    // an album's next message came as the list went down to its first: its bubble is another
    // height now (a mosaic), the newest stays at the bottom
    function keepDown() {
        if (!list.down && !scroll.running)
            return
        const was = list.contentY
        list.forceLayout()
        list.positionViewAtBeginning()
        if (scroll.running) {
            scroll.to = list.contentY
            list.contentY = was
            scroll.restart()
        }
    }
    // the row past the album `index` is in, `step` 1 the older side, -1 the newer
    function beyond(index, step, album) {
        let k = index + step
        while (k >= 0 && k < messages.count && messages.get(k).album === album)
            k += step
        return k >= 0 && k < messages.count ? messages.get(k) : undefined
    }
    // a member's media, copied out of its row (a new object: what binds to it is told)
    function reactsOf(id) {
        const i = indexOf(id)
        return i < 0 ? "" : messages.get(i).reacts
    }
    function cellOf(id) {
        const i = indexOf(id)
        if (i < 0)
            return null
        const r = messages.get(i)
        return { picKind: r.picKind, picW: r.picW, picH: r.picH, mini: r.mini, pic: r.pic, dur: r.dur,
                 got: r.got, path: r.path, fileSize: r.fileSize, sending: r.sending, veiled: r.veiled,
                 rowKind: r.rowKind, fileName: r.fileName, wave: r.wave, title: r.title, sub: r.sub,
                 text: r.text, rich: r.rich, out: r.out }
    }
    // the mosaic `wide` across: { width, height, items: [{ id, x, y, w, h, corner }] }
    function tilesOf(g, wide) {
        const key = g.ids.join(",") + "/" + Math.floor(wide) + "/" + Prefs.bubbleR
        if (laidOut[key])
            return laidOut[key]
        const cells = g.ids.map((id) => ({ id: id, c: cellOf(id) })).filter((x) => x.c)
        const lay = Mosaic.layout(cells.map((x) => ({ w: x.c.picW, h: x.c.picH })), Math.floor(wide), 64, 2)
        const round = (it, a, b) => it.sides.indexOf(a) >= 0 && it.sides.indexOf(b) >= 0 ? Math.max(1, Prefs.bubbleR - 3) : Math.min(3, Math.max(1, Prefs.bubbleR - 3))
        lay.items.forEach((it, k) => {
            it.id = cells[k].id
            it.corner = [round(it, "t", "l"), round(it, "t", "r"), round(it, "b", "r"), round(it, "b", "l")].join(",")
        })
        if (cells.length === g.ids.length)
            laidOut[key] = lay
        return lay
    }
    // what shows message `id`'s picture: its tile when it is in an album's mosaic, else its row
    function shownAt(id) {
        const i = indexOf(id)
        if (i < 0)
            return null
        const r = messages.get(i)
        const g = r.album ? albums[r.album] : null
        if (g && g.ids.length > 1) {
            const k = indexOf(g.main)
            const it = k >= 0 ? list.itemAtIndex(k) : null
            return it && it.view ? it.view.tileOf(id) : null
        }
        const it = list.itemAtIndex(i)
        return it ? it.view : null
    }
    Connections {
        target: messages
        function onRowsInserted(parent, first, last) {
            if (first > 0 && last === messages.count - 1)
                page.regroupAdded(first, last)
            else
                page.regroup()
        }
        function onRowsRemoved() { page.regroup() }
        function onModelReset() { page.regroup() }
        // an album member's row changed (its picture came, its file moves on): the albums' cells again,
        // once a frame. Not regroup(): what makes an album (its caption, its comments) is changed where it
        // changes (regroupAt) -- a whole regroup and a tick for each file's progress held the first flick
        // through a group's pictures (each walked all rows, each tick all albums' tiles)
        function onDataChanged(from, to) {
            for (let i = from.row; i <= to.row; i++)
                if (messages.get(i).album) {
                    Qt.callLater(page.tick)
                    return
                }
        }
    }

    // a replied message not loaded here: ask for it, then fill the replies to it
    function want(id) {
        if (asked[id])
            return
        asked[id] = true
        store.send({ "@type": "getMessage", chat_id: chatId, message_id: id }, (m) => {
            if (!page)
                return
            if (m["@type"] === "message")
                page.remember(m)
            else
                page.quotes[id] = { name: "", text: Tr.t("O'chirilgan xabar") }
            page.requote(id)
        })
    }

    function requote(id) {
        const q = quotes[id]
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).replyId === id) {
                messages.setProperty(i, "quoteName", q.name)
                messages.setProperty(i, "quoteText", q.text)
            }
    }

    function indexOf(id) {
        const k = rowAt[id]
        if (k !== undefined && k < messages.count && messages.get(k).msgId === id)
            return k
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).msgId === id)
                return i
        return -1
    }

    function otherDay(other, date) {
        return !other || new Date(other.date * 1000).toDateString() !== new Date(date * 1000).toDateString()
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

    // what is on the screen is read: the newest message in sight and all before it (as Telegram counts)
    function seen() {
        if (!ready || !messages.count)
            return
        // (over the list's bottom spacer, foot + 10: in it there is no row, and atYBeginning is not always true at
        // the bottom -- opened at a few unread ones, the newest were left unread)
        let i = list.indexAt(list.width / 2, list.contentY + list.height - page.foot - 14)
        if (i < 0)
            i = list.atYBeginning ? 0 : -1
        away = gap || i > 2
        if (i < 0 || messages.get(i).msgId <= readTo)
            return
        const ids = []
        const newest = messages.get(i).msgId
        for (let k = i; k < messages.count && ids.length < 100; k++) {
            const r = messages.get(k)
            if (r.msgId <= readTo)
                break
            if (!r.out)
                ids.push(r.msgId)
        }
        readTo = newest
        if (ids.length)
            store.send({ "@type": "viewMessages", chat_id: chatId, message_ids: ids, force_read: true })
    }
    Timer { id: seenLater; interval: 250; onTriggered: page.seen() }
    Timer { id: unflash; interval: 1400; onTriggered: page.flashId = 0 }

    // newer messages while the bottom is 15 away, when it was opened at the unread ones
    function nearBottom() {
        if (!gap || newering || !messages.count)
            return
        const bottom = list.indexAt(list.width / 2, list.contentY + list.height - 4)
        if (bottom < 0 ? list.atYBeginning : bottom <= 15)
            newer()
    }

    function newer() {
        newering = true
        const from = messages.get(0).msgId
        store.send({ "@type": "getChatHistory", chat_id: chatId, from_message_id: from, offset: -40, limit: 41,
                     only_local: false }, (r) => {
            if (!page)
                return
            page.newering = false
            if (r["@type"] === "error") {
                console.warn("nullgram: getChatHistory (newer)", page.chatId, from, r.code, r.message)
                return
            }
            const got = (r.messages || []).filter((m) => m.id > from)      // newest first
            if (!got.length) {
                page.gap = false            // nothing newer: these are the newest
                return
            }
            for (const m of got)
                page.remember(m)
            messages.insert(0, got.map((m) => page.row(m)))
            const last = page.chat && page.chat.last_message
            if (last && got[0].id >= last.id)
                page.gap = false
            Qt.callLater(page.nearBottom)
            seenLater.restart()
        })
    }

    // older messages a page at a time: 20, not 40 -- a page's answer is read (JSON.parse) and its rows
    // remembered in the frame it comes, and 40 (130k letters) took a frame of a flick on the big cores
    readonly property int pageSize: 20
    function older() {
        if (loading || !more || !messages.count)
            return
        loading = true
        store.history(chatId, messages.get(messages.count - 1).msgId, pageSize, (got, failed) => {
            if (!page)
                return
            if (td.fps)
                td.mark("page", 1)
            page.addLater(page.withRoot(got, !failed && got.length < pageSize), () => {
                page.more = failed || got.length > 0
                page.loading = false
                if (!failed)
                    Qt.callLater(page.nearTop)  // still near the top (a short page, a fast flick): the next ones
            })
        }, null, thread, directTopic)
    }

    // older messages while the top of the list is still 15 messages away, not only once it is reached:
    // atYEnd alone does not change again when the list stays at the top after a load
    function nearTop() {
        if (loading || !more || !messages.count)
            return
        const top = list.indexAt(list.width / 2, list.contentY + 4)
        if (top < 0 ? list.atYEnd : top >= messages.count - 15)
            older()
    }

    // the replied message, if it is loaded
    function jump(id) {
        const i = indexOf(id)
        if (i >= 0)
            centre(i)
    }
    // a message in the middle of the screen; one taller than the room there from its top
    function centre(i) {
        list.positionViewAtIndex(i, ListView.Center)
        const it = list.itemAtIndex(i)
        if (it && it.height > list.height - bar.height - foot - 60)
            toTop(i, 8)
    }
    // row i's top just under the header (`gap` lower), as far as the list goes: where the rows run out first
    // (a short chat, the unread ones few) the newest stay in sight over the field, as on iOS, not pushed under it
    // (past its end the list put them back at its next layout, and all of it jumped)
    function toTop(i, gap) {
        list.positionViewAtIndex(i, ListView.End)      // (the end of a bottom-to-top list: its top)
        const it = list.itemAtIndex(i), at = list.contentY
        const want = at + (it ? it.mapToItem(list, 0, 0).y : 0) - bar.height - gap
        list.positionViewAtBeginning()
        const low = list.contentY                       // (the newest at the bottom, over the field)
        list.contentY = Math.min(low, Math.max(list.originY, want))  // (originY may still be short of the rows above)
    }
    // a message in the middle, lit up a moment: loaded here, else the history around it in place of these
    function goTo(id) {
        if (indexOf(id) >= 0) {
            jump(id)
            flashId = id
            unflash.restart()
        } else {
            messages.clear()
            more = true
            openAt(id, false)
        }
    }

    // ---- searching in the chat (Telegram-iOS: the field in the header, ↑ ↓ and "1 of N" under) ----
    property bool searching: false
    property var hits: []               // the messages found, newest first
    property int hit: -1                // the one shown
    property bool searched: false       // TDLib has answered for what is in the field
    function find(q) {
        hits = []
        hit = -1
        searched = false
        if (!q.trim())
            return
        store.send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: store.topic(thread), query: q,
                     sender_id: null, from_message_id: 0, offset: 0, limit: 100, filter: null }, (r) => {
            if (!page || !searching || q !== findField.text)
                return
            if (r["@type"] !== "foundChatMessages")
                console.warn("nullgram: search", JSON.stringify(r))
            page.hits = (r.messages || []).map((m) => m.id)
            page.searched = true
            if (page.hits.length)
                page.showHit(0)
        })
    }
    function showHit(k) {
        hit = k
        goTo(hits[k])
    }
    function focusFind() {
        searching = true
        findField.forceActiveFocus()
    }
    function stopSearch() {
        searching = false
        findField.text = ""
        findField.focus = false
        hits = []
        hit = -1
    }

    // ---- the menu ------------------------------------------------------------
    // testing (NULLGRAM_SAY with a channel): the newest post's comments open and these lines go there
    property string say: ""
    property string findNow: ""         // testing (NULLGRAM_FIND): search for this once the messages are in
    onReadyChanged: {
        if (ready && findNow) {
            searching = true
            findField.text = findNow
            findNow = ""
        }
        if (!ready || !say)
            return
        const t = say
        say = ""
        if (thread) {
            for (const line of t.split("\n"))
                if (line)
                    store.sendText(chatId, line, 0, thread)
        } else if (messages.count) {
            sayLater.text = t
            sayLater.start()            // (once this page is in: a push while one moves is dropped)
        }
    }
    Timer { id: sayLater; property string text; interval: 900; onTriggered: page.openComments(messages.get(0).msgId, text) }

    // a post's comments, in a page of their own over this one (the discussion group's thread)
    property Component commentsPage: null
    function openComments(id, say) {
        store.send({ "@type": "getMessageThread", chat_id: chatId, message_id: id }, (r) => {
            if (!page)
                return
            if (r["@type"] !== "messageThreadInfo") {
                console.warn("nullgram: getMessageThread", r.code, r.message)
                return
            }
            if (!page.commentsPage)
                page.commentsPage = Qt.createComponent("ChatPage.qml")
            page.nav.push(page.commentsPage, { chatId: r.chat_id, thread: r.message_thread_id, threadRoot: r.messages || [], say: say || "",
                                               threadOf: page.chat ? page.chat.title : "" })
        })
    }

    // a tap on a link in a message's words (Words' hrefs, Store.rich): a spoiler shows, @name, a
    // t.me link and a user open their chat (a message link at the message), #tag is looked for in
    // this chat, /command is sent; the rest goes to the browser
    function follow(url, id) {
        if (url === "spoiler") {
            bared[id] = true
            const i = indexOf(id)
            if (i >= 0 && spoilers[id] && originals[id] === undefined)
                messages.setProperty(i, "rich", store.rich(spoilers[id], true))
            return
        }
        const c = url.charAt(0)
        if (c === "#" || c === "$") {
            searching = true
            findField.text = url
            return
        }
        if (c === "/") {
            store.sendText(chatId, url, 0, thread)
            return
        }
        if (c === "@") {
            store.send({ "@type": "searchPublicChat", username: url.slice(1) }, (r) => openChat(r, 0))
            return
        }
        if (url.startsWith("user:")) {
            store.send({ "@type": "createPrivateChat", user_id: Number(url.slice(5)), force: false }, (r) => openChat(r, 0))
            return
        }
        if (url.startsWith("time:")) {
            playFrom(Number(url.slice(5)), id)
            return
        }
        if (!/^(https?:\/\/)?(t\.me|telegram\.me|telegram\.dog)\/|^tg:/i.test(url)) {
            Qt.openUrlExternally(url)
            return
        }
        store.send({ "@type": "getInternalLinkType", link: url }, (r) => {
            const t = r["@type"]
            if (t === "internalLinkTypePublicChat")
                store.send({ "@type": "searchPublicChat", username: r.chat_username }, (c) => openChat(c, 0))
            else if (t === "internalLinkTypeMessage")
                store.send({ "@type": "getMessageLinkInfo", url: url }, (info) => {
                    if (info["@type"] !== "messageLinkInfo" || !info.chat_id)
                        return toast(Tr.t("Xabar topilmadi"))
                    openChat({ "@type": "chat", id: info.chat_id }, info.message ? info.message.id : 0)
                })
            else if (t === "internalLinkTypeChatInvite")
                store.send({ "@type": "checkChatInviteLink", invite_link: r.invite_link }, (info) => {
                    if (info.chat_id)
                        openChat({ "@type": "chat", id: info.chat_id }, 0)
                    else
                        toast(info.title ? Tr.f("«%1» — taklif havolasi", info.title) : Tr.t("Havola ochilmadi"))
                })
            else
                Qt.openUrlExternally(url)
        })
    }
    function openChat(r, target) {
        if (!page)
            return
        if (r["@type"] !== "chat")
            return toast(Tr.t("Topilmadi") + (r.message ? ": " + r.message : ""))
        if (r.id === chatId && !thread) {
            if (target)
                jump(target)
            return
        }
        if (!page.commentsPage)
            page.commentsPage = Qt.createComponent("ChatPage.qml")
        page.nav.push(page.commentsPage, target ? { chatId: r.id, target: target } : { chatId: r.id })
    }
    function unfold(id) {
        const u = Object.assign({}, unfolded)
        if (u[id])
            delete u[id]
        else
            u[id] = true
        unfolded = u
    }

    // `one`: an album's picture or file under the finger (its id), as Telegram-iOS puts the one pressed
    // first: «Nusxalash» takes its caption; a picture without one the album's, a file without one none
    // the keyboard down now. Qt.inputMethod.hide() does nothing under the shell (text-input-v3 has no
    // hide; the keyboard goes once nothing holds the focus): the field let go of, the shell told at once
    function keyboardDown() {
        panelOpen = false
        panelHold = false
        if (page.kb > 0) {
            field.focus = false
            osk.hide()
        }
    }

    function openMenu(item, one) {
        keyboardDown()              // first: over the menu's actions it would stay
        const own = one && one !== item.msgId ? cellOf(one) : null
        const m = { id: item.msgId, text: item.text, kind: item.kind, out: item.out,
                    name: item.out ? Tr.t("Siz") : item.sender || (chat ? chat.title : ""),
                    ids: item.grouped ? item.group.ids : [item.msgId],      // (an album: all of it)
                    copy: own && (own.text || item.stacked) ? own.text : item.emo || item.text }
        // its properties and the reactions it can get, both asked at once; the menu opens with both
        let props = null, reactions = null
        const both = () => { if (props && reactions) page.showMenu(item, m, props, reactions) }
        store.send({ "@type": "getMessageAvailableReactions", chat_id: chatId, message_id: item.reactId, row_size: 8 }, (r) => {
            const list = r["@type"] === "availableReactions" ? r.top_reactions.concat(r.popular_reactions || []) : []
            const hasPaid = page.channel && list.some((a) => a.type["@type"] === "reactionTypePaid")
            const emojis = list.filter((a) => a.type["@type"] === "reactionTypeEmoji" && !a.needs_premium)
                               .map((a) => a.type.emoji).filter((e, i, all) => all.indexOf(e) === i).slice(0, hasPaid ? 11 : 12)
            reactions = hasPaid ? ["⭐"].concat(emojis) : emojis
            both()
        })
        store.send({ "@type": "getMessageProperties", chat_id: chatId, message_id: m.id }, (p) => {
            props = p
            both()
        })
    }

    function showMenu(item, m, p, reactions, waited) {
        const ok = p["@type"] === "messageProperties"
        const acts = []
        if (ok && p.can_be_replied && !page.channel)
            acts.push({ text: Tr.t("Javob yozish"), glyph: "↩", run: () => page.reply(m) })
        if (m.copy)
            acts.push({ text: Tr.t("Nusxalash"), glyph: "⧉", run: () => page.copy(m.copy) })
        if (ok && p.can_be_edited && !m.kind && !item.media && !item.rowKind)
            acts.push({ text: Tr.t("Tahrirlash"), glyph: "✎", run: () => page.edit(m) })
        if (m.text && !page.translating && (Prefs.translateButton || page.originals[m.id] !== undefined))   // this one alone in Uzbek, and back
            acts.push(page.originals[m.id] !== undefined
                      ? { text: Tr.t("Asl nusxasi"), glyph: "🌐", run: () => page.untranslateOne(m.id) }
                      : { text: Tr.t("Tarjima qilish"), glyph: "🌐", run: () => { page.ones[m.id] = true; page.translateId(m.id) } })
        if (ok && p.can_get_link)
            acts.push({ text: Tr.t("Havolani nusxalash"), glyph: "🔗", run: () => page.copyLink(m.id) })
        if (ok && p.can_be_forwarded)
            acts.push({ text: Tr.t("Uzatish"), glyph: "↪", run: () => { page.forwarding = m.ids; page.copying = false; forwardSheet.show() } })
        if (ok && p.can_be_copied && page.channel)   // (Telegram-iOS's "forward without the author's name")
            acts.push({ text: Tr.t("Imzosiz forward qilish"), glyph: "↪", run: () => { page.forwarding = m.ids; page.copying = true; forwardSheet.show() } })
        if (ok && p.can_be_pinned)
            acts.push({ text: item.isPinned ? Tr.t("Qadashni olish") : Tr.t("Qadash"), glyph: "📌",
                        run: () => store.pin(page.chatId, m.id, !item.isPinned) })
        if (page.mains[m.id] && !item.sending)
            acts.push({ text: item.picKind === "photo" ? Tr.t("Rasmni saqlash") : item.picKind === "video" || item.picKind === "round" ? Tr.t("Videoni saqlash") : Tr.t("Saqlash"),
                        glyph: "↓", run: () => page.save(m.id) })
        if (item.rowKind === "poll" && item.poll) {      // Telegram-iOS's «Retract Vote», «Stop Poll»
            const poll = JSON.parse(item.poll)
            if (!poll.is_closed && poll.type["@type"] !== "pollTypeQuiz" && poll.options.some((o) => o.is_chosen))
                acts.push({ text: Tr.t("Ovozni qaytarish"), glyph: "↺", run: () => page.vote(m.id, []) })
            if (!poll.is_closed && m.out && ok && p.can_be_edited)
                acts.push({ text: poll.type["@type"] === "pollTypeQuiz" ? Tr.t("Viktorinani yakunlash") : Tr.t("So'rovnomani yakunlash"), glyph: "■",
                            run: () => store.send({ "@type": "stopPoll", chat_id: page.chatId, message_id: m.id, reply_markup: null }, store.check) })
        }
        if (ok && p.can_report_chat && !m.out)       // (TDLib allows one's own; Telegram's apps do not offer it)
            acts.push({ text: Tr.t("Shikoyat qilish"), glyph: "ⓘ", run: () => page.report([m.id], "", "") })
        if (ok && p.can_be_deleted_only_for_self && p.can_be_deleted_for_all_users) {
            acts.push({ text: Tr.t("Men uchun o'chirish"), glyph: "✕", danger: true,
                        run: () => store.deleteMessages(page.chatId, m.ids, false) })
            acts.push({ text: Tr.t("Hamma uchun o'chirish"), glyph: "✕", danger: true,
                        run: () => store.deleteMessages(page.chatId, m.ids, true) })
        } else if (ok && (p.can_be_deleted_only_for_self || p.can_be_deleted_for_all_users)) {
            acts.push({ text: Tr.t("O'chirish"), glyph: "✕", danger: true,
                        run: () => store.deleteMessages(page.chatId, m.ids, p.can_be_deleted_for_all_users) })
        }
        if (!item.said && !item.sending)        // set apart at the end, as Telegram-iOS has it
            acts.push({ text: Tr.t("Tanlash"), glyph: "✓", gap: true, run: () => page.startPicking(m.ids) })
        // our message: when they read it (a private chat) or who saw it (a group), first, set apart from the
        // actions -- Telegram-iOS's ContextMenu read stats. A row kept for it while TDLib is asked (the
        // menu does not wait), filled when it answers, taken away if there is nothing to say
        const stats = ok && (p.can_get_read_date || p.can_get_viewers) && acts.length
        if (stats) {
            acts.unshift({ text: "…", glyph: p.can_get_read_date ? "✓✓" : "👁", info: true })
            acts[1] = Object.assign({}, acts[1], { gap: true })
        }
        if (page.kb > 0 && !waited) {   // (opened once it is down: the bubble moves down with the list)
            menuWaits = () => page.showMenu(item, m, p, reactions, true)
            menuLate.restart()
            return
        }
        const i = page.indexOf(m.id)
        const shell = i >= 0 ? list.itemAtIndex(i) : null
        const it = shell ? shell.view : null
        page.reacting = item.reactId
        if (it && acts.length) {
            menu.show(it.face, m.out, acts, reactions, it.reactList.filter((r) => r.mine).map((r) => r.e))
            if (stats)
                readStats(m.id, p.can_get_read_date, it.face)
        }
    }

    // a time as iOS's read stats say it: "14:32", "Kecha 14:32", "3-noyabr 14:32"
    function whenSaid(unix) {
        const d = new Date(unix * 1000), day = dayName(unix)
        return (day === Tr.t("Bugun") ? "" : day + " ") + Qt.formatTime(d, "HH:mm")
    }
    function readStats(id, private_, face) {
        const here = () => page && menu.open && menu.bubble === face
        const set = (row) => {      // the first row (the kept one) now this, or gone (null)
            if (!here())
                return
            const acts = menu.actions.slice()
            if (row)
                acts[0] = Object.assign({}, acts[0], row)
            else {
                acts.shift()
                acts[0] = Object.assign({}, acts[0], { gap: false })
            }
            menu.change(acts)
        }
        if (private_) {
            store.send({ "@type": "getMessageReadDate", chat_id: chatId, message_id: id }, (r) => {
                const t = r["@type"]
                set(t === "messageReadDateRead" ? { text: Tr.f("%1 da o'qildi", whenSaid(r.read_date)) }
                    : t === "messageReadDateUnread" ? { text: Tr.t("Hali o'qilmadi") }
                    : t === "messageReadDateUserPrivacyRestricted" || t === "messageReadDateMyPrivacyRestricted"
                      ? { text: Tr.t("O'qildi (vaqti yashirin)") } : null)
            })
            return
        }
        store.send({ "@type": "getMessageViewers", chat_id: chatId, message_id: id }, (r) => {
            const seen = r["@type"] === "messageViewers" ? r.viewers : []
            if (!seen.length) {
                set({ text: Tr.t("Hech kim ko'rmadi") })
                return
            }
            const one = seen.length === 1 ? store.senderName({ "@type": "messageSenderUser", user_id: seen[0].user_id }, false) : ""
            set({ text: one || Tr.n("%1 kishi ko'rdi", seen.length), info: false,
                  side: one ? whenSaid(seen[0].view_date) : "",
                  run: seen.length > 1 ? () => page.showViewers(seen) : null, stay: true })
        })
    }
    // who saw it, in the menu in place of its actions (Telegram-iOS's list behind «N Seen»); back: the actions
    function showViewers(seen) {
        const was = menu.actions
        const rows = [{ text: Tr.t("Orqaga"), glyph: "‹", stay: true, run: () => menu.change(was) }]
        for (const v of seen)
            rows.push({ text: store.senderName({ "@type": "messageSenderUser", user_id: v.user_id }, false) || "…",
                        side: whenSaid(v.view_date), gap: rows.length === 1 })
        menu.change(rows)
    }
    property bool holding: false        // a long-pressed bubble's finger still down: the list stays where it is
    property var menuWaits: null        // the menu, while the keyboard goes down
    onKbChanged: if (kb === 0 && menuWaits) menuLate.triggered()
    Timer {
        id: menuLate
        interval: 800               // (should the keyboard not go)
        onTriggered: {
            const f = page.menuWaits
            page.menuWaits = null
            stop()
            if (f)
                f()
        }
    }
    property var forwarding: []         // the messages the forward sheet sends
    property bool copying: false        // and whether as our own (no "forwarded from")
    property var reacting: 0            // the message the menu's reactions go on

    function reply(m) {
        editing = null
        replying = { id: m.id, name: m.name, text: m.text || m.kind }
        field.forceActiveFocus()
    }

    function edit(m) {
        replying = null
        editing = { id: m.id }
        field.text = m.text
        field.cursorPosition = field.length
        field.forceActiveFocus()
        // its formatting comes along (TDLib has the message at hand), unless already typed over
        store.send({ "@type": "getMessage", chat_id: chatId, message_id: m.id }, (r) => {
            const ft = r && r.content && store.formatted(r.content)
            if (!page || !editing || editing.id !== m.id || !ft || field.text !== ft.text)
                return
            marks = ft.entities.filter((e) => store.given.indexOf(e.type["@type"]) >= 0)
            ink.paint(field.textDocument, marks, Theme.accent)
        })
    }

    // whether the chosen words are all under a mark of this kind (the field's Format menu)
    function marked(kind) {
        const a = field.selectionStart, b = field.selectionEnd
        return b > a && marks.some((e) => e.type["@type"] === kind && e.offset <= a && e.offset + e.length >= b)
    }
    // the Format menu: the chosen words get this mark, or lose it when they have it (url: a link's)
    function toggleMark(kind, url) {
        const a = field.selectionStart, b = field.selectionEnd
        if (b <= a)
            return
        const off = marked(kind)
        const out = []
        let lo = a, hi = b
        for (const e of marks) {
            const x = e.offset, y = e.offset + e.length
            if (e.type["@type"] !== kind || y < a || x > b) {
                out.push(e)
                continue
            }
            if (off) {               // what is left of it on either side of the chosen words
                if (x < a)
                    out.push({ "@type": "textEntity", offset: x, length: a - x, type: e.type })
                if (y > b)
                    out.push({ "@type": "textEntity", offset: b, length: y - b, type: e.type })
            } else if (!url) {       // one with those it touches (a link keeps its own address)
                lo = Math.min(lo, x)
                hi = Math.max(hi, y)
            } else
                out.push(e)
        }
        if (!off) {
            const type = { "@type": kind }
            if (url)
                type.url = url
            out.push({ "@type": "textEntity", offset: lo, length: hi - lo, type: type })
        }
        marks = out.sort((p, q) => p.offset - q.offset)
        ink.paint(field.textDocument, marks, Theme.accent)
    }

    // the field's formatting as TDLib's textEntity's, moved along as its words change: what is
    // typed inside a mark grows it, at its edges stays out; a custom emoji typed over is dropped
    property var marks: []
    property string fieldWas: ""
    function reMark() {
        const was = fieldWas, now = field.text
        fieldWas = now
        if (!marks.length)
            return
        let p = 0
        while (p < was.length && p < now.length && was[p] === now[p])
            p++
        let q = 0
        while (q < was.length - p && q < now.length - p && was[was.length - 1 - q] === now[now.length - 1 - q])
            q++
        const end = was.length - q, d = now.length - was.length
        const out = []
        for (const e of marks) {
            const a = e.offset, b = e.offset + e.length
            if (e.type["@type"] === "textEntityTypeCustomEmoji" && a < end && b > p)
                continue
            const a2 = a < p ? a : a >= end ? a + d : p + Math.max(0, end - p + d)
            const b2 = b <= p ? b : b >= end ? b + d : p
            if (b2 > a2)
                out.push({ "@type": "textEntity", offset: a2, length: b2 - a2, type: e.type })
        }
        marks = out
        ink.paint(field.textDocument, marks, Theme.accent)
    }
    // the field's words to send, trimmed, with their marks moved to match
    function fieldWords() {
        const t = field.text, lead = t.length - t.replace(/^\s+/, "").length
        const text = t.trim()
        const out = []
        for (const e of marks) {
            const a = Math.max(0, e.offset - lead), b = Math.min(text.length, e.offset + e.length - lead)
            if (b > a)
                out.push({ "@type": "textEntity", offset: a, length: b - a, type: e.type })
        }
        return { text: text, marks: out }
    }

    // Shikoyat qilish (reportChat): Telegram asks step by step — why (its options, maybe nested),
    // some words when it wants them — until it is sent
    function report(ids, option, text) {
        store.send({ "@type": "reportChat", chat_id: chatId, option_id: option, message_ids: ids, text: text }, (r) => {
            if (!page)
                return
            const t = r["@type"]
            if (t === "reportChatResultOk")
                toast(Tr.t("Shikoyat yuborildi"))
            else if (t === "reportChatResultOptionRequired")
                reportMenu.ask({ ids: ids, title: r.title, options: r.options })
            else if (t === "reportChatResultTextRequired")
                reportMenu.ask({ ids: ids, option: r.option_id, optional: r.is_optional })
            else
                toast(t === "error" ? Tr.t("Shikoyat yuborilmadi") : Tr.t("Avval xabarlarni tanlang"))
        })
    }

    function copyLink(id) {
        store.send({ "@type": "getMessageLink", chat_id: chatId, message_id: id }, (r) => {
            if (!page)
                return
            if (r["@type"] === "messageLink") {
                page.copy(r.link)
                page.toast(Tr.t("Havola nusxalandi"))
            } else {
                page.toast(Tr.t("Havolani olib bo'lmadi"))
            }
        })
    }

    // «Tanlash» (Telegram-iOS: the menu's last, set apart): messages picked by a tap each — a circle on
    // each one's left, «N ta tanlandi» over them, under them deleting and forwarding them all at once
    property bool selecting: false
    // the rows' circles made while picking, and kept as they go (450 ms: their slide out)
    property bool picking: false
    onSelectingChanged: {
        if (selecting) {
            unpicked.stop()
            picking = true
        } else {
            unpicked.restart()
        }
    }
    Timer { id: unpicked; interval: 450; onTriggered: page.picking = false }
    property var picked: ({})           // id → its messageProperties (null until TDLib answers)
    readonly property var pickedIds: Object.keys(picked).map(Number).sort((a, b) => a - b)  // oldest first
    function startPicking(ids) {
        keyboardDown()
        cancelCompose()
        picked = ({})
        selecting = true
        pick(ids)
    }
    // these (one message, or an album's all) picked, or put back when they all were
    function pick(ids) {
        const p = Object.assign({}, picked)
        if (ids.every((id) => p[id] !== undefined)) {
            ids.forEach((id) => delete p[id])
            picked = p
            return
        }
        ids.forEach((id) => p[id] = null)
        picked = p
        for (const id of ids)
            store.send({ "@type": "getMessageProperties", chat_id: chatId, message_id: id }, (r) => {
                if (!page || picked[id] === undefined)
                    return
                const q = Object.assign({}, picked)
                q[id] = r["@type"] === "messageProperties" ? r : {}
                picked = q
            })
    }
    function stopPicking() {
        selecting = false
        picked = ({})
        deleteMenu.visible = false
    }
    // whether every one picked can (each one's properties known)
    function pickedCan(what) {
        const ids = Object.keys(picked)
        return ids.length > 0 && ids.every((k) => picked[k] && picked[k][what])
    }
    readonly property bool pickedDeletable: pickedIds.length > 0 && Object.keys(picked).every((k) =>
        picked[k] && (picked[k].can_be_deleted_only_for_self || picked[k].can_be_deleted_for_all_users))
    function deletePicked(everyone) {
        store.deleteMessages(chatId, pickedIds, everyone)
        stopPicking()
    }
    // the picked ones' words, oldest first, a blank line between (those loaded; media without words left out)
    readonly property string pickedText: {
        const out = []
        for (const id of pickedIds) {
            const i = indexOf(id)
            const t = i >= 0 ? messages.get(i).text : ""
            if (t)
                out.push(t)
        }
        return out.join("\n\n")
    }
    function forwardPicked() {
        forwarding = pickedIds
        copying = false
        stopPicking()
        forwardSheet.show()
    }

    function copy(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
    }

    // Drafts (Telegram-iOS's ChatInterfaceState): what is typed, and what it answers, kept by Telegram
    // (setChatDraftMessage: on every device, the chat list's «Draft:») a moment after typing stops and
    // as the chat closes; back in the field when it opens. Not while a message is edited (that is not a
    // draft), nor in a post's comments (theirs is the thread's, not the chat's)
    property string draftKept: ""       // what Telegram has (text + reply), so the same is not sent again
    function draftKey(w, to) { return w.text + "\u0001" + JSON.stringify(w.marks) + "\u0001" + to }
    function saveDraft() {
        if (thread || editing || !chat)
            return
        const w = fieldWords(), to = replying ? replying.id : 0
        const key = draftKey(w, to)
        if (key === draftKept)
            return
        draftKept = key
        store.send({ "@type": "setChatDraftMessage", chat_id: chatId, topic_id: null,
                     draft_message: !w.text && !to ? null : {
                         "@type": "draftMessage",
                         reply_to: to ? { "@type": "inputMessageReplyToMessage", message_id: to } : null,
                         content: { "@type": "draftMessageContentText",
                                    text: { "@type": "formattedText", text: w.text, entities: w.marks } } } },
                   store.check)
    }
    Timer { id: draftLater; interval: 1500; onTriggered: page.saveDraft() }
    function loadDraft() {
        const d = !thread && chat ? chat.draft_message : null
        const c = d && d.content
        const ft = c && c["@type"] === "draftMessageContentText" ? c.text : null
        if (ft && ft.text) {
            field.text = ft.text
            field.cursorPosition = field.length
            marks = (ft.entities || []).filter((e) => store.given.indexOf(e.type["@type"]) >= 0)
            ink.paint(field.textDocument, marks, Theme.accent)
        }
        const to = d && d.reply_to && d.reply_to["@type"] === "inputMessageReplyToMessage" ? d.reply_to.message_id : 0
        draftKept = draftKey(fieldWords(), to)
        if (to)
            store.send({ "@type": "getMessage", chat_id: chatId, message_id: to }, (m) => {
                if (!page || m["@type"] !== "message" || page.replying || page.editing)
                    return
                page.replying = { id: m.id, name: m.is_outgoing ? Tr.t("Siz") : store.senderName(m.sender_id, false),
                                  text: store.preview(m.content, chat) }
            })
    }
    onReplyingChanged: if (ready) draftLater.restart()

    function cancelCompose() {
        if (editing)
            field.text = ""
        editing = null
        replying = null
    }

    // the back button: the menu first, then a reply or edit being written (Main asks)
    function dismiss() {
        if (paidAlert.open) {
            paidAlert.open = false
            return true
        }
        if (paidSheet.open) {
            paidSheet.backOne()
            return true
        }
        if (sheet.open) {
            sheet.close()
            return true
        }
        if (giftSheet.open) {
            giftSheet.backOne()
            return true
        }
        if (forwardSheet.open) {
            forwardSheet.close()
            return true
        }
        if (viewer.open) {
            viewer.close()
            return true
        }
        if (menu.open) {
            menu.close()
            return true
        }
        if (deleteMenu.visible) {
            deleteMenu.visible = false
            return true
        }
        if (recording) {         // a locked voice note: thrown away, as its «Bekor qilish»
            stopVoice(true)
            return true
        }
        if (preview || roundPreview) {
            dropPreview()
            return true
        }
        if (voters.visible || placeMenu.visible) {
            voters.visible = false
            placeMenu.visible = false
            return true
        }
        if (panelOpen) {         // the emoji panel down, as the keyboard would go
            keyboardDown()
            return true
        }
        if (selecting) {
            stopPicking()
            return true
        }
        if (searching) {
            stopSearch()
            return true
        }
        if (replying || editing) {
            cancelCompose()
            return true
        }
        return false
    }

    TextEdit { id: clip; visible: false }      // the clipboard's way in

    Connections {
        target: store
        function onReadOutbox(chatId, lastRead) {
            if (chatId === page.chatId)
                page.readUpTo = lastRead
        }
        function onMessage(m) {
            if (m.chat_id !== page.chatId || page.gap)      // (in a gap it comes with the newer ones)
                return
            if (page.thread && !(m.topic_id && m.topic_id.message_thread_id === page.thread))
                return
            if (page.directTopic && !(m.topic_id && m.topic_id["@type"] === "messageTopicDirectMessages"
                                      && m.topic_id.direct_messages_chat_topic_id === page.directTopic))
                return
            for (let i = 0; i < Math.min(messages.count, 20); i++)
                if (messages.get(i).msgId === m.id)
                    return
            const from = m.is_outgoing && page.flying &&     // (one emoji alone comes back as messageAnimatedEmoji)
                         store.plain(m.content) === page.flying.text ? page.flying : null
            const bottom = list.atYBeginning || scroll.running || from
            const was = list.contentY
            page.remember(m)
            messages.insert(0, page.row(m))
            if (bottom) {            // keep the newest in sight: scroll to it on the sent bubble's vertical curve
                list.positionViewAtBeginning()
                const to = list.contentY
                list.contentY = was
                scroll.to = to
                scroll.restart()
                if (from) {
                    page.flying = null
                    const it = list.itemAtIndex(0)
                    if (it && it.view)
                        it.view.flyFrom(from)
                }
            }
            seenLater.restart()
        }
        function onChatChanged(chatId) {
            if (chatId === page.chatId) {
                page.rewall()
                page.unread = page.chat.unread_count
                page.muted = page.isMuted()
                page.blocked = page.isBlocked()
            }
        }
        function onMessageChanged(chatId, oldId, m) {
            if (chatId !== page.chatId)
                return
            for (let i = 0; i < Math.min(messages.count, 50); i++)
                if (messages.get(i).msgId === oldId) {
                    if (page.unveiled[oldId])       // (its spoiler taken off while it went)
                        page.unveiled[m.id] = true
                    page.remember(m)
                    messages.set(i, page.row(m))
                    page.regroupAt(i)               // (an album's member: its id in the album is another now)
                    const r = messages.get(i)
                    if (!r.pic)                     // (the delegate stays: it does not ask again by itself)
                        page.loadPic(m.id)
                    // nor bring down what comes down by itself: a GIF sent is the server's MP4 now, not
                    // the file that went (it stood still under a ↓)
                    if (r.auto && !r.path && r.got < 0)
                        page.download(m.id, false)
                    return
                }
        }
        function onContentOpened(chatId, id) {
            const i = chatId === page.chatId ? page.indexOf(id) : -1
            if (i >= 0)
                messages.setProperty(i, "heard", true)
        }
        function onMessageContent(chatId, id, content) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0) {
                const s = page.shown(content, id)
                delete page.translations[id]
                delete page.originals[id]
                page.put(i, s)
                if (page.translating || page.ones[id])
                    page.translateId(id)
                messages.setProperty(i, "kind", s.kind)
                messages.setProperty(i, "poll", content["@type"] === "messagePoll" ? JSON.stringify(content.poll) : "")
                const p = page.media(content)
                messages.setProperty(i, "veiled", p.spoiler && !page.unveiled[id])
                messages.setProperty(i, "heard", p.heard || page.channel)
                if (p.picKind === "map" && content["@type"] === "messageLiveLocation") {     // moved: its map again
                    const was = page.maps[id], now = content.location.location
                    if (!was || was.latitude !== now.latitude || was.longitude !== now.longitude) {
                        page.maps[id] = now
                        delete page.files[id]
                        page.loadMap(id)
                    }
                    const r = messages.get(i)
                    messages.setProperty(i, "dur", content.location.live_period >= 0x7FFFFFFF ? 0x7FFFFFFF : r.date + content.location.live_period)
                }
                if (p.file && p.file.id !== (page.files[id] || {}).id) {
                    page.files[id] = p.file
                    messages.setProperty(i, "pic", "")
                    page.loadPic(id)
                }
            }
            if (page.quotes[id]) {
                page.quotes[id].text = store.preview(content, chat)
                page.requote(id)
            }
        }
        function onMessagePinned(chatId, id, on) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0)
                messages.setProperty(i, "isPinned", on)
            page.loadPinned()
        }
        function onEmojiClicked(chatId, id, sticker) {     // the other one tapped an emoji: it plays here too
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id), shell = i >= 0 ? list.itemAtIndex(i) : null
            if (shell && shell.view)
                shell.view.replay(true)
            page.burst(id, sticker)
        }
        function onMessageInteraction(chatId, id, info) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i < 0)
                return
            messages.setProperty(i, "reacts", JSON.stringify(store.reactions(info, page.chat)))
            messages.setProperty(i, "views", info ? info.view_count : 0)
            if (page.channel && info && info.reply_info) {
                messages.setProperty(i, "comments", info.reply_info.reply_count)
                page.regroupAt(i)
            } else if (!page.channel)
                messages.setProperty(i, "replies", info && info.reply_info ? info.reply_info.reply_count : 0)
        }
        function onFileUpdated(f) {
            const ids = page.fileMsgs[f.id]
            if (!ids)
                return
            for (const id of ids) {
                page.mains[id] = f
                const i = page.indexOf(id)
                if (i < 0)
                    continue
                const done = f.local.is_downloading_completed
                messages.setProperty(i, "got", store.progress(f))
                if (done && messages.get(i).path !== f.local.path)
                    messages.setProperty(i, "path", f.local.path)
                if (done && page.wantOpen === id) {
                    page.wantOpen = 0
                    const it = page.shownAt(id)
                    if (it)
                        page.openMedia(it)
                }
            }
        }
        function onMessageEdited(chatId, id, date) {
            if (chatId !== page.chatId)
                return
            const i = page.indexOf(id)
            if (i >= 0)
                messages.setProperty(i, "edited", true)
        }
        function onMessagesDeleted(chatId, ids) {
            if (chatId !== page.chatId)
                return
            for (let i = messages.count - 1; i >= 0; i--)
                if (ids.indexOf(messages.get(i).msgId) >= 0)
                    messages.remove(i)
            if (page.editing && ids.indexOf(page.editing.id) >= 0)
                page.cancelCompose()
            if (page.replying && ids.indexOf(page.replying.id) >= 0)
                page.replying = null
            if (page.selecting && ids.some((id) => page.picked[id] !== undefined)) {
                const p = Object.assign({}, page.picked)
                ids.forEach((id) => delete p[id])
                page.picked = p
            }
        }
    }

    Item {               // the chat itself: what the menu blurs
        id: content
        anchors.fill: parent

        Wallpaper {          // the background: the chat's own, else the app's
            anchors.fill: parent
            spec: page.wallSpec || Theme.wall
        }
        Rectangle { anchors.fill: parent; color: "black"; opacity: Theme.dark && page.wallSpec ? page.wallDim : 0; visible: opacity > 0 }

        ListView {
            id: list
            interactive: !page.holding
            anchors.fill: parent
            transform: Translate { y: -page.kb }
            z: page.lift ? 2 : 0        // over the field while a sent bubble leaves it (the header stays over all)
            model: messages
            verticalLayoutDirection: ListView.BottomToTop
            cacheBuffer: 800
            maximumFlickVelocity: 6000
            flickDeceleration: 2200
            header: Item { width: 1; height: page.foot + 10 }
            footer: Item { width: 1; height: bar.height + pinBar.height + 8 + page.kbTo }   // (gone up: the oldest clear the header)
            onContentYChanged: {                             // (index 0 is the newest, at the bottom)
                page.nearTop()
                page.nearBottom()
                seenLater.restart()
            }
            // where it stands, in steps of 100: what every row asks each frame of a flick (inSight,
            // onScreen) is worked out again only when it moves on a step
            readonly property real seen: Math.round(contentY / 100) * 100
            // whether it stands at the newest: then it stays there when the field grows or shrinks
            property bool down: true
            onMovementEnded: down = atYBeginning

            // a row is a shell (what the model gives it, whether it shows) and, only when it shows, its bubble in
            // it (`look`). An album's others are tucked under its first: rows of their own with nothing to show,
            // they made a whole bubble each (its texts, frame, time, a dozen bindings asking the page), in a
            // group of albums more than half the rows made in a first flick, every one of them hidden.
            delegate: Item {
                id: shell
                readonly property real born: td.fps ? Date.now() : 0     // (NULLGRAM_FPS: what a row cost to make)
                required property int index
                required property var msgId
                required property bool out
                required property string text
                required property string rich
                required property string kind
                required property string sender
                required property string senderKey
                required property string rank       // beside the name, on the right: an admin's title, a signature
                required property int rankKind      // 0 grey (a signature, a member's tag), 1 an admin's, 2 the owner's
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
                required property int edge          // its older neighbour came: first and newDay again
                required property string rowKind    // voice | audio | file: a row in the bubble
                required property string fileName
                required property real fileSize
                required property string wave
                required property string title
                required property string sub
                required property bool anim         // a video sticker: it plays as a GIF does
                required property string emo        // one emoji alone, drawn as Telegram's animated one: the emoji
                required property int fitz          // its skin tone (tlottie's fitz modifier)
                required property bool auto         // comes down by itself (GIFs, voice notes, round videos)
                required property real got          // the file coming down or going up: how far, else -1
                required property string path       // the file, here
                required property int jumbo         // one to three emoji alone: big, no bubble
                required property string fwd        // forwarded: who from
                required property string reacts     // its reactions, JSON: [{ e, n, mine }]
                required property bool isPinned
                required property int comments      // a channel post's comments (-1: none)
                required property int replies       // a group message's answers
                required property string said       // a service message: its words, in a pill in the middle
                required property string album      // pictures sent together: their media_album_id
                required property bool veiled       // a spoiler: the picture blurred under dust until tapped
                required property string poll       // a poll: TDLib's, JSON (PollView)
                required property bool heard        // a voice note or a round video played (else its dot)
                // an album: its main one shows them all (a mosaic), the others are tucked away under it
                readonly property var group: album !== "" ? (page.albumRev, page.albums[album] || null) : null
                readonly property bool grouped: group !== null && group.ids.length > 1
                readonly property bool tucked: grouped && group.main !== msgId
                readonly property bool media: picKind !== ""
                readonly property Item view: look.item          // the row as the page asks it things (null: tucked)
                readonly property bool translated: page.translating
                onTranslatedChanged: if (translated) page.translateId(msgId)
                Component.onCompleted: {
                    if (td.fps) {
                        td.mark("row", 1)
                        td.mark("makems", Date.now() - born)
                        if (Date.now() - born > 25)
                            console.warn("nullgram: slow row", Date.now() - born, "ms", kind, picKind, rowKind, album ? "album" : "",
                                         text.length, "chars", reacts.length > 2 ? "reacts" : "", replyId ? "reply" : "",
                                         JSON.stringify((said || fwd || sender).slice(0, 40)))
                    }
                    if (page.translating || page.ones[msgId])
                        page.translateId(msgId)
                    if ((media || rowKind === "file") && !pic)
                        page.loadPic(msgId)
                    if (auto && !path && got < 0)
                        page.download(msgId, false)
                }
                width: list.width
                height: look.item ? look.item.height : 0
                visible: !tucked
                z: view && view.bursting ? 5 : 1        // (its emoji's effect over the rows about it)
                Loader {
                    id: look
                    active: !shell.tucked
                    width: shell.width
                    // (inside, `item` is the row: its own id, found before the Loader's `item`; what the model
                    // gave the shell, handed in)
                    sourceComponent: Item {
                        id: item
                        readonly property int index: shell.index
                        readonly property var msgId: shell.msgId
                        readonly property bool out: shell.out
                        readonly property string text: shell.text
                        readonly property string rich: shell.rich
                        readonly property string kind: shell.kind
                        readonly property string sender: shell.sender
                        readonly property string senderKey: shell.senderKey
                        readonly property string tint: shell.tint
                        readonly property string rank: shell.rank
                        readonly property int rankKind: shell.rankKind
                        readonly property string time: shell.time
                        readonly property bool sending: shell.sending
                        readonly property int views: shell.views
                        readonly property int date: shell.date
                        readonly property bool edited: shell.edited
                        readonly property var replyId: shell.replyId
                        readonly property string quoteName: shell.quoteName
                        readonly property string quoteText: shell.quoteText
                        readonly property string picKind: shell.picKind
                        readonly property int picW: shell.picW
                        readonly property int picH: shell.picH
                        readonly property string mini: shell.mini
                        readonly property string pic: shell.pic
                        readonly property int dur: shell.dur
                        readonly property int edge: shell.edge
                        readonly property string rowKind: shell.rowKind
                        readonly property string fileName: shell.fileName
                        readonly property real fileSize: shell.fileSize
                        readonly property string wave: shell.wave
                        readonly property string title: shell.title
                        readonly property string sub: shell.sub
                        readonly property bool anim: shell.anim
                        readonly property string emo: shell.emo
                        readonly property int fitz: shell.fitz
                        readonly property bool auto: shell.auto
                        readonly property real got: shell.got
                        readonly property string path: shell.path
                        readonly property int jumbo: shell.jumbo
                        readonly property string fwd: shell.fwd
                        readonly property string reacts: shell.reacts
                        readonly property bool isPinned: shell.isPinned
                        readonly property int comments: shell.comments
                        readonly property int replies: shell.replies
                        readonly property string said: shell.said
                        readonly property string album: shell.album
                        readonly property bool veiled: shell.veiled
                        readonly property string poll: shell.poll
                        readonly property bool heard: shell.heard
                        readonly property var group: shell.group
                        readonly property bool grouped: shell.grouped
                        readonly property bool tucked: shell.tucked
                        readonly property bool mosaic: grouped && group.main === msgId && rowKind === ""
                        readonly property bool stacked: grouped && group.main === msgId && rowKind !== ""     // files or songs
                        readonly property var tiles: mosaic ? page.tilesOf(group, wide) : null
                        readonly property var ids: grouped ? group.ids : [msgId]
                        function tileOf(id) {       // an album's picture, or its file
                            return picLoad.item ? picLoad.item.tileOf(id) : stack.item ? stack.item.memberOf(id) : null
                        }
                        function oneAt(x, y) {      // the album's picture or file at (x, y) on the row: its message (0: none)
                            if (mosaic && picLoad.item) {
                                const at = item.mapToItem(picture, x, y)
                                const t = picLoad.item.tileAt(at.x, at.y)
                                return t ? t.msgId : 0
                            }
                            if (stacked && stack.item) {
                                const at = item.mapToItem(attach, x, y)
                                const f = stack.item.memberAt(at.x, at.y)
                                return f ? f.msgId : 0
                            }
                            return 0
                        }
                        function replay(gently) {   // an animated emoji: played again (tapped; gently: if it has stopped)
                            if (picLoad.item)
                                picLoad.item.replay(gently)
                        }
                        readonly property bool bursting: bursts.count > 0      // its effects (a tap on the emoji): below
                        function burst(path) {
                            if (Prefs.fx && bursts.count < 4)      // (not with the Quvvat tejash page's effects off)
                                bursts.append({ file: path, key: ++page.burstSeq,
                                                dx: Math.random() * 60 - 30, dy: Math.random() * 60 - 30 })
                        }
                        function burstGone(key) {
                            for (let k = 0; k < bursts.count; k++)
                                if (bursts.get(k).key === key) {
                                    bursts.remove(k)
                                    return
                                }
                        }
                        function blow(x, y) {       // its spoiler off, from (x, y) on the picture (its middle when not given)
                            if (picLoad.item)
                                picLoad.item.blow(x === undefined ? picture.width / 2 : x, y === undefined ? picture.height / 2 : y)
                        }
                        readonly property int talk: mosaic || stacked ? group.talk : comments          // the comments, an album's on one of them
                        readonly property var talkId: mosaic || stacked ? group.talkId : msgId
                        // the last line of what is last in the bubble: the time goes by it when it fits
                        readonly property real lastLine: stacked ? (stack.item ? stack.item.last : 0) : body.last
                        readonly property Item face: bubble
                        readonly property Item picFace: picture
                        // a picture: photo, video or GIF in the bubble; sticker and round video without one
                        readonly property bool media: picKind !== ""
                        readonly property bool bare: picKind === "sticker" || picKind === "round" || jumbo > 0
                        // nearly on the screen: a GIF's player is made ready; on it: only then it plays (one
                        // playing just off the screen kept the whole window redrawn at the video's 30 fps)
                        // (the shell's y: this item stands at 0 in it)
                        readonly property bool inSight: shell.y + height > list.seen - 300 && shell.y < list.seen + list.height + 300
                        readonly property bool onScreen: shell.y + height > list.seen - 100 && shell.y < list.seen + list.height + 100
                        readonly property real aspect: picH / picW
                        // a sticker's side (Telegram-iOS's 180 on its wider screen); an emoji alone's that times the
                        // server's emojies_animated_zoom (iOS: animatedEmojiScale)
                        readonly property real side: emo !== "" ? Math.round(160 * page.store.emojiZoom) : 160
                        // a round video playing: from 200 to the width but 10 on each side (404 at most), its avatar
                        // gone (Telegram-iOS's ChatMessageInstantVideoItemNode: maximumDisplaySize, avatarOffset)
                        readonly property bool roundBig: picKind === "round" && page.roundId === msgId
                        property real roundK: roundBig ? 1 : 0
                        Behavior on roundK { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        readonly property real roundSide: 200 + (Math.min(404, width - 20) - 200) * roundK
                        // its middle on the screen, between the header and the field: else it goes on in the corner (PiP)
                        readonly property bool roundShown: roundBig && (shell.y + bubble.y + bubble.height / 2 - list.contentY - page.kb > bar.height + pinBar.height
                                                                        && shell.y + bubble.y + bubble.height / 2 - list.contentY - page.kb < page.height - page.kb - page.foot)
                        onRoundShownChanged: if (roundBig) page.roundSeen = roundShown
                        onRoundBigChanged: if (roundBig) page.roundSeen = roundShown
                        Component.onDestruction: if (page && page.roundId === msgId) page.roundSeen = false
                        readonly property real pw: mosaic ? tiles.width : picKind === "round" ? roundSide : picKind === "sticker" ? side * Math.min(1, 1 / aspect)
                                                 : aspect * wide > 360 ? Math.max(150, 360 / aspect) : wide
                        readonly property real ph: mosaic ? tiles.height : picKind === "round" ? roundSide : picKind === "sticker" ? side * Math.min(1, aspect)
                                                 : Math.max(110, Math.min(360, aspect * wide))
                        readonly property real wide: Math.min(width * 0.72, 270) - moved
                        readonly property bool overlaid: media && text === "" && !reacted     // the time over the picture
                        // an album's reactions are its first message's, as Telegram-iOS shows them and puts them on (topMessage)
                        readonly property var reactId: grouped ? group.ids[0] : msgId
                        readonly property string reactsShown: reactId === msgId ? reacts : (page.albumTick, page.reactsOf(reactId))
                        readonly property var reactList: reactsShown ? JSON.parse(reactsShown) : []
                        readonly property bool reacted: reactList.length > 0
                        // a run: one sender's messages within 10 minutes of each other. Its first (the
                        // top) has the name and more space over it, its last (the bottom) the tail.
                        readonly property bool first: edge, grouped ? page.apart(page.beyond(index, 1, album), senderKey, date)
                                                             : page.apart(messages.get(index + 1), senderKey, date)
                        readonly property bool last: grouped ? page.apart(page.beyond(index, -1, album), senderKey, date)
                                                     : page.apart(messages.get(index - 1), senderKey, date)
                        readonly property real most: width * 0.78 - moved
                        // a group's incoming messages leave room on the left for their sender's picture,
                        // which stands by the last of a run (Telegram-iOS)
                        readonly property bool faced: sender !== "" && !said       // (sender: only a group's incoming)
                        // the first message of a day has the day over it
                        readonly property bool newDay: edge, grouped ? page.otherDay(page.beyond(index, 1, album), date)
                                                              : page.otherDay(messages.get(index + 1), date)
                        readonly property bool unreadBar: msgId === page.firstUnread || (grouped && ids.indexOf(page.firstUnread) >= 0)
                        // «Tanlash»: a circle on its left, the incoming ones moved over for it (iOS)
                        readonly property bool pickable: page.selecting && !said && !sending
                        readonly property bool isPicked: ids.every((id) => page.picked[id] !== undefined)
                        readonly property real moved: pickable && !out ? 40 : 0       // (and narrower by as much)
                        readonly property real above: (newDay ? 38 : 0) + (unreadBar ? 36 : 0) + (first ? 8 : 2)
                        width: shell.width
                        height: (said ? pill.height + 4 : bubble.height) + above

                        // what only some rows show is made only for them (a row's every Text costs it to make,
                        // shown or not, and a first flick makes a row a frame or two)
                        Loader {
                            id: dayPill
                            active: item.newDay
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            readonly property Item msg: item
                            sourceComponent: Rectangle {
                                readonly property Item item: dayPill.msg
                                width: dayText.implicitWidth + 16; height: 22; radius: 11
                                color: Theme.dayPill
                                Text {
                                    id: dayText
                                    anchors.centerIn: parent
                                    text: page.dayName(item.date)
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                            }
                        }
                        Rectangle {          // the message found, lit up a moment (as Telegram-iOS does)
                            y: item.above - 2
                            width: parent.width; height: parent.height - y + 2
                            color: Theme.accent
                            opacity: item.ids.indexOf(page.flashId) >= 0 ? 0.18 : 0
                            Behavior on opacity { NumberAnimation { duration: 500 } }
                        }
                        Loader {             // Telegram-iOS's unread bar, over the first unread message
                            active: item.unreadBar
                            y: (item.newDay ? 38 : 0) + 6
                            width: parent.width; height: 28
                            sourceComponent: Rectangle {
                                color: Theme.bar
                                Text {
                                    anchors.centerIn: parent
                                    text: Tr.t("O'qilmagan xabarlar")
                                    color: Theme.grey
                                    font.family: Theme.font; font.pixelSize: 13
                                }
                            }
                        }

                        Loader {             // a service message (who did what): no bubble, a pill in the middle
                            id: pill
                            active: item.said !== ""
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: item.above + 2
                            readonly property Item msg: item
                            sourceComponent: Rectangle {
                                readonly property Item item: pill.msg
                                width: Math.min(saidText.implicitWidth, item.width - 80) + 20
                                height: saidText.height + 8; radius: Math.min(11, height / 2)
                                color: Theme.dayPill
                                Text {
                                    id: saidText
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, item.width - 80)
                                    text: item.said
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                            }
                        }

                        // a message just sent flies here from where its text was in the field: it starts
                        // there (moved by mover's x, y) and comes to rest on Telegram-iOS's two curves
                        // (ChatMessageTransitionNode.swift), on the render thread
                        Item {
                            id: mover
                            visible: !item.said
                            width: item.width; height: item.height
                            transform: Translate {
                                x: item.moved
                                Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring } }
                            }
                            // a tap on an emoji alone: its effect (Telegram-iOS's playEffectAnimation) three times its size,
                            // its middle moved in toward the chat by the emoji's width less 10, a little off at random each
                            // time, turned round for one that came in; once, over the rows about it, four at most at a time
                            ListModel { id: bursts }
                            Repeater {
                                model: bursts
                                Lottie {
                                    required property string file
                                    required property int key
                                    required property real dx
                                    required property real dy
                                    readonly property real w: picture.width
                                    readonly property real h: picture.height
                                    z: 10
                                    width: 3 * w; height: 3 * h
                                    x: bubble.x + picture.x - w + (item.out ? 10 - w : w - 10) + dx
                                    y: bubble.y + picture.y - h + dy
                                    path: file
                                    once: true
                                    most: 512
                                    running: page.visible
                                    transform: Scale { origin.x: 1.5 * w; xScale: item.out ? 1 : -1 }
                                    onEnded: item.burstGone(key)
                                    onFailedChanged: if (failed) item.burstGone(key)
                                }
                            }
                            Loader {
                                id: faceAt
                                active: item.faced && item.last
                                opacity: 1 - item.roundK
                                x: 8 - 100 * item.roundK; y: bubble.y + bubble.height - 34
                                width: 34; height: 34
                                // (handed through: inside sourceComponent `item` is the Loader's)
                                readonly property string name: item.sender
                                readonly property string key: item.senderKey
                                readonly property string tint: item.tint
                                sourceComponent: Avatar {
                                    id: face
                                    letters: store.letters(faceAt.name)
                                    tint: faceAt.tint
                                    Component.onCompleted: {
                                        const s = JSON.parse(faceAt.key)
                                        const u = s.user_id && store.users[s.user_id]
                                        if (u && u.type && u.type["@type"] === "userTypeDeleted")
                                            face.ghost = true
                                        else if (s.user_id)
                                            store.userPhoto(store.users[s.user_id], (path) => face.source = path)
                                        else if (store.chats[s.chat_id]) {
                                            store.watchPhoto(store.chats[s.chat_id])
                                            face.source = store.photoPath(store.chats[s.chat_id])
                                        }
                                    }
                                }
                            }
                            Item {
                                id: bubble
                                y: item.above
                                x: item.out ? item.width - width - 14 + 4 * item.roundK : (14 + (item.faced ? 40 : 0)) * (1 - item.roundK) + 10 * item.roundK
                                // the time goes in the last line's corner when it fits there, else under it
                                readonly property real stampRoom: stamp.implicitWidth + 8
                                readonly property real tail: item.talk >= 0 && !item.bare ? 42 : 0     // the comments row

                                readonly property bool stampUnder: !item.overlaid && item.lastLine + stampRoom > (item.media ? width : item.most) - 24
                                width: item.jumbo ? Math.max(body.implicitWidth, stamp.implicitWidth + 12) + 8
                                     : item.bare ? item.pw : item.media ? item.pw + 6
                                     : Math.min(item.most, Math.max(body.implicitWidth, who.implicitWidth + (rankText.visible ? rankText.implicitWidth + 11 : 0), quote.visible ? quote.wants : 0,
                                                                    attach.visible ? attach.width : 0, fwdText.visible ? fwdText.implicitWidth : 0,
                                                                    item.reacted ? reactRow.wants + stamp.implicitWidth + 6 : 0,
                                                                    stampUnder ? stamp.implicitWidth : item.lastLine + stampRoom, tail ? 196 : 0) + 24)
                                height: tail + (item.jumbo ? body.y + body.height + 26
                                      : item.overlaid ? picture.y + item.ph + (item.bare ? 0 : 3)
                                      : item.reacted ? reactRow.y + reactRow.height + 6
                                      : body.y + body.height + (stampUnder ? 24 : 8))

                                Rectangle {     // while the stretched picture loads
                                    anchors.fill: parent
                                    visible: !item.bare && shape.status !== Image.Ready
                                    radius: Prefs.bubbleR
                                    color: item.out ? Theme.bubbleOut : Theme.bubbleIn
                                }
                                BorderImage {   // the bubble, stretched from a small picture (nullgram.py Bubble), drawn
                                    id: shape       // in device pixels and scaled down: then its borders come out right
                                    readonly property real d: Screen.devicePixelRatio
                                    x: item.out ? 0 : -6
                                    width: (parent.width + 6) * d; height: parent.height * d
                                    scale: 1 / d; transformOrigin: Item.TopLeft
                                    readonly property int r: Prefs.bubbleR
                                    readonly property int b: Prefs.bubbleB
                                    border { left: (item.out ? r : b + 6) * d; right: (item.out ? b + 6 : r) * d; top: r * d; bottom: b * d }
                                    source: "image://bubble/" + (item.out ? "out/" : "in/") + (item.first ? "b/" : "s/") + (item.last ? "t/" : "s/")
                                            + String(item.out ? Theme.bubbleOut : Theme.bubbleIn).slice(1) + "/" + Screen.devicePixelRatio
                                            + "/" + r + "/" + Prefs.bubbleS
                                    smooth: true
                                    visible: !item.bare
                                }

                                // a long press lifts it into the menu; while pressed it sinks a little (iOS)
                                MouseArea {
                                    id: hold
                                    anchors.fill: parent
                                    pressAndHoldInterval: 350
                                    // held: the menu is coming or open and this finger still down -- the list keeps
                                    // still (page.holding; preventStealing instead left an action lit, pressed, as the
                                    // menu came), and where it goes and is lifted is the menu's (MessageMenu.track)
                                    // Only once it has moved: the actions may come up right under a finger that stays.
                                    property bool held: false
                                    property bool slid: false
                                    property point heldAt
                                    onHeldChanged: page.holding = held
                                    Component.onDestruction: if (held) page.holding = false
                                    onPressed: { held = false; rise.stop(); sink.restart() }
                                    onReleased: (mouse) => {
                                        sink.stop(); rise.restart()
                                        if (held && slid) {
                                            const at = hold.mapToItem(menu, mouse.x, mouse.y)
                                            menu.lift(at.x, at.y)
                                        }
                                        held = false
                                    }
                                    onCanceled: { held = false; sink.stop(); rise.restart() }
                                    onPositionChanged: (mouse) => {
                                        if (!held)
                                            return
                                        slid = slid || Math.hypot(mouse.x - heldAt.x, mouse.y - heldAt.y) > 10
                                        if (slid) {
                                            const at = hold.mapToItem(menu, mouse.x, mouse.y)
                                            menu.track(at.x, at.y)
                                        }
                                    }
                                    onPressAndHold: (mouse) => {
                                        held = true
                                        slid = false
                                        heldAt = Qt.point(mouse.x, mouse.y)
                                        const at = hold.mapToItem(item, mouse.x, mouse.y)
                                        page.openMenu(item, item.oneAt(at.x, at.y))
                                    }
                                    onClicked: (mouse) => {
                                        if (item.mosaic) {          // the album's picture under the finger
                                            const at = hold.mapToItem(picture, mouse.x, mouse.y)
                                            const t = picLoad.item ? picLoad.item.tileAt(at.x, at.y) : null
                                            if (t)
                                                page.tapMedia(t, at.x - t.x, at.y - t.y)
                                        } else if (item.stacked) {  // the album's file under the finger
                                            const at = hold.mapToItem(attach, mouse.x, mouse.y)
                                            const f = stack.item ? stack.item.memberAt(at.x, at.y) : null
                                            if (f)
                                                page.tapMedia(f)
                                        } else if (item.media || item.rowKind) {
                                            const at = hold.mapToItem(picture, mouse.x, mouse.y)
                                            page.tapMedia(item, at.x, at.y)
                                        }
                                    }
                                }
                                ScaleAnimator { id: sink; target: bubble; to: 0.96; duration: 350; easing.type: Easing.OutQuad }
                                ScaleAnimator { id: rise; target: bubble; to: 1; duration: 150; easing.type: Easing.OutQuad }

                                // how wide the name and the forward line may be: a picture's bubble is as wide as
                                // the picture, they are cut to it (Telegram-iOS: maximumNodeWidth, the media's);
                                // a text's grows to them up to `most` (not bubble.width: that is made of them)
                                readonly property real headRoom: (item.media ? item.pw + 6 : item.most) - 24
                                Text {          // (not over a sticker, a round video or big emoji: Telegram-iOS's
                                    id: who     // ChatMessageAnimatedStickerItemNode has no name, the face says who)
                                    visible: item.sender !== "" && item.first && !item.bare
                                    x: 12; y: 7
                                    width: Math.min(implicitWidth, bubble.headRoom - (rankText.visible ? rankText.implicitWidth + 11 : 0))
                                    elide: Text.ElideRight
                                    text: item.sender
                                    color: item.tint
                                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                }
                                Rectangle {     // the rank's capsule: an admin's and the owner's only (faint, of its colour)
                                    visible: rankText.visible && item.rankKind > 0
                                    x: rankText.x - 5; y: rankText.y + rankText.height / 2 - 8.5
                                    width: rankText.width + 10; height: 17; radius: 8.5
                                    color: rankText.color
                                    opacity: 0.1
                                }
                                Text {          // on the right, as far as the bubble goes
                                    id: rankText
                                    visible: who.visible && item.rank !== ""
                                    x: bubble.width - 12 - width; y: who.y + 1
                                    width: Math.min(implicitWidth, bubble.headRoom / 2)
                                    elide: Text.ElideRight
                                    text: item.rank
                                    color: item.rankKind === 2 ? "#956ac8" : item.rankKind === 1 ? "#49a355" : (item.out ? Theme.outMeta : Theme.inMeta)
                                    font.family: Theme.font; font.pixelSize: 13
                                }
                                Loader {        // forwarded: from whom (Telegram-iOS: two lines in the accent colour)
                                    id: fwdText     // (its implicitWidth: the lines' width, at most headRoom)
                                    active: item.fwd !== "" && !item.bare
                                    visible: active
                                    x: 12; y: who.visible ? who.y + who.height + 1 : 7
                                    readonly property Item msg: item
                                    readonly property real room: bubble.headRoom
                                    // two Texts: one Text of two lines ("…\n…") was not cut by its elide at all,
                                    // a long channel's name ran out of the bubble
                                    sourceComponent: Column {
                                        readonly property Item item: fwdText.msg
                                        Repeater {
                                            model: [Tr.t("Uzatilgan xabar"), item.fwd]
                                            Text {
                                                required property string modelData
                                                width: Math.min(implicitWidth, fwdText.room)
                                                elide: Text.ElideRight
                                                text: modelData
                                                color: item.out ? Theme.check : Theme.accent
                                                lineHeight: 0.95
                                                font.family: Theme.font; font.pixelSize: 14
                                            }
                                        }
                                    }
                                }
                                // the lowest of the name and the forward line: what comes next goes under it
                                readonly property Item head: fwdText.visible ? fwdText : who
                                Loader {        // what it answers: a bar, the name, a line of the text; a tap goes there
                                    id: quote       // (made only for a reply; inside, `item` is the message again: answer's own)
                                    active: item.replyId !== 0
                                    visible: active
                                    readonly property real wants: quote.item ? quote.item.wants : 0
                                    // a sticker's, an animated emoji's, a round video's or big emoji's (no bubble): at the
                                    // screen's other edge, level with its top, on the time's dark pill -- Telegram-iOS's
                                    // ChatMessageAnimatedStickerItemNode (14 pt in from the left of ours, from the right of
                                    // theirs; 200 pt at most), not over the picture
                                    readonly property real side: item.out ? bubble.x - 22 : item.width - bubble.x - bubble.width - 22
                                    x: item.bare ? (item.out ? 14 - bubble.x : item.width - 14 - width - bubble.x) : 8
                                    y: item.bare ? 8 : bubble.head.visible ? bubble.head.y + bubble.head.height + 4 : 8
                                    width: item.bare ? Math.max(60, Math.min(wants, 200, side)) : bubble.width - 16
                                    height: visible ? 40 : 0
                                    readonly property Item msg: item
                                    sourceComponent: Rectangle {
                                        id: answer
                                        readonly property Item item: quote.msg
                                        readonly property color ink: item.bare ? "white" : item.out ? Theme.check : Theme.accent
                                        readonly property real wants: Math.max(quoteWho.implicitWidth, Math.min(quoteWhat.implicitWidth, 220)) + 22
                                        radius: 6
                                        // (by a sticker: on the wallpaper, as the time by it)
                                        color: item.bare ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(ink.r, ink.g, ink.b, 0.12)
                                        clip: true
                                        Rectangle { width: 3; height: parent.height; color: answer.ink }
                                        Text {
                                            id: quoteWho
                                            x: 11; y: 3
                                            width: parent.width - 16
                                            elide: Text.ElideRight
                                            text: item.quoteName
                                            color: answer.ink
                                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                        }
                                        Text {
                                            id: quoteWhat
                                            x: 11; y: 20
                                            width: parent.width - 16
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            // (its emoji as pictures, the text's size: the font's came out small and low)
                                            textFormat: Text.StyledText
                                            text: Emo.emojify(page.store.escaped(item.quoteText.replace(/\s+/g, " ")), 16)
                                            color: item.bare ? "white" : item.out ? Theme.outText : Theme.inText
                                            font.family: Theme.font; font.pixelSize: 14
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: page.jump(item.replyId) }
                                    }
                                }
                                Item {          // the picture: Telegram's blurred preview at once, the picture over it when here
                                    id: picture
                                    visible: item.media
                                    x: item.bare ? 0 : 3
                                    y: item.bare ? 0 : quote.visible ? quote.y + quote.height + 4 : bubble.head.visible ? bubble.head.y + bubble.head.height + 4 : 3
                                    width: item.pw; height: visible ? item.ph : 0
                                    readonly property string corner: item.picKind === "round" ? "-1" : item.bare ? "0" : String(Math.max(1, Prefs.bubbleR - 3))
                                    // what is in it made only for a message with a picture (a text's row made all of it,
                                    // two dozen hidden things). Inside, `item` is the message again (block's): the
                                    // Loader is the context object there, its own `item` would come first
                                    Loader {
                                        id: picLoad
                                        anchors.fill: parent
                                        active: item.media && !item.tucked      // (an album's others: shown by its main)
                                        // made a piece at a time over the next frames, not with the row: a row coming
                                        // into sight in a flick is made there and then, in the frame, and an album's
                                        // (its tiles, their pictures and veils) was half of its 40-60 ms. Its size is
                                        // the row's (pw, ph), known at once: nothing moves when it comes.
                                        asynchronous: true
                                        readonly property Item msg: item
                                        sourceComponent: Item {
                                            id: block
                                            readonly property Item item: picLoad.msg
                                            function tileOf(id) {
                                                for (let k = 0; k < tileRep.count; k++)
                                                    if (tileRep.itemAt(k) && tileRep.itemAt(k).msgId === id)
                                                        return tileRep.itemAt(k)
                                                return null
                                            }
                                            function tileAt(x, y) {         // the album's picture there
                                                const t = tilesView.childAt(x, y)
                                                return t && t.msgId ? t : null
                                            }
                                            function replay(gently) {
                                                if (moving.item && moving.lottie)
                                                    moving.item.replay(gently)
                                            }
                                            function blow(x, y) {
                                                if (veil.item)
                                                    veil.item.blow(x, y)
                                            }
                                            Item {      // an album's: each its own picture
                                                id: tilesView
                                                visible: item.mosaic
                                                anchors.fill: parent
                                                Repeater {
                                                    id: tileRep
                                                    model: item.mosaic ? item.tiles.items : []
                                                    AlbumTile {
                                                        required property var modelData
                                                        x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                                                        msgId: modelData.id
                                                        corner: modelData.corner
                                                        cell: page.albumTick, page.albumRev, page.cellOf(modelData.id)
                                                        live: item.onScreen
                                                        onUnveiled: page.unveil(msgId)
                                                        marks: page.picking
                                                        picking: item.pickable
                                                        picked: page.picked[modelData.id] !== undefined
                                                        Component.onCompleted: if (!pic) page.loadPic(msgId)
                                                    }
                                                }
                                            }
                                            Image {
                                                anchors.fill: parent
                                                visible: item.mini !== "" && full.status !== Image.Ready && !item.mosaic
                                                asynchronous: true
                                                // (in points: Qt asks the provider for these times the pixel ratio)
                                                sourceSize: Qt.size(12, 12 * item.ph / item.pw)     // blurred: small is enough
                                                source: item.mini ? "image://pic/" + picture.corner + "/" + Math.round(item.pw) + "/mini/" + item.mini : ""
                                                smooth: true
                                            }
                                            Image {
                                                id: full
                                                anchors.fill: parent
                                                asynchronous: true
                                                sourceSize: Qt.size(Math.round(item.pw), Math.round(item.ph))
                                                source: item.pic && !item.mosaic ? "image://pic/" + picture.corner + "/" + Math.round(item.pw) + "/" + item.pic : ""
                                                opacity: status === Image.Ready && !moving.covers ? 1 : 0
                                                Behavior on opacity { OpacityAnimator { duration: 150 } }
                                            }
                                            Loader {        // a GIF (or a video sticker) over and over; a round video tapped, once with sound
                                                id: moving
                                                anchors.fill: parent
                                                readonly property bool round: block.item.picKind === "round"
                                                readonly property var msgId: block.item.msgId
                                                active: block.item.path !== "" && page.visible && block.item.inSight && !block.item.mosaic && !block.item.veiled &&
                                                        ((block.item.picKind === "gif" && Prefs.gifs) || (round && page.roundId === block.item.msgId) ||
                                                         (block.item.anim && (block.item.emo !== "" ? Prefs.emoji : Prefs.stickers)))
                                                // (handed through here: inside sourceComponent `item` is not the delegate)
                                                readonly property string file: block.item.path
                                                // paused, not taken apart, under the gallery: made anew all at once as it
                                                // closed they held up the frames of its flight back
                                                readonly property bool playing: !viewer.open && (round || block.item.onScreen)
                                                // a TGS sticker (TDLib keeps it as .tgs): its frames drawn here, not a video
                                                readonly property bool lottie: /\.tgs$/i.test(file)
                                                readonly property bool emo: block.item.emo !== ""
                                                // (its still under it goes once a frame is up: the frames are see-through)
                                                readonly property bool covers: lottie && !!item && item.shown === true
                                                sourceComponent: lottie ? lottiePlayer : videoPlayer
                                                Component {
                                                    id: videoPlayer
                                                    InlineVideo {
                                                        id: clip
                                                        path: moving.file
                                                        running: moving.round ? block.item.roundShown && !page.player.roundPaused : moving.playing
                                                        resumeFrom: moving.round ? (() => page.player.roundPos) : null
                                                        radius: Number(picture.corner)
                                                        sound: moving.round
                                                        loop: !moving.round
                                                        rate: moving.round ? page.player.rate : 1
                                                        onEnded: if (moving.round && page.roundId === moving.msgId) page.player.step(false)
                                                        // (how far it is: the mini player's line, the ring, the time)
                                                        Binding { when: moving.round && clip.running; target: page.player; property: "roundPos"; value: clip.position }
                                                        Binding { when: moving.round && clip.duration > 0; target: page.player; property: "roundDur"; value: clip.duration }
                                                    }
                                                }
                                                Component {
                                                    id: lottiePlayer
                                                    Lottie {
                                                        path: moving.file
                                                        running: moving.playing
                                                        once: moving.emo
                                                        fitz: block.item.fitz
                                                        // (played once already in this chat: on its last frame, as on iOS)
                                                        atEnd: moving.emo && !!page.seenEmo[block.item.msgId]
                                                        onEnded: page.seenEmo[block.item.msgId] = true
                                                    }
                                                }
                                            }
                                            Loader {        // a round video playing: how far, an arc round its edge (Telegram-iOS's
                                                id: roundRing   // InstantVideoRadialStatusNode: white 0.6, 4 wide, round ends, from the top,
                                                anchors.fill: parent    // its circle 1.5 + 2 + 4 in; seen 0.15 s after it starts, faded in 0.2 s)
                                                active: block.item.roundBig
                                                readonly property Item msg: block.item
                                                sourceComponent: Shape {
                                                    preferredRendererType: Shape.CurveRenderer
                                                    opacity: 0
                                                    SequentialAnimation on opacity {
                                                        PauseAnimation { duration: 150 }
                                                        NumberAnimation { to: 1; duration: 200 }
                                                    }
                                                    ShapePath {
                                                        fillColor: "transparent"
                                                        strokeColor: Qt.rgba(1, 1, 1, 0.6)
                                                        strokeWidth: 4
                                                        capStyle: ShapePath.RoundCap
                                                        PathAngleArc {
                                                            centerX: roundRing.width / 2; centerY: roundRing.height / 2
                                                            radiusX: (roundRing.width - 15) / 2; radiusY: radiusX
                                                            startAngle: -90
                                                            sweepAngle: page.player.duration > 0 ? 360 * Math.min(1, page.player.position / page.player.duration) : 0
                                                        }
                                                    }
                                                }
                                            }
                                            Loader {        // a spoiler: blurred under its dust until tapped (the play button and
                                                id: veil        // the length stay over it, as Telegram-iOS has them)
                                                anchors.fill: parent
                                                active: block.item.veiled && !block.item.mosaic
                                                readonly property Item msg: block.item     // (inside sourceComponent `item` is the Loader's own)
                                                sourceComponent: Veil {
                                                    corner: picture.corner
                                                    mini: veil.msg.mini
                                                    pic: veil.msg.pic
                                                    live: veil.msg.onScreen
                                                    onGone: page.unveil(veil.msg.msgId)
                                                }
                                            }
                                            Rectangle {     // a video: play over it (the ring while it comes); a GIF: the ring
                                                visible: !item.mosaic && (item.got >= 0 || item.picKind === "video" || (item.picKind === "gif" && !item.path)
                                                                            || (item.picKind === "round" && (page.roundId !== item.msgId || page.player.roundPaused)))
                                                anchors.centerIn: parent
                                                width: 48; height: 48; radius: 24
                                                color: Qt.rgba(0, 0, 0, 0.45)
                                                Icon {
                                                    visible: item.got < 0
                                                    anchors.centerIn: parent
                                                    anchors.horizontalCenterOffset: name === "play" ? 1.5 : 0
                                                    width: 24; height: 24
                                                    name: item.path || item.picKind === "video" ? "play" : "down"
                                                    color: "white"
                                                }
                                                Ring {
                                                    visible: item.got >= 0
                                                    anchors.fill: parent
                                                    value: item.got
                                                }
                                            }
                                            Loader {    // a place: the pin at the map's middle (its point there); live: a dot, pulsing
                                                id: pin
                                                active: block.item.picKind === "map"
                                                anchors.fill: parent
                                                readonly property Item msg: block.item
                                                sourceComponent: Item {
                                                    readonly property Item item: pin.msg
                                                    readonly property bool live: item.dur > 0 && (item.dur === 0x7FFFFFFF || item.dur > page.now)
                                                    Icon {
                                                        visible: !parent.live
                                                        x: (parent.width - width) / 2; y: parent.height / 2 - height + 3
                                                        width: 40; height: 40
                                                        name: "place"
                                                        color: Theme.danger
                                                    }
                                                    Rectangle {
                                                        visible: parent.live
                                                        anchors.centerIn: parent
                                                        width: 44; height: 44; radius: 22
                                                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                                        SequentialAnimation on scale {
                                                            running: parent.visible && item.onScreen; loops: Animation.Infinite
                                                            ScaleAnimator { from: 0.6; to: 1.2; duration: 1000; easing.type: Easing.OutQuad }
                                                            ScaleAnimator { from: 1.2; to: 0.6; duration: 1000; easing.type: Easing.InQuad }
                                                        }
                                                    }
                                                    Rectangle {
                                                        visible: parent.live
                                                        anchors.centerIn: parent
                                                        width: 16; height: 16; radius: 8
                                                        color: Theme.accent
                                                        border.color: "white"; border.width: 2.5
                                                    }
                                                }
                                            }
                                            Loader {    // (made only for a video's, a GIF's: not for every photo's)
                                                id: lenTag
                                                // (`block.item`: on a Loader, `item` is its own)
                                                active: !block.item.mosaic && (block.item.picKind === "video" || block.item.picKind === "gif" || block.item.picKind === "round"
                                                                               || (block.item.picKind === "map" && block.item.dur > 0))
                                                // a round video's at its foot on the left; big: its middle − 81 (Telegram-iOS: − 56 − 25)
                                                x: 6 + (block.item.picKind === "round" ? block.item.roundK * (parent.width / 2 - 87) : 0)
                                                y: block.item.picKind === "round" ? parent.height - 26 : 6
                                                readonly property Item msg: block.item
                                                sourceComponent: Rectangle {
                                                    readonly property Item item: lenTag.msg
                                                    // a round video not yet watched: a dot after its length (Telegram-iOS)
                                                    readonly property bool fresh: item.picKind === "round" && !item.heard
                                                    width: len.implicitWidth + 12 + (fresh ? 9 : 0); height: 20; radius: 10
                                                    color: Qt.rgba(0, 0, 0, 0.45)
                                                    Rectangle {
                                                        visible: parent.fresh
                                                        x: len.x + len.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter
                                                        width: 5; height: 5; radius: 2.5
                                                        color: "white"
                                                    }
                                                    Text {
                                                        id: len
                                                        x: 6; anchors.verticalCenter: parent.verticalCenter
                                                        text: item.picKind === "map" ? page.liveLeft(item.dur)
                                                            : item.picKind === "gif" ? "GIF" : page.clock(item.roundBig ? Math.floor(page.player.position / 1000) : item.dur)
                                                              + (item.picKind === "video" && !item.path && item.fileSize ? " · " + store.size(item.fileSize) : "")
                                                        color: "white"
                                                        font.family: Theme.font; font.pixelSize: 12
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Item {          // a voice note, a song or a file
                                    id: attach
                                    visible: item.rowKind !== ""
                                    x: 12
                                    y: quote.visible ? quote.y + quote.height + 6 : bubble.head.visible ? bubble.head.y + bubble.head.height + 4 : 6
                                    width: item.stacked ? (stack.item ? stack.item.width : 0)
                                         : item.rowKind === "file" ? (fileRow.item ? fileRow.item.width : 0)
                                         : item.rowKind === "poll" ? Math.min(item.most - 24, 300) : 230
                                    height: !visible ? 0 : item.stacked ? (stack.item ? stack.item.height : 0)
                                          : item.rowKind === "poll" ? (pollRow.item ? pollRow.item.height : 0) : 50
                                    // made only for such a message (each row made both: a voice note's 43 bars
                                    // for every message made while scrolling). The message handed through
                                    // `msg`: inside sourceComponent `item` is the Loader's own (null, then the row)
                                    Loader {
                                        id: audioRow
                                        active: !item.stacked && !item.tucked && (item.rowKind === "voice" || item.rowKind === "audio")
                                        readonly property Item msg: item
                                        sourceComponent: AudioRow {
                                            kind: audioRow.msg.rowKind === "audio" ? "audio" : "voice"
                                            out: audioRow.msg.out
                                            wave: audioRow.msg.wave
                                            dur: audioRow.msg.dur
                                            title: audioRow.msg.title
                                            sub: audioRow.msg.sub
                                            got: audioRow.msg.got
                                            here: audioRow.msg.path !== ""
                                            current: page.soundId === audioRow.msg.msgId
                                            playing: current && page.player.playing
                                            at: current ? page.player.position : 0
                                            fresh: !audioRow.msg.heard
                                        }
                                    }
                                    Loader {
                                        id: pollRow
                                        active: !item.tucked && item.rowKind === "poll" && item.poll !== ""
                                        readonly property Item msg: item
                                        sourceComponent: PollView {
                                            width: attach.width
                                            out: pollRow.msg.out
                                            poll: JSON.parse(pollRow.msg.poll)
                                            onVote: (ids) => page.vote(pollRow.msg.msgId, ids)
                                            onVoters: page.showVoters(pollRow.msg.msgId, poll)
                                            onExplain: (t) => page.toast(t)
                                            onHeld: page.openMenu(pollRow.msg)
                                        }
                                    }
                                    Loader {
                                        id: fileRow
                                        active: !item.stacked && !item.tucked && item.rowKind === "file"
                                        readonly property Item msg: item
                                        sourceComponent: FileRow {
                                            out: fileRow.msg.out
                                            name: fileRow.msg.fileName
                                            size: fileRow.msg.fileSize
                                            got: fileRow.msg.got
                                            here: fileRow.msg.path !== ""
                                            thumb: fileRow.msg.pic
                                        }
                                    }
                                    Loader {        // files or songs sent together: each under the one before, its
                                        id: stack   // caption under it, as Telegram-iOS stacks them in one bubble
                                        active: item.stacked
                                        readonly property Item msg: item
                                        sourceComponent: Column {
                                            id: files
                                            readonly property Item item: stack.msg
                                            spacing: 6
                                            // the last caption's last line (0: the last has none): the time goes by it
                                            readonly property real last: {
                                                const f = members.count ? members.itemAt(members.count - 1) : null
                                                return f ? f.lastLine : 0
                                            }
                                            function memberOf(id) {
                                                for (let k = 0; k < members.count; k++)
                                                    if (members.itemAt(k) && members.itemAt(k).msgId === id)
                                                        return members.itemAt(k)
                                                return null
                                            }
                                            function memberAt(x, y) {
                                                const f = childAt(x, y)
                                                return f && f.msgId ? f : null
                                            }
                                            Repeater {
                                                id: members
                                                model: item.group ? item.group.ids : []     // (oldest first: the top)
                                                Item {
                                                    id: member
                                                    required property var modelData
                                                    readonly property var msgId: modelData
                                                    readonly property var cell: (page.albumTick, page.albumRev, page.cellOf(modelData))
                                                    // what tapMedia and openMedia ask of a message's file
                                                    readonly property string rowKind: cell ? cell.rowKind : ""
                                                    readonly property string picKind: ""
                                                    readonly property bool media: false
                                                    readonly property bool veiled: false
                                                    readonly property real got: cell ? cell.got : -1
                                                    readonly property string path: cell ? cell.path : ""
                                                    readonly property bool sending: cell ? cell.sending : false
                                                    readonly property Item face: member
                                                    readonly property bool worded: !!cell && (cell.text !== "" || cell.rich !== "")
                                                    readonly property real lastLine: worded ? caption.last : 0
                                                    width: Math.max(rowKind === "file" ? (fileOne.item ? fileOne.item.width : 200) : 230,
                                                                    worded ? caption.width : 0)
                                                    height: 50 + (worded ? caption.height + 4 : 0)
                                                    Loader {
                                                        id: songOne
                                                        active: member.rowKind === "audio"
                                                        sourceComponent: AudioRow {
                                                            kind: "audio"
                                                            out: member.cell.out
                                                            dur: member.cell.dur
                                                            title: member.cell.title
                                                            sub: member.cell.sub
                                                            got: member.cell.got
                                                            here: member.cell.path !== ""
                                                            current: page.soundId === member.msgId
                                                            playing: current && page.player.playing
                                                            at: current ? page.player.position : 0
                                                        }
                                                    }
                                                    Loader {
                                                        id: fileOne
                                                        active: member.rowKind === "file"
                                                        sourceComponent: FileRow {
                                                            out: member.cell.out
                                                            name: member.cell.fileName
                                                            size: member.cell.fileSize
                                                            got: member.cell.got
                                                            here: member.cell.path !== ""
                                                            thumb: member.cell.pic
                                                        }
                                                    }
                                                    Loader {        // «Tanlash»'s mark over the icon's corner (iOS: 20 pt at 29, 26)
                                                        active: page.picking
                                                        x: 29; y: 26
                                                        sourceComponent: Check {
                                                            width: 20; height: 20
                                                            on: files.item.pickable
                                                            checked: page.picked[member.msgId] !== undefined
                                                            hollow: files.item.out ? Theme.bubbleOut : Theme.bubbleIn
                                                            ring: Theme.grey
                                                            ringChecked: files.item.out ? Theme.bubbleOut : Theme.bubbleIn
                                                        }
                                                    }
                                                    Words {
                                                        id: caption
                                                        visible: member.worded
                                                        y: 54
                                                        width: Math.min(implicitWidth, item.most - 24)
                                                        room: item.most - 24
                                                        size: Prefs.chatSize
                                                        live: item.onScreen
                                                        text: member.worded ? member.cell.text : ""
                                                        parts: member.worded ? member.cell.rich : ""
                                                        ink: item.out ? Theme.outText : Theme.inText
                                                        tint: item.out ? Theme.check : Theme.accent
                                                        open: !!page.unfolded[member.msgId]
                                                        onLink: (url) => page.follow(url, member.msgId)
                                                        onTouched: (down) => { if (down) { rise.stop(); sink.restart() } else { sink.stop(); rise.restart() } }
                                                        onHeld: page.openMenu(item, member.msgId)
                                                        onTapped: page.tapMedia(member)
                                                        onFold: page.unfold(member.msgId)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Words {
                                    id: body
                                    visible: !item.overlaid
                                    x: item.jumbo ? 4 : 12
                                    y: item.media ? picture.y + picture.height + 5 : attach.visible ? attach.y + attach.height + (text || parts ? 4 : 0)
                                     : quote.visible && !item.bare ? quote.y + quote.height + 4 : bubble.head.visible ? bubble.head.y + bubble.head.height + 2 : item.jumbo ? 0 : 8
                                    height: (attach.visible || item.media) && !text && !parts ? 0 : implicitHeight
                                    width: item.media ? bubble.width - 24 : attach.visible ? Math.max(attach.width, Math.min(implicitWidth, item.most - 24))
                                         : Math.min(implicitWidth, item.most - 24)
                                    live: item.onScreen
                                    room: item.media ? bubble.width - 24 : attach.visible ? Math.max(attach.width, item.most - 24) : item.most - 24
                                    text: item.stacked ? "" : (item.kind ? "[" + item.kind + "] " : "") + item.text     // (a stack has each caption under its file)
                                    parts: item.kind || item.stacked ? "" : item.rich
                                    ink: item.out ? Theme.outText : Theme.inText
                                    tint: item.out ? Theme.check : Theme.accent
                                    size: item.jumbo === 1 ? 94 : item.jumbo === 2 ? 79 : item.jumbo === 3 ? 65 : Prefs.chatSize    // (Telegram-iOS: 94 × 1, 0.84, 0.69; words: Matn o'lchami)
                                    open: !!page.unfolded[item.msgId]
                                    onLink: (url) => page.follow(url, item.msgId)
                                    onTouched: (down) => { if (down) { rise.stop(); sink.restart() } else { sink.stop(); rise.restart() } }
                                    onHeld: page.openMenu(item)
                                    onTapped: if (!item.mosaic && (item.media || item.rowKind)) page.tapMedia(item)
                                    onFold: page.unfold(item.msgId)
                                }
                                Loader {        // the reactions: emoji and how many, ours lit; a tap puts ours on or off.
                                    id: reactRow    // More than a line holds go on to the next, the time by the last (Telegram-iOS)
                                    active: item.reacted        // (made only when there are; its height is the Flow's)
                                    visible: active
                                    x: item.bare ? 0 : 10
                                    y: body.y + body.height + (body.height ? 6 : 4)
                                    readonly property real wants: item.reactList.reduce((w, r, k) =>
                                        w + page.chipWidth(r) + (k ? 4 : 0), 0)
                                    width: Math.min(wants + 1, bubble.width - x - 10)
                                    readonly property Item msg: item
                                    sourceComponent: Flow {
                                        readonly property Item item: reactRow.msg
                                        // the time by the last line, or under it when that line has no room
                                        property bool stampBelow: false
                                        onPositioningComplete: {
                                            const last = children.length > 1 ? children[children.length - 2] : null     // (the Repeater is last)
                                            stampBelow = !!last && last.x + last.width + stamp.implicitWidth + 12 > bubble.width - reactRow.x - 10
                                        }
                                        height: implicitHeight + (stampBelow ? 18 : 0)
                                        spacing: 4
                                        Repeater {
                                            model: item.reactList
                                            Rectangle {
                                                id: chip
                                                required property var modelData
                                                readonly property bool isPaid: !!modelData.paid
                                                readonly property var who: modelData.who || []
                                                width: page.chipWidth(modelData); height: 28; radius: 14
                                                readonly property color ink: item.bare ? "white" : item.out ? Theme.check : Theme.accent
                                                readonly property color goldInk: Theme.dark ? "#ffc337" : "#c87000"
                                                // paid star reaction chip: gold translucent (unchosen) or solid warm gold (chosen)
                                                // regular chip: accent translucent or solid; standalone over wallpaper on dayPill
                                                color: isPaid ? (modelData.mine ? "#f59300" : Qt.rgba(1, 0.72, 0.05, item.bare ? 0.45 : 0.22))
                                                     : modelData.mine ? ink : item.bare ? Theme.dayPill : Qt.rgba(ink.r, ink.g, ink.b, 0.15)
                                                border.width: isPaid && modelData.mine ? 1 : 0
                                                border.color: "#ffd43b"
                                                Icon {
                                                    id: starGlyph
                                                    visible: chip.isPaid
                                                    x: 8; anchors.verticalCenter: parent.verticalCenter
                                                    width: 16; height: 16
                                                    name: "star"
                                                    color: chip.modelData.mine ? "white" : "#ffb10a"
                                                }
                                                Text {
                                                    id: chipText
                                                    visible: !chip.isPaid
                                                    anchors.centerIn: chip.who.length ? undefined : parent
                                                    x: 8; anchors.verticalCenter: parent.verticalCenter
                                                    text: chip.who.length ? chip.modelData.e : chip.modelData.e + " " + chip.modelData.n
                                                    color: chip.modelData.mine ? (item.bare ? "#1c1c1e" : Theme.dark && item.out ? Theme.bubbleOut : "white") : chip.ink
                                                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                                }
                                                // top paid reactors (20 pt) OR regular reactors (24 pt)
                                                Repeater {
                                                    model: chip.who
                                                    Rectangle {
                                                        required property var modelData
                                                        required property int index
                                                        readonly property int sz: chip.isPaid ? 20 : 24
                                                        readonly property int step: chip.isPaid ? 10 : 12
                                                        x: (chip.isPaid ? starGlyph.x + starGlyph.width + 4 : chipText.x + chipText.implicitWidth + 4) + index * step - 1.5
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        z: chip.who.length - index      // (over the chip: below 0 it went under its colour)
                                                        width: sz + 3; height: sz + 3; radius: width / 2
                                                        // (the chip's colour over the bubble's, whole: a see-through ring would show the face under it)
                                                        color: chip.modelData.mine || item.bare ? chip.color
                                                             : Qt.tint(item.out ? Theme.bubbleOut : Theme.bubbleIn, chip.color)
                                                        Avatar {
                                                            id: reactor
                                                            anchors.centerIn: parent
                                                            width: parent.sz; height: parent.sz
                                                            Component.onCompleted: store.faceOn(reactor, parent.modelData)
                                                        }
                                                    }
                                                }
                                                Text {
                                                    visible: chip.isPaid
                                                    x: starGlyph.x + starGlyph.width + (chip.who.length ? 4 + 20 + (chip.who.length - 1) * 10 : 0) + 4
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: store.short(chip.modelData.n)
                                                    color: chip.modelData.mine ? "white" : chip.goldInk
                                                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                                }
                                            }
                                        }
                                    }
                                    MouseArea {     // one for all the chips: the one under the finger
                                        anchors.fill: parent
                                        onClicked: (mouse) => {
                                            const c = reactRow.item && reactRow.item.childAt(mouse.x, mouse.y)
                                            if (!c || !c.modelData)
                                                return
                                            if (c.modelData.paid)
                                                paidSheet.show(item.reactId, c.modelData.reactors || [], !!c.modelData.mine)
                                            else
                                                store.react(page.chatId, item.reactId, c.modelData.e, !c.modelData.mine)
                                        }
                                    }
                                }
                                Rectangle {     // under the time when it is over a picture, or on the wallpaper (a sticker's)
                                    visible: item.overlaid || item.jumbo > 0 || item.bare
                                    anchors.fill: stamp; anchors.margins: -3; anchors.leftMargin: -6; anchors.rightMargin: -6
                                    radius: height / 2
                                    color: Qt.rgba(0, 0, 0, 0.4)
                                }
                                Row {           // the time: 📌, 👁 views, ↩ answers, edited, when, ✓ (Telegram-iOS's order)
                                    id: stamp
                                    anchors.right: parent.right; anchors.rightMargin: item.overlaid || item.jumbo ? (item.bare ? 8 : 12) : 10
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: bubble.tail + (item.overlaid || item.jumbo ? (item.bare ? 6 : 10) : 6)
                                    spacing: 2
                                    readonly property color ink: item.overlaid || item.jumbo || item.bare ? "white" : item.out ? Theme.outMeta : Theme.inMeta
                                    Loader {        // (made only when there are any)
                                        id: counts
                                        active: item.views > 0 || item.replies > 0
                                        visible: active
                                        readonly property Item msg: item
                                        sourceComponent: Row {
                                            readonly property Item item: counts.msg
                                            spacing: 2
                                            Icon {
                                                visible: item.views > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 14; height: 14
                                                name: "eye"; color: stamp.ink
                                            }
                                            Text {
                                                visible: item.views > 0
                                                text: store.short(item.views) + " "
                                                color: stamp.ink
                                                font.family: Theme.font; font.pixelSize: 12
                                            }
                                            Icon {
                                                visible: item.replies > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 13; height: 13
                                                name: "reply"; color: stamp.ink
                                            }
                                            Text {
                                                visible: item.replies > 0
                                                text: item.replies + " "
                                                color: stamp.ink
                                                font.family: Theme.font; font.pixelSize: 12
                                            }
                                        }
                                    }
                                    Text {
                                        textFormat: Text.StyledText
                                        text: (item.isPinned ? "📌 " : "") + (item.edited ? Tr.t("tahrirlandi") + " " : "") + item.time +
                                              (item.out ? (item.sending ? " ◷" : " <font color='" + (item.overlaid || item.jumbo ? "white" : Theme.check) + "'>" + (item.msgId <= page.readUpTo ? "✓✓" : "✓") + "</font>") : "")
                                        color: stamp.ink
                                        font.family: Theme.font; font.pixelSize: 12
                                    }
                                }
                                Loader {        // a channel post's comments: how many, a tap opens them (made only for such a post)
                                    id: talkRow
                                    active: bubble.tail > 0
                                    anchors.bottom: parent.bottom
                                    width: parent.width; height: bubble.tail
                                    readonly property Item msg: item
                                    sourceComponent: Item {
                                        readonly property Item item: talkRow.msg
                                        Rectangle { x: 12; width: parent.width - 24; height: 1; color: Theme.fieldBorder }
                                        Icon {
                                            x: 10; anchors.verticalCenter: parent.verticalCenter
                                            name: "chats"; color: Theme.accent; scale: 0.8
                                        }
                                        Text {
                                            x: 40; anchors.verticalCenter: parent.verticalCenter
                                            text: item.talk > 0 ? Tr.n("%1 ta izoh", item.talk) : Tr.t("Izoh qoldirish")
                                            color: Theme.accent
                                            font.family: Theme.font; font.pixelSize: 15
                                        }
                                        Text {
                                            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                            text: "›"
                                            color: Theme.accent
                                            font.family: Theme.font; font.pixelSize: 22
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: page.openComments(item.talkId) }
                                    }
                                }
                            }
                            Loader {            // beside a channel's post: send it on (as Telegram has it; made only in a channel)
                                id: share
                                active: page.channel && !item.out
                                x: bubble.x + bubble.width + 8
                                y: bubble.y + bubble.height - bubble.tail - height
                                width: 32; height: 32
                                readonly property Item msg: item
                                sourceComponent: Rectangle {
                                    readonly property Item item: share.msg
                                    radius: 16
                                    color: Qt.rgba(0, 0, 0, 0.22)
                                    Icon { anchors.centerIn: parent; name: "forward"; color: "white"; scale: 0.72 }
                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -6
                                        onClicked: { page.forwarding = item.ids; forwardSheet.show() }
                                    }
                                }
                            }
                        }
                        Loader {             // «Tanlash»: its circle, filled and ticked once picked (made while picking and as it goes)
                            id: circle
                            active: page.picking
                            readonly property Item msg: item
                            sourceComponent: Rectangle {
                                readonly property Item item: circle.msg
                                // in from the left once made: Behaviors move nothing until the row is complete
                                property bool shown: false
                                Component.onCompleted: Qt.callLater(() => shown = Qt.binding(() => item.pickable))
                                visible: opacity > 0
                                opacity: shown ? 1 : 0
                                x: shown ? 12 : -16
                                y: item.above + (bubble.height - height) / 2
                                width: 26; height: 26; radius: 13
                                color: item.isPicked ? Theme.accent : Qt.rgba(0, 0, 0, 0.12)
                                border.color: item.isPicked ? Theme.accent : "white"; border.width: 1.5
                                Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring } }
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Icon { visible: item.isPicked; anchors.centerIn: parent; width: 18; height: 18; name: "check"; color: "white" }
                            }
                        }
                        MouseArea {          // while picking a tap anywhere on its row picks it (or puts it back);
                            anchors.fill: parent    // on one of an album's pictures or files, that one alone
                            visible: item.pickable
                            onClicked: (mouse) => {
                                const one = item.oneAt(mouse.x, mouse.y)
                                page.pick(one ? [one] : item.ids)
                            }
                        }
                        XAnimator { id: flyX; target: mover; to: 0; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] }
                        YAnimator { id: flyY; target: mover; to: 0; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.19919, 0.01064, 0.27921, 0.91025, 1.0, 1.0] }
                        // start where the text was in the field. Called before the list scrolls to this on
                        // the same vertical curve: the two together make one path from there to rest.
                        function flyFrom(from) {
                            const here = body.mapToItem(page, 0, 0)
                            mover.x = from.x - here.x
                            mover.y = from.y - here.y
                            page.lift = true
                            landed.restart()
                            flyX.start()
                            flyY.start()
                        }
                    }
                }
            }
        }

        Glass {              // ↓: to the newest (loaded afresh when it was opened at the unread ones)
            id: toNewest
            z: 2
            anchors.right: parent.right; anchors.rightMargin: 10
            y: parent.height - page.kb - page.foot - height - 8
            width: 40; height: 40
            visible: page.ready && page.away
            Text {
                anchors.centerIn: parent
                text: "⌄"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 26
                anchors.verticalCenterOffset: -5
            }
            Rectangle {      // how many are unread
                visible: page.unread > 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: -9
                width: Math.max(20, unreadText.implicitWidth + 10); height: 20; radius: 10
                color: Theme.badge
                Text {
                    id: unreadText
                    anchors.centerIn: parent
                    text: store.count(page.unread)
                    color: Theme.badgeText
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -6
                onClicked: {
                    if (page.gap) {
                        page.fresh()
                        return
                    }
                    list.down = true
                    list.positionViewAtBeginning()
                }
            }
        }

        Rectangle {          // a chat with nothing in it yet: a card in the middle, as Telegram-iOS's
            visible: page.ready && messages.count === 0
            anchors.centerIn: parent
            transform: Translate { y: -page.kb / 2 }
            width: Math.min(parent.width - 80, 240); height: emptyText.height + 32
            radius: 18
            color: Theme.dayPill
            Column {
                id: emptyText
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 6
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Hali xabar yo'q")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: page.canPost ? Tr.t("Birinchi xabarni yozing.") : Tr.t("Bu yerga hali hech narsa yuborilmagan.")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
        }

        Item {               // the header, Telegram-iOS 26's: three glass pieces over the chat — ‹ and the
            id: bar          // chats waiting unread, the name and what it is, the picture (owner's iPad 26204/26206)
            z: 3
            width: parent.width; height: 60
            Rectangle {      // iOS 26's edge: what scrolls up fades out under the glass
                width: parent.width; height: parent.height + pinBar.height + 16
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(Theme.glass.r, Theme.glass.g, Theme.glass.b, 0.7) }
                    GradientStop { position: 0.6; color: Qt.rgba(Theme.glass.r, Theme.glass.g, Theme.glass.b, 0.35) }
                    GradientStop { position: 1; color: Qt.rgba(Theme.glass.r, Theme.glass.g, Theme.glass.b, 0) }
                }
            }
            Glass {          // ‹ 24
                id: backCap
                visible: !page.selecting
                x: 10; y: 8
                width: backRow.width + 26; height: 44
                opacity: backHit.pressed ? 0.5 : 1
                Row {
                    id: backRow
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2
                        text: "‹"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Light
                    }
                    Rectangle {
                        visible: store.unreadChats > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(height, backCount.implicitWidth + 12); height: 20; radius: 10
                        color: Theme.text
                        Text {
                            id: backCount
                            anchors.centerIn: parent
                            text: store.unreadChats > 99 ? "99+" : store.unreadChats
                            color: Theme.bg
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                }
            }
            MouseArea {          // the back button: the bar's whole height and from the edge, as iOS takes it
                id: backHit
                enabled: !page.selecting
                width: backCap.x + backCap.width + 4; height: parent.height
                onClicked: page.nav.pop()
            }
            Glass {          // the name, and under it what it is
                id: titleCap
                readonly property real rightEdge: dmBarBtn.visible ? bar.width - dmBarBtn.x : bar.width - face.x
                readonly property real room: bar.width - 2 * (page.selecting ? bar.width - cancelCap.x
                                                                 : Math.max(backCap.x + backCap.width, rightEdge)) - 16
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: Math.min(room, Math.max(titleText.implicitWidth, subText.visible ? subText.implicitWidth : 0) + 40)
                height: 44
                opacity: titleHit.pressed ? 0.6 : 1
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    Text {
                        id: titleText
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: page.selecting ? (page.pickedIds.length ? Tr.n("%1 ta tanlandi", page.pickedIds.length) : Tr.t("Xabarlarni tanlang"))
                            : page.directTopic && page.directSender ? (store.seen, store.senderName(page.directSender, false) || store.title(page.chat))
                            : page.thread ? Tr.t("Izohlar") : store.title(page.chat)
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        id: subText
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: page.directTopic ? store.title(page.chat) + " · " + Tr.t("Kanalga xabarlar")
                            : page.thread ? page.threadOf : (store.seen, page.now, store.status(page.chat, page.now))     // (re-read when either changes)
                        visible: text !== "" && !page.selecting
                        color: text === Tr.t("onlayn") || text.endsWith("...") ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
            MouseArea {          // the title, or the picture: the page about the chat (in comments: the search)
                id: titleHit
                enabled: !page.selecting
                anchors.left: backHit.right; anchors.right: parent.right
                height: parent.height
                onClicked: {
                    if (page.thread)
                        page.focusFind()
                    else if (page.directTopic && page.directSender && page.directSender["@type"] === "messageSenderUser")
                        store.chatWith(page.directSender.user_id, (id) => page.nav.push(infoPage, { chatId: id, chatPage: page }))
                    else
                        page.nav.push(infoPage, { chatId: page.chatId, chatPage: page })
                }
            }
            Glass {          // channel admin's DM inbox shortcut (with unread count badge)
                id: dmBarBtn
                visible: page.channel && page.canPost && page.directChatId !== 0 && !page.selecting
                anchors.right: face.left; anchors.rightMargin: 8; y: 8
                width: 44; height: 44
                opacity: dmBarHit.pressed ? 0.65 : 1
                Icon { anchors.centerIn: parent; width: 20; height: 20; name: "direct"; color: Theme.text }
                Rectangle {
                    readonly property int n: (store.seen, page.directChatId && store.chats[page.directChatId]
                                              ? (store.chats[page.directChatId].unread_count || 0) : 0)
                    visible: n > 0
                    anchors.right: parent.right; anchors.rightMargin: -2; y: -3
                    width: Math.max(18, dmCnt.implicitWidth + 8); height: 18; radius: 9
                    color: Theme.badge
                    Text {
                        id: dmCnt
                        anchors.centerIn: parent
                        text: parent.n > 99 ? "99+" : String(parent.n)
                        color: Theme.badgeText
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold
                    }
                }
                MouseArea {
                    id: dmBarHit
                    anchors.fill: parent
                    onClicked: store.openDirectMessages(page.directChatId, page.nav, page.chatId)
                }
            }
            Avatar {
                id: face
                anchors.right: parent.right; anchors.rightMargin: 10
                y: 8
                width: 44; height: 44
                source: page.directTopic && page.directSender ? dmFacePhoto : (page.chat ? store.photoPath(page.chat) : "")
                letters: page.directTopic && page.directSender
                    ? store.letters(store.senderName(page.directSender, false))
                    : (page.chat ? store.letters(page.chat.title) : "")
                tint: page.directTopic && page.directSender
                    ? store.tints[Math.abs(page.directSender.user_id || page.directSender.chat_id || 0) % store.tints.length]
                    : store.tints[Math.abs(page.chatId) % store.tints.length]
                saved: !page.directTopic && store.isSaved(page.chat)
                visible: !page.selecting
                property string dmFacePhoto: ""
                Component.onCompleted: {
                    if (page.directTopic && page.directSender) {
                        const s = page.directSender
                        if (s["@type"] === "messageSenderUser" && store.users[s.user_id])
                            store.userPhoto(store.users[s.user_id], (p) => face.dmFacePhoto = p)
                        else if (s["@type"] === "messageSenderChat" && store.chats[s.chat_id])
                            face.dmFacePhoto = store.photoPath(store.chats[s.chat_id])
                    }
                }
            }
            Glass {          // picking: «Bekor» where the picture was
                id: cancelCap
                visible: page.selecting
                anchors.right: parent.right; anchors.rightMargin: 10
                y: 8
                width: cancelPick.implicitWidth + 32; height: 44
                opacity: cancelPickHit.pressed ? 0.6 : 1
                Text {
                    id: cancelPick
                    anchors.centerIn: parent
                    text: Tr.t("Bekor")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                MouseArea { id: cancelPickHit; anchors.fill: parent; anchors.margins: -6; onClicked: page.stopPicking() }
            }
        }

        Rectangle {          // searching: the field over the header, "Bekor" to leave
            z: 4
            visible: page.searching
            width: parent.width; height: bar.height
            color: Qt.rgba(Theme.bar.r, Theme.bar.g, Theme.bar.b, 1)     // (the bar itself lets its title through)
            MouseArea { anchors.fill: parent }
            Rectangle {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - cancelFind.width - 26; height: 36; radius: 18
                color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
                Icon {
                    x: 11; anchors.verticalCenter: parent.verticalCenter
                    name: "search"; width: 18; height: 18; color: Theme.grey
                }
                TextInput {
                    id: findField
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 12
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onTextChanged: findLater.restart()
                    onAccepted: { findLater.stop(); page.find(text); focus = false }
                    Text {
                        visible: !findField.text
                        text: Tr.t("Chatdan qidirish")
                        color: Theme.grey
                        font: findField.font
                    }
                }
                Timer { id: findLater; interval: 400; onTriggered: page.find(findField.text) }
            }
            Text {
                id: cancelFind
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Bekor")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.stopSearch() }
            }
        }

        Rectangle {          // searching: under the messages, which one of how many, ↑ older ↓ newer
            id: findBar
            z: 2
            visible: page.searching
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.barLift }
            width: parent.width; height: 52
            color: Theme.bar
            MouseArea { anchors.fill: parent }
            Rectangle { y: parent.height; width: parent.width; height: page.barLift - page.kb; color: Theme.bar }    // on to the edge
            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
            Row {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ g: "⌃", d: 1 }, { g: "⌄", d: -1 }]
                    Text {
                        required property var modelData
                        readonly property int to: page.hit + modelData.d
                        readonly property bool can: to >= 0 && to < page.hits.length
                        width: 44; height: 44
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: modelData.g
                        color: can ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 26; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; enabled: parent.can; onClicked: page.showHit(parent.to) }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: page.hits.length ? Tr.f("%1 tadan %2", store.count(page.hits.length), page.hit + 1)
                    : page.searched ? Tr.t("Hech narsa topilmadi") : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
        }

        Item {               // under the header, one glass panel as Telegram-iOS 26's (owner's iPad 26204/26206):
            id: pinBar       // who asks to join (admins), the pinned message (ChatPinnedMessageTitlePanelNode)
            z: 3
            y: bar.height
            width: parent.width
            height: panel.height > 0 ? panel.height + 8 : 0
            visible: height > 0
            Glass {
                id: panel
                x: 10; y: 2
                width: parent.width - 20
                height: miniRow.height + (page.askingShown ? 48 : 0) + (page.pinned ? 48 : 0) + (page.translatable ? 48 : 0)
                radius: 20
                clip: true
                MiniPlayer {    // the sound playing, first (iOS 26: the media accessory over the pinned message)
                    id: miniRow
                    player: page.player
                    onOpened: {
                        if (page.player.kind === "audio")
                            page.player.showSheet()
                        else if (page.player.chatId === page.chatId)
                            page.jump(page.player.msgId)
                        else
                            page.nav.push(Qt.createComponent("ChatPage.qml"), { chatId: page.player.chatId, target: page.player.msgId })   // (not a Component of itself: recursive)
                    }
                    Rectangle {
                        visible: askRow.visible || pinRow.visible || transRow.visible
                        x: 14; anchors.bottom: parent.bottom; width: parent.width - 28; height: 0.5; color: Theme.separator
                    }
                }
                Item {          // "N ta qo'shilish so'rovi": the first one's picture, a tap lists them, × hides
                    id: askRow
                    y: miniRow.height
                    width: parent.width; height: page.askingShown ? 48 : 0
                    visible: height > 0
                    opacity: askHit.pressed ? 0.6 : 1
                    property string photo: ""
                    readonly property var first: page.asking && page.asking.user_ids.length
                                                 ? (store.seen, store.users[page.asking.user_ids[0]]) : null
                    onFirstChanged: { photo = ""; if (first) store.userPhoto(first, (p) => askRow.photo = p) }
                    Avatar {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34
                        source: askRow.photo
                        letters: askRow.first ? store.letters(askRow.first.first_name + " " + askRow.first.last_name) : ""
                        tint: store.tints[Math.abs(askRow.first ? askRow.first.id : 0) % store.tints.length]
                    }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 120
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: page.asking ? Tr.n("%1 ta qo'shilish so'rovi", page.asking.total_count, store.count(page.asking.total_count)) : ""
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15
                    }
                    MouseArea {
                        id: askHit
                        anchors.fill: parent
                        onClicked: page.nav.push(joinPage, { chatId: page.chatId })
                    }
                    Icon {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        name: "cross"
                        color: Theme.text
                        MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.askingHidden = page.asking.total_count }
                    }
                    Rectangle {
                        visible: !!page.pinned
                        x: 14; anchors.bottom: parent.bottom; width: parent.width - 28; height: 0.5; color: Theme.separator
                    }
                }
                Item {          // "O'zbek tiliga tarjima qilish" / back to the original; ⋯: not for this chat
                    id: transRow
                    y: miniRow.height + askRow.height + pinRow.height
                    width: parent.width; height: page.translatable ? 48 : 0
                    visible: height > 0
                    Rectangle {
                        visible: askRow.visible || pinRow.visible
                        x: 14; width: parent.width - 28; height: 0.5; color: Theme.separator
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        opacity: transHit.pressed ? 0.5 : 1
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22
                            name: "translate"
                            color: Theme.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Tr.t(page.translating ? "Asl nusxasini ko'rsatish" : "O'zbek tiliga tarjima qilish")
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                    }
                    MouseArea {
                        id: transHit
                        anchors.fill: parent; anchors.rightMargin: 52
                        onClicked: page.setTranslating(!page.translating)
                    }
                    Rectangle {      // ⋯
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; radius: 13
                        color: "transparent"
                        border.color: Theme.text; border.width: 1.5
                        opacity: moreHit.pressed ? 0.5 : 1
                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.text } }
                        }
                        MouseArea { id: moreHit; anchors.fill: parent; anchors.margins: -10; onClicked: transMenu.show() }
                    }
                }
                Item {          // the pinned message: a tap goes to it
                    id: pinRow
                    y: miniRow.height + askRow.height
                    width: parent.width; height: page.pinned ? 48 : 0
                    visible: height > 0
                    opacity: pinHit.pressed ? 0.6 : 1
                    Rectangle { x: 14; y: 9; width: 2.5; height: 30; radius: 1.25; color: Theme.accent }
                    Text {
                        x: 26; y: 6
                        text: Tr.t("Qadalgan xabar")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        x: 26; y: 25
                        width: parent.width - x - 48
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: page.pinned ? page.pinned.text.replace(/\s+/g, " ") : ""
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Icon {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        name: "pin"
                        color: Theme.text
                    }
                    MouseArea {
                        id: pinHit
                        anchors.fill: parent
                        onClicked: page.goTo(page.pinned.id)
                    }
                }
            }
        }

        Item {               // a channel we only read: its sound on or off instead of the field, a capsule
            id: chanBar      // and a round 🔍 of glass floating over the posts (Telegram-iOS 26, owner's IMG_0092)
            z: 1
            visible: !page.canPost && !page.searching && !page.selecting
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.barLift }
            width: parent.width
            height: visible ? 60 : 0
            readonly property bool hasGift: page.canGift && !page.outside
            readonly property bool hasDm: page.directChatId !== 0 && !page.outside
            readonly property real leftEnd: hasGift && hasDm ? 102 : (hasGift || hasDm) ? 52 : 8
            readonly property real rightStart: width - 52          // 8 margin + 44 search circle
            readonly property real slotLeft: leftEnd + (hasGift || hasDm ? 8 : 0)
            readonly property real slotRight: rightStart - 8
            readonly property real slotW: Math.max(80, slotRight - slotLeft)
            Glass {
                id: mutePill
                readonly property real pad: chanBar.hasGift && chanBar.hasDm ? 28 : 44
                width: Math.min(chanBar.slotW, muteText.implicitWidth + pad)
                height: 44
                // when both 🎁 and 💬 sit on the left, center cleanly inside the open middle slot between them and 🔍
                // (equal breathing gaps on both sides, zero overlap); with 0 or 1 left button, center on the bar
                x: chanBar.hasGift && chanBar.hasDm
                   ? chanBar.slotLeft + (chanBar.slotW - width) / 2
                   : Math.max(chanBar.slotLeft, Math.min(chanBar.slotRight - width, (chanBar.width - width) / 2))
                anchors.verticalCenter: parent.verticalCenter
                opacity: muteHit.pressed ? 0.7 : 1
                Text {
                    id: muteText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, mutePill.width - 18)
                    wrapMode: page.barred ? Text.Wrap : Text.NoWrap
                    maximumLineCount: page.barred ? 2 : 1
                    fontSizeMode: page.barred ? Text.FixedSize : Text.HorizontalFit
                    minimumPixelSize: 13
                    elide: page.barred ? Text.ElideNone : Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    text: page.outside ? Tr.t("Qo'shilish") : page.blocked ? Tr.t(page.bot ? "Qayta ishga tushirish" : "Blokdan chiqarish")
                          : page.barred || (page.muted ? Tr.t("Sukutdan chiqarish") : Tr.t("Sukut qilish"))
                    color: page.outside || page.blocked ? Theme.accent : page.barred ? Theme.grey : Theme.text
                    font.family: Theme.font; font.pixelSize: page.barred ? 13 : 16; font.weight: Font.Medium
                }
                MouseArea {
                    id: muteHit
                    anchors.fill: parent
                    enabled: !page.barred || page.blocked
                    onClicked: {
                        if (page.outside)
                            return store.send({ "@type": "joinChat", chat_id: page.chatId }, store.check)
                        if (page.blocked)
                            return page.unblock()
                        const n = Object.assign({}, page.chat.notification_settings)
                        n["@type"] = "chatNotificationSettings"
                        n.use_default_mute_for = false
                        n.mute_for = page.muted ? 0 : 2147483647
                        page.muted = !page.muted        // at once; TDLib's update says the same
                        store.send({ "@type": "setChatNotificationSettings", chat_id: page.chatId, notification_settings: n }, store.check)
                    }
                }
            }
            Glass {              // 🎁 on the left (IMG_0297: gift · sound · search): GiftSheet
                visible: chanBar.hasGift
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                opacity: giftHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "gift"; color: Theme.text }
                MouseArea { id: giftHit; anchors.fill: parent; onClicked: giftSheet.show() }
            }
            Glass {              // Channel Direct Messages button on the left (next to 🎁 if both are shown)
                visible: chanBar.hasDm
                x: chanBar.hasGift ? 58 : 8
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                opacity: dmSubHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; width: 20; height: 20; name: "direct"; color: Theme.text }
                MouseArea { id: dmSubHit; anchors.fill: parent; onClicked: store.openDirectMessages(page.directChatId, page.nav, page.chatId) }
            }
            Glass {              // (as IMG_0297: the search on the bar's right)
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                opacity: findHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "search"; color: Theme.text }
                MouseArea { id: findHit; anchors.fill: parent; onClicked: { page.searching = true; findField.forceActiveFocus() } }
            }
        }

        Item {               // picking: what goes for all of them — deleted (🗑, left), their words copied
            id: pickBar      // (the middle), forwarded (right); each a piece of glass as the field's
            z: 1
            visible: page.selecting
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.barLift }
            width: parent.width
            height: visible ? 60 : 0
            Glass {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                opacity: !page.pickedDeletable ? 0.4 : trashHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "trash"; color: Theme.danger }
                MouseArea { id: trashHit; anchors.fill: parent; enabled: page.pickedDeletable; onClicked: deleteMenu.show() }
            }
            Glass {
                anchors.centerIn: parent
                visible: page.pickedText !== ""
                width: copyPickText.implicitWidth + 44; height: 44
                opacity: copyPickHit.pressed ? 0.7 : 1
                Text {
                    id: copyPickText
                    anchors.centerIn: parent
                    text: Tr.t("Nusxalash")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                MouseArea {
                    id: copyPickHit
                    anchors.fill: parent
                    onClicked: {
                        page.copy(page.pickedText)
                        page.toast(page.pickedIds.length > 1 ? Tr.n("%1 ta xabar nusxalandi", page.pickedIds.length) : Tr.t("Nusxalandi"))
                        page.stopPicking()
                    }
                }
            }
            Glass {
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                readonly property bool can: page.pickedCan("can_be_forwarded")
                opacity: !can ? 0.4 : fwdPickHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "forward"; color: Theme.text }
                MouseArea { id: fwdPickHit; anchors.fill: parent; enabled: parent.can; onClicked: page.forwardPicked() }
            }
        }

        Item {               // the field, with what it answers or edits over it: Telegram-iOS 26's glass
            id: input        // floating over the chat — 📎, the field, the mic, each its own piece
            z: 1
            visible: page.canPost && !page.searching && !page.selecting
            anchors.bottom: parent.bottom
            transform: Translate { y: -page.barLift }
            width: parent.width
            height: visible ? compose.height + Math.max(60, field.contentHeight + 38) : 0
            onHeightChanged: if (list.down && !scroll.running) Qt.callLater(list.positionViewAtBeginning)
            Glass {              // the field's menu (held): as iOS's edit menu, and Telegram's «Format»
                id: fieldMenu
                property bool shown: false
                property bool formats: false        // B I U S … in place of cut/copy/paste
                property bool linking: false        // the address of a link being written
                readonly property bool chosen: field.selectionEnd > field.selectionStart
                visible: shown && (field.activeFocus || link.activeFocus)
                // put back once out of the change: `shown` is in `visible`'s own binding (a loop, in the log)
                onVisibleChanged: if (!visible) Qt.callLater(reset)
                function reset() { if (!visible) { formats = false; linking = false; shown = false } }
                anchors.horizontalCenter: parent.horizontalCenter
                y: -height - 4
                height: 44
                width: Math.min(parent.width - 16, (linking ? linkRow.implicitWidth : acts.implicitWidth) + 12)
                radius: 22
                z: 3
                readonly property var plainActs: (chosen ? [
                    { t: Tr.t("Kesish"), run: () => field.cut() }, { t: Tr.t("Nusxa"), run: () => field.copy() } ] : [])
                    .concat(field.canPaste ? [{ t: Tr.t("Joylash"), run: () => field.paste() }] : [])
                    .concat(field.text && !(field.selectionStart === 0 && field.selectionEnd === field.length)
                            ? [{ t: Tr.t("Hammasi"), keep: true, run: () => field.selectAll() }] : [])
                    .concat(chosen ? [{ t: Tr.t("Format ›"), keep: true, run: () => fieldMenu.formats = true }] : [])
                readonly property var formatActs: [
                    { t: "B", w: Font.Bold, k: "textEntityTypeBold" }, { t: "I", i: true, k: "textEntityTypeItalic" },
                    { t: "U", u: true, k: "textEntityTypeUnderline" }, { t: "S", s: true, k: "textEntityTypeStrikethrough" },
                    { t: Tr.t("Kod"), mono: true, k: "textEntityTypeCode" }, { t: Tr.t("Spoyler"), k: "textEntityTypeSpoiler" },
                    { t: Tr.t("Iqtibos"), k: "textEntityTypeBlockQuote" }, { t: Tr.t("Havola"), k: "textEntityTypeTextUrl" }]
                onFormatsChanged: menuFlick.contentX = 0
                Flickable {
                    id: menuFlick
                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                    visible: !fieldMenu.linking
                    contentWidth: acts.implicitWidth
                    clip: true
                    Row {
                        id: acts
                        height: 44
                        Repeater {
                            model: fieldMenu.formats ? fieldMenu.formatActs : fieldMenu.plainActs
                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property bool on: !!modelData.k && page.marked(modelData.k)
                                width: word.implicitWidth + 18; height: 44
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width - 6; height: 32; radius: 16
                                    color: parent.on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : "transparent"
                                }
                                Text {
                                    id: word
                                    anchors.centerIn: parent
                                    text: modelData.t
                                    color: parent.on ? Theme.accent : Theme.text
                                    font.family: modelData.mono ? "monospace" : Theme.font; font.pixelSize: 15
                                    font.weight: modelData.w || Font.Normal; font.italic: !!modelData.i
                                    font.underline: !!modelData.u; font.strikeout: !!modelData.s
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const a = modelData
                                        if (a.k === "textEntityTypeTextUrl" && !page.marked(a.k)) {
                                            fieldMenu.linking = true
                                            link.text = ""
                                            link.forceActiveFocus()
                                            return
                                        }
                                        if (a.k)
                                            return page.toggleMark(a.k)
                                        // closed first: run() changes what the menu offers (the text, the
                                        // choice, the clipboard), its Repeater makes this button again, and
                                        // after that nothing here is left to reach fieldMenu by
                                        if (!a.keep)
                                            fieldMenu.shown = false
                                        a.run()
                                    }
                                }
                            }
                        }
                    }
                }
                Row {                // Havola: the address, ✓ to put it on the chosen words
                    id: linkRow
                    visible: fieldMenu.linking
                    x: 14; height: 44; spacing: 10
                    TextInput {
                        id: link
                        anchors.verticalCenter: parent.verticalCenter
                        width: 220
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 15
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                        Text { visible: !link.text; text: "https://"; color: Theme.grey; font: link.font }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"; color: Theme.accent; font.pixelSize: 20; font.weight: Font.Bold
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -10
                            onClicked: {
                                const u = link.text.trim()
                                if (u)
                                    page.toggleMark("textEntityTypeTextUrl", /^[a-z][a-z0-9+.-]*:/i.test(u) ? u : "https://" + u)
                                fieldMenu.linking = false
                                field.forceActiveFocus()
                            }
                        }
                    }
                }
            }
            Glass {              // the clip: pictures and files from the phone
                x: 8
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                width: 44; height: 44
                visible: !page.editing
                opacity: !page.canAttach ? 0.4 : clipHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; width: 26; height: 26; name: "clip"; color: Theme.text }
                MouseArea {
                    id: clipHit
                    anchors.fill: parent
                    onClicked: {
                        if (!page.canAttach)        // (none of what it sends may be sent here)
                            return page.toast(page.allowedText)
                        page.keyboardDown()     // (over the sheet it stayed, its «Yuborish» under it)
                        sheet.show()
                    }
                }
            }
            Glass {
                id: fieldBox
                x: page.editing ? 8 : 58; y: 8
                width: parent.width - x - 58; height: parent.height - 16
                radius: 22
                Item {           // what it answers or edits, at the top of the field's glass
                    id: compose
                    width: parent.width
                    height: page.replying || page.editing ? 46 : 0
                    visible: height > 0
                    Rectangle { x: 14; y: 8; width: 2; height: 32; radius: 1; color: Theme.accent }
                    Text {
                        x: 24; y: 7
                        width: parent.width - 60
                        elide: Text.ElideRight
                        text: page.editing ? Tr.t("Tahrirlash") : page.replying ? Tr.f("Javob: %1", page.replying.name) : ""
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        x: 24; y: 25
                        width: parent.width - 60
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: page.replying ? page.replying.text.replace(/\s+/g, " ") : ""
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.cancelCompose() }
                    }
                }
                TextEdit {
                    id: field
                    x: 14; y: compose.height + 11
                    width: parent.width - 28 - (bell.visible ? 30 : 0) - (clock.visible ? 30 : 0) - (smiley.visible ? 30 : 0)
                    wrapMode: TextEdit.Wrap
                    onActiveFocusChanged: if (activeFocus && page.panelOpen) page.keyboardUp()
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                    onTextChanged: {
                        page.reMark()
                        if (page.ready)
                            draftLater.restart()
                    }
                    readOnly: page.textBarred
                    activeFocusOnPress: !page.textBarred
                    persistentSelection: fieldMenu.linking      // the chosen words, while their link is written
                    onSelectedTextChanged: if (!selectedText && fieldMenu.shown && fieldMenu.formats) fieldMenu.shown = false
                    // held: the word under the finger chosen, and the field's menu. Chosen once let go:
                    // a touch's release puts the cursor and would undo it
                    TapHandler {
                        property int at: -1          // where it was held
                        onLongPressed: at = field.positionAt(point.position.x, point.position.y)
                        onPressedChanged: if (!pressed && at >= 0) Qt.callLater(() => {
                            if (field.text && !(at >= field.selectionStart && at < field.selectionEnd)) {
                                field.cursorPosition = at
                                field.selectWord()
                            }
                            at = -1
                            fieldMenu.formats = false
                            fieldMenu.shown = true
                        })
                        onTapped: fieldMenu.shown = false
                    }
                    Text {
                        visible: !field.text && !field.preeditText && !page.textBarred
                        text: page.paidMessageStars > 0 ? Tr.f("Xabar (⭐ %1)", store.count(page.paidMessageStars))
                            : page.channel ? Tr.t("Xabar tarqatish") : Tr.t("Xabar")
                        color: page.paidMessageStars > 0 ? (Theme.dark ? "#ffc337" : "#c87000") : Theme.grey
                        font: field.font
                    }
                }
                Row {            // text barred: 🔒 and why, in the field's middle (Telegram-iOS's «Text not allowed»)
                    visible: page.textBarred
                    x: (parent.width - width) / 2
                    y: compose.height + (parent.height - compose.height - height) / 2
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; name: "lock"; color: Theme.grey }
                    Text { text: Tr.t("Matn yozib bo'lmaydi"); color: Theme.grey; font: field.font }
                }
                MouseArea {      // and a tap on it says what may be sent instead
                    visible: page.textBarred
                    y: compose.height
                    width: parent.width; height: parent.height - compose.height
                    onClicked: page.toast(page.allowedText)
                }
                Item {           // 🙂: the emoji, stickers and GIFs (StickerPanel) in the keyboard's place; ⌨ back
                    id: smiley
                    visible: !page.editing
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: (44 - height) / 2
                    width: 24; height: 24
                    Text {
                        visible: !page.panelOpen
                        anchors.centerIn: parent
                        text: "☺"
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 24
                    }
                    Text {
                        visible: page.panelOpen
                        anchors.centerIn: parent
                        text: "⌨"
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 22
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -10
                        onClicked: page.panelOpen ? page.keyboardUp() : page.showPanel()
                    }
                }
                Item {           // ⏱: how long messages stay (Telegram-iOS's auto-delete button), the time when set
                    id: clock
                    visible: page.canAutoDelete && !page.editing
                    anchors.right: smiley.visible ? smiley.left : parent.right; anchors.rightMargin: smiley.visible ? 8 : 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: (44 - height) / 2
                    width: 22; height: 22
                    Icon {
                        visible: !page.autoDelete
                        anchors.fill: parent
                        name: "timer"
                        color: Theme.grey
                    }
                    Rectangle {
                        visible: page.autoDelete > 0
                        anchors.centerIn: parent
                        width: Math.max(22, clockText.implicitWidth + 8); height: 22; radius: 11
                        color: "transparent"
                        border.color: Theme.accent; border.width: 1.5
                        Text {
                            id: clockText
                            anchors.centerIn: parent
                            text: store.lastingShort(page.autoDelete)
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: timerMenu.show() }
                }
                Icon {           // a channel's 🔔: the post with or without a sound (Telegram-iOS's silent posting)
                    id: bell
                    visible: page.channel && !page.editing
                    anchors.right: clock.visible ? clock.left : smiley.visible ? smiley.left : parent.right
                    anchors.rightMargin: clock.visible || smiley.visible ? 8 : 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: (44 - height) / 2
                    width: 22; height: 22
                    name: "bell"
                    color: Theme.grey
                    Rectangle {     // the stroke through it when silent
                        visible: page.silent
                        anchors.centerIn: parent
                        width: 2; height: 26; radius: 1
                        rotation: -45
                        color: Theme.grey
                        border.color: Theme.glass; border.width: 0.5
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.setSilent(!page.silent) }
                }
            }
            Rectangle {          // recording: the time, and how to let it go (over the clip and the field)
                id: recBar
                visible: page.recording
                x: 8; y: fieldBox.y + compose.height
                width: parent.width - 66; height: fieldBox.height - compose.height
                radius: 22
                color: Theme.glass
                Rectangle {
                    id: dot
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: Theme.danger
                    SequentialAnimation on opacity {
                        running: page.recording; loops: Animation.Infinite
                        OpacityAnimator { from: 1; to: 0.2; duration: 500 }
                        OpacityAnimator { from: 0.2; to: 1; duration: 500 }
                    }
                }
                Text {
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    readonly property int tenths: Math.floor(page.recordMs / 100)
                    text: Math.floor(tenths / 600) + ":" + String(Math.floor(tenths / 10) % 60).padStart(2, "0") + "," + tenths % 10
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.features: { "tnum": 1 }
                }
                Text {
                    visible: !page.recordLocked
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width - implicitWidth - 12 + Math.min(0, page.recordSlide)
                    opacity: 1 - Math.min(0.8, -page.recordSlide / 150)
                    text: page.recordSlide < -110 ? Tr.t("Qo'yib yuboring — bekor bo'ladi") : Tr.t("‹ bekor qilish uchun suring")
                    color: page.recordSlide < -110 ? Theme.danger : Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {           // locked: the hands are free, «Bekor qilish» throws it away (iOS's «Cancel»)
                    visible: page.recordLocked
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right; anchors.rightMargin: 16
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.stopVoice(true) }
                }
            }
            Rectangle {          // the voice note stopped, before it goes: 🗑, ▶ and its waveform, its length
                id: previewBar
                visible: page.preview !== null || page.roundPreview !== null || page.roundBusy
                x: 8; y: fieldBox.y + compose.height
                width: parent.width - 66; height: fieldBox.height - compose.height
                radius: 22
                color: Theme.glass
                MouseArea { anchors.fill: parent }      // (not through to the field under it)
                Icon {
                    id: bin
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24
                    name: "trash"
                    color: Theme.danger
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.dropPreview() }
                }
                Text {           // a round video's: what and how long (it plays in its circle over the chat)
                    visible: page.roundPreview !== null || page.roundBusy
                    x: 48; anchors.verticalCenter: parent.verticalCenter
                    text: page.roundBusy ? Tr.t("Video xabar tayyorlanmoqda…")
                        : page.roundPreview ? Tr.t("Video xabar") + " · 0:" + String(page.roundPreview.dur).padStart(2, "0") : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15
                }
                Rectangle {
                    visible: page.preview !== null
                    x: 48; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 6; height: parent.height - 8
                    radius: height / 2
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                    clip: true
                    AudioRow {
                        x: -2; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        scale: 0.8; transformOrigin: Item.Left
                        kind: "voice"
                        wave: page.preview ? page.preview.wave : ""
                        dur: page.preview ? page.preview.dur : 0
                        here: true
                        current: hearing.position > 0 || playing     // (its length until it plays)
                        playing: hearing.playbackState === MediaPlayer.PlayingState
                        at: hearing.position
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: hearing.playbackState === MediaPlayer.PlayingState ? hearing.pause() : hearing.play()
                    }
                }
            }
            Rectangle {          // send (✓ for an edit); with the field empty, the mic: held, it records
                id: sendButton
                readonly property bool mic: !field.text.trim() && !page.editing && !page.recordLocked && page.preview === null
                                            && page.roundPreview === null && !page.roundBusy
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                width: 44; height: 44; radius: 22
                // (`sendButton.mic`, never `mic` alone: that is the page's AudioInput, an id coming before the
                // item's own property — the button stayed as the mic's: no colour under ↑, faint where voice was barred)
                color: sendButton.mic ? (page.recording ? Theme.danger : "transparent")
                     : field.text.trim() !== "" || page.recordLocked || page.preview !== null || page.roundPreview !== null
                       ? Theme.accent : Theme.mutedBadge
                scale: page.recording && !page.recordLocked ? 1.6 : 1
                opacity: sendButton.mic && !(page.roundMode ? page.canRound : page.canVoice) ? 0.4 : 1
                Behavior on scale { ScaleAnimator { duration: 200; easing.type: Easing.OutBack } }
                Rectangle {      // how loud it is: a blob round the held mic, growing with the voice (iOS)
                    z: -2
                    visible: page.recording
                    anchors.centerIn: parent
                    width: 44; height: 44; radius: 22
                    color: page.recordLocked ? Theme.accent : Theme.danger
                    opacity: 0.25
                    scale: 1 + meter.level * 0.9
                    Behavior on scale { NumberAnimation { duration: 90 } }
                }
                Glass {          // the mic's own round glass (the send button is the accent's colour)
                    z: -1
                    anchors.fill: parent
                    visible: sendButton.mic && !page.recording
                }
                Icon {           // (a tap switches it: the mic, or the camera for a round video, as on iOS)
                    visible: sendButton.mic
                    anchors.centerIn: parent
                    width: 26; height: 26
                    name: page.roundMode ? "camera" : "mic"
                    color: page.recording ? "white" : Theme.text
                }
                Text { visible: !sendButton.mic; anchors.centerIn: parent; text: page.editing ? "✓" : "↑"; color: "white"; font.pixelSize: 20; font.weight: Font.Bold }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    property real startX: 0
                    property real startY: 0
                    property bool held: false       // this press started the recording (a locked one's ↑ is a tap)
                    // held a moment first (as iOS): a tap switches mic ↔ camera without starting the recorder (whose
                    // start holds the UI thread long enough that a tap's release came late, counted as a hold)
                    Timer { id: holdOn; interval: 180; onTriggered: { parent.held = true; page.startVoice() } }
                    onPressed: (m) => {
                        held = false
                        if (!sendButton.mic)
                            return
                        if (!(page.roundMode ? page.canRound : page.canVoice))     // (barred here; a tap still switches)
                            page.toast(page.allowedText)
                        const at = mapToItem(page, m.x, m.y)    // (the page's points: the button grows 1.6× under the finger)
                        startX = at.x
                        startY = at.y
                        if (page.roundMode ? page.canRound : page.canVoice)
                            holdOn.restart()
                    }
                    // left: towards throwing it away; up past the lock: it goes on by itself (iOS)
                    onPositionChanged: (m) => {
                        if (!page.recording || !held || page.recordLocked)
                            return
                        const at = mapToItem(page, m.x, m.y)
                        page.recordSlide = at.x - startX
                        page.recordUp = Math.max(0, startY - at.y)
                        if (page.recordUp > 80 && page.recordSlide > -60)
                            page.recordLocked = true
                    }
                    onReleased: {
                        if (sendButton.mic && !held) {      // a tap: voice ↔ round video
                            holdOn.stop()
                            page.roundMode = !page.roundMode
                            page.toast(page.roundMode ? Tr.t("Video xabar: yozish uchun bosib turing") : Tr.t("Ovozli xabar: yozish uchun bosib turing"))
                            return
                        }
                        if (page.recording && held && !page.recordLocked)
                            page.stopVoice(page.recordSlide < -110)
                    }
                    onCanceled: {
                        holdOn.stop()
                        if (page.recording && held && !page.recordLocked)
                            page.stopVoice(true)
                    }
                    onClicked: {
                        if (held)
                            return
                        if (page.recordLocked)      // locked: ↑ sends it as it is
                            return page.stopVoice(false)
                        if (page.preview)
                            return page.sendPreview()
                        if (page.roundPreview)
                            return page.sendRoundPreview()
                        if (sendButton.mic)
                            return
                        const w = page.fieldWords(), t = w.text
                        if (!t)
                            return
                        if (page.editing) {
                            store.editText(page.chatId, page.editing.id, t, w.marks)
                            page.editing = null
                            field.text = ""
                            return
                        }
                        const doSend = () => {
                            if (page.gap)           // what is sent goes under the newest: go there first
                                page.fresh()
                            const at = field.mapToItem(page, 0, 0)
                            page.flying = { text: t, x: at.x, y: at.y }
                            store.sendText(page.chatId, t, page.replying ? page.replying.id : 0, page.thread, page.silent,
                                           w.marks, page.directTopic, page.paidMessageStars)
                            page.replying = null
                            field.text = ""
                            list.positionViewAtBeginning()
                        }
                        if (page.paidMessageStars > 0)
                            page.askPaid(page.paidMessageStars, doSend)
                        else
                            doSend()
                    }
                }
            }
        }
    }

    Item {               // a round video: the camera's circle over the dimmed chat (VideoMessageCameraScreen)
        id: roundView
        z: 1.8
        visible: (page.recording && page.roundMode) || page.roundPreview !== null || page.roundBusy
        width: parent.width; height: parent.height - page.kb - page.foot
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
        MouseArea { anchors.fill: parent }      // (nothing under it meanwhile)
        RoundCamera {
            id: roundCam
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(70, (parent.height - height) / 2 - 20)
            width: Math.min(parent.width - 60, 300); height: width
            visible: roundView.visible
            path: page.roundPreview ? page.roundPreview.path : td.fakeCamera
            mirrored: page.roundPreview ? false : page.roundMirror
            progress: page.roundPreview || page.roundBusy ? -1 : page.recordMs / 60000
            sound: page.roundPreview !== null
        }
        Glass {          // the camera's flip (here: the file mirrored)
            visible: page.recording
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: roundCam.bottom; anchors.topMargin: 22
            width: 44; height: 44
            Text { anchors.centerIn: parent; text: "⇄"; color: Theme.text; font.pixelSize: 22 }
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: page.roundMirror = !page.roundMirror }
        }
    }
    Glass {              // over the held mic: 🔒 and ⌃ (slide up to it); locked, ■ stops it for listening first
        id: lockPill
        z: 2
        visible: page.recording
        anchors.right: parent.right; anchors.rightMargin: 12
        y: page.height - page.kb - 60 - height - 34 - (page.recordLocked ? 0 : Math.min(40, page.recordUp / 2))
        width: 36; height: page.recordLocked ? 40 : 64
        radius: 18
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Icon {
            visible: !page.recordLocked
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: 20; height: 20
            name: "lock"
            color: page.recordUp > 80 ? Theme.accent : Theme.grey
        }
        Icon {
            visible: !page.recordLocked
            anchors.horizontalCenter: parent.horizontalCenter
            y: 34
            width: 18; height: 18
            rotation: 180
            name: "chevron"
            color: Theme.grey
            SequentialAnimation on y {
                running: lockPill.visible && !page.recordLocked; loops: Animation.Infinite
                NumberAnimation { from: 36; to: 30; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 30; to: 36; duration: 600; easing.type: Easing.InOutQuad }
            }
        }
        Rectangle {
            visible: page.recordLocked
            anchors.centerIn: parent
            width: 14; height: 14; radius: 3
            color: Theme.danger
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -8
            enabled: page.recordLocked
            onClicked: page.stopVoice(false, true)
        }
    }

    Component { id: infoPage; ChatInfoPage {} }

    // ---- a place ---------------------------------------------------------------
    // a live location's time left, as Telegram-iOS's ring says it in words: «12 daq qoldi», «tugadi»
    function liveLeft(end) {
        if (end === 0x7FFFFFFF)
            return Tr.t("Jonli")
        const left = end - now
        return left <= 0 ? Tr.t("Tugadi") : left < 3600 ? Tr.f("Jonli · %1 daq", Math.ceil(left / 60)) : Tr.f("Jonli · %1 soat", Math.round(left / 3600))
    }
    Item {               // a place tapped: its coordinates copied, or the map opened (as Telegram-iOS's sheet)
        id: placeMenu
        z: 30
        anchors.fill: parent
        visible: false
        property var loc: null
        property string name: ""
        readonly property string coords: loc ? loc.latitude.toFixed(6) + ", " + loc.longitude.toFixed(6) : ""
        function show(l, n) {
            loc = l
            name = n.split("\n")[0]
            visible = true
            placeCard.scale = 0.01
            placeGrow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: placeMenu.visible = false }
        Rectangle {
            id: placeCard
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: page.foot + 8
            width: parent.width - 32; height: placeChoices.height
            radius: 16
            color: Theme.menu
            transformOrigin: Item.Bottom
            layer.enabled: true
            ScaleAnimator { id: placeGrow; target: placeCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Column {
                id: placeChoices
                width: parent.width
                Text {
                    x: 16; width: parent.width - 32
                    topPadding: 12; bottomPadding: 8
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: (placeMenu.name && placeMenu.name !== Tr.t("Jonli joylashuv") ? placeMenu.name + "\n" : "") + placeMenu.coords
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: [{ t: Tr.t("Koordinatalarni nusxalash"), run: () => { page.copy(placeMenu.coords); page.toast(Tr.f("Nusxalandi: %1", placeMenu.coords)) } },
                            { t: Tr.t("Xaritada ochish (OpenStreetMap)"), run: () => Qt.openUrlExternally(
                                  "https://www.openstreetmap.org/?mlat=" + placeMenu.loc.latitude + "&mlon=" + placeMenu.loc.longitude
                                  + "#map=17/" + placeMenu.loc.latitude + "/" + placeMenu.loc.longitude) },
                            { t: Tr.t("Bekor qilish"), bold: true, run: () => {} }]
                    Rectangle {
                        required property var modelData
                        width: placeChoices.width; height: 50
                        color: placeHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.t
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 17; font.weight: parent.modelData.bold ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: placeHit
                            anchors.fill: parent
                            onClicked: {
                                const run = parent.modelData.run
                                placeMenu.visible = false
                                run()
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- a poll ----------------------------------------------------------------
    function vote(id, ids) {
        store.send({ "@type": "setPollAnswer", chat_id: chatId, message_id: id, option_ids: ids }, (r) => {
            if (r["@type"] === "error" && page)
                page.toast(r.message)
        })
    }
    // «Natijalarni ko'rish»: who chose what, each answer with its voters (getPollVoters, 50 each)
    function showVoters(id, poll) {
        voters.title = poll.question.text
        voters.rows = []
        voters.visible = true
        const order = poll.option_order && poll.option_order.length === poll.options.length ? poll.option_order
                                                                                            : poll.options.map((o, k) => k)
        const got = {}
        let left = order.length
        for (const k of order) {
            const o = poll.options[k]
            if (!o.voter_count) {
                got[k] = []
                if (--left === 0)
                    voters.fill(order, poll, got)
                continue
            }
            store.send({ "@type": "getPollVoters", chat_id: chatId, message_id: id, option_id: k, offset: 0, limit: 50 }, (r) => {
                got[k] = (r.voters || []).map((v) => store.me && v.voter_id.user_id === store.me.id ? Tr.t("Siz")
                                                   : store.senderName(v.voter_id, false) || Tr.t("Noma'lum"))
                if (--left === 0 && page)
                    voters.fill(order, poll, got)
            })
        }
    }
    Item {               // the voters, a card from the foot (as the ⏱'s choices, over the chat)
        id: voters
        z: 30
        anchors.fill: parent
        visible: false
        property string title: ""
        property var rows: []           // [{ head, n } or { name }]
        function fill(order, poll, got) {
            const out = []
            for (const k of order) {
                const o = poll.options[k]
                out.push({ head: o.text.text, n: o.voter_count, pc: o.vote_percentage })
                for (const name of got[k] || [])
                    out.push({ name: name })
            }
            rows = out
        }
        MouseArea { anchors.fill: parent; onClicked: voters.visible = false }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: Math.min(parent.height * 0.7, voterList.contentHeight + 60)
            radius: 16
            color: Theme.card
            MouseArea { anchors.fill: parent }
            Text {
                x: 16; y: 14
                width: parent.width - 32
                elide: Text.ElideRight
                text: voters.title
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            ListView {
                id: voterList
                y: 46
                width: parent.width; height: parent.height - y - 8
                clip: true
                model: voters.rows
                delegate: Item {
                    required property var modelData
                    width: voterList.width; height: modelData.head !== undefined ? 40 : 36
                    Text {
                        x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        width: parent.width - 32
                        elide: Text.ElideRight
                        text: modelData.head !== undefined ? modelData.head + " — " + modelData.pc + "%, " + Tr.n("%1 ta ovoz", modelData.n)
                                                           : modelData.name
                        color: modelData.head !== undefined ? Theme.grey : Theme.text
                        font.family: Theme.font; font.pixelSize: modelData.head !== undefined ? 13 : 16
                        font.weight: modelData.head !== undefined ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }
    Component { id: joinPage; JoinRequestsPage {} }
    PhotoViewer {
        id: viewer
        store: page.store
        chatId: page.chatId
        thread: page.thread
        locate: (id) => {           // a paged-to message's picture, when its bubble is on the page
            const it = page.shownAt(id)
            return it && it.media ? it.picFace : null
        }
        onPaged: (id) => page.unveil(id)        // (seen there, a spoiler is off here too, as on iOS)
        onSave: {
            const s = viewer.current
            if (s && s.file)
                store.saveFile(s.file, s.name, (text) => { if (page) page.toast(text) })
            else if (page.viewing)
                page.save(page.viewing)
        }
    }

    ForwardSheet {
        id: forwardSheet
        store: page.store
        onPicked: (to, title) => store.forward(to, page.chatId, page.forwarding, page.copying, (ok) => {
            if (page && ok)
                page.toast(Tr.f("Uzatildi: %1", title))
        })
    }

    GiftSheet {
        id: giftSheet
        store: page.store
        chatId: page.chatId
        onSay: (text) => page.toast(text)
    }

    PaidReactionSheet {
        id: paidSheet
        store: page.store
        chatId: page.chatId
        onSay: (text) => page.toast(text)
    }
    function askPaid(cost, run) {
        paidAlert.title = Tr.t("Pullik xabar")
        paidAlert.text = Tr.f("Ushbu xabarni yuborish uchun ⭐ %1 yulduz yechiladi. Davom etilsinmi?", store.count(cost))
        paidAlert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Yuborish"), run: run }]
        paidAlert.open = true
    }
    Alert { id: paidAlert; z: 32; anchors.fill: parent }

    AttachSheet {
        id: sheet
        rights: page.rights
        onRefused: (text) => page.toast(text)
        onSend: (picked, asFiles, apart) => {
            const doSend = () => {
                if (page.gap)
                    page.fresh()
                store.sendFiles(page.chatId, picked, page.textBarred ? null : page.fieldWords(), page.replying ? page.replying.id : 0,
                                asFiles, page.thread, page.silent, apart, page.directTopic, page.paidMessageStars)
                field.text = ""
                page.replying = null
                list.down = true
                list.positionViewAtBeginning()
            }
            if (page.paidMessageStars > 0)
                page.askPaid(page.paidMessageStars * Math.max(1, picked.length), doSend)
            else
                doSend()
        }
    }

    StickerPanel {
        id: emojiPanel
        z: 1
        store: page.store
        visible: page.panelOpen || (page.kb > 1 && !page.panelHold && osk.h === 0 && y < page.height)
        y: page.height - (page.panelOpen ? page.kb : Math.min(page.kb, page.panelH))
        width: page.width; height: page.panelH
        emojiOk: !page.textBarred
        stickersOk: !page.rights || page.rights.other
        barredText: page.allowedText
        onEmoji: (e) => page.putEmoji(e)
        onBackspace: page.eraseBack()
        onSticker: (st) => page.sendSticker(st)
        onGif: (a) => page.sendGif(a)
    }
    // an emoji where the cursor is (the field keeps its cursor when it has no focus)
    function putEmoji(e) {
        const at = field.cursorPosition
        field.insert(at, e)
        field.cursorPosition = at + e.length
    }
    // ⌫: the character before the cursor, an emoji whole (its surrogates, skin tone, ZWJ joins, VS16, a flag's pair)
    function eraseBack() {
        const t = field.text, at = field.cursorPosition
        if (at <= 0)
            return
        // by code points (Qt's JavaScript splits a string by UTF-16 units, Array.from too: half an emoji went)
        const before = []
        for (let k = 0; k < at; k++) {
            const c = t.charCodeAt(k)
            const pair = c >= 0xD800 && c <= 0xDBFF && k + 1 < at
            before.push(pair ? t.slice(k, k + 2) : t[k])
            if (pair)
                k++
        }
        const cp = (s) => s.length === 2 ? (s.charCodeAt(0) - 0xD800) * 0x400 + s.charCodeAt(1) - 0xDC00 + 0x10000 : s.charCodeAt(0)
        const tail = (s) => { const c = cp(s); return c === 0xFE0F || c === 0x20E3 || (c >= 0x1F3FB && c <= 0x1F3FF) || (c >= 0xE0020 && c <= 0xE007F) }
        const flag = (s) => { const c = cp(s); return c >= 0x1F1E6 && c <= 0x1F1FF }
        let n = 0
        while (before.length && tail(before[before.length - 1]))      // modifiers after it
            n += before.pop().length
        if (before.length) {
            const last = before.pop()
            n += last.length
            if (flag(last) && before.length && flag(before[before.length - 1]) && before.filter(flag).length % 2 === 1)
                n += before.pop().length
        }
        while (before.length >= 2 && cp(before[before.length - 1]) === 0x200D) {       // joined to the one before
            n += before.pop().length
            while (before.length && tail(before[before.length - 1]))
                n += before.pop().length
            if (before.length)
                n += before.pop().length
        }
        field.remove(at - n, at)
    }
    function sendSticker(st) {
        const doSend = () => {
            if (page.gap)
                page.fresh()
            store.sendSticker(page.chatId, st, page.replying ? page.replying.id : 0, page.thread, page.silent,
                              page.directTopic, page.paidMessageStars)
            page.replying = null
            list.down = true
            list.positionViewAtBeginning()
        }
        if (page.paidMessageStars > 0)
            askPaid(page.paidMessageStars, doSend)
        else
            doSend()
    }
    function sendGif(a) {
        const doSend = () => {
            if (page.gap)
                page.fresh()
            store.sendGif(page.chatId, a, page.replying ? page.replying.id : 0, page.thread, page.silent,
                          page.directTopic, page.paidMessageStars)
            page.replying = null
            list.down = true
            list.positionViewAtBeginning()
        }
        if (page.paidMessageStars > 0)
            askPaid(page.paidMessageStars, doSend)
        else
            doSend()
    }

    // the round video playing, its bubble gone off the screen: on in a 150 pt circle at the top right, 4 from the
    // edge and under the header (Telegram-iOS's OverlayInstantVideoNode in OverlayMediaControllerNode: location
    // (1, 0)), in from the right in 0.3 s; its shadow, the arc of how far; a tap holds it. Back on the screen, the
    // bubble goes on from there.
    Loader {
        id: pip
        z: 20
        active: page.roundId !== 0 && !page.roundSeen && page.player.roundPath !== ""
        x: page.width - 4 - 150; y: bar.height + pinBar.height + 4
        width: 150; height: 150
        sourceComponent: Item {
            Rectangle {     // its shadow
                x: -3; y: -1; width: parent.width + 6; height: parent.height + 6; radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.18)
            }
            InlineVideo {
                id: pipClip
                anchors.fill: parent
                path: page.player.roundPath
                radius: -1
                sound: true
                loop: false
                rate: page.player.rate
                running: !page.player.roundPaused
                resumeFrom: () => page.player.roundPos
                onEnded: page.player.step(false)
                Binding { when: pipClip.running; target: page.player; property: "roundPos"; value: pipClip.position }
                Binding { when: pipClip.duration > 0; target: page.player; property: "roundDur"; value: pipClip.duration }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.rgba(1, 1, 1, 0.6)
                    strokeWidth: 4
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 75; centerY: 75
                        radiusX: (150 - 12) / 2; radiusY: radiusX
                        startAngle: -90
                        sweepAngle: page.player.duration > 0 ? 360 * Math.min(1, page.player.position / page.player.duration) : 0
                    }
                }
            }
            Rectangle {     // held: ▶
                visible: page.player.roundPaused
                anchors.centerIn: parent
                width: 48; height: 48; radius: 24
                color: Qt.rgba(0, 0, 0, 0.45)
                Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1.5; width: 24; height: 24; name: "play"; color: "white" }
            }
            MouseArea { anchors.fill: parent; onClicked: page.player.toggle() }
        }
        onLoaded: inPip.restart()
        NumberAnimation { id: inPip; target: pip; property: "x"; from: page.width + 4; to: page.width - 4 - 150; duration: 300; easing.type: Easing.OutCubic }
    }

    Rectangle {          // a word that comes and goes (saved, no mic)
        id: toastBox
        z: 25
        anchors.horizontalCenter: parent.horizontalCenter
        y: bar.height + pinBar.height + 12
        width: Math.min(parent.width - 40, toastText.implicitWidth + 28); height: toastText.implicitHeight + 16
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.75)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }      // (an Animator would set it only at the end)
        Text {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.parent.width - 68)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
    }
    Timer { id: toastAway; interval: 2200; onTriggered: toastBox.opacity = 0 }

    // ---- a voice note ----------------------------------------------------------
    // held: it records (Ogg Opus, what Telegram's voice notes are); let go: it is sent, its
    // waveform worked out from the file (td.voice); slid left: thrown away
    property bool recording: false
    property bool recordLocked: false   // slid up to the lock: it goes on without the finger
    property real recordUp: 0           // how far up the finger has slid
    property bool toPreview: false      // stopped by ■: listened to before it goes
    property var preview: null          // { path, dur, wave } stopped, not yet sent
    // a round video (the mic tapped: the camera): what it shows comes from td.fakeCamera until there is a camera
    property bool roundMode: false
    property bool roundMirror: false    // the flip: the front camera's mirror
    property real roundStart: 0         // where the camera's file was when it started (ms)
    property real recordTook: 0         // how long the last one recorded (ms)
    property bool roundBusy: false      // its file being made (ffmpeg)
    property bool roundAudio: false     // the microphone recording beside it
    property var roundPreview: null     // { path, dur } made, not yet sent
    Timer {             // 60 s at most (Telegram's): it stops itself, to be listened to when locked
        interval: 250; repeat: true; running: page.recording && page.roundMode
        onTriggered: if (Date.now() - page.recordFrom >= 60000) page.stopVoice(false, page.recordLocked)
    }
    Connections {
        target: td
        function onRoundMade(path, secs) {
            page.roundBusy = false
            if (!path)
                return page.toast(Tr.t("Video xabarni tayyorlab bo'lmadi"))
            if (page.toPreview)
                page.roundPreview = { path: path, dur: secs }
            else
                page.sendRound(path, secs)
        }
    }
    MediaPlayer { id: hearing; audioOutput: AudioOutput {} }
    property real recordMs: 0
    property real recordSlide: 0
    property bool recordCancel: false
    property real recordFrom: 0
    MediaDevices { id: devices }
    Timer {
        interval: 100; repeat: true; running: page.recording
        onTriggered: page.recordMs = Date.now() - page.recordFrom
    }
    Timer {             // Telegram shows "ovozli xabar yozmoqda" while it lasts: say it again now and then
        interval: 4000; repeat: true; running: page.recording
        onTriggered: page.acting("chatActionRecordingVoiceNote")
    }
    function acting(what) {
        store.send({ "@type": "sendChatAction", chat_id: chatId, action: what ? { "@type": what } : null })
    }
    function startVoice() {
        if (roundMode && !td.fakeCamera) {
            toast(Tr.t("Kamera topilmadi — telefonning kamerasi hali ulanmagan"))
            return
        }
        if (devices.audioInputs.length === 0 && !roundMode) {      // (a round video goes without its sound)
            toast(Tr.t("Mikrofon topilmadi — telefonning mikrofoni hali ulanmagan"))
            return
        }
        if (Prefs.pauseMusic || player.kind !== "audio")     // (Ma'lumotlar va xotira's «Yozayotganda musiqani to'xtatish»)
            player.pause()
        recordCancel = false
        recordLocked = false
        toPreview = false
        recordUp = 0
        recordSlide = 0
        recordMs = 0
        recordFrom = Date.now()
        roundStart = roundMode ? roundCam.position : 0
        roundAudio = devices.audioInputs.length > 0
        recording = true
        if (roundAudio) {
            mic.device = devices.defaultAudioInput     // (the one there now: it was made with what there was then)
            recorder.outputLocation = "file://" + td.voicePath()
            recorder.record()
            meter.start()
        }
        acting(roundMode ? "chatActionRecordingVideoNote" : "chatActionRecordingVoiceNote")
    }
    // cancel: thrown away; listen: kept to be listened to first (■, locked)
    function stopVoice(cancel, listen) {
        recordCancel = cancel || Date.now() - recordFrom < 700     // a tap is not a voice note
        if (recordCancel && !cancel)
            toast(roundMode ? Tr.t("Video xabar uchun tugmani bosib turing") : Tr.t("Ovozli xabar uchun tugmani bosib turing"))
        toPreview = !!listen
        recordTook = Date.now() - recordFrom
        recording = false
        recordLocked = false
        recordUp = 0
        if (roundAudio) {
            recorder.stop()
            meter.stop()
        } else if (roundMode && !recordCancel) {        // no sound recorded: made at once, silent
            roundBusy = true
            td.roundNote(td.fakeCamera, roundStart, recordTook, roundMirror, "")
        }
        acting("")
    }
    function recorded() {
        const at = String(recorder.actualLocation).replace(/^file:\/\//, "")
        if (recordCancel || !at)
            return
        if (roundMode) {        // the camera's clip and this sound made one file (td.roundMade then)
            roundBusy = true
            td.roundNote(td.fakeCamera, roundStart, recordTook, roundMirror, at)
            return
        }
        const v = td.voice(at)
        if (toPreview) {
            preview = { path: at, dur: v.duration, wave: v.waveform }
            hearing.source = "file://" + at
            return
        }
        const doSend = () => {
            if (page.gap)
                page.fresh()
            store.sendVoice(chatId, at, v.duration, v.waveform, replying ? replying.id : 0, thread, silent, directTopic, paidMessageStars)
            replying = null
            list.down = true
            list.positionViewAtBeginning()
        }
        if (paidMessageStars > 0)
            askPaid(paidMessageStars, doSend)
        else
            doSend()
    }
    function sendPreview() {
        const p = preview
        dropPreview()
        const doSend = () => {
            if (page.gap)
                page.fresh()
            store.sendVoice(chatId, p.path, p.dur, p.wave, replying ? replying.id : 0, thread, silent, directTopic, paidMessageStars)
            replying = null
            list.down = true
            list.positionViewAtBeginning()
        }
        if (paidMessageStars > 0)
            askPaid(paidMessageStars, doSend)
        else
            doSend()
    }
    function dropPreview() {
        hearing.stop()
        hearing.source = ""
        preview = null
        roundPreview = null
    }
    function sendRound(path, secs) {
        const doSend = () => {
            if (page.gap)
                page.fresh()
            store.sendRound(chatId, path, secs, replying ? replying.id : 0, thread, silent, directTopic, paidMessageStars)
            replying = null
            list.down = true
            list.positionViewAtBeginning()
        }
        if (paidMessageStars > 0)
            askPaid(paidMessageStars, doSend)
        else
            doSend()
    }
    function sendRoundPreview() {
        const p = roundPreview
        roundPreview = null
        sendRound(p.path, p.dur)
    }
    CaptureSession {
        audioInput: AudioInput { id: mic }
        recorder: MediaRecorder {
            id: recorder
            mediaFormat {
                fileFormat: MediaFormat.Ogg
                audioCodec: MediaFormat.AudioCodec.Opus
            }
            audioChannelCount: 1
            audioSampleRate: 48000
            audioBitRate: 32000
            encodingMode: MediaRecorder.ConstantBitRateEncoding
            onRecorderStateChanged: if (recorderState === MediaRecorder.StoppedState) page.recorded()
            onErrorOccurred: (error, text) => {
                page.recording = false
                page.toast(Tr.f("Yozib bo'lmadi: %1", text))
            }
        }
    }

    Item {               // ⏱'s choices, over the field as Telegram-iOS's context menu
        id: timerMenu
        z: 30
        anchors.fill: parent
        visible: false
        function show() {
            page.keyboardDown()
            visible = true
            card.scale = 0.01
            grow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: timerMenu.visible = false }
        Rectangle {
            id: card
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.bottom: parent.bottom; anchors.bottomMargin: page.foot + 8
            width: 230; height: choices.height
            radius: 16
            color: Theme.menu
            transformOrigin: Item.BottomRight
            layer.enabled: true
            ScaleAnimator { id: grow; target: card; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Column {
                id: choices
                width: parent.width
                Text {
                    x: 16; width: parent.width - 32
                    topPadding: 10; bottomPadding: 6
                    wrapMode: Text.Wrap
                    text: Tr.t("Yangi xabarlar shuncha vaqtdan keyin o'chadi")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: [0, 86400, 604800, 2678400]
                    Rectangle {
                        required property int modelData
                        width: choices.width; height: 44
                        color: choiceHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData ? store.lasting(parent.modelData) : Tr.t("O'chirilgan")
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        Text {
                            visible: page.autoDelete === parent.modelData
                            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            text: "✓"
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: choiceHit
                            anchors.fill: parent
                            onClicked: {
                                timerMenu.visible = false
                                if (parent.modelData !== page.autoDelete)
                                    page.setAutoDelete(parent.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    Item {               // the picked ones deleted: for us, or for everyone too (as the ⏱'s choices)
        id: deleteMenu
        z: 30
        anchors.fill: parent
        visible: false
        // what TDLib lets with all of them: both, or only one of the two
        readonly property var choices: {
            const all = page.pickedCan("can_be_deleted_for_all_users"), self = page.pickedCan("can_be_deleted_only_for_self")
            return all && self ? [{ t: Tr.t("Hamma uchun o'chirish"), everyone: true }, { t: Tr.t("Men uchun o'chirish"), everyone: false }]
                 : all ? [{ t: Tr.t("O'chirish"), everyone: true }] : [{ t: Tr.t("Men uchun o'chirish"), everyone: false }]
        }
        function show() {
            visible = true
            delCard.scale = 0.01
            delGrow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: deleteMenu.visible = false }
        Rectangle {
            id: delCard
            x: 10
            anchors.bottom: parent.bottom; anchors.bottomMargin: page.foot + 8
            width: 250; height: delChoices.height
            radius: 16
            color: Theme.menu
            transformOrigin: Item.BottomLeft
            layer.enabled: true
            ScaleAnimator { id: delGrow; target: delCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Column {
                id: delChoices
                width: parent.width
                Text {
                    x: 16; width: parent.width - 32
                    topPadding: 10; bottomPadding: 6
                    wrapMode: Text.Wrap
                    text: page.pickedIds.length > 1 ? Tr.n("%1 ta xabar o'chirilsinmi?", page.pickedIds.length) : Tr.t("Xabar o'chirilsinmi?")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Repeater {
                    model: deleteMenu.choices
                    Rectangle {
                        required property var modelData
                        width: delChoices.width; height: 44
                        color: delHit.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.t
                            color: Theme.danger
                            font.family: Theme.font; font.pixelSize: 16
                        }
                        MouseArea {
                            id: delHit
                            anchors.fill: parent
                            onClicked: {
                                deleteMenu.visible = false
                                page.deletePicked(parent.modelData.everyone)
                            }
                        }
                    }
                }
            }
        }
    }

    Item {               // Shikoyat qilish: why (Telegram's options), or a few words, a step at a time
        id: reportMenu
        z: 30
        anchors.fill: parent
        visible: false
        property var step: null         // { ids, title, options } or { ids, option, optional }
        function ask(st) {
            step = st
            why.text = ""
            visible = true
            reportCard.scale = 0.01
            reportGrow.start()
            if (!st.options)
                why.forceActiveFocus()
        }
        function close() {
            visible = false
            why.focus = false
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.25) }
        MouseArea { anchors.fill: parent; onClicked: reportMenu.close() }
        Rectangle {
            id: reportCard
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(60, (parent.height - page.kb - height) / 2)
            width: Math.min(parent.width - 48, 300); height: Math.min(steps.height + 48, parent.height - page.kb - 120)
            radius: 16
            clip: true
            color: Theme.menu
            layer.enabled: true
            ScaleAnimator { id: reportGrow; target: reportCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            MouseArea { anchors.fill: parent }      // (not through to the shade, which closes it)
            Flickable {          // (a long list of reasons scrolls; «Bekor qilish» stays under it)
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: reportCancel.top }
                contentHeight: steps.height
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Column {
                    id: steps
                    width: reportCard.width
                    readonly property var st: reportMenu.step || {}
                    Text {
                        x: 16; width: parent.width - 32
                        topPadding: 14; bottomPadding: 8
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        text: steps.st.options ? (steps.st.title || Tr.t("Shikoyat sababi")) : Tr.t(steps.st.optional ? "Batafsil yozing (ixtiyoriy)" : "Batafsil yozing")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: steps.st.options || []
                        Rectangle {
                            required property var modelData
                            width: steps.width; height: Math.max(44, optText.implicitHeight + 20)
                            color: optHit.pressed ? Theme.highlight : "transparent"
                            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                            Text {
                                id: optText
                                x: 16; width: parent.width - 48
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.Wrap
                                text: parent.modelData.text
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 16
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "›"; color: Theme.grey; font.pixelSize: 20
                            }
                            MouseArea {
                                id: optHit
                                anchors.fill: parent
                                onClicked: {
                                    const ids = steps.st.ids
                                    reportMenu.close()
                                    page.report(ids, parent.modelData.id, "")
                                }
                            }
                        }
                    }
                    Rectangle {          // the words, when Telegram asks for them
                        visible: !steps.st.options
                        x: 16; width: parent.width - 32
                        height: visible ? Math.max(44, why.contentHeight + 20) : 0
                        radius: 10
                        color: Theme.field
                        TextEdit {
                            id: why
                            x: 10; y: 10; width: parent.width - 20
                            wrapMode: TextEdit.Wrap
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }
                    }
                    Rectangle {
                        visible: !steps.st.options
                        width: steps.width; height: visible ? 52 : 0
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Yuborish")
                            color: steps.st.optional || why.text.trim() ? Theme.accent : Theme.grey
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!steps.st.optional && !why.text.trim())
                                    return
                                const st = steps.st
                                reportMenu.close()
                                page.report(st.ids, st.option, why.text.trim())
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: reportCancel
                anchors.bottom: parent.bottom
                width: parent.width; height: 48
                color: cancelHit.pressed ? Theme.highlight : Theme.menu
                Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 17
                }
                MouseArea { id: cancelHit; anchors.fill: parent; onClicked: reportMenu.close() }
            }
        }
    }

    Item {               // ⋯ of the translation row: hide it for this chat (Telegram-iOS: "Tarjima qilmaslik")
        id: transMenu
        z: 30
        anchors.fill: parent
        visible: false
        function show() {
            visible = true
            transCard.scale = 0.01
            transGrow.start()
        }
        MouseArea { anchors.fill: parent; onClicked: transMenu.visible = false }
        Rectangle {
            id: transCard
            anchors.right: parent.right; anchors.rightMargin: 16
            y: pinBar.y + pinBar.height
            width: 250; height: 44
            radius: 16
            color: Theme.menu
            transformOrigin: Item.TopRight
            layer.enabled: true
            ScaleAnimator { id: transGrow; target: transCard; from: 0.01; to: 1; duration: 420
                            easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: hideHit.pressed ? Theme.highlight : "transparent"
            }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Bu chatni tarjima qilmaslik")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
            }
            MouseArea {
                id: hideHit
                anchors.fill: parent
                onClicked: {
                    transMenu.visible = false
                    page.setTranslating(false)
                    store.send({ "@type": "toggleChatIsTranslatable", chat_id: page.chatId, is_translatable: false })
                }
            }
        }
    }

    FontMetrics {        // a reaction's chip, measured before it is made (the bubble's width)
        id: chipMetrics
        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
    }

    MessageMenu {
        id: menu
        behind: content
        ceiling: bar.height
        floor: page.height
        onReacted: (emoji) => {
            if (emoji === "⭐") {
                const i = page.indexOf(page.reacting)
                let paid = null
                if (i >= 0) {
                    const list = JSON.parse(messages.get(i).reacts || "[]")
                    paid = list.find((r) => r.paid)
                }
                paidSheet.show(page.reacting, paid ? (paid.reactors || []) : [], !!(paid && paid.mine))
                return
            }
            store.react(page.chatId, page.reacting, emoji, menu.chosen.indexOf(emoji) < 0)
        }
    }
}
