// «Ikki baravar limitlar» (Telegram-iOS's PremiumLimitsListScreen): each limit getPremiumFeatures gave, its name and
// words, then a bar: «Bepul N» in grey on the left half, «Premium M» on iOS's purple run on the right.
import QtQuick

SubPage {
    id: page
    property var limits: []
    title: Tr.t("Ikki baravar limitlar")
    readonly property var about: ({
        premiumLimitTypeSupergroupCount: ["Guruhlar va kanallar", "%1 tagacha guruh va kanalga qo'shiling"],
        premiumLimitTypePinnedChatCount: ["Qadalgan chatlar", "Asosiy ro'yxatda %1 tagacha chatni qadang"],
        premiumLimitTypeCreatedPublicChatCount: ["Ommaviy havolalar", "%1 tagacha t.me/nom havolasi oling"],
        premiumLimitTypeSavedAnimationCount: ["Saqlangan GIF'lar", "%1 tagacha GIF saqlang"],
        premiumLimitTypeFavoriteStickerCount: ["Sevimli stikerlar", "%1 tagacha stikerni sevimlilarga qo'shing"],
        premiumLimitTypeChatFolderCount: ["Papkalar", "%1 tagacha papka tuzing"],
        premiumLimitTypeChatFolderChosenChatCount: ["Papkadagi chatlar", "Har papkaga %1 tagacha chat qo'shing"],
        premiumLimitTypePinnedArchivedChatCount: ["Arxivda qadalganlar", "Arxivda %1 tagacha chatni qadang"],
        premiumLimitTypePinnedSavedMessagesTopicCount: ["Saqlanganlarda qadalganlar", "Saqlangan xabarlarda %1 tagacha chatni qadang"],
        premiumLimitTypeMessageTextLength: ["Xabar uzunligi", "Xabarda %1 tagacha belgi"],
        premiumLimitTypeCaptionLength: ["Media izohi", "Media izohida %1 tagacha belgi"],
        premiumLimitTypeBioLength: ["Bio", "Bioda %1 tagacha belgi va havola"],
        premiumLimitTypeChatFolderInviteLinkCount: ["Papka havolalari", "Har papkaga %1 tagacha taklif havolasi"],
        premiumLimitTypeShareableChatFolderCount: ["Ulashilgan papkalar", "%1 tagacha papkaga qo'shiling"],
        premiumLimitTypeActiveStoryCount: ["Faol hikoyalar", "Bir vaqtda %1 tagacha hikoya"],
        premiumLimitTypeWeeklyPostedStoryCount: ["Haftalik hikoyalar", "Haftasiga %1 tagacha hikoya joylang"],
        premiumLimitTypeMonthlyPostedStoryCount: ["Oylik hikoyalar", "Oyiga %1 tagacha hikoya joylang"],
        premiumLimitTypeStoryCaptionLength: ["Hikoya izohi", "Hikoya izohida %1 tagacha belgi"],
        premiumLimitTypeStorySuggestedReactionAreaCount: ["Hikoyadagi reaksiyalar", "Hikoyaga %1 tagacha reaksiya joyi"],
        premiumLimitTypeSimilarChatCount: ["O'xshash kanallar", "%1 tagacha o'xshash kanalni ko'ring"],
        premiumLimitTypeOwnedBotCount: ["Botlar", "%1 tagacha bot yarating"],
        premiumLimitTypeCustomTextCompositionStyleCount: ["Matn uslublari", "%1 tagacha o'z uslubingiz"]
    })
    readonly property var shown: limits.filter((l) => about[l.type["@type"]] && l.premium_value > l.default_value)

    Repeater {
        model: page.shown
        Item {
            id: lim
            required property var modelData
            readonly property var a: page.about[modelData.type["@type"]]
            x: 16; width: parent.width - 32; height: bar.y + bar.height
            Text {
                id: name
                text: Tr.t(lim.a[0])
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                id: words
                y: name.height + 2; width: parent.width
                wrapMode: Text.Wrap
                text: Tr.f(lim.a[1], lim.modelData.premium_value)
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
            Item {          // the bar: its outer ends rounded (each half round, a square patch where they meet)
                id: bar
                y: words.y + words.height + 8
                width: parent.width; height: 30
                readonly property color free: Theme.dark ? "#3a3a3c" : "#e5e5ea"
                Rectangle { width: parent.width / 2; height: 30; radius: 8; color: bar.free }
                Rectangle { x: parent.width / 2 - 10; width: 10; height: 30; color: bar.free }
                Rectangle {
                    x: parent.width / 2; width: parent.width / 2; height: 30; radius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#8878ff" }
                        GradientStop { position: 1; color: "#e46ace" }
                    }
                }
                Rectangle { x: parent.width / 2; width: 10; height: 30; color: "#8878ff" }
                Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Bepul"); color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { x: parent.width / 2 - width - 10; anchors.verticalCenter: parent.verticalCenter; text: lim.modelData.default_value; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { x: parent.width / 2 + 10; anchors.verticalCenter: parent.verticalCenter; text: "Premium"; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: lim.modelData.premium_value; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            }
        }
    }
}
