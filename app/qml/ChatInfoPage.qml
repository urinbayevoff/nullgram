// About a chat (Telegram-iOS's PeerInfoScreen): its picture, name and status, buttons for its
// sound and a search in it, what is known of it (the number, the username, the bio; a group's or
// a channel's description and link), then a group's members (a tap opens a chat with one) and what
// was sent there by kind: pictures and videos in a grid (a tap shows one full screen), files, links,
// voice notes (a tap goes back to the chat, at it).
import QtQuick
import QtQuick.Effects
import QtQuick.Window

SubPage {
    id: page
    title: ""
    property var chatId: 0
    property Item chatPage: null        // the chat under this page (its search, its messages)
    property int changed: 0             // the chat changed (TDLib changes it in place)
    readonly property var chat: (changed, store.seen, store.chats[chatId])
    readonly property string kind: chat ? chat.type["@type"] : ""
    readonly property var user: kind === "chatTypePrivate" ? (store.seen, store.users[chat.type.user_id]) : null
    readonly property var group: !chat ? null
        : kind === "chatTypeSupergroup" ? store.groups["s" + chat.type.supergroup_id]
        : kind === "chatTypeBasicGroup" ? store.groups["b" + chat.type.basic_group_id] : null
    property var full: null             // userFullInfo, supergroupFullInfo or basicGroupFullInfo
    property string photo: ""
    property real now: Date.now() / 1000
    readonly property bool saved: store.isSaved(chat)
    readonly property bool isGroup: kind === "chatTypeBasicGroup" || (kind === "chatTypeSupergroup" && !chat.type.is_channel)
    readonly property bool isChannel: kind === "chatTypeSupergroup" && !!chat.type.is_channel
    readonly property bool muted: (changed, !!chat && chat.notification_settings.mute_for > 0)
    readonly property var directChatId: full && full.direct_messages_chat_id ? full.direct_messages_chat_id : 0
    readonly property bool canManageGifts: isChannel && runs && (myStatus["@type"] === "chatMemberStatusCreator"
                                                                  || (!!myStatus.rights && !!myStatus.rights.can_post_messages))
    readonly property bool canDirectAdmin: isChannel && runs && (myStatus["@type"] === "chatMemberStatusCreator"
                                                                 || (!!myStatus.rights && !!myStatus.rights.can_manage_direct_messages))
    readonly property var giftOwnerId: isChannel ? { "@type": "messageSenderChat", chat_id: chatId }
                                       : user ? { "@type": "messageSenderUser", user_id: user.id } : null
    Connections {
        target: store
        function onChatChanged(id) { if (id === page.chatId) page.changed++ }
    }

    Component.onCompleted: {
        if (!chat)
            return
        const big = chat.photo && chat.photo.big
        if (big)
            store.fetch(big, 8, (path) => page.photo = path)
        loadFull()
        for (const t of tabs)
            if (t.filter)
                count(t)
        load(tabs[0])
        loadPictures()
        overlay = overlayMaker.createObject(page)
    }
    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }
    function loadFull() {
        const want = user ? { "@type": "getUserFullInfo", user_id: user.id }
            : kind === "chatTypeSupergroup" ? { "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }
            : kind === "chatTypeBasicGroup" ? { "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id } : null
        if (want)
            store.send(want, (r) => {
                if (!page || r["@type"] === "error")
                    return
                page.full = r
                page.countGifts()
            })
    }
    onVisibleChanged: if (visible && full && user) loadFull()     // (back from the contact's page: its notes)
    readonly property bool follows: !user       // (a basic group made a supergroup on a page over this: now that)
    onChatIdChanged: if (chat) loadFull()

    function mute() {
        const n = Object.assign({}, chat.notification_settings)
        n["@type"] = "chatNotificationSettings"
        n.use_default_mute_for = false
        n.mute_for = muted ? 0 : 2147483647
        store.send({ "@type": "setChatNotificationSettings", chat_id: chatId, notification_settings: n }, store.check)
    }
    // back to the chat: searching in it, or at a message
    function search() {
        nav.pop()
        if (chatPage) {
            chatPage.searching = true
            chatPage.focusFind()
        }
    }
    function toMessage(id) {
        nav.pop()
        if (chatPage)
            chatPage.goTo(id)
    }

    // ---- «yana» (Telegram-iOS's «more» on a user's page): block them, clear the chat ----
    readonly property bool other: !!user && !saved && !(store.me && user.id === store.me.id)
    readonly property bool blocked: (changed, !!chat && !!chat.block_list)
    readonly property bool bot: !!user && user.type["@type"] === "userTypeBot"
    readonly property string firstName: user ? user.first_name || store.title(chat) : ""
    readonly property bool contact: (changed, store.seen, !!user && !!user.is_contact)
    readonly property bool deleted: !!user && user.type["@type"] === "userTypeDeleted"
    // gifts they take at all (userFullInfo.gift_settings: iOS leaves «Send a Gift» out when none)
    readonly property bool giftable: {
        if (!other || bot || deleted)
            return false
        const g = full && full.gift_settings ? full.gift_settings.accepted_gift_types : null
        return !g || g.unlimited_gifts || g.limited_gifts || g.upgraded_gifts || g.premium_subscription
    }
    readonly property int autoDelete: (changed, chat ? chat.message_auto_delete_time || 0 : 0)
    // Telegram-iOS's «more» for a user (PeerInfoScreenPerformButtonAction): Change Wallpaper (WallpaperPage for this
    // chat), Share Contact, Send a Gift, Enable/Adjust Auto-Delete, Clear Messages, Block User (Secret Chat: not here)
    function moreMenu() {
        const out = []
        if (!deleted)
            out.push({ t: Tr.t("Fon rasmini o'zgartirish"), run: () => page.openPage("WallpaperPage.qml", { home: page }) })
        if (contact && user.phone_number && !bot)
            out.push({ t: Tr.t("Kontaktni ulashish"), run: () => page.overlay.forward.show() })
        if (giftable)
            out.push({ t: Tr.t("Hadya yuborish"), run: () => page.overlay.gift.show() })
        if (!deleted)
            out.push({ t: autoDelete ? Tr.f("Avto-o'chirishni sozlash (%1)", store.lasting(autoDelete)) : Tr.t("Avto-o'chirishni yoqish"),
                       run: () => page.autoDeleteMenu() })
        out.push({ t: Tr.t("Xabarlarni tozalash"), run: () => page.askClear() })
        out.push({ t: Tr.t(blocked ? (bot ? "Botni qayta ishga tushirish" : "Blokdan chiqarish") : bot ? "Botni to'xtatish" : "Bloklash"),
                   red: !blocked, run: () => blocked ? page.block(false) : page.askBlock() })
        overlay.ask("", out)
    }
    // its second level (iOS pushes it in the same menu): 1 day, 1 week, 1 month; Disable when on
    function autoDeleteMenu() {
        Qt.callLater(() => {
            const out = [86400, 604800, 2678400].map((secs) => ({ t: store.lasting(secs) + (secs === page.autoDelete ? "  ✓" : ""),
                                                                 run: () => page.setAutoDelete(secs) }))
            if (page.autoDelete)
                out.push({ t: Tr.t("O'chirib qo'yish"), red: true, run: () => page.setAutoDelete(0) })
            page.overlay.ask(Tr.t("Bu chatda yuborilgan xabarlarni ma'lum vaqtdan keyin avtomatik o'chirish."), out)
        })
    }
    function setAutoDelete(secs) {
        store.send({ "@type": "setChatMessageAutoDeleteTime", chat_id: chatId, message_auto_delete_time: secs }, (r) => {
            if (r["@type"] === "error")
                page.overlay.say(Tr.t("O'zgartirib bo'lmadi"))
            else
                page.overlay.say(secs ? Tr.f("Yangi xabarlar %1dan keyin o'chadi", store.lasting(secs)) : Tr.t("Avtomatik o'chirish o'chirildi"))
        })
    }
    // the contact to another chat (iOS's share screen; ours, the forward sheet): inputMessageContact
    function shareTo(to, title) {
        store.send({ "@type": "sendMessage", chat_id: to, input_message_content: { "@type": "inputMessageContact", contact: {
                         "@type": "contact", phone_number: user.phone_number, first_name: user.first_name || "",
                         last_name: user.last_name || "", vcard: "", user_id: user.id } } }, (r) => {
            if (r["@type"] === "error")
                return page.overlay.say(r.message)
            const saved = store.isSaved(store.chats[to])
            page.overlay.say(saved ? Tr.t("Kontakt Saqlangan xabarlarga uzatildi") : Tr.f("Kontakt %1ga uzatildi", title))
        })
    }
    // ---- their contact's page (Tahrirlash on the bar; «Kontaktlarga qo'shish» in the card) ----
    property Component contactMaker: null
    function editContact(adding) {
        if (!contactMaker)
            contactMaker = Qt.createComponent("ContactPage.qml")
        const p = nav.push(contactMaker, { userId: user.id, full: full, adding: adding })
        if (p)
            p.said.connect((text) => { if (page && page.overlay) page.overlay.say(text) })
    }
    // a channel or group we run: «Tahrirlash» opens its editing (ChannelEditPage); a contact's: the contact
    readonly property var myStatus: group ? group.status : null
    readonly property bool runs: !!myStatus && (myStatus["@type"] === "chatMemberStatusCreator"
                                                || myStatus["@type"] === "chatMemberStatusAdministrator")
    action: contact && other ? Tr.t("Tahrirlash") : runs ? Tr.t("Tahrirlash") : ""
    onActed: runs && !user ? openPage("ChannelEditPage.qml", {}) : editContact(false)
    function openPage(file, props) {
        const c = Qt.createComponent(file)
        if (c.status === Component.Error)
            return console.warn("nullgram:", c.errorString())
        props.chatId = chatId
        return nav.push(c, props)
    }
    // ---- what is known of a user: copied with a tap ----
    TextEdit { id: clip; visible: false }      // the clipboard's way in
    function copy(text, said) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        overlay.say(said)
    }
    // +998 90 123 45 67 (Uzbek numbers grouped as written there; the others whole)
    function phoneText(n) {
        const m = /^998(\d{2})(\d{3})(\d{2})(\d{2})$/.exec(n)
        return m ? "+998 " + m.slice(1).join(" ") : "+" + n
    }
    function age(b) {
        const d = new Date()
        let n = d.getFullYear() - b.year
        if (d.getMonth() + 1 < b.month || (d.getMonth() + 1 === b.month && d.getDate() < b.day))
            n--
        return n
    }
    function tapFact(f) {
        if (f.act === "phone")
            overlay.ask(f.v, [{ t: Tr.t("Nusxa olish"), run: () => page.copy(f.v, Tr.t("Telefon raqami nusxalandi")) }])
        else if (f.act === "username") {
            const name = f.v.substr(1)
            overlay.ask(f.v, [{ t: Tr.t("Havolani nusxa olish"), run: () => page.copy("https://t.me/" + name, Tr.t("Havola nusxalandi")) },
                              { t: Tr.t("Foydalanuvchi nomini nusxa olish"), run: () => page.copy(f.v, Tr.t("Foydalanuvchi nomi nusxalandi")) }])
        } else if (f.act === "gift")
            overlay.gift.show()
        else if (f.act === "add")
            editContact(true)
        else if (f.act === "block")
            askBlock()
        else if (f.act === "unblock")
            block(false)
        else if (f.act === "link")
            copy(f.v.startsWith("http") ? f.v : "https://" + f.v, Tr.t("Havola nusxalandi"))
    }
    // their (or the group's, the channel's) t.me link as a code, over the whole window
    property Item qr: null
    function showQr(name) {
        if (!qr)
            qr = qrMaker.createObject(page.nav || page)
        qr.username = name
        qr.photo = page.photo || (chat ? store.photoPath(chat) : "")
        qr.show()
    }
    Component.onDestruction: if (qr) qr.destroy()
    Component {
        id: qrMaker
        QrSheet {
            z: 100
            store: page.store
            letters: page.chat ? page.store.letters(page.chat.title) : ""
            tint: page.store.tints[Math.abs(page.chatId) % page.store.tints.length]
            onCopied: page.overlay.say(Tr.t("Havola nusxalandi"))
        }
    }
    function askBlock() {
        overlay.ask(Tr.f(bot ? "%1 botini to'xtatasizmi? U sizga boshqa yoza olmaydi."
                             : "%1 sizga Telegram'da yoza va qo'ng'iroq qila olmasinmi?", store.title(chat)),
                    [{ t: Tr.f(bot ? "%1ni to'xtatish" : "%1ni bloklash", firstName), red: true, run: () => page.block(true) }])
    }
    function block(on) {
        store.send({ "@type": "setMessageSenderBlockList", sender_id: { "@type": "messageSenderUser", user_id: user.id },
                     block_list: on ? { "@type": "blockListMain" } : null }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: block", r.code, r.message)
                page.overlay.say(r.message)
            } else
                page.overlay.say(Tr.f(on ? "%1 bloklandi" : "%1 blokdan chiqarildi", page.firstName))
        })
    }
    function askClear() {
        const out = []
        if (chat.can_be_deleted_for_all_users)
            out.push({ t: Tr.f("Men va %1 uchun o'chirish", firstName), red: true, run: () => page.clearAll(true) })
        if (chat.can_be_deleted_only_for_self)
            out.push({ t: Tr.t("Faqat men uchun o'chirish"), red: true, run: () => page.clearAll(false) })
        overlay.ask(Tr.t("Chatdagi barcha xabarlarni o'chirmoqchimisiz?"), out)
    }
    function clearAll(both) {
        store.send({ "@type": "deleteChatHistory", chat_id: chatId, remove_from_chat_list: false, revoke: both }, (r) => {
            if (r["@type"] === "error")
                console.warn("nullgram: clear", r.code, r.message)
            else {
                page.found = []
                page.counts = ({})
                page.overlay.say(Tr.t("Xabarlar o'chirildi"))
            }
        })
    }

    // ---- a group's members, then what was sent there by kind, and received gifts ----
    readonly property var tabs: (isGroup ? [{ key: "members", name: Tr.t("A'zolar") }] : []).concat([
        { key: "media", name: Tr.t("Media"), filter: "searchMessagesFilterPhotoAndVideo" },
        { key: "files", name: Tr.t("Fayllar"), filter: "searchMessagesFilterDocument" },
        { key: "links", name: Tr.t("Havolalar"), filter: "searchMessagesFilterUrl" },
        { key: "voice", name: Tr.t("Ovozli"), filter: "searchMessagesFilterVoiceNote" },
        { key: "music", name: Tr.t("Musiqa"), filter: "searchMessagesFilterAudio" }
    ]).concat(isChannel || (other && !bot && !deleted) ? [{ key: "gifts", name: Tr.t("Hadyalar") }] : [])
    property var counts: ({})           // tab key -> how many
    property string tab: "media"
    property var found: []              // the shown tab's messages, newest first (members: online first; gifts: receivedGift[])
    property bool more: false           // older ones not yet asked
    property bool loading: false
    property string giftOffset: ""
    property var giftPaths: ({})        // sticker file id -> local path
    property int giftGot: 0
    readonly property var shownTabs: tabs.filter((t) => counts[t.key] > 0)

    function hexColor(c) { return "#" + ((c >>> 0) & 0xffffff).toString(16).padStart(6, "0") }
    function giftSticker(g) {
        if (!g || !g.gift || !g.gift.gift)
            return null
        return g.gift["@type"] === "sentGiftUpgraded"
            ? (g.gift.gift.model ? g.gift.gift.model.sticker : null)
            : g.gift.gift.sticker
    }
    function wantGift(f) {
        if (!f || giftPaths[f.id] !== undefined)
            return
        giftPaths[f.id] = ""
        store.fetch(f, 2, (path) => {
            if (!page)
                return
            page.giftPaths[f.id] = path
            page.giftGot++
        })
    }
    function countGifts() {
        if (!giftOwnerId || (!isChannel && !(other && !bot && !deleted)))
            return
        if (!canManageGifts && full && full.gift_count === 0) {
            counted("gifts", 0)
            return
        }
        store.send({ "@type": "getReceivedGifts", business_connection_id: "", owner_id: giftOwnerId,
                     collection_id: 0, exclude_unsaved: !canManageGifts, exclude_saved: false,
                     exclude_unlimited: false, exclude_upgradable: false, exclude_non_upgradable: false,
                     exclude_upgraded: false, exclude_without_colors: false, exclude_hosted: false,
                     sort_by_price: false, offset: "", limit: 1 }, (r) => {
            if (page && r["@type"] === "receivedGifts")
                page.counted("gifts", r.total_count)
        })
    }
    function reloadGifts() {
        countGifts()
        if (tab === "gifts") {
            const t = tabs.find((x) => x.key === "gifts")
            if (t)
                load(t)
        }
    }
    function moreGifts() {
        if (!giftOwnerId) {
            loading = false
            more = false
            return
        }
        store.send({ "@type": "getReceivedGifts", business_connection_id: "", owner_id: giftOwnerId,
                     collection_id: 0, exclude_unsaved: !canManageGifts, exclude_saved: false,
                     exclude_unlimited: false, exclude_upgradable: false, exclude_non_upgradable: false,
                     exclude_upgraded: false, exclude_without_colors: false, exclude_hosted: false,
                     sort_by_price: false, offset: giftOffset, limit: 30 }, (r) => {
            if (!page || page.tab !== "gifts")
                return
            page.loading = false
            if (r["@type"] !== "receivedGifts") {
                page.more = false
                return
            }
            const got = r.gifts || []
            page.found = page.found.concat(got)
            page.giftOffset = r.next_offset || ""
            page.more = page.giftOffset !== "" && got.length > 0
            page.counted("gifts", r.total_count)
        })
    }

    function count(t) {
        store.send({ "@type": "getChatMessageCount", chat_id: chatId, filter: { "@type": t.filter },
                     topic_id: null, return_local: false }, (r) => {
            if (r["@type"] === "count")
                page.counted(t.key, r.count)
        })
    }
    function counted(key, n) {
        const c = Object.assign({}, counts)
        c[key] = n
        counts = c
        if (counts[tab] === 0) {        // the first one with something in it
            const first = shownTabs[0]
            if (first)
                load(first)
        }
    }
    function load(t) {
        tab = t.key
        found = []
        giftOffset = ""
        more = true
        loading = false
        older()
    }
    function older() {
        if (loading || !more)
            return
        loading = true
        if (tab === "members") {
            moreMembers()
            return
        }
        if (tab === "gifts") {
            moreGifts()
            return
        }
        const t = tabs.find((x) => x.key === tab)
        const from = found.length ? found[found.length - 1].id : 0
        store.send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: null, query: "", sender_id: null,
                     from_message_id: from, offset: 0, limit: 60, filter: { "@type": t.filter } }, (r) => {
            if (page.tab !== t.key)
                return
            if (r["@type"] !== "foundChatMessages")
                console.warn("nullgram: info", t.key, JSON.stringify(r))
            page.loading = false
            const got = (r.messages || []).filter((m) => !page.found.some((f) => f.id === m.id))
            page.found = page.found.concat(got)
            page.more = got.length > 0 && !!r.next_from_message_id && page.found.length < (page.counts[t.key] || Infinity)
        })
    }

    // a supergroup's members 200 at a time (its count comes with them), a basic group's all at once
    function moreMembers() {
        const basic = kind === "chatTypeBasicGroup"
        store.send(basic ? { "@type": "getBasicGroupFullInfo", basic_group_id: chat.type.basic_group_id }
                         : { "@type": "getSupergroupMembers", supergroup_id: chat.type.supergroup_id,
                             filter: { "@type": "supergroupMembersFilterRecent" }, offset: found.length, limit: 200 }, (r) => {
            if (page.tab !== "members")
                return
            page.loading = false
            if (r["@type"] === "error") {       // hidden from us
                console.warn("nullgram: members", r.code, r.message)
                page.more = false
                page.counted("members", 0)
                return
            }
            const key = (m) => m.member_id.user_id || m.member_id.chat_id
            const got = (r.members || []).filter((m) => !page.found.some((f) => key(f) === key(m)))
            page.found = page.found.concat(got).sort((a, b) => page.seenRank(b) - page.seenRank(a))
            const total = basic ? page.found.length : r.total_count
            page.more = !basic && got.length > 0 && page.found.length < total
            page.counted("members", total)
        })
    }
    // the order Telegram lists members in: I, those online, then by when they were last here
    function seenRank(m) {
        const u = m.member_id["@type"] === "messageSenderUser" ? store.users[m.member_id.user_id] : null
        if (!u)
            return 0
        if (store.me && u.id === store.me.id)
            return 4e9
        const s = u.status
        switch (s["@type"]) {
        case "userStatusOnline": return s.expires > now ? 3e9 : s.expires
        case "userStatusOffline": return s.was_online
        case "userStatusRecently": return 3
        case "userStatusLastWeek": return 2
        case "userStatusLastMonth": return 1
        }
        return 0
    }
    property Component chatPageMaker: null
    function chatWith(userId) {
        store.chatWith(userId, (id) => {
            if (!page.chatPageMaker)
                page.chatPageMaker = Qt.createComponent("ChatPage.qml")
            page.nav.push(page.chatPageMaker, { chatId: id })
        })
    }

    // a message's picture for the grid: the smallest size not under the cell, else a video's still
    function cellFile(m) {
        const c = m.content
        if (c["@type"] === "messagePhoto") {
            const sizes = c.photo.sizes
            for (const z of sizes)
                if (z.width >= 240)
                    return z.photo
            return sizes.length ? sizes[sizes.length - 1].photo : null
        }
        const v = c.video
        return v && v.thumbnail && v.thumbnail.format["@type"] === "thumbnailFormatJpeg" ? v.thumbnail.file : null
    }
    function mini(m) {
        const c = m.content
        const t = c["@type"] === "messagePhoto" ? c.photo.minithumbnail : c.video ? c.video.minithumbnail : null
        return t ? t.data : ""
    }
    function clock(s) {
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    // the text's first link (a link entity, else one written out)
    function link(m) {
        const t = m.content.text || m.content.caption
        if (!t)
            return ""
        for (const e of t.entities || []) {
            if (e.type["@type"] === "textEntityTypeTextUrl")
                return e.type.url
            if (e.type["@type"] === "textEntityTypeUrl")
                return t.text.substr(e.offset, e.length)
        }
        const w = m.content.link_preview
        return w ? w.url : ""
    }

    // ---- one of the grid full screen (Telegram's gallery) ----
    property Item overlay: null         // the viewer and its note, over the page (not in its list)
    property var shown: null            // what the viewer shows: { file, name } (its ↓ saves it)
    // a spoiler's cell blurred under dust until it is seen full screen (Telegram-iOS's shared media)
    property var unveiled: ({})
    property int unveiledTick: 0
    function unveil(id) {
        if (!unveiled[id]) {
            unveiled[id] = true
            unveiledTick++
        }
    }
    function view(cell) {
        const m = cell.modelData, c = m.content, v = overlay.viewer
        unveil(m.id)
        const side = Math.round(grid.side), small = mini(m)
        const src = cell.path ? "image://pic/0/" + side + "/" + cell.path
                  : small ? "image://pic/0/" + side + "/mini/" + small : ""
        if (c["@type"] === "messagePhoto") {
            const big = c.photo.sizes[c.photo.sizes.length - 1]
            shown = { file: big.photo, name: "photo_" + m.id + ".jpg" }
            v.show(cell, big.height / big.width, src, "", m.id)
            store.fetch(big.photo, 32, (path) => { if (page && v.open) v.better(path) })
            return
        }
        const video = c.video
        if (!video || cell.loading)
            return
        shown = { file: video.video, name: video.file_name || "video_" + m.id + ".mp4" }
        const aspect = video.width ? video.height / video.width : 9 / 16
        cell.loading = !video.video.local.is_downloading_completed
        store.fetch(video.video, 32, (path) => {
            cell.loading = false
            if (page && page.nav.topPage === page)
                v.show(cell, aspect, src, path, m.id)
        })
    }
    function save() {
        const s = overlay.viewer.current
        const f = s && s.file ? { file: s.file, name: s.name } : shown
        if (f)
            store.fetch(f.file, 32, (path) => {
                const to = td.save(path, f.name)
                if (page)
                    page.overlay.say(to ? Tr.f("Saqlandi: Downloads/%1", to.split("/").pop()) : Tr.t("Saqlab bo'lmadi"))
            })
    }
    // the shell's back: the viewer closes first
    function dismiss() {
        if (qr && qr.open) {
            qr.hide()
            return true
        }
        if (overlay && overlay.giftView.open) {
            overlay.giftView.backOne()
            return true
        }
        if (overlay && overlay.gift.open) {
            overlay.gift.backOne()
            return true
        }
        if (overlay && overlay.forward.open) {
            overlay.forward.close()
            return true
        }
        if (overlay && overlay.sheet.open) {
            overlay.sheet.open = false
            return true
        }
        if (overlay && overlay.viewer.open) {
            overlay.viewer.close()
            return true
        }
        return false
    }
    Component {
        id: overlayMaker
        Item {
            anchors.fill: parent
            z: 20
            readonly property alias viewer: viewer
            function say(text) {
                note.text = text
                noteBox.opacity = 1
                noteAway.restart()
            }
            // iOS's action sheet: the choices on a card at the foot, «Bekor qilish» on its own under them
            function ask(title, choices) {
                sheet.title = title
                sheet.choices = choices
                sheet.open = true
            }
            readonly property alias sheet: sheet
            readonly property alias forward: forward
            readonly property alias gift: gift
            readonly property alias giftView: giftView
            ForwardSheet {
                id: forward
                z: 26
                store: page.store
                onPicked: (to, title) => page.shareTo(to, title)
            }
            GiftSheet {
                id: gift
                z: 26
                store: page.store
                chatId: page.chatId
                onSay: (text) => parent.say(text)
            }
            GiftViewSheet {
                id: giftView
                z: 28
                store: page.store
                onSay: (text) => parent.say(text)
                onChanged: page.reloadGifts()
                onOpenSender: (s) => {
                    if (s["@type"] === "messageSenderUser")
                        page.chatWith(s.user_id)
                    else if (s["@type"] === "messageSenderChat") {
                        if (!page.chatPageMaker)
                            page.chatPageMaker = Qt.createComponent("ChatPage.qml")
                        page.nav.push(page.chatPageMaker, { chatId: s.chat_id })
                    }
                }
            }
            Item {
                id: sheet
                anchors.fill: parent
                z: 24
                property bool open: false
                property string title: ""
                property var choices: []
                visible: dim.opacity > 0
                Rectangle {
                    id: dim
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.4)
                    opacity: sheet.open ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                    MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
                }
                Column {
                    id: cards
                    x: 8; width: parent.width - 16
                    y: sheet.open ? parent.height - height - 8 - safe.bottom : parent.height + 8
                    Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0] } }
                    spacing: 8
                    Rectangle {
                        width: parent.width; height: choiceCol.height
                        radius: 14
                        color: Theme.menu
                        clip: true
                        Column {
                            id: choiceCol
                            width: parent.width
                            Text {
                                visible: sheet.title !== ""
                                x: 16; width: parent.width - 32
                                topPadding: 14; bottomPadding: 14
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                text: sheet.title
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 13
                            }
                            Repeater {
                                model: sheet.choices
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: choiceCol.width; height: 57
                                    color: choiceHit.pressed ? Theme.highlight : "transparent"
                                    Rectangle { visible: index > 0 || sheet.title !== ""; width: parent.width; height: 0.5; color: Theme.separator }
                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 32
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: parent.modelData.t
                                        color: parent.modelData.red ? Theme.danger : Theme.accent
                                        font.family: Theme.font; font.pixelSize: 20
                                    }
                                    MouseArea {
                                        id: choiceHit
                                        anchors.fill: parent
                                        onClicked: {
                                            const run = parent.modelData.run
                                            sheet.open = false
                                            run()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 57
                        radius: 14
                        color: cancelHit.pressed ? Theme.highlight : Theme.menu
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Bekor qilish")
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                        }
                        MouseArea { id: cancelHit; anchors.fill: parent; onClicked: sheet.open = false }
                    }
                }
            }
            PhotoViewer {
                id: viewer
                store: page.store
                chatId: page.chatId
                locate: (id) => {           // a paged-to one's cell, when it is in the grid
                    const i = page.found.findIndex((m) => m.id === id)
                    return i >= 0 && grid.visible ? cells.itemAt(i) : null
                }
                onSave: page.save()
                onPaged: (id) => page.unveil(id)
            }
            Rectangle {
                id: noteBox
                z: 30
                anchors.horizontalCenter: parent.horizontalCenter
                y: 68
                width: Math.min(parent.width - 40, note.implicitWidth + 28); height: note.implicitHeight + 16
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.75)
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Text {
                    id: note
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.parent.width - 68)
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
            Timer { id: noteAway; interval: 2200; onTriggered: noteBox.opacity = 0 }
        }
    }

    // ---- the head: picture, name, status, the buttons ----
    // Pulled down (32 under the top) or its picture tapped, the picture grows across the page's top,
    // as Telegram-iOS's PeerInfoHeaderNode (isAvatarExpanded): min(width, height − 61) + 98 high, in
    // 0.35 s by the spring, the name and status in white at its foot over a shadow, the buttons on it
    // white on white 0.1; scrolled back up it is round again. A user's pictures (getUserProfilePhotos)
    // show in turn: a tap on its left fifth the one before, elsewhere the next (round from either end),
    // a 2 pt strip at the top for each; pulled once more, or tapped when it is the only one, it shows
    // full screen.
    property bool expanded: false
    property real ex: expanded ? 1 : 0
    Behavior on ex { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0] } }
    clear: ex
    property var pictures: []           // [{ file, w, h, mini, date }], the newest first
    property int pictureAt: 0
    property var picturePaths: ({})     // index -> local path
    readonly property string bigPath: (picturePaths[pictureAt] || (pictureAt === 0 ? photo : "")) || ""
    readonly property bool canExpand: !saved && !!chat && !!chat.photo
    property bool canOpen: false        // a new drag on the grown picture: pulled, it shows full screen
    function lerp(a, b, t) { return a + (b - a) * t }
    function mix(a, b, t) { return Qt.rgba(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.a, b.a, t)) }

    function loadPictures() {
        const first = chat && chat.photo && chat.photo.big
        if (first)
            pictures = [{ file: first, w: 640, h: 640, mini: chat.photo.minithumbnail ? chat.photo.minithumbnail.data : "" }]
        if (!user)
            return
        store.send({ "@type": "getUserProfilePhotos", user_id: user.id, offset: 0, limit: 100 }, (r) => {
            if (!page || r["@type"] !== "chatPhotos" || !r.photos.length)
                return
            page.pictures = r.photos.map((p) => {
                const z = p.sizes.find((x) => x.width >= 640) || p.sizes[p.sizes.length - 1]
                return { file: z.photo, w: z.width, h: z.height, mini: p.minithumbnail ? p.minithumbnail.data : "",
                         date: p.added_date }
            })
            page.picturePaths = ({})
            page.want(page.pictureAt)
        })
    }
    // a picture's file, and the next one's ahead of its tap
    function want(i) {
        for (const k of [i, (i + 1) % pictures.length]) {
            const p = pictures[k]
            if (p && !picturePaths[k])
                store.fetch(p.file, k === i ? 16 : 4, (path) => {
                    if (!page)          // the page was closed before the picture came
                        return
                    const m = Object.assign({}, page.picturePaths)
                    m[k] = path
                    page.picturePaths = m
                })
        }
    }
    function expand() {
        if (!canExpand || expanded)
            return
        want(pictureAt)
        expanded = true
    }
    function step(back) {
        const n = pictures.length
        if (n < 2) {
            showPicture()
            return
        }
        pictureAt = (pictureAt + (back ? n - 1 : 1)) % n
        want(pictureAt)
    }
    function showPicture() {
        const p = pictures[pictureAt]
        if (!p || !bigPath)
            return
        overlay.viewer.show(bigPic, p.h / p.w, "image://pic/0/" + Math.round(width) + "/" + bigPath, "", 0)
        store.fetch(p.file, 32, (path) => { if (page && overlay.viewer.open) overlay.viewer.better(path) })
    }
    Connections {
        target: page.flick
        function onContentYChanged() {
            const y = page.flick.contentY
            if (y >= 1 && page.expanded)
                page.expanded = false
            else if (y <= -32 && page.flick.dragging) {
                if (!page.expanded)
                    page.expand()
                else if (page.canOpen && page.ex > 0.99) {
                    page.canOpen = false
                    page.showPicture()
                }
            }
        }
        function onDraggingChanged() { if (page.flick.dragging) page.canOpen = page.expanded && page.ex > 0.99 }
    }

    Item {
        id: head
        readonly property real top0: 72                      // its top on the page, unscrolled (the bar, 16)
        readonly property real bigH: Math.min(page.width, page.height - 61) + 98
        readonly property real pull: Math.max(0, -page.flick.contentY)   // pulled under the top
        width: parent.width
        height: page.lerp(258, bigH - top0, page.ex) + songH
        z: 2
        // their profile's song (userFullInfo.first_profile_audio) under the buttons, as Telegram-iOS's: «♫ Nom  Ijrochi ›»
        readonly property var song: page.user && page.full && page.full.first_profile_audio ? page.full.first_profile_audio : null
        readonly property real songH: song ? 40 : 0

        Item {          // the picture: round (with story ring when active), or across the top
            id: bigPic
            x: page.lerp((head.width - 100) / 2, 0, page.ex)
            y: page.lerp(0, -head.top0 - head.pull, page.ex)
            width: page.lerp(100, head.width, page.ex)
            height: page.lerp(100, head.bigH + head.pull, page.ex)
            readonly property bool hasStory: !page.saved && (store.storiesSeen, store.hasStories(page.chatId))
            readonly property bool freshStory: hasStory && (store.storiesSeen, store.unseen(page.chatId))
            Rectangle {     // seen story ring
                visible: page.ex === 0 && bigPic.hasStory && !bigPic.freshStory
                anchors.fill: parent; anchors.margins: -5
                radius: width / 2; color: "transparent"
                border.color: Theme.dark ? "#48484a" : "#c7c7cc"; border.width: 2
            }
            Rectangle {     // unseen story ring (green to blue)
                visible: page.ex === 0 && bigPic.freshStory
                anchors.fill: parent; anchors.margins: -5
                radius: width / 2; rotation: 45
                gradient: Gradient {
                    GradientStop { position: 0; color: "#34c76f" }
                    GradientStop { position: 1; color: "#3da1fd" }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 5.6; height: width; radius: width / 2
                    color: Theme.bg
                }
            }
            Avatar {
                anchors.fill: parent
                visible: page.ex === 0
                source: page.photo || (page.chat ? store.photoPath(page.chat) : "")
                letters: page.chat ? store.letters(page.chat.title) : ""
                tint: store.tints[Math.abs(page.chatId) % store.tints.length]
                saved: page.saved
            }
            Item {
                id: wide
                anchors.fill: parent
                visible: false
                layer.enabled: page.ex > 0
                Rectangle { anchors.fill: parent; color: store.tints[Math.abs(page.chatId) % store.tints.length] }
                Image {     // the tiny preview, blurred, until the picture comes
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    readonly property var p: page.pictures[page.pictureAt]
                    source: p && p.mini ? "image://pic/0/" + Math.round(head.width) + "/mini/" + p.mini : ""
                    visible: bigImage.status !== Image.Ready
                }
                Image {
                    id: bigImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.round(head.width)
                    source: page.ex > 0 && page.bigPath ? "image://pic/0/" + Math.round(head.width) + "/" + page.bigPath : ""
                }
                Rectangle {     // the shadow at the top, under the bar
                    width: parent.width; height: 76
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.4) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                    }
                }
                Rectangle {     // and at the foot, under the name and the buttons
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 188
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                }
            }
            Rectangle {
                id: wideMask
                anchors.fill: parent
                radius: page.lerp(50, 0, page.ex)
                visible: false
                layer.enabled: page.ex > 0
            }
            MultiEffect {
                anchors.fill: parent
                visible: page.ex > 0
                source: wide
                maskEnabled: true
                maskSource: wideMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Row {           // a strip for each picture, the shown one white
                x: 8; y: 8
                spacing: 4
                visible: page.pictures.length > 1
                opacity: page.ex
                Repeater {
                    model: page.pictures.length
                    Rectangle {
                        required property int index
                        width: (head.width - 16 - 4 * (page.pictures.length - 1)) / page.pictures.length; height: 2
                        radius: 1
                        color: "white"
                        opacity: index === page.pictureAt ? 1 : 0.2
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                function tap(m) {
                    if (!page.expanded) {
                        if (bigPic.hasStory)
                            root.storyView.show([page.chatId], 0)
                        else
                            page.expand()
                    } else
                        page.step(m.x < width / 5)
                }
                onClicked: (m) => tap(m)
                onDoubleClicked: (m) => tap(m)      // (quick taps: Qt makes the second a double one, not a click)
            }
        }
        Text {
            id: name
            readonly property real free: head.width - 40
            width: Math.min(implicitWidth, free)
            x: page.lerp((head.width - width) / 2, 16, page.ex)
            y: page.lerp(112, head.bigH - 141 - head.top0, page.ex)
            elide: Text.ElideRight
            text: (page.changed, store.title(page.chat))       // (renamed in place: the same chat object)
            color: page.mix(Theme.text, Qt.rgba(1, 1, 1, 1), page.ex)
            font.family: Theme.font; font.pixelSize: 23; font.weight: Font.DemiBold
        }
        Text {
            id: status
            width: Math.min(implicitWidth, head.width - 40)
            x: page.lerp((head.width - width) / 2, 16, page.ex)
            y: name.y + page.lerp(34, 32, page.ex)
            elide: Text.ElideRight
            // (a group's full info counts its members better than the group itself)
            text: page.saved ? "" : page.full && page.full.member_count && !store.activity(page.chat)
                  ? Tr.n(page.chat.type.is_channel ? "%1 obunachi" : "%1 a'zo", page.full.member_count, store.count(page.full.member_count))
                  : (store.seen, store.status(page.chat, page.now))
            readonly property bool online: text === Tr.t("onlayn")
            color: page.mix(online ? Theme.accent : Theme.grey, Qt.rgba(1, 1, 1, page.ex > 0 && !online ? 0.75 : 1), page.ex)
            font.family: Theme.font; font.pixelSize: 15
        }

        // ---- the buttons ----
        Row {
            x: 16; width: parent.width - 32
            y: page.lerp(200, head.bigH - 16 - 58 - head.top0, page.ex)
            spacing: 8
            Repeater {
                id: buttons
                readonly property bool callBtns: page.other && !page.bot && !page.deleted
                model: (callBtns ? [{ icon: "phone", name: Tr.t("qo'ng'iroq"), act: "call" },
                                    { icon: "camera", name: Tr.t("video"), act: "video" }] : [])
                       .concat(page.isChannel && page.directChatId !== 0 ? [{ icon: "direct", name: Tr.t("xabar"), act: "direct" }] : [])
                       .concat(page.saved ? [] : [{ icon: "bell", name: Tr.t(page.muted ? "ovozni yoqish" : "ovozsiz"), act: "mute" }])
                       .concat([{ icon: "search", name: Tr.t("qidiruv"), act: "search" }])
                       .concat(page.other ? [{ icon: "more", name: Tr.t("yana"), act: "more" }] : [])
                Rectangle {
                    required property var modelData
                    width: (parent.width - 8 * (buttons.count - 1)) / buttons.count; height: 58
                    radius: page.lerp(12, 16, page.ex)
                    color: hit.pressed ? page.mix(Theme.highlight, Qt.rgba(1, 1, 1, 0.25), page.ex)
                                       : page.mix(Theme.card, Qt.rgba(1, 1, 1, 0.1), page.ex)
                    readonly property color ink: page.mix(Theme.accent, Qt.rgba(1, 1, 1, 1), page.ex)
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; y: 8; name: parent.modelData.icon; color: parent.ink }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 35
                        width: parent.width - 4
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: parent.modelData.name
                        color: parent.ink
                        font.family: Theme.font; font.pixelSize: buttons.count > 4 ? 11 : 12
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        onClicked: {
                            const a = parent.modelData.act
                            if (a === "call" || a === "video")
                                page.overlay.say(Tr.t("Nullgram'da ovozli va video qo'ng'iroqlar hali yo'q"))
                            else if (a === "direct")
                                store.openDirectMessages(page.directChatId, page.nav, page.chatId)
                            else if (a === "mute")
                                page.mute()
                            else if (a === "more")
                                page.moreMenu()
                            else
                                page.search()
                        }
                    }
                }
            }
        }

        // the song: the title in the accent, the performer grey, sliding when long (Marquee); tapped, their songs
        // play in the player's sheet, «X pleylisti» (Player.openProfile)
        Item {
            visible: !!head.song
            y: head.height - head.songH
            width: parent.width; height: head.songH
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 27 - height / 2
                spacing: 4
                opacity: songHit.pressed ? 0.5 : 1
                Marquee {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(textWidth, head.width - 72)
                    textFormat: Text.StyledText
                    color: Theme.accent
                    text: head.song ? "♫ " + (head.song.title || head.song.file_name || Tr.t("Musiqa")).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                      + "  <font color='" + Theme.grey + "'>"
                                      + (head.song.performer || Tr.t("Noma'lum ijrochi")).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>" : ""
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "›"; color: Theme.grey; font.pixelSize: 17 }
            }
            MouseArea {
                id: songHit
                anchors.fill: parent
                onClicked: page.player.openProfile(page.user.id, page.firstName, head.song)
            }
        }
    }

    // ---- what is known of it ----
    // As Telegram-iOS's infoItems: a user's «mobil» and «foydalanuvchi nomi» (others «shuningdek @…», the QR's
    // place) in the accent, the birthday («bugun tug'ilgan kun» with 🎁), «bio», our «eslatmalar» («faqat sizga
    // ko'rinadi» on the right); then, not a contact, «Kontaktlarga qo'shish» and «Bloklash» (blocked:
    // «Blokdan chiqarish»). PeerInfoScreenLabeledValueItem: 15 over and under, the label 14, 3, the value 17.
    SettingsGroup {
        visible: facts.count > 0
        Repeater {
            id: facts
            model: {
                const out = []
                if (page.saved)
                    return out
                const u = page.user, f = page.full, g = page.group
                if (u && u.phone_number)
                    out.push({ k: Tr.t(u.phone_number.startsWith("888") ? "anonim raqam" : "mobil"), v: page.phoneText(u.phone_number),
                               accent: true, act: "phone" })
                const names = u ? u.usernames : g ? g.usernames : null
                const active = names && names.active_usernames ? names.active_usernames : []
                if (active.length)
                    out.push(u ? { k: Tr.t("foydalanuvchi nomi"), v: "@" + active[0], accent: true, act: "username", icon: "qr", qr: active[0],
                                   also: active.length > 1 ? Tr.f("shuningdek %1", "@" + active.slice(1).join(", @")) : "" }
                               : { k: Tr.t("havola"), v: "t.me/" + active[0], accent: true, act: "link", icon: "qr", qr: active[0] })
                if (f && f.birthdate) {
                    const b = f.birthdate, d = new Date(page.now * 1000)
                    const today = b.day === d.getDate() && b.month === d.getMonth() + 1
                    out.push({ k: Tr.t(today ? "bugun tug'ilgan kun" : "tug'ilgan sana"),
                               v: Tr.date(b.day, b.month, b.year) + (b.year ? " (" + Tr.n("%1 yosh", page.age(b)) + ")" : ""),
                               icon: today && page.giftable ? "gift" : "", act: today && page.giftable ? "gift" : "" })
                }
                if (f && f.bio && f.bio.text)
                    out.push({ k: Tr.t("bio"), v: f.bio.text })
                if (f && f.note && f.note.text)
                    out.push({ k: Tr.t("eslatmalar"), right: Tr.t("faqat sizga ko'rinadi"), v: f.note.text })
                if (f && f.description)
                    out.push({ k: Tr.t("ma'lumot"), v: f.description })
                if (f && !active.length && f.invite_link)
                    out.push({ k: Tr.t("taklif havolasi"), v: f.invite_link.invite_link, accent: true, act: "link" })
                if (page.other && !page.bot && !page.deleted) {
                    if (!page.contact)
                        out.push({ action: Tr.t("Kontaktlarga qo'shish"), act: "add" })
                    if (page.blocked)
                        out.push({ action: Tr.t("Blokdan chiqarish"), act: "unblock" })
                    else if (!page.contact)
                        out.push({ action: Tr.t("Bloklash"), red: true, act: "block" })
                }
                return out
            }
            Rectangle {
                id: fact
                required property var modelData
                required property int index
                readonly property bool action: !!modelData.action
                width: parent.width
                height: action ? 46 : value.y + value.height + (alsoText.visible ? 3 + alsoText.height : 0) + 15
                color: factHit.pressed && !!modelData.act ? Theme.highlight : "transparent"
                Text {
                    visible: fact.action
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 32
                    elide: Text.ElideRight
                    text: fact.modelData.action || ""
                    color: fact.modelData.red ? Theme.danger : Theme.accent
                    font.family: Theme.font; font.pixelSize: 17
                }
                Text {
                    id: label
                    visible: !fact.action
                    x: 16; y: 15
                    text: fact.modelData.k || ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    visible: !!fact.modelData.right
                    anchors.right: parent.right; anchors.rightMargin: 16; y: 15
                    text: fact.modelData.right || ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    id: value
                    visible: !fact.action
                    x: 16; y: fact.action ? 0 : label.y + label.height + 3
                    width: parent.width - 32 - (factIcon.visible ? 32 : 0)
                    height: fact.action ? 0 : implicitHeight
                    wrapMode: Text.Wrap
                    text: fact.modelData.v || ""
                    color: fact.modelData.accent ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: 17
                }
                Text {
                    id: alsoText
                    visible: !!fact.modelData.also
                    x: 16; y: value.y + value.height + 3
                    width: parent.width - 32
                    wrapMode: Text.Wrap
                    text: fact.modelData.also || ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Icon {
                    id: factIcon
                    visible: !!fact.modelData.icon
                    opacity: qrPress.pressed ? 0.5 : 1
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    name: fact.modelData.icon || ""
                    color: Theme.accent
                }
                Rectangle {
                    visible: fact.index < facts.count - 1
                    x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                }
                MouseArea {
                    id: factHit
                    anchors.fill: parent
                    enabled: !!fact.modelData.act
                    onClicked: page.tapFact(fact.modelData)
                }
                MouseArea {     // the QR on the right: their link as a code (QrSheet)
                    id: qrPress
                    visible: !!fact.modelData.qr
                    anchors.right: parent.right
                    width: 56; height: parent.height
                    onClicked: page.showQr(fact.modelData.qr)
                }
            }
        }
    }

    // ---- a channel or group we run: its people and money (iOS's admin rows in PeerInfoScreen; a group's: its
    // settings only, the members are below) ----
    SettingsGroup {
        id: adminRows
        visible: page.runs && !page.user
        readonly property bool chan: page.runs && !!page.chat.type.is_channel
        SettingsRow {
            icon: "star"; tint: "#ff9500"
            visible: adminRows.chan
            text: Tr.t("Administratorlar")
            value: page.full && page.full.administrator_count ? String(page.full.administrator_count) : ""
            onClicked: page.openPage("MembersPage.qml", { mode: "admins" })
        }
        SettingsRow {
            icon: "person"; tint: "#34c759"
            visible: adminRows.chan
            text: Tr.t("Obunachilar")
            value: page.full ? String(page.full.member_count) : ""
            onClicked: page.openPage("MembersPage.qml", { mode: "members" })
        }
        SettingsRow {
            icon: "hand"; tint: "#3478f6"
            visible: (page.changed, !!page.chat && !!page.chat.pending_join_requests && page.chat.pending_join_requests.total_count > 0)
            text: Tr.t("Qo'shilish so'rovlari")
            value: visible ? String(page.chat.pending_join_requests.total_count) : ""
            onClicked: page.openPage("JoinRequestsPage.qml", {})
        }
        SettingsRow {
            icon: "direct"; tint: "#007aff"
            visible: adminRows.chan && page.directChatId !== 0 && page.canDirectAdmin
            text: Tr.t("Kanalga xabarlar")
            value: (store.seen, page.directChatId && store.chats[page.directChatId] && store.chats[page.directChatId].unread_count > 0
                    ? String(store.chats[page.directChatId].unread_count) : "")
            onClicked: store.openDirectMessages(page.directChatId, page.nav, page.chatId)
        }
        SettingsRow {
            art: "stars"
            visible: page.stars > 0
            text: Tr.t("Balans")
            value: "⭐ " + page.stars
            onClicked: page.overlay.say(Tr.t("Yulduzlarni yechib olish — Telegram'ning boshqa ilovasida"))
        }
        SettingsRow {
            icon: "settings"; tint: "#8e8e93"
            last: true
            text: Tr.t(adminRows.chan ? "Kanal sozlamalari" : "Guruh sozlamalari")
            onClicked: page.openPage("ChannelEditPage.qml", {})
        }
    }
    property int stars: 0       // a channel's Stars (getStarRevenueStatus: what it earned, its owner sees)
    readonly property bool ownsChannel: runs && myStatus["@type"] === "chatMemberStatusCreator" && chat.type.is_channel
    onOwnsChannelChanged: askStars()
    Item { Component.onCompleted: page.askStars() }
    function askStars() {
        if (ownsChannel)
            store.send({ "@type": "getStarRevenueStatistics", owner_id: { "@type": "messageSenderChat", chat_id: chatId }, is_dark: false }, (r) => {
                if (page && r.status && r.status.current_amount)
                    page.stars = r.status.current_amount.star_count || 0
            })
    }

    // ---- what was sent: a tab for each kind there is ----
    Column {
        width: parent.width
        visible: page.shownTabs.length > 0
        spacing: 0
        Flickable {         // the tabs (more than fit: they slide)
            x: 16; width: parent.width - 32; height: 34
            contentWidth: tabRow.width
            clip: true
            Row {
                id: tabRow
                spacing: 6
                Repeater {
                    model: page.shownTabs
                    Rectangle {
                        required property var modelData
                        readonly property bool on: page.tab === modelData.key
                        width: tabText.width + 26; height: 30
                        radius: 15
                        color: on ? Theme.accent : Theme.card
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: parent.modelData.name + "  " + store.count(page.counts[parent.modelData.key])
                            color: parent.on ? "white" : Theme.text
                            font.family: Theme.font; font.pixelSize: 14; font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { anchors.fill: parent; onClicked: if (!parent.on) page.load(parent.modelData) }
                    }
                }
            }
        }
        Item { width: 1; height: 10 }

        Grid {              // pictures and videos, three across
            id: grid
            visible: page.tab === "media"
            width: parent.width
            columns: 3
            spacing: 1.5
            readonly property real side: (width - 2 * spacing) / 3
            Repeater {
                id: cells
                model: grid.visible ? page.found : []
                Item {
                    id: cell
                    required property var modelData
                    width: grid.side; height: grid.side
                    property string path: ""
                    Component.onCompleted: {
                        const f = page.cellFile(modelData)
                        if (f)
                            store.fetch(f, 4, (p) => { if (cell) cell.path = p })    // cell gone if scrolled away / page closed
                    }
                    Rectangle { anchors.fill: parent; color: Theme.highlight }
                    Image {
                        anchors.fill: parent
                        visible: full.status !== Image.Ready
                        asynchronous: true
                        sourceSize: Qt.size(12, 12)
                        readonly property string m: page.mini(cell.modelData)
                        source: m ? "image://pic/0/" + Math.round(grid.side) + "/mini/" + m : ""
                    }
                    Image {
                        id: full
                        anchors.fill: parent
                        asynchronous: true
                        sourceSize: Qt.size(Math.round(grid.side), Math.round(grid.side))
                        source: cell.path ? "image://pic/0/" + Math.round(grid.side) + "/" + cell.path : ""
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { OpacityAnimator { duration: 150 } }
                    }
                    Loader {        // a spoiler, until it is seen full screen
                        anchors.fill: parent
                        active: !!cell.modelData.content.has_spoiler && !(page.unveiledTick, page.unveiled[cell.modelData.id])
                        sourceComponent: Veil {
                            corner: "0"
                            mini: page.mini(cell.modelData)
                            pic: cell.path
                            live: page.visible
                        }
                    }
                    Rectangle {     // a video's length
                        visible: cell.modelData.content["@type"] === "messageVideo"
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                        width: len.width + 10; height: 18; radius: 9
                        color: Qt.rgba(0, 0, 0, 0.5)
                        Text {
                            id: len
                            anchors.centerIn: parent
                            text: visible && cell.modelData.content.video ? page.clock(cell.modelData.content.video.duration) : ""
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    Rectangle {     // a video coming down before it plays
                        anchors.fill: parent
                        visible: cell.loading
                        color: Qt.rgba(0, 0, 0, 0.35)
                    }
                    property bool loading: false
                    MouseArea { anchors.fill: parent; onClicked: page.view(cell) }
                }
            }
        }

        SettingsGroup {     // a group's members: a picture, the name, when last here, owner or admin
            visible: page.tab === "members" && page.found.length > 0
            SettingsRow {   // (iOS: «Add Members» over them, for who may)
                visible: page.tab === "members" && (page.runs && (page.myStatus["@type"] === "chatMemberStatusCreator"
                                                                  || !!page.myStatus.rights.can_invite_users)
                                                    || (page.changed, !!page.chat && !!page.chat.permissions && page.chat.permissions.can_invite_users))
                icon: "person"; tint: Theme.accent; accent: true; chevron: false
                text: Tr.t("A'zo qo'shish")
                onClicked: store.addMembers(page.chatId, page.nav, () => page.load(page.tabs[0]))
            }
            Repeater {
                id: people
                model: page.tab === "members" ? page.found : []
                Rectangle {
                    id: person
                    required property var modelData
                    required property int index
                    readonly property var who: modelData.member_id
                    readonly property var u: who["@type"] === "messageSenderUser" ? store.users[who.user_id] : null
                    readonly property bool mine: !!u && !!store.me && u.id === store.me.id
                    readonly property string name: store.senderName(who, false) || Tr.t("O'chirilgan hisob")
                    readonly property string role: {
                        const s = modelData.status
                        return s["@type"] === "chatMemberStatusCreator" ? s.custom_title || Tr.t("egasi")
                             : s["@type"] === "chatMemberStatusAdministrator" ? s.custom_title || Tr.t("admin") : ""
                    }
                    width: parent.width; height: 56
                    color: personHit.pressed ? Theme.highlight : "transparent"
                    property string photo: ""
                    Component.onCompleted: {
                        if (u)
                            store.userPhoto(u, (p) => person.photo = p)
                        else if (store.chats[who.chat_id] && store.chats[who.chat_id].photo)
                            store.fetch(store.chats[who.chat_id].photo.small, 1, (p) => person.photo = p)
                    }
                    Avatar {
                        x: 14; y: 8
                        width: 40; height: 40
                        source: person.photo
                        letters: store.letters(person.name)
                        tint: store.tints[Math.abs(person.who.user_id || person.who.chat_id) % store.tints.length]
                    }
                    Text {
                        x: 66; y: 8
                        width: parent.width - x - roleText.width - 24
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft     // (an Arabic name too, as Telegram lists it)
                        text: person.name
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        x: 66; y: 30
                        width: parent.width - x - 14
                        elide: Text.ElideRight
                        text: person.mine ? Tr.t("onlayn") : (store.seen, store.userStatus(person.u, page.now))
                        color: text === Tr.t("onlayn") ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        id: roleText
                        anchors.right: parent.right; anchors.rightMargin: 14; y: 10
                        text: person.role
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Rectangle {
                        visible: person.index < people.count - 1
                        x: 66; anchors.bottom: parent.bottom; width: parent.width - 66; height: 0.5; color: Theme.separator
                    }
                    MouseArea {
                        id: personHit
                        anchors.fill: parent
                        enabled: !!person.u && !person.mine
                        onClicked: page.chatWith(person.u.id)
                    }
                }
            }
        }

        Grid {              // received gifts, three across (Telegram-iOS PeerInfoGifts)
            id: giftGrid
            visible: page.tab === "gifts" && page.found.length > 0
            x: 16; width: parent.width - 32
            columns: 3
            spacing: 8
            readonly property real side: (width - 16) / 3
            Repeater {
                model: giftGrid.visible ? page.found : []
                Rectangle {
                    id: gCell
                    required property var modelData
                    readonly property var sent: modelData.gift
                    readonly property bool upgraded: !!sent && sent["@type"] === "sentGiftUpgraded"
                    readonly property var inner: sent ? sent.gift : null
                    readonly property var backdrop: upgraded && inner && inner.backdrop ? inner.backdrop.colors : null
                    readonly property var st: page.giftSticker(modelData)
                    readonly property bool tgs: !!st && st.format["@type"] === "stickerFormatTgs"
                    readonly property var f: !st ? null : tgs || st.format["@type"] === "stickerFormatWebp" ? st.sticker
                                             : st.thumbnail ? st.thumbnail.file : null
                    readonly property string path: f ? (page.giftGot, page.giftPaths[f.id] || "") : ""
                    onFChanged: page.wantGift(f)
                    Component.onCompleted: page.wantGift(f)

                    width: giftGrid.side; height: giftGrid.side + 16
                    radius: 14
                    clip: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: gCell.backdrop ? page.hexColor(gCell.backdrop.center_color) : Theme.card }
                        GradientStop { position: 1; color: gCell.backdrop ? page.hexColor(gCell.backdrop.edge_color) : Theme.card }
                    }
                    scale: gHit.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    // gift sticker (first frame for TGS, or thumbnail)
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 18
                        width: gCell.width - 28; height: width
                        source: gCell.path === "" ? "" : gCell.tgs ? "image://lottie/0/-/" + gCell.path : "image://thumb/" + gCell.path
                        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }
                    // top-left: pinned badge OR sender mini avatar
                    Rectangle {
                        visible: !!gCell.modelData.is_pinned
                        x: 6; y: 6; width: 20; height: 20; radius: 10
                        color: Qt.rgba(0, 0, 0, 0.35)
                        Icon { anchors.centerIn: parent; width: 11; height: 11; name: "pin"; color: "white" }
                    }
                    Avatar {
                        id: gFrom
                        visible: !gCell.modelData.is_pinned && !gCell.modelData.is_private && !!gCell.modelData.sender_id
                        x: 6; y: 6; width: 20; height: 20
                        Component.onCompleted: {
                            const s = gCell.modelData.sender_id
                            if (s)
                                store.faceOn(gFrom, s.user_id ? { user_id: s.user_id } : { chat_id: s.chat_id })
                        }
                    }
                    // top-right: hidden badge (admin) OR upgraded #number OR limited ribbon
                    Rectangle {
                        visible: !gCell.modelData.is_saved
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 6
                        width: 22; height: 20; radius: 10
                        color: Qt.rgba(0, 0, 0, 0.45)
                        Icon { anchors.centerIn: parent; width: 13; height: 13; name: "eyeoff"; color: "white" }
                    }
                    Rectangle {
                        visible: gCell.modelData.is_saved && (gCell.upgraded || (!!gCell.inner && !!gCell.inner.overall_limits))
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 6
                        width: rBadge.implicitWidth + 10; height: 18; radius: 9
                        color: gCell.upgraded ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                        Text {
                            id: rBadge
                            anchors.centerIn: parent
                            text: gCell.upgraded && gCell.inner ? "#" + gCell.inner.number
                                : gCell.inner && gCell.inner.overall_limits ? "1/" + store.short(gCell.inner.overall_limits.total_count) : ""
                            color: gCell.upgraded ? "white" : Theme.accent
                            font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold
                        }
                    }
                    // bottom: price pill (regular) or upgraded title
                    Row {
                        visible: !gCell.upgraded && !!gCell.inner
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                        spacing: 2
                        Icon { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; name: "star"; color: "#ffb10a" }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: gCell.inner ? store.count(gCell.inner.star_count) : ""
                            color: Theme.dark ? "#ffc337" : "#d3720a"
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        visible: gCell.upgraded && !!gCell.inner
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        width: parent.width - 12; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: gCell.inner && gCell.inner.title ? gCell.inner.title : ""
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: gHit
                        anchors.fill: parent
                        onClicked: page.overlay.giftView.show(gCell.modelData, page.giftOwnerId, page.found, page.canManageGifts, page.ownsChannel)
                    }
                }
            }
        }

        SettingsGroup {     // files, links, voice notes, music: a row each
            visible: page.tab !== "media" && page.tab !== "members" && page.tab !== "gifts" && page.found.length > 0
            Repeater {
                id: rows
                model: page.tab !== "media" && page.tab !== "members" && page.tab !== "gifts" ? page.found : []
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var c: modelData.content
                    width: parent.width; height: 60
                    color: rowHit.pressed ? Theme.highlight : "transparent"
                    readonly property var parts: {
                        const t = c["@type"]
                        if (t === "messageDocument")
                            return [c.document.file_name || Tr.t("Fayl"), store.size(c.document.document.size)]
                        if (t === "messageVoiceNote")
                            return [store.origin(modelData.forward_info) || (modelData.is_outgoing ? Tr.t("Siz")
                                    : store.senderName(modelData.sender_id, false) || store.title(page.chat)),
                                    Tr.t("Ovozli xabar") + " · " + page.clock(c.voice_note.duration)]
                        if (t === "messageAudio")
                            return [c.audio.title || c.audio.file_name || Tr.t("Musiqa"), (c.audio.performer || "") + (c.audio.performer ? " · " : "") + page.clock(c.audio.duration)]
                        const text = c.text || c.caption
                        return [page.link(modelData) || Tr.t("havola"), text ? text.text.replace(/\s+/g, " ") : ""]
                    }
                    Text {
                        x: 16; y: 10; width: parent.width - 90
                        elide: Text.ElideMiddle
                        text: row.parts[0]
                        color: page.tab === "links" ? Theme.accent : Theme.text
                        font.family: Theme.font; font.pixelSize: 16
                    }
                    Text {
                        x: 16; y: 33; width: parent.width - 32
                        elide: Text.ElideRight
                        text: row.parts[1]
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                        text: store.stamp(row.modelData.date)
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Rectangle {
                        visible: row.index < rows.count - 1
                        x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                    }
                    MouseArea { id: rowHit; anchors.fill: parent; onClicked: page.toMessage(row.modelData.id) }
                }
            }
        }
        Text {
            visible: page.more
            width: parent.width; height: 44
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: Tr.t(page.loading ? "yuklanmoqda..." : "Yana")
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 15
            MouseArea { anchors.fill: parent; onClicked: page.older() }
        }
    }
}
