// «Telegram Stars» (Telegram-iOS's StarsTransactionsScreen, as the owner's #26495): the gold star over sparkles, the
// balance card («⭐ N», «balansingiz», «Yana yulduz olish», «Do'stlarga yulduz sovg'a qilish»), then the transactions
// (getStarTransactions; Hammasi / Kiruvchi / Chiquvchi): who, what for, when, «-20 ⭐» red / «+50 ⭐» green, more as
// the list nears its end. A row tapped tells its details. Buying: StarsBuyPage (the packs; paying needs a store).
import QtQuick

SubPage {
    id: page
    property int dir: 0                 // 0 all, 1 incoming, 2 outgoing
    property var rows: []
    property string next: ""
    property bool loading: false
    property bool loaded: false
    property real balance: store.stars
    property var photos: ({})
    property int got: 0
    title: ""

    function owner() { return { "@type": "messageSenderUser", user_id: store.me ? store.me.id : 0 } }
    function load(more) {
        if (loading || (more && !next))
            return
        loading = true
        const d = dir
        store.send({ "@type": "getStarTransactions", owner_id: owner(), subscription_id: "",
                     direction: d === 1 ? { "@type": "transactionDirectionIncoming" }
                              : d === 2 ? { "@type": "transactionDirectionOutgoing" } : null,
                     offset: more ? next : "", limit: 30 }, (r) => {
            page.loading = false
            if (r["@type"] !== "starTransactions" || d !== page.dir)
                return
            page.balance = store.stars = r.star_amount.star_count
            page.rows = (more ? page.rows : []).concat(r.transactions || [])
            page.next = r.next_offset || ""
            page.loaded = true
        })
    }
    onDirChanged: { rows = []; next = ""; loaded = false; loading = false; load(false) }
    Component.onCompleted: load(false)
    Connections {
        target: page.flick
        function onContentYChanged() {
            if (page.flick.contentY + page.flick.height > page.flick.contentHeight - 400)
                page.load(true)
        }
    }

    // who a transaction was with (a MessageSender), or null: Telegram's own (deposits, ads, …)
    function partner(t) {
        const y = t.type
        if (y.user_id) return { "@type": "messageSenderUser", user_id: y.user_id }
        if (y.chat_id) return { "@type": "messageSenderChat", chat_id: y.chat_id }
        return y.owner_id || y.sender_id || null
    }
    function source(t) {
        return ({ starTransactionTypePremiumBotDeposit: "Premium Bot", starTransactionTypeAppStoreDeposit: "App Store",
                  starTransactionTypeGooglePlayDeposit: "Google Play", starTransactionTypeFragmentDeposit: "Fragment",
                  starTransactionTypeFragmentWithdrawal: "Fragment", starTransactionTypeTelegramAdsWithdrawal: Tr.t("Telegram reklamasi"),
                  starTransactionTypeTelegramApiUsage: "Telegram API", starTransactionTypePublicPostSearch: Tr.t("Postlar qidiruvi") })[t.type["@type"]] || "Telegram"
    }
    function what(t) {
        const y = t.type, k = y["@type"]
        if (t.is_refund) return Tr.t("Qaytarildi")
        if (k.endsWith("Deposit") && k !== "starTransactionTypeUserDeposit" && k !== "starTransactionTypeGiveawayDeposit") return Tr.t("Yulduzlar sotib olindi")
        if (y.product_info) return y.product_info.title
        return Tr.t(({ starTransactionTypeUserDeposit: "Sovg'a qilingan yulduzlar", starTransactionTypeGiveawayDeposit: "Yutuq",
                       starTransactionTypeFragmentWithdrawal: "Yechib olindi", starTransactionTypeChannelSubscriptionPurchase: "Obuna",
                       starTransactionTypeChannelSubscriptionSale: "Obuna", starTransactionTypeBotPaidMediaPurchase: "Pullik media",
                       starTransactionTypeBotPaidMediaSale: "Pullik media", starTransactionTypeChannelPaidMediaPurchase: "Pullik media",
                       starTransactionTypeChannelPaidMediaSale: "Pullik media", starTransactionTypeGiftPurchase: "Sovg'a",
                       starTransactionTypeGiftSale: "Sovg'a sotildi", starTransactionTypeGiftUpgrade: "Sovg'a yangilandi",
                       starTransactionTypeGiftUpgradePurchase: "Sovg'a yangilandi", starTransactionTypeGiftTransfer: "Sovg'a uzatildi",
                       starTransactionTypeUpgradedGiftPurchase: "Noyob sovg'a", starTransactionTypeUpgradedGiftSale: "Noyob sovg'a sotildi",
                       starTransactionTypeGiftAuctionBid: "Auksion taklifi", starTransactionTypeChannelPaidReactionSend: "Yulduzli reaksiya",
                       starTransactionTypeChannelPaidReactionReceive: "Yulduzli reaksiya", starTransactionTypePremiumPurchase: "Telegram Premium",
                       starTransactionTypeAffiliateProgramCommission: "Hamkorlik komissiyasi", starTransactionTypePaidGroupCallMessageSend: "Efirdagi xabar",
                       starTransactionTypePaidGroupCallReactionSend: "Efirdagi reaksiya", starTransactionTypeSuggestedPostPaymentSend: "Taklif qilingan post",
                       starTransactionTypeSuggestedPostPaymentReceive: "Taklif qilingan post", starTransactionTypeBusinessBotTransferSend: "Biznes bot",
                       starTransactionTypeBusinessBotTransferReceive: "Biznes bot" })[k] || "")
            || (y.message_count ? Tr.f("%1 ta xabar uchun to'lov", y.message_count) : "")
    }
    function name(t) { const s = partner(t); return s ? store.senderName(s) || "…" : source(t) }
    function photoOf(s) {
        got
        if (!s) return ""
        const id = s.user_id || s.chat_id
        if (photos[id] !== undefined)
            return photos[id]
        photos[id] = ""
        if (s["@type"] === "messageSenderUser")
            store.userPhoto(store.users[id], (p) => { page.photos[id] = p; page.got++ })
        else {
            const c = store.chats[id]
            photos[id] = c ? store.photoPath(c) : ""
        }
        return photos[id]
    }
    function when(t) { return new Date(t.date * 1000).toLocaleString(Qt.locale(Tr.en ? "en_US" : "uz_UZ"), "d MMM, HH:mm") }
    function amount(t) {
        const n = t.star_amount.star_count + (t.star_amount.nanostar_count || 0) / 1e9
        return (n > 0 ? "+" : n < 0 ? "−" : "") + Math.abs(n).toLocaleString(Qt.locale(), "f", n % 1 ? 2 : 0)
    }
    function tell(t) {
        alert.show(name(t), [amount(t) + " ⭐", what(t), when(t), Tr.f("Tranzaksiya ID: %1", t.id)].filter((s) => s).join("\n"),
                   [{ t: Tr.t("Yopish") }])
    }
    function gift() {
        const p = nav.push(Qt.createComponent("FolderChatsPage.qml"), {
            heading: Tr.t("Yulduz sovg'a qilish"), chosen: [],
            pool: (c) => c.type["@type"] === "chatTypePrivate" && !store.isSaved(c) })
        if (p)
            p.done.connect((flags, ids) => {
                const c = ids.length ? store.chats[ids[0]] : null
                if (c)
                    Qt.callLater(() => nav.push(Qt.createComponent("StarsBuyPage.qml"), { userId: c.type.user_id }))
            })
    }

    PromoHead {
        title: "Telegram Stars"
        stops: ["#f9a51c", "#fdc12f", "#ffd94a"]
        text: Tr.t("Telegram'dagi mini ilovalarda kontent va xizmatlarni ochish uchun yulduzlar sotib oling.")
    }

    SettingsGroup {             // the balance card
        Item {
            width: parent ? parent.width : 300; height: 196
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18; spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "⭐"; font.pixelSize: 34 }
                Text {
                    text: page.balance < 0 ? "…" : Math.floor(page.balance).toLocaleString(Qt.locale(), "f", 0)
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 44; font.weight: Font.Bold
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 74
                text: Tr.t("balansingiz")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
            Rectangle {
                x: 16; y: 110; width: parent.width - 32; height: 48; radius: 24
                color: Theme.accent
                opacity: buyHit.pressed ? 0.7 : 1
                Text {
                    anchors.centerIn: parent
                    text: "⊕  " + Tr.t("Yana yulduz olish")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea { id: buyHit; anchors.fill: parent; onClicked: nav.push(Qt.createComponent("StarsBuyPage.qml"), {}) }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 166
                text: Tr.t("Do'stlarga yulduz sovg'a qilish")
                color: Theme.accent
                opacity: giftHit.pressed ? 0.4 : 1
                font.family: Theme.font; font.pixelSize: 17
                MouseArea { id: giftHit; anchors.fill: parent; anchors.margins: -8; onClicked: page.gift() }
            }
        }
    }

    Segments {
        x: 16; width: parent.width - 32
        visible: page.loaded && (page.rows.length > 0 || page.dir > 0)
        items: [Tr.t("Hammasi"), Tr.t("Kiruvchi"), Tr.t("Chiquvchi")]
        index: page.dir
        onPicked: (i) => page.dir = i
    }

    SettingsGroup {
        visible: page.rows.length > 0
        Repeater {
            model: page.rows
            Item {
                id: tx
                required property var modelData
                required property int index
                readonly property var who: page.partner(modelData)
                readonly property bool minus: modelData.star_amount.star_count < 0
                width: parent ? parent.width : 300; height: 72
                Rectangle { anchors.fill: parent; color: Theme.highlight; visible: txHit.pressed }
                Avatar {
                    visible: !!tx.who
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: page.photoOf(tx.who)
                    letters: store.letters(page.name(tx.modelData))
                    tint: store.tints[Math.abs(Number(tx.who ? tx.who.user_id || tx.who.chat_id : 0)) % store.tints.length]
                }
                Image {
                    visible: !tx.who
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: "settings-icons/stars.png"
                    sourceSize.width: 120; sourceSize.height: 120
                }
                Column {
                    x: 68; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - amt.width - 24
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: page.name(tx.modelData)
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width; elide: Text.ElideRight
                        text: page.what(tx.modelData)
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        text: page.when(tx.modelData)
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                Text {
                    id: amt
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.amount(tx.modelData) + " ⭐"
                    color: tx.minus ? "#ff3b30" : "#34c759"
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Rectangle { visible: tx.index < page.rows.length - 1; x: 68; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
                MouseArea { id: txHit; anchors.fill: parent; onClicked: page.tell(tx.modelData) }
            }
        }
    }
    Text {
        visible: page.loaded && !page.rows.length
        x: 32; width: parent.width - 64
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: Tr.t("Hali tranzaksiyalar yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
