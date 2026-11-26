// The chats, as Telegram-iOS lists them (ChatListItem.swift): a round picture, the
// name and time on one line, two lines of the last message under it, the unread
// count in a pill. A tap lights the row at once; the chat comes in when it is ready.
// Over the list, as on iOS 26: the title in the middle and the search box under it; a tap
// on the box turns the page into the search (SearchView). Under it the chat folders (IMG_0295): a
// capsule of chips, the one shown on grey with its unread count; the folders' lists side by side
// under them, a sideways swipe slides to the next or the one before.
// Also reused in archiveMode (ArchivePage.qml) for chatListArchive, with list-level swipe,
// long-press preview menu, confirmation alerts, and multi-select edit mode (0 added row objects).
import QtQuick

Page {
    id: page
    property bool archiveMode: false
    property bool searching: false
    property bool editing: false
    readonly property bool modalOpen: chatMenu.open || alert.open
    property var picked: ({})
    property int pickedSeen: 0
    readonly property int pickedCount: pickedSeen >= 0 ? Object.keys(picked).length : 0
    // chats with something unread (not muted): the tab bar's badge
    readonly property int unreadChats: store.unreadChats

    function toTop() {
        if (list)
            list.positionViewAtBeginning()
    }

    // the folders as the chips show them: all chats first (or where Premium put them: main_chat_list_position)
    readonly property var tabs: {
        if (archiveMode)
            return [{ id: -1, name: Tr.t("Arxiv") }]
        const t = store.folders.slice()
        t.splice(Math.min(store.mainPosition, t.length), 0, { id: 0, name: Tr.t("Hammasi") })
        return t
    }
    readonly property int tabIndex: archiveMode ? 0 : Math.max(0, tabs.findIndex((t) => t.id === store.folder))
    function go(i) {
        if (archiveMode || i < 0 || i >= tabs.length || tabs[i].id === store.folder)
            return
        closeSwipe()
        store.showFolder(tabs[i].id)
    }

    Component.onCompleted: {
        if (archiveMode)
            store.loadArchive(100)
    }

    // TDLib counts a folder's unread chats once the folder is loaded: load each a little
    property bool countsAsked: false
    Connections {
        target: store
        function onFoldersChanged() {
            if (page.archiveMode || page.countsAsked || !store.folders.length)
                return
            page.countsAsked = true
            for (const f of store.folders)
                store.send({ "@type": "loadChats", chat_list: { "@type": "chatListFolder", chat_folder_id: f.id }, limit: 20 })
        }
        function onActionChanged(id) {
            const pages = pager.contentItem ? pager.contentItem.children : null
            if (!pages)
                return
            for (let i = 0; i < pages.length; i++) {
                const lv = pages[i].rows
                const ci = lv && lv.contentItem ? lv.contentItem.children : null
                if (!ci)
                    continue
                for (let j = 0; j < ci.length; j++) {
                    const r = ci[j]
                    if (r && r.chatId === id)
                        r.acted++
                }
            }
        }
    }
    property var litChatId: null
    property var pressedChatId: null
    Timer { id: unlight; interval: 600; onTriggered: page.litChatId = null }
    function openChat(chatId, messageId) {
        page.litChatId = chatId
        unlight.restart()
        const c = store.chats[chatId]
        if (td.fps)
            store.tapAt = Date.now()
        if (store.isDirectAdmin(c))
            page.nav.push(directPage, { chatId: chatId })
        else if (!messageId && store.isForum(c))
            page.nav.push(forumPage, { chatId: chatId })
        else
            page.nav.pushChat(chatPage, messageId ? { chatId: chatId, target: messageId } : { chatId: chatId })
    }
    property Component archiveComp: null
    function openArchive() {
        closeSwipe()
        if (!archiveComp)
            archiveComp = Qt.createComponent("ArchivePage.qml")
        if (archiveComp.status === Component.Error)
            return console.warn("nullgram:", archiveComp.errorString())
        page.nav.push(archiveComp, {})
    }
    function dismiss() {
        if (alert.open) {
            alert.open = false
            return true
        }
        if (chatMenu.open) {
            chatMenu.close()
            return true
        }
        if (editing) {
            exitEdit()
            return true
        }
        if (swipedChatId !== null) {
            closeSwipe()
            return true
        }
        if (!archiveMode && searching) {
            search.close()
            return true
        }
        return false
    }

    // ---- List-level swipe state (0 objects added to rowDelegate) ----
    property var swipedChatId: null
    property int swipedListId: 0
    property real swipedRowY: 0
    property real swipeX: 0
    property bool swiping: false
    readonly property real leftSwipeW: 190      // 3 discs: Mute, Delete, Archive/Unarchive (10 + 3 x 50 + 2 x 10 + 10)
    readonly property real rightSwipeW: 130     // 2 discs: Read/Unread, Pin/Unpin (10 + 2 x 50 + 10 + 10)
    // a press near a side (Telegram-iOS: max(22, min(width / 6, 80)) pt) swipes the row; one in the middle, with
    // folders, turns to the next folder (its InteractiveTransitionGestureRecognizer fails at the edges, and a row's
    // reveal gesture waits for it to fail); without folders, or in the archive, a row swipes from anywhere
    property bool edgePress: false
    // The pager turns folders only while no row wants the finger. It is turned OFF at once (a row's swipe, an edge
    // press), but ON again only once the finger is up: a Flickable turned on mid-gesture takes moves of a press it
    // never saw (the phone, 11-25: a press that closed an open row dragged the pager along from it; it stopped between
    // two folders) -- so pagerArmed holds what the pager could do when the finger came down, until it is lifted
    readonly property bool pagerWants: !archiveMode && store.folders.length > 0 && !searching && !swiping
                                       && swipedChatId === null && !edgePress
    property bool pagerArmed: true
    onPagerWantsChanged: if (!pagerWants && fingerDown.active) pagerArmed = false
    Behavior on swipeX { enabled: !page.swiping; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    onSwipeXChanged: if (!swiping && swipeX === 0 && swipedChatId !== null) swipedChatId = null
    function relocateSwipe(view) {
        Qt.callLater(() => {
            if (swipedChatId === null || !view.model)
                return
            const i = store.rowIndex(view.model, swipedChatId)
            view.forceLayout()
            const it = i >= 0 ? view.itemAtIndex(i) : null
            if (it) {
                swipedRowY = it.y
                return
            }
            swiping = false             // its row left this list (archived, deleted): no strip left behind
            swipedChatId = null
            swipeX = 0
        })
    }
    function closeSwipe() {
        swiping = false
        if (swipeX === 0)
            swipedChatId = null
        else
            swipeX = 0
    }

    // ---- Multi-select edit mode ----
    function enterEdit(initialChatId) {
        closeSwipe()
        editing = true
        const p = {}
        if (initialChatId !== undefined && initialChatId !== null)
            p[initialChatId] = true
        picked = p
        pickedSeen++
    }
    function exitEdit() {
        editing = false
        picked = {}
        pickedSeen++
    }
    function togglePick(chatId) {
        const p = Object.assign({}, picked)
        if (p[chatId])
            delete p[chatId]
        else
            p[chatId] = true
        picked = p
        pickedSeen++
    }
    function pickedIds() {
        return Object.keys(picked).map((k) => Number(k))
    }

    // ---- Chat row actions (used by swipe buttons, long-press menu, and bulk edit bar) ----
    function isChatMuted(c) {
        return !!(c && c.notification_settings && c.notification_settings.mute_for > 0)
    }
    function isChatUnread(c) {
        return !!(c && ((c.unread_count || 0) > 0 || c.is_marked_as_unread))
    }
    function isChatPinned(c, listId) {
        if (!c)
            return false
        const p = store.positionIn(listId, c)
        return !!(p && p.is_pinned)
    }
    function doMute(chatId) {
        const c = store.chats[chatId]
        if (!c)
            return
        const next = !isChatMuted(c)
        store.toggleMuteChat(chatId, next, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(next ? "Chat ovozsiz qilindi" : "Chat ovozi yoqildi"))
        })
    }
    function doToggleUnread(chatId) {
        const c = store.chats[chatId]
        if (!c)
            return
        const next = !isChatUnread(c)
        store.toggleUnreadChat(chatId, next, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(next ? "O'qilmagan deb belgilandi" : "O'qilgan deb belgilandi"))
        })
    }
    function doTogglePin(chatId, listId) {
        const c = store.chats[chatId]
        if (!c)
            return
        const next = !isChatPinned(c, listId)
        store.togglePinChat(chatId, listId, next, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(next ? "Chat qadaldi" : "Qadash yechildi"))
        })
    }
    function doArchive(chatId, toArchive) {
        store.archiveChat(chatId, toArchive, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(toArchive ? "Arxivga olindi" : "Arxivdan chiqarildi"))
        })
    }
    function openFolderPicker(chatId) {
        store.chatListsToAdd(chatId, (r) => {
            if (!page)
                return
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            const ids = (r.chat_lists || []).filter((l) => l["@type"] === "chatListFolder").map((l) => l.chat_folder_id)
            const items = []
            for (const f of store.folders) {
                if (ids.indexOf(f.id) >= 0) {
                    const fid = f.id, fname = f.name
                    items.push({ text: fname, icon: "folder", run: () => {
                        store.addChatToFolder(chatId, fid, (res) => {
                            if (res["@type"] === "error")
                                return page.nav.say(Tr.f("Bo'lmadi: %1", res.message))
                            page.nav.say(Tr.f("«%1» papkasiga qo'shildi", fname))
                        })
                    } })
                }
            }
            if (!items.length)
                return page.nav.say(Tr.t("Bu chat allaqachon barcha papkalarda"))
            chatMenu.showList(Tr.t("Papkaga qo'shish"), items)
        })
    }
    function askClearHistory(chatId) {
        const c = store.chats[chatId]
        if (!c)
            return
        const name = store.title(c)
        const runClear = (both) => store.clearChatHistory(chatId, both, false, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t("Tarix tozalandi"))
        })
        if (c.type["@type"] === "chatTypePrivate" && !store.isSaved(c) && c.can_be_deleted_for_all_users) {
            alert.show(Tr.t("Tarixni tozalash"), Tr.f("«%1» chatidagi barcha xabarlar o'chirilsinmi?", name), [
                { t: Tr.t("Ikkala tomondan ham tozalash"), red: true, run: () => runClear(true) },
                { t: Tr.t("Faqat men uchun tozalash"), red: true, run: () => runClear(false) },
                { t: Tr.t("Bekor qilish") }
            ], true)
        } else {
            alert.show(Tr.t("Tarixni tozalash"), Tr.f("«%1» chatidagi barcha xabarlar o'chirilsinmi?", name), [
                { t: Tr.t("Bekor qilish") },
                { t: Tr.t("Tozalash"), red: true, run: () => runClear(false) }
            ], false)
        }
    }
    function askDeleteChat(chatId) {
        const c = store.chats[chatId]
        if (!c)
            return
        const name = store.title(c)
        const ty = c.type["@type"]
        if (ty === "chatTypePrivate") {
            const delBoth = () => store.deleteChat(chatId, (r) => {
                if (r["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                page.nav.say(Tr.t("Chat o'chirildi"))
            })
            const delSelf = () => store.clearChatHistory(chatId, false, true, (r) => {
                if (r["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                page.nav.say(Tr.t("Chat o'chirildi"))
            })
            if (!store.isSaved(c) && c.can_be_deleted_for_all_users) {
                alert.show(Tr.t("Chatni o'chirish"), Tr.f("«%1» bilan chatni o'chirmoqchimisiz?", name), [
                    { t: Tr.t("Ikkala tomondan ham o'chirish"), red: true, run: delBoth },
                    { t: Tr.t("Faqat men uchun o'chirish"), red: true, run: delSelf },
                    { t: Tr.t("Bekor qilish") }
                ], true)
            } else {
                alert.show(Tr.t("Chatni o'chirish"), Tr.f("«%1» bilan chatni o'chirmoqchimisiz?", name), [
                    { t: Tr.t("Bekor qilish") },
                    { t: Tr.t("O'chirish"), red: true, run: delSelf }
                ], false)
            }
            return
        }
        const isChan = ty === "chatTypeSupergroup" && !!c.type.is_channel
        const g = store.groupOf(c)
        const isOwner = !!(g && g.status && g.status["@type"] === "chatMemberStatusCreator")
        const doLeave = () => store.leaveChat(chatId, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(isChan ? "Kanaldan chiqdingiz" : "Guruhdan chiqdingiz"))
        })
        const doDrop = () => store.deleteChat(chatId, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t("Chat o'chirildi"))
        })
        // (the owner deletes a group or channel for everyone, as ChannelEditPage does; can_be_deleted_for_all_users is
        // about a chat's messages and stays false for a channel -- the owner was offered only «chiqish»)
        if (isOwner) {
            alert.show(Tr.t(isChan ? "Kanalni o'chirish" : "Guruhni o'chirish"),
                       Tr.f(isChan ? "«%1» kanalidan chiqasizmi yoki butunlay o'chirasizmi?"
                                   : "«%1» guruhidan chiqasizmi yoki butunlay o'chirasizmi?", name), [
                { t: Tr.t("Hamma uchun o'chirish"), red: true, run: doDrop },
                { t: Tr.t(isChan ? "Kanaldan chiqish" : "Guruhdan chiqish"), red: true, run: doLeave },
                { t: Tr.t("Bekor qilish") }
            ], true)
        } else {
            alert.show(Tr.t(isChan ? "Kanaldan chiqish" : "Guruhdan chiqish"),
                       Tr.f(isChan ? "«%1» kanalidan chiqmoqchimisiz?" : "«%1» guruhidan chiqmoqchimisiz?", name), [
                { t: Tr.t("Bekor qilish") },
                { t: Tr.t("Tark etish"), red: true, run: doLeave }
            ], false)
        }
    }
    function openRowMenu(chatId, listId) {
        const c = store.chats[chatId]
        if (!c)
            return
        closeSwipe()
        const saved = store.isSaved(c)
        const pinned = isChatPinned(c, listId)
        const muted = isChatMuted(c)
        const unread = isChatUnread(c)
        const ty = c.type["@type"]
        const isChan = ty === "chatTypeSupergroup" && !!c.type.is_channel
        const isGroup = ty === "chatTypeBasicGroup" || (ty === "chatTypeSupergroup" && !c.type.is_channel)
        const acts = []
        acts.push({ text: Tr.t(pinned ? "Qadashni yechish" : "Qadash"), icon: "pin", run: () => page.doTogglePin(chatId, listId) })
        if (!saved)
            acts.push({ text: Tr.t(muted ? "Ovozini yoqish" : "Ovozsiz qilish"), icon: muted ? "bell" : "belloff", run: () => page.doMute(chatId) })
        acts.push({ text: Tr.t(unread ? "O'qilgan deb belgilash" : "O'qilmagan deb belgilash"),
                    icon: unread ? "check" : "chats", run: () => page.doToggleUnread(chatId) })
        if (!saved)
            acts.push({ text: Tr.t(page.archiveMode ? "Arxivdan chiqarish" : "Arxivlash"),
                        icon: page.archiveMode ? "unarchive" : "archive", run: () => page.doArchive(chatId, !page.archiveMode) })
        if (store.folders.length > 0)
            acts.push({ text: Tr.t("Papkaga qo'shish"), icon: "folder", run: () => page.openFolderPicker(chatId) })
        acts.push({ text: Tr.t("Tanlash"), icon: "select", run: () => page.enterEdit(chatId) })
        let needGap = true
        if (ty === "chatTypePrivate" || ty === "chatTypeBasicGroup") {
            acts.push({ text: Tr.t("Tarixni tozalash"), icon: "trash", danger: true, gap: needGap, run: () => page.askClearHistory(chatId) })
            needGap = false
        }
        acts.push({ text: Tr.t(isChan ? "Kanaldan chiqish" : isGroup ? "Guruhdan chiqish" : "Chatni o'chirish"),
                    icon: "trash", danger: true, gap: needGap, run: () => page.askDeleteChat(chatId) })
        chatMenu.show(chatId, acts)
    }
    function openArchiveMenu() {
        const s = store.archiveSettings || {}
        const items = [
            { text: Tr.t(store.archiveHidden ? "Asosiy ro'yxatda ko'rsatish" : "Asosiy ro'yxatdan yashirish"),
              icon: store.archiveHidden ? "eye" : "eyeoff",
              run: () => {
                  store.archiveHidden = !store.archiveHidden
                  page.nav.say(Tr.t(store.archiveHidden ? "Arxiv yashirildi. Ko'rsatish uchun pastga torting" : "Asosiy ro'yxatda ko'rsatish"))
              } },
            { text: Tr.t("Ovozlilarni arxivda saqlash"), icon: "archive", checked: !!s.keep_unmuted_chats_archived,
              run: () => store.setArchiveSettings({ keep_unmuted_chats_archived: !s.keep_unmuted_chats_archived }, () => page.nav.say(Tr.t("Sozlamalar saqlandi"))) },
            { text: Tr.t("Papkalardagilarni arxivda saqlash"), icon: "folder", checked: !!s.keep_chats_from_folders_archived,
              run: () => store.setArchiveSettings({ keep_chats_from_folders_archived: !s.keep_chats_from_folders_archived }, () => page.nav.say(Tr.t("Sozlamalar saqlandi"))) }
        ]
        chatMenu.showList(Tr.t("Arxiv sozlamalari"), items)
    }

    // ---- Bulk actions in Edit mode ----
    function bulkRead() {
        const ids = pickedIds()
        if (!ids.length)
            return
        for (const id of ids)
            store.toggleUnreadChat(id, false)
        exitEdit()
        page.nav.say(Tr.n("%1 ta chat o'qildi", ids.length))
    }
    function bulkArchive() {
        const ids = pickedIds()
        if (!ids.length)
            return
        const toArchive = !archiveMode
        for (const id of ids)
            if (!store.isSaved(store.chats[id]))
                store.archiveChat(id, toArchive)
        exitEdit()
        page.nav.say(Tr.n(toArchive ? "%1 ta chat arxivlandi" : "%1 ta chat arxivdan chiqarildi", ids.length))
    }
    function bulkDeleteAsk() {
        // Saved Messages is never deleted in bulk (only from its own menu, asked alone)
        const ids = pickedIds().filter((id) => store.chats[id] && !store.isSaved(store.chats[id]))
        if (!ids.length)
            return page.nav.say(Tr.t("Saqlangan xabarlar bu yerdan o'chirilmaydi"))
        alert.show(Tr.t("Chatlarni o'chirish"), Tr.n("Tanlangan %1 ta chat o'chirilsinmi?", ids.length), [
            { t: Tr.t("Bekor qilish") },
            { t: Tr.t("O'chirish"), red: true, run: () => {
                for (const id of ids) {
                    const c = store.chats[id]
                    if (!c)
                        continue
                    if (c.type["@type"] === "chatTypePrivate")
                        store.clearChatHistory(id, false, true)
                    else
                        store.leaveChat(id)
                }
                page.exitEdit()
                page.nav.say(Tr.n("%1 ta chat o'chirildi", ids.length))
            } }
        ], false)
    }

    // the folders side by side (Telegram-iOS: the list slides with the finger to the next folder, the
    // chips follow), each its own list, kept as it was: going back shows it at once with its pictures
    // (one list filled afresh at each folder lit up white and put initials over every picture, IMG_0085)
    // (the sound playing: under the chips in their capsule, as iOS 26 has it -- or a capsule of its own)
    // Hikoyalar (Q): the row of ringed pictures over the search box, out when the list is pulled down past
    // 60 (or the small pictures by the title tapped), in again once the list has gone up past it
    readonly property bool anyStories: !archiveMode && (store.storiesSeen, store.storyRow.length > 0 || (!!store.me && store.hasStories(store.me.id))
                                                                  || store.storyPostingActive)
    property bool storiesOpen: false
    property bool quick: false
    readonly property real storyFull: 98
    property real storyH: storiesOpen && anyStories ? storyFull : 0
    Behavior on storyH { enabled: !page.quick; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    function pulled(l) {
        if (!archiveMode && store.folder === 0 && store.archiveHidden && store.archiveList.count > 0 && l.contentY - l.originY < -60) {
            store.archiveHidden = false
            return
        }
        if (anyStories && !storiesOpen && l.contentY - l.originY < -60)
            storiesOpen = true
    }
    function scrolled(l) {
        if (!storiesOpen || l.contentY - l.originY <= storyFull + 2)
            return
        // gone up under the title: folded at once, nothing moves (the header 98 pt shorter, the list's origin follows
        // it and the rows stay where they are -- moving contentY too had them jump 98 pt down)
        quick = true
        storiesOpen = false
        quick = false
    }
    // stopped half way with the stories out (a pull's rebound ends where the list's top was before the header grew
    // by them, ~18 pt down -- their taps need p = 1): out or folded, whichever is nearer (Telegram-iOS)
    function settle() {
        const l = list
        if (archiveMode || !storiesOpen || !l || l.moving)
            return
        const s = l.contentY - l.originY
        if (s <= 0.5 || s > storyFull + 2)
            return
        snapAnim.target = l
        snapAnim.to = s < storyFull / 2 ? l.originY : l.originY + storyFull + 3
        snapAnim.restart()
    }
    NumberAnimation { id: snapAnim; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }
    Timer { id: settleSoon; interval: 300; onTriggered: page.settle() }
    // our story starts going up (StoryCreatePage gone at once): the list to its top, the stories row out, so the
    // ring round «Hikoyam» shows how far it is (Telegram-iOS)
    Connections {
        target: store
        function onStoryPostingActiveChanged() {
            if (!store.storyPostingActive || page.archiveMode)
                return
            if (page.list)
                page.list.contentY = page.list.originY
            page.storiesOpen = true
        }
    }
    function newStory() {
        if (typeof root.storyCreate === "function")
            root.storyCreate()
        else
            root.say(Tr.t("Hikoya joylash hozircha yo'q"))
    }
    function openStories(chatId) {
        const me = store.me ? store.me.id : 0
        if (chatId === me) {
            if (store.hasStories(me))
                root.stories().show([me], 0)
            else
                newStory()
            return
        }
        const row = store.storyRow
        if (row.indexOf(chatId) < 0)
            root.stories().show([chatId], 0)
        else
            root.stories().show(row, row.indexOf(chatId))
    }
    readonly property real headHeight: archiveMode
        ? 56
        : 104 + storyH + (store.folders.length || miniList.on ? 52 - (store.folders.length ? 0 : 44) + miniList.height : 0)
    readonly property ListView list: pager.currentItem ? pager.currentItem.rows : null
    // Telegram-iOS (owner's video 11-25): the title row stays; the stories and the search box go up under it as
    // the list goes up, the folders stop right under the title, the chats pass under them. scrollS: how far the shown
    // list is up (below 0: pulled down); pinH: what stays; collapse: what goes; shownHead: the header's height now
    readonly property real scrollS: list && !archiveMode ? list.contentY - list.originY : 0
    readonly property real pinH: archiveMode ? headHeight
                                 : (store.folders.length || miniList.on ? headHeight - storyH - 50 : 50)
    readonly property real collapse: headHeight - pinH
    readonly property real shownHead: archiveMode ? headHeight : Math.max(pinH, headHeight - scrollS)
    // the stories out (1) or folded by the title (0): pulled out by the finger, gone back in as the list goes up
    readonly property real storyP: anyStories ? Math.max(0, Math.min(1, (storyH - scrollS) / storyFull)) : 0
    ListView {
        id: pager
        anchors.fill: parent
        orientation: ListView.Horizontal
        model: page.tabs
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        interactive: page.pagerWants && page.pagerArmed
        flickDeceleration: 4000
        highlightMoveDuration: 400
        cacheBuffer: width * Math.max(1, page.tabs.length)      // all of them made, none dropped
        currentIndex: page.tabIndex
        onMovementEnded: settleTimer.restart()
        onInteractiveChanged: settleTimer.restart()
        onCurrentIndexChanged: {
            settleTimer.restart()           // (a chip's tap moves it with no movement of its own)
            if (!page.archiveMode && currentIndex !== page.tabIndex && page.tabs[currentIndex]) {
                page.closeSwipe()
                page.align()
                store.showFolder(page.tabs[currentIndex].id)
            }
        }
        delegate: Item {
            id: folderPage
            required property var modelData
            readonly property ListView rows: rows
            width: pager.width; height: pager.height
            clip: true          // nothing of a folder over its neighbour
            ListView {
                id: rows
                anchors.fill: parent
                Component.onCompleted: model = store.modelOf(folderPage.modelData.id)
                cacheBuffer: 600
                reuseItems: true
                boundsBehavior: Flickable.DragOverBounds
                onMovementStarted: { snapAnim.stop(); if (page.swipedChatId !== null) page.closeSwipe() }
                onMovementEnded: settleSoon.restart()
                // the list reordered under an open row (a message came, a chat was pinned): the discs follow it.
                // (ListModel's rowsMoved/Inserted/Removed and dataChanged are not QML's: a row comes or goes --
                // its count; one moves -- Store.rowMoved)
                Connections {
                    target: rows.model
                    enabled: page.swipedChatId !== null && page.swipedListId === folderPage.modelData.id
                    function onCountChanged() { page.relocateSwipe(rows) }
                }
                Connections {
                    target: store
                    enabled: page.swipedChatId !== null && page.swipedListId === folderPage.modelData.id
                    function onRowMoved(listId) { if (listId === folderPage.modelData.id) page.relocateSwipe(rows) }
                }
                onDragEnded: page.pulled(rows)
                onContentYChanged: if (page.storiesOpen) page.scrolled(rows)
                onAtYEndChanged: if (atYEnd && page.archiveMode && store.archiveList.count > 0) store.loadArchive(50)
                maximumFlickVelocity: 6000
                flickDeceleration: 2200
                header: Item {
                    id: hdr
                    width: rows.width
                    readonly property bool showArchive: !page.archiveMode && folderPage.modelData.id === 0
                                                        && store.archiveSeen >= 0 && store.archiveList.count > 0 && !store.archiveHidden
                    height: page.headHeight + (showArchive ? 76 : 0)

                    // Pull-down hint when Archive row is hidden
                    Text {
                        visible: !page.archiveMode && folderPage.modelData.id === 0 && store.archiveSeen >= 0
                                 && store.archiveList.count > 0 && store.archiveHidden
                                 && (rows.contentY - rows.originY < -18)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: page.headHeight - 24
                        text: Tr.t("Arxivni ko'rsatish uchun qo'yib yuboring")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }

                    // Archive row at the top of the main list (single instance, 0 objects in rowDelegate)
                    Item {
                        id: archiveRow
                        visible: hdr.showArchive
                        y: page.headHeight
                        width: parent.width; height: 76
                        clip: true
                        property real slide: 0
                        readonly property var topRow: (store.archiveSeen >= 0 && store.archiveList.count > 0) ? store.archiveList.get(0) : null
                        readonly property int unreadN: (store.archiveSeen >= 0) ? store.archiveUnreadCount() : 0

                        // Right-side "Yashirish" reveal button
                        Rectangle {
                            x: parent.width + archiveRow.slide
                            width: 84; height: parent.height
                            color: Theme.mutedBadge
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 20; height: 20; name: "eyeoff"; color: "white" }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Tr.t("Yashirish")
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    archiveRow.slide = 0
                                    store.archiveHidden = true
                                    page.nav.say(Tr.t("Arxiv yashirildi. Ko'rsatish uchun pastga torting"))
                                }
                            }
                        }

                        Rectangle {
                            id: archInner
                            x: archiveRow.slide
                            width: parent.width; height: parent.height
                            color: archHit.pressed && !archHit.dragging ? Theme.highlight : Theme.bg
                            Behavior on x { enabled: !archHit.dragging; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                            Rectangle {
                                x: 10; y: 8; width: 60; height: 60; radius: 30
                                color: store.unreadArchiveUnmuted > 0 ? Theme.accent : Theme.mutedBadge
                                Icon { anchors.centerIn: parent; width: 28; height: 28; name: "archive"; color: "white" }
                            }
                            Text {
                                x: 80; y: 9
                                width: parent.width - 100 - archCount.width
                                text: Tr.t("Arxiv")
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            Text {
                                id: archCount
                                x: parent.width - width - 14; y: 11
                                text: Tr.n("%1 ta chat", store.archiveList.count)
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 13
                            }
                            Text {
                                x: 80; y: 31
                                width: parent.width - 80 - (archPill.visible ? archPill.width + 22 : 14)
                                text: archiveRow.topRow ? archiveRow.topRow.title : ""
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 15
                            }
                            Text {
                                x: 80; y: 50
                                width: parent.width - 80 - (archPill.visible ? archPill.width + 22 : 14)
                                text: archiveRow.topRow
                                      ? ((archiveRow.topRow.who ? archiveRow.topRow.who + ": " : "") + archiveRow.topRow.preview)
                                      : ""
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 15
                            }
                            Rectangle {
                                id: archPill
                                visible: archiveRow.unreadN > 0
                                x: parent.width - width - 14; y: 40
                                height: 22; radius: 11
                                width: Math.max(22, archBadgeTxt.implicitWidth + 14)
                                color: store.unreadArchiveUnmuted > 0 ? Theme.badge : Theme.mutedBadge
                                Text {
                                    id: archBadgeTxt
                                    anchors.centerIn: parent
                                    text: archiveRow.unreadN > 999 ? Math.floor(archiveRow.unreadN / 1000) + "K" : archiveRow.unreadN
                                    color: store.unreadArchiveUnmuted > 0 ? Theme.badgeText : "white"
                                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                            }
                            Rectangle {
                                x: 80; y: parent.height - 0.5
                                width: parent.width - x; height: 0.5
                                color: Theme.separator
                            }
                            Timer {
                                id: archHold
                                interval: 420
                                onTriggered: {
                                    if (!archHit.pressed || archHit.dragging)
                                        return
                                    archHit.held = true
                                    page.openArchiveMenu()
                                }
                            }
                            MouseArea {
                                id: archHit
                                anchors.fill: parent
                                property real x0: 0
                                property real y0: 0
                                property real s0: 0
                                property bool dragging: false
                                property bool held: false
                                onPressed: (m) => {
                                    x0 = m.x; y0 = m.y; s0 = archiveRow.slide
                                    dragging = false; held = false; preventStealing = false
                                    if (page.swipedChatId !== null)
                                        page.closeSwipe()
                                    if (s0 === 0)
                                        archHold.restart()
                                }
                                onPositionChanged: (m) => {
                                    if (held)
                                        return
                                    const dx = m.x - x0, dy = m.y - y0
                                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10)
                                        archHold.stop()
                                    if (!dragging && Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(dy)) {
                                        dragging = true
                                        preventStealing = true
                                    }
                                    if (dragging)
                                        archiveRow.slide = Math.max(-84, Math.min(0, s0 + dx))
                                }
                                onReleased: {
                                    archHold.stop()
                                    preventStealing = false
                                    if (held) { held = false; return }
                                    if (dragging) {
                                        dragging = false
                                        archiveRow.slide = archiveRow.slide < -36 ? -84 : 0
                                        return
                                    }
                                    if (s0 < 0)
                                        archiveRow.slide = 0
                                    else
                                        page.openArchive()
                                }
                                onCanceled: {
                                    archHold.stop()
                                    dragging = false
                                    preventStealing = false
                                    archiveRow.slide = 0
                                }
                            }
                        }
                    }
                }
                footer: Item {
                    width: 1
                    height: page.archiveMode ? ((page.editing ? 68 : 24) + safe.bottom)
                                             : (page.editing ? 68 + safe.bottom : 90)
                }
                delegate: rowDelegate

                // Single list-level gesture handler (tap, long-press, horizontal swipe) — 0 objects in rowDelegate
                Timer {
                    id: holdTimer
                    interval: 420
                    onTriggered: {
                        if (!listHit.pressed || listHit.dragged || page.editing || !listHit.hitRow)
                            return
                        listHit.held = true
                        listHit.preventStealing = true
                        page.pressedChatId = null
                        page.openRowMenu(listHit.hitChatId, folderPage.modelData.id)
                    }
                }
                MouseArea {
                    id: listHit
                    anchors.fill: parent
                    property real x0: 0
                    property real y0: 0
                    property real startSwipe: 0
                    property var hitRow: null
                    property var hitChatId: null
                    property bool dragged: false
                    property bool held: false
                    property bool hadSwipe: false
                    onPressed: (m) => {
                        const cy = m.y + rows.contentY
                        const r = rows.itemAt(m.x, cy)
                        if (!r || r.chatId === undefined) {
                            m.accepted = false
                            return
                        }
                        x0 = m.x; y0 = m.y
                        hitRow = r; hitChatId = r.chatId
                        dragged = false; held = false
                        preventStealing = false
                        hadSwipe = page.swipedChatId !== null && page.swipedChatId !== r.chatId
                        // (+ 18: ztMETRO takes the outer 18 pt of each side for its own gestures, EDGE in ztmetro.c --
                        // a row's swipe there never reaches us, so the iOS zone starts inside it)
                        const edge = Math.max(22, Math.min(page.width / 6, 80)) + 18
                        page.edgePress = !hadSwipe && !page.editing && (m.x < edge || m.x > width - edge)
                        if (hadSwipe) {
                            page.closeSwipe()
                            return
                        }
                        startSwipe = page.swipedChatId === r.chatId ? page.swipeX : 0
                        if (startSwipe === 0) {
                            const ly = cy - r.y
                            const onStory = !page.editing && r.storied && m.x >= 6 && m.x < 74 && ly >= 4 && ly < 72
                            page.pressedChatId = onStory ? null : r.chatId
                            if (!page.editing && !onStory)
                                holdTimer.restart()
                        }
                    }
                    onPositionChanged: (m) => {
                        if (held || hadSwipe || !hitRow)
                            return
                        const dx = m.x - x0, dy = m.y - y0
                        if (!dragged) {
                            if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                                holdTimer.stop()
                                page.pressedChatId = null
                            }
                            if (page.editing)
                                return
                            if (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(dy)) {
                                // from the middle, with folders, the pager takes it (it steals the press)
                                if (startSwipe === 0 && !page.edgePress && pager.interactive)
                                    return
                                dragged = true
                                preventStealing = true
                                page.swiping = true
                                page.swipedChatId = hitChatId
                                page.swipedRowY = hitRow.y
                                page.swipedListId = folderPage.modelData.id
                            }
                        }
                        if (dragged) {
                            const nx = Math.max(-page.leftSwipeW, Math.min(page.rightSwipeW, startSwipe + dx))
                            page.swipeX = nx
                        }
                    }
                    onReleased: (m) => {
                        holdTimer.stop()
                        page.edgePress = false
                        page.pressedChatId = null
                        if (held || hadSwipe) {
                            held = false; hadSwipe = false; preventStealing = false
                            return
                        }
                        if (dragged) {
                            dragged = false
                            preventStealing = false
                            page.swiping = false
                            if (page.swipeX < -55)
                                page.swipeX = -page.leftSwipeW
                            else if (page.swipeX > 45)
                                page.swipeX = page.rightSwipeW
                            else
                                page.closeSwipe()
                            return
                        }
                        if (startSwipe !== 0) {
                            page.closeSwipe()
                            return
                        }
                        if (!hitRow || hitChatId === null)
                            return
                        const cy = m.y + rows.contentY
                        const r = rows.itemAt(m.x, cy)
                        if (!r || r.chatId !== hitChatId)
                            return
                        if (page.editing) {
                            page.togglePick(r.chatId)
                            return
                        }
                        const ly = cy - r.y
                        if (r.storied && m.x >= 6 && m.x < 74 && ly >= 4 && ly < 72)
                            page.openStories(r.chatId)
                        else
                            page.openChat(r.chatId)
                    }
                    onCanceled: {
                        holdTimer.stop()
                        page.edgePress = false
                        page.pressedChatId = null
                        if (dragged) {
                            dragged = false
                            page.swiping = false
                            page.closeSwipe()
                        }
                        preventStealing = false
                    }
                }
            }

            // Revealed swipe action strip (single list-level Loader, active only while a row is swiped)
            Loader {
                id: swipeBar
                z: 5
                readonly property bool on: page.swipedChatId !== null && page.swipedListId === folderPage.modelData.id && Math.abs(page.swipeX) > 1
                active: on
                x: page.swipeX < 0 ? Math.max(0, rows.width + page.swipeX) : 0
                y: page.swipedRowY - rows.contentY
                width: Math.min(rows.width, Math.abs(page.swipeX))
                height: 76
                clip: true
                sourceComponent: on ? (page.swipeX < 0 ? leftSwipeComp : rightSwipeComp) : null
            }
        }
    }
    // the finger over the pager, seen by a passive grab (above the pager: told of the press before the pager and the
    // rows are, and of its release whoever took it)
    Item {
        anchors.fill: pager
        PointHandler {
            id: fingerDown
            target: null
            grabPermissions: PointerHandler.ApprovesTakeOverByAnything
            onActiveChanged: {
                page.pagerArmed = active ? page.pagerWants : true
                if (!active)
                    settleTimer.restart()
            }
        }
    }
    // never left between two folders: once all has stopped (after the pager's own 400 ms snap), back to a whole one
    Timer {
        id: settleTimer
        interval: 450
        onTriggered: {
            if (pager.width <= 0)
                return
            if (fingerDown.active || pager.dragging || pager.flicking || pager.moving) {
                restart()               // (not yet still: again later -- a glide may end with no movementEnded)
                return
            }
            const to = pager.originX + pager.currentIndex * pager.width
            if (Math.abs(pager.contentX - to) > 0.5) {
                settleAnim.to = to
                settleAnim.restart()
            }
            page.topOthers()
        }
    }
    // the folders not shown back to their top (owner 11-25: a folder came back where it was left, it should start
    // from its first chat), the title bar as far up as the shown one's (no jump when the next one comes)
    function topOthers() {
        const cur = page.list
        const pages = pager.contentItem ? pager.contentItem.children : null
        if (!cur || !pages)
            return
        const off = Math.min(cur.contentY - cur.originY, page.collapse)
        for (let i = 0; i < pages.length; i++) {
            const lv = pages[i].rows
            // (not past its end: a short folder would spring back under the finger later)
            const to = lv ? lv.originY + Math.max(0, Math.min(off, lv.contentHeight - lv.height)) : 0
            if (!lv || lv === cur || lv.dragging || Math.abs(lv.contentY - to) <= 0.5)
                continue
            lv.cancelFlick()            // (still gliding from before the folder turned: it would carry on from there)
            lv.contentY = to
        }
    }
    NumberAnimation { id: settleAnim; target: pager; property: "contentX"; duration: 200; easing.type: Easing.OutCubic }

    // Empty archive placeholder
    Column {
        visible: page.archiveMode && store.archiveSeen >= 0 && store.archiveList.count === 0
        anchors.centerIn: parent
        spacing: 10
        Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 48; height: 48; name: "archive"; color: Theme.grey }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Arxivda chat yo'q")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 16
        }
    }

    // Swipe action strips (instantiated only while a row is swiped): laid out as Telegram-iOS's ItemListRevealOptionsNode
    // (a 50 pt slot per action, 10 apart and 10 from the edge, an 11 pt grey title under it, grown from 0.3 as the row
    // opens), drawn Nullgram's way (owner's choice 2026-11-25): no filled disc, the logo's null ring in the action's
    // colour round its glyph (Icons.js nr*); «off» actions are ∅. Colours: iOS's itemDisclosureActions by day (grey
    // darkened to read without a disc), the system ones at night.
    readonly property var swipeColors: Theme.dark
        ? { mute: "#ff9f0a", del: "#ff453a", grey: "#98989f", pin: "#30d158", unread: Theme.accent }
        : { mute: "#f09a37", del: "#ff3824", grey: "#8e8e93", pin: "#00c900", unread: Theme.accent }
    component SwipeOption: Item {
        id: opt
        property string glyph
        property string title
        property color fill
        property real reveal: 1
        signal hit()
        width: 60; height: 76
        Icon {
            x: 5; y: 4; width: 50; height: 50
            name: opt.glyph; color: opt.fill
            scale: 0.3 + 0.7 * opt.reveal
            opacity: optHit.pressed ? 0.5 : 1
        }
        Text {
            y: 58; width: parent.width
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
            text: opt.title
            color: Theme.grey
            opacity: opt.reveal
            font.family: Theme.font; font.pixelSize: 11
        }
        MouseArea { id: optHit; anchors.fill: parent; onClicked: opt.hit() }
    }
    Component {
        id: leftSwipeComp
        Rectangle {
            id: strip
            anchors.right: parent ? parent.right : undefined
            width: page.leftSwipeW; height: 76
            color: Theme.bg
            readonly property var chat: (store.seen >= 0 && page.swipedChatId !== null) ? store.chats[page.swipedChatId] : null
            readonly property bool muted: page.isChatMuted(chat)
            readonly property real reveal: Math.min(1, Math.abs(page.swipeX) / width)
            Row {
                x: 5
                SwipeOption {
                    glyph: strip.muted ? "nrbell" : "nrmute"
                    title: Tr.t(strip.muted ? "Ovozli qilish" : "Ovozsiz")
                    fill: page.swipeColors.mute; reveal: strip.reveal
                    onHit: { const id = page.swipedChatId; page.closeSwipe(); if (id !== null) page.doMute(id) }
                }
                SwipeOption {
                    glyph: "nrtrash"
                    title: Tr.t("O'chirish")
                    fill: page.swipeColors.del; reveal: strip.reveal
                    onHit: { const id = page.swipedChatId; page.closeSwipe(); if (id !== null) page.askDeleteChat(id) }
                }
                SwipeOption {
                    glyph: page.archiveMode ? "nrunarchive" : "nrarchive"
                    // («Chiqarish» alone is MembersPage's «Remove» in lang-en; the English here is «Arxivdan chiqarish»'s)
                    title: page.archiveMode ? (Tr.en ? Tr.t("Arxivdan chiqarish") : "Chiqarish") : Tr.t("Arxivlash")
                    fill: page.swipeColors.grey; reveal: strip.reveal
                    onHit: { const id = page.swipedChatId; page.closeSwipe(); if (id !== null) page.doArchive(id, !page.archiveMode) }
                }
            }
        }
    }
    Component {
        id: rightSwipeComp
        Rectangle {
            id: strip
            anchors.left: parent ? parent.left : undefined
            width: page.rightSwipeW; height: 76
            color: Theme.bg
            readonly property var chat: (store.seen >= 0 && page.swipedChatId !== null) ? store.chats[page.swipedChatId] : null
            readonly property bool unread: page.isChatUnread(chat)
            readonly property bool pinned: page.isChatPinned(chat, page.swipedListId)
            readonly property real reveal: Math.min(1, Math.abs(page.swipeX) / width)
            Row {
                x: 5
                SwipeOption {
                    glyph: strip.unread ? "nrread" : "nrunread"
                    title: Tr.t(strip.unread ? "O'qildi" : "O'qilmagan")
                    fill: strip.unread ? page.swipeColors.grey : page.swipeColors.unread; reveal: strip.reveal
                    onHit: { const id = page.swipedChatId; page.closeSwipe(); if (id !== null) page.doToggleUnread(id) }
                }
                SwipeOption {
                    glyph: strip.pinned ? "nrunpin" : "nrpin"
                    title: Tr.t(strip.pinned ? "Yechish" : "Qadash")
                    fill: page.swipeColors.pin; reveal: strip.reveal
                    onHit: {
                        const id = page.swipedChatId, lid = page.swipedListId
                        page.closeSwipe()
                        if (id !== null)
                            page.doTogglePin(id, lid)
                    }
                }
            }
        }
    }

    // a folder comes in with the title where the one before had it (when both are near their tops)
    function align() {
        const l = list
        const off = l ? l.contentY - l.originY : 0
        Qt.callLater(() => {
            const n = page.list
            if (!n || off >= page.collapse || n.contentY - n.originY >= page.collapse)
                return
            n.contentY = n.originY + off
        })
    }

    // over the lists: the title, the search box, the folder chips. The title row stays; the stories and the search box
    // go up under it with the list shown, the chips stop right under it and the chats pass under them (Telegram-iOS;
    // in archiveMode: fixed 56pt navigation bar with back, title, Edit and ••• menu)
    Item {
        id: head
        width: parent.width; height: page.shownHead
        Rectangle { z: -2; anchors.fill: parent; color: Theme.bg }
        Rectangle {         // a hairline under what stays once the chats pass under it
            visible: !page.archiveMode && page.scrollS > page.collapse + 1
            anchors.bottom: parent.bottom
            width: parent.width; height: 0.5
            color: Theme.separator
        }

        // Back button (archiveMode) or Edit/Done button (main list, top-left as on iOS)
        Text {
            visible: page.archiveMode
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            opacity: archBackHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea {
            id: archBackHit
            visible: page.archiveMode
            width: 64; height: parent.height
            onClicked: if (page.editing) page.exitEdit(); else page.nav.pop()
        }
        Text {
            visible: !page.archiveMode
            x: 16; y: 16
            text: page.editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")
            color: Theme.accent
            opacity: editTopHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 16; font.weight: page.editing ? Font.DemiBold : Font.Normal
        }
        MouseArea {
            id: editTopHit
            visible: !page.archiveMode
            x: 0; y: 0; width: 108; height: 48
            onClicked: page.editing ? page.exitEdit() : page.enterEdit()
        }

        // ⊕ by ✎ (main list): a new story (StoryCreatePage; docs/reja-sarlavha.md step 5)
        Icon {
            visible: !page.archiveMode && !page.editing
            anchors.right: parent.right; anchors.rightMargin: 52
            y: 14
            width: 25; height: 25
            name: "storyadd"
            color: Theme.accent
            opacity: storyAddHit.pressed ? 0.4 : 1
        }
        MouseArea {
            id: storyAddHit
            visible: !page.archiveMode && !page.editing
            anchors.right: parent.right; anchors.rightMargin: 46
            width: 38; height: 52
            onClicked: page.newStory()
        }

        // ✎ top-right (main list): a new message, group or channel (NewChatPage, nav.newChat)
        Icon {
            visible: !page.archiveMode && !page.editing
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 14
            width: 25; height: 25
            name: "compose"
            color: Theme.accent
            opacity: composeHit.pressed ? 0.4 : 1
        }
        MouseArea {
            id: composeHit
            visible: !page.archiveMode && !page.editing
            anchors.right: parent.right
            width: 52; height: 52
            onClicked: page.nav.newChat()
        }

        // Archive mode top-right: Edit/Done and ••• menu
        Text {
            id: archEditText
            visible: page.archiveMode
            anchors.right: parent.right; anchors.rightMargin: page.editing ? 16 : 46
            anchors.verticalCenter: parent.verticalCenter
            text: page.editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")
            color: Theme.accent
            opacity: archEditHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 16; font.weight: page.editing ? Font.DemiBold : Font.Normal
        }
        MouseArea {
            id: archEditHit
            visible: page.archiveMode
            anchors.right: parent.right; anchors.rightMargin: page.editing ? 0 : 38
            width: archEditText.implicitWidth + 24; height: parent.height
            onClicked: page.editing ? page.exitEdit() : page.enterEdit()
        }
        Icon {
            visible: page.archiveMode && !page.editing
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22
            name: "more"
            color: Theme.accent
            opacity: archMoreHit.pressed ? 0.4 : 1
        }
        MouseArea {
            id: archMoreHit
            visible: page.archiveMode && !page.editing
            anchors.right: parent.right
            width: 40; height: parent.height
            onClicked: page.openArchiveMenu()
        }

        Row {
            id: titleRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: page.archiveMode ? Math.round((parent.height - height) / 2) : 16
            spacing: 6
            Item {          // the stories folded: up to three small pictures by the title
                id: foldedStories
                visible: !page.archiveMode && !page.editing && page.anyStories
                opacity: page.storyP > 0 ? 0 : 1
                width: visible ? 22 + 14 * (Math.max(1, Math.min(3, store.storyRow.length)) - 1) : 0; height: 22
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: page.archiveMode ? [] : (store.storiesSeen, store.storyRow.slice(0, 3))
                    StoryAvatar {
                        required property var modelData
                        required property int index
                        x: index * 14; z: 3 - index
                        chatId: modelData
                        size: 22
                    }
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    enabled: page.storyP === 0
                    onClicked: {
                        if (page.list && page.scrollS > 0)
                            page.list.contentY = page.list.originY
                        page.storiesOpen = true
                    }
                }
            }
            Text {
                // between «Tahrirlash» (or ‹) and ✎ (or •••): a long «tarmoq kutilmoqda...» ran over them
                width: Math.min(implicitWidth, head.width - 2 * 112 - (foldedStories.visible ? foldedStories.width + 6 : 0))
                elide: Text.ElideRight
                text: page.editing && page.pickedCount > 0
                      ? Tr.n("%1 tanlandi", page.pickedCount)
                      : page.archiveMode ? Tr.t("Arxiv") : (store.connection || Tr.t("Chatlar"))
                color: !page.archiveMode && !page.editing && store.connection ? Theme.grey : Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
        }
        Rectangle {
            visible: page.archiveMode
            anchors.bottom: parent.bottom
            width: parent.width; height: 0.5
            color: Theme.separator
        }
        // the stories out: Mening hikoyam, then the others' (unseen first). Not cut by the collapser: as the list
        // is pulled from the top the folded pictures by the title grow and fly down into this row with the finger,
        // and as it goes up they shrink and fly back (storyP, 0 folded .. 1 out; Telegram-iOS). The band sits just
        // over the search box, 98·p high; each picture is drawn at 64 and scaled (no ring redrawn each frame)
        ListView {
            id: storyList
            readonly property real p: page.storyP
            // where the folded pictures are, in head's own coordinates (the title row moves only with its text)
            readonly property point fold: Qt.point(titleRow.x + foldedStories.x, titleRow.y + foldedStories.y)
            y: 46 + page.storyH - page.scrollS - page.storyFull * p
            z: 1
            width: parent.width; height: page.storyFull * p
            visible: !page.archiveMode && p > 0
            interactive: p >= 1
            orientation: ListView.Horizontal
            leftMargin: 8; rightMargin: 8
            spacing: 2
            model: page.archiveMode ? [] : (store.storiesSeen, [store.me ? store.me.id : 0].concat(store.storyRow))
            delegate: Item {
                id: st
                required property var modelData
                required property int index
                readonly property bool mine: index === 0
                // which folded picture it flies to: the three first of the others; Hikoyam and the rest fade by them
                readonly property int k: Math.max(0, Math.min(2, index - 1))
                readonly property bool folds: index >= 1 && index <= 3
                width: 74; height: page.storyFull
                StoryAvatar {
                    id: sav
                    readonly property real q: 1 - storyList.p
                    x: 5 + q * (storyList.fold.x + st.k * 14 - (st.x - storyList.contentX) - 5)
                    y: 4 + q * (storyList.fold.y - storyList.y - 4)
                    z: 3 - st.k
                    scale: 1 - q * (1 - 22 / 64)
                    transformOrigin: Item.TopLeft
                    opacity: st.folds ? 1 : storyList.p
                    chatId: st.modelData
                    size: 64
                    plus: st.mine && !store.storyPostingActive
                    Ring {          // ours being posted: how far (store.storyPosting, agy/hikoya-joylash)
                        visible: st.mine && store.storyPostingActive
                        anchors.fill: parent
                        value: store.storyPosting
                        color: Theme.accent
                        thickness: 2.6
                        cross: false
                    }
                }
                Text {          // under its picture wherever it is; only the last third of the way out
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: sav.y + 64 * sav.scale + 4
                    width: parent.width - 4
                    opacity: Math.max(0, storyList.p * 3 - 2)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: st.mine ? Tr.t("Hikoyam") : (store.seen, store.chats[st.modelData] ? store.chats[st.modelData].title.split(" ")[0] : "")
                    color: !st.mine && (store.storiesSeen, !store.unseen(st.modelData)) ? Theme.grey : Theme.text
                    font.family: Theme.font; font.pixelSize: 12
                }
                MouseArea { anchors.fill: parent; enabled: storyList.p >= 1; onClicked: page.openStories(st.modelData) }
            }
        }
        Item {              // what goes up under the title row (the search box; the stories' band over it): cut at its edge,
            id: collapser   // taps too -- nothing under the title takes its taps
            visible: !page.archiveMode
            y: 46; z: -1
            width: parent.width; height: Math.max(0, page.shownHead - 46)
            clip: true
            Rectangle {          // the search box: a tap opens the search
                visible: !page.archiveMode
                x: 14
                width: parent.width - 28; height: 38; radius: 19
                color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
                y: 6 + page.storyH - page.scrollS
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { name: "search"; width: 18; height: 18; color: Theme.grey; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: Tr.t("Qidiruv")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 16
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: search.show() }
            }
        }
        Rectangle {          // the folders, and under them the mini player
            visible: !page.archiveMode && (store.folders.length > 0 || miniList.on)
            x: 12; y: Math.max(50, 100 + page.storyH - page.scrollS)
            width: parent.width - 24; height: (store.folders.length ? 44 : 0) + miniList.height; radius: 22
            clip: true
            color: Theme.bg
            border.color: Theme.fieldBorder; border.width: 0.5
            MiniPlayer {
                id: miniList
                y: store.folders.length ? 44 : 0
                player: page.player
                onOpened: page.player.kind !== "audio"
                          ? page.nav.push(chatPage, { chatId: page.player.chatId, target: page.player.msgId })
                          : page.player.showSheet()
                Rectangle {
                    visible: store.folders.length > 0
                    x: 14; width: parent.width - 28; height: 0.5; color: Theme.separator
                }
            }
            ListView {
                id: chips
                visible: store.folders.length > 0
                x: 4; y: 4; width: parent.width - 8; height: 36
                orientation: ListView.Horizontal
                clip: true
                spacing: 2
                model: page.tabs
                currentIndex: page.tabIndex
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                // the grey capsule goes along with the lists as they slide, between the two chips
                highlightFollowsCurrentItem: false
                highlight: Rectangle {
                    readonly property real at: pager.width > 0 ? Math.max(0, Math.min(page.tabs.length - 1, (pager.contentX - pager.originX) / pager.width)) : 0
                    readonly property Item from: chips.itemAtIndex(Math.floor(at))
                    readonly property Item to: chips.itemAtIndex(Math.ceil(at)) || from
                    readonly property real t: at - Math.floor(at)
                    x: from ? from.x + (to.x - from.x) * t : 0
                    width: from ? from.width + (to.width - from.width) * t : 0
                    height: 36
                    radius: 18; color: Theme.highlight
                }
                delegate: Item {
                    id: chip
                    required property var modelData
                    required property int index
                    readonly property int unread: modelData.id ? (store.folderUnread[modelData.id] || 0) : store.unreadChats
                    width: label.implicitWidth + (badge.visible ? badge.width + 6 : 0) + 28; height: 36
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            id: label
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.name
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 15; font.weight: chip.index === page.tabIndex ? Font.DemiBold : Font.Normal
                        }
                        Rectangle {
                            id: badge
                            visible: chip.unread > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(20, n.implicitWidth + 10); height: 20; radius: 10
                            color: Theme.mutedBadge
                            Text {
                                id: n
                                anchors.centerIn: parent
                                text: store.count(chip.unread)
                                color: "white"
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.go(chip.index) }
                }
            }
        }
    }

    // Multi-select bottom bar (respects ztMETRO's safe.bottom navigation line)
    Rectangle {
        id: editBar
        visible: page.editing
        z: 12
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 52 + safe.bottom
        color: Theme.bar
        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
        Row {
            width: parent.width; height: 52
            Item {
                width: parent.width / 3; height: 52
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("O'qildi")
                    color: page.pickedCount > 0 ? Theme.accent : Theme.grey
                    opacity: ebRead.pressed ? 0.4 : 1
                    font.family: Theme.font; font.pixelSize: 16
                }
                MouseArea { id: ebRead; anchors.fill: parent; enabled: page.pickedCount > 0; onClicked: page.bulkRead() }
            }
            Item {
                width: parent.width / 3; height: 52
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12
                    text: Tr.t(page.archiveMode ? "Arxivdan chiqarish" : "Arxivlash")
                    color: page.pickedCount > 0 ? Theme.accent : Theme.grey
                    opacity: ebArch.pressed ? 0.4 : 1
                    font.family: Theme.font; font.pixelSize: 16
                }
                MouseArea { id: ebArch; anchors.fill: parent; enabled: page.pickedCount > 0; onClicked: page.bulkArchive() }
            }
            Item {
                width: parent.width / 3; height: 52
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("O'chirish")
                    color: page.pickedCount > 0 ? Theme.danger : Theme.grey
                    opacity: ebDel.pressed ? 0.4 : 1
                    font.family: Theme.font; font.pixelSize: 16
                }
                MouseArea { id: ebDel; anchors.fill: parent; enabled: page.pickedCount > 0; onClicked: page.bulkDeleteAsk() }
            }
        }
    }

    // Optional row parts at page level, loaded via a single Loader per row only when needed
    Component {
        id: storySeenComp
        Rectangle {
            readonly property var r: parent ? parent.r : null
            x: (r ? r.editOff : 0) + 10; y: 8
            width: 60; height: 60; radius: 30
            color: "transparent"
            border.color: Theme.dark ? "#48484a" : "#c7c7cc"; border.width: 1.3
        }
    }
    Component {
        id: storyFreshComp
        Rectangle {
            id: ring
            readonly property var r: parent ? parent.r : null
            x: (r ? r.editOff : 0) + 10; y: 8
            width: 60; height: 60; radius: 30
            rotation: 45
            gradient: Gradient {
                GradientStop { position: 0; color: "#34c76f" }
                GradientStop { position: 1; color: "#3da1fd" }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 55.4; height: width; radius: width / 2
                color: ring.r ? ring.r.color : Theme.bg
            }
        }
    }
    Component {
        id: directTagComp
        Rectangle {
            id: directTag
            readonly property var r: parent ? parent.r : null
            readonly property var t: parent ? parent.t : null
            readonly property real directW: width
            x: t ? 80 + (r ? r.editOff : 0) + t.width + 6 : 80
            y: t ? 9 + Math.floor((t.height - height) / 2) : 9
            width: directLbl.implicitWidth + 10; height: 17; radius: 5
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
            Text {
                id: directLbl
                anchors.centerIn: parent
                text: "DIRECT"
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold
            }
        }
    }
    Component {
        id: whoComp
        Text {
            readonly property var r: parent ? parent.r : null
            x: 80 + (r ? r.editOff : 0); y: 31
            width: r ? r.textWidth : 0
            text: r ? r.who : ""
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: r && r.draft ? Theme.danger : Theme.text
            font.family: Theme.font; font.pixelSize: 15
        }
    }
    Component {
        id: glyphComp
        Icon {
            readonly property var r: parent ? parent.r : null
            x: 80 + (r ? r.editOff : 0); y: r && r.author ? 52 : 33
            width: 16; height: 16
            name: r ? r.glyph : ""
            color: Theme.grey
        }
    }
    Component {
        id: pillComp
        Rectangle {
            id: pill
            readonly property var r: parent ? parent.r : null
            readonly property real pillW: width
            readonly property bool dot: !!r && r.unread === 0 && r.markedUnread
            x: r ? r.width - width - 14 : 0
            y: 40
            height: 22; radius: 11
            width: r && r.unread > 0 ? Math.max(22, count.implicitWidth + 14) : 22
            color: r && (r.unread > 0 || r.markedUnread) ? (r.muted ? Theme.mutedBadge : Theme.badge) : "transparent"
            Text {
                id: count
                visible: !pill.dot
                anchors.centerIn: parent
                text: pill.r && pill.r.unread > 0 ? (pill.r.unread > 9999 ? Math.floor(pill.r.unread / 1000) + "K" : pill.r.unread) : "📌"
                color: pill.r && pill.r.unread > 0 ? (pill.r.muted ? "white" : Theme.badgeText) : Theme.grey
                font.family: Theme.font; font.pixelSize: pill.r && pill.r.unread > 0 ? 13 : 11; font.weight: Font.DemiBold
            }
        }
    }
    Component {
        id: whoPillComp
        Text {
            id: wp
            readonly property var r: parent ? parent.r : null
            readonly property real pillW: wpPill.width
            x: 80 + (r ? r.editOff : 0); y: 31
            width: r ? r.textWidth : 0
            text: r ? r.who : ""
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: r && r.draft ? Theme.danger : Theme.text
            font.family: Theme.font; font.pixelSize: 15
            Rectangle {
                id: wpPill
                readonly property bool dot: !!wp.r && wp.r.unread === 0 && wp.r.markedUnread
                x: wp.r ? wp.r.width - 80 - wp.r.editOff - width - 14 : 0
                y: 9
                height: 22; radius: 11
                width: wp.r && wp.r.unread > 0 ? Math.max(22, wpCount.implicitWidth + 14) : 22
                color: wp.r && (wp.r.unread > 0 || wp.r.markedUnread) ? (wp.r.muted ? Theme.mutedBadge : Theme.badge) : "transparent"
                Text {
                    id: wpCount
                    visible: !wpPill.dot
                    anchors.centerIn: parent
                    text: wp.r && wp.r.unread > 0 ? (wp.r.unread > 9999 ? Math.floor(wp.r.unread / 1000) + "K" : wp.r.unread) : "📌"
                    color: wp.r && wp.r.unread > 0 ? (wp.r.muted ? "white" : Theme.badgeText) : Theme.grey
                    font.family: Theme.font; font.pixelSize: wp.r && wp.r.unread > 0 ? 13 : 11; font.weight: Font.DemiBold
                }
            }
        }
    }
    Component {
        id: editCheckComp
        Rectangle {
            readonly property var r: parent ? parent.r : null
            readonly property bool on: !!r && (page.pickedSeen >= 0) && !!page.picked[r.chatId]
            x: 12; y: 26
            width: 24; height: 24; radius: 12
            color: on ? Theme.accent : "transparent"
            border.color: on ? Theme.accent : Theme.separator
            border.width: 1.5
            Icon {
                visible: parent.on
                anchors.centerIn: parent
                width: 15; height: 15
                name: "check"
                color: "white"
            }
        }
    }
    Component {
        id: multiExtrasComp
        Item {
            id: multi
            readonly property var r: parent ? parent.r : null
            readonly property var t: parent ? parent.t : null
            readonly property real pillW: mPill.item ? mPill.item.width : 22
            readonly property real directW: mDirect.item ? mDirect.item.width : 0
            Loader {
                readonly property var r: multi.r
                active: !!multi.r && multi.r.storied
                sourceComponent: active ? (multi.r.fresh ? storyFreshComp : storySeenComp) : null
            }
            Loader {
                id: mDirect
                readonly property var r: multi.r
                readonly property var t: multi.t
                active: !!multi.r && multi.r.direct
                sourceComponent: active ? directTagComp : null
            }
            Loader {
                readonly property var r: multi.r
                active: !!multi.r && multi.r.author
                sourceComponent: active ? whoComp : null
            }
            Loader {
                readonly property var r: multi.r
                active: !!multi.r && multi.r.hasGlyph
                sourceComponent: active ? glyphComp : null
            }
            Loader {
                id: mPill
                readonly property var r: multi.r
                active: !!multi.r && multi.r.hasPill
                sourceComponent: active ? pillComp : null
            }
        }
    }
    Component {
        id: multiEditExtrasComp
        Item {
            id: multiE
            readonly property var r: parent ? parent.r : null
            readonly property var t: parent ? parent.t : null
            readonly property real pillW: mePill.item ? mePill.item.width : 22
            readonly property real directW: meDirect.item ? meDirect.item.width : 0
            Loader {
                readonly property var r: multiE.r
                active: page.editing
                sourceComponent: active ? editCheckComp : null
            }
            Loader {
                readonly property var r: multiE.r
                active: !!multiE.r && multiE.r.storied
                sourceComponent: active ? (multiE.r.fresh ? storyFreshComp : storySeenComp) : null
            }
            Loader {
                id: meDirect
                readonly property var r: multiE.r
                readonly property var t: multiE.t
                active: !!multiE.r && multiE.r.direct
                sourceComponent: active ? directTagComp : null
            }
            Loader {
                readonly property var r: multiE.r
                active: !!multiE.r && multiE.r.author
                sourceComponent: active ? whoComp : null
            }
            Loader {
                readonly property var r: multiE.r
                active: !!multiE.r && multiE.r.hasGlyph
                sourceComponent: active ? glyphComp : null
            }
            Loader {
                id: mePill
                readonly property var r: multiE.r
                active: !!multiE.r && multiE.r.hasPill
                sourceComponent: active ? pillComp : null
            }
        }
    }

    Component {
        id: rowDelegate
        Rectangle {
            id: row
            required property int index
            required property var chatId
            required property string title
            required property bool saved
            required property bool direct
            required property string who
            required property bool draft
            required property string glyph
            required property string preview
            required property string time
            required property int unread
            required property bool markedUnread
            required property bool muted
            required property bool pinned
            required property string photo
            required property string letters
            required property string tint
            required property bool outgoing
            required property bool read

            // (a Translate, not x: the ListView sets a row's x to 0 when it inserts or moves it, and that broke an x
            // binding for good -- a reused row then stayed put under its open discs)
            // (only in the list shown: a chat in two folders has a row in each, and the next folder's one, moved
            // 190 pt to the left, came over the shown folder -- the phone, 11-25)
            transform: Translate { x: page.swipedChatId === row.chatId && row.ListView.view === page.list ? page.swipeX : 0 }
            width: page.width; height: 76
            color: page.litChatId === row.chatId || page.pressedChatId === row.chatId ? Theme.highlight : Theme.bg

            readonly property real editOff: page.editing ? 36 : 0
            // a story ring round it (Q); a tap on the picture then opens the stories, not the chat
            readonly property bool storied: !row.saved && store.storiesSeen >= 0 && !!store.stories[row.chatId]
            readonly property bool fresh: row.storied && store.storiesSeen >= 0 && store.unseen(row.chatId)

            Avatar {
                z: 1
                x: row.editOff + (row.storied ? 15 : 10); y: row.storied ? 13 : 8
                width: row.storied ? 50 : 60; height: width
                source: row.photo; letters: row.letters; tint: row.tint; saved: row.saved
            }
            Text {
                id: titleText
                x: 80 + row.editOff; y: 9
                width: Math.min(implicitWidth, row.width - 100 - row.editOff - stamp.width - (row.direct ? row.directW + 6 : 0))
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                id: stamp
                x: row.width - width - 14
                y: 11
                text: (row.outgoing ? (row.read ? "✓✓ " : "✓ ") : "") + row.time
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            // under the name, as Telegram-iOS: who wrote it (a group's sender, «Siz», a red «Qoralama») on a
            // line of its own and the text under it on one; with no one, the text on two. Typing: in their place
            property int acted: 0       // its own chat's actions changed (Store.actionChanged, dispatched by page)
            readonly property string busy: row.acted >= 0 && store.actions[row.chatId] ? store.activity(store.chats[row.chatId]) : ""
            readonly property bool author: row.who !== "" && busy === ""
            // (by the data, not pill.visible / glyph.visible: those read false while the list's page is
            // hidden under a chat, and every row of every folder was laid out again as it hid and showed)
            readonly property bool hasPill: row.unread > 0 || row.markedUnread || row.pinned
            readonly property bool hasGlyph: row.glyph !== "" && row.busy === ""
            readonly property int extraMask: (row.author ? 1 : 0) | (row.hasPill ? 2 : 0) | (row.hasGlyph ? 4 : 0)
                                           | (row.direct ? 8 : 0) | (row.storied ? (row.fresh ? 32 : 16) : 0)
                                           | (page.editing ? 64 : 0)
            readonly property real pillW: row.hasPill && extras.item && extras.item.pillW ? extras.item.pillW : 22
            readonly property real directW: row.direct && extras.item && extras.item.directW ? extras.item.directW : 0
            readonly property real textWidth: width - 80 - row.editOff - (hasPill ? pillW + 22 : 14)
            Text {
                x: (row.hasGlyph ? 100 : 80) + row.editOff; y: row.author ? 50 : 31
                width: row.textWidth - (x - 80 - row.editOff)
                height: row.author || row.hasGlyph ? 20 : 40
                maximumLineCount: row.author || row.hasGlyph ? 1 : 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.busy || row.preview
                color: row.busy ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 15
                lineHeight: 0.95
            }
            Loader {
                id: extras
                readonly property var r: row
                readonly property var t: titleText
                active: row.extraMask !== 0
                sourceComponent: row.extraMask === 0 ? null
                               : row.extraMask === 1 ? whoComp
                               : row.extraMask === 2 ? pillComp
                               : row.extraMask === 3 ? whoPillComp
                               : row.extraMask === 4 ? glyphComp
                               : row.extraMask === 8 ? directTagComp
                               : row.extraMask === 16 ? storySeenComp
                               : row.extraMask === 32 ? storyFreshComp
                               : row.extraMask === 64 ? editCheckComp
                               : (row.extraMask & 64) ? multiEditExtrasComp
                               : multiExtrasComp
            }
            Rectangle {
                x: 80 + row.editOff; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
        }
    }

    Component { id: chatPage; ChatPage {} }
    Component { id: directPage; DirectTopicsPage {} }
    Component { id: forumPage; ForumTopicsPage {} }

    SearchView {
        id: search
        anchors.fill: parent
        store: page.store
        onOpenChanged: page.searching = open
        onPicked: (chatId, messageId) => page.nav.push(chatPage, messageId ? { chatId: chatId, target: messageId }
                                                                            : { chatId: chatId })
    }

    ChatMenu {
        id: chatMenu
        store: page.store
        onOpenChat: (id, msgId) => page.openChat(id, msgId)
    }

    Alert {
        id: alert
        anchors.fill: parent
    }
}
