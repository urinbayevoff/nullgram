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
                root.storyView.show([me], 0)
            else
                root.say(Tr.t("Hikoya joylash hozircha yo'q"))
            return
        }
        const row = store.storyRow
        if (row.indexOf(chatId) < 0)
            root.storyView.show([chatId], 0)
        else
            root.storyView.show(row, row.indexOf(chatId))
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
                boundsBehavior: Flickable.DragOverBounds
                onDragEnded: page.pulled(rows)
                onContentYChanged: if (page.storiesOpen) page.scrolled(rows)
                maximumFlickVelocity: 6000
                flickDeceleration: 2200
                header: Item { width: 1; height: page.headHeight }     // the title, search and chips are over it
                footer: Item { width: 1; height: 90 }      // room over the tab bar
                delegate: rowDelegate
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

    Component {
        id: rowDelegate
        Rectangle {
            id: row
            required property int index
            required property var chatId
            required property string title
            required property bool saved
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

            width: ListView.view.width; height: 76
            color: tap.pressed || lit ? Theme.highlight : Theme.bg
            property bool lit: false

            // a story ring round it (Q); a tap on the picture then opens the stories, not the chat
            readonly property bool storied: (store.storiesSeen, !row.saved && store.hasStories(row.chatId))
            readonly property bool fresh: (store.storiesSeen, row.storied && store.unseen(row.chatId))
            Rectangle {
                visible: row.storied && !row.fresh
                x: 10; y: 8
                width: 60; height: 60; radius: 30
                color: "transparent"
                border.color: Theme.dark ? "#48484a" : "#c7c7cc"; border.width: 1.3
            }
            Rectangle {
                visible: row.fresh
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
                    color: tap.pressed || row.lit ? Theme.highlight : Theme.bg
                }
            }
            Avatar {
                x: row.storied ? 15 : 10; y: row.storied ? 13 : 8
                width: row.storied ? 50 : 60; height: width
                source: row.photo; letters: row.letters; tint: row.tint; saved: row.saved
            }
            Text {
                id: name
                x: 80; y: 9
                width: parent.width - x - stamp.width - 20
                text: row.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                id: stamp
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 11
                text: (row.outgoing ? (row.read ? "✓✓ " : "✓ ") : "") + row.time
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            // under the name, as Telegram-iOS: who wrote it (a group's sender, «Siz», a red «Qoralama») on a
            // line of its own and the text under it on one; with no one, the text on two. Typing: in their place
            readonly property string busy: store.acting, store.activity(store.chats[row.chatId])
            readonly property bool author: row.who !== "" && busy === ""
            readonly property real textWidth: width - 80 - (pill.visible ? pill.width + 22 : 14)
            Text {
                x: 80; y: 31
                width: row.textWidth
                visible: row.author
                text: row.who
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: row.draft ? Theme.danger : Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
            Icon {
                id: glyph
                x: 80; y: row.author ? 52 : 33
                width: 16; height: 16
                visible: row.glyph !== "" && row.busy === ""
                name: row.glyph
                color: Theme.grey
            }
            Text {
                x: glyph.visible ? 100 : 80; y: row.author ? 50 : 31
                width: row.textWidth - (x - 80)
                height: row.author || glyph.visible ? 20 : 40
                maximumLineCount: row.author || glyph.visible ? 1 : 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.busy || row.preview
                color: row.busy ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 15
                lineHeight: 0.95
            }
            Rectangle {
                id: pill
                visible: row.unread > 0 || row.pinned
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 40
                height: 22; radius: 11
                width: row.unread > 0 ? Math.max(22, count.implicitWidth + 14) : 22
                color: row.unread > 0 ? (row.muted ? Theme.mutedBadge : Theme.badge) : "transparent"
                Text {
                    id: count
                    anchors.centerIn: parent
                    text: row.unread > 0 ? (row.unread > 9999 ? Math.floor(row.unread / 1000) + "K" : row.unread) : "📌"
                    color: row.unread > 0 ? (row.muted ? "white" : Theme.badgeText) : Theme.grey
                    font.family: Theme.font; font.pixelSize: row.unread > 0 ? 13 : 11; font.weight: Font.DemiBold
                }
            }
            Rectangle {
                x: 80; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                onClicked: {
                    row.lit = true
                    unlight.restart()
                    page.nav.push(chatPage, { chatId: row.chatId })
                }
            }
            MouseArea {         // (over the row's own: the ringed picture opens the stories)
                enabled: row.storied
                x: 6; y: 4; width: 68; height: 68
                onClicked: page.openStories(row.chatId)
            }
            Timer { id: unlight; interval: 600; onTriggered: row.lit = false }
        }
    }

    Component { id: chatPage; ChatPage {} }

    SearchView {
        id: search
        anchors.fill: parent
        store: page.store
        onOpenChanged: page.searching = open
        onPicked: (chatId, messageId) => page.nav.push(chatPage, messageId ? { chatId: chatId, target: messageId }
                                                                            : { chatId: chatId })
    }
}
