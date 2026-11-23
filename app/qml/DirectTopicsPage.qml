// Channel Direct Messages inbox for channel admins (Telegram-iOS's Monoforum / DirectMessages topics list):
// loads topics via loadDirectMessagesChatTopics(chatId, 50), observes Store.directTopics (updateDirectMessagesChatTopic),
// shows each subscriber's thread sorted by topic.order desc with avatar, name, preview, time, unread pill, and
// «Bepul» badge when unpaid messages are allowed. Tap opens ChatPage on that directTopic; long-press shows iOS
// action sheet (Mark Read/Unread, Allow/Disallow Free Messages, Delete Chat).
import QtQuick

Page {
    id: page
    required property var chatId        // the direct_messages_chat_id (supergroup with is_administered_direct_messages_group)
    property var channelChatId: 0       // parent channel chat id (for «Sozlamalar» shortcut when owner)
    readonly property var chat: (store.seen, store.chats[chatId])
    readonly property var group: (store.seen, store.groupOf(chat))
    readonly property int paidPrice: group ? (group.paid_message_star_count || 0) : 0
    readonly property var channelChat: channelChatId ? (store.seen, store.chats[channelChatId]) : null
    readonly property var channelGroup: channelChat ? (store.seen, store.groupOf(channelChat)) : null
    readonly property bool channelOwner: !!channelGroup && channelGroup.status
                                         && channelGroup.status["@type"] === "chatMemberStatusCreator"

    property bool loaded: false
    property bool loading: false
    property bool more: true
    property var menuTopic: null
    readonly property var topics: (store.directTopicsSeen, store.directTopicList(chatId))

    Component.onCompleted: {
        store.send({ "@type": "openChat", chat_id: chatId })
        loadMore()
    }
    Component.onDestruction: {
        store.send({ "@type": "closeChat", chat_id: chatId })
    }
    function loadMore() {
        if (loading || !more)
            return
        loading = true
        store.send({ "@type": "loadDirectMessagesChatTopics", chat_id: chatId, limit: 50 }, (r) => {
            if (!page)
                return
            page.loading = false
            page.loaded = true
            if (r["@type"] === "error")     // 404: all loaded
                page.more = false
        })
    }
    function openTopic(t) {
        const c = Qt.createComponent("ChatPage.qml")
        if (c.status === Component.Error)
            return console.warn("nullgram:", c.errorString())
        nav.push(c, { chatId: page.chatId, directTopic: t.id, directSender: t.sender_id,
                      directCanUnpaid: !!t.can_send_unpaid_messages })
    }
    function openSettings() {
        if (!channelChatId)
            return
        store.send({ "@type": "getSupergroupFullInfo", supergroup_id: channelChat.type.supergroup_id }, (r) => {
            if (!page)
                return
            const c = Qt.createComponent("ChannelDirectPage.qml")
            if (c.status === Component.Error)
                return console.warn("nullgram:", c.errorString())
            page.nav.push(c, { chatId: page.channelChatId, full: r["@type"] === "supergroupFullInfo" ? r : null })
        })
    }
    function toggleUnread(t) {
        const mark = !(t.unread_count > 0 || t.is_marked_as_unread)
        store.send({ "@type": "setDirectMessagesChatTopicIsMarkedAsUnread", chat_id: chatId, topic_id: t.id,
                     is_marked_as_unread: mark }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(mark ? "O'qilmagan deb belgilandi" : "O'qilgan deb belgilandi"))
        })
    }
    function toggleUnpaid(t) {
        const next = !t.can_send_unpaid_messages
        store.send({ "@type": "toggleDirectMessagesChatTopicCanSendUnpaidMessages", chat_id: chatId, topic_id: t.id,
                     can_send_unpaid_messages: next, refund_payments: false }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(next ? "Bepul yozishga ruxsat berildi" : "Pullik xabarlar qayta yoqildi"))
        })
    }
    function askDelete(t) {
        const name = store.senderName(t.sender_id, false) || Tr.t("Foydalanuvchi")
        alert.title = Tr.t("Suhbatni o'chirish")
        alert.text = Tr.f("%1 bilan barcha xabarlar o'chirilsinmi?", name)
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () => {
            store.send({ "@type": "deleteDirectMessagesChatTopicHistory", chat_id: page.chatId, topic_id: t.id }, (r) => {
                if (r["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                store.dropDirectTopic(page.chatId, t.id)
                page.nav.say(Tr.t("Suhbat o'chirildi"))
            })
        } }]
        alert.open = true
    }
    function dismiss() {
        if (alert.open) {
            alert.open = false
            return true
        }
        if (sheet.open) {
            sheet.open = false
            return true
        }
        return false
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---- topic list ----
    ListView {
        id: list
        anchors.fill: parent
        model: page.topics
        boundsBehavior: Flickable.DragOverBounds
        header: Item { width: 1; height: bar.height + (paidBanner.visible ? paidBanner.height : 0) }
        footer: Item { width: 1; height: 24 + safe.bottom }
        onAtYEndChanged: if (atYEnd && page.more && !page.loading) page.loadMore()

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property var t: modelData
            readonly property string whoName: (store.seen, store.senderName(t.sender_id, false) || Tr.t("Foydalanuvchi"))
            readonly property var lastMsg: t.last_message
            readonly property string previewText: lastMsg ? store.preview(lastMsg.content, page.chat).replace(/\s+/g, " ") : ""
            readonly property string stampText: lastMsg ? store.stamp(lastMsg.date) : ""
            readonly property int unread: t.unread_count || 0

            width: list.width; height: 74
            color: hit.pressed ? Theme.highlight : Theme.bg

            Avatar {
                id: av
                x: 12; y: 10
                width: 54; height: 54
                Component.onCompleted: {
                    const s = row.t.sender_id
                    if (s)
                        store.faceOn(av, s.user_id ? { user_id: s.user_id } : { chat_id: s.chat_id })
                }
            }
            Row {
                x: 78; y: 10
                width: parent.width - x - timeText.width - 22
                spacing: 6
                Text {
                    width: Math.min(implicitWidth, parent.width - (freeBadge.visible ? freeBadge.width + 6 : 0))
                    elide: Text.ElideRight
                    text: row.whoName
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Rectangle {
                    id: freeBadge
                    visible: page.paidPrice > 0 && !!row.t.can_send_unpaid_messages
                    anchors.verticalCenter: parent.verticalCenter
                    width: freeLabel.implicitWidth + 10; height: 17; radius: 5
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    Text {
                        id: freeLabel
                        anchors.centerIn: parent
                        text: Tr.t("Bepul")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                }
            }
            Text {
                id: timeText
                anchors.right: parent.right; anchors.rightMargin: 14; y: 12
                text: (row.lastMsg && row.lastMsg.is_outgoing
                       ? (row.lastMsg.id <= (row.t.last_read_outbox_message_id || 0) ? "✓✓ " : "✓ ") : "") + row.stampText
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                x: 78; y: 33
                width: parent.width - x - (badge.visible ? badge.width + 24 : 14)
                maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.previewText
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15; lineHeight: 0.96
            }
            Rectangle {
                id: badge
                visible: row.unread > 0 || !!row.t.is_marked_as_unread
                anchors.right: parent.right; anchors.rightMargin: 14; y: 38
                height: 22; radius: 11
                width: row.unread > 0 ? Math.max(22, uText.implicitWidth + 14) : 14
                color: Theme.badge
                Text {
                    id: uText
                    visible: row.unread > 0
                    anchors.centerIn: parent
                    text: row.unread > 999 ? Math.floor(row.unread / 1000) + "K" : String(row.unread)
                    color: Theme.badgeText
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
            }
            Rectangle { x: 78; anchors.bottom: parent.bottom; width: parent.width - 78; height: 0.5; color: Theme.separator }
            MouseArea {
                id: hit
                anchors.fill: parent
                onClicked: page.openTopic(row.t)
                onPressAndHold: {
                    page.menuTopic = row.t
                    sheet.open = true
                }
            }
        }
    }

    // ---- empty state ----
    Column {
        visible: page.loaded && page.topics.length === 0
        anchors.centerIn: parent
        width: parent.width - 64
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; width: 48; height: 48; name: "direct"; color: Theme.grey }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: Tr.t("Hali xabarlar yo'q")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: Tr.t("Obunachilar kanalingizga shaxsiy xabar yozganda, ular shu yerda ko'rinadi.")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
    }

    // ---- top bar (iOS 26 floating glass) ----
    Item {
        id: bar
        width: parent.width; height: 60
        Rectangle {
            width: parent.width; height: parent.height + 10
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92) }
                GradientStop { position: 1; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0) }
            }
        }
        Glass {
            x: 10; y: 8; width: 44; height: 44
            opacity: backHit.pressed ? 0.5 : 1
            Text {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                text: "‹"; color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Light
            }
            MouseArea { id: backHit; anchors.fill: parent; onClicked: page.nav.pop() }
        }
        Glass {
            anchors.horizontalCenter: parent.horizontalCenter; y: 8
            width: Math.min(parent.width - 136, Math.max(tMain.implicitWidth, tSub.implicitWidth) + 40); height: 44
            Column {
                anchors.centerIn: parent; width: parent.width - 24
                Text {
                    id: tMain
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: page.chat ? page.chat.title : Tr.t("Kanalga xabarlar")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    id: tSub
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: page.topics.length ? Tr.n("%1 ta suhbat", page.topics.length) : Tr.t("Kanalga xabarlar")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
        Glass {
            visible: page.channelOwner
            anchors.right: parent.right; anchors.rightMargin: 10; y: 8
            width: 44; height: 44
            opacity: setHit.pressed ? 0.6 : 1
            Icon { anchors.centerIn: parent; width: 20; height: 20; name: "settings"; color: Theme.text }
            MouseArea { id: setHit; anchors.fill: parent; onClicked: page.openSettings() }
        }
    }

    // ---- paid price banner under bar ----
    Rectangle {
        id: paidBanner
        y: bar.height
        width: parent.width; height: visible ? 34 : 0
        visible: page.paidPrice > 0
        color: Theme.grouped
        Text {
            anchors.centerIn: parent
            text: Tr.f("Obunachilar har bir xabar uchun ⭐ %1 to'laydi", store.count(page.paidPrice))
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 13
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
    }

    // ---- long-press topic action sheet ----
    Item {
        id: sheet
        anchors.fill: parent
        z: 20
        property bool open: false
        visible: dim.opacity > 0
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: sheet.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: sheet.open ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            spacing: 8
            Rectangle {
                width: parent.width; height: actCol.height; radius: 14; color: Theme.menu; clip: true
                Column {
                    id: actCol
                    width: parent.width
                    Rectangle {
                        width: parent.width; height: 54
                        color: a1.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: page.menuTopic && (page.menuTopic.unread_count > 0 || page.menuTopic.is_marked_as_unread)
                                  ? Tr.t("O'qilgan deb belgilash") : Tr.t("O'qilmagan deb belgilash")
                            color: Theme.accent; font.family: Theme.font; font.pixelSize: 19
                        }
                        MouseArea { id: a1; anchors.fill: parent; onClicked: { const t = page.menuTopic; sheet.open = false; if (t) page.toggleUnread(t) } }
                    }
                    Rectangle { visible: page.paidPrice > 0; width: parent.width; height: 0.5; color: Theme.separator }
                    Rectangle {
                        visible: page.paidPrice > 0
                        width: parent.width; height: visible ? 54 : 0
                        color: a2.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: page.menuTopic && page.menuTopic.can_send_unpaid_messages
                                  ? Tr.t("Bepul yozishni cheklash") : Tr.t("Bepul yozishga ruxsat berish")
                            color: Theme.accent; font.family: Theme.font; font.pixelSize: 19
                        }
                        MouseArea { id: a2; anchors.fill: parent; onClicked: { const t = page.menuTopic; sheet.open = false; if (t) page.toggleUnpaid(t) } }
                    }
                    Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                    Rectangle {
                        width: parent.width; height: 54
                        color: a3.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Suhbatni o'chirish")
                            color: Theme.danger; font.family: Theme.font; font.pixelSize: 19
                        }
                        MouseArea { id: a3; anchors.fill: parent; onClicked: { const t = page.menuTopic; sheet.open = false; if (t) page.askDelete(t) } }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 54; radius: 14
                color: cHit.pressed ? Theme.highlight : Theme.menu
                Text { anchors.centerIn: parent; text: Tr.t("Bekor qilish"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold }
                MouseArea { id: cHit; anchors.fill: parent; onClicked: sheet.open = false }
            }
        }
    }

    Alert { id: alert; anchors.fill: parent }
}
