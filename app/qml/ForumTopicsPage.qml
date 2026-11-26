// Forum supergroup topics list (0.9.8, Telegram-iOS List view):
// shows General topic at top, pinned topics, unread/mention badges, closed lock, colored circle +
// first letter icons (when custom_emoji_id is unset), search (getForumTopics query), offset_*
// pagination, live updateForumTopicInfo/updateForumTopic updates, and admin actions (+ new, edit,
// close/reopen, pin/unpin).
pragma ComponentBehavior: Bound
import QtQuick

Page {
    id: page
    required property var chatId
    readonly property bool follows: true
    readonly property var chat: store.seen >= 0 ? store.chats[chatId] : null
    readonly property bool canManage: store.seen >= 0 && store.canManageTopics(chat)
    readonly property bool canCreate: store.seen >= 0 && store.canCreateTopics(chat)

    property bool loaded: false
    property bool loading: false
    property bool hasMore: true
    property int totalCount: 0
    property int nextOffsetDate: 0
    property var nextOffsetMsgId: 0
    property int nextOffsetTopicId: 0
    property int reqSeq: 0
    property string query: ""
    property var rawTopics: ({})
    property var menuTopic: null
    property int now: Date.now() / 1000

    readonly property alias topicList: list
    readonly property alias topicsModel: topicModel
    readonly property alias searchInput: searchField
    readonly property alias topicSheetView: topicSheet

    ListModel { id: topicModel }

    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }
    Timer { id: searchTimer; interval: 220; onTriggered: page.reload(searchField.text.trim()) }
    Timer {
        id: openTimer
        interval: 1
        property var pending: null
        onTriggered: {
            const p = pending
            pending = null
            if (!p || !page || !page.nav)
                return
            if (p.info)
                page.nav.push(infoPageComp, { chatId: page.chatId })
            else
                page.nav.pushChat(chatPageComp, p)
        }
    }

    Component.onCompleted: reload("")

    function reload(q) {
        searchTimer.stop()
        query = q || ""
        reqSeq++
        rawTopics = {}
        topicModel.clear()
        list.positionViewAtBeginning()
        loaded = false
        loading = false
        hasMore = true
        nextOffsetDate = 0
        nextOffsetMsgId = 0
        nextOffsetTopicId = 0
        loadMore()
    }

    function loadMore() {
        if (loading || !hasMore)
            return
        loading = true
        const seq = reqSeq
        const q = query
        store.getForumTopics(chatId, q, nextOffsetDate, nextOffsetMsgId, nextOffsetTopicId, 20,
                             (topics, nDate, nMsgId, nTopicId, total, err) => {
            if (!page || seq !== page.reqSeq)
                return
            page.loading = false
            page.loaded = true
            if (err) {
                page.hasMore = false
                if (page.nav)
                    page.nav.say(err)
                return
            }
            if (q === "")
                page.totalCount = total
            let added = 0
            for (const t of (topics || [])) {
                if (!t || !t.info || !t.info.forum_topic_id)
                    continue
                const tid = t.info.forum_topic_id
                if (!page.rawTopics[tid])
                    added++
                page.rawTopics[tid] = t
            }
            page.nextOffsetDate = nDate || 0
            page.nextOffsetMsgId = nMsgId || 0
            page.nextOffsetTopicId = nTopicId || 0
            page.hasMore = added > 0 && (nDate !== 0 || nMsgId !== 0 || nTopicId !== 0)
            page.rebuildModel()
        })
    }

    function topicLetter(name, isGeneral) {
        if (isGeneral)
            return "#"
        const s = (name || "").trim()
        if (!s)
            return "?"
        const chars = Array.from(s)
        return chars.length ? chars[0].toUpperCase() : "?"
    }

    function rowFromTopic(t) {
        const info = t.info || {}
        const tid = info.forum_topic_id || 0
        const isGen = !!info.is_general
        const name = info.name || (isGen ? Tr.t("Umumiy") : "")
        const icon = info.icon || {}
        const colorInt = icon.color || 0
        const m = t.last_message || null
        const draftText = t.draft_message && t.draft_message.content && t.draft_message.content.text
                          ? t.draft_message.content.text.text : ""
        let sender = ""
        let preview = ""
        if (draftText) {
            sender = Tr.t("Qoralama")
            preview = draftText.replace(/\s+/g, " ")
        } else if (m) {
            const svc = store.service(m, chat)
            if (svc !== null) {
                preview = svc
            } else {
                sender = m.is_outgoing ? Tr.t("Siz") : (store.senderName(m.sender_id, true) || "")
                preview = store.preview(m.content, chat).replace(/\s+/g, " ")
            }
        } else {
            preview = Tr.t("Hali xabar yo'q")
        }
        const muted = !!(t.notification_settings && t.notification_settings.mute_for > 0)
        const outMsg = !!(m && m.is_outgoing && !draftText)
        const outRead = outMsg && m.id <= (t.last_read_outbox_message_id || 0)
        return {
            topicId: tid,
            name: name,
            letter: topicLetter(name, isGen),
            colorHex: store.forumColorHex(colorInt, tid),
            colorInt: colorInt,
            isGeneral: isGen,
            isClosed: !!info.is_closed,
            isPinned: !!t.is_pinned,
            isOutgoing: !!info.is_outgoing,
            unread: t.unread_count || 0,
            unreadMentions: t.unread_mention_count || 0,
            unreadReactions: t.unread_reaction_count || 0,
            muted: muted,
            isDraft: !!draftText,
            sender: sender,
            preview: preview,
            time: m ? store.stamp(m.date) : (info.creation_date ? store.stamp(info.creation_date) : ""),
            outMsg: outMsg,
            outRead: outRead,
            orderKey: String(t.order || "0"),
            lastDate: m ? (m.date || 0) : (info.creation_date || 0)
        }
    }

    function compareTopics(a, b) {
        const ai = a.info || {}, bi = b.info || {}
        if (!!ai.is_general !== !!bi.is_general)
            return ai.is_general ? -1 : 1
        if (!!a.is_pinned !== !!b.is_pinned)
            return a.is_pinned ? -1 : 1
        const ao = String(a.order || "0"), bo = String(b.order || "0")
        if (ao !== bo)
            return store.before(ao, bo) ? -1 : 1
        const ad = (a.last_message ? a.last_message.date : ai.creation_date) || 0
        const bd = (b.last_message ? b.last_message.date : bi.creation_date) || 0
        if (ad !== bd)
            return bd - ad
        return (bi.forum_topic_id || 0) - (ai.forum_topic_id || 0)
    }

    function rebuildModel() {
        const arr = []
        for (const k in rawTopics) {
            const t = rawTopics[k]
            if (t && t.info && !t.info.is_hidden)
                arr.push(t)
        }
        arr.sort(compareTopics)
        const rows = arr.map((t) => rowFromTopic(t))
        // Update in place or append tail without destroying existing delegates
        if (rows.length >= topicModel.count && topicModel.count > 0) {
            let samePrefix = true
            for (let i = 0; i < topicModel.count; i++) {
                if (topicModel.get(i).topicId !== rows[i].topicId) {
                    samePrefix = false
                    break
                }
            }
            if (samePrefix) {
                for (let i = 0; i < topicModel.count; i++)
                    topicModel.set(i, rows[i])
                if (rows.length > topicModel.count)
                    topicModel.append(rows.slice(topicModel.count))
                return
            }
        }
        const savedY = list.contentY
        topicModel.clear()
        if (rows.length)
            topicModel.append(rows)
        if (savedY > list.originY)
            list.contentY = Math.min(savedY, Math.max(list.originY, list.originY + list.contentHeight - list.height))
    }

    function openTopic(tid) {
        const t = rawTopics[tid] || store.forumTopicOf(chatId, tid)
        const info = t && t.info ? t.info : {}
        searchField.focus = false
        osk.hide()
        openTimer.pending = {
            chatId: page.chatId,
            forumTopic: tid,
            forumGeneral: !!info.is_general,
            forumTitle: info.name || (info.is_general ? Tr.t("Umumiy") : ""),
            forumClosed: !!info.is_closed
        }
        openTimer.restart()
    }

    function openInfo() {
        searchField.focus = false
        osk.hide()
        openTimer.pending = { info: true }
        openTimer.restart()
    }

    function openTopicMenu(tid) {
        const t = rawTopics[tid]
        if (!t || !t.info)
            return
        const info = t.info
        const canEdit = canManage || !!info.is_outgoing
        const canPin = canManage && !info.is_general
        if (!canEdit && !canPin)
            return
        menuTopic = {
            topicId: tid,
            name: info.name || (info.is_general ? Tr.t("Umumiy") : ""),
            colorInt: info.icon ? (info.icon.color || 0) : 0,
            isGeneral: !!info.is_general,
            isClosed: !!info.is_closed,
            isPinned: !!t.is_pinned,
            canEdit: canEdit,
            canPin: canPin
        }
        actionSheet.open = true
    }

    function toggleCloseTopic(mt) {
        const nextClosed = !mt.isClosed
        store.toggleForumTopicClosed(chatId, mt.topicId, nextClosed, (r) => {
            if (!page)
                return
            if (r && r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(nextClosed ? "Mavzu yopildi" : "Mavzu ochildi"))
        })
    }

    function togglePinTopic(mt) {
        const nextPinned = !mt.isPinned
        store.toggleForumTopicPinned(chatId, mt.topicId, nextPinned, (r) => {
            if (!page)
                return
            if (r && r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(nextPinned ? "Mavzu qadaldi" : "Qadash yechildi"))
        })
    }

    function dismiss() {
        if (topicSheet.open) {
            topicSheet.close()
            return true
        }
        if (actionSheet.open) {
            actionSheet.open = false
            return true
        }
        if (searchField.text !== "" || searchField.activeFocus) {
            searchField.focus = false
            osk.hide()
            if (searchField.text !== "") {
                searchField.text = ""
                reload("")
            }
            return true
        }
        return false
    }

    Connections {
        target: store
        function onForumTopicInfoUpdated(info) {
            if (!info || info.chat_id !== page.chatId)
                return
            const tid = info.forum_topic_id
            if (!tid)
                return
            if (info.is_hidden) {
                delete page.rawTopics[tid]
                page.rebuildModel()
                return
            }
            if (page.query !== "" && store.fold(info.name || "").indexOf(store.fold(page.query)) < 0 && !page.rawTopics[tid])
                return
            const cur = page.rawTopics[tid]
            if (cur)
                page.rawTopics[tid] = Object.assign({}, cur, { info: info })
            else {
                const cached = store.forumTopicOf(page.chatId, tid)
                page.rawTopics[tid] = cached || {
                    "@type": "forumTopic", info: info, last_message: null, order: String(Date.now()),
                    is_pinned: false, unread_count: 0, last_read_inbox_message_id: 0,
                    last_read_outbox_message_id: 0, unread_mention_count: 0,
                    unread_reaction_count: 0, unread_poll_vote_count: 0,
                    notification_settings: null, draft_message: null
                }
                if (page.query === "" && page.loaded)
                    page.totalCount = Math.max(page.totalCount + 1, Object.keys(page.rawTopics).length)
            }
            page.rebuildModel()
        }
        function onForumTopicUpdated(u) {
            if (!u || u.chat_id !== page.chatId)
                return
            const tid = u.forum_topic_id
            const cur = page.rawTopics[tid]
            if (!cur)
                return
            const next = Object.assign({}, cur)
            if (u.is_pinned !== undefined)
                next.is_pinned = !!u.is_pinned
            if (u.last_read_inbox_message_id !== undefined) {
                next.last_read_inbox_message_id = u.last_read_inbox_message_id
                if (next.last_message && next.last_message.id <= u.last_read_inbox_message_id)
                    next.unread_count = 0
            }
            if (u.last_read_outbox_message_id !== undefined)
                next.last_read_outbox_message_id = u.last_read_outbox_message_id
            if (u.unread_mention_count !== undefined)
                next.unread_mention_count = u.unread_mention_count || 0
            if (u.unread_reaction_count !== undefined)
                next.unread_reaction_count = u.unread_reaction_count || 0
            if (u.notification_settings !== undefined)
                next.notification_settings = u.notification_settings
            page.rawTopics[tid] = next
            page.rebuildModel()
        }
        function onMessage(m) {
            if (!m || m.chat_id !== page.chatId || !m.topic_id || m.topic_id["@type"] !== "messageTopicForum")
                return
            const tid = m.topic_id.forum_topic_id
            const cur = page.rawTopics[tid]
            if (!cur)
                return
            const next = Object.assign({}, cur, { last_message: m })
            if (!m.is_outgoing && store.openChat !== page.chatId)
                next.unread_count = (cur.unread_count || 0) + 1
            page.rawTopics[tid] = next
            page.rebuildModel()
        }
    }

    Component { id: infoPageComp; ChatInfoPage {} }
    Component { id: chatPageComp; ChatPage {} }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---- virtual topic list ----
    ListView {
        id: list
        anchors.fill: parent
        model: topicModel
        clip: true
        boundsBehavior: Flickable.DragOverBounds
        header: Item { width: 1; height: bar.height + searchBar.height }
        footer: Item {
            width: list.width
            height: (page.loading && topicModel.count > 0 ? 44 : 0) + 24 + safe.bottom
            Ring {
                visible: page.loading && topicModel.count > 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 24; height: 24
                value: 0.7; cross: false
                color: Theme.accent
            }
        }
        onAtYEndChanged: if (atYEnd && page.hasMore && !page.loading && topicModel.count > 0) page.loadMore()

        delegate: Rectangle {
            id: row
            required property int topicId
            required property string name
            required property string letter
            required property string colorHex
            required property bool isGeneral
            required property bool isClosed
            required property bool isPinned
            required property int unread
            required property int unreadMentions
            required property bool muted
            required property bool isDraft
            required property string sender
            required property string preview
            required property string time
            required property bool outMsg
            required property bool outRead

            width: list.width; height: 74
            color: hit.pressed ? Theme.highlight : Theme.bg

            // Topic icon: # for General, colored circle + first letter otherwise
            Rectangle {
                x: 12; y: 13
                width: 48; height: 48; radius: 24
                color: row.isGeneral ? (Theme.dark ? "#2c2c2e" : "#e5e5ea") : row.colorHex
                Text {
                    anchors.centerIn: parent
                    text: row.letter
                    color: row.isGeneral ? Theme.grey : "white"
                    font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold
                }
            }

            // Title + closed lock
            Row {
                x: 72; y: 11
                width: parent.width - x - timeText.width - 22
                spacing: 5
                Text {
                    width: Math.min(implicitWidth, parent.width - (lockIcon.visible ? 18 : 0))
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Icon {
                    id: lockIcon
                    visible: row.isClosed
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13; height: 13
                    name: "lock"
                    color: Theme.grey
                }
            }

            // Timestamp + outgoing ticks
            Text {
                id: timeText
                anchors.right: parent.right; anchors.rightMargin: 14; y: 13
                text: (row.outMsg ? (row.outRead ? "✓✓ " : "✓ ") : "") + row.time
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }

            // Last message preview (sender + text, max 2 lines)
            Text {
                x: 72; y: 34
                width: parent.width - x - (badges.width > 0 ? badges.width + 22 : 14)
                maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.sender ? (row.sender + ": " + row.preview) : row.preview
                color: row.isDraft ? Theme.danger : Theme.grey
                font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.05
            }

            // Right badges: @ mention, unread count, pin
            Row {
                id: badges
                anchors.right: parent.right; anchors.rightMargin: 14; y: 38
                spacing: 5
                Rectangle {
                    visible: row.unreadMentions > 0
                    width: 22; height: 22; radius: 11
                    color: Theme.badge
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        text: "@"
                        color: Theme.badgeText
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    visible: row.unread > 0
                    height: 22; radius: 11
                    width: Math.max(22, uText.implicitWidth + 12)
                    color: row.muted ? Theme.mutedBadge : Theme.badge
                    Text {
                        id: uText
                        anchors.centerIn: parent
                        text: row.unread > 999 ? Math.floor(row.unread / 1000) + "K" : String(row.unread)
                        color: Theme.badgeText
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
                Icon {
                    visible: row.isPinned
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15; height: 15
                    name: "pin"
                    color: Theme.grey
                }
            }

            Rectangle { x: 72; anchors.bottom: parent.bottom; width: parent.width - 72; height: 0.5; color: Theme.separator }

            MouseArea {
                id: hit
                anchors.fill: parent
                onClicked: page.openTopic(row.topicId)
                onPressAndHold: page.openTopicMenu(row.topicId)
            }
        }
    }

    // ---- loading / empty state ----
    Ring {
        visible: page.loading && !page.loaded && topicModel.count === 0
        anchors.centerIn: parent
        width: 30; height: 30
        value: 0.7; cross: false
        color: Theme.accent
    }
    Column {
        visible: page.loaded && topicModel.count === 0
        anchors.centerIn: parent
        width: parent.width - 64
        spacing: 6
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: page.query ? Tr.t("Mavzular topilmadi") : Tr.t("Mavzular yo'q")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
        Text {
            visible: page.query !== ""
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: Tr.t("Boshqa so'z bilan qidirib ko'ring")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
    }

    // ---- search bar under header ----
    Rectangle {
        id: searchBar
        z: 2
        y: bar.height
        width: parent.width; height: 48
        color: Theme.bg
        Rectangle {
            x: 12; y: 6
            width: parent.width - 24; height: 36; radius: 18
            color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
            Icon {
                x: 11; anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17; name: "search"; color: Theme.grey
            }
            TextInput {
                id: searchField
                x: 34; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (clearBtn.visible ? 34 : 12)
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 15
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: searchTimer.restart()
                onAccepted: { searchTimer.stop(); page.reload(text.trim()); focus = false }
                Text {
                    visible: !searchField.text
                    text: Tr.t("Mavzu qidirish")
                    color: Theme.grey
                    font: searchField.font
                }
            }
            Item {
                id: clearBtn
                visible: searchField.text !== ""
                anchors.right: parent.right; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: Theme.grey
                    Icon { anchors.centerIn: parent; width: 10; height: 10; name: "cross"; color: Theme.bg }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        searchTimer.stop()
                        searchField.text = ""
                        page.reload("")
                    }
                }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
    }

    // ---- top bar (iOS 26 floating glass) ----
    Item {
        id: bar
        z: 3
        width: parent.width; height: 60
        Rectangle {
            width: parent.width; height: parent.height + 6
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.96) }
                GradientStop { position: 1; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0) }
            }
        }
        Glass {
            id: backBtn
            x: 10; y: 8; width: 44; height: 44
            opacity: backHit.pressed ? 0.5 : 1
            Text {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                text: "‹"; color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Light
            }
            MouseArea { id: backHit; anchors.fill: parent; onClicked: page.nav.pop() }
        }
        Glass {
            id: titleCap
            readonly property real rightEdge: addBtn.visible ? bar.width - addBtn.x : bar.width - face.x
            readonly property real room: bar.width - 2 * Math.max(backBtn.x + backBtn.width, rightEdge) - 12
            anchors.horizontalCenter: parent.horizontalCenter; y: 8
            width: Math.max(96, Math.min(room, Math.max(tMain.implicitWidth, tSub.implicitWidth) + 34))
            height: 44
            opacity: titleHit.pressed ? 0.6 : 1
            Column {
                anchors.centerIn: parent; width: parent.width - 22
                Text {
                    id: tMain
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: page.chat ? store.title(page.chat) : Tr.t("Mavzular")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    id: tSub
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: page.totalCount > 0 ? Tr.n("%1 ta mavzu", page.totalCount)
                        : (store.seen >= 0 ? store.status(page.chat, page.now) : "")
                    visible: text !== ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            MouseArea { id: titleHit; anchors.fill: parent; onClicked: page.openInfo() }
        }
        Glass {
            id: addBtn
            visible: page.canCreate
            anchors.right: face.left; anchors.rightMargin: 8; y: 8
            width: 44; height: 44
            opacity: addHit.pressed ? 0.6 : 1
            Icon { anchors.centerIn: parent; width: 20; height: 20; name: "plus"; color: Theme.accent }
            MouseArea { id: addHit; anchors.fill: parent; onClicked: topicSheet.showCreate() }
        }
        Avatar {
            id: face
            anchors.right: parent.right; anchors.rightMargin: 10; y: 8
            width: 44; height: 44
            source: page.chat ? store.photoPath(page.chat) : ""
            letters: page.chat ? store.letters(page.chat.title) : ""
            tint: store.tints[Math.abs(page.chatId) % store.tints.length]
            MouseArea { anchors.fill: parent; onClicked: page.openInfo() }
        }
    }

    // ---- long-press admin action sheet (safe.bottom aware) ----
    Item {
        id: actionSheet
        anchors.fill: parent
        z: 20
        property bool open: false
        visible: actDim.opacity > 0.001
        Rectangle {
            id: actDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: actionSheet.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent; onClicked: actionSheet.open = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: actionSheet.open ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            spacing: 8
            Rectangle {
                width: parent.width; height: actCol.height; radius: 14; color: Theme.menu; clip: true
                Column {
                    id: actCol
                    width: parent.width
                    Rectangle {
                        visible: !!(page.menuTopic && page.menuTopic.canEdit)
                        width: parent.width; height: visible ? 54 : 0
                        color: eHit.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Mavzuni tahrirlash")
                            color: Theme.accent; font.family: Theme.font; font.pixelSize: 18
                        }
                        MouseArea {
                            id: eHit
                            anchors.fill: parent
                            onClicked: {
                                const mt = page.menuTopic
                                actionSheet.open = false
                                if (mt)
                                    topicSheet.showEdit(mt.topicId, mt.name, mt.colorInt)
                            }
                        }
                    }
                    Rectangle {
                        visible: !!(page.menuTopic && page.menuTopic.canEdit)
                        width: parent.width; height: 0.5; color: Theme.separator
                    }
                    Rectangle {
                        visible: !!(page.menuTopic && page.menuTopic.canEdit)
                        width: parent.width; height: visible ? 54 : 0
                        color: clHit.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: page.menuTopic && page.menuTopic.isClosed ? Tr.t("Mavzuni ochish") : Tr.t("Mavzuni yopish")
                            color: Theme.accent; font.family: Theme.font; font.pixelSize: 18
                        }
                        MouseArea {
                            id: clHit
                            anchors.fill: parent
                            onClicked: {
                                const mt = page.menuTopic
                                actionSheet.open = false
                                if (mt)
                                    page.toggleCloseTopic(mt)
                            }
                        }
                    }
                    Rectangle {
                        visible: !!(page.menuTopic && page.menuTopic.canPin)
                        width: parent.width; height: 0.5; color: Theme.separator
                    }
                    Rectangle {
                        visible: !!(page.menuTopic && page.menuTopic.canPin)
                        width: parent.width; height: visible ? 54 : 0
                        color: pinHit.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: page.menuTopic && page.menuTopic.isPinned ? Tr.t("Qadashni yechish") : Tr.t("Qadash")
                            color: Theme.accent; font.family: Theme.font; font.pixelSize: 18
                        }
                        MouseArea {
                            id: pinHit
                            anchors.fill: parent
                            onClicked: {
                                const mt = page.menuTopic
                                actionSheet.open = false
                                if (mt)
                                    page.togglePinTopic(mt)
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 54; radius: 14
                color: cancelHit.pressed ? Theme.highlight : Theme.menu
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                }
                MouseArea { id: cancelHit; anchors.fill: parent; onClicked: actionSheet.open = false }
            }
        }
    }

    // ---- create / edit topic sheet ----
    ForumTopicSheet {
        id: topicSheet
        anchors.fill: parent
        z: 25
        store: page.store
        chatId: page.chatId
        safeBottom: safe.bottom
        oskH: osk.h
        onHideKeyboardRequested: osk.hide()
        onSaved: (info) => {
            if (page.nav)
                page.nav.say(Tr.t(info ? "Mavzu yaratildi" : "Mavzu saqlandi"))
        }
    }
}
