// Everything Telegram tells us, kept the way TDLib's own clients keep it:
// updates build the state (chats, users, the main list's order), requests
// answer through "@extra". JavaScript on the UI thread -- no Python.
import QtQuick
import "Looks.js" as Looks

QtObject {
    id: store

    property real tapAt: 0              // NULLGRAM_FPS: when a chat was tapped open (ChatPage's «open» lines count from it)
    // NULLGRAM_FPS, read once: td is Python, and asking it for every update TDLib sent cost ~0.1 ms each
    // (~1300 of them in the first seconds after start)
    readonly property bool fps: td.fps
    property string auth: ""            // TDLib's authorizationState, without the prefix: "WaitPhoneNumber", "Ready", ...
    // an emoji alone's size against a sticker's: Telegram's app config emojies_animated_zoom (Telegram-iOS's
    // animatedEmojiScale, ChatHistoryListNode); 0.625 until it comes (its value when last looked)
    property real emojiZoom: 0.625
    property string qrLink: ""          // tg://login?token=... while it waits for a scan
    property string passwordHint: ""
    // a QR given up for the number: the client closed and a new one opened (renew), the sign-in kept on the
    // screen meanwhile (Main), not a blank page for the seconds it takes
    property bool renewing: false
    property bool byPhone: true         // signing in by number, as Telegram's phone apps begin (the QR code: «QR kod bilan kirish»)
    property bool wasReady: false       // signed in in this run (a close then is a sign-out: the app starts again)
    property var authState: ({})        // the whole of it: where the code went (code_info), the e-mail's pattern...
    property string error: ""
    property string connection: ""      // "" when connected, else what it is doing ("ulanmoqda...")
    property var me: null
    property real stars: -1             // our Telegram Stars (updateOwnedStarCount; -1 not yet told)
    property int unreadChats: 0         // the main list's chats with unread messages, not muted
    property int unreadArchive: 0       // the archive list's chats with unread messages
    property int unreadArchiveUnmuted: 0
    property bool archiveUnreadKnown: false
    property bool archiveHidden: false  // the Archive row collapsed above the main list (pull down to reveal)
    property int archiveSeen: 0         // bumped when archiveList changes (Archive row binds to this)
    property var archiveSettings: ({ archive_and_mute_new_chats_from_unknown_users: false,
                                     keep_unmuted_chats_archived: false, keep_chats_from_folders_archived: false })
    property var folders: []            // the user's chat folders: [{ id, name, icon, color, shared, links }], in their order
    property int mainPosition: 0        // where «All chats» stands among them (moved only with Premium)
    property bool folderTags: false     // each chat's folders named in the list (Premium)
    property var scopes: ({})           // notificationSettingsScope… -> its scopeNotificationSettings (as TDLib tells them)
    property var reactionSettings: null // reactionNotificationSettings (TDLib tells them at the start: no getter)
    property var folderUnread: ({})     // folder id -> its chats with unread messages, not muted
    property int folder: 0              // the list on the screen: 0 the main one, else that folder
    property var openChat: 0            // the chat on the screen (its new messages do not notify)
    property var spots: ({})            // chat id -> { id, gap }: where it was left scrolled up (ChatPage.leave), reopened there
    property var backgrounds: ({})      // "day" / "night" -> TDLib's default background for it (null: Telegram-iOS's own)
    property var emojiThemes: []        // the chat themes (updateEmojiChatThemes): [{ name (an emoji), light_settings, dark_settings }]
    property var accentColors: []       // the names' colours past the seven (updateAccentColors): [accentColor]
    property var accentIds: [0, 1, 2, 3, 4, 5, 6]  // in the order shown (its available_accent_color_ids)
    property var profileColors: []      // the profiles' (updateProfileAccentColors): [profileAccentColor]
    property var profileIds: []
    // Hikoyalar (Q): chat id -> TDLib's chatActiveStories (list, order, max_read_story_id, stories: [storyInfo]);
    // storyRow: the main list's chats with some, ours apart (Mening hikoyam), unseen first then TDLib's order
    property var stories: ({})
    property var storyRow: []
    property int storiesSeen: 0
    property var _storyCache: ({})      // "chat:id" -> TDLib's story, once got (updateStory keeps it fresh)
    signal storyChanged(var chatId, var id)
    // Kanal DM (monoforum): chat id -> { topicId -> directMessagesChatTopic }
    property var directTopics: ({})
    property int directTopicsSeen: 0

    readonly property ListModel chatList: ListModel {}     // the main list in Telegram's order
    readonly property ListModel archiveList: ListModel {}  // the archived chats in Telegram's order (list id -1)
    property var folderLists: ({})      // folder id -> its ListModel, made when first shown, kept up after
    readonly property Component listModel: Component { ListModel {} }
    property var chats: ({})
    property var users: ({})
    property var groups: ({})           // "b" + basic group id, "s" + supergroup id
    property var actions: ({})          // chat id -> sender -> what they are doing (TDLib cancels them itself)
    property int seen: 0                // users, groups or actions changed: what reads them binds to this
    property int acting: 0              // actions alone (the chat list binds to this: statuses come often)
    property var _calls: ({})
    property int _seq: 0
    property var _fileChats: ({})       // a chat photo's file id -> chat ids showing it

    signal message(var msg)             // a new message in any chat
    signal messageChanged(var chatId, var oldId, var msg)   // sent: its id is final now
    signal messagesDeleted(var chatId, var ids)
    signal messageContent(var chatId, var id, var content)
    signal messageEdited(var chatId, var id, var date)
    signal messageReplyMarkup(var chatId, var id, var replyMarkup)
    signal contentOpened(var chatId, var id)    // a voice note or a round video played (here or by them)
    signal readOutbox(var chatId, var lastRead)
    signal chatChanged(var chatId)      // fields of a chat changed (an open chat page reads them again)
    signal actionChanged(var chatId)    // someone started or stopped typing (or the like) in that chat
    signal fileUpdated(var f)           // a file is coming or going: how far, or done
    signal messagePinned(var chatId, var id, bool pinned)
    signal messageInteraction(var chatId, var id, var info)     // views, reactions
    signal rowMoved(var listId)         // a row of a kept list moved (ListModel's rowsMoved is not QML's): an open swipe follows
    signal emojiClicked(var chatId, var id, var sticker)    // the other one in a private chat tapped an emoji alone: its effect

    // ---- talking to TDLib ----------------------------------------------------
    function send(req, done) {
        if (done) {
            _seq += 1
            req["@extra"] = String(_seq)
            _calls[req["@extra"]] = done
        }
        if (td)         // (gone while the app quits)
            td.send(JSON.stringify(req))
    }

    property Connections _td: Connections {
        target: td
        function onReceived(text) {
            if (!store.fps) {
                store.receive(JSON.parse(text))
                return
            }
            const t0 = Date.now(), r = JSON.parse(text), t1 = Date.now()
            store.receive(r)
            const t2 = Date.now()
            td.mark("tdms", t2 - t0)
            if (t2 - t0 > 15)
                console.warn("nullgram: slow update", r["@type"], "parse", t1 - t0, "ms, handled", t2 - t1, "ms,", text.length, "chars")
        }
    }

    function receive(u) {
        const extra = u["@extra"]
        if (extra !== undefined) {
            const done = _calls[extra]
            delete _calls[extra]
            if (done)
                done(u)
            return
        }
        const f = handlers[u["@type"]]
        if (f)
            f(u)
    }

    // ---- updates -------------------------------------------------------------
    readonly property var handlers: ({
        updateAuthorizationState: (u) => store.authorization(u.authorization_state),
        updateConnectionState: (u) => {
            const s = u.state["@type"]
            store.connection = s === "connectionStateReady" ? ""
                : Tr.t(s === "connectionStateUpdating" ? "yangilanmoqda..."
                : s === "connectionStateWaitingForNetwork" ? "tarmoq kutilmoqda..." : "ulanmoqda...")
        },
        updateOwnedStarCount: (u) => { store.stars = u.star_amount.star_count },
        updateUser: (u) => {
            store.users[u.user.id] = u.user
            if (store.me && store.me.id === u.user.id)
                store.me = u.user       // (Your Color: the colours just set)
            store.seenSoon()
        },
        updateAnimatedEmojiMessageClicked: (u) => store.emojiClicked(u.chat_id, u.message_id, u.sticker),
        updateUserStatus: (u) => {
            const user = store.users[u.user_id]
            if (user) {
                user.status = u.status
                store.seenSoon()
            }
        },
        updateBasicGroup: (u) => { store.groups["b" + u.basic_group.id] = u.basic_group; store.seenSoon() },
        updateDiceEmojis: (u) => { store.diceEmojis = u.emojis || store.diceEmojis },
        updateSupergroup: (u) => { store.groups["s" + u.supergroup.id] = u.supergroup; store.seenSoon() },
        updateDirectMessagesChatTopic: (u) => {
            const t = u.topic
            if (!t)
                return
            const map = store.directTopics[t.chat_id] || {}
            if (String(t.order) === "0" && !t.last_message)
                delete map[t.id]
            else
                map[t.id] = t
            store.directTopics[t.chat_id] = map
            store.directTopicsSeen++
        },
        updateForumTopicInfo: (u) => store.onForumTopicInfo(u.info),
        updateForumTopic: (u) => store.onForumTopic(u),
        updateChatAction: (u) => {
            const acts = store.actions[u.chat_id] || {}
            const key = JSON.stringify(u.sender_id)
            if (u.action["@type"] === "chatActionCancel")
                delete acts[key]
            else
                acts[key] = { sender: u.sender_id, action: u.action["@type"], emoji: u.action.emoji || "" }
            store.actions[u.chat_id] = acts
            // (not `seen`: every binding on it, every row of every list, was worked out again for each
            // «yozmoqda»; the list's row listens for its own chat, the header and profile bind to `acting`)
            store.acting++
            store.actionChanged(u.chat_id)
        },
        updateNewChat: (u) => {
            const c = u.chat
            c.positions = c.positions || []
            store.chats[c.id] = c
            store.watchPhoto(c)
            store.place(c)
        },
        updateChatTitle: (u) => store.change(u.chat_id, { title: u.title }),
        updateChatPhoto: (u) => {
            store.change(u.chat_id, { photo: u.photo })
            store.watchPhoto(store.chats[u.chat_id])
        },
        updateChatLastMessage: (u) => {
            store.change(u.chat_id, { last_message: u.last_message })
            for (const p of u.positions)
                store.position(u.chat_id, p)
        },
        updateChatPosition: (u) => store.position(u.chat_id, u.position),
        updateChatReadInbox: (u) => store.change(u.chat_id, { unread_count: u.unread_count,
                                                               last_read_inbox_message_id: u.last_read_inbox_message_id }),
        updateChatIsMarkedAsUnread: (u) => store.change(u.chat_id, { is_marked_as_unread: u.is_marked_as_unread }),
        updateArchiveChatListSettings: (u) => { store.archiveSettings = u.settings },
        updateChatReadOutbox: (u) => {
            store.change(u.chat_id, { last_read_outbox_message_id: u.last_read_outbox_message_id })
            store.readOutbox(u.chat_id, u.last_read_outbox_message_id)
        },
        updateChatBlockList: (u) => store.change(u.chat_id, { block_list: u.block_list }),
        updateChatPermissions: (u) => store.change(u.chat_id, { permissions: u.permissions }),
        updateChatUnreadMentionCount: (u) => store.change(u.chat_id, { unread_mention_count: u.unread_mention_count || 0 }),
        updateChatUnreadReactionCount: (u) => store.change(u.chat_id, { unread_reaction_count: u.unread_reaction_count || 0 }),
        // a mention or a reaction read by viewing its message: TDLib sends the chat's new count only here
        updateMessageMentionRead: (u) => store.change(u.chat_id, { unread_mention_count: u.unread_mention_count || 0 }),
        updateMessageUnreadReactions: (u) => store.change(u.chat_id, { unread_reaction_count: u.unread_reaction_count || 0 }),
        updateChatIsTranslatable: (u) => store.change(u.chat_id, { is_translatable: u.is_translatable }),
        updateChatMessageAutoDeleteTime: (u) => store.change(u.chat_id, { message_auto_delete_time: u.message_auto_delete_time }),
        updateChatPendingJoinRequests: (u) => store.change(u.chat_id, { pending_join_requests: u.pending_join_requests }),
        updateChatNotificationSettings: (u) => store.change(u.chat_id, { notification_settings: u.notification_settings }),
        updateReactionNotificationSettings: (u) => { store.reactionSettings = u.notification_settings },
        updateScopeNotificationSettings: (u) => {
            const s = Object.assign({}, store.scopes)
            s[u.scope["@type"]] = u.notification_settings
            store.scopes = s
        },
        updateChatDraftMessage: (u) => {
            store.change(u.chat_id, { draft_message: u.draft_message })
            for (const p of u.positions)
                store.position(u.chat_id, p)
        },
        updateNewMessage: (u) => {
            if (u.message && u.message.scheduling_state)
                return store.onScheduledNew(u.message)
            store.message(u.message); store.autoSave(u.message)
        },
        updateMessageSendSucceeded: (u) => {
            if (u.message && u.message.scheduling_state)
                return store.scheduledChanged(u.message.chat_id, u.old_message_id, u.message)
            store.scheduledSent(u.message.chat_id, u.old_message_id)
            store.messageChanged(u.message.chat_id, u.old_message_id, u.message)
        },
        updateMessageContent: (u) => store.messageContent(u.chat_id, u.message_id, u.new_content),
        updateMessageEdited: (u) => {
            store.messageEdited(u.chat_id, u.message_id, u.edit_date)
            store.messageReplyMarkup(u.chat_id, u.message_id, u.reply_markup || null)
        },
        updateChatReplyMarkup: (u) => store.change(u.chat_id, { reply_markup_message_id: u.reply_markup_message_id || 0 }),
        updateMessageContentOpened: (u) => store.contentOpened(u.chat_id, u.message_id),
        updateDeleteMessages: (u) => {
            if (u.is_permanent) {
                store.messagesDeleted(u.chat_id, u.message_ids)
                store.scheduledDeleted(u.chat_id, u.message_ids)
            }
        },
        updateChatHasScheduledMessages: (u) => store.change(u.chat_id, { has_scheduled_messages: !!u.has_scheduled_messages }),
        updateFile: (u) => store.file(u.file),
        updateChatActiveStories: (u) => {
            const a = u.active_stories
            if (a.stories.length)
                store.stories[a.chat_id] = a
            else
                delete store.stories[a.chat_id]
            Qt.callLater(store.sortStories)    // (once for a burst: ~6 at the start, each row of the strip made anew)
        },
        updateStory: (u) => {
            store._storyCache[u.story.poster_chat_id + ":" + u.story.id] = u.story
            store.storyChanged(u.story.poster_chat_id, u.story.id)
        },
        updateStoryDeleted: (u) => {
            delete store._storyCache[u.story_poster_chat_id + ":" + u.story_id]
            store.storyChanged(u.story_poster_chat_id, u.story_id)
        },
        updateMessageIsPinned: (u) => store.messagePinned(u.chat_id, u.message_id, u.is_pinned),
        updateMessageInteractionInfo: (u) => store.messageInteraction(u.chat_id, u.message_id, u.interaction_info),
        // TDLib's notifications (it knows the muted chats and takes them back when read): a banner
        // for each new one, unless its chat is on the screen; the old ones at start are not news
        updateNotificationGroup: (u) => {
            for (const n of u.added_notifications)
                if (n.type["@type"] === "notificationTypeNewMessage" && !n.is_silent && Date.now() / 1000 - n.date < 120)
                    store.notify(u.chat_id, n.type.message, n.type.show_preview)
        },
        updateUnreadChatCount: (u) => {
            if (u.chat_list["@type"] === "chatListMain")
                store.unreadChats = u.unread_unmuted_count
            else if (u.chat_list["@type"] === "chatListArchive") {
                store.archiveUnreadKnown = true
                store.unreadArchive = u.unread_count
                store.unreadArchiveUnmuted = u.unread_unmuted_count
            } else if (u.chat_list["@type"] === "chatListFolder") {
                const f = Object.assign({}, store.folderUnread)
                f[u.chat_list.chat_folder_id] = u.unread_unmuted_count
                store.folderUnread = f
            }
        },
        updateDefaultBackground: (u) => store.setBackground(u.for_dark_theme, u.background),
        updateEmojiChatThemes: (u) => { store.emojiThemes = u.chat_themes },
        updateAccentColors: (u) => { store.accentColors = u.colors; store.accentIds = u.available_accent_color_ids },
        updateProfileAccentColors: (u) => { store.profileColors = u.colors; store.profileIds = u.available_accent_color_ids },
        updateChatBackground: (u) => store.change(u.chat_id, { background: u.background }),
        updateChatTheme: (u) => store.change(u.chat_id, { theme: u.theme }),
        updateChatFolders: (u) => {
            store.folders = u.chat_folders.map((f) => ({ id: f.id, name: f.name.text.text, icon: f.icon ? f.icon.name : "",
                                                        color: f.color_id, shared: f.is_shareable, links: f.has_my_invite_links }))
            store.mainPosition = u.main_chat_list_position || 0
            store.folderTags = !!u.are_tags_enabled
            for (const k in store.folderLists)
                if (!store.folders.some((f) => String(f.id) === k)) {
                    store.folderLists[k].destroy()
                    delete store.folderLists[k]
                }
            if (store.folder && !store.folders.some((f) => f.id === store.folder))
                store.showFolder(0)
        },
        updateInstalledStickerSets: (u) => store.installedStickerSetsChanged(u.sticker_type, u.sticker_set_ids || []),
    })

    function authorization(s) {
        auth = s["@type"].replace("authorizationState", "")
        authState = s
        error = ""
        if (auth !== "LoggingOut" && auth !== "Closed" && auth !== "WaitTdlibParameters")
            renewing = false
        if (accounts.adding && (auth === "WaitPhoneNumber" || auth === "WaitOtherDeviceConfirmation"))
            _watchOthers.start()            // (0.9.7: the others' numbers, for the sign-in's «already here»)
        if (auth === "WaitTdlibParameters" && !td.apiId) {
            auth = "NeedApiKey"         // no key in this build or on this phone: Main asks for one (ApiKeyPage)
        } else if (auth === "WaitTdlibParameters") {
            send({ "@type": "setTdlibParameters", use_test_dc: td.testDc,
                   database_directory: td.dataDir + "/db", files_directory: td.dataDir + "/files",
                   use_file_database: true, use_chat_info_database: true, use_message_database: true,
                   api_id: td.apiId, api_hash: td.apiHash, system_language_code: Tr.lang,
                   device_model: td.deviceModel, system_version: td.systemVersion,
                   application_version: td.appVersion }, check)
        } else if (auth === "WaitPhoneNumber" && td.testPhone) {
            send({ "@type": "setAuthenticationPhoneNumber", phone_number: td.testPhone }, check)
        } else if (auth === "WaitCode" && td.testPhone) {
            send({ "@type": "checkAuthenticationCode",
                   code: td.testPhone.charAt(5).repeat(s.code_info.type.length || 5) }, check)
        } else if (auth === "WaitRegistration" && td.testPhone) {
            send({ "@type": "registerUser", first_name: "Sinov", last_name: td.testPhone.slice(-4) }, check)
        } else if (auth === "WaitPhoneNumber" && !byPhone) {
            send({ "@type": "requestQrCodeAuthentication", other_user_ids: accounts.otherIds() }, check)
        } else if (auth === "WaitOtherDeviceConfirmation" && byPhone) {
            renewing = true                 // (the number chosen while the QR was on its way: that QR given up)
            send({ "@type": "logOut" }, check)
        } else if (auth === "WaitOtherDeviceConfirmation") {
            qrLink = s.link
        } else if (auth === "WaitPassword") {
            passwordHint = s.password_hint || ""
        } else if (auth === "Closed") {     // (signed out: TDLib closes the client; at the app's own end QML is gone)
            if (wasReady) {
                accounts.signedOut()        // (0.9.7: only this account; the next one shown)
                td.restart()
            }
            else
                td.renew()                  // (the QR given up for the number: a new client, at WaitPhoneNumber)
        } else if (auth === "Ready") {
            wasReady = true
            qrLink = ""
            tellNetwork()
            cleaner.restart()
            send({ "@type": "getMe" }, (m) => {
                store.me = m
                if (m["@type"] !== "user")
                    return
                // (0.9.7: the accounts' list shows it; an account just added that was here already: this new
                // session signed out, and the app goes to that one -- AccountList.signedOut)
                const same = accounts.setMe(m.id, m.first_name || "", (m.usernames && m.usernames.active_usernames[0]) || "", !!m.is_premium)
                if (same)
                    send({ "@type": "logOut" }, check)
                else
                    syncContacts()
            })
            _watchOthers.start()
            send({ "@type": "getApplicationConfig" }, (c) => {
                for (const m of c.members || [])
                    if (m.key === "emojies_animated_zoom" && m.value && m.value.value > 0)
                        store.emojiZoom = m.value.value
                console.log("nullgram: emoji zoom", store.emojiZoom)
            })
            send({ "@type": "setOption", name: "notification_group_count_max",
                   value: { "@type": "optionValueInteger", value: 10 } })
            send({ "@type": "setOption", name: "notification_group_size_max",
                   value: { "@type": "optionValueInteger", value: 3 } })
            send({ "@type": "loadChats", chat_list: { "@type": "chatListMain" }, limit: 200 })
            send({ "@type": "loadChats", chat_list: { "@type": "chatListArchive" }, limit: 50 })
            send({ "@type": "getArchiveChatListSettings" }, (r) => {
                if (r["@type"] === "archiveChatListSettings")
                    store.archiveSettings = r
            })
            store.loadStories(0)
            for (const dark of [false, true])       // (no default of its own told: Telegram's)
                if (store.backgrounds[dark ? "night" : "day"] === undefined)
                    store.setBackground(dark, null)
        }
    }

    // Chiqish: Telegram forgets this device's session, TDLib its database; then LoggingOut, Closed (above)
    function logOut() {
        send({ "@type": "logOut" }, check)
    }

    // the sign-in by number or by QR code: TDLib takes a number only while it waits for one, so a QR asked
    // for already is given up (logOut before signing in only closes the client: renew() above)
    function signInBy(phone) {
        byPhone = phone
        error = ""
        if (phone && auth === "WaitOtherDeviceConfirmation") {
            qrLink = ""
            renewing = true
            send({ "@type": "logOut" }, check)
        } else if (!phone && auth === "WaitPhoneNumber")
            send({ "@type": "requestQrCodeAuthentication", other_user_ids: accounts.otherIds() }, check)
    }

    function check(r) {
        if (r["@type"] === "error") {
            error = r.message
            console.warn("nullgram: TDLib said", r.code, r.message)
        }
    }

    // a group's basicGroup or supergroup (its status: what we may do there), null for the others
    function groupOf(c) {
        if (!c)
            return null
        const t = c.type["@type"]
        return t === "chatTypeSupergroup" ? groups["s" + c.type.supergroup_id]
             : t === "chatTypeBasicGroup" ? groups["b" + c.type.basic_group_id] : null
    }
    // a basic group made a supergroup (what some settings need: hidden history, topics, slow mode, a public
    // name, exceptions): done(the new chat's id), or an error said; the pages on it follow (nav.rechat)
    function upgrade(id, nav, done) {
        const c = chats[id]
        if (!c || c.type["@type"] !== "chatTypeBasicGroup")
            return done(id)
        send({ "@type": "upgradeBasicGroupChatToSupergroupChat", chat_id: id }, (r) => {
            if (r["@type"] === "error")
                return nav.say(Tr.f("Bo'lmadi: %1", r.message))
            if (!chats[r.id])
                chats[r.id] = r
            seen++
            nav.rechat(id, r.id)
            done(r.id)
        })
    }

    // «A'zo qo'shish»: people from the chats (private, not bots) picked, added at once (addChatMembers); done() after
    function addMembers(id, nav, done) {
        const p = nav.push(Qt.createComponent("FolderChatsPage.qml"), {
            heading: Tr.t("A'zo qo'shish"), chosen: [],
            pool: (c) => c.type["@type"] === "chatTypePrivate" && !isSaved(c)
                         && !(users[c.type.user_id] && users[c.type.user_id].type["@type"] === "userTypeBot") })
        if (p)
            p.done.connect((flags, ids) => {
                const who = ids.map((i) => chats[i]).filter((c) => c && c.type.user_id).map((c) => c.type.user_id)
                if (!who.length)
                    return
                send({ "@type": "addChatMembers", chat_id: id, user_ids: who }, (r) => {
                    if (r["@type"] === "error")
                        return nav.say(Tr.f("Bo'lmadi: %1", r.message))
                    const failed = r.failed_to_add_members ? r.failed_to_add_members.length : 0
                    nav.say(failed ? Tr.n("%1 kishini qo'shib bo'lmadi (maxfiylik sozlamalari)", failed)
                                   : Tr.n("%1 kishi guruhga qo'shildi", who.length))
                    if (done)
                        done()
                })
            })
    }

    function change(id, fields) {
        const c = chats[id]
        if (!c)
            return
        for (const k in fields)
            c[k] = fields[k]
        refresh(c)
        chatChanged(id)
    }

    // a chat's place in one list (the main one, a folder, the archive) changed
    function position(id, p) {
        const c = chats[id]
        if (!c)
            return
        c.positions = c.positions.filter((q) => !sameList(q.list, p.list))
        if (p.order !== "0")
            c.positions.push(p)
        const at = listId(p.list)
        if (at !== null && (at === 0 || at === -1 || folderLists[at]))
            placeIn(at, c)
    }

    function sameList(a, b) {
        return a["@type"] === b["@type"] && (a["@type"] !== "chatListFolder" || a.chat_folder_id === b.chat_folder_id)
    }

    // a TDLib chat list by our id (0 the main one, -1 the archive, >0 a folder's), and back
    function chatListOf(id) {
        return id === -1 ? { "@type": "chatListArchive" }
             : id ? { "@type": "chatListFolder", chat_folder_id: id }
                  : { "@type": "chatListMain" }
    }
    function listId(list) {
        return list["@type"] === "chatListMain" ? 0
             : list["@type"] === "chatListArchive" ? -1
             : list["@type"] === "chatListFolder" ? list.chat_folder_id : null
    }
    function shown() {
        return chatListOf(folder)
    }
    function positionIn(id, c) {
        const list = chatListOf(id)
        for (const p of c.positions)
            if (sameList(p.list, list))
                return p
        return null
    }
    function mainPosition(c) {
        return positionIn(0, c)
    }

    // the rows of a list: the main and archive lists always there, a folder's made the first time it is asked for
    // (its chats now, sorted by their order there; TDLib then loads more) and kept up from then on, so
    // that going back to it shows it at once with its pictures
    function modelOf(id) {
        if (id === -1)
            return archiveList
        if (!id)
            return chatList
        let m = folderLists[id]
        if (m)
            return m
        m = listModel.createObject(store)
        folderLists[id] = m
        const rows = []
        for (const k in chats) {
            const p = positionIn(id, chats[k])
            if (p)
                rows.push({ c: chats[k], order: p.order })
        }
        rows.sort((a, b) => before(a.order, b.order) ? -1 : 1)
        for (const r of rows)
            m.append(row(r.c, id))
        send({ "@type": "loadChats", chat_list: chatListOf(id), limit: 100 })
        return m
    }
    function showFolder(id) {
        modelOf(id)
        folder = id
    }

    // orders are int64 written as text: longer is bigger, else compare the text
    function before(a, b) {
        return a.length !== b.length ? a.length > b.length : a > b
    }

    function rowIndex(m, id) {
        for (let i = 0; i < m.count; i++)
            if (m.get(i).chatId === id)
                return i
        return -1
    }

    // put a chat where its order says in every list kept (or out of one where it has none)
    function place(c) {
        placeIn(0, c)
        placeIn(-1, c)
        for (const k in folderLists)
            placeIn(Number(k), c)
    }
    // A little later (_placer): at the start ~300 chats came one update each, all in one turn of the loop,
    // and each was put in on its own (its place looked for row by row, the list told of each row): one
    // ~400 ms frame. Now the chats a turn moved are put in once each after it, an empty list all at once.
    property var _dirty: ({})           // list id -> chat id -> true
    property Timer _placer: Timer { interval: 15; onTriggered: store.placeNow() }
    function placeIn(id, c) {
        if (!id) {
            const p = positionIn(0, c)
            if (p) {
                c.order = p.order       // (the search sorts by it)
                c.pinned = p.is_pinned
            }
        }
        const d = _dirty[id] || (_dirty[id] = {})
        d[c.id] = true
        if (!_placer.running)
            _placer.start()
    }
    function placeNow() {
        const dirty = _dirty
        _dirty = {}
        for (const k in dirty) {
            const id = Number(k)
            if (id > 0 && !folderLists[id])
                continue
            const m = modelOf(id)
            const ids = Object.keys(dirty[k])
            if (m.count === 0 && ids.length > 1) {
                const rows = []
                for (const cid of ids) {
                    const c = chats[cid]
                    const p = c ? positionIn(id, c) : null
                    if (p)
                        rows.push({ c: c, order: p.order })
                }
                rows.sort((a, b) => before(a.order, b.order) ? -1 : 1)
                m.append(rows.map((r) => row(r.c, id)))
                if (fps && !id)
                    td.mark("listed", 1)    // (tools/startup.py: when the chats came)
                if (id === -1)
                    archiveSeen++
                continue
            }
            for (const cid of ids)
                if (chats[cid])
                    placeOne(id, m, chats[cid])
            if (id === -1)
                archiveSeen++
        }
    }
    function placeOne(id, m, c) {
        const p = positionIn(id, c)
        const at = rowIndex(m, c.id)
        if (!p) {
            if (at >= 0)
                m.remove(at)
            return
        }
        const order = (q) => { const r = positionIn(id, q); return r ? r.order : "0" }
        let to = 0
        while (to < m.count) {
            const other = m.get(to).chatId
            if (other !== c.id && before(p.order, order(chats[other])))
                break
            to++
        }
        if (at < 0) {
            m.insert(to, row(c, id))
            return
        }
        if (to > at)
            to--
        if (to !== at)
            m.move(at, to, 1)
        setRow(m, to, row(c, id))
        if (to !== at)
            rowMoved(id)
    }

    function refresh(c) {
        let at = rowIndex(chatList, c.id)
        if (at >= 0)
            setRow(chatList, at, row(c, 0))
        at = rowIndex(archiveList, c.id)
        if (at >= 0) {
            setRow(archiveList, at, row(c, -1))
            archiveSeen++
        }
        for (const k in folderLists) {
            at = rowIndex(folderLists[k], c.id)
            if (at >= 0)
                setRow(folderLists[k], at, row(c, Number(k)))
        }
    }
    // only what changed: a whole set() told the list every field of the row changed, and the row worked
    // out all it shows again (its texts laid out anew) for each read mark, each status, each message
    function setRow(m, at, r) {
        const was = m.get(at)
        for (const k in r)
            if (was[k] !== r[k])
                m.setProperty(at, k, r[k])
    }

    // the language changed (Tr): every row's words anew (a row keeps the words it was made with)
    property Connections _lang: Connections {
        target: Tr
        function onLangChanged() {
            for (const id in store.chats)
                store.refresh(store.chats[id])
            store._tile.restart()
        }
    }

    // ---- the other accounts (0.9.7): kept on in the background (nullgram_app.py's AccountList) ----------
    // a moment after this one is up (its start not shared with theirs), when Bildirishnomalar › «Barcha
    // hisoblardan» is on; their new messages told here, the banner made as this account's are, its title
    // «chat → account» (Telegram-iOS's NotificationRecipientAccount; the account's first name, as Android)
    property Timer _watchOthers: Timer {
        interval: 3000
        onTriggered: accounts.watch(Prefs.allAccounts, Tr.lang)
    }
    property Connections _others: Connections {
        target: accounts
        function onNotified(slot, p) { store.notifyOther(p) }
        function onContactsChanged() { store.syncContacts() }
        function onChanged() { store._tile.restart() }     // (othersUnread too: the tile)
    }
    // Kontaktlarni sinxronlash (0.9.7): the phone's contacts to this account -- at the start, when the phone's
    // change, when switched on (Telegram Android's ContactsController: the whole book, TDLib finding what changed
    // and taking the ones gone off the server too); one request at a time (TDLib's rule), a change meanwhile after.
    // Off: nothing read, nothing sent; what was sent stays till «Sinxronlangan kontaktlarni o'chirish».
    property bool _syncing: false
    property bool _syncAgain: false
    function syncContacts() {
        if (!accounts.sync || !wasReady)
            return
        if (_syncing)
            return _syncAgain = true
        const book = accounts.phoneContacts()
        if (!book.length)
            return console.log("nullgram: contact sync: no phone contacts")
        _syncing = true
        send({ "@type": "changeImportedContacts", contacts: book }, (r) => {
            _syncing = false
            if (r["@type"] === "error")
                console.warn("nullgram: contact sync", r.code, r.message)
            else
                console.log("nullgram: contact sync:", book.length, "sent,", (r.user_ids || []).filter((u) => u).length, "on Telegram")
            if (_syncAgain) {
                _syncAgain = false
                syncContacts()
            }
        })
    }
    // how many may be signed in: 3, 4 with Premium on any of them (Telegram's phone apps: UserConfig, AccountUtils)
    readonly property int accountLimit: accounts.list.some((a) => a.premium) ? 4 : 3
    // the switch: «Hisob ochilmoqda…» drawn first (HomePage), then the app starts again with it (AccountList)
    property int switchingTo: 0
    function switchAccount(slot) {
        if (slot === accounts.active || switchingTo)
            return
        switchingTo = slot
        _switch.start()
    }
    property Timer _switch: Timer { interval: 120; onTriggered: accounts.switchTo(store.switchingTo) }
    // «Hisob qo'shish»: past the limit, why (Telegram Android's LimitReachedBottomSheet TYPE_ACCOUNTS, Premium's page
    // to read: nothing bought here); else the app starts again at a new account's sign-in (AccountList.add), its
    // contacts to be synced to begin with (Telegram's apps; the sign-in's switch changes it)
    function addAccount(nav, alert) {
        if (switchingTo)
            return
        if (accounts.count >= accountLimit) {
            alert.show(Tr.t("Hisoblar limiti"),
                       accountLimit < 4 ? Tr.t("Bir vaqtda %1 tagacha hisob ulash mumkin. Telegram Premium bilan — 4 tagacha.").arg(accountLimit)
                                        : Tr.t("Bir vaqtda %1 tagacha hisob ulash mumkin.").arg(accountLimit),
                       accountLimit < 4 ? [{ t: "OK" }, { t: Tr.t("Premium haqida"), run: () => nav.push(Qt.createComponent("PremiumPage.qml"), {}) }]
                                        : [{ t: "OK" }])
            return
        }
        switchingTo = -1
        _add.start()
    }
    property Timer _add: Timer { interval: 120; onTriggered: if (!accounts.add(true)) store.switchingTo = 0 }
    function notifyOther(p) {
        if (inFront && !Prefs.inAppPreview)
            return
        const who = p.kind === "group" && Prefs.lockNames && p.sender ? p.sender + ": " : ""
        const body = p.preview ? preview(p.content, { type: { is_channel: p.kind === "channel" } }) : Tr.t("Yangi xabar")
        td.notify(Prefs.lockNames ? p.chat + (p.account ? " → " + p.account : "") : "Nullgram",
                  who + body, inFront && !Prefs.inAppSounds)
    }

    // ---- outside the app: banners, the tile, being online ------------------------
    readonly property bool inFront: Qt.application.state === Qt.ApplicationActive
    function notify(chatId, m, full) {
        if (inFront && openChat === chatId)
            return
        const c = chats[chatId]
        if (!c)
            return
        // a channel's post copied into its discussion group (sent by the channel itself): the
        // channel tells of it, or is muted — the copy is not news, nor while the channel is open
        const o = m.forward_info && m.forward_info.origin
        if (o && o["@type"] === "messageOriginChannel" && m.sender_id["@type"] === "messageSenderChat"
                && m.sender_id.chat_id === o.chat_id && chats[o.chat_id])
            return
        if (inFront && !Prefs.inAppPreview)         // («Ilova ichida ko'rsatish» off: none while the app is in front)
            return
        const group = c.type["@type"] === "chatTypeBasicGroup" || (c.type["@type"] === "chatTypeSupergroup" && !c.type.is_channel)
        const who = group && Prefs.lockNames ? senderName(m.sender_id, true) : ""
        // (2+ accounts: whose, «Chat → Ism» as the others' -- Telegram Android's; names off: none, iOS's)
        const mine = accounts.count > 1 && me && me.first_name ? " → " + me.first_name : ""
        td.notify(Prefs.lockNames ? title(c) + mine : "Nullgram", (who ? who + ": " : "") + (full ? preview(m.content, c) : Tr.t("Yangi xabar")),
                  inFront && !Prefs.inAppSounds)
    }

    // the tile's back: the newest chats with unread messages (not muted), their count on the corner
    // (a moment after the last change: messages come in bursts)
    property Timer _tile: Timer {
        interval: 1500
        onTriggered: {
            const rows = []
            for (const id in store.chats) {
                const c = store.chats[id]
                const muted = c.notification_settings && c.notification_settings.mute_for > 0
                const p = c.positions.find((q) => q.list["@type"] === "chatListMain")
                if (p && c.unread_count > 0 && !muted)
                    rows.push({ c: c, order: p.order })
            }
            rows.sort((a, b) => store.before(a.order, b.order) ? -1 : 1)
            // the count as the Bildirishnomalar page has it (NISHON HISOBLAGICHI): TDLib's own when it is chats with the channels
            const counted = rows.filter((r) => Prefs.badgeChannels || !(r.c.type["@type"] === "chatTypeSupergroup" && r.c.type.is_channel))
            // (+ the other accounts' unread chats while they are kept on, «Barcha hisoblardan»: chats, also when
            // this one's are counted as messages -- the others' messages are not known)
            const count = (Prefs.badgeChannels && !Prefs.badgeMessages ? store.unreadChats
                           : counted.reduce((n, r) => n + (Prefs.badgeMessages ? r.c.unread_count : 1), 0)) + accounts.othersUnread
            const lines = rows.slice(0, 3).map((r) => store.title(r.c) + ": " +
                                               (r.c.last_message ? store.preview(r.c.last_message.content, r.c) : ""))
            if (td)
                td.tile("null", lines, count)
        }
    }
    function retile() { _tile.restart() }
    onUnreadChatsChanged: _tile.restart()
    onChatChanged: _tile.restart()

    // online only while it is on the screen (hidden in the background it still gets everything)
    onInFrontChanged: if (auth === "Ready")
        send({ "@type": "setOption", name: "online", value: { "@type": "optionValueBoolean", value: inFront } })

    // ---- what a row shows ----------------------------------------------------
    function row(c, list) {
        const m = c.last_message
        const at = positionIn(list || 0, c)
        const said = m ? service(m, c) : null
        let text = said !== null ? said : m ? preview(m.content) : ""
        let who = "", drafted = false
        const draft = c.draft_message && c.draft_message.content
        if (draft && draft["@type"] === "draftMessageContentText" && draft.text.text) {
            who = Tr.t("Qoralama")
            drafted = true
            text = draft.text.text
        } else if (said === null && m && m.is_outgoing && c.type["@type"] !== "chatTypePrivate" && !c.type.is_channel) {
            who = Tr.t("Siz")
        } else if (said === null && m && (c.type["@type"] === "chatTypeBasicGroup" ||
                         (c.type["@type"] === "chatTypeSupergroup" && !c.type.is_channel))) {
            who = senderName(m.sender_id, true)
        }
        const muted = c.notification_settings && c.notification_settings.mute_for > 0
        return {
            chatId: c.id, title: title(c), saved: isSaved(c), direct: isDirect(c), who: who, draft: drafted, preview: text.replace(/\s+/g, " "),
            // a song: Telegram-iOS's round ▶ before its name (a draft has its own text)
            glyph: !drafted && said === null && m && m.content["@type"] === "messageAudio" ? "playround" : "",
            time: m ? stamp(m.date) : "", unread: c.unread_count || 0, markedUnread: !!c.is_marked_as_unread,
            muted: muted, pinned: !!(at && at.is_pinned),
            photo: photoPath(c), letters: letters(c.title), tint: tints[Math.abs(c.id) % tints.length],
            outgoing: !!(m && m.is_outgoing), read: !!(m && m.is_outgoing && m.id <= (c.last_read_outbox_message_id || 0))
        }
    }

    // one's own chat is Saved Messages, as Telegram calls it
    function isSaved(c) {
        return !!(c && me && c.type["@type"] === "chatTypePrivate" && c.type.user_id === me.id)
    }
    // channel direct messages group (monoforum) — either as a subscriber or as an admin
    function isDirect(c) {
        if (!c || c.type["@type"] !== "chatTypeSupergroup")
            return false
        const g = groups["s" + c.type.supergroup_id]
        return !!(g && g.is_direct_messages_group)
    }
    function isDirectAdmin(c) {
        if (!c || c.type["@type"] !== "chatTypeSupergroup")
            return false
        const g = groups["s" + c.type.supergroup_id]
        return !!(g && g.is_administered_direct_messages_group)
    }
    function directTopicList(chatId) {
        const map = directTopics[chatId]
        if (!map)
            return []
        return Object.keys(map).map((k) => map[k]).sort((a, b) => before(a.order, b.order) ? -1 : 1)
    }
    function dropDirectTopic(chatId, topicId) {
        const map = directTopics[chatId]
        if (!map)
            return
        delete map[topicId]
        directTopicsSeen++
    }
    // open a channel's direct messages chat: inbox (DirectTopicsPage) for admins, 1-on-1 ChatPage for subscribers
    function openDirectMessages(directChatId, nav, channelChatId) {
        if (!directChatId || !nav)
            return
        const go = (c) => {
            if (!c || c["@type"] === "error")
                return nav.say(Tr.t("Kanal xabarlarini ochib bo'lmadi"))
            if (!chats[c.id])
                chats[c.id] = c
            const file = isDirectAdmin(c) ? "DirectTopicsPage.qml" : "ChatPage.qml"
            const comp = Qt.createComponent(file)
            if (comp.status === Component.Error)
                return console.warn("nullgram:", comp.errorString())
            nav.push(comp, file === "DirectTopicsPage.qml"
                     ? { chatId: c.id, channelChatId: channelChatId || 0 }
                     : { chatId: c.id })
        }
        if (chats[directChatId] && groupOf(chats[directChatId]))
            go(chats[directChatId])
        else
            send({ "@type": "getChat", chat_id: directChatId }, go)
    }
    function title(c) {
        return isSaved(c) ? Tr.t("Saqlangan xabarlar") : c ? c.title : ""
    }

    readonly property var tints: ["#ff516a", "#ffa85c", "#a685ff", "#54cb68", "#28c9b7", "#2a9ef1", "#d669ed"]
    // the seven name colours (PeerNameColors' red, orange, violet, green, cyan, blue, pink): a folder's tag; -1 none
    function nameColor(id) {
        return (Theme.dark ? ["#ff8e86", "#ffa357", "#c19dff", "#89d36f", "#5ec9e3", "#69baf7", "#ff87bf"]
                           : ["#cc5049", "#d67722", "#955cdb", "#40a920", "#309eba", "#368ad1", "#c7508b"])[id] || "transparent"
    }

    // a name's colours (Your Color; Telegram-iOS PeerNameColors): an accent colour id as one to three "#rrggbb" — the
    // first the name's and the quote bar's, the others the bar's stripes; the seven built in are nameColor's
    function nameColors(id) {
        const a = accentColors.find((c) => c.id === id)
        const list = a ? (Theme.dark ? a.dark_theme_colors : a.light_theme_colors) : []
        if (!list.length) {
            const c = nameColor(a ? a.built_in_accent_color_id : id)
            return [c === "transparent" ? nameColor(0) : c]
        }
        return list.map((c) => "#" + hex((c >>> 0) & 0xffffff))
    }
    // a profile's colours (profileAccentColors of the day or the night): { palette, background, story } as "#rrggbb"
    function profileColorsOf(id) {
        const p = profileColors.find((c) => c.id === id)
        const set = p ? (Theme.dark ? p.dark_theme_colors : p.light_theme_colors) : null
        const of = (l) => (l || []).map((c) => "#" + hex((c >>> 0) & 0xffffff))
        return set ? { palette: of(set.palette_colors), background: of(set.background_colors), story: of(set.story_colors) }
                   : { palette: [], background: [], story: [] }
    }
    // Your Color set: the name's (accent_color_id) and the profile's (-1: none); TDLib tells the user changed (updateUser)
    function setYourColor(name, profile, done) {
        let left = 0
        const back = (r) => { if (r["@type"] === "error") console.warn("nullgram: your color", r.message); if (--left === 0 && done) done() }
        if (me && name !== me.accent_color_id) {
            left++
            send({ "@type": "setAccentColor", accent_color_id: name, background_custom_emoji_id: me.background_custom_emoji_id || "0" }, back)
        }
        if (me && profile !== (me.profile_accent_color_id === undefined ? -1 : me.profile_accent_color_id)) {
            left++
            send({ "@type": "setProfileAccentColor", profile_accent_color_id: profile,
                   profile_background_custom_emoji_id: profile < 0 ? "0" : me.profile_background_custom_emoji_id || "0" }, back)
        }
        if (left === 0 && done)
            done()
    }

    function letters(title) {
        const w = (title || "").trim().split(/\s+/)
        return (first(w[0] || "") + (w.length > 1 ? first(w[1]) : "")).toUpperCase()
    }

    // a word's first letter as it is seen (Telegram-iOS takes Swift's first Character): an emoji whole --
    // charAt(0) gave half of 🖤 (a lone surrogate: � on the avatar) -- with what goes with it: ❤️'s
    // variation selector, a skin tone, a flag's second half, keycap, marks over a letter, ZWJ joins (👨‍👩‍👧)
    function first(word) {
        const cps = []          // (by code points: Qt's Array.from(string) still splits UTF-16 units)
        for (let i = 0; i < word.length; ) {
            const c = String.fromCodePoint(word.codePointAt(i))
            cps.push(c)
            i += c.length
        }
        if (!cps.length)
            return ""
        let out = cps[0], k = 1
        const ri = (c) => c >= 0x1F1E6 && c <= 0x1F1FF
        if (ri(cps[0].codePointAt(0)) && cps.length > 1 && ri(cps[1].codePointAt(0)))
            out += cps[k++]
        while (k < cps.length) {
            const c = cps[k].codePointAt(0)
            if (c === 0x200D && k + 1 < cps.length) {
                out += cps[k] + cps[k + 1]
                k += 2
            } else if ((c >= 0xFE00 && c <= 0xFE0F) || (c >= 0x1F3FB && c <= 0x1F3FF) || (c >= 0x0300 && c <= 0x036F)
                       || c === 0x20E3 || (c >= 0xE0020 && c <= 0xE007F)) {
                out += cps[k++]
            } else {
                break
            }
        }
        return out
    }

    function senderName(sender, short) {
        if (!sender)
            return ""
        if (sender["@type"] === "messageSenderUser") {
            const u = users[sender.user_id]
            if (u && u.type && u.type["@type"] === "userTypeDeleted")     // (TDLib leaves its name empty; iOS: «Deleted Account»)
                return Tr.t("O'chirilgan hisob")
            return u ? (short ? u.first_name : (u.first_name + " " + u.last_name).trim()) : ""
        }
        const c = chats[sender.chat_id]
        return c ? c.title : ""
    }

    readonly property var doing: ({
        chatActionTyping: "yozmoqda", chatActionRecordingVoiceNote: "ovozli xabar yozmoqda",
        chatActionUploadingVoiceNote: "ovozli xabar yubormoqda", chatActionRecordingVideoNote: "video xabar yozmoqda",
        chatActionUploadingVideoNote: "video xabar yubormoqda", chatActionRecordingVideo: "video yozmoqda",
        chatActionUploadingVideo: "video yubormoqda", chatActionUploadingPhoto: "rasm yubormoqda",
        chatActionUploadingDocument: "fayl yubormoqda", chatActionChoosingSticker: "stiker tanlamoqda",
        chatActionChoosingLocation: "joylashuv tanlamoqda", chatActionChoosingContact: "kontakt tanlamoqda",
        chatActionStartPlayingGame: "o'ynamoqda", chatActionWatchingAnimations: "ko'rmoqda"
    })

    // the line under a chat's name: what someone is doing in it, else whether the person is
    // online and when they were, or how many are in the group; `now` in seconds
    function status(c, now) {
        if (!c)
            return ""
        const busy = activity(c)
        if (busy)
            return busy
        const t = c.type["@type"]
        if (t === "chatTypeBasicGroup") {
            const g = groups["b" + c.type.basic_group_id]
            return g ? Tr.n("%1 a'zo", g.member_count, count(g.member_count)) : Tr.t("guruh")
        }
        if (t === "chatTypeSupergroup") {
            const g = groups["s" + c.type.supergroup_id]
            if (g && g.is_direct_messages_group)
                return Tr.t("kanalga xabarlar")
            return g && g.member_count ? Tr.n(c.type.is_channel ? "%1 obunachi" : "%1 a'zo", g.member_count, count(g.member_count))
                 : Tr.t(c.type.is_channel ? "kanal" : "guruh")
        }
        if (t !== "chatTypePrivate")
            return ""
        return userStatus(users[c.type.user_id], now)
    }

    // a person's: "onlayn", "bugun 14:05 da bo'lgan", "bot", ...
    function userStatus(u, now) {
        if (!u || (me && u.id === me.id))
            return ""
        if (u.id === 777000)
            return Tr.t("xizmat xabarlari")
        if (u.type["@type"] === "userTypeBot")
            return "bot"
        const s = u.status["@type"]
        if (s === "userStatusOnline")
            return u.status.expires > now ? Tr.t("onlayn") : lastSeen(u.status.expires, now)
        if (s === "userStatusOffline")
            return lastSeen(u.status.was_online, now)
        return Tr.t(s === "userStatusRecently" ? "yaqinda bo'lgan"
             : s === "userStatusLastWeek" ? "shu hafta bo'lgan"
             : s === "userStatusLastMonth" ? "shu oy bo'lgan" : "anchadan beri bo'lmagan")
    }

    // "yozmoqda...", "Ali yozmoqda...", "2 kishi yozmoqda..." or ""
    function activity(c) {
        const acts = Object.values(c && actions[c.id] || {})
        if (!acts.length)
            return ""
        const a = acts[0]       // (the other one tapping an emoji alone: Telegram-iOS's "enjoying 😂 animations")
        const what = a.action === "chatActionWatchingAnimations" && a.emoji ? Tr.f("%1 animatsiyalaridan zavqlanmoqda", a.emoji)
                   : Tr.t(doing[a.action] || "yozmoqda") + "..."
        if (c.type["@type"] === "chatTypePrivate")
            return what
        return (acts.length > 1 ? Tr.n("%1 kishi", acts.length) : senderName(acts[0].sender, true)) + " " + what
    }

    function lastSeen(unix, now) {
        if (now - unix < 60)
            return Tr.t("hozirgina bo'lgan")
        if (now - unix < 3600)
            return Tr.n("%1 daqiqa oldin bo'lgan", Math.floor((now - unix) / 60))
        const d = new Date(unix * 1000), today = new Date(now * 1000)
        if (d.toDateString() === today.toDateString())
            return Tr.f("bugun %1 da bo'lgan", Qt.formatTime(d, "HH:mm"))
        if (d.toDateString() === new Date(now * 1000 - 86400000).toDateString())
            return Tr.f("kecha %1 da bo'lgan", Qt.formatTime(d, "HH:mm"))
        return Tr.f("%1 da bo'lgan", Qt.formatDate(d, "dd.MM.yy"))
    }

    // 12345 -> "12 345"
    function count(n) {
        return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ")
    }

    // how long messages stay: 1 kun, 1 hafta, 1 oy (by whole months, weeks, days, hours, minutes)
    function lasting(secs) {
        const units = [[2678400, "%1 oy"], [604800, "%1 hafta"], [86400, "%1 kun"], [3600, "%1 soat"], [60, "%1 daqiqa"]]
        for (const u of units)
            if (secs >= u[0] && secs % u[0] === 0)
                return Tr.n(u[1], secs / u[0])
        return Tr.n("%1 soniya", secs)
    }
    // the same in the field's ⏱: 1k, 1h, 1o
    function lastingShort(secs) {
        const units = Tr.en ? [[2678400, "mo"], [604800, "w"], [86400, "d"], [3600, "h"], [60, "m"]]
                            : [[2678400, "o"], [604800, "h"], [86400, "k"], [3600, "s"], [60, "d"]]
        for (const u of units)
            if (secs >= u[0])
                return Math.floor(secs / u[0]) + u[1]
        return secs + "s"
    }

    // a post's views as Telegram-iOS shows them by the time: 957, 12.3K, 1.2M
    function short(n) {
        const cut = (v, u) => (v >= 100 ? Math.floor(v) : Math.floor(v * 10) / 10) + u
        return n < 1000 ? String(n) : n < 1000000 ? cut(n / 1000, "K") : cut(n / 1000000, "M")
    }

    readonly property var kinds: ({
        messagePhoto: "Rasm", messageVideo: "Video", messageVoiceNote: "Ovozli xabar", messageAudio: "Musiqa",
        messageSticker: "Stiker", messageAnimation: "GIF", messageDocument: "Fayl", messageContact: "Kontakt",
        messageLocation: "Joylashuv", messageLiveLocation: "Jonli joylashuv", messageVenue: "Joy", messagePoll: "So'rovnoma", messageVideoNote: "Video xabar",
        messageStory: "Hikoya", messageDice: "O'yin", messageCall: "Qo'ng'iroq", messageGame: "O'yin",
        messageInvoice: "To'lov", messageChatAddMembers: "a'zo qo'shildi", messageChatJoinByLink: "guruhga qo'shildi",
        messageChatDeleteMember: "guruhdan chiqdi", messagePinMessage: "xabar qadaldi", messageChatChangeTitle: "nom o'zgardi",
        messageChatChangePhoto: "rasm o'zgardi", messageBasicGroupChatCreate: "guruh yaratildi",
        messageSupergroupChatCreate: "guruh yaratildi", messageContactRegistered: "Telegram'ga qo'shildi",
        messageChatDeletePhoto: "rasm o'chirildi", messageChatJoinByRequest: "guruhga qo'shildi",
        messageChatUpgradeTo: "superguruhga aylandi", messageChatUpgradeFrom: "superguruhga aylandi",
        messageChatSetMessageAutoDeleteTime: "avto-o'chirish o'zgardi", messageScreenshotTaken: "skrinshot olindi",
        messageChatSetTheme: "mavzu o'zgardi", messageChatSetBackground: "fon o'zgardi",
        messageForumTopicCreated: "mavzu yaratildi", messageForumTopicEdited: "mavzu o'zgardi",
        messageVideoChatStarted: "video chat boshlandi", messageVideoChatEnded: "video chat tugadi",
        messageVideoChatScheduled: "video chat rejalashtirildi", messageInviteVideoChatParticipants: "video chatga taklif",
        messageExpiredPhoto: "Rasm muddati tugadi", messageExpiredVideo: "Video muddati tugadi",
        messageExpiredVoiceNote: "Ovozli xabar muddati tugadi", messageExpiredVideoNote: "Video xabar muddati tugadi",
        messagePaidMedia: "Pullik media", messageGift: "Hadya", messageUpgradedGift: "Hadya", messageRefundedUpgradedGift: "Hadya",
        messageGiftedPremium: "Premium hadya", messagePremiumGiftCode: "Premium hadya", messageGiftedStars: "Yulduzlar hadya",
        messageGiveaway: "Konkurs", messageGiveawayCreated: "Konkurs", messageGiveawayCompleted: "Konkurs yakunlandi",
        messageGiveawayWinners: "Konkurs g'oliblari", messageChatBoost: "Kanal kuchaytirildi",
        messagePaymentSuccessful: "To'lov qilindi", messageProximityAlertTriggered: "Yaqinlashdi",
        messageSuggestProfilePhoto: "Profil rasmi taklifi", messageCustomServiceAction: "Xizmat xabari",
        messageBotWriteAccessAllowed: "botga ruxsat berildi", messageWebAppDataSent: "ilova ma'lumot yubordi",
        messageUsersShared: "Kontakt ulashildi", messageChatShared: "Chat ulashildi", messageChecklist: "Ro'yxat",
        messagePaidMessagePriceChanged: "pullik xabar narxi o'zgardi",
        messageDirectMessagePriceChanged: "kanalga xabar narxi o'zgardi",
        messagePaidMessagesRefunded: "yulduzlar qaytarildi",
        messageUnsupported: "Bu Telegram versiyasida ochilmaydi", messageManagedBotCreated: "bot yaratildi"
    })

    // the text of a message that is text: plain, one emoji alone (TDLib makes it messageAnimatedEmoji),
    // or a rich message (its blocks' words, a paragraph a line); null for the rest
    function plain(content) {
        const t = content["@type"]
        if (t === "messageText")
            return content.text.text
        if (t === "messageAnimatedEmoji")
            return content.emoji
        if (t === "messageRichMessage") {
            const lines = []
            for (const b of content.message.blocks) {
                const words = []
                words_of(b, words)
                if (words.length)
                    lines.push(words.join(""))
            }
            return lines.join("\n")
        }
        return null
    }
    // a formatted text as Telegram draws it: "" when there is nothing to draw but its words, else
    // JSON of its parts, [{ q, h }]: q "" for words, "quote", "fold" (a quote that opens), "pre" (code),
    // h the part as StyledText. Quotes and code stand apart; the rest is bold, italic, links (href:
    // the url, or "@name", "#tag", "/command", "user:<id>", "time:<s>", "spoiler"). A spoiler is
    // a link to "spoiler" until `bare` (Words hides its letters under dust). (TDLib's offsets are in UTF-16, as JavaScript's strings.)
    readonly property var marks: ({
        textEntityTypeBold: ["<b>", "</b>"], textEntityTypeItalic: ["<i>", "</i>"],
        textEntityTypeUnderline: ["<u>", "</u>"], textEntityTypeStrikethrough: ["<s>", "</s>"],
        textEntityTypeCode: ["<font face='monospace'>", "</font>"]
    })
    readonly property var linked: ["textEntityTypeUrl", "textEntityTypeTextUrl", "textEntityTypeMention",
                                   "textEntityTypeMentionName", "textEntityTypeHashtag", "textEntityTypeCashtag",
                                   "textEntityTypeBotCommand", "textEntityTypeEmailAddress", "textEntityTypePhoneNumber",
                                   "textEntityTypeMediaTimestamp", "textEntityTypeBankCardNumber"]
    readonly property var blocks: ({ textEntityTypeBlockQuote: "quote", textEntityTypeExpandableBlockQuote: "fold",
                                     textEntityTypePre: "pre", textEntityTypePreCode: "pre" })
    // the entities a sender gives (TDLib finds links, @names, #tags itself): kept when editing
    readonly property var given: ["textEntityTypeBold", "textEntityTypeItalic", "textEntityTypeUnderline",
                                  "textEntityTypeStrikethrough", "textEntityTypeSpoiler", "textEntityTypeCode",
                                  "textEntityTypePre", "textEntityTypePreCode", "textEntityTypeTextUrl",
                                  "textEntityTypeMentionName", "textEntityTypeBlockQuote",
                                  "textEntityTypeExpandableBlockQuote", "textEntityTypeCustomEmoji"]
    function hasSpoiler(ft) {
        return !!ft && (ft.entities || []).some((e) => e.type["@type"] === "textEntityTypeSpoiler")
    }
    function rich(ft, bare) {
        const es = ((ft && ft.entities) || []).filter((e) => {
            const t = e.type["@type"]
            return marks[t] || blocks[t] || linked.indexOf(t) >= 0 || t === "textEntityTypeSpoiler"
        })
        const s = ft ? ft.text : ""
        if (!es.length) {
            // no formatting, but emoji still become images (otherwise Words draws the plain text)
            if (!Emo.ready || !Emo.hint.test(s))
                return ""
            const h0 = Emo.emojify(escaped(s))
            return h0.indexOf("<img") >= 0 ? JSON.stringify([{ q: "", h: h0 }]) : ""
        }
        const cuts = [0, s.length]
        for (const e of es)
            cuts.push(e.offset, e.offset + e.length)
        const at = cuts.filter((c, i, all) => all.indexOf(c) === i).sort((a, b) => a - b)
        const parts = []
        let cur = null
        for (let k = 0; k + 1 < at.length; k++) {
            const a = at[k], b = at[k + 1]
            const over = es.filter((e) => e.offset <= a && e.offset + e.length >= b)
            const block = over.find((e) => blocks[e.type["@type"]]) || null
            if (!cur || cur.block !== block) {
                cur = { q: block ? blocks[block.type["@type"]] : "", raw: "", h: "", block: block }
                parts.push(cur)
            }
            let piece = s.slice(a, b)
            cur.raw += piece
            const spoiled = !bare && over.some((e) => e.type["@type"] === "textEntityTypeSpoiler")
            let h = Emo.emojify(escaped(piece))
            for (const e of over) {
                const m = marks[e.type["@type"]]
                if (m && !(m[0].indexOf("monospace") > 0 && cur.q === "pre"))
                    h = m[0] + h + m[1]
            }
            const link = spoiled ? "spoiler" : over.map((e) => href(e, s)).find((x) => x) || ""
            if (link)
                h = "<a href=\"" + link.replace(/"/g, "&quot;") + "\">" + h + "</a>"
            cur.h += h
        }
        // the line breaks around a quote are the quote's edges now: dropped
        const out = []
        for (let k = 0; k < parts.length; k++) {
            const p = parts[k]
            if (!p.q) {
                if (k > 0)
                    p.h = p.h.replace(/^((?:<[^>]+>)*)<br>/, "$1")
                if (k + 1 < parts.length)
                    p.h = p.h.replace(/<br>((?:<\/[^>]+>)*)$/, "$1")
                if (!p.raw.trim())
                    continue
            }
            out.push({ q: p.q, h: p.h })
        }
        return JSON.stringify(out)
    }
    // words for StyledText: its own marks escaped, line breaks kept, runs of spaces kept
    function escaped(t) {
        return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                .replace(/\n/g, "<br>").replace(/ (?= )/g, "&nbsp;")
    }
    function href(e, s) {
        const t = e.type["@type"], w = s.substr(e.offset, e.length)
        switch (t) {
        case "textEntityTypeUrl": return /^[a-z][a-z0-9+.-]*:/i.test(w) ? w : "https://" + w
        case "textEntityTypeTextUrl": return e.type.url
        case "textEntityTypeEmailAddress": return "mailto:" + w
        case "textEntityTypePhoneNumber": return "tel:" + w.replace(/[^0-9+]/g, "")
        case "textEntityTypeMentionName": return "user:" + e.type.user_id
        case "textEntityTypeMediaTimestamp": return "time:" + e.type.media_timestamp
        case "textEntityTypeMention":
        case "textEntityTypeHashtag":
        case "textEntityTypeCashtag":
        case "textEntityTypeBotCommand":
        case "textEntityTypeBankCardNumber": return w
        }
        return ""
    }
    // the formatted text a message's words are in (its text, or a picture's caption)
    function formatted(content) {
        const t = content["@type"]
        if (t === "messageAnimatedEmoji")       // one emoji alone: its words, so Emo makes it a picture too
            return { "@type": "formattedText", text: content.emoji, entities: [] }
        return t === "messageText" ? content.text : content.caption && content.caption.text ? content.caption : null
    }

    // every richTextPlain's string under a page block, in order
    function words_of(v, out) {
        if (Array.isArray(v)) {
            for (const x of v)
                words_of(x, out)
        } else if (v && typeof v === "object") {
            if (v["@type"] === "richTextPlain")
                out.push(v.text)
            else
                for (const k in v)
                    if (k !== "@type")
                        words_of(v[k], out)
        }
    }

    // a service message as Telegram words it (who did what), in a pill in the middle of the chat;
    // null when the message is not one. `chat` tells a channel from a group.
    // «Siz» takes the verb's second person: «Siz xabarni qadadingiz», not «… qadadi».
    function service(m, chat) {
        const s = serviceWords(m, chat)
        return s !== null && !Tr.en && m.is_outgoing && s.startsWith("Siz ") && s.endsWith("di") ? s + "ngiz" : s
    }
    // (Tr.f's %1 is who did it; in Uzbek a person done to has -ni: «Alini», «sizni»)
    function serviceWords(m, chat) {
        const c = m.content, t = c["@type"]
        const chan = !!(chat && chat.type.is_channel)
        const me_ = m.is_outgoing ? Tr.t("Siz") : senderName(m.sender_id, false) || (chat ? chat.title : "")
        const user = (id) => {
            const name = senderName({ "@type": "messageSenderUser", user_id: id }, false) || Tr.t("kimdir")
            return id === (me && me.id) ? Tr.t("sizni") : Tr.en ? name : name + "ni"
        }
        switch (t) {
        case "messageBasicGroupChatCreate":
        case "messageSupergroupChatCreate":
            return chan ? Tr.t("Kanal yaratildi") : Tr.f("%1 «%2» guruhini yaratdi", me_, c.title)
        case "messageChatAddMembers": {
            const others = c.member_user_ids.filter((id) => id !== m.sender_id.user_id)
            return others.length ? Tr.f("%1 %2 qo'shdi", me_, others.map(user).join(", "))
                                 : Tr.f(chan ? "%1 kanalga qo'shildi" : "%1 guruhga qo'shildi", me_)
        }
        case "messageChatJoinByLink": return Tr.f("%1 havola orqali qo'shildi", me_)
        case "messageChatJoinByRequest": return Tr.f(chan ? "%1 kanalga qo'shildi" : "%1 guruhga qo'shildi", me_)
        case "messageChatDeleteMember":
            return c.user_id === m.sender_id.user_id ? Tr.f(chan ? "%1 kanaldan chiqdi" : "%1 guruhdan chiqdi", me_)
                                                     : Tr.f("%1 %2 chiqardi", me_, user(c.user_id))
        case "messagePinMessage": return chan ? Tr.t("Xabar qadaldi") : Tr.f("%1 xabarni qadadi", me_)
        case "messageChatChangeTitle":
            return chan ? Tr.f("Kanal nomi «%1»ga o'zgardi", c.title) : Tr.f("%1 guruh nomini «%2»ga o'zgartirdi", me_, c.title)
        case "messageChatChangePhoto": return chan ? Tr.t("Kanal rasmi o'zgardi") : Tr.f("%1 guruh rasmini o'zgartirdi", me_)
        case "messageChatDeletePhoto": return chan ? Tr.t("Kanal rasmi o'chirildi") : Tr.f("%1 guruh rasmini o'chirdi", me_)
        case "messageChatUpgradeTo":
        case "messageChatUpgradeFrom": return Tr.t("Guruh superguruhga aylandi")
        case "messageContactRegistered": return Tr.f("%1 Telegram'ga qo'shildi", me_)
        case "messageScreenshotTaken": return Tr.f("%1 skrinshot oldi", me_)
        case "messageForumTopicCreated": return Tr.f("«%1» mavzusi yaratildi", c.name)
        case "messageForumTopicEdited": return Tr.f("%1 mavzuni o'zgartirdi", me_)
        case "messageVideoChatStarted": return chan ? Tr.t("Jonli efir boshlandi") : Tr.f("%1 video chatni boshladi", me_)
        case "messageVideoChatEnded": return Tr.t(chan ? "Jonli efir tugadi" : "Video chat tugadi")
        case "messageVideoChatScheduled": return Tr.t(chan ? "Jonli efir rejalashtirildi" : "Video chat rejalashtirildi")
        case "messageInviteVideoChatParticipants": return Tr.f("%1 video chatga taklif qildi", me_)
        case "messageChatSetTheme": return Tr.f("%1 chat mavzusini o'zgartirdi", me_)
        case "messageChatSetBackground": return Tr.f("%1 chat fonini o'zgartirdi", me_)
        case "messageChatSetMessageAutoDeleteTime":
            return Tr.t(c.message_auto_delete_time ? "Avto-o'chirish yoqildi" : "Avto-o'chirish o'chirildi")
        case "messageChatBoost": return Tr.f(chan ? "%1 kanalni kuchaytirdi" : "%1 guruhni kuchaytirdi", me_)
        case "messageCustomServiceAction": return c.text
        case "messageBotWriteAccessAllowed": return Tr.t("Botga yozishga ruxsat berildi")
        case "messageGiveawayCreated": return Tr.t("Konkurs boshlandi")
        case "messageGiveawayCompleted": return Tr.t("Konkurs yakunlandi")
        case "messagePaidMessagePriceChanged":
            return c.paid_message_star_count > 0
                ? Tr.f("%1 har bir xabar narxini ⭐ %2 qilib belgiladi", me_, count(c.paid_message_star_count))
                : Tr.f("%1 pullik xabarlarni o'chirdi", me_)
        case "messageDirectMessagePriceChanged":
            return !c.is_enabled ? Tr.t("Kanalga xabarlar o'chirildi")
                 : c.paid_message_star_count > 0
                   ? Tr.f("Kanalga har bir xabar narxi ⭐ %1 qilib belgilandi", count(c.paid_message_star_count))
                   : Tr.t("Kanalga bepul xabar yozish yoqildi")
        case "messagePaidMessagesRefunded":
            return Tr.f("%1 ta xabar uchun ⭐ %2 qaytarildi", count(c.message_count), count(c.star_count))
        }
        return null
    }

    // a kind we have no word for yet: said once in the log, so it can be added
    property var _unknown: ({})
    function kindOf(t) {
        if (kinds[t])
            return Tr.t(kinds[t])
        if (!_unknown[t]) {
            _unknown[t] = true
            console.warn("nullgram: no word for", t)
        }
        return Tr.t("Bu turdagi xabar hali yo'q")
    }

    // the text a message shows in the list (and a bubble without a picture); `chat`, when known, tells a
    // channel's «kanal yaratildi» from a group's (TDLib makes both of them messageSupergroupChatCreate)
    function preview(content, chat) {
        const t = content["@type"]
        if (chat && chat.type.is_channel && (t === "messageSupergroupChatCreate" || t === "messageBasicGroupChatCreate"))
            return Tr.t("kanal yaratildi")
        const words = plain(content)
        if (words !== null)
            return words
        const cp = cardPreview(content)
        if (cp !== "")
            return cp
        const caption = content.caption ? content.caption.text : ""
        if (t === "messageSticker" && content.sticker.emoji)
            return content.sticker.emoji + " " + Tr.t("Stiker")
        // a song by its name, as Telegram-iOS: «Title — Performer», else the file's name
        const a = t === "messageAudio" && content.audio
        const kind = a && a.title ? (a.performer ? a.title + " — " + a.performer : a.title)
                   : a && a.file_name ? a.file_name : kindOf(t)
        return caption ? kind + ", " + caption : kind
    }

    function stamp(unix) {
        const d = new Date(unix * 1000), now = new Date()
        if (d.toDateString() === now.toDateString())
            return Qt.formatTime(d, "HH:mm")
        if (now - d < 6 * 86400000)
            return Tr.weekday(d.getDay())
        return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "dd.MM" : "dd.MM.yy")
    }

    // ---- pictures --------------------------------------------------------------
    function photoPath(c) {
        const f = c.photo && c.photo.small
        return f && f.local.is_downloading_completed ? f.local.path : ""	// a path: image://round/ takes it as one
    }

    function watchPhoto(c) {
        const f = c && c.photo && c.photo.small
        if (!f || f.local.is_downloading_completed)
            return
        const ids = _fileChats[f.id] || []
        if (ids.indexOf(c.id) < 0)
            ids.push(c.id)
        _fileChats[f.id] = ids
        send({ "@type": "downloadFile", file_id: f.id, priority: 1, offset: 0, limit: 0, synchronous: false })
    }

    // ---- backgrounds (Telegram-iOS's wallpapers): Wallpaper.qml's spec from TDLib's background ----------------
    readonly property string defaultSlug: "fqv01SQemVIBAAAApND8LDRUhRU"     // Telegram's own pattern (BuiltinWallpaperData.default)
    function hex(n) {
        return ("000000" + ((n >>> 0) & 0xffffff).toString(16)).slice(-6)
    }
    // a BackgroundFill as Wallpaper's <fill>
    function fillSpec(f) {
        if (!f)
            return ""
        if (f["@type"] === "backgroundFillSolid")
            return hex(f.color)
        if (f["@type"] === "backgroundFillGradient")
            return hex(f.top_color) + "," + hex(f.bottom_color) + "@" + (f.rotation_angle || 0)
        return (f.colors || []).map(hex).join(",")
    }
    // a background and its type as the spec, with the file's path when it is here ("" else)
    function wallSpec(bg, type, path) {
        type = type || (bg && bg.type)
        if (!type)
            return ""
        const t = type["@type"]
        if (t === "backgroundTypePattern")
            return fillSpec(type.fill) + ";" + (type.is_inverted ? -type.intensity : type.intensity) + ";p;" + (path || "")
        if (t === "backgroundTypeFill")
            return fillSpec(type.fill) + ";0;;"
        if (t === "backgroundTypeWallpaper")
            return "000000;0;" + (type.is_blurred ? "blur" : "photo") + ";" + (path || "")
        return ""
    }
    // the spec to `done`: at once with what is here, again when its file has come down
    function wallOf(bg, type, done) {
        const doc = bg && bg.document && bg.document.document
        if (!doc || doc.local.is_downloading_completed) {
            done(wallSpec(bg, type, doc ? doc.local.path : ""))
            return
        }
        done(wallSpec(bg, type, ""))
        fetch(doc, 2, (path) => done(wallSpec(bg, type, path)))
    }
    // Telegram-iOS's own, for the day or the night (its pattern found by its name once)
    property var _builtin: undefined    // the pattern's background; null: asked
    property var _builtinWait: []
    function builtinType(dark) {
        const colors = dark ? [0x598bf6, 0x7a5eef, 0xd67cff, 0xf38b58] : [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884]
        return { "@type": "backgroundTypePattern", fill: { "@type": "backgroundFillFreeformGradient", colors: colors },
                 intensity: dark ? 34 : 50, is_inverted: dark, is_moving: false }
    }
    function builtin(done) {
        if (_builtin) {
            done(_builtin)
            return
        }
        _builtinWait.push(done)
        if (_builtin === null)
            return
        _builtin = null
        send({ "@type": "searchBackground", name: defaultSlug }, (r) => {
            _builtin = r["@type"] === "background" ? r : undefined
            const w = _builtinWait
            _builtinWait = []
            if (_builtin)
                for (const d of w)
                    d(_builtin)
        })
    }
    // a mode's default changed (null: back to Telegram's own): Theme's wall for it
    function setBackground(dark, bg) {
        const b = Object.assign({}, backgrounds)
        b[dark ? "night" : "day"] = bg || null
        backgrounds = b
        retheme()
    }
    // the chat theme chosen (Prefs.theme, one of emojiThemes by its emoji) as its themeSettings for the day or the night;
    // null: the Classic one
    function themeSet(dark) {
        const th = Prefs.theme ? emojiThemes.find((t) => t.name === Prefs.theme) : null
        return th ? (dark ? th.dark_settings : th.light_settings) || null : null
    }
    // a fill as one colour, "#rrggbb" (our bubbles are of one): a gradient's colours mixed
    function fillColor(f) {
        if (!f)
            return ""
        const cs = f["@type"] === "backgroundFillSolid" ? [f.color]
                 : f["@type"] === "backgroundFillGradient" ? [f.top_color, f.bottom_color] : (f.colors || [])
        if (!cs.length)
            return ""
        let r = 0, g = 0, b = 0
        for (const c of cs) {
            r += (c >> 16) & 255
            g += (c >> 8) & 255
            b += c & 255
        }
        return "#" + hex((Math.round(r / cs.length) << 16) | (Math.round(g / cs.length) << 8) | Math.round(b / cs.length))
    }
    // ---- the app's theme: a base (Classic, Day; Night, Tinted) and its accent (Looks.js), or one of Telegram's chat themes ----
    function baseNow(dark) {
        const b = dark ? Prefs.nightBase : Prefs.dayBase
        return Looks.BASES.some((x) => x.id === b && x.dark === dark) ? b : dark ? "night" : "classic"
    }
    function accentOf(base) {
        let a
        try { a = JSON.parse(Prefs.accents)[base] } catch (e) {}
        return a === undefined ? Looks.first(base) : a
    }
    // the app's own look by day or by night: its base with its accent
    function ownLook(dark) {
        return Looks.look(baseNow(dark), accentOf(baseNow(dark)))
    }
    // the look by day or by night: the chat theme's (its themeSettings: accent, our bubbles, its base's tint), else
    // the base's with its accent
    function lookOf(dark) {
        const set = themeSet(dark)
        if (!set)
            return ownLook(dark)
        const out = fillColor(set.outgoing_message_fill)
        const accent = set.accent_color ? (set.accent_color >>> 0) & 0xffffff : -1
        const tinted = dark && accent >= 0 && !!set.base_theme && set.base_theme["@type"] === "builtInThemeTinted"
        return { base: "", dark: dark, accent: accent >= 0 ? "#" + hex(accent) : "", out: out,
                 outLight: out !== "" && Looks.lightness(parseInt(out.slice(1), 16)) > 0.705, outMeta: "", check: "", control: "",
                 bubbleIn: "", tint: tinted ? Looks.tintOf(accent) : null, badgeText: "", wall: null }
    }
    // one of Telegram's patterns by its name (a look's background), found once
    property var _patterns: ({})        // slug -> its background, or the list of those waiting for it
    function pattern(slug, done) {
        if (slug === defaultSlug) {
            builtin(done)
            return
        }
        const have = _patterns[slug]
        if (have && !Array.isArray(have)) {
            done(have)
            return
        }
        if (have) {
            have.push(done)
            return
        }
        _patterns[slug] = [done]
        send({ "@type": "searchBackground", name: slug }, (r) => {
            const w = _patterns[slug]
            if (r["@type"] !== "background") {
                delete _patterns[slug]
                return
            }
            _patterns[slug] = r
            for (const d of w)
                d(r)
        })
    }
    // a look's background as a spec to `done` (its colours at once, then with its pattern): a base's tile
    function wallOfLook(l, done) {
        const w = l.wall
        if (!w)
            builtin((p) => wallOf(p, builtinType(l.dark), done))
        else if (w.slug) {
            done(wallSpec(null, { "@type": "backgroundTypeFill", fill: lookWallType(w).fill }, ""))
            pattern(w.slug, (p) => wallOf(p, lookWallType(w), done))
        } else
            done(wallSpec(null, lookWallType(w), ""))
    }
    // a look's background as TDLib's type
    function lookWallType(w) {
        const fill = (cs) => cs.length === 1 ? { "@type": "backgroundFillSolid", color: cs[0] }
                                             : { "@type": "backgroundFillFreeformGradient", colors: cs }
        if (w.fill)
            return { "@type": "backgroundTypeFill", fill: fill(w.fill) }
        return { "@type": "backgroundTypePattern", fill: fill(w.colors), intensity: Math.abs(w.intensity), is_inverted: w.intensity < 0, is_moving: false }
    }
    // the background the chats have by day or by night, and its type: the chosen theme's while it is the one in use
    // (Prefs.themeWall; a chat theme's, a look's, else Telegram's own), else the one set (TDLib's default), else the theme's.
    // `slug`: a look's pattern, to be found (pattern()) when `background` is not here yet
    function wallNow(dark) {
        const set = themeSet(dark)
        const mine = backgrounds[dark ? "night" : "day"] || null
        const bg = (!Prefs.themeWall && mine) || (set && set.background) || null
        if (bg)
            return { background: bg, type: bg.type, builtin: false }
        const w = set ? null : lookOf(dark).wall
        if (w && w.slug) {
            const p = w.slug === defaultSlug ? _builtin : _patterns[w.slug]
            return { background: p && !Array.isArray(p) ? p : null, type: lookWallType(w), slug: w.slug, builtin: false, look: true }
        }
        if (w)
            return { background: null, type: lookWallType(w), builtin: false, look: true }
        return { background: _builtin || null, type: builtinType(dark), builtin: true }
    }
    property var _wallAsked: ({})       // "day" / "night" -> the last asking's number (an older one's answer is dropped)
    function rewall(dark) {
        const mode = dark ? "night" : "day"
        const n = (_wallAsked[mode] || 0) + 1
        _wallAsked[mode] = n
        const put = (s) => {
            if (_wallAsked[mode] !== n || !s)
                return
            if (dark)
                Theme.wallNight = s
            else
                Theme.wallDay = s
        }
        const now = wallNow(dark)
        if (now.builtin)
            builtin((p) => wallOf(p, builtinType(dark), put))
        else if (now.slug && !now.background) {
            put(wallSpec(null, { "@type": "backgroundTypeFill", fill: now.type.fill }, ""))      // (its colours until the pattern is found)
            pattern(now.slug, (p) => wallOf(p, now.type, put))
        } else
            wallOf(now.background, now.type, put)
    }
    // the theme's colours and backgrounds into Theme: as it is chosen, as the themes come, as night falls
    function retheme() {
        const l = lookOf(Theme.dark)
        if (l.base === "day") {         // (the Day's grey bubbles are for its white page: white over any other background)
            const now = wallNow(Theme.dark)
            if (!now.look || now.slug)
                l.bubbleIn = ""
        }
        Theme.look = l
        rewall(false)
        rewall(true)
    }
    // a theme chosen on the Ko'rinish page ("" the app's own: its base and accent): its background with it
    function chooseTheme(name) {
        Prefs.themeWall = true
        Prefs.theme = name
        retheme()
    }
    // «O'z mavzungizni yaratish»: a base chosen (a dark one is the night's, and night falls), an accent of a base
    function chooseBase(id) {
        const b = Looks.BASES.find((x) => x.id === id)
        if (!b)
            return
        Prefs.themeWall = true
        Prefs.theme = ""
        if (b.dark)
            Prefs.nightBase = id
        else
            Prefs.dayBase = id
        Theme.dark = b.dark
        retheme()
    }
    function chooseAccent(base, key) {
        let all = {}
        try { all = JSON.parse(Prefs.accents) || {} } catch (e) {}
        all[base] = key
        Prefs.themeWall = true
        Prefs.theme = ""
        Prefs.accents = JSON.stringify(all)
        retheme()
    }
    onEmojiThemesChanged: retheme()
    property Connections _themeWatch: Connections {
        target: Theme
        function onDarkChanged() { store.retheme() }
    }
    property Connections _prefsWatch: Connections {
        target: Prefs
        function onThemeChanged() { store.retheme() }
        function onThemeWallChanged() { store.retheme() }
        function onDayBaseChanged() { store.retheme() }
        function onNightBaseChanged() { store.retheme() }
        function onAccentsChanged() { store.retheme() }
    }
    // a chat's own background or its theme's, as a spec to `done` (with the night's dimming); "" when it has none
    function chatWall(c, dark, done) {
        const own = c && c.background
        if (own && own.background) {
            wallOf(own.background, own.background.type, (s) => done(s, (own.dark_theme_dimming || 0) / 100))
            return
        }
        const th = c && c.theme && c.theme["@type"] === "chatThemeEmoji" ? emojiThemes.find((t) => t.name === c.theme.name) : null
        const set = th && (dark ? th.dark_settings : th.light_settings)
        if (set && set.background) {
            wallOf(set.background, set.background.type, (s) => done(s, 0))
            return
        }
        done("", 0)
    }

    // ---- an emoji alone's effects (it tapped): Telegram's own set of them, "EmojiAnimations" (TDLib's
    // animated_emoji_click special set; it hands them out itself only in private chats) ----
    property var _effects: null         // its stickers by emoji (no skin tone, no U+FE0F); null: not here yet
    property var _effectsWait: []
    property var _lastEffect: ({})      // emoji -> the file played last for it (not the same one twice running)
    function bareEmoji(e) {
        return e.replace(/\uFE0F|\uD83C[\uDFFB-\uDFFF]/g, "")
    }
    // one of emoji's effects (a sticker) to `done`, picked at random as TDLib does; none: `done` is not called
    function emojiEffect(emoji, done) {
        if (!emoji)
            return
        if (_effects === null) {
            _effectsWait.push([emoji, done])
            if (_effectsWait.length === 1)
                send({ "@type": "searchStickerSet", name: "EmojiAnimations", ignore_cache: false }, (r) => {
                    if (r["@type"] === "stickerSet") {
                        const by = {}
                        r.stickers.forEach((st, k) => {
                            // (each its emoji and a number, 1-9 as a keycap: Telegram-iOS's index of it)
                            for (const e of r.emojis && r.emojis[k] ? r.emojis[k].emojis : [st.emoji]) {
                                const b = bareEmoji(e)
                                if (!/^[0-9]\u20E3$/.test(b))
                                    (by[b] = by[b] || []).push(st)
                            }
                        })
                        _effects = by
                    }
                    const w = _effectsWait
                    _effectsWait = []
                    if (_effects !== null)      // (else: asked again on the next tap)
                        for (const [e, d] of w)
                            emojiEffect(e, d)
                })
            return
        }
        let b = bareEmoji(emoji)
        if (["💛", "💙", "💚", "💜", "🧡", "🖤", "🤎", "🤍"].indexOf(b) >= 0)   // (Telegram-iOS: a heart's are the red one's)
            b = "❤"
        let all = _effects[b] || []
        if (all.length > 1)
            all = all.filter((st) => st.sticker.id !== _lastEffect[b])
        if (!all.length)
            return
        const st = all[Math.floor(Math.random() * all.length)]
        _lastEffect[b] = st.sticker.id
        done(st)
    }

    // a file's local path to `done`, now or once TDLib has it (one download however many ask)
    property var _waiters: ({})
    function fetch(f, priority, done) {
        if (f.local.is_downloading_completed) {
            done(f.local.path)
            return
        }
        const w = _waiters[f.id] || []
        w.push(done)
        _waiters[f.id] = w
        if (w.length === 1)
            send({ "@type": "downloadFile", file_id: f.id, priority: priority, offset: 0, limit: 0, synchronous: false },
                 (r) => { if (r["@type"] === "file") file(r) })      // (here already: no updateFile comes)
    }

    // ---- a gallery's slides: PhotoViewer pages through a chat's pictures and videos ----
    // one message as the viewer shows it: its shape, a picture for now (a small size or the
    // video's still, else Telegram's tiny preview), the biggest size, the video, what ↓ saves
    function slide(m) {
        const c = m.content
        if (c["@type"] === "messagePhoto" && c.photo.sizes.length) {
            const sizes = c.photo.sizes, big = sizes[sizes.length - 1]
            let small = big
            for (const z of sizes)
                if (z.width >= 320) {
                    small = z
                    break
                }
            return { id: m.id, aspect: big.height / big.width, small: small.photo, big: big.photo, video: null,
                     mini: c.photo.minithumbnail ? c.photo.minithumbnail.data : "",
                     file: big.photo, name: "photo_" + m.id + ".jpg" }
        }
        if (c["@type"] === "messageVideo") {
            const v = c.video
            return { id: m.id, aspect: v.width ? v.height / v.width : 9 / 16,
                     small: v.thumbnail && v.thumbnail.format["@type"] === "thumbnailFormatJpeg" ? v.thumbnail.file : null,
                     big: null, video: v.video, mini: v.minithumbnail ? v.minithumbnail.data : "",
                     file: v.video, name: v.file_name || "video_" + m.id + ".mp4" }
        }
        return null
    }
    // the slides either side of message `id`: done(older, newer), null at an end
    function besides(chatId, thread, id, done) {
        send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: topic(thread), query: "", sender_id: null,
               from_message_id: id, offset: -2, limit: 5, filter: { "@type": "searchMessagesFilterPhotoAndVideo" } }, (r) => {
            let older = null, newer = null
            for (const m of r.messages || []) {
                const s = slide(m)
                if (s && m.id < id && (!older || m.id > older.id))
                    older = s
                if (s && m.id > id && (!newer || m.id < newer.id))
                    newer = s
            }
            done(older, newer)
        })
    }
    // into ~/Downloads, brought down first: done(what to tell)
    function saveFile(f, name, done) {
        fetch(f, 32, (path) => {
            const to = td.save(path, name)
            done(to ? Tr.f("Saqlandi: Downloads/%1", to.split("/").pop()) : Tr.t("Saqlab bo'lmadi"))
        })
    }

    function file(f) {
        fileUpdated(f)
        const w = _waiters[f.id]
        if (w && f.local.is_downloading_completed) {
            delete _waiters[f.id]
            for (const done of w)
                done(f.local.path)
        }
        const ids = _fileChats[f.id]
        if (!ids || !f.local.is_downloading_completed)
            return
        delete _fileChats[f.id]
        for (const id of ids) {
            const c = chats[id]
            if (c && c.photo && c.photo.small.id === f.id) {
                c.photo.small = f
                refresh(c)
            }
        }
    }

    // how far a file is, 0..1, while it comes down or goes up; -1 when neither
    function progress(f) {
        const all = f.size || f.expected_size
        if (f.local.is_downloading_active)
            return all ? f.local.downloaded_size / all : 0
        if (f.remote.is_uploading_active)
            return all ? f.remote.uploaded_size / all : 0
        return -1
    }

    function stopFile(f) {
        delete _waiters[f.id]
        send({ "@type": "cancelDownloadFile", file_id: f.id, only_if_pending: false })
    }

    // 1234567 -> "1.2 MB"
    function size(n) {
        return n < 1024 ? n + " B" : n < 1048576 ? Math.round(n / 1024) + " KB"
             : n < 1073741824 ? (n / 1048576).toFixed(1) + " MB" : (n / 1073741824).toFixed(2) + " GB"
    }

    // ---- Ma'lumotlar va xotira: what comes down by itself, what is kept, what is saved ----------------------
    // a chat as the settings group it: "private" (with a bot, ourselves), "groups", "channels"
    function chatGroup(chatId) {
        const c = chats[chatId]
        if (!c)
            return "private"
        const t = c.type["@type"]
        return t === "chatTypeSupergroup" ? (c.type.is_channel ? "channels" : "groups")
             : t === "chatTypeBasicGroup" ? "groups" : "private"
    }
    // the network the auto-download settings for now are: Prefs.dl's "mobile" or "wifi"
    readonly property string dlNet: typeof net !== "undefined" && net && net.kind === "mobile" ? "mobile" : "wifi"
    // whether a chat's photo / video / file of `size` comes down by itself (Telegram-iOS's shouldDownloadMediaAutomatically)
    function autoOk(kind, size, chatId) {
        const n = Prefs.dl[dlNet]
        if (!n || !n.on || !n[kind])
            return false
        const g = chatGroup(chatId)
        let who = g
        if (g === "private") {
            const c = chats[chatId], u = c && c.type.user_id ? users[c.type.user_id] : null
            who = u && u.is_contact ? "contacts" : "others"
        }
        if (!n[kind][who])
            return false
        return kind === "video" ? (size || 0) <= n.videoMax : kind === "file" ? (size || 0) <= n.fileMax : true
    }
    // «Galereyaga saqlash»: a new photo / video that came (not ours) into ~/Downloads, as Prefs.saveTo says
    function autoSave(m) {
        if (!m || m.is_outgoing)
            return
        const want = Prefs.saveTo[chatGroup(m.chat_id)]
        const c = m.content, t = c["@type"]
        if (!want)
            return
        if (t === "messagePhoto" && want.photo && c.photo.sizes.length) {
            const f = c.photo.sizes[c.photo.sizes.length - 1].photo
            fetch(f, 2, (path) => td.save(path, "photo_" + m.chat_id + "_" + m.id + ".jpg"))
        } else if (t === "messageVideo" && want.video && c.video.video.size < 200e6) {
            fetch(c.video.video, 2, (path) => td.save(path, c.video.file_name || "video_" + m.chat_id + "_" + m.id + ".mp4"))
        }
    }
    // «Keshdagi mediani o'chirish» and «Keshning eng katta hajmi» (iOS's cache settings): what TDLib keeps of each
    // kind of chat older than its time (last opened), then the whole cache under the size; on start and daily
    function keepClean() {
        const k = Prefs.keep
        for (const g of ["private", "groups", "channels"]) {
            if (!(k[g] > 0))
                continue
            const ids = Object.keys(chats).filter((id) => chatGroup(id) === g).map(Number)
            if (ids.length)
                send({ "@type": "optimizeStorage", size: -1, ttl: k[g], count: -1, immunity_delay: -1, file_types: [],
                       chat_ids: ids, exclude_chat_ids: [], return_deleted_file_statistics: false, chat_limit: 0 })
        }
        if (Prefs.maxCache > 0)
            send({ "@type": "optimizeStorage", size: Prefs.maxCache * 1073741824, ttl: -1, count: -1, immunity_delay: -1,
                   file_types: [], chat_ids: [], exclude_chat_ids: [], return_deleted_file_statistics: false, chat_limit: 0 })
    }
    // TDLib counts its traffic per network type (getNetworkStatistics): told which one the phone is on
    function tellNetwork() {
        const k = typeof net !== "undefined" && net ? net.kind : "wifi"
        send({ "@type": "setNetworkType", type: { "@type": k === "mobile" ? "networkTypeMobile"
                                                         : k === "none" ? "networkTypeNone" : "networkTypeWiFi" } })
    }

    // ---- messages --------------------------------------------------------------
    // up to `limit` messages before `from` (0: the newest), newest first. TDLib answers
    // from its database at once and may give fewer: ask again until there are enough.
    // `failed`: TDLib said no (offline, too many asks) -- that is not the beginning of the chat.
    // `thread`: only a post's comments (its thread in the discussion group)
    // `directTopic`: a subscriber's thread in an administered channel direct messages chat
    // `local`: only what TDLib has without asking the server (only_local; Telegram X opens a chat so), up to
    // the first message it lacks -- consecutive, as TDLib keeps them
    function history(chatId, from, limit, done, got, thread, directTopic, local, forumTopic) {
        got = got || []
        const req = directTopic
            ? { "@type": "getDirectMessagesChatTopicHistory", chat_id: chatId, topic_id: directTopic,
                from_message_id: from, offset: 0, limit: limit - got.length }
            : forumTopic
            ? { "@type": "getForumTopicHistory", chat_id: chatId, forum_topic_id: forumTopic,
                from_message_id: from, offset: 0, limit: limit - got.length }
            : thread
            ? { "@type": "getMessageThreadHistory", chat_id: chatId, message_id: thread, from_message_id: from,
                offset: 0, limit: limit - got.length }
            : { "@type": "getChatHistory", chat_id: chatId, from_message_id: from, offset: 0,
                limit: limit - got.length, only_local: !!local }
        const t0 = td.fps ? Date.now() : 0
        send(req, (r) => {
            if (td.fps)
                console.warn("nullgram: history call from", from, "limit", limit - got.length, "got",
                             (r.messages || []).length, "in", Date.now() - t0, "ms")
            if (r["@type"] === "error") {
                console.warn("nullgram: getChatHistory", chatId, from, r.code, r.message)
                done(got, true)
                return
            }
            const msgs = r.messages || []
            got = got.concat(msgs)
            if (msgs.length === 0 || got.length >= limit)
                done(got, false)
            else
                store.history(chatId, msgs[msgs.length - 1].id, limit, done, got, thread, directTopic, local, forumTopic)
        })
    }

    // a message in a post's comments goes to its thread; in a channel DM inbox to its directMessages topic; in a forum to its topic
    function topic(thread, directTopic, forumTopic) {
        if (directTopic)
            return { "@type": "messageTopicDirectMessages", direct_messages_chat_topic_id: directTopic }
        if (forumTopic)
            return { "@type": "messageTopicForum", forum_topic_id: forumTopic }
        return thread ? { "@type": "messageTopicThread", message_thread_id: thread } : null
    }
    function sendOpts(silent, paidStars, schedule) {
        if (!silent && !(paidStars > 0) && !schedule)
            return null
        const o = { "@type": "messageSendOptions", disable_notification: !!silent }
        if (paidStars > 0)
            o.paid_message_star_count = paidStars
        if (schedule)
            o.scheduling_state = schedule
        return o
    }

    // silent: the subscribers get it without a sound (a channel's 🔔 off)
    // marks: the formatting given in the field (textEntity's), [] for none
    // the emojis a message of only one of goes as a dice (Telegram's apps do so: 🎲 alone is thrown, not
    // written); the server's list comes in updateDiceEmojis
    property var diceEmojis: ["🎲", "🎯", "🏀", "⚽", "🎳", "🎰"]
    function diceOf(text, marks) {
        if (marks && marks.length)
            return ""
        const t = (text || "").trim().replace(/\uFE0F/g, "")
        for (const e of diceEmojis)
            if (e.replace(/\uFE0F/g, "") === t)
                return e
        return ""
    }
    function sendText(chatId, text, replyTo, thread, silent, marks, directTopic, paidStars, schedule, linkPreviewOptions, forumTopic) {
        const dice = diceOf(text, marks)
        const content = dice ? { "@type": "inputMessageDice", emoji: dice, clear_draft: true }
            : { "@type": "inputMessageText", text: { "@type": "formattedText", text: text, entities: marks || [] } }
        if (linkPreviewOptions && !dice)
            content.link_preview_options = linkPreviewOptions
        const req = { "@type": "sendMessage", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic),
                      options: sendOpts(silent, paidStars, schedule),
                      input_message_content: content }
        if (replyTo)
            req.reply_to = { "@type": "inputMessageReplyToMessage", message_id: replyTo }
        send(req, check)
    }

    // files from the phone (td.recent's): pictures and videos together as an album when there are
    // several (unless `apart`), the rest one by one; the field's words ({ text, marks }) go under the
    // first. asFiles: all as documents; a picture or video with `spoiler` goes hidden under one
    function sendFiles(chatId, files, caption, replyTo, asFiles, thread, silent, apart, directTopic, paidStars, schedule, forumTopic) {
        const options = sendOpts(silent, paidStars, schedule)
        const text = { "@type": "formattedText", text: caption ? caption.text : "", entities: caption ? caption.marks : [] }
        // (TDLib 1.8.68: the file and its sizes go in an inputPhoto, inputVideo... of their own)
        const contents = files.map((f, k) => {
            const local = { "@type": "inputFileLocal", path: f.path }
            const c = k === 0 ? text : null
            if (asFiles)
                return { "@type": "inputMessageDocument", caption: c, document: { "@type": "inputDocument", document: local } }
            // a GIF goes as an animation, as Telegram-iOS sends one (a document before: no spoiler, not played
            // in the chat); Telegram makes it an MP4. Never in an album (TDLib takes photos and videos there)
            if (f.kind === "photo" && f.path.toLowerCase().endsWith(".gif")) {
                const g = td.probe(f.path)
                return { "@type": "inputMessageAnimation", caption: c, has_spoiler: !!f.spoiler,
                         animation: { "@type": "inputAnimation", animation: local, duration: g.duration,
                                      width: g.width || f.w, height: g.height || f.h } }
            }
            if (f.kind === "photo")
                return { "@type": "inputMessagePhoto", caption: c, has_spoiler: !!f.spoiler,
                         photo: { "@type": "inputPhoto", photo: local, width: f.w, height: f.h } }
            if (f.kind === "video") {
                const v = td.probe(f.path)
                return { "@type": "inputMessageVideo", caption: c, has_spoiler: !!f.spoiler,
                         video: { "@type": "inputVideo", video: local, duration: v.duration, width: v.width,
                                  height: v.height, supports_streaming: true } }
            }
            if (f.kind === "audio")
                return { "@type": "inputMessageAudio", caption: c,
                         audio: { "@type": "inputAudio", audio: local, duration: td.probe(f.path).duration } }
            return { "@type": "inputMessageDocument", caption: c, document: { "@type": "inputDocument", document: local } }
        })
        const reply = replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null
        const album = contents.filter((c) => c["@type"] === "inputMessagePhoto" || c["@type"] === "inputMessageVideo")
        const rest = contents.filter((c) => album.indexOf(c) < 0)
        if (album.length > 1 && !apart) {
            for (let k = 0; k < album.length; k += 10)
                send({ "@type": "sendMessageAlbum", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic), reply_to: k ? null : reply, options: options,
                       input_message_contents: album.slice(k, k + 10) }, check)
        } else {
            rest.unshift(...album)
        }
        for (const c of rest)
            send({ "@type": "sendMessage", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic), reply_to: reply, options: options,
                   input_message_content: c }, check)
    }

    function sendVoice(chatId, path, duration, waveform, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic) {
        send({ "@type": "sendMessage", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic),
               options: sendOpts(silent, paidStars, schedule),
               reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
               input_message_content: { "@type": "inputMessageVoiceNote",
                                        voice_note: { "@type": "inputVoiceNote", voice_note: { "@type": "inputFileLocal", path: path },
                                                      duration: duration, waveform: waveform } } }, check)
    }

    // a round video (384×384 square MP4, as Telegram's apps send them)
    function sendRound(chatId, path, duration, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic) {
        send({ "@type": "sendMessage", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic),
               options: sendOpts(silent, paidStars, schedule),
               reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
               input_message_content: { "@type": "inputMessageVideoNote", self_destruct_type: null,
                                        video_note: { "@type": "inputVideoNote", video_note: { "@type": "inputFileLocal", path: path },
                                                      thumbnail: null, duration: duration, length: 384 } } }, check)
    }
    // a sticker or a GIF from the panel (TDLib has them already: sent by their file's id, nothing uploaded)
    function sendSticker(chatId, st, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic) {
        send({ "@type": "sendMessage", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic),
               options: sendOpts(silent, paidStars, schedule),
               reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
               input_message_content: { "@type": "inputMessageSticker", emoji: st.emoji || "",
                                        sticker: { "@type": "inputSticker", sticker: { "@type": "inputFileId", id: st.sticker.id },
                                                   width: st.width, height: st.height } } }, check)
    }
    function sendGif(chatId, a, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic) {
        send({ "@type": "sendMessage", chat_id: chatId, topic_id: topic(thread, directTopic, forumTopic),
               options: sendOpts(silent, paidStars, schedule),
               reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
               input_message_content: { "@type": "inputMessageAnimation",
                                        animation: { "@type": "inputAnimation", animation: { "@type": "inputFileId", id: a.animation.id },
                                                     duration: a.duration, width: a.width, height: a.height },
                                        caption: null, has_spoiler: false } }, check)
    }

    // a text that is one to three emoji and nothing else: how many (it shows big, without a
    // bubble, as Telegram does), else 0
    function emojiCount(t) {
        if (!t || t.length > 48)
            return 0
        let n = 0, joined = false, flags = 0
        for (const ch of t) {
            const c = ch.codePointAt(0)
            if (c === 0x200d) {
                joined = true
                continue
            }
            if (c === 0xfe0f || c === 0xfe0e || c === 0x20e3 || (c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0020 && c <= 0xe007f))
                continue
            if (c >= 0x1f1e6 && c <= 0x1f1ff) {     // a flag is two of these
                if (flags++ % 2 === 0)
                    n++
                continue
            }
            if (!pictograph(c))
                return 0
            if (!joined)
                n++
            joined = false
        }
        return n <= 3 ? n : 0
    }
    function pictograph(c) {
        return (c >= 0x1f000 && c <= 0x1faff) || (c >= 0x2600 && c <= 0x27bf) || (c >= 0x2300 && c <= 0x23ff)
            || (c >= 0x2b00 && c <= 0x2bff) || (c >= 0x2190 && c <= 0x21ff) || (c >= 0x25a0 && c <= 0x25ff)
            || [0xa9, 0xae, 0x203c, 0x2049, 0x2122, 0x2139, 0x24c2, 0x3030, 0x303d, 0x3297, 0x3299].indexOf(c) >= 0
    }

    function editText(chatId, messageId, text, marks, linkPreviewOptions) {
        const content = { "@type": "inputMessageText",
                          text: { "@type": "formattedText", text: text, entities: marks || [] } }
        if (linkPreviewOptions)
            content.link_preview_options = linkPreviewOptions
        send({ "@type": "editMessageText", chat_id: chatId, message_id: messageId,
               input_message_content: content }, check)
    }

    function forward(toChat, fromChat, ids, copy, done) {
        send({ "@type": "forwardMessages", chat_id: toChat, from_chat_id: fromChat, message_ids: ids,
               send_copy: copy, remove_caption: false }, (r) => {
            check(r)
            if (done)
                done(r["@type"] !== "error")
        })
    }

    // put a reaction on a message, or take ours off
    function react(chatId, messageId, emoji, on) {
        const type = { "@type": "reactionTypeEmoji", emoji: emoji }
        if (on)
            send({ "@type": "addMessageReaction", chat_id: chatId, message_id: messageId, reaction_type: type,
                   is_big: false, update_recent_reactions: true }, check)
        else
            send({ "@type": "removeMessageReaction", chat_id: chatId, message_id: messageId, reaction_type: type }, check)
    }

    function pin(chatId, messageId, on) {
        if (on)
            send({ "@type": "pinChatMessage", chat_id: chatId, message_id: messageId, disable_notification: true,
                   only_for_self: false }, check)
        else
            send({ "@type": "unpinChatMessage", chat_id: chatId, message_id: messageId }, check)
    }

    // who a forwarded message first came from
    function origin(fi) {
        if (!fi)
            return ""
        const o = fi.origin
        const t = o["@type"]
        if (t === "messageOriginUser") {
            const u = users[o.sender_user_id]
            return u ? (u.first_name + " " + u.last_name).trim() : "..."
        }
        if (t === "messageOriginHiddenUser")
            return o.sender_name
        if (t === "messageOriginChat")
            return chats[o.sender_chat_id] ? chats[o.sender_chat_id].title : "..."
        if (t === "messageOriginChannel")
            return chats[o.chat_id] ? chats[o.chat_id].title : "..."
        return ""
    }

    // a message's reactions as the bubble shows them: [{ e, n, mine }] (stars and custom emoji as ⭐)
    // a message's reactions as its chips show them: [{ e, n, mine, who }]; `who`: the faces in place of the count
    // (Telegram-iOS's ChatMessageReactionsFooterContentNode): in a private chat ours if chosen, then the other one's
    // unless only we chose it; in a group the ones who chose it when TDLib names them all (recent_sender_ids, for
    // every reaction on it: it does when they are few), ours first; none in a channel, nor in Saved Messages
    function reactions(info, chat) {
        const list = info && info.reactions ? info.reactions.reactions : []
        const paidReactors = info && info.reactions && info.reactions.paid_reactors ? info.reactions.paid_reactors : []
        const t = chat ? chat.type : null
        const priv = !!t && t["@type"] === "chatTypePrivate" && !(me && t.user_id === me.id)
        const faces = priv || (!!t && t["@type"] !== "chatTypePrivate" && !(t["@type"] === "chatTypeSupergroup" && t.is_channel)
                               && list.every((r) => (r.recent_sender_ids || []).length === r.total_count))
        return list.map((r) => {
            const isPaid = r.type["@type"] === "reactionTypePaid"
            let who = []
            if (isPaid) {
                who = paidReactors.filter((p) => !p.is_anonymous && p.sender_id).slice(0, 3)
                                  .map((p) => p.sender_id.user_id ? { user_id: p.sender_id.user_id } : { chat_id: p.sender_id.chat_id })
            } else if (faces && priv) {
                if (r.is_chosen && me)
                    who.push({ user_id: me.id })
                if (!r.is_chosen || r.total_count >= 2)
                    who.push({ user_id: t.user_id })
            } else if (faces) {
                who = r.recent_sender_ids.map((s) => s.user_id ? { user_id: s.user_id } : { chat_id: s.chat_id })
                const k = me ? who.findIndex((s) => s.user_id === me.id) : -1
                if (k > 0)
                    who.unshift(who.splice(k, 1)[0])
            }
            const out = { e: r.type["@type"] === "reactionTypeEmoji" ? r.type.emoji : "⭐", n: r.total_count, mine: r.is_chosen, who: who }
            if (isPaid) {
                out.paid = true
                out.reactors = paidReactors
            }
            return out
        })
    }
    // a sender's face on an Avatar: its letters and tint, the ghost for a deleted account, its picture when it is here
    function faceOn(av, s) {
        av.letters = letters(senderName(s.user_id ? { "@type": "messageSenderUser", user_id: s.user_id }
                                                  : { "@type": "messageSenderChat", chat_id: s.chat_id }))
        av.tint = tints[Math.abs(s.user_id || s.chat_id || 0) % tints.length]
        const u = s.user_id && users[s.user_id]
        if (u && u.type && u.type["@type"] === "userTypeDeleted")
            av.ghost = true
        else if (s.user_id)
            userPhoto(u, (path) => av.source = path)
        else if (chats[s.chat_id]) {
            watchPhoto(chats[s.chat_id])
            av.source = photoPath(chats[s.chat_id])
        }
    }

    function deleteMessages(chatId, ids, everyone) {
        send({ "@type": "deleteMessages", chat_id: chatId, message_ids: ids, revoke: everyone }, check)
    }

    // ---- search ----------------------------------------------------------------
    // Uzbek Cyrillic as its Latin, so "Шавкат" is found by "shavkat" and the other way round;
    // small letters, no apostrophes (o'/oʻ/o` all one)
    readonly property var _latin: ({
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "", "ы": "i", "ь": "",
        "э": "e", "ю": "yu", "я": "ya", "ў": "o", "қ": "q", "ғ": "g", "ҳ": "h",
        "'": "", "`": "", "ʻ": "", "ʼ": "", "‘": "", "’": ""
    })
    function fold(text) {
        let out = ""
        for (const ch of (text || "").toLowerCase()) {
            const l = _latin[ch]
            out += l === undefined ? ch : l
        }
        return out
    }

    // chats for a query, as fast as each comes: ours by name from what is loaded (at once), then
    // TDLib's (its database, then the server's), then public ones; `done(kind, ids)` each time,
    // kind "chats" or "global". A newer query makes the older answers be dropped (by `asked`).
    property int _query: 0
    function searchChats(q, done) {
        const asked = ++_query
        const f = fold(q)
        const local = []
        for (const id in chats) {
            const c = chats[id]
            const u = c.type["@type"] === "chatTypePrivate" ? users[c.type.user_id] : null
            const names = fold(c.title) + " " + (u && u.usernames ? fold(u.usernames.active_usernames.join(" ")) : "")
            if (c.positions.length && names.indexOf(f) >= 0)
                local.push(c.id)
        }
        local.sort((a, b) => before(chats[a].order || "0", chats[b].order || "0") ? -1 : 1)
        done("chats", local.slice(0, 50))
        const mine = local.slice()
        const more = (r) => {
            if (asked !== _query || !r.chat_ids)
                return
            for (const id of r.chat_ids)
                if (mine.indexOf(id) < 0 && chats[id])
                    mine.push(id)
            done("chats", mine.slice(0, 50))
        }
        send({ "@type": "searchChats", query: q, limit: 50 }, more)
        send({ "@type": "searchChatsOnServer", query: q, limit: 50 }, more)
        if (q.replace(/^@/, "").length >= 4)
            send({ "@type": "searchPublicChats", query: q.replace(/^@/, "") }, (r) => {
                if (asked === _query && r.chat_ids)
                    done("global", r.chat_ids.filter((id) => mine.indexOf(id) < 0 && chats[id]))
            })
    }

    // messages with the query in every chat, newest first: `done(messages)`
    function searchMessages(q, done) {
        const asked = _query
        send({ "@type": "searchMessages", chat_list: null, query: q, offset: "", limit: 40,
               filter: null, chat_type_filter: null, min_date: 0, max_date: 0 }, (r) => {
            if (asked === _query)
                done(r.messages || [])
        })
    }

    // ---- contacts --------------------------------------------------------------
    // the contacts, by name: `done([user])` (users not yet known are asked for first)
    function contacts(done) {
        send({ "@type": "getContacts" }, (r) => {
            const ids = r.user_ids || []
            let left = 0
            const finish = () => {
                const list = ids.map((id) => users[id]).filter((u) => u)
                list.sort((a, b) => fold(a.first_name + " " + a.last_name) < fold(b.first_name + " " + b.last_name) ? -1 : 1)
                done(list)
            }
            for (const id of ids)
                if (!users[id]) {
                    left++
                    send({ "@type": "getUser", user_id: id }, (u) => {
                        if (u["@type"] === "user")
                            users[u.id] = u
                        if (--left === 0)
                            finish()
                    })
                }
            if (left === 0)
                finish()
        })
    }

    // a person's chat (made if there is none yet): `done(chatId)`
    function chatWith(userId, done) {
        send({ "@type": "createPrivateChat", user_id: userId, force: false }, (c) => {
            if (c["@type"] === "chat") {
                if (!chats[c.id]) {
                    c.positions = c.positions || []
                    chats[c.id] = c
                }
                done(c.id)
            }
        })
    }

    // a user's small picture's path, now or later: `done(path)`
    function userPhoto(u, done) {
        if (u && u.profile_photo && u.profile_photo.small)
            fetch(u.profile_photo.small, 1, done)
    }

    // the cache kept to Prefs.keep / maxCache: a minute after signing in (the chats known by then), then daily
    // users' and groups' updates come in bursts (statuses, member counts): `seen` once for a burst, 50 ms
    // after its first, not once each -- each was every binding on it worked out again
    function seenSoon() {
        if (!_seenSoon.running)
            _seenSoon.start()
    }
    property Timer _seenSoon: Timer { interval: 50; onTriggered: store.seen++ }
    property Timer cleaner: Timer { interval: 60000; repeat: true; onTriggered: { interval = 86400000; store.keepClean() } }
    property Connections _netWatch: Connections {
        target: typeof net !== "undefined" ? net : null
        function onChanged() { if (store.auth === "Ready") store.tellNetwork() }
    }

    // ---- Hikoyalar (Q) ------------------------------------------------------------
    // TDLib tells each chat's active stories as updateChatActiveStories once asked: a part at a time,
    // until it says there are no more (404)
    function loadStories(n) {
        send({ "@type": "loadActiveStories", story_list: { "@type": "storyListMain" } }, (r) => {
            if (r["@type"] === "ok" && n < 8)
                Qt.callLater(() => store.loadStories(n + 1))
        })
    }
    function unseen(chatId) {
        const a = stories[chatId]
        return !!a && a.stories.some((s) => s.story_id > a.max_read_story_id)
    }
    function hasStories(chatId) { return !!stories[chatId] }
    function sortStories() {
        const me = store.me ? store.me.id : 0
        const row = []
        for (const k in stories) {
            const a = stories[k]
            if (a.chat_id !== me && a.list && a.list["@type"] === "storyListMain")
                row.push(a)
        }
        row.sort((a, b) => (unseen(b.chat_id) - unseen(a.chat_id)) || (b.order - a.order))
        storyRow = row.map((a) => a.chat_id)
        storiesSeen++
        warmStories()
    }
    // where a chat's stories start when opened: its first unseen one, else the first
    function storyStart(chatId) {
        const a = stories[chatId]
        if (!a)
            return 0
        const i = a.stories.findIndex((s) => s.story_id > a.max_read_story_id)
        return Math.max(0, i)
    }
    function putStories(list) {
        for (const s of list || [])
            if (s && s.poster_chat_id && s.id)
                _storyCache[s.poster_chat_id + ":" + s.id] = s
    }
    function story(chatId, id, done) {
        const k = chatId + ":" + id
        if (_storyCache[k]) {
            done(_storyCache[k])
            return
        }
        send({ "@type": "getStory", story_poster_chat_id: chatId, story_id: id, only_local: true }, (r) => {
            if (r["@type"] === "story") {
                _storyCache[k] = r
                done(r)
                return
            }
            send({ "@type": "getStory", story_poster_chat_id: chatId, story_id: id, only_local: false }, (r2) => {
                if (r2["@type"] === "story")
                    _storyCache[k] = r2
                done(r2["@type"] === "story" ? r2 : null)
            })
        })
    }
    // warm up the first unseen story of the top active chats (metadata + preview) so tapping opens fast
    property var _storyWarmed: ({})
    function warmStories() {
        for (const cid of storyRow.slice(0, 3)) {
            const a = stories[cid]
            if (!a || !a.stories.length)
                continue
            const id = a.stories[storyStart(cid)].story_id
            const k = cid + ":" + id
            if (_storyWarmed[k])
                continue
            _storyWarmed[k] = true
            story(cid, id, (s) => {
                if (!s || !s.content)
                    return
                if (s.content["@type"] === "storyContentVideo") {
                    const th = s.content.video && s.content.video.thumbnail ? s.content.video.thumbnail.file : null
                    if (th)
                        fetch(th, 4, () => {})
                } else if (s.content["@type"] === "storyContentPhoto") {
                    const sizes = s.content.photo ? s.content.photo.sizes || [] : []
                    let f = null
                    for (const z of sizes)
                        if (!f || (z.width >= 720 && z.width < f.w) || f.w < 720)
                            f = { file: z.photo, w: z.width }
                    if (f)
                        fetch(f.file, 4, () => {})
                }
            })
        }
    }
    // seen: TDLib then moves max_read_story_id on (updateChatActiveStories)
    function openStory(chatId, id, on) {
        send({ "@type": on ? "openStory" : "closeStory", story_poster_chat_id: chatId, story_id: id })
    }
    function storyReact(chatId, id, emoji) {
        send({ "@type": "setStoryReaction", story_poster_chat_id: chatId, story_id: id,
               reaction_type: emoji ? { "@type": "reactionTypeEmoji", emoji: emoji } : null, update_recent_reactions: true })
        const s = _storyCache[chatId + ":" + id]
        if (s)
            s.chosen_reaction_type = emoji ? { "@type": "reactionTypeEmoji", emoji: emoji } : null
    }
    // «Shaxsiy javob…»: a message to the poster, answering the story
    function storyReply(chatId, id, text) {
        send({ "@type": "sendMessage", chat_id: chatId, reply_to: { "@type": "inputMessageReplyToStory",
               story_poster_chat_id: chatId, story_id: id },
               input_message_content: { "@type": "inputMessageText", text: { "@type": "formattedText", text: text, entities: [] },
                                        link_preview_options: null, clear_draft: false } })
    }
    function storyHidden(chatId) {
        const a = stories[chatId]
        return !!a && !!a.list && a.list["@type"] === "storyListArchive"
    }
    function storyArchive(chatId, id, posted, done) {
        send({ "@type": "toggleStoryIsPostedToChatPage", story_poster_chat_id: chatId, story_id: id,
               is_posted_to_chat_page: !!posted }, (r) => {
            if (r["@type"] === "ok") {
                const s = _storyCache[chatId + ":" + id]
                if (s)
                    s.is_posted_to_chat_page = !!posted
                storyChanged(chatId, id)
            }
            if (done)
                done(r)
        })
    }
    function storyPin(chatId, ids, done) {
        send({ "@type": "setChatPinnedStories", chat_id: chatId, story_ids: ids }, (r) => {
            if (done)
                done(r)
        })
    }
    function storyDelete(chatId, id, done) {
        send({ "@type": "deleteStory", story_poster_chat_id: chatId, story_id: id }, (r) => {
            if (r["@type"] === "ok") {
                delete _storyCache[chatId + ":" + id]
                const a = stories[chatId]
                if (a) {
                    a.stories = a.stories.filter((x) => x.story_id !== id)
                    if (!a.stories.length)
                        delete stories[chatId]
                    sortStories()
                }
                storyChanged(chatId, id)
            }
            if (done)
                done(r)
        })
    }
    function storyHide(chatId, hide, done) {
        const list = { "@type": hide ? "storyListArchive" : "storyListMain" }
        send({ "@type": "setChatActiveStoriesList", chat_id: chatId, story_list: list }, (r) => {
            if (r["@type"] === "ok") {
                const a = stories[chatId]
                if (a) {
                    a.list = list
                    sortStories()
                }
            }
            if (done)
                done(r)
        })
    }
    function fetchPrefix(f, priority, limit) {
        if (!f || (f.local && f.local.is_downloading_completed))
            return
        send({ "@type": "downloadFile", file_id: f.id, priority: priority || 12,
               offset: 0, limit: limit || 524288, synchronous: false })
    }
    function storyViewers(chatId, storyId, isMine, opts, done) {
        const o = opts || {}
        const req = isMine
            ? { "@type": "getStoryInteractions", story_id: storyId, query: o.query || "",
                only_contacts: !!o.onlyContacts, prefer_forwards: !!o.preferForwards,
                prefer_with_reaction: !!o.preferWithReaction, offset: o.offset || "", limit: 50 }
            : { "@type": "getChatStoryInteractions", story_poster_chat_id: chatId, story_id: storyId,
                reaction_type: null, prefer_forwards: !!o.preferForwards, offset: o.offset || "", limit: 50 }
        send(req, (r) => {
            if (r["@type"] === "error")
                console.warn("nullgram: storyViewers", req["@type"], chatId, storyId, r.code, r.message)
            if (done)
                done(r)
        })
    }
    function storyBlockViewer(userId, hide, done) {
        send({ "@type": "setMessageSenderBlockList",
               sender_id: { "@type": "messageSenderUser", user_id: userId },
               block_list: hide ? { "@type": "blockListStories" } : null }, (r) => {
            if (done)
                done(r)
        })
    }
    function storyReport(chatId, id, optionId, text, done) {
        send({ "@type": "reportStory", story_poster_chat_id: chatId, story_id: id,
               option_id: optionId || "", text: text || "" }, done)
    }

    // ---- archive and chat list row actions -----------------------------------
    function loadArchive(limit, done) {
        send({ "@type": "loadChats", chat_list: { "@type": "chatListArchive" }, limit: limit || 50 }, done || check)
    }
    function archiveUnreadCount() {
        if (archiveUnreadKnown)
            return unreadArchive
        let n = 0
        for (let i = 0; i < archiveList.count; i++) {
            const r = archiveList.get(i)
            if (r.unread > 0 || r.markedUnread)
                n++
        }
        return n
    }
    function archiveChat(chatId, archived, done) {
        send({ "@type": "addChatToList", chat_id: chatId,
               chat_list: { "@type": archived ? "chatListArchive" : "chatListMain" } }, done || check)
    }
    function togglePinChat(chatId, listId, pinned, done) {
        send({ "@type": "toggleChatIsPinned", chat_list: chatListOf(listId || 0),
               chat_id: chatId, is_pinned: !!pinned }, done || check)
    }
    function toggleMuteChat(chatId, muted, done) {
        const c = chats[chatId]
        if (!c)
            return
        const n = Object.assign({}, c.notification_settings || {})
        n["@type"] = "chatNotificationSettings"
        n.use_default_mute_for = false
        n.mute_for = muted ? 2147483647 : 0
        send({ "@type": "setChatNotificationSettings", chat_id: chatId, notification_settings: n }, done || check)
    }
    function toggleUnreadChat(chatId, unread, done) {
        const c = chats[chatId]
        if (!c)
            return
        if (unread) {
            send({ "@type": "toggleChatIsMarkedAsUnread", chat_id: chatId, is_marked_as_unread: true }, done || check)
            return
        }
        if (c.unread_count > 0 && c.last_message) {
            send({ "@type": "viewMessages", chat_id: chatId, message_ids: [c.last_message.id],
                   source: { "@type": "messageSourceChatList" }, force_read: true }, (r) => {
                if (c.is_marked_as_unread)
                    send({ "@type": "toggleChatIsMarkedAsUnread", chat_id: chatId, is_marked_as_unread: false }, done || check)
                else if (done)
                    done(r)
            })
        } else {
            send({ "@type": "toggleChatIsMarkedAsUnread", chat_id: chatId, is_marked_as_unread: false }, done || check)
        }
    }
    function chatListsToAdd(chatId, done) {
        send({ "@type": "getChatListsToAddChat", chat_id: chatId }, done)
    }
    function addChatToFolder(chatId, folderId, done) {
        send({ "@type": "addChatToList", chat_id: chatId,
               chat_list: { "@type": "chatListFolder", chat_folder_id: folderId } }, done || check)
    }
    function clearChatHistory(chatId, revoke, remove, done) {
        send({ "@type": "deleteChatHistory", chat_id: chatId,
               remove_from_chat_list: !!remove, revoke: !!revoke }, done || check)
    }
    function leaveChat(chatId, done) {
        send({ "@type": "leaveChat", chat_id: chatId }, done || check)
    }
    function deleteChat(chatId, done) {
        send({ "@type": "deleteChat", chat_id: chatId }, done || check)
    }
    function setArchiveSettings(settings, done) {
        const s = Object.assign({ "@type": "archiveChatListSettings" }, archiveSettings, settings)
        send({ "@type": "setArchiveChatListSettings", settings: s }, (r) => {
            if (r["@type"] !== "error")
                store.archiveSettings = s
            if (done)
                done(r)
        })
    }

    // ---- Yangi suhbat va kontaktlar (0.9.5) ----------------------------------------
    // last-seen sort rank (higher = more recently active; online first)
    function userLastSeenRank(u, now) {
        if (!u || !u.status)
            return 0
        const s = u.status["@type"]
        if (s === "userStatusOnline")
            return u.status.expires > now ? now + 1000000 : (u.status.expires || 0)
        if (s === "userStatusOffline")
            return u.status.was_online || 0
        if (s === "userStatusRecently")
            return now - 86400 * 2
        if (s === "userStatusLastWeek")
            return now - 86400 * 7
        if (s === "userStatusLastMonth")
            return now - 86400 * 30
        return 0
    }

    // search contacts on TDLib (query "" returns contacts ordered by relevance): done([user])
    function searchContacts(q, limit, done) {
        send({ "@type": "searchContacts", query: q || "", limit: limit || 50 }, (r) => {
            const ids = r.user_ids || []
            let left = 0
            const finish = () => done(ids.map((id) => users[id]).filter((u) => u))
            for (const id of ids) {
                if (!users[id]) {
                    left++
                    send({ "@type": "getUser", user_id: id }, (u) => {
                        if (u["@type"] === "user")
                            users[u.id] = u
                        if (--left === 0)
                            finish()
                    })
                }
            }
            if (left === 0)
                finish()
        })
    }

    // global public chats by username or title: done([chatId])
    function searchPublic(q, done) {
        const clean = (q || "").trim().replace(/^@/, "")
        if (clean.length < 4) {
            done([])
            return
        }
        send({ "@type": "searchPublicChats", query: clean }, (r) => {
            const ids = r.chat_ids || []
            let left = 0
            const finish = () => done(ids.filter((id) => !!chats[id]))
            for (const id of ids) {
                if (!chats[id]) {
                    left++
                    send({ "@type": "getChat", chat_id: id }, (c) => {
                        if (c["@type"] === "chat") {
                            c.positions = c.positions || []
                            chats[c.id] = c
                        }
                        if (--left === 0)
                            finish()
                    })
                }
            }
            if (left === 0)
                finish()
        })
    }

    // create a new basic group (and set its photo if given): done(chatId, errorText, how many could not be added)
    function createGroup(title, userIds, photoPath, done) {
        send({ "@type": "createNewBasicGroupChat", user_ids: userIds || [], title: title, message_auto_delete_time: 0 }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: createNewBasicGroupChat", r.code, r.message)
                done(0, r.message || Tr.t("Bo'lmadi"))
                return
            }
            const cid = r["@type"] === "createdBasicGroupChat" ? r.chat_id : r["@type"] === "chat" ? r.id : 0
            if (!cid) {
                done(0, Tr.t("Bo'lmadi"))
                return
            }
            if (r["@type"] === "chat" && !chats[cid]) {
                r.positions = r.positions || []
                chats[cid] = r
            }
            // those whose privacy settings kept them out (createdBasicGroupChat.failed_to_add_members)
            const failed = r.failed_to_add_members && r.failed_to_add_members.failed_to_add_members
                ? r.failed_to_add_members.failed_to_add_members.length : 0
            const afterChat = () => {
                if (!photoPath) {
                    done(cid, "", failed)
                    return
                }
                send({ "@type": "setChatPhoto", chat_id: cid,
                       photo: { "@type": "inputChatPhotoStatic", photo: { "@type": "inputFileLocal", path: photoPath } } }, (pr) => {
                    if (pr["@type"] === "error")
                        console.warn("nullgram: setChatPhoto", pr.code, pr.message)
                    done(cid, "", failed)
                })
            }
            if (chats[cid])
                afterChat()
            else
                send({ "@type": "getChat", chat_id: cid }, (c) => {
                    if (c["@type"] === "chat") {
                        c.positions = c.positions || []
                        chats[c.id] = c
                    }
                    afterChat()
                })
        })
    }

    // create a new channel (supergroup with is_channel: true, plus photo if given): done(chatId, errorText)
    function createChannel(title, description, photoPath, done) {
        send({ "@type": "createNewSupergroupChat", title: title, is_forum: false, is_channel: true,
               description: description || "", location: null, message_auto_delete_time: 0, for_import: false }, (r) => {
            if (r["@type"] !== "chat") {
                console.warn("nullgram: createNewSupergroupChat", r.code, r.message)
                done(0, r.message || Tr.t("Bo'lmadi"))
                return
            }
            r.positions = r.positions || []
            chats[r.id] = r
            if (!photoPath) {
                done(r.id, "")
                return
            }
            send({ "@type": "setChatPhoto", chat_id: r.id,
                   photo: { "@type": "inputChatPhotoStatic", photo: { "@type": "inputFileLocal", path: photoPath } } }, (pr) => {
                if (pr["@type"] === "error")
                    console.warn("nullgram: setChatPhoto", pr.code, pr.message)
                done(r.id, "")
            })
        })
    }

    // import a contact by phone number: done(userId, errorText); userId === 0 with empty error = not on Telegram
    function importContact(phone, firstName, lastName, done) {
        send({ "@type": "importContacts",
               contacts: [{ "@type": "importedContact", phone_number: phone, first_name: firstName,
                            last_name: lastName || "", note: null }] }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: importContacts", r.code, r.message)
                done(0, r.message || Tr.t("Bo'lmadi"))
                return
            }
            const uid = r.user_ids && r.user_ids.length ? r.user_ids[0] : 0
            if (!uid) {
                done(0, "")
                return
            }
            send({ "@type": "getUser", user_id: uid }, (u) => {
                if (u["@type"] === "user") {
                    users[u.id] = u
                    seenSoon()
                }
                done(uid, "")
            })
        })
    }

    // --- hikoya joylash (agy/hikoya-joylash) ---
    property real storyPosting: 0           // 0..1 upload/posting progress (0 when idle; Claude's «Hikoyam» ring)
    property bool storyPostingActive: false // true while postStory is in flight
    property int _storyPostId: 0            // temporary story id returned by postStory
    property int _storyPostFileId: 0        // uploading file id for progress tracking
    property var _storyPostDone: null       // callback(ok, err, story)
    signal storyPosted(bool ok, string err)

    property Timer _storyPostReset: Timer {
        interval: 350
        onTriggered: {
            if (!store.storyPostingActive)
                store.storyPosting = 0
        }
    }

    property Connections _storyPostFile: Connections {
        target: store
        enabled: store.storyPostingActive && store._storyPostFileId > 0
        function onFileUpdated(f) {
            if (!f || f.id !== store._storyPostFileId)
                return
            const p = store.progress(f)
            if (p >= 0)
                store.storyPosting = Math.max(0.15, Math.min(0.95, p))
        }
    }

    property Connections _storyPostTd: Connections {
        target: td
        enabled: store.storyPostingActive
        function onReceived(text) {
            if (text.indexOf("updateStoryPost") < 0 && text.indexOf("updateStorySend") < 0
                    && text.indexOf("updateStoryDeleted") < 0)
                return
            const u = JSON.parse(text)
            const t = u["@type"]
            if (t === "updateStoryPostSucceeded" || t === "updateStorySendSucceeded") {
                const s = u.story
                if (s && s.poster_chat_id && s.id) {
                    if (u.old_story_id)
                        delete store._storyCache[s.poster_chat_id + ":" + u.old_story_id]
                    store._storyCache[s.poster_chat_id + ":" + s.id] = s
                    store.storyChanged(s.poster_chat_id, s.id)
                }
                if (!store._storyPostId || !u.old_story_id || u.old_story_id === store._storyPostId)
                    store._finishStoryPost(true, "", s || null)
            } else if (t === "updateStoryPostFailed" || t === "updateStorySendFailed") {
                if (!store._storyPostId || !u.story || u.story.id === store._storyPostId) {
                    const msg = (u.error && u.error.message) || Tr.t("Hikoya joylanmadi")
                    store._finishStoryPost(false, msg, null)
                }
            } else if (t === "updateStoryDeleted" && store._storyPostId && u.story_id === store._storyPostId) {
                store._finishStoryPost(false, Tr.t("Hikoya joylash bekor qilindi"), null)
            }
        }
    }

    function _storyRetryText(sec) {
        if (!sec || sec <= 0)
            return ""
        if (sec >= 86400)
            return Tr.n("%1 kun", Math.ceil(sec / 86400))
        if (sec >= 3600)
            return Tr.n("%1 soat", Math.ceil(sec / 3600))
        return Tr.n("%1 daqiqa", Math.max(1, Math.ceil(sec / 60)))
    }

    function _finishStoryPost(ok, err, s) {
        const cb = _storyPostDone
        _storyPostDone = null
        _storyPostId = 0
        _storyPostFileId = 0
        storyPostingActive = false
        storyPosting = ok ? 1 : 0
        if (ok)
            _storyPostReset.restart()
        storyPosted(ok, err || "")
        if (cb)
            cb(ok, err || "", s || null)
    }

    // check whether our account can post a story right now: done({ ok, type, text, retryAfter, count, premiumNeeded })
    function canPostStory(done) {
        const cid = store.me ? store.me.id : 0
        if (!cid) {
            if (done)
                done({ ok: false, type: "error", text: Tr.t("Hisob hali tayyor emas"), retryAfter: 0, count: 0, premiumNeeded: false })
            return
        }
        send({ "@type": "canPostStory", chat_id: cid }, (r) => {
            const t = r["@type"] || "error"
            let res = { ok: false, type: t, text: "", retryAfter: r.retry_after || 0, count: r.story_count || 0, premiumNeeded: false }
            if (t === "canPostStoryResultOk") {
                res.ok = true
            } else if (t === "canPostStoryResultPremiumNeeded") {
                res.premiumNeeded = true
                res.text = Tr.t("Hikoya joylash uchun Telegram Premium kerak")
            } else if (t === "canPostStoryResultWeeklyLimitExceeded") {
                const w = store._storyRetryText(r.retry_after)
                res.text = w ? Tr.f("Haftalik hikoya limiti tugadi. %1dan keyin urinib ko'ring", w)
                             : Tr.t("Haftalik hikoya limiti tugadi")
            } else if (t === "canPostStoryResultMonthlyLimitExceeded") {
                const w = store._storyRetryText(r.retry_after)
                res.text = w ? Tr.f("Oylik hikoya limiti tugadi. %1dan keyin urinib ko'ring", w)
                             : Tr.t("Oylik hikoya limiti tugadi")
            } else if (t === "canPostStoryResultActiveStoryLimitExceeded") {
                res.text = Tr.t("Faol hikoyalar soni limitga yetdi")
            } else if (t === "canPostStoryResultBoostNeeded") {
                res.text = Tr.t("Hikoya joylash uchun kanalga boost kerak")
            } else if (t === "canPostStoryResultLiveStoryIsActive") {
                res.text = Tr.t("Jonli hikoya faol paytda yangi hikoya joylab bo'lmaydi")
            } else {
                res.text = r.message || Tr.t("Hikoya joylab bo'lmaydi")
            }
            if (done)
                done(res)
        })
    }

    // post a photo or video story (TDLib 1.8.68: postStory + updateStoryPostSucceeded / updateStoryPostFailed)
    function postStory(file, isVideo, caption, privacy, period, done, opts) {
        const cid = store.me ? store.me.id : 0
        if (!cid || !file) {
            if (done)
                done(false, Tr.t("Fayl tanlanmagan"), null)
            return
        }
        if (storyPostingActive) {
            if (done)
                done(false, Tr.t("Hikoya yuklanmoqda…"), null)
            return
        }
        const o = opts || {}
        const local = { "@type": "inputFileLocal", path: file }
        let content
        if (isVideo) {
            const p = o.duration > 0 ? { duration: o.duration } : td.probe(file)
            const dur = p && p.duration > 0 ? p.duration : 1
            content = { "@type": "inputStoryContentVideo", video: local, added_sticker_file_ids: [],
                        duration: dur, cover_frame_timestamp: 0, is_animation: false }
        } else {
            content = { "@type": "inputStoryContentPhoto", photo: local, added_sticker_file_ids: [] }
        }
        let priv
        if (privacy && privacy["@type"]) {
            priv = privacy
        } else {
            const kind = privacy && privacy.kind ? privacy.kind : "everyone"
            if (kind === "contacts")
                priv = { "@type": "storyPrivacySettingsContacts", except_user_ids: [] }
            else if (kind === "closeFriends")
                priv = { "@type": "storyPrivacySettingsCloseFriends" }
            else if (kind === "selected")
                priv = { "@type": "storyPrivacySettingsSelectedUsers", user_ids: (privacy && privacy.userIds) || [] }
            else
                priv = { "@type": "storyPrivacySettingsEveryone", except_user_ids: [] }
        }
        const prem = !!(store.me && store.me.is_premium)
        const activePeriod = prem && period > 0 ? period : 86400
        const capText = (caption || "").trim()
        const cap = capText ? { "@type": "formattedText", text: capText, entities: [] } : null
        const saveToProfile = o.saveToProfile !== undefined ? !!o.saveToProfile : true
        const protectContent = !!o.protectContent

        _storyPostReset.stop()
        storyPostingActive = true
        storyPosting = 0.08
        _storyPostId = 0
        _storyPostFileId = 0
        _storyPostDone = done || null

        send({ "@type": "postStory", chat_id: cid, content: content, areas: null, caption: cap,
               privacy_settings: priv, album_ids: [], active_period: activePeriod,
               from_story_full_id: null, is_posted_to_chat_page: saveToProfile,
               protect_content: protectContent }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: postStory", r.code, r.message)
                store._finishStoryPost(false, r.message || Tr.t("Hikoya joylanmadi"), null)
                return
            }
            if (r["@type"] === "story") {
                store._storyPostId = r.id || 0
                if (r.poster_chat_id && r.id)
                    store._storyCache[r.poster_chat_id + ":" + r.id] = r
                const c = r.content
                const f = c && c["@type"] === "storyContentVideo"
                    ? (c.video && c.video.video)
                    : (c && c.photo && c.photo.sizes && c.photo.sizes.length
                       ? c.photo.sizes[c.photo.sizes.length - 1].photo : null)
                if (f && f.id)
                    store._storyPostFileId = f.id
                if (!r.is_being_posted)
                    store._finishStoryPost(true, "", r)
                else if (store.storyPosting < 0.15)
                    store.storyPosting = 0.15
            }
        })
    }

    // --- rejali yuborish (agy/rejali-yuborish) ---
    signal scheduledMessage(var msg)
    signal scheduledChanged(var chatId, var oldId, var msg)
    signal scheduledDeleted(var chatId, var ids)
    signal scheduledSent(var chatId, var oldId)

    function onScheduledNew(m) {
        if (chats[m.chat_id])
            change(m.chat_id, { has_scheduled_messages: true })
        scheduledMessage(m)
    }

    // "Send When Online" is allowed only in private chats with a regular user whose last-seen status is known
    function canScheduleOnline(c) {
        if (!c || c.type["@type"] !== "chatTypePrivate" || isSaved(c))
            return false
        const u = users[c.type.user_id]
        if (!u || !u.type || u.type["@type"] !== "userTypeRegular" || !u.status)
            return false
        const st = u.status["@type"]
        return st === "userStatusOnline" || st === "userStatusOffline"
    }

    function scheduleAt(unix) {
        return { "@type": "messageSchedulingStateSendAtDate", send_date: Math.floor(unix) }
    }

    function scheduleOnline() {
        return { "@type": "messageSchedulingStateSendWhenOnline" }
    }

    function scheduledMessages(chatId, done) {
        send({ "@type": "getChatScheduledMessages", chat_id: chatId }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: getChatScheduledMessages", r.code, r.message)
                if (done)
                    done([], true)
                return
            }
            const list = r.messages || []
            if (chats[chatId])
                change(chatId, { has_scheduled_messages: list.length > 0 })
            if (done)
                done(list, false)
        })
    }

    function sendScheduledNow(chatId, messageId, done) {
        send({ "@type": "editMessageSchedulingState", chat_id: chatId, message_id: messageId,
               scheduling_state: null }, done || check)
    }

    function rescheduleMessage(chatId, messageId, schedulingState, done) {
        send({ "@type": "editMessageSchedulingState", chat_id: chatId, message_id: messageId,
               scheduling_state: schedulingState }, done || check)
    }

    function deleteScheduledMessages(chatId, ids, done) {
        send({ "@type": "deleteMessages", chat_id: chatId, message_ids: ids, revoke: true }, done || check)
    }

    // --- havola ko'rinishi (agy/havola-korinish) ---
    function linkPreviewOptions(opts) {
        if (!opts)
            return null
        return {
            "@type": "linkPreviewOptions",
            is_disabled: !!opts.is_disabled,
            url: opts.url || "",
            force_small_media: !!opts.force_small_media,
            force_large_media: !!opts.force_large_media,
            show_above_text: !!opts.show_above_text
        }
    }

    function getLinkPreview(text, marks, opts, done) {
        send({
            "@type": "getLinkPreview",
            text: { "@type": "formattedText", text: text || "", entities: marks || [] },
            link_preview_options: linkPreviewOptions(opts)
        }, (r) => {
            if (done)
                done(r && r["@type"] === "linkPreview" ? r : null, r)
        })
    }

    function _lpPhotoPick(photo, wantW) {
        if (!photo || !photo.sizes || !photo.sizes.length)
            return null
        const sizes = photo.sizes
        let best = sizes[sizes.length - 1]
        for (const z of sizes) {
            if (z.width >= wantW) {
                best = z
                break
            }
        }
        return {
            file: best.photo || null,
            w: best.width || 1,
            h: best.height || 1,
            mini: photo.minithumbnail ? (photo.minithumbnail.data || "") : ""
        }
    }

    function _lpStillThumb(th) {
        if (!th || !th.format)
            return null
        const f = th.format["@type"]
        if (f !== "thumbnailFormatJpeg" && f !== "thumbnailFormatWebp" && f !== "thumbnailFormatPng" && f !== "thumbnailFormatGif")
            return null
        return { file: th.file || null, w: th.width || 1, h: th.height || 1 }
    }

    function linkPreviewInfo(lp) {
        if (!lp || lp["@type"] !== "linkPreview")
            return null
        const url = lp.url || ""
        const displayUrl = lp.display_url || url
        let site = lp.site_name || ""
        const title = lp.title || ""
        const desc = lp.description ? (lp.description.text || "") : ""
        if (!site && !title && displayUrl) {
            const m = displayUrl.match(/^(?:https?:\/\/)?(?:www\.)?([^\/?#]+)/i)
            site = m ? m[1] : displayUrl
        }
        const showLarge = !!lp.show_large_media
        const hasLarge = !!lp.has_large_media
        const mediaAbove = !!lp.show_media_above_description
        const aboveText = !!lp.show_above_text
        const wantW = showLarge ? 640 : 240

        let file = null, mini = "", w = 1, h = 1, isVideo = false, dur = 0
        const tp = lp.type || null
        const tt = tp ? tp["@type"] : ""
        const usePhoto = (p) => {
            const k = _lpPhotoPick(p, wantW)
            if (k) {
                file = k.file
                mini = k.mini
                w = k.w
                h = k.h
            }
        }
        const useThumb = (th, mth, dw, dh) => {
            const k = _lpStillThumb(th)
            if (k) {
                file = k.file
                w = k.w
                h = k.h
            } else if (dw && dh) {
                w = dw
                h = dh
            }
            if (mth && mth.data)
                mini = mth.data
        }

        if (tt === "linkPreviewTypeArticle" || tt === "linkPreviewTypePhoto" || tt === "linkPreviewTypeApp" || tt === "linkPreviewTypeWebApp") {
            usePhoto(tp.photo)
        } else if (tt === "linkPreviewTypeVideo") {
            isVideo = true
            const v = tp.video
            dur = v ? (v.duration || 0) : 0
            if (tp.cover)
                usePhoto(tp.cover)
            else if (v)
                useThumb(v.thumbnail, v.minithumbnail, v.width, v.height)
        } else if (tt === "linkPreviewTypeEmbeddedVideoPlayer" || tt === "linkPreviewTypeEmbeddedAnimationPlayer") {
            isVideo = true
            dur = tp.duration || 0
            if (tp.thumbnail)
                usePhoto(tp.thumbnail)
            if (tp.width && tp.height && w === 1 && h === 1) {
                w = tp.width
                h = tp.height
            }
        } else if (tt === "linkPreviewTypeExternalVideo") {
            isVideo = true
            dur = tp.duration || 0
            if (tp.width && tp.height) {
                w = tp.width
                h = tp.height
            }
        } else if (tt === "linkPreviewTypeAnimation" && tp.animation) {
            isVideo = true
            dur = tp.animation.duration || 0
            useThumb(tp.animation.thumbnail, tp.animation.minithumbnail, tp.animation.width, tp.animation.height)
        } else if (tt === "linkPreviewTypeVideoNote" && tp.video_note) {
            isVideo = true
            dur = tp.video_note.duration || 0
            useThumb(tp.video_note.thumbnail, tp.video_note.minithumbnail, tp.video_note.length, tp.video_note.length)
        } else if (tt === "linkPreviewTypeAlbum" && tp.media && tp.media.length) {
            const first = tp.media[0]
            if (first["@type"] === "linkPreviewAlbumMediaVideo") {
                isVideo = true
                if (first.video) {
                    dur = first.video.duration || 0
                    useThumb(first.video.thumbnail, first.video.minithumbnail, first.video.width, first.video.height)
                }
            } else if (first.photo) {
                usePhoto(first.photo)
            }
        } else if ((tt === "linkPreviewTypeChat" || tt === "linkPreviewTypeUser") && tp.photo) {
            usePhoto(tp.photo)
        } else if (tt === "linkPreviewTypeDocument" && tp.document) {
            useThumb(tp.document.thumbnail, tp.document.minithumbnail, 1, 1)
        } else if (tt === "linkPreviewTypeAudio" && tp.audio) {
            useThumb(tp.audio.album_cover_thumbnail, tp.audio.album_cover_minithumbnail, 1, 1)
        } else if (tt === "linkPreviewTypeSticker" && tp.sticker) {
            useThumb(tp.sticker.thumbnail, null, tp.sticker.width, tp.sticker.height)
        } else if (tp && tp.photo) {
            usePhoto(tp.photo)
        }

        return {
            url: url,
            displayUrl: displayUrl,
            site: site,
            title: title,
            desc: desc,
            showLarge: showLarge,
            hasLarge: hasLarge,
            mediaAbove: mediaAbove,
            aboveText: aboveText,
            isVideo: isVideo,
            dur: dur,
            file: file,
            mini: mini,
            w: w,
            h: h,
            hasMedia: !!(file || mini)
        }
    }


    // --- agy/qidiruv-tablar ---
    // global message search with an optional TDLib SearchMessagesFilter and string offset pagination:
    // done(messages, nextOffset, totalCount, err)
    function searchMessagesFiltered(q, filterType, offset, limit, done) {
        const req = {
            "@type": "searchMessages",
            chat_list: null,
            query: q || "",
            offset: offset || "",
            limit: limit || 30,
            filter: filterType ? { "@type": filterType } : null,
            chat_type_filter: null,
            min_date: 0,
            max_date: 0
        }
        send(req, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: searchMessages", filterType || "", r.code, r.message)
                if (done)
                    done([], "", 0, r.message || Tr.t("Bo'lmadi"))
                return
            }
            if (done)
                done(r.messages || [], r.next_offset || "", r.total_count || 0, "")
        })
    }

    // --- agy/eslatma-tarjima ---
    function searchUnreadMentions(chatId, fromId, done) {
        send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: null, query: "", sender_id: null,
               from_message_id: fromId || 0, offset: 0, limit: 20,
               filter: { "@type": "searchMessagesFilterUnreadMention" } }, (r) => {
            if (!done)
                return
            if (r["@type"] === "foundChatMessages")
                done(r.messages || [], "")
            else
                done([], r.message || "")
        })
    }

    function searchUnreadReactions(chatId, fromId, done) {
        send({ "@type": "searchChatMessages", chat_id: chatId, topic_id: null, query: "", sender_id: null,
               from_message_id: fromId || 0, offset: 0, limit: 20,
               filter: { "@type": "searchMessagesFilterUnreadReaction" } }, (r) => {
            if (!done)
                return
            if (r["@type"] === "foundChatMessages")
                done(r.messages || [], "")
            else
                done([], r.message || "")
        })
    }

    function readAllMentions(chatId, done) {
        send({ "@type": "readAllChatMentions", chat_id: chatId }, done || check)
    }

    function readAllReactions(chatId, done) {
        send({ "@type": "readAllChatReactions", chat_id: chatId }, done || check)
    }

    function viewMessage(chatId, msgId) {
        if (!chatId || !msgId)
            return
        send({ "@type": "viewMessages", chat_id: chatId, message_ids: [msgId], force_read: true })
    }

    function translateErrorText(r) {
        const msg = r && r.message ? String(r.message) : ""
        const up = msg.toUpperCase()
        if (up.indexOf("PREMIUM") >= 0)
            return Tr.t("Bu tarjima uchun Telegram Premium kerak")
        if ((r && r.code === 429) || up.indexOf("FLOOD") >= 0 || up.indexOf("TOO_MANY") >= 0)
            return Tr.t("Juda ko'p so'rov. Birozdan keyin urinib ko'ring")
        if (up.indexOf("LANGUAGE") >= 0 || up.indexOf("UNSUPPORTED") >= 0 || up.indexOf("TRANSLATION_DISABLED") >= 0)
            return Tr.t("Bu tilga tarjima hozircha mavjud emas")
        if (up.indexOf("EMPTY") >= 0 || up.indexOf("MESSAGE_ID_INVALID") >= 0)
            return Tr.t("Bu xabarda tarjima qilinadigan matn yo'q")
        return msg ? Tr.f("Tarjima qilib bo'lmadi: %1", msg) : Tr.t("Tarjima qilib bo'lmadi")
    }

    function translateMessage(chatId, msgId, langCode, done) {
        const to = langCode || Tr.lang || "uz"
        send({ "@type": "translateMessageText", chat_id: chatId, message_id: msgId,
               to_language_code: to, tone: "" }, (r) => {
            if (!done)
                return
            if (r["@type"] === "formattedText") {
                const raw = r.text || ""
                const txt = r.entities && r.entities.length
                    ? raw
                    : raw.replace(/<\/?(b|i|u|s|code|pre)>/g, "").replace(/\*\*|__/g, "")
                done(true, txt, r, "")
                return
            }
            done(false, "", null, store.translateErrorText(r))
        })
    }

    // --- agy/avtotoldirish ---
    // search group/supergroup members for @ mention autocomplete (TDLib 1.8.68: searchChatMembers + chatMembersFilterMention)
    function searchChatMembers(chatId, query, topicId, limit, done) {
        if (!chatId) {
            if (done)
                done([])
            return
        }
        send({ "@type": "searchChatMembers", chat_id: chatId, query: query || "", limit: limit || 20,
               filter: { "@type": "chatMembersFilterMention", topic_id: topicId || null } }, (r) => {
            if (!done)
                return
            if (!r || r["@type"] !== "chatMembers") {
                done([])
                return
            }
            const uids = []
            for (const m of (r.members || [])) {
                const s = m && m.member_id
                if (s && s["@type"] === "messageSenderUser" && s.user_id && uids.indexOf(s.user_id) < 0)
                    uids.push(s.user_id)
            }
            let left = 0
            const finish = () => {
                const list = []
                for (const id of uids) {
                    const u = users[id]
                    if (u && (!u.type || u.type["@type"] !== "userTypeDeleted"))
                        list.push(u)
                }
                done(list)
            }
            for (const id of uids) {
                if (!users[id]) {
                    left++
                    send({ "@type": "getUser", user_id: id }, (u) => {
                        if (u && u["@type"] === "user")
                            users[u.id] = u
                        if (--left === 0)
                            finish()
                    })
                }
            }
            if (left === 0)
                finish()
        })
    }

    // search emoji suggestions by keyword (TDLib 1.8.68: searchEmojis -> emojiKeywords / emojis)
    function searchEmojis(query, done) {
        const q = (query || "").trim()
        if (!q) {
            if (done)
                done([])
            return
        }
        const prefLang = (Prefs.lang || Tr.lang || "en").toLowerCase()
        const langs = prefLang && prefLang !== "en" ? [prefLang, "en"] : ["en"]
        send({ "@type": "searchEmojis", text: q, input_language_codes: langs }, (r) => {
            if (!done)
                return
            const out = []
            if (r && r["@type"] === "emojiKeywords" && r.emoji_keywords) {
                for (const k of r.emoji_keywords) {
                    if (k && k.emoji && out.indexOf(k.emoji) < 0)
                        out.push(k.emoji)
                }
            } else if (r && r["@type"] === "emojis" && r.emojis) {
                for (const e of r.emojis) {
                    if (e && out.indexOf(e) < 0)
                        out.push(e)
                }
            }
            done(out)
        })
    }

    // per-chat local hashtag history (up to 50 most recent tags, persisted in Prefs.recentHashtags)
    function _hashtagMap() {
        try {
            const o = Prefs.recentHashtags ? JSON.parse(Prefs.recentHashtags) : {}
            return o && typeof o === "object" && !Array.isArray(o) ? o : {}
        } catch (e) {
            return {}
        }
    }

    function chatHashtags(chatId) {
        if (!chatId)
            return []
        const arr = _hashtagMap()[String(chatId)]
        return Array.isArray(arr) ? arr.slice(0, 50) : []
    }

    function recordHashtags(chatId, text) {
        if (!chatId || !text || text.indexOf("#") < 0)
            return
        const re = /(?:^|[\s(\["'«])#([A-Za-z0-9_\u00C0-\u024F\u0400-\u052F\u1E00-\u1EFF]+)/g
        const found = []
        let m
        while ((m = re.exec(text)) !== null) {
            if (m[1])
                found.push(m[1])
        }
        if (!found.length)
            return
        const map = _hashtagMap()
        const key = String(chatId)
        const cur = Array.isArray(map[key]) ? map[key].slice() : []
        for (const tag of found) {
            const low = tag.toLowerCase()
            for (let i = cur.length - 1; i >= 0; i--) {
                if (String(cur[i]).toLowerCase() === low)
                    cur.splice(i, 1)
            }
            cur.unshift(tag)
        }
        map[key] = cur.slice(0, 50)
        Prefs.recentHashtags = JSON.stringify(map)
    }

    function filterHashtags(chatId, query) {
        const list = chatHashtags(chatId)
        const q = fold((query || "").trim())
        if (!q)
            return list
        const pref = [], sub = []
        for (const tag of list) {
            const f = fold(tag)
            if (f.indexOf(q) === 0)
                pref.push(tag)
            else if (f.indexOf(q) > 0)
                sub.push(tag)
        }
        return pref.concat(sub)
    }

    // --- agy/bot-tugmalar ---
    function botUsernameOf(uid) {
        const u = uid ? users[uid] : null
        const un = u && u.usernames
        if (!un)
            return ""
        if (un.active_usernames && un.active_usernames.length)
            return un.active_usernames[0]
        return un.editable_username || ""
    }

    function inlineKeyboardRows(rm) {
        if (!rm || rm["@type"] !== "replyMarkupInlineKeyboard" || !rm.rows || !rm.rows.length)
            return null
        const out = []
        for (const row of rm.rows) {
            if (!row || !row.length)
                continue
            const btns = []
            for (const b of row) {
                if (!b)
                    continue
                const tp = b.type || {}
                const tt = tp["@type"] || ""
                let kind = "unsupported"
                const item = { text: b.text || "", kind: "unsupported", url: "", data: "", copyText: "", query: "", inCurrent: false, userId: 0 }
                if (tt === "inlineKeyboardButtonTypeUrl") {
                    kind = "url"
                    item.url = tp.url || ""
                } else if (tt === "inlineKeyboardButtonTypeCallback") {
                    kind = "callback"
                    item.data = tp.data || ""
                } else if (tt === "inlineKeyboardButtonTypeCopyText") {
                    kind = "copy"
                    item.copyText = tp.text || ""
                } else if (tt === "inlineKeyboardButtonTypeSwitchInline") {
                    kind = "switch_inline"
                    item.query = tp.query || ""
                    item.inCurrent = !!(tp.target_chat && tp.target_chat["@type"] === "targetChatCurrent")
                } else if (tt === "inlineKeyboardButtonTypeUser") {
                    kind = "user"
                    item.userId = tp.user_id || 0
                } else if (tt === "inlineKeyboardButtonTypeLoginUrl") {
                    kind = "login_url"
                } else if (tt === "inlineKeyboardButtonTypeBuy") {
                    kind = "buy"
                } else if (tt === "inlineKeyboardButtonTypeWebApp") {
                    kind = "web_app"
                } else if (tt === "inlineKeyboardButtonTypeCallbackGame") {
                    kind = "game"
                }
                item.kind = kind
                btns.push(item)
            }
            if (btns.length)
                out.push(btns)
        }
        return out.length ? out : null
    }

    function replyKeyboardInfo(rm, msgId) {
        if (!rm || rm["@type"] !== "replyMarkupShowKeyboard" || !rm.rows || !rm.rows.length)
            return null
        const rows = []
        for (const row of rm.rows) {
            if (!row || !row.length)
                continue
            const btns = []
            for (const b of row) {
                if (!b)
                    continue
                const tt = b.type ? (b.type["@type"] || "") : ""
                btns.push({ text: b.text || "", kind: tt === "keyboardButtonTypeText" || !tt ? "text" : "unsupported" })
            }
            if (btns.length)
                rows.push(btns)
        }
        if (!rows.length)
            return null
        return {
            msgId: msgId || 0,
            rows: rows,
            oneTime: !!rm.one_time,
            resize: !!rm.resize_keyboard,
            persistent: !!rm.is_persistent,
            personal: !!rm.is_personal,
            placeholder: rm.input_field_placeholder || ""
        }
    }

    function botCallback(chatId, messageId, payload, done) {
        send({
            "@type": "getCallbackQueryAnswer",
            chat_id: chatId,
            message_id: messageId,
            payload: payload
        }, (r) => {
            if (done)
                done(r)
        })
    }

    function startBot(botUserId, chatId, parameter, done) {
        send({
            "@type": "sendBotStartMessage",
            bot_user_id: botUserId,
            chat_id: chatId,
            parameter: parameter || ""
        }, done || check)
    }

    function deleteReplyMarkup(chatId, messageId, done) {
        send({
            "@type": "deleteChatReplyMarkup",
            chat_id: chatId,
            message_id: messageId
        }, done || check)
    }

    function loadBotCommands(chatId, done) {
        const c = chats[chatId]
        if (!c || !done) {
            if (done)
                done([], "")
            return
        }
        const t = c.type["@type"]
        if (t === "chatTypePrivate") {
            const uid = c.type.user_id
            const u = users[uid]
            if (!u || u.type["@type"] !== "userTypeBot") {
                done([], "")
                return
            }
            send({ "@type": "getUserFullInfo", user_id: uid }, (r) => {
                if (r["@type"] !== "userFullInfo" || !r.bot_info) {
                    done([], "")
                    return
                }
                const bi = r.bot_info
                const uname = store.botUsernameOf(uid)
                const cmds = (bi.commands || []).map((cmd) => ({
                    command: (cmd.command || "").replace(/^\/+/, ""),
                    description: cmd.description || "",
                    botUserId: uid,
                    botUsername: uname
                })).filter((x) => x.command !== "")
                done(cmds, bi.description || bi.short_description || "")
            })
            return
        }
        if (t === "chatTypeBasicGroup" || (t === "chatTypeSupergroup" && !c.type.is_channel)) {
            const req = t === "chatTypeBasicGroup"
                ? { "@type": "getBasicGroupFullInfo", basic_group_id: c.type.basic_group_id }
                : { "@type": "getSupergroupFullInfo", supergroup_id: c.type.supergroup_id }
            send(req, (r) => {
                const groups = (r && r.bot_commands) || []
                const cmds = []
                for (const bc of groups) {
                    const uname = store.botUsernameOf(bc.bot_user_id)
                    for (const cmd of (bc.commands || [])) {
                        const name = (cmd.command || "").replace(/^\/+/, "")
                        if (name)
                            cmds.push({
                                command: name,
                                description: cmd.description || "",
                                botUserId: bc.bot_user_id || 0,
                                botUsername: uname
                            })
                    }
                }
                done(cmds, "")
            })
            return
        }
        done([], "")
    }

    // --- agy/kartochkalar ---
    readonly property var _cardTypes: ({
        messageContact: "contact",
        messageCall: "call",
        messageStory: "story",
        messageGift: "gift",
        messageUpgradedGift: "gift",
        messageDice: "dice",
        messageGame: "game",
        messageChecklist: "checklist",
        messagePaidMedia: "paid",
        messageGiveaway: "giveaway",
        messageGiveawayWinners: "giveawayWinners",
        messageInvoice: "invoice"
    })

    function isCardType(t) {
        return !!_cardTypes[t]
    }

    function cardPreview(content) {
        if (!content)
            return ""
        const t = content["@type"]
        if (t === "messageContact" && content.contact) {
            const c = content.contact
            const name = ((c.first_name || "") + " " + (c.last_name || "")).trim()
            return name ? Tr.t("Kontakt") + ": " + name : Tr.t("Kontakt")
        }
        if (t === "messageCall")
            return Tr.t(content.is_video ? "Video qo'ng'iroq" : "Qo'ng'iroq")
        if (t === "messageStory")
            return Tr.t("Hikoya")
        if (t === "messageDice")
            return (content.emoji || "🎲") + (content.value > 0 ? " " + content.value : "")
        if (t === "messageGame" && content.game)
            return content.game.title ? "🎮 " + content.game.title : Tr.t("O'yin")
        if (t === "messageChecklist" && content.list) {
            const title = content.list.title && content.list.title.text ? content.list.title.text : ""
            return title ? "☑ " + title : Tr.t("Ro'yxat")
        }
        if (t === "messagePaidMedia")
            return Tr.t("Pullik media") + (content.star_count > 0 ? " · ⭐ " + count(content.star_count) : "")
        if (t === "messageInvoice" && content.product_info && content.product_info.title)
            return Tr.t("To'lov") + ": " + content.product_info.title
        if (t === "messageUpgradedGift" && content.gift && content.gift.title)
            return Tr.t("Hadya") + ": " + content.gift.title
        return ""
    }

    function formatPhone(raw) {
        const digits = String(raw || "").replace(/[^0-9]/g, "")
        if (!digits)
            return String(raw || "").trim()
        const m = /^998(\d{2})(\d{3})(\d{2})(\d{2})$/.exec(digits)
        return m ? "+998 " + m.slice(1).join(" ") : "+" + digits
    }

    function formatCallDuration(secs) {
        const d = Math.max(0, Math.floor(secs || 0))
        if (d <= 0)
            return ""
        if (d >= 3600)
            return Math.floor(d / 3600) + ":" + String(Math.floor(d / 60) % 60).padStart(2, "0") + ":" + String(d % 60).padStart(2, "0")
        return Math.floor(d / 60) + ":" + String(d % 60).padStart(2, "0")
    }

    function _photoBestFile(photo) {
        if (!photo || !photo.sizes || !photo.sizes.length)
            return null
        let best = photo.sizes[photo.sizes.length - 1]
        for (const z of photo.sizes) {
            if (z.width >= 320) {
                best = z
                break
            }
        }
        return best ? best.photo : null
    }

    function _stickerPicFile(st) {
        if (!st)
            return null
        const fmt = st.format ? st.format["@type"] : ""
        if (fmt === "stickerFormatTgs" || fmt === "stickerFormatWebp")
            return st.sticker || null
        return st.thumbnail ? st.thumbnail.file : null
    }

    function cardFile(c) {
        if (!c)
            return null
        const t = c["@type"]
        if (t === "messageContact" && c.contact && c.contact.user_id > 0) {
            const u = users[c.contact.user_id]
            return u && u.profile_photo ? u.profile_photo.small : null
        }
        if (t === "messageGift" && c.gift)
            return _stickerPicFile(c.gift.sticker)
        if (t === "messageUpgradedGift" && c.gift && c.gift.model)
            return _stickerPicFile(c.gift.model.sticker)
        if (t === "messageGame" && c.game)
            return _photoBestFile(c.game.photo)
        if (t === "messageInvoice" && c.product_info)
            return _photoBestFile(c.product_info.photo)
        if (t === "messageGiveaway" && c.sticker)
            return _stickerPicFile(c.sticker)
        if (t === "messageDice" && c.final_state && c.final_state["@type"] === "diceStickersRegular")
            return _stickerPicFile(c.final_state.sticker)
        return null
    }

    function cardData(m) {
        if (!m || !m.content)
            return null
        const c = m.content, t = c["@type"]
        if (!isCardType(t))
            return null
        const out = !!m.is_outgoing
        if (t === "messageContact") {
            const ct = c.contact || {}
            const uid = ct.user_id || 0
            const u = uid > 0 ? users[uid] : null
            const first = ct.first_name || (u ? u.first_name : "") || ""
            const last = ct.last_name || (u ? u.last_name : "") || ""
            const name = (first + " " + last).trim() || formatPhone(ct.phone_number)
            const tint = tints[Math.abs(uid || name.length) % tints.length]
            return {
                kind: "contact",
                first: first,
                last: last,
                name: name,
                phone: formatPhone(ct.phone_number),
                rawPhone: ct.phone_number || "",
                userId: uid,
                isContact: !!(u && u.is_contact),
                letters: letters(name),
                tint: tint
            }
        }
        if (t === "messageCall") {
            const why = c.discard_reason ? c.discard_reason["@type"] : ""
            const missed = !out && (why === "callDiscardReasonMissed" || why === "callDiscardReasonDeclined")
            const cancelled = out && (why === "callDiscardReasonMissed" || why === "callDiscardReasonDeclined")
            return {
                kind: "call",
                video: !!c.is_video,
                out: out,
                missed: missed,
                cancelled: cancelled,
                declined: why === "callDiscardReasonDeclined",
                duration: c.duration || 0,
                durText: formatCallDuration(c.duration || 0)
            }
        }
        if (t === "messageStory") {
            const cid = c.story_poster_chat_id || 0
            const sid = c.story_id || 0
            const ch = cid ? chats[cid] : null
            const cached = _storyCache[cid + ":" + sid] || null
            let mini = "", isVideo = false
            if (cached && cached.content) {
                if (cached.content["@type"] === "storyContentPhoto" && cached.content.photo && cached.content.photo.minithumbnail)
                    mini = cached.content.photo.minithumbnail.data || ""
                else if (cached.content["@type"] === "storyContentVideo" && cached.content.video) {
                    isVideo = true
                    if (cached.content.video.minithumbnail)
                        mini = cached.content.video.minithumbnail.data || ""
                }
            }
            return {
                kind: "story",
                chatId: cid,
                storyId: sid,
                viaMention: !!c.via_mention,
                author: ch ? ch.title : "",
                mini: mini,
                isVideo: isVideo,
                expired: false
            }
        }
        if (t === "messageGift" || t === "messageUpgradedGift") {
            const up = t === "messageUpgradedGift"
            const g = c.gift || {}
            const st = up ? (g.model ? g.model.sticker : null) : g.sticker
            const isTgs = !!(st && st.format && st.format["@type"] === "stickerFormatTgs")
            const bd = up && g.backdrop && g.backdrop.colors ? g.backdrop.colors : null
            const hex = (v) => "#" + ((v >>> 0) & 0xffffff).toString(16).padStart(6, "0")
            return {
                kind: "gift",
                upgraded: up,
                title: up && g.title ? g.title + (g.number ? " #" + g.number : "") : Tr.t("Hadya"),
                stars: up ? 0 : (g.star_count || 0),
                text: c.text && c.text.text ? c.text.text : "",
                tgs: isTgs,
                bg1: bd ? hex(bd.center_color) : "",
                bg2: bd ? hex(bd.edge_color) : "",
                converted: !!c.was_converted,
                wasUpgraded: !!c.was_upgraded
            }
        }
        if (t === "messageDice") {
            const st = c.final_state && c.final_state["@type"] === "diceStickersRegular" ? c.final_state.sticker : null
            const isTgs = !!(st && st.format && st.format["@type"] === "stickerFormatTgs")
            // 🎰: five animations over each other (Telegram's SlotMachineAnimationNode): the background, the
            // three reels, the lever; each a TGS whose end shows this value
            const sm = c.final_state && c.final_state["@type"] === "diceStickersSlotMachine" ? c.final_state : null
            const part = (x) => x && x.sticker ? x.sticker : null
            return {
                kind: "dice",
                emoji: c.emoji || "🎲",
                value: c.value || 0,
                tgs: isTgs,
                // played from the start only when it has just come (Telegram-iOS plays a dice once, as it
                // arrives); an old one shows its last frame, the outcome
                fresh: (m.date || 0) > Date.now() / 1000 - 30,
                slot: sm ? [part(sm.background), part(sm.left_reel), part(sm.center_reel), part(sm.right_reel),
                            part(sm.lever)].filter((f) => f) : null
            }
        }
        if (t === "messageGame") {
            const g = c.game || {}
            const ph = g.photo
            const sz = ph && ph.sizes && ph.sizes.length ? ph.sizes[ph.sizes.length - 1] : null
            return {
                kind: "game",
                title: g.title || Tr.t("O'yin"),
                desc: g.description || "",
                scoreText: g.text && g.text.text ? g.text.text : "",
                hasPhoto: !!(ph && ph.sizes && ph.sizes.length),
                mini: ph && ph.minithumbnail ? (ph.minithumbnail.data || "") : "",
                w: sz && sz.width > 0 ? sz.width : 16,
                h: sz && sz.height > 0 ? sz.height : 9
            }
        }
        if (t === "messageChecklist") {
            const lst = c.list || {}
            const tasks = (lst.tasks || []).map((tk) => ({
                id: tk.id,
                text: tk.text && tk.text.text ? tk.text.text : "",
                done: !!(tk.completion_date > 0 || tk.completed_by),
                by: tk.completed_by ? (senderName(tk.completed_by, true) || "") : ""
            }))
            return {
                kind: "checklist",
                title: lst.title && lst.title.text ? lst.title.text : Tr.t("Vazifalar ro'yxati"),
                tasks: tasks,
                canMark: out || !!lst.others_can_mark_tasks_as_done
            }
        }
        if (t === "messagePaidMedia") {
            const items = c.media || []
            let mini = "", w = 16, h = 10, videoCount = 0, photoCount = 0
            for (const it of items) {
                const itype = it && it["@type"]
                if (itype === "paidMediaPreview") {
                    if (!mini && it.minithumbnail)
                        mini = it.minithumbnail.data || ""
                    if (it.width > 0 && it.height > 0 && w === 16 && h === 10) {
                        w = it.width; h = it.height
                    }
                    if (it.duration > 0) videoCount++
                    else photoCount++
                } else if (itype === "paidMediaPhoto" && it.photo) {
                    photoCount++
                    if (!mini && it.photo.minithumbnail)
                        mini = it.photo.minithumbnail.data || ""
                } else if (itype === "paidMediaVideo" && it.video) {
                    videoCount++
                    if (!mini && it.video.minithumbnail)
                        mini = it.video.minithumbnail.data || ""
                }
            }
            return {
                kind: "paid",
                stars: c.star_count || 0,
                mediaCount: items.length,
                photoCount: photoCount,
                videoCount: videoCount,
                mini: mini,
                w: w,
                h: h
            }
        }
        if (t === "messageGiveaway") {
            const p = c.parameters || {}
            const pr = c.prize || {}
            const ch = p.boosted_chat_id ? chats[p.boosted_chat_id] : null
            const prizeText = pr["@type"] === "giveawayPrizeStars"
                ? Tr.f("⭐ %1 yulduz", count(pr.star_count || 0))
                : Tr.f("%1 oylik Telegram Premium", pr.month_count || 1)
            const st = c.sticker
            return {
                kind: "giveaway",
                winners: c.winner_count || 1,
                prize: prizeText,
                extra: p.prize_description || "",
                channel: ch ? ch.title : "",
                extraChats: p.additional_chat_ids ? p.additional_chat_ids.length : 0,
                until: p.winners_selection_date || 0,
                onlyNew: !!p.only_new_members,
                tgs: !!(st && st.format && st.format["@type"] === "stickerFormatTgs")
            }
        }
        if (t === "messageGiveawayWinners") {
            const pr = c.prize || {}
            const ch = c.boosted_chat_id ? chats[c.boosted_chat_id] : null
            const prizeText = pr["@type"] === "giveawayPrizeStars"
                ? Tr.f("⭐ %1 yulduz", count(pr.star_count || 0))
                : Tr.f("%1 oylik Telegram Premium", pr.month_count || 1)
            const wids = c.winner_user_ids || []
            const names = []
            for (let k = 0; k < Math.min(5, wids.length); k++) {
                const n = senderName({ "@type": "messageSenderUser", user_id: wids[k] }, false)
                names.push(n || ("#" + wids[k]))
            }
            return {
                kind: "giveawayWinners",
                winners: c.winner_count || wids.length,
                prize: prizeText,
                extra: c.prize_description || "",
                channel: ch ? ch.title : "",
                names: names,
                moreNames: Math.max(0, wids.length - names.length),
                date: c.actual_winners_selection_date || 0,
                refunded: !!c.was_refunded,
                unclaimed: c.unclaimed_prize_count || 0
            }
        }
        if (t === "messageInvoice") {
            const pi = c.product_info || {}
            const ph = pi.photo
            const sz = ph && ph.sizes && ph.sizes.length ? ph.sizes[ph.sizes.length - 1] : null
            return {
                kind: "invoice",
                title: pi.title || Tr.t("To'lov"),
                desc: pi.description && pi.description.text ? pi.description.text : "",
                currency: c.currency || "",
                amount: c.total_amount || 0,
                isTest: !!c.is_test,
                paid: !!(c.receipt_message_id && c.receipt_message_id > 0),
                hasPhoto: !!(ph && ph.sizes && ph.sizes.length),
                mini: ph && ph.minithumbnail ? (ph.minithumbnail.data || "") : "",
                w: sz && sz.width > 0 ? sz.width : 16,
                h: sz && sz.height > 0 ? sz.height : 9
            }
        }
        return null
    }

    function cardGiftForSheet(m) {
        if (!m || !m.content)
            return null
        const c = m.content, t = c["@type"]
        if (t !== "messageGift" && t !== "messageUpgradedGift")
            return null
        const up = t === "messageUpgradedGift"
        return {
            "@type": "receivedGift",
            received_gift_id: "",
            sender_id: c.sender_id || m.sender_id || null,
            text: c.text || null,
            is_private: !!c.is_private,
            is_saved: !!c.is_saved,
            is_pinned: false,
            can_be_upgraded: false,
            can_be_transferred: false,
            was_refunded: false,
            date: m.date || 0,
            gift: up ? { "@type": "sentGiftUpgraded", gift: c.gift }
                     : { "@type": "sentGiftRegular", gift: c.gift },
            sell_star_count: c.sell_star_count || 0,
            prepaid_upgrade_star_count: c.prepaid_upgrade_star_count || 0
        }
    }

    function markChecklistTask(chatId, messageId, taskId, doneNow, cb) {
        send({
            "@type": "markChecklistTasksAsDone",
            chat_id: chatId,
            message_id: messageId,
            marked_as_done_task_ids: doneNow ? [taskId] : [],
            marked_as_not_done_task_ids: doneNow ? [] : [taskId]
        }, cb || check)
    }

    // --- agy/forum ---
    // Forum supergroup topics (TDLib 1.8.68: getForumTopics, forumTopic, forumTopicInfo,
    // forumTopicIcon, messageTopicForum, getForumTopicHistory, updateForumTopicInfo, updateForumTopic,
    // createForumTopic, editForumTopic, toggleForumTopicIsClosed, toggleForumTopicIsPinned,
    // readAllForumTopicMentions, readAllForumTopicReactions)
    property var forumTopics: ({})      // chatId -> { forum_topic_id -> forumTopic }
    property int forumTopicsSeen: 0
    signal forumTopicInfoUpdated(var info)
    signal forumTopicUpdated(var upd)

    readonly property var forumIconColors: [0x6FB9F0, 0xFFD67E, 0xCB86DB, 0x8EEE98, 0xFF93B2, 0xFB6F5F]

    function isForum(c) {
        if (!c || !c.type || c.type["@type"] !== "chatTypeSupergroup" || c.type.is_channel)
            return false
        const g = groups["s" + c.type.supergroup_id]
        return !!(g && g.is_forum)
    }

    function canManageTopics(c) {
        if (!c || !c.type || c.type["@type"] !== "chatTypeSupergroup")
            return false
        const g = groups["s" + c.type.supergroup_id]
        const st = g ? g.status : null
        if (!st)
            return false
        if (st["@type"] === "chatMemberStatusCreator")
            return true
        return st["@type"] === "chatMemberStatusAdministrator" && !!(st.rights && st.rights.can_manage_topics)
    }

    function canCreateTopics(c) {
        if (!c || !c.type || c.type["@type"] !== "chatTypeSupergroup")
            return false
        if (canManageTopics(c))
            return true
        const g = groups["s" + c.type.supergroup_id]
        const st = g ? g.status : null
        if (!st)
            return false
        const k = st["@type"]
        if (k === "chatMemberStatusBanned" || k === "chatMemberStatusLeft")
            return false
        if (k === "chatMemberStatusRestricted")
            return (!st.permissions || st.permissions.can_create_topics !== false)
                   && !!(c.permissions && c.permissions.can_create_topics)
        return !!(c.permissions && c.permissions.can_create_topics)
    }

    function forumColorHex(colorInt, fallbackId) {
        if (colorInt && colorInt > 0)
            return "#" + hex(colorInt)
        return tints[Math.abs(fallbackId || 0) % tints.length]
    }

    function forumTopicOf(chatId, topicId) {
        const m = forumTopics[chatId]
        return m ? (m[topicId] || null) : null
    }

    function cacheForumTopic(chatId, t) {
        if (!chatId || !t || !t.info)
            return
        const tid = t.info.forum_topic_id
        if (!tid)
            return
        const map = forumTopics[chatId] || {}
        map[tid] = t
        forumTopics[chatId] = map
    }

    function onForumTopicInfo(info) {
        if (!info || !info.chat_id || !info.forum_topic_id)
            return
        const cid = info.chat_id, tid = info.forum_topic_id
        const map = forumTopics[cid] || {}
        const cur = map[tid]
        if (cur)
            map[tid] = Object.assign({}, cur, { info: info })
        else
            map[tid] = { "@type": "forumTopic", info: info, last_message: null, order: "0", is_pinned: false,
                         unread_count: 0, last_read_inbox_message_id: 0, last_read_outbox_message_id: 0,
                         unread_mention_count: 0, unread_reaction_count: 0, unread_poll_vote_count: 0,
                         notification_settings: null, draft_message: null }
        forumTopics[cid] = map
        forumTopicsSeen++
        forumTopicInfoUpdated(info)
    }

    function onForumTopic(u) {
        if (!u || !u.chat_id || !u.forum_topic_id)
            return
        const cid = u.chat_id, tid = u.forum_topic_id
        const map = forumTopics[cid] || {}
        const cur = map[tid]
        if (cur) {
            const next = Object.assign({}, cur)
            if (u.is_pinned !== undefined)
                next.is_pinned = !!u.is_pinned
            if (u.last_read_inbox_message_id !== undefined)
                next.last_read_inbox_message_id = u.last_read_inbox_message_id
            if (u.last_read_outbox_message_id !== undefined)
                next.last_read_outbox_message_id = u.last_read_outbox_message_id
            if (u.unread_mention_count !== undefined)
                next.unread_mention_count = u.unread_mention_count || 0
            if (u.unread_reaction_count !== undefined)
                next.unread_reaction_count = u.unread_reaction_count || 0
            if (u.unread_poll_vote_count !== undefined)
                next.unread_poll_vote_count = u.unread_poll_vote_count || 0
            if (u.notification_settings !== undefined)
                next.notification_settings = u.notification_settings
            map[tid] = next
            forumTopics[cid] = map
            forumTopicsSeen++
        }
        forumTopicUpdated(u)
    }

    function getForumTopics(chatId, query, offsetDate, offsetMsgId, offsetTopicId, limit, done) {
        send({
            "@type": "getForumTopics",
            chat_id: chatId,
            query: query || "",
            offset_date: offsetDate || 0,
            offset_message_id: offsetMsgId || 0,
            offset_forum_topic_id: offsetTopicId || 0,
            limit: limit || 20
        }, (r) => {
            if (r["@type"] === "forumTopics") {
                const list = r.topics || []
                for (const t of list)
                    store.cacheForumTopic(chatId, t)
                if (list.length)
                    store.forumTopicsSeen++
                if (done)
                    done(list, r.next_offset_date || 0, r.next_offset_message_id || 0,
                         r.next_offset_forum_topic_id || 0, r.total_count || list.length, "")
                return
            }
            if (done)
                done([], 0, 0, 0, 0, r.message || Tr.t("Bo'lmadi"))
        })
    }

    function createForumTopic(chatId, name, color, done) {
        send({
            "@type": "createForumTopic",
            chat_id: chatId,
            name: (name || "").trim(),
            is_name_implicit: false,
            icon: { "@type": "forumTopicIcon", color: color || forumIconColors[0], custom_emoji_id: "0" }
        }, (r) => {
            if (r["@type"] === "forumTopicInfo")
                store.onForumTopicInfo(r)
            if (done)
                done(r)
        })
    }

    function editForumTopic(chatId, topicId, name, done) {
        send({
            "@type": "editForumTopic",
            chat_id: chatId,
            forum_topic_id: topicId,
            name: (name || "").trim(),
            edit_icon_custom_emoji: false,
            icon_custom_emoji_id: "0"
        }, done || check)
    }

    function toggleForumTopicClosed(chatId, topicId, closed, done) {
        send({
            "@type": "toggleForumTopicIsClosed",
            chat_id: chatId,
            forum_topic_id: topicId,
            is_closed: !!closed
        }, done || check)
    }

    function toggleForumTopicPinned(chatId, topicId, pinned, done) {
        send({
            "@type": "toggleForumTopicIsPinned",
            chat_id: chatId,
            forum_topic_id: topicId,
            is_pinned: !!pinned
        }, done || check)
    }

    function searchForumUnreadMentions(chatId, topicId, fromId, done) {
        send({
            "@type": "searchChatMessages",
            chat_id: chatId,
            topic_id: { "@type": "messageTopicForum", forum_topic_id: topicId },
            query: "",
            sender_id: null,
            from_message_id: fromId || 0,
            offset: 0,
            limit: 20,
            filter: { "@type": "searchMessagesFilterUnreadMention" }
        }, (r) => {
            if (!done)
                return
            if (r["@type"] === "foundChatMessages")
                done(r.messages || [], "")
            else
                done([], r.message || "")
        })
    }

    function searchForumUnreadReactions(chatId, topicId, fromId, done) {
        send({
            "@type": "searchChatMessages",
            chat_id: chatId,
            topic_id: { "@type": "messageTopicForum", forum_topic_id: topicId },
            query: "",
            sender_id: null,
            from_message_id: fromId || 0,
            offset: 0,
            limit: 20,
            filter: { "@type": "searchMessagesFilterUnreadReaction" }
        }, (r) => {
            if (!done)
                return
            if (r["@type"] === "foundChatMessages")
                done(r.messages || [], "")
            else
                done([], r.message || "")
        })
    }

    function readAllForumTopicMentions(chatId, topicId, done) {
        send({ "@type": "readAllForumTopicMentions", chat_id: chatId, forum_topic_id: topicId }, done || check)
    }

    function readAllForumTopicReactions(chatId, topicId, done) {
        send({ "@type": "readAllForumTopicReactions", chat_id: chatId, forum_topic_id: topicId }, done || check)
    }

    // --- agy/inline-botlar ---
    // Inline bot queries (TDLib 1.8.68: searchPublicChat, userTypeBot.is_inline,
    // userTypeBot.inline_query_placeholder, getInlineQueryResults, inlineQueryResults,
    // inlineQueryResultsButton/StartBot/WebApp, inlineQueryResult*, sendInlineQueryResultMessage,
    // message.via_bot_user_id)
    property var _inlineBotCache: ({})      // lowercase username -> { isInline, userId, username, placeholder, title }
    property var _viaBotAsked: ({})         // userId -> true (lazy getUser guard)

    function viaBotName(userId) {
        if (!userId || userId <= 0)
            return ""
        const u = users[userId]
        if (u) {
            const un = botUsernameOf(userId)
            return un || ((u.first_name || "") + " " + (u.last_name || "")).trim()
        }
        if (!_viaBotAsked[userId]) {
            _viaBotAsked[userId] = true
            send({ "@type": "getUser", user_id: userId }, (r) => {
                if (r && r["@type"] === "user") {
                    users[r.id] = r
                    seenSoon()
                }
            })
        }
        return ""
    }

    function _inlineBotInfoFromUser(u, fallbackName) {
        if (!u || !u.type || u.type["@type"] !== "userTypeBot")
            return { isInline: false, userId: u ? u.id : 0, username: fallbackName || "", placeholder: "", title: "" }
        const un = botUsernameOf(u.id) || fallbackName || ""
        return {
            isInline: !!u.type.is_inline,
            userId: u.id,
            username: un,
            placeholder: u.type.inline_query_placeholder || "",
            title: ((u.first_name || "") + " " + (u.last_name || "")).trim() || un
        }
    }

    function resolveInlineBot(username, done) {
        const clean = String(username || "").trim().replace(/^@/, "").toLowerCase()
        if (clean.length < 3) {
            if (done)
                done(null)
            return
        }
        if (_inlineBotCache[clean] !== undefined) {
            if (done)
                done(_inlineBotCache[clean])
            return
        }
        // Check already-loaded users first to avoid redundant searchPublicChat
        for (const k in users) {
            const u = users[k]
            if (!u || !u.usernames)
                continue
            const actives = u.usernames.active_usernames || []
            const match = actives.some((x) => String(x || "").toLowerCase() === clean)
                       || String(u.usernames.editable_username || "").toLowerCase() === clean
            if (match) {
                const info = _inlineBotInfoFromUser(u, clean)
                _inlineBotCache[clean] = info
                if (done)
                    done(info)
                return
            }
        }
        send({ "@type": "searchPublicChat", username: clean }, (c) => {
            if (!c || c["@type"] !== "chat" || !c.type || c.type["@type"] !== "chatTypePrivate") {
                const miss = { isInline: false, userId: 0, username: clean, placeholder: "", title: "" }
                _inlineBotCache[clean] = miss
                if (done)
                    done(miss)
                return
            }
            const uid = c.type.user_id
            const finish = (u) => {
                const info = _inlineBotInfoFromUser(u, clean)
                _inlineBotCache[clean] = info
                if (done)
                    done(info)
            }
            if (users[uid]) {
                finish(users[uid])
                return
            }
            send({ "@type": "getUser", user_id: uid }, (u) => {
                if (u && u["@type"] === "user") {
                    users[u.id] = u
                    finish(u)
                } else {
                    finish(null)
                }
            })
        })
    }

    function queryInlineBot(botUserId, chatId, query, offset, done) {
        send({
            "@type": "getInlineQueryResults",
            bot_user_id: botUserId,
            chat_id: chatId,
            user_location: null,
            query: query || "",
            offset: offset || ""
        }, (r) => {
            if (!done)
                return
            if (r && r["@type"] === "inlineQueryResults") {
                done(r, "")
                return
            }
            done(null, (r && r.message) || Tr.t("Bo'lmadi"))
        })
    }

    function inlineResultInfo(res, queryId) {
        if (!res || !res["@type"])
            return null
        const t = res["@type"]
        const id = String(res.id || "")
        const qid = String(queryId || "0")
        const thumbOf = (th) => th && th.file ? th.file : null
        const thumbMini = (obj) => obj && obj.minithumbnail ? (obj.minithumbnail.data || "") : ""
        if (t === "inlineQueryResultPhoto") {
            const ph = res.photo || {}
            const sz = ph.sizes && ph.sizes.length ? ph.sizes[ph.sizes.length - 1] : null
            return {
                id: id, queryId: qid, grid: true, kind: "photo",
                title: res.title || "", desc: res.description || "",
                thumbFile: _photoBestFile(ph), animFile: null, mini: thumbMini(ph),
                w: sz && sz.width > 0 ? sz.width : 1, h: sz && sz.height > 0 ? sz.height : 1,
                dur: 0, isTgs: false, badge: ""
            }
        }
        if (t === "inlineQueryResultAnimation") {
            const a = res.animation || {}
            return {
                id: id, queryId: qid, grid: true, kind: "animation",
                title: res.title || "", desc: "",
                thumbFile: thumbOf(a.thumbnail), animFile: a.animation || null, mini: thumbMini(a),
                w: a.width > 0 ? a.width : 4, h: a.height > 0 ? a.height : 3,
                dur: a.duration || 0, isTgs: false, badge: "GIF"
            }
        }
        if (t === "inlineQueryResultSticker") {
            const st = res.sticker || {}
            const isTgs = !!(st.format && st.format["@type"] === "stickerFormatTgs")
            return {
                id: id, queryId: qid, grid: true, kind: "sticker",
                title: st.emoji || "", desc: "",
                thumbFile: _stickerPicFile(st), animFile: null, mini: "",
                w: st.width > 0 ? st.width : 1, h: st.height > 0 ? st.height : 1,
                dur: 0, isTgs: isTgs, badge: ""
            }
        }
        if (t === "inlineQueryResultVideo") {
            const v = res.video || {}
            const dur = v.duration || 0
            return {
                id: id, queryId: qid, grid: true, kind: "video",
                title: res.title || "", desc: res.description || "",
                thumbFile: thumbOf(v.thumbnail), animFile: null, mini: thumbMini(v),
                w: v.width > 0 ? v.width : 16, h: v.height > 0 ? v.height : 9,
                dur: dur, isTgs: false, badge: dur > 0 ? formatCallDuration(dur) : "▶"
            }
        }
        if (t === "inlineQueryResultArticle") {
            return {
                id: id, queryId: qid, grid: false, kind: "article",
                title: res.title || res.url || Tr.t("Havola"),
                desc: res.description || res.url || "",
                thumbFile: thumbOf(res.thumbnail), animFile: null, mini: "",
                w: 1, h: 1, dur: 0, isTgs: false, badge: ""
            }
        }
        if (t === "inlineQueryResultAudio") {
            const au = res.audio || {}
            const dur = au.duration ? formatCallDuration(au.duration) : ""
            const perf = au.performer || ""
            return {
                id: id, queryId: qid, grid: false, kind: "audio",
                title: au.title || au.file_name || Tr.t("Musiqa"),
                desc: perf && dur ? perf + " · " + dur : (perf || dur),
                thumbFile: thumbOf(au.album_cover_thumbnail), animFile: null, mini: "",
                w: 1, h: 1, dur: au.duration || 0, isTgs: false, badge: "♪"
            }
        }
        if (t === "inlineQueryResultDocument") {
            const doc = res.document || {}
            const sz = doc.document ? size(doc.document.size || doc.document.expected_size || 0) : ""
            return {
                id: id, queryId: qid, grid: false, kind: "document",
                title: res.title || doc.file_name || Tr.t("Fayl"),
                desc: res.description || (doc.file_name && res.title ? doc.file_name + (sz ? " · " + sz : "") : sz),
                thumbFile: thumbOf(doc.thumbnail), animFile: null, mini: thumbMini(doc),
                w: 1, h: 1, dur: 0, isTgs: false, badge: "📄"
            }
        }
        if (t === "inlineQueryResultLocation") {
            const loc = res.location || {}
            const coords = loc.latitude !== undefined ? (Number(loc.latitude).toFixed(4) + ", " + Number(loc.longitude).toFixed(4)) : ""
            return {
                id: id, queryId: qid, grid: false, kind: "location",
                title: res.title || Tr.t("Joylashuv"),
                desc: coords,
                thumbFile: thumbOf(res.thumbnail), animFile: null, mini: "",
                w: 1, h: 1, dur: 0, isTgs: false, badge: "📍"
            }
        }
        if (t === "inlineQueryResultVenue") {
            const ven = res.venue || {}
            return {
                id: id, queryId: qid, grid: false, kind: "venue",
                title: ven.title || Tr.t("Joy"),
                desc: ven.address || "",
                thumbFile: thumbOf(res.thumbnail), animFile: null, mini: "",
                w: 1, h: 1, dur: 0, isTgs: false, badge: "📍"
            }
        }
        if (t === "inlineQueryResultContact") {
            const ct = res.contact || {}
            const name = ((ct.first_name || "") + " " + (ct.last_name || "")).trim() || Tr.t("Kontakt")
            return {
                id: id, queryId: qid, grid: false, kind: "contact",
                title: name,
                desc: formatPhone(ct.phone_number || ""),
                thumbFile: thumbOf(res.thumbnail), animFile: null, mini: "",
                w: 1, h: 1, dur: 0, isTgs: false, badge: "👤"
            }
        }
        if (t === "inlineQueryResultVoiceNote") {
            const vn = res.voice_note || {}
            return {
                id: id, queryId: qid, grid: false, kind: "voice",
                title: res.title || Tr.t("Ovozli xabar"),
                desc: vn.duration ? formatCallDuration(vn.duration) : "",
                thumbFile: null, animFile: null, mini: "",
                w: 1, h: 1, dur: vn.duration || 0, isTgs: false, badge: "🎤"
            }
        }
        if (t === "inlineQueryResultGame") {
            const g = res.game || {}
            return {
                id: id, queryId: qid, grid: false, kind: "game",
                title: g.title || Tr.t("O'yin"),
                desc: g.description || "",
                thumbFile: _photoBestFile(g.photo), animFile: null, mini: thumbMini(g.photo),
                w: 1, h: 1, dur: 0, isTgs: false, badge: "🎮"
            }
        }
        return {
            id: id, queryId: qid, grid: false, kind: "other",
            title: res.title || id, desc: res.description || "",
            thumbFile: null, animFile: null, mini: "",
            w: 1, h: 1, dur: 0, isTgs: false, badge: "•"
        }
    }

    function sendInlineResult(chatId, queryId, resultId, replyTo, thread, silent, directTopic, paidStars, forumTopic, hideViaBot, done) {
        const req = {
            "@type": "sendInlineQueryResultMessage",
            chat_id: chatId,
            topic_id: topic(thread, directTopic, forumTopic),
            reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
            options: sendOpts(silent, paidStars, null),
            query_id: String(queryId || "0"),
            result_id: String(resultId || ""),
            hide_via_bot: !!hideViaBot
        }
        send(req, done || check)
    }

    // --- agy/sorovnoma-joylashuv ---
    property int pollOptionLimit: 10
    property int pollOpenPeriodMax: 600
    property bool _pollLimitsLoaded: false

    function loadPollLimits(done) {
        if (_pollLimitsLoaded) {
            if (done)
                done(pollOptionLimit, pollOpenPeriodMax)
            return
        }
        let left = 2
        const finish = () => {
            if (--left === 0) {
                store._pollLimitsLoaded = true
                if (done)
                    done(store.pollOptionLimit, store.pollOpenPeriodMax)
            }
        }
        send({ "@type": "getOption", name: "poll_answer_count_max" }, (r) => {
            const v = r && r["@type"] === "optionValueInteger" ? Number(r.value) : 0
            if (v >= 2 && v <= 20)
                store.pollOptionLimit = v
            finish()
        })
        send({ "@type": "getOption", name: "poll_open_period_max" }, (r) => {
            const v = r && r["@type"] === "optionValueInteger" ? Number(r.value) : 0
            if (v >= 30 && v <= 86400)
                store.pollOpenPeriodMax = v
            finish()
        })
    }

    // TDLib 1.8.68 inputMessagePoll (inputPollOption + inputPollTypeRegular / inputPollTypeQuiz)
    function sendPoll(chatId, question, options, opts, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic, done) {
        const o = opts || {}
        const isQuiz = !!o.quiz
        const typeObj = isQuiz
            ? {
                "@type": "inputPollTypeQuiz",
                correct_option_ids: [o.correctOptionId >= 0 ? o.correctOptionId : 0],
                explanation: { "@type": "formattedText", text: (o.explanation || "").trim(), entities: [] }
            }
            : { "@type": "inputPollTypeRegular", allow_adding_options: false }
        const content = {
            "@type": "inputMessagePoll",
            question: { "@type": "formattedText", text: (question || "").trim(), entities: [] },
            options: (options || []).map((opt) => ({
                "@type": "inputPollOption",
                text: { "@type": "formattedText", text: String(opt || "").trim(), entities: [] }
            })),
            is_anonymous: o.anonymous !== undefined ? !!o.anonymous : true,
            allows_multiple_answers: !isQuiz && !!o.multiple,
            allows_revoting: !isQuiz,
            shuffle_options: false,
            hide_results_until_closes: false,
            type: typeObj,
            open_period: o.openPeriod > 0 ? Math.round(o.openPeriod) : 0,
            close_date: o.closeDate > 0 ? Math.round(o.closeDate) : 0,
            is_closed: false
        }
        const req = {
            "@type": "sendMessage",
            chat_id: chatId,
            topic_id: topic(thread, directTopic, forumTopic),
            options: sendOpts(silent, paidStars, schedule),
            input_message_content: content
        }
        if (replyTo)
            req.reply_to = { "@type": "inputMessageReplyToMessage", message_id: replyTo }
        send(req, done || check)
    }

    function getMapThumbnail(chatId, lat, lon, zoom, width, height, scale, done) {
        send({
            "@type": "getMapThumbnailFile",
            location: { "@type": "location", latitude: lat, longitude: lon, horizontal_accuracy: 0 },
            zoom: Math.max(13, Math.min(20, Math.round(zoom || 15))),
            width: Math.max(16, Math.min(1024, Math.round(width || 360))),
            height: Math.max(16, Math.min(1024, Math.round(height || 360))),
            scale: Math.max(1, Math.min(3, Math.round(scale || 2))),
            chat_id: chatId || 0
        }, (f) => {
            if (!f || f["@type"] !== "file") {
                if (done)
                    done("")
                return
            }
            store.fetch(f, 16, (path) => {
                if (done)
                    done(path || "")
            })
        })
    }

    // TDLib 1.8.68 inputMessageLocation
    function sendLocation(chatId, lat, lon, accuracy, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic, done) {
        const req = {
            "@type": "sendMessage",
            chat_id: chatId,
            topic_id: topic(thread, directTopic, forumTopic),
            options: sendOpts(silent, paidStars, schedule),
            input_message_content: {
                "@type": "inputMessageLocation",
                location: { "@type": "location", latitude: lat, longitude: lon, horizontal_accuracy: accuracy || 0 }
            }
        }
        if (replyTo)
            req.reply_to = { "@type": "inputMessageReplyToMessage", message_id: replyTo }
        send(req, done || check)
    }

    // TDLib 1.8.68 inputMessageLiveLocation (only used when device GPS is available)
    function sendLiveLocation(chatId, lat, lon, accuracy, livePeriod, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic, done) {
        const req = {
            "@type": "sendMessage",
            chat_id: chatId,
            topic_id: topic(thread, directTopic, forumTopic),
            options: sendOpts(silent, paidStars, schedule),
            input_message_content: {
                "@type": "inputMessageLiveLocation",
                location: {
                    "@type": "liveLocation",
                    location: { "@type": "location", latitude: lat, longitude: lon, horizontal_accuracy: accuracy || 0 },
                    live_period: livePeriod || 900,
                    heading: 0,
                    proximity_alert_radius: 0
                }
            }
        }
        if (replyTo)
            req.reply_to = { "@type": "inputMessageReplyToMessage", message_id: replyTo }
        send(req, done || check)
    }

    // TDLib 1.8.68 inputMessageContact
    function sendContact(chatId, user, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic, done) {
        if (!user)
            return
        const req = {
            "@type": "sendMessage",
            chat_id: chatId,
            topic_id: topic(thread, directTopic, forumTopic),
            options: sendOpts(silent, paidStars, schedule),
            input_message_content: {
                "@type": "inputMessageContact",
                contact: {
                    "@type": "contact",
                    phone_number: user.phone_number || "",
                    first_name: user.first_name || "",
                    last_name: user.last_name || "",
                    vcard: "",
                    user_id: user.id || 0
                }
            }
        }
        if (replyTo)
            req.reply_to = { "@type": "inputMessageReplyToMessage", message_id: replyTo }
        send(req, done || check)
    }

    // --- agy/stiker-gif-qidiruv ---
    // Sticker/GIF panel search & sticker set sheet helpers (TDLib 1.8.68:
    // getStickers, searchStickers, searchStickerSets, getStickerSet, changeStickerSet,
    // updateInstalledStickerSets, searchPublicChat, getInlineQueryResults, sendInlineQueryResultMessage)
    signal installedStickerSetsChanged(var stickerType, var setIds)
    property var _gifBotId: 0
    property bool _gifBotAsking: false
    property var _gifBotWait: []

    function stickerSearchLangs() {
        const primary = Prefs.lang || Tr.lang || "uz"
        return primary === "en" ? ["en"] : [primary, "en"]
    }

    function searchStickersLocal(query, chatId, limit, done) {
        send({
            "@type": "getStickers",
            sticker_type: { "@type": "stickerTypeRegular" },
            query: query || "",
            limit: limit || 40,
            chat_id: chatId || 0
        }, (r) => {
            if (!done)
                return
            done(r && r["@type"] === "stickers" ? (r.stickers || []) : [])
        })
    }

    function searchStickersRemote(emojis, query, offset, limit, done) {
        send({
            "@type": "searchStickers",
            sticker_type: { "@type": "stickerTypeRegular" },
            emojis: emojis || "",
            query: query || "",
            input_language_codes: stickerSearchLangs(),
            offset: offset || 0,
            limit: limit || 30
        }, (r) => {
            if (!done)
                return
            done(r && r["@type"] === "stickers" ? (r.stickers || []) : [])
        })
    }

    function searchStickerSets(query, done) {
        send({
            "@type": "searchStickerSets",
            sticker_type: { "@type": "stickerTypeRegular" },
            query: query || ""
        }, (r) => {
            if (!done)
                return
            done(r && r["@type"] === "stickerSets" ? (r.sets || []) : [])
        })
    }

    function getStickerSet(setId, done) {
        send({ "@type": "getStickerSet", set_id: String(setId) }, (r) => {
            if (!done)
                return
            if (r && r["@type"] === "stickerSet")
                done(r, "")
            else
                done(null, (r && r.message) || "")
        })
    }

    function changeStickerSet(setId, installed, done) {
        send({
            "@type": "changeStickerSet",
            set_id: String(setId),
            is_installed: !!installed,
            is_archived: false
        }, (r) => {
            if (r && r["@type"] === "error") {
                console.warn("nullgram: changeStickerSet", r.message)
                if (done)
                    done(false, r.message || "")
                return
            }
            if (done)
                done(true, "")
        })
    }

    function _resolveGifBot(done) {
        if (_gifBotId > 0) {
            if (done)
                done(_gifBotId)
            return
        }
        if (done)
            _gifBotWait.push(done)
        if (_gifBotAsking)
            return
        _gifBotAsking = true
        send({ "@type": "searchPublicChat", username: "gif" }, (r) => {
            store._gifBotAsking = false
            let uid = 0
            if (r && r["@type"] === "chat" && r.type && r.type["@type"] === "chatTypePrivate")
                uid = r.type.user_id || 0
            if (uid > 0)
                store._gifBotId = uid
            const wait = store._gifBotWait
            store._gifBotWait = []
            for (const cb of wait)
                cb(uid)
        })
    }

    function searchGifInline(chatId, query, offset, done) {
        _resolveGifBot((botId) => {
            if (!botId) {
                if (done)
                    done("", [], "", "GIF bot not found")
                return
            }
            send({
                "@type": "getInlineQueryResults",
                bot_user_id: botId,
                chat_id: chatId || 0,
                user_location: null,
                query: query || "",
                offset: offset || ""
            }, (r) => {
                if (!done)
                    return
                if (!r || r["@type"] !== "inlineQueryResults") {
                    done("", [], "", (r && r.message) || "")
                    return
                }
                const qid = r.inline_query_id ? String(r.inline_query_id) : ""
                const items = []
                for (const it of (r.results || [])) {
                    if (it && it["@type"] === "inlineQueryResultAnimation" && it.animation)
                        items.push({ id: String(it.id || ""), queryId: qid, title: it.title || "", animation: it.animation })
                }
                done(qid, items, r.next_offset || "", "")
            })
        })
    }

    function sendInlineGifResult(chatId, queryId, resultId, replyTo, thread, silent, directTopic, paidStars, schedule, forumTopic, done) {
        send({
            "@type": "sendInlineQueryResultMessage",
            chat_id: chatId,
            topic_id: topic(thread, directTopic, forumTopic),
            reply_to: replyTo ? { "@type": "inputMessageReplyToMessage", message_id: replyTo } : null,
            options: sendOpts(silent, paidStars, schedule),
            query_id: String(queryId),
            result_id: String(resultId),
            hide_via_bot: false
        }, done || check)
    }
}
