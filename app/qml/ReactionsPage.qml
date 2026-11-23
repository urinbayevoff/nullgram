// Reactions in a channel or group we run (Telegram-iOS's PeerAllowedReactionsScreen): All / Some / None; Some —
// a grid of the reaction emoji, each tapped on or off. Kept as it changes (setChatAvailableReactions, after a
// moment) and said to the opener: changed(chatAvailableReactions).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    property var allowed: null          // chat.available_reactions
    property bool canPaid: false        // supergroupFullInfo.can_enable_paid_reaction
    readonly property var chat: store.chats[chatId]
    readonly property bool channel: !!chat && chat.type["@type"] === "chatTypeSupergroup" && chat.type.is_channel
    signal changed(var r)
    title: Tr.t("Reaksiyalar")
    // Telegram's active emoji reactions (the server's list, as of 2026)
    readonly property var all: ["👍", "👎", "❤", "🔥", "🥰", "👏", "😁", "🤔", "🤯", "😱", "🤬", "😢", "🎉", "🤩", "🤮", "💩",
        "🙏", "👌", "🕊", "🤡", "🥱", "🥴", "😍", "🐳", "❤‍🔥", "🌚", "🌭", "💯", "🤣", "⚡", "🍌", "🏆", "💔", "🤨", "😐",
        "🍓", "🍾", "💋", "🖕", "😈", "😴", "😭", "🤓", "👻", "👨‍💻", "👀", "🎃", "🙈", "😇", "😨", "🤝", "✍", "🤗", "🫡",
        "🎅", "🎄", "☃", "💅", "🤪", "🗿", "🆒", "💘", "🙉", "🦄", "😘", "💊", "🙊", "😎", "👾", "🤷‍♂", "🤷", "🤷‍♀", "😡"]
    property int kind: 0                // 0 all, 1 some, 2 none
    property bool paid: false           // reactionTypePaid enabled (channels only)
    property var chosen: ({})           // emoji -> true
    Component.onCompleted: {
        const r = allowed
        if (!r || r["@type"] === "chatAvailableReactionsAll") {
            kind = 0
            paid = false
        } else {
            const c = {}
            let hasPaid = false
            for (const x of r.reactions || []) {
                if (x["@type"] === "reactionTypeEmoji")
                    c[x.emoji] = true
                else if (x["@type"] === "reactionTypePaid")
                    hasPaid = true
            }
            paid = hasPaid
            chosen = c
            const count = Object.keys(c).length
            // (TDLib encodes «All + Paid» in a channel as chatAvailableReactionsSome containing all active emojis + reactionTypePaid)
            kind = count === 0 ? 2 : (hasPaid && count >= all.length - 5) ? 0 : 1
        }
        if (channel && !canPaid && chat)
            store.send({ "@type": "getSupergroupFullInfo", supergroup_id: chat.type.supergroup_id }, (f) => {
                if (page && f["@type"] === "supergroupFullInfo" && f.can_enable_paid_reaction)
                    page.canPaid = true
            })
    }
    function made() {
        if (!paid) {
            if (kind === 0)
                return { "@type": "chatAvailableReactionsAll", max_reaction_count: 11 }
            const list = kind === 2 ? [] : all.filter((e) => chosen[e]).map((e) => ({ "@type": "reactionTypeEmoji", emoji: e }))
            return { "@type": "chatAvailableReactionsSome", reactions: list, max_reaction_count: 11 }
        }
        // paid reactions enabled: TDLib ChatReactions requires chatAvailableReactionsSome with reactionTypePaid
        const emojis = kind === 0 ? all : kind === 1 ? all.filter((e) => chosen[e]) : []
        const list = [{ "@type": "reactionTypePaid" }].concat(emojis.map((e) => ({ "@type": "reactionTypeEmoji", emoji: e })))
        return { "@type": "chatAvailableReactionsSome", reactions: list, max_reaction_count: 11 }
    }
    function flipPaid() {
        paid = !paid
        later.restart()
    }
    function pickKind(k) {
        if (k === 1 && !Object.keys(chosen).length) {
            const c = {}
            for (const e of all.slice(0, 12))
                c[e] = true
            chosen = c
        }
        kind = k
        later.restart()
    }
    function flip(e) {
        const c = Object.assign({}, chosen)
        if (c[e])
            delete c[e]
        else
            c[e] = true
        chosen = c
        later.restart()
    }
    Timer {
        id: later
        interval: 600
        onTriggered: {
            const r = page.made()
            store.send({ "@type": "setChatAvailableReactions", chat_id: page.chatId, available_reactions: r }, (x) => {
                if (x["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", x.message))
                page.changed(r)
            })
        }
    }
    Component.onDestruction: if (later.running) { later.stop(); later.triggered() }

    SettingsGroup {
        visible: page.channel && (page.canPaid || page.paid)
        note: Tr.t("Obunachilar kanal postlariga Telegram Yulduzlari bilan reaksiya bildira oladi.")
        SettingsRow {
            icon: "star"; tint: "#ffb10a"
            text: Tr.t("Yulduzli reaksiyalar")
            toggle: true; chevron: false; last: true
            on: page.paid
            onClicked: page.flipPaid()
        }
    }
    SettingsGroup {
        title: Tr.t("Ruxsat etilgan reaksiyalar")
        note: Tr.t(page.kind === 0 ? (page.channel ? "Obunachilar istalgan reaksiyani qo'ya oladi." : "A'zolar istalgan reaksiyani qo'ya oladi.")
                 : page.kind === 1 ? "Faqat tanlangan reaksiyalarni qo'yish mumkin." : "Reaksiya qo'yib bo'lmaydi.")
        SettingsRow { text: Tr.t("Hammasi"); chevron: false; tick: page.kind === 0; onClicked: page.pickKind(0) }
        SettingsRow { text: Tr.t("Ba'zilari"); chevron: false; tick: page.kind === 1; onClicked: page.pickKind(1) }
        SettingsRow { text: Tr.t("Hech biri"); chevron: false; tick: page.kind === 2; last: true; onClicked: page.pickKind(2) }
    }
    Item { width: 1; height: 24 }
    SettingsGroup {
        visible: page.kind === 1
        title: Tr.n("Tanlangan: %1", Object.keys(page.chosen).length)
        Grid {
            id: grid
            readonly property int cols: Math.max(5, Math.floor((width - 16) / 52))
            x: 8; width: parent.width - 16
            topPadding: 8; bottomPadding: 8
            columns: cols
            Repeater {
                model: page.all
                Item {
                    id: cell
                    required property var modelData
                    readonly property bool on: !!page.chosen[modelData]
                    width: (grid.width) / grid.cols; height: 52
                    Rectangle {
                        anchors.centerIn: parent
                        width: 44; height: 44; radius: 22
                        color: cell.on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : "transparent"
                        border.width: cell.on ? 2 : 0
                        border.color: Theme.accent
                    }
                    Image {
                        id: pic
                        anchors.centerIn: parent
                        width: 30; height: 30
                        opacity: cell.on ? 1 : 0.35
                        sourceSize: Qt.size(Math.ceil(30 * Screen.devicePixelRatio), Math.ceil(30 * Screen.devicePixelRatio))
                        asynchronous: true
                        source: Emo.fileUrl(cell.modelData)
                    }
                    Text {
                        visible: pic.status !== Image.Ready
                        anchors.centerIn: parent
                        opacity: cell.on ? 1 : 0.35
                        text: cell.modelData
                        font.pixelSize: 26
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.flip(cell.modelData) }
                }
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
