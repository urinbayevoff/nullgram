// The chats, as Telegram-iOS lists them (ChatListItem.swift): a round picture, the
// name and time on one line, two lines of the last message under it, the unread
// count in a pill. A tap lights the row at once; the chat comes in when it is ready.
// Over the list, as on iOS 26: the title in the middle and the search box under it; a tap
// on the box turns the page into the search (SearchView). Under it the chat folders (IMG_0295): a
// capsule of chips, the one shown on grey with its unread count; the folders' lists side by side
// under them, a sideways swipe slides to the next or the one before.
import QtQuick

Page {
    id: page
    property bool searching: false
    // chats with something unread (not muted): the tab bar's badge
    readonly property int unreadChats: store.unreadChats

    function toTop() {
        if (list)
            list.positionViewAtBeginning()
    }

    // the folders as the chips show them: all chats first (or where Premium put them: main_chat_list_position)
    readonly property var tabs: { const t = store.folders.slice(); t.splice(Math.min(store.mainPosition, t.length), 0, { id: 0, name: Tr.t("Hammasi") }); return t }
    readonly property int tabIndex: Math.max(0, tabs.findIndex((t) => t.id === store.folder))
    function go(i) {
        if (i < 0 || i >= tabs.length || tabs[i].id === store.folder)
            return
        store.showFolder(tabs[i].id)
    }

    // TDLib counts a folder's unread chats once the folder is loaded: load each a little
    property bool countsAsked: false
    Connections {
        target: store
        function onFoldersChanged() {
            if (page.countsAsked || !store.folders.length)
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
    function openChat(chatId) {
        page.litChatId = chatId
        unlight.restart()
        const c = store.chats[chatId]
        if (td.fps)
            store.tapAt = Date.now()
        if (store.isDirectAdmin(c))
            page.nav.push(directPage, { chatId: chatId })
        else
            page.nav.pushChat(chatPage, { chatId: chatId })
    }
    function dismiss() {
        if (searching) {
            search.close()
            return true
        }
        return false
    }

    // the folders side by side (Telegram-iOS: the list slides with the finger to the next folder, the
    // chips follow), each its own list, kept as it was: going back shows it at once with its pictures
    // (one list filled afresh at each folder lit up white and put initials over every picture, IMG_0085)
    // (the sound playing: under the chips in their capsule, as iOS 26 has it -- or a capsule of its own)
    // Hikoyalar (Q): the row of ringed pictures over the search box, out when the list is pulled down past
    // 60 (or the small pictures by the title tapped), in again once the list has gone up past it
    readonly property bool anyStories: (store.storiesSeen, store.storyRow.length > 0 || (!!store.me && store.hasStories(store.me.id)))
    property bool storiesOpen: false
    property bool quick: false
    readonly property real storyFull: 98
    property real storyH: storiesOpen && anyStories ? storyFull : 0
    Behavior on storyH { enabled: !page.quick; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    function pulled(l) {
        if (anyStories && !storiesOpen && l.contentY - l.originY < -60)
            storiesOpen = true
    }
    function scrolled(l) {
        if (!storiesOpen || l.contentY - l.originY <= headHeight + 20)
            return
        quick = true            // (out of sight: at once, the rows kept where they are)
        storiesOpen = false
        l.contentY -= storyFull
        quick = false
    }
    function openStories(chatId) {
        const me = store.me ? store.me.id : 0
        if (chatId === me) {
            if (store.hasStories(me))
                root.stories().show([me], 0)
            else
                root.say(Tr.t("Hikoya joylash hozircha yo'q"))
            return
        }
        const row = store.storyRow
        if (row.indexOf(chatId) < 0)
            root.stories().show([chatId], 0)
        else
            root.stories().show(row, row.indexOf(chatId))
    }
    readonly property real headHeight: 104 + storyH + (store.folders.length || miniList.on ? 52 - (store.folders.length ? 0 : 44) + miniList.height : 0)
    readonly property ListView list: pager.currentItem ? pager.currentItem.rows : null
    ListView {
        id: pager
        anchors.fill: parent
        orientation: ListView.Horizontal
        model: page.tabs
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        interactive: store.folders.length > 0 && !page.searching
        flickDeceleration: 4000
        highlightMoveDuration: 400
        cacheBuffer: width * Math.max(1, page.tabs.length)      // all of them made, none dropped
        currentIndex: page.tabIndex
        onCurrentIndexChanged: if (currentIndex !== page.tabIndex && page.tabs[currentIndex]) {
            page.align()
            store.showFolder(page.tabs[currentIndex].id)
        }
        delegate: Item {
            id: folderPage
            required property var modelData
            readonly property ListView rows: rows
            width: pager.width; height: pager.height
            ListView {
                id: rows
                anchors.fill: parent
                Component.onCompleted: model = store.modelOf(folderPage.modelData.id)
                cacheBuffer: 600
                reuseItems: true
                boundsBehavior: Flickable.DragOverBounds
                onDragEnded: page.pulled(rows)
                onContentYChanged: if (page.storiesOpen) page.scrolled(rows)
                maximumFlickVelocity: 6000
                flickDeceleration: 2200
                header: Item { width: 1; height: page.headHeight }     // the title, search and chips are over it
                footer: Item { width: 1; height: 90 }      // room over the tab bar
                delegate: rowDelegate
                TapHandler {
                    onPressedChanged: {
                        if (!pressed) {
                            page.pressedChatId = null
                            return
                        }
                        const p = point.pressPosition
                        const r = rows.itemAt(p.x, p.y)
                        if (!r || r.chatId === undefined) {
                            page.pressedChatId = null
                            return
                        }
                        const ly = p.y - r.y
                        page.pressedChatId = (r.storied && p.x >= 6 && p.x < 74 && ly >= 4 && ly < 72) ? null : r.chatId
                    }
                    onTapped: (eventPoint) => {
                        const p = eventPoint.position
                        const r = rows.itemAt(p.x, p.y)
                        if (!r || r.chatId === undefined)
                            return
                        const ly = p.y - r.y
                        if (r.storied && p.x >= 6 && p.x < 74 && ly >= 4 && ly < 72)
                            page.openStories(r.chatId)
                        else
                            page.openChat(r.chatId)
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
            if (!n || off >= page.headHeight || n.contentY - n.originY >= page.headHeight)
                return
            n.contentY = n.originY + off
        })
    }

    // over the lists: the title, the search box, the folder chips. It goes up with the list shown,
    // as if in it
    Item {
        id: head
        width: parent.width; height: page.headHeight
        y: page.list ? Math.max(-height, -(page.list.contentY - page.list.originY)) : 0
        Rectangle { anchors.fill: parent; color: Theme.bg }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16
            spacing: 6
            Item {          // the stories folded: up to three small pictures by the title
                visible: page.anyStories && page.storyH < 1
                width: visible ? 22 + 14 * (Math.min(3, store.storyRow.length) - 1) : 0; height: 22
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: (store.storiesSeen, store.storyRow.slice(0, 3))
                    StoryAvatar {
                        required property var modelData
                        required property int index
                        x: index * 14; z: 3 - index
                        chatId: modelData
                        size: 22
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: page.storiesOpen = true }
            }
            Text {
                text: store.connection || Tr.t("Chatlar")
                color: store.connection ? Theme.grey : Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
        }
        ListView {          // the stories out: Mening hikoyam, then the others' (unseen first)
            id: storyList
            y: 46
            width: parent.width; height: page.storyH
            visible: page.storyH > 1
            opacity: page.storyH / page.storyFull
            clip: true
            orientation: ListView.Horizontal
            leftMargin: 8; rightMargin: 8
            spacing: 2
            model: (store.storiesSeen, [store.me ? store.me.id : 0].concat(store.storyRow))
            delegate: Item {
                id: st
                required property var modelData
                required property int index
                readonly property bool mine: index === 0
                width: 74; height: page.storyFull
                StoryAvatar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    chatId: st.modelData
                    size: 64
                    plus: st.mine
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 72
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: st.mine ? Tr.t("Hikoyam") : (store.seen, store.chats[st.modelData] ? store.chats[st.modelData].title.split(" ")[0] : "")
                    color: !st.mine && (store.storiesSeen, !store.unseen(st.modelData)) ? Theme.grey : Theme.text
                    font.family: Theme.font; font.pixelSize: 12
                }
                MouseArea { anchors.fill: parent; onClicked: page.openStories(st.modelData) }
            }
        }
        Rectangle {          // the search box: a tap opens the search
            x: 14
            width: parent.width - 28; height: 38; radius: 19
            color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
            y: 52 + page.storyH
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
        Rectangle {          // the folders, and under them the mini player
            visible: store.folders.length > 0 || miniList.on
            x: 12; y: 100 + page.storyH
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

    // Optional row parts at page level, loaded via a single Loader per row only when needed
    Component {
        id: storySeenComp
        Rectangle {
            readonly property var r: parent ? parent.r : null
            x: 10; y: 8
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
            x: 10; y: 8
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
            x: t ? 80 + t.width + 6 : 80
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
            x: 80; y: 31
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
            x: 80; y: r && r.author ? 52 : 33
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
            x: r ? r.width - width - 14 : 0
            y: 40
            height: 22; radius: 11
            width: r && r.unread > 0 ? Math.max(22, count.implicitWidth + 14) : 22
            color: r && r.unread > 0 ? (r.muted ? Theme.mutedBadge : Theme.badge) : "transparent"
            Text {
                id: count
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
            x: 80; y: 31
            width: r ? r.textWidth : 0
            text: r ? r.who : ""
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: r && r.draft ? Theme.danger : Theme.text
            font.family: Theme.font; font.pixelSize: 15
            Rectangle {
                id: wpPill
                x: wp.r ? wp.r.width - 80 - width - 14 : 0
                y: 9
                height: 22; radius: 11
                width: wp.r && wp.r.unread > 0 ? Math.max(22, wpCount.implicitWidth + 14) : 22
                color: wp.r && wp.r.unread > 0 ? (wp.r.muted ? Theme.mutedBadge : Theme.badge) : "transparent"
                Text {
                    id: wpCount
                    anchors.centerIn: parent
                    text: wp.r && wp.r.unread > 0 ? (wp.r.unread > 9999 ? Math.floor(wp.r.unread / 1000) + "K" : wp.r.unread) : "📌"
                    color: wp.r && wp.r.unread > 0 ? (wp.r.muted ? "white" : Theme.badgeText) : Theme.grey
                    font.family: Theme.font; font.pixelSize: wp.r && wp.r.unread > 0 ? 13 : 11; font.weight: Font.DemiBold
                }
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
            required property bool muted
            required property bool pinned
            required property string photo
            required property string letters
            required property string tint
            required property bool outgoing
            required property bool read

            width: page.width; height: 76
            color: page.litChatId === row.chatId || page.pressedChatId === row.chatId ? Theme.highlight : Theme.bg

            // a story ring round it (Q); a tap on the picture then opens the stories, not the chat
            readonly property bool storied: !row.saved && store.storiesSeen >= 0 && !!store.stories[row.chatId]
            readonly property bool fresh: row.storied && store.storiesSeen >= 0 && store.unseen(row.chatId)

            Avatar {
                z: 1
                x: row.storied ? 15 : 10; y: row.storied ? 13 : 8
                width: row.storied ? 50 : 60; height: width
                source: row.photo; letters: row.letters; tint: row.tint; saved: row.saved
            }
            Text {
                id: titleText
                x: 80; y: 9
                width: Math.min(implicitWidth, row.width - 100 - stamp.width - (row.direct ? row.directW + 6 : 0))
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
            readonly property bool hasPill: row.unread > 0 || row.pinned
            readonly property bool hasGlyph: row.glyph !== "" && row.busy === ""
            readonly property int extraMask: (row.author ? 1 : 0) | (row.hasPill ? 2 : 0) | (row.hasGlyph ? 4 : 0)
                                           | (row.direct ? 8 : 0) | (row.storied ? (row.fresh ? 32 : 16) : 0)
            readonly property real pillW: row.hasPill && extras.item && extras.item.pillW ? extras.item.pillW : 22
            readonly property real directW: row.direct && extras.item && extras.item.directW ? extras.item.directW : 0
            readonly property real textWidth: width - 80 - (hasPill ? pillW + 22 : 14)
            Text {
                x: row.hasGlyph ? 100 : 80; y: row.author ? 50 : 31
                width: row.textWidth - (x - 80)
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
                               : multiExtrasComp
            }
            Rectangle {
                x: 80; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
        }
    }

    Component { id: chatPage; ChatPage {} }
    Component { id: directPage; DirectTopicsPage {} }

    SearchView {
        id: search
        anchors.fill: parent
        store: page.store
        onOpenChanged: page.searching = open
        onPicked: (chatId, messageId) => page.nav.push(chatPage, messageId ? { chatId: chatId, target: messageId }
                                                                            : { chatId: chatId })
    }
}
