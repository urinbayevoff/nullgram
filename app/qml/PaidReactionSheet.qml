// Paid Star reaction sheet for a channel post (Telegram-iOS's StarReactionsController): gold star hero with sparkles,
// balance at top-right, interactive Star amount slider + preset chips (1..paid_reaction_star_count_max), Top Reactors
// leaderboard (paid_reactors), identity privacy toggle (Show me / Anonymous / as owned channel via
// getChatAvailablePaidMessageReactionSenders; setPaidMessageReactionType if already reacted), and gold CTA with
// confirmation alert (addPendingPaidMessageReaction + commitPendingPaidMessageReactions).
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 24

    property var store
    property var chatId: 0
    property var messageId: 0
    property var reactors: []           // paidReactor[] from messageInteractionInfo.reactions.paid_reactors
    property bool alreadyMine: false    // current user already sent a paid reaction on this post
    property int amount: 50
    property int maxStars: 2500         // getOption("paid_reaction_star_count_max")
    property string mode: "regular"     // "regular" | "anonymous" | "chat"
    property var senderChatId: 0        // when mode === "chat"
    property var availableSenders: []   // messageSenderChat[] we own (from getChatAvailablePaidMessageReactionSenders)
    property bool open: false
    property bool sending: false
    signal say(string text)

    readonly property var chat: store && chatId ? store.chats[chatId] : null
    readonly property string channelTitle: chat ? chat.title : ""
    readonly property real stars: store ? store.stars : -1
    readonly property bool few: stars >= 0 && stars < amount
    readonly property color gold: Theme.dark ? "#ffc337" : "#d3720a"
    readonly property var spring: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]
    // non-linear steps as Telegram-iOS's Star slider: fine control at 1..100, broader steps up to maxStars
    readonly property var presets: [1, 10, 50, 100, 500, 1000, 2500]

    function fmt(n) { return String(Math.floor(n || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, Tr.en ? "," : " ") }
    function sliderToStars(t) {
        const clamped = Math.max(0, Math.min(1, t))
        const cap = Math.max(10, maxStars)
        if (clamped <= 0)
            return 1
        if (clamped >= 1)
            return cap
        // exponential curve: 1 -> cap
        const v = Math.round(Math.pow(cap, clamped))
        if (v < 10) return Math.max(1, v)
        if (v < 100) return Math.round(v / 5) * 5
        if (v < 500) return Math.round(v / 25) * 25
        return Math.min(cap, Math.round(v / 50) * 50)
    }
    function starsToSlider(n) {
        const cap = Math.max(10, maxStars)
        return Math.max(0, Math.min(1, Math.log(Math.max(1, n)) / Math.log(cap)))
    }
    function reactionTypeObj() {
        if (mode === "anonymous")
            return { "@type": "paidReactionTypeAnonymous" }
        if (mode === "chat" && senderChatId)
            return { "@type": "paidReactionTypeChat", chat_id: senderChatId }
        return { "@type": "paidReactionTypeRegular" }
    }

    function show(msgId, paidReactors, mine) {
        messageId = msgId
        reactors = paidReactors || []
        alreadyMine = !!mine
        sending = false
        confirm.visible = false
        amount = Math.min(50, maxStars)
        // restore our current identity if we already reacted on this post
        const meRow = reactors.find((r) => r.is_me)
        if (meRow) {
            if (meRow.is_anonymous) {
                mode = "anonymous"
                senderChatId = 0
            } else if (meRow.sender_id && meRow.sender_id["@type"] === "messageSenderChat") {
                mode = "chat"
                senderChatId = meRow.sender_id.chat_id
            } else {
                mode = "regular"
                senderChatId = 0
            }
        } else {
            mode = "regular"
            senderChatId = 0
        }
        flick.contentY = 0
        open = true
        visible = true
        panel.y = height
        rise.to = height - panel.height + 40
        rise.restart()
        shade.restart()
        load()
    }
    function close() {
        if (!open)
            return
        open = false
        confirm.visible = false
        rise.stop()
        down.to = height
        fall.restart()
    }
    function backOne() {
        if (confirm.visible)
            confirm.visible = false
        else
            close()
    }
    function load() {
        store.send({ "@type": "getOption", name: "paid_reaction_star_count_max" }, (r) => {
            if (sheet && r["@type"] === "optionValueInteger" && Number(r.value) > 0)
                sheet.maxStars = Number(r.value)
        })
        if (store.me)
            store.send({ "@type": "getStarTransactions", owner_id: { "@type": "messageSenderUser", user_id: store.me.id },
                         subscription_id: "", direction: null, offset: "", limit: 1 }, (r) => {
                if (sheet && r["@type"] === "starTransactions")
                    store.stars = r.star_amount.star_count
            })
        store.send({ "@type": "getChatAvailablePaidMessageReactionSenders", chat_id: chatId }, (r) => {
            if (!sheet || r["@type"] !== "messageSenders")
                return
            sheet.availableSenders = (r.senders || []).filter((s) => s["@type"] === "messageSenderChat")
        })
    }
    function changeIdentity(newMode, cid) {
        mode = newMode
        senderChatId = cid || 0
        if (alreadyMine) {
            store.send({ "@type": "setPaidMessageReactionType", chat_id: chatId, message_id: messageId,
                         type: reactionTypeObj() }, (r) => {
                if (r["@type"] === "error")
                    return sheet.say(Tr.f("Bo'lmadi: %1", r.message))
                sheet.say(Tr.t("Ko'rinish yangilandi"))
            })
        }
    }
    function askSend() {
        if (sending)
            return
        if (few)
            return say(Tr.t("Yulduz yetmaydi"))
        confirm.show()
    }
    function sendPaid() {
        sending = true
        const n = amount, mid = messageId, cid = chatId
        store.send({ "@type": "addPendingPaidMessageReaction", chat_id: cid, message_id: mid,
                     star_count: n, type: reactionTypeObj() }, (r) => {
            if (r["@type"] === "error") {
                sheet.sending = false
                return sheet.say(Tr.f("Bo'lmadi: %1", r.message))
            }
            store.send({ "@type": "commitPendingPaidMessageReactions", chat_id: cid, message_id: mid }, (r2) => {
                sheet.sending = false
                if (r2["@type"] === "error") {
                    store.send({ "@type": "removePendingPaidMessageReactions", chat_id: cid, message_id: mid })
                    return sheet.say(Tr.f("Bo'lmadi: %1", r2.message))
                }
                sheet.close()
                sheet.say(Tr.f("⭐ %1 yulduzli reaksiya yuborildi", sheet.fmt(n)))
            })
        })
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.4; duration: 300 }

    Rectangle {
        id: panel
        width: parent.width
        height: Math.min(parent.height - 36, col.height + foot.height + safe.bottom) + 40
        onHeightChanged: if (sheet.open && !rise.running) y = sheet.height - height + 40
        radius: 34
        color: Theme.grouped
        clip: true
        MouseArea { anchors.fill: parent }

        Flickable {
            id: flick
            width: parent.width
            height: parent.height - 40 - foot.height - safe.bottom
            contentHeight: col.height
            boundsBehavior: Flickable.DragOverBounds
            clip: true

            Column {
                id: col
                width: parent.width
                spacing: 0

                // ---- star hero + title ----
                Item {
                    width: parent.width; height: 112
                    Repeater {
                        model: 16
                        Icon {
                            required property int index
                            readonly property real r1: ((index * 53 + 17) % 97) / 97
                            readonly property real r2: ((index * 37 + 23) % 89) / 89
                            x: parent.width / 2 - 90 + r1 * 180
                            y: 12 + r2 * 84
                            width: 5 + (index % 3) * 2; height: width
                            opacity: 0.4 + (index % 4) * 0.15
                            name: index % 3 === 0 ? "star" : "sparkle"
                            color: "#ffb10a"
                        }
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 26
                        width: 72; height: 72; radius: 36
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#ffd43b" }
                            GradientStop { position: 1; color: "#f59000" }
                        }
                        Icon { anchors.centerIn: parent; width: 42; height: 42; name: "star"; color: "white" }
                    }
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Yulduzli reaksiya")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold
                }
                Item { width: 1; height: 6 }
                Text {
                    x: 24; width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: Tr.f("«%1» kanalini Telegram Yulduzlari bilan qo'llab-quvvatlang.", sheet.channelTitle)
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Item { width: 1; height: 18 }

                // ---- chosen star amount badge + smooth slider + presets ----
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: amountRow.implicitWidth + 32; height: 44; radius: 22
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ffb800" }
                        GradientStop { position: 1; color: "#f58500" }
                    }
                    Row {
                        id: amountRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; name: "star"; color: "white" }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sheet.fmt(sheet.amount)
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold
                        }
                    }
                }
                Item { width: 1; height: 14 }
                Item {          // continuous slider
                    x: 20; width: parent.width - 40; height: 36
                    readonly property real pos: sheet.starsToSlider(sheet.amount)
                    Rectangle {
                        y: 15; width: parent.width; height: 6; radius: 3
                        color: Theme.dark ? "#3a3a3c" : "#e5e5ea"
                    }
                    Rectangle {
                        y: 15; width: Math.max(6, parent.pos * parent.width); height: 6; radius: 3
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#ffd43b" }
                            GradientStop { position: 1; color: "#f59000" }
                        }
                    }
                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - width, parent.pos * parent.width - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 14
                        color: "white"
                        border.color: "#f59000"; border.width: 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        function pick(mx) { sheet.amount = sheet.sliderToStars(mx / width) }
                        onPressed: (m) => pick(m.x)
                        onPositionChanged: (m) => { if (pressed) pick(m.x) }
                    }
                }
                Item { width: 1; height: 8 }
                Flickable {
                    x: 16; width: parent.width - 32; height: 34
                    contentWidth: presetRow.width
                    clip: true
                    Row {
                        id: presetRow
                        spacing: 8
                        Repeater {
                            model: sheet.presets.filter((p) => p <= sheet.maxStars)
                            Rectangle {
                                id: pChip
                                required property int modelData
                                readonly property bool on: sheet.amount === modelData
                                width: pRow.implicitWidth + 22; height: 30; radius: 15
                                color: on ? Qt.rgba(1, 0.72, 0.05, 0.25) : Theme.card
                                border.color: on ? "#f59000" : "transparent"; border.width: 1.5
                                Row {
                                    id: pRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Icon { anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; name: "star"; color: "#ffb10a" }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: sheet.fmt(pChip.modelData)
                                        color: pChip.on ? sheet.gold : Theme.text
                                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                    }
                                }
                                MouseArea { anchors.fill: parent; onClicked: sheet.amount = pChip.modelData }
                            }
                        }
                    }
                }

                // ---- Top Reactors leaderboard ----
                Item { width: 1; height: sheet.reactors.length ? 18 : 14 }
                SettingsGroup {
                    visible: sheet.reactors.length > 0
                    title: Tr.t("Eng faol yuboruvchilar")
                    Repeater {
                        id: topList
                        model: sheet.reactors
                        Item {
                            id: rRow
                            required property var modelData
                            required property int index
                            readonly property bool anon: !!modelData.is_anonymous || !modelData.sender_id
                            readonly property string label: anon ? (modelData.is_me ? Tr.t("Siz (anonim)") : Tr.t("Anonim"))
                                : (sheet.store.seen, sheet.store.senderName(modelData.sender_id, false) || Tr.t("Foydalanuvchi"))
                            width: parent.width; height: 50
                            Rectangle {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22; radius: 11
                                color: index === 0 ? "#ffb800" : index === 1 ? "#8e8e93" : index === 2 ? "#cd7f32" : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "#" + (rRow.index + 1)
                                    color: rRow.index < 3 ? "white" : Theme.grey
                                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }
                            Avatar {
                                id: rAv
                                x: 44; anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 34
                                ghost: rRow.anon
                                letters: rRow.anon ? "" : sheet.store.letters(rRow.label)
                                tint: rRow.anon ? "#8e8e93" : sheet.store.tints[Math.abs(rRow.modelData.sender_id.user_id || rRow.modelData.sender_id.chat_id || 0) % sheet.store.tints.length]
                                Component.onCompleted: {
                                    if (!rRow.anon && rRow.modelData.sender_id) {
                                        const s = rRow.modelData.sender_id
                                        sheet.store.faceOn(rAv, s.user_id ? { user_id: s.user_id } : { chat_id: s.chat_id })
                                    }
                                }
                            }
                            Text {
                                x: 88; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - starVal.width - 26
                                elide: Text.ElideRight
                                text: rRow.label + (rRow.modelData.is_me && !rRow.anon ? " (" + Tr.t("Siz") + ")" : "")
                                color: rRow.modelData.is_me ? Theme.accent : Theme.text
                                font.family: Theme.font; font.pixelSize: 15; font.weight: rRow.modelData.is_me ? Font.DemiBold : Font.Normal
                            }
                            Row {
                                id: starVal
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3
                                Icon { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; name: "star"; color: "#ffb10a" }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sheet.fmt(rRow.modelData.star_count)
                                    color: sheet.gold
                                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                }
                            }
                            Rectangle {
                                visible: rRow.index < topList.count - 1
                                x: 44; anchors.bottom: parent.bottom; width: parent.width - 44; height: 0.5; color: Theme.separator
                            }
                        }
                    }
                }

                Item { width: 1; height: 14 }

                // ---- Privacy / Identity selector ----
                SettingsGroup {
                    note: Tr.t(sheet.mode === "anonymous"
                        ? "Ismingiz eng faol yuboruvchilar ro'yxatida ko'rinmaydi."
                        : "Ismingiz ushbu postning eng faol yuboruvchilari ro'yxatida ko'rinadi.")
                    SettingsRow {
                        text: Tr.t("Top yuboruvchilarda ko'rinish")
                        toggle: true; chevron: false
                        on: sheet.mode !== "anonymous"
                        last: sheet.availableSenders.length === 0 || sheet.mode === "anonymous"
                        onClicked: sheet.changeIdentity(sheet.mode === "anonymous" ? "regular" : "anonymous", 0)
                    }
                    Repeater {
                        model: sheet.mode !== "anonymous" ? sheet.availableSenders : []
                        SettingsRow {
                            required property var modelData
                            required property int index
                            readonly property var c: sheet.store.chats[modelData.chat_id]
                            text: Tr.f("Kanal nomidan: %1", c ? c.title : "")
                            chevron: false
                            tick: sheet.mode === "chat" && sheet.senderChatId === modelData.chat_id
                            last: index === sheet.availableSenders.length - 1
                            onClicked: sheet.changeIdentity(
                                sheet.mode === "chat" && sheet.senderChatId === modelData.chat_id ? "regular" : "chat",
                                sheet.mode === "chat" && sheet.senderChatId === modelData.chat_id ? 0 : modelData.chat_id)
                        }
                    }
                }
                Item { width: 1; height: 12 }
            }
        }

        // ---- ✕ top-left & Balance top-right ----
        Glass {
            x: 16; y: 16
            width: 40; height: 40
            opacity: closeHit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; width: 20; height: 20; name: "cross"; color: Theme.text }
            MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.close() }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 16; y: 16
            visible: sheet.stars >= 0
            Text {
                anchors.right: parent.right
                text: Tr.t("Balans")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
            Row {
                anchors.right: parent.right; spacing: 3
                Icon { anchors.verticalCenter: parent.verticalCenter; width: 15; height: 15; name: "star"; color: "#ffb10a" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sheet.fmt(Math.max(0, sheet.stars))
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
            }
        }

        // ---- bottom gold CTA (safe.bottom aware) ----
        Rectangle {
            id: foot
            y: parent.height - 40 - height - safe.bottom
            width: parent.width; height: sheet.few ? 98 : 76
            color: Theme.grouped
            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
            Text {
                visible: sheet.few
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                text: Tr.f("Yulduz yetmaydi. Balansingiz: ⭐ %1", sheet.fmt(Math.max(0, sheet.stars)))
                color: Theme.danger
                font.family: Theme.font; font.pixelSize: 13
            }
            Rectangle {
                x: 20; width: parent.width - 40; height: 50
                anchors.bottom: parent.bottom; anchors.bottomMargin: 13
                radius: 25
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffb800" }
                    GradientStop { position: 1; color: "#f58500" }
                }
                opacity: sheet.few || sheet.sending ? 0.45 : ctaHit.pressed ? 0.8 : 1
                Row {
                    anchors.centerIn: parent; spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; name: "star"; color: "white" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.f("%1 yulduz yuborish", sheet.fmt(sheet.amount))
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                }
                MouseArea { id: ctaHit; anchors.fill: parent; onClicked: sheet.askSend() }
            }
        }
    }

    // ---- spend confirmation alert ----
    Item {
        id: confirm
        anchors.fill: parent
        visible: false
        z: 4
        function show() { visible = true }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }
        MouseArea { anchors.fill: parent; onClicked: confirm.visible = false }
        Rectangle {
            anchors.centerIn: parent
            width: 290; height: alertCol.height
            radius: 24
            color: Theme.menu
            MouseArea { anchors.fill: parent }
            Column {
                id: alertCol
                width: parent.width
                Item { width: 1; height: 18 }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Yulduzli reaksiya")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Text {
                    x: 18; width: parent.width - 36
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: Tr.f("«%1» postiga ⭐ %2 yulduzli reaksiya yuborilsinmi?", sheet.channelTitle, sheet.fmt(sheet.amount))
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Item { width: 1; height: 16 }
                Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                Row {
                    width: parent.width; height: 46
                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        color: noHit.pressed ? Theme.highlight : "transparent"
                        Text { anchors.centerIn: parent; text: Tr.t("Bekor qilish"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 17 }
                        MouseArea { id: noHit; anchors.fill: parent; onClicked: confirm.visible = false }
                    }
                    Rectangle { width: 0.5; height: parent.height; color: Theme.separator }
                    Rectangle {
                        width: parent.width / 2 - 0.5; height: parent.height
                        color: yesHit.pressed ? Theme.highlight : "transparent"
                        Text { anchors.centerIn: parent; text: Tr.t("Yuborish"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                        MouseArea { id: yesHit; anchors.fill: parent; onClicked: { confirm.visible = false; sheet.sendPaid() } }
                    }
                }
            }
        }
    }

    YAnimator {
        id: rise
        target: panel
        duration: 420
        easing.type: Easing.BezierSpline
        easing.bezierCurve: sheet.spring
        onFinished: if (sheet.open) panel.y = sheet.height - panel.height + 40
    }
    ParallelAnimation {
        id: fall
        YAnimator { id: down; target: panel; duration: 240; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 240 }
        onFinished: sheet.visible = false
    }
}
