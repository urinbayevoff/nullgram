// Channel Direct Messages settings (Telegram-iOS's ChannelDirectMessagesSettingsController): enable/disable
// direct messages to the channel (setChatDirectMessagesGroup), optionally charge Telegram Stars per message
// (when supergroupFullInfo.can_enable_paid_messages) with a StepSlider (1..10K ⭐) and creator earnings note,
// and quick link to open the DM inbox (DirectTopicsPage).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    property var full: null                 // channel's supergroupFullInfo
    readonly property var chat: (store.seen, store.chats[chatId])
    readonly property var group: (store.seen, store.groupOf(chat))
    readonly property var dmChatId: full ? (full.direct_messages_chat_id || 0) : 0
    readonly property var dmChat: dmChatId ? (store.seen, store.chats[dmChatId]) : null
    readonly property var dmGroup: dmChat ? (store.seen, store.groupOf(dmChat)) : null
    readonly property bool canPaid: !!(full && full.can_enable_paid_messages)

    property bool enabledDm: false
    property bool paidOn: false
    property int starIdx: 2                 // default 10 ⭐
    property int maxStars: 10000
    property int perMille: 850              // getOption("paid_message_earnings_per_mille")
    property bool saving: false
    readonly property var allSteps: [1, 5, 10, 50, 100, 500, 1000, 5000, 10000]
    readonly property var starSteps: allSteps.filter((v) => v <= maxStars)
    readonly property int chosenStars: enabledDm && paidOn ? (starSteps[Math.min(starIdx, starSteps.length - 1)] || 10) : 0

    title: Tr.t("Kanalga xabarlar")
    action: Tr.t("Saqlash")
    actionBold: true
    actionOn: !saving
    onActed: save()

    Component.onCompleted: {
        enabledDm = !!(group && group.has_direct_messages_group)
        const cur = dmGroup ? (dmGroup.paid_message_star_count || 0) : 0
        if (cur > 0) {
            paidOn = true
            let best = 0
            for (let i = 0; i < allSteps.length; i++)
                if (allSteps[i] <= cur)
                    best = i
            starIdx = best
        }
        store.send({ "@type": "getOption", name: "paid_message_star_count_max" }, (r) => {
            if (page && r["@type"] === "optionValueInteger" && Number(r.value) > 0)
                page.maxStars = Number(r.value)
        })
        store.send({ "@type": "getOption", name: "paid_message_earnings_per_mille" }, (r) => {
            if (page && r["@type"] === "optionValueInteger" && Number(r.value) > 0)
                page.perMille = Number(r.value)
        })
        if (dmChatId && !dmChat)
            store.send({ "@type": "getChat", chat_id: dmChatId }, () => {})
    }
    onDmGroupChanged: {
        if (!saving && dmGroup && dmGroup.paid_message_star_count > 0 && !paidOn) {
            paidOn = true
            let best = 0
            for (let i = 0; i < allSteps.length; i++)
                if (allSteps[i] <= dmGroup.paid_message_star_count)
                    best = i
            starIdx = best
        }
    }

    function save() {
        saving = true
        const stars = enabledDm && paidOn ? chosenStars : 0
        store.send({ "@type": "setChatDirectMessagesGroup", chat_id: chatId,
                     is_enabled: enabledDm, paid_message_star_count: stars }, (r) => {
            page.saving = false
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.say(Tr.t(page.enabledDm ? "Kanalga xabarlar saqlandi" : "Kanalga xabarlar o'chirildi"))
            page.nav.pop()
        })
    }

    // ---- header illustration + explanation ----
    Item { width: 1; height: 8 }
    Column {
        width: parent.width
        spacing: 10
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76; height: 76; radius: 22
            gradient: Gradient {
                GradientStop { position: 0; color: "#5ac8fa" }
                GradientStop { position: 1; color: "#007aff" }
            }
            Icon { anchors.centerIn: parent; width: 42; height: 42; name: "direct"; color: "white" }
        }
        Text {
            x: 24; width: parent.width - 48
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: Tr.t("Obunachilar kanal egasi va adminlariga alohida suhbat orqali shaxsiy xabar yoza oladi.")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 14
        }
        Item { width: 1; height: 4 }
    }

    // ---- enable switch ----
    SettingsGroup {
        note: Tr.t("Yoqilsa, kanal ostida xabar yuborish tugmasi paydo bo'ladi va kelgan xabarlar alohida qutida jamlanadi.")
        SettingsRow {
            icon: "direct"; tint: "#007aff"
            text: Tr.t("Kanalga xabarlarni yoqish")
            toggle: true; chevron: false; last: true
            on: page.enabledDm
            onClicked: page.enabledDm = !page.enabledDm
        }
    }

    // ---- paid messages pricing ----
    SettingsGroup {
        visible: page.enabledDm
        title: Tr.t("Xabarlar narxi")
        note: page.paidOn
            ? Tr.f("Obunachilar har bir xabar uchun ⭐ %1 to'laydi. Kanal daromadi: %2%.",
                   store.count(page.chosenStars), Math.round(page.perMille / 10))
            : Tr.t("Obunachilar kanalga bepul xabar yoza oladi. Spamni cheklash uchun yulduzli narx belgilashingiz mumkin.")
        SettingsRow {
            art: "stars"
            text: Tr.t("Xabarlar uchun yulduz")
            toggle: true; chevron: false
            dim: !page.canPaid
            on: page.paidOn
            last: !page.paidOn
            onClicked: {
                if (!page.canPaid)
                    return page.nav.say(Tr.t("Bu kanalda pullik xabarlar hali mavjud emas."))
                page.paidOn = !page.paidOn
            }
        }
        Item {
            visible: page.paidOn
            width: parent.width; height: visible ? 116 : 0
            Text {
                x: 16; y: 12
                text: Tr.f("Har bir xabar uchun: ⭐ %1", store.count(page.chosenStars))
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
            }
            StepSlider {
                x: 16; y: 38
                width: parent.width - 32
                labels: page.starSteps.map((v) => v >= 1000 ? (v / 1000) + "K" : String(v))
                value: Math.min(page.starIdx, page.starSteps.length - 1)
                onMoved: (i) => page.starIdx = i
            }
        }
    }

    // ---- open inbox shortcut ----
    SettingsGroup {
        visible: page.enabledDm && page.dmChatId !== 0
        SettingsRow {
            icon: "chats"; tint: "#34c759"
            text: Tr.t("Kelgan xabarlarni ochish")
            value: page.dmChat && page.dmChat.unread_count > 0 ? String(page.dmChat.unread_count) : ""
            last: true
            onClicked: store.openDirectMessages(page.dmChatId, page.nav, page.chatId)
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
