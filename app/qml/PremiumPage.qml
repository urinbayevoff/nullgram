// «Telegram Premium» (Telegram-iOS's PremiumIntroScreen, as the owner's #26493–94): the purple star over sparkles,
// «Go beyond the limits…» (or, subscribed, getPremiumState's own words: when it renews), the plans (getPremiumState's
// payment options: ✓ Annual «-35%» «12 months · 29,99 US$» «2,49 US$/month», Monthly) and «NIMALAR KIRADI»: the
// features getPremiumFeatures names, each on its square of iOS's orange-to-blue run. «Ikki baravar limitlar» opens the
// limits (Bepul / Premium, PremiumLimitsPage); the others tell what they are. The button at the foot: buying goes
// through Apple / Google stores, which OmonullOS has not, so it says so and offers @PremiumBot (the payment link).
import QtQuick
import "Money.js" as Money

SubPage {
    id: page
    property var plans: []              // premiumStatePaymentOption
    property int chosen: 0
    property var features: []
    property var limits: []
    property var link: null             // the features' payment_link (internalLinkTypeBotStart @PremiumBot …)
    property string state: ""
    readonly property bool premium: !!(store.me && store.me.is_premium)
    title: ""

    // iOS's list colours, top to bottom (PremiumIntroScreen's perk gradient)
    readonly property var run: ["#ef6922", "#e95a2c", "#e74e33", "#e54937", "#e3433c", "#db374b", "#cb3e6d", "#bc4395",
                                "#ab4ac4", "#9b4fed", "#8958ff", "#676bff", "#6172ff", "#5b79ff", "#4492ff", "#429bd5",
                                "#41a6a5", "#3eb26d", "#3dbd4a"]
    // a feature's icon, name and words (Telegram-iOS's strings, ours)
    readonly property var about: ({
        premiumFeatureUpgradedStories: ["playround", "Hikoyalar", "Cheksiz joylash, birinchi navbatda ko'rinish, yashirin rejim, doimiy ko'rishlar tarixi va boshqalar."],
        premiumFeatureIncreasedUploadFileSize: ["data", "Cheksiz bulut xotirasi", "Har bir hujjat 4 GB gacha, chatlar va media uchun cheksiz joy."],
        premiumFeatureIncreasedLimits: ["X2", "Ikki baravar limitlar", "1000 tagacha kanal, 30 papka, 10 qadalgan chat, 20 ommaviy havola, 4 akkaunt va boshqalar."],
        premiumFeatureBusiness: ["laptop", "Telegram Business", "Akkauntingizni biznes imkoniyatlari bilan kuchaytiring: joylashuv, ish vaqti, tezkor javoblar."],
        premiumFeatureLastSeenTimes: ["eye", "So'nggi faollik vaqti", "O'zingiznikini yashirgan bo'lsangiz ham boshqalarning so'nggi faolligini ko'ring."],
        premiumFeatureMessagePrivacy: ["lock", "Xabarlar maxfiyligi", "Kontaktingizda bo'lmaganlar sizga yozishidan oldin Premium olishi kerak bo'lsin."],
        premiumFeatureImprovedDownloadSpeed: ["down", "Tezroq yuklab olish", "Media va hujjatlarni yuklab olishda tezlik cheklanmaydi."],
        premiumFeatureVoiceRecognition: ["mic", "Ovozni matnga aylantirish", "Har qanday ovozli va dumaloq video xabarni matn ko'rinishida o'qing."],
        premiumFeatureRealTimeChatTranslation: ["translate", "Tarjima", "Butun chatlarni bir bosishda real vaqtda tarjima qiling."],
        premiumFeatureDisabledAds: ["cross", "Reklamasiz", "Ommaviy kanallardagi homiylik xabarlari endi ko'rinmaydi."],
        premiumFeatureUniqueReactions: ["sparkle", "Cheksiz reaksiyalar", "Minglab emojilar bilan reaksiya qiling — har xabarga 3 tagacha."],
        premiumFeatureUniqueStickers: ["ghost", "Premium stikerlar", "Har oy qo'shiladigan maxsus animatsiyali stikerlar."],
        premiumFeatureCustomEmoji: ["hand", "Animatsiyali emoji", "Xabar va izohlarga yuzlab to'plamdagi animatsiyali emojilarni qo'ying."],
        premiumFeatureAdvancedChatManagement: ["folder", "Chatlarni boshqarish", "Asosiy papkani almashtirish, yangi chatlarni avtomatik arxivlash va boshqa vositalar."],
        premiumFeatureProfileBadge: ["star", "Premium belgisi", "Ismingiz yonidagi alohida belgi sizni Telegram'ni qo'llab-quvvatlovchi sifatida ko'rsatadi."],
        premiumFeatureEmojiStatus: ["sparkle", "Emoji holatlar", "Ismingiz yoniga minglab emojidan birini, animatsiyali ham, qo'ying."],
        premiumFeatureAnimatedProfilePhoto: ["person", "Animatsiyali profil rasmi", "Hamma chatlarda — ro'yxatda ham — harakatlanadigan video avatar."],
        premiumFeatureForumTopicIcon: ["chats", "Mavzu ikonkalari", "Guruh mavzularini animatsiyali emojilar bilan belgilang."],
        premiumFeatureAppIcons: ["settings", "Qo'shimcha ilova ikonkalari", "Telefoningiz ekrani uchun Telegram'ning maxsus ikonkalari."],
        premiumFeatureChatBoost: ["bell", "Kanallarni kuchaytirish", "Sevimli kanallaringizga qo'shimcha imkoniyatlar ochishga yordam bering."],
        premiumFeatureAccentColor: ["halfmoon", "Ism va profil ranglari", "Ismingiz, havolalaringiz va profilingiz uchun rang va belgini tanlang."],
        premiumFeatureBackgroundForBoth: ["globe", "Ikki tomonga fon", "Suhbatdoshingiz uchun ham chat fon rasmini o'rnating."],
        premiumFeatureSavedMessagesTags: ["bookmark", "Saqlanganlar teglari", "Saqlangan xabarlarni emoji teglar bilan tartiblang va tez toping."],
        premiumFeatureMessageEffects: ["sparkle", "Xabar effektlari", "Shaxsiy chatlarda yuborilgan xabarlarga animatsiyali effekt qo'shing."],
        premiumFeatureChecklists: ["check", "Vazifalar ro'yxati", "Chatda vazifalar ro'yxatini tuzing va bajarilganini belgilang."],
        premiumFeaturePaidMessages: ["star", "Pullik xabarlar", "Notanishlar sizga yozishi uchun yulduzlarda narx qo'ying."],
        premiumFeatureProtectPrivateChatContent: ["lock", "Chatni himoyalash", "Shaxsiy chatdagi xabarlarni nusxalash va uzatishni taqiqlang."],
        premiumFeatureTextComposition: ["quote", "Matn uslublari", "Xabarlarni yozishda qo'shimcha uslublardan foydalaning."],
        premiumFeatureRichMessages: ["quote", "Boy xabarlar", "Xabarlarga ko'proq bezak va formatlash qo'shing."]
    })
    function feature(f) { return about[f["@type"]] || ["star", f["@type"].replace("premiumFeature", ""), ""] }

    function money(amount, currency) { return Money.money(amount, currency, Tr.en) }
    function perMonth(o) { return money(Math.floor(o.amount / Math.max(1, o.month_count)), o.currency) }     // (iOS: 29,99/12 → 2,49)
    function planName(o) {
        return o.month_count === 12 ? Tr.t("Yillik") : o.month_count === 1 ? Tr.t("Oylik")
             : o.month_count === 6 ? Tr.t("Yarim yillik") : Tr.f("%1 oylik", o.month_count)
    }
    function load() {
        store.send({ "@type": "getPremiumState" }, (r) => {
            if (r["@type"] !== "premiumState")
                return
            page.state = r.state ? r.state.text : ""
            page.plans = (r.payment_options || []).map((p) => p.payment_option)
                .sort((a, b) => b.month_count - a.month_count)
            page.chosen = 0
        })
        store.send({ "@type": "getPremiumFeatures", source: { "@type": "premiumSourceSettings" } }, (r) => {
            if (r["@type"] !== "premiumFeatures")
                return
            page.features = r.features || []
            page.limits = r.limits || []
            page.link = r.payment_link
        })
    }
    Component.onCompleted: load()

    function open(f) {
        if (f["@type"] === "premiumFeatureIncreasedLimits")
            nav.push(Qt.createComponent("PremiumLimitsPage.qml"), { limits: page.limits })
        else {
            const a = feature(f)
            alert.show(Tr.t(a[1]), Tr.t(a[2]), [{ t: Tr.t("Yopish") }])
        }
    }
    function subscribe() {
        const l = page.link
        const bot = l && l["@type"] === "internalLinkTypeBotStart" ? l.bot_username : "PremiumBot"
        alert.show(Tr.t("Obuna bo'lish"),
                   Tr.f("OmonullOS'da App Store yoki Google Play yo'q, shu sababli bu yerdan to'lab bo'lmaydi. Premium'ni @%1 orqali olish mumkin.", bot),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Ochish"), run: () => page.openBot(bot) }])
    }
    function openBot(bot) {
        store.send({ "@type": "searchPublicChat", username: bot }, (c) => {
            if (c["@type"] === "chat")
                nav.push(Qt.createComponent("ChatPage.qml"), { chatId: c.id })
        })
    }

    PromoHead {
        title: "Telegram Premium"
        text: page.premium
            ? (page.state ? page.state : Tr.t("Hammasi tayyor! Telegram Premium'ga obuna bo'lganingiz uchun rahmat. Mana sizda bor imkoniyatlar."))
            : Tr.t("<b>Limitlardan</b> chiqing va Telegram'ga obuna bo'lib <b>o'nlab</b> alohida imkoniyatni oching.")
    }

    SettingsGroup {             // the plans
        visible: !page.premium && page.plans.length > 0
        Repeater {
            model: page.plans
            Item {
                id: plan
                required property var modelData
                required property int index
                readonly property int off: modelData.discount_percentage || 0
                width: parent ? parent.width : 300; height: off || modelData.month_count > 1 ? 62 : 52
                Rectangle { anchors.fill: parent; color: Theme.highlight; visible: planHit.pressed }
                Rectangle {             // the round ✓
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 12
                    color: page.chosen === plan.index ? Theme.accent : "transparent"
                    border.width: page.chosen === plan.index ? 0 : 1.5; border.color: Theme.grey
                    Icon { anchors.centerIn: parent; width: 16; height: 16; visible: page.chosen === plan.index; name: "check"; color: "white" }
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - price.width - 28
                    Row {
                        spacing: 6
                        Text {
                            text: page.planName(plan.modelData)
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 17
                        }
                        Rectangle {
                            visible: plan.off > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: offText.width + 8; height: 19; radius: 4
                            color: Theme.accent
                            Text {
                                id: offText
                                anchors.centerIn: parent
                                text: "-" + plan.off + "%"
                                color: "white"
                                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                        }
                    }
                    Text {
                        visible: plan.modelData.month_count > 1
                        width: parent.width; elide: Text.ElideRight
                        text: Tr.f("%1 oy", plan.modelData.month_count) + " · " + page.money(plan.modelData.amount, plan.modelData.currency)
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                Text {
                    id: price
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.perMonth(plan.modelData) + Tr.t("/oy")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 17
                }
                Rectangle { visible: plan.index < page.plans.length - 1; x: 56; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
                MouseArea { id: planHit; anchors.fill: parent; onClicked: page.chosen = plan.index }
            }
        }
    }

    SettingsGroup {             // what comes with it
        visible: page.features.length > 0
        title: Tr.t("NIMALAR KIRADI")
        Repeater {
            model: page.features
            Item {
                id: perk
                required property var modelData
                required property int index
                readonly property var a: page.feature(modelData)
                width: parent ? parent.width : 300
                height: Math.max(56, words.height + 20)
                Rectangle { anchors.fill: parent; color: Theme.highlight; visible: perkHit.pressed }
                Rectangle {
                    x: 16; y: 12
                    width: 30; height: 30; radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0; color: page.run[Math.min(perk.index, page.run.length - 1)] }
                        GradientStop { position: 1; color: page.run[Math.min(perk.index + 1, page.run.length - 1)] }
                    }
                    Icon {
                        visible: perk.a[0] !== "X2"
                        anchors.centerIn: parent
                        width: 20; height: 20
                        name: perk.a[0]
                        color: "white"
                    }
                    Text {
                        visible: perk.a[0] === "X2"
                        anchors.centerIn: parent
                        text: "X2"
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Black
                    }
                }
                Column {
                    id: words
                    x: 60; y: 10
                    width: parent.width - x - 36
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: Tr.t(perk.a[1])
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: Tr.t(perk.a[2])
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 24
                }
                Rectangle { visible: perk.index < page.features.length - 1; x: 60; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
                MouseArea { id: perkHit; anchors.fill: parent; onClicked: page.open(perk.modelData) }
            }
        }
    }
    Item { width: 1; height: page.premium ? 0 : 70 }        // (room for the button)

    Rectangle {                 // «Subscribe for 29,99 US$ / year», floating over the list's foot
        parent: page
        visible: !page.premium && page.plans.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + safe.bottom
        width: parent.width - 32; height: 50; radius: 25
        opacity: buyHit.pressed ? 0.7 : 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#6b93ff" }
            GradientStop { position: 0.5; color: "#8878ff" }
            GradientStop { position: 1; color: "#e46ace" }
        }
        Text {
            anchors.centerIn: parent
            readonly property var o: page.plans[page.chosen]
            text: o ? Tr.f("Obuna bo'lish: %1", page.money(o.amount, o.currency)) +
                      (o.month_count === 12 ? Tr.t(" / yil") : o.month_count === 1 ? Tr.t(" / oy") : "") : ""
            color: "white"
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
        MouseArea { id: buyHit; anchors.fill: parent; onClicked: page.subscribe() }
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
