// «Yulduz olish» (Telegram-iOS's StarsPurchaseScreen): the packs getStarPaymentOptions gives — «⭐ 50» «0,99 US$», the
// rest under «Ko'proq variantlar» (is_additional) — or, with `userId`, getStarGiftPaymentOptions' for a gift to them.
// Paying goes through Apple / Google stores (store_product_id), which OmonullOS has not: a pack tapped says so and
// offers @PremiumBot, which sells Stars too.
import QtQuick
import "Money.js" as Money

SubPage {
    id: page
    property real userId: 0
    property var packs: []
    property bool more: false
    property bool loaded: false
    readonly property var user: userId ? store.users[userId] : null
    title: userId ? Tr.t("Yulduz sovg'a qilish") : Tr.t("Yulduz olish")

    Component.onCompleted: store.send(userId ? { "@type": "getStarGiftPaymentOptions", user_id: userId }
                                             : { "@type": "getStarPaymentOptions" }, (r) => {
        page.packs = (r.options || []).sort((a, b) => a.star_count - b.star_count)
        page.loaded = true
    })
    readonly property var shown: more ? packs : packs.filter((p) => !p.is_additional)
    function money(o) { return Money.money(o.amount, o.currency, Tr.en) }
    function buy(o) {
        alert.show("⭐ " + o.star_count,
                   Tr.t("OmonullOS'da App Store yoki Google Play yo'q, shu sababli bu yerdan to'lab bo'lmaydi. Yulduzlarni @PremiumBot orqali olish mumkin."),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Ochish"), run: () =>
                       store.send({ "@type": "searchPublicChat", username: "PremiumBot" }, (c) => {
                           if (c["@type"] === "chat")
                               nav.push(Qt.createComponent("ChatPage.qml"), { chatId: c.id })
                       }) }])
    }

    PromoHead {
        title: page.userId ? Tr.t("Yulduz sovg'a qilish") : "Telegram Stars"
        stops: ["#f9a51c", "#fdc12f", "#ffd94a"]
        text: page.userId
            ? Tr.f("<b>%1</b> ga yulduz sovg'a qiling — ular bilan mini ilovalarda kontent va xizmatlarni ochadi.",
                   page.user ? [page.user.first_name, page.user.last_name].filter((s) => s).join(" ") : "…")
            : Tr.t("Telegram'dagi mini ilovalarda kontent va xizmatlarni ochish uchun yulduzlar sotib oling.")
    }

    SettingsGroup {
        visible: page.shown.length > 0
        Repeater {
            model: page.shown
            SettingsRow {
                required property var modelData
                required property int index
                text: "⭐  " + modelData.star_count.toLocaleString(Qt.locale(), "f", 0) + " " + Tr.t("yulduz")
                value: page.money(modelData)
                chevron: false
                last: index === page.shown.length - 1 && (page.more || !page.packs.some((p) => p.is_additional))
                onClicked: page.buy(modelData)
            }
        }
        SettingsRow {
            visible: !page.more && page.packs.some((p) => p.is_additional)
            text: Tr.t("Ko'proq variantlar") + "  ⌄"
            accent: true; chevron: false; last: true
            onClicked: page.more = true
        }
    }
    Text {
        visible: page.loaded && !page.packs.length
        x: 32; width: parent.width - 64
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: Tr.t("Hozir sotib olish variantlari yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
