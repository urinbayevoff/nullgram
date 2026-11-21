// The language Nullgram speaks, laid out as Telegram-iOS's LocalizationListControllerNode: «TARJIMA» first
// (Localization.ShowTranslate — «Tarjima qilish» in a message's menu; Localization.TranslateEntireChat — the chat's
// panel; iOS's note under them), then «INTERFEYS TILI», each a LocalizationListItem: its name (17 → our 16) and
// under it the name in its own words (13), 12 above and below, ✓ in the accent at the right. Ours are omonullOS
// Settings' own language and the two Nullgram has words for. (Telegram's search over its ~70 languages and
// «Do Not Translate» are left out: we have two.)
import QtQuick

SubPage {
    id: page
    title: Tr.t("Til")

    SettingsGroup {
        title: Tr.t("Xabarlarni tarjima qilish")
        note: Tr.t("Xabar menyusida «Tarjima qilish» tugmasini ko'rsatish.\n\nGoogle siz tarjima qilgan matnni ko'rishi mumkin.")
        SettingsRow {
            text: Tr.t("Tarjima tugmasini ko'rsatish")
            toggle: true; on: Prefs.translateButton
            onClicked: Prefs.translateButton = !Prefs.translateButton
        }
        SettingsRow {
            text: Tr.t("Butun chatni tarjima qilish")
            toggle: true; on: Prefs.translateChats; last: true
            onClicked: Prefs.translateChats = !Prefs.translateChats
        }
    }

    SettingsGroup {
        title: Tr.t("Interfeys tili")
        note: Tr.t("Tizim tili omonullOS Sozlamalaridan olinadi.")
        Repeater {
            model: [{ k: "", name: Tr.t("Tizim tili"),
                      own: Tr.system === "en" ? "English" : "O'zbekcha" },
                    { k: "uz", name: Tr.t("O'zbekcha"), own: "O'zbekcha" },
                    { k: "en", name: Tr.t("Inglizcha"), own: "English" }]
            Item {
                id: lang
                required property var modelData
                required property int index
                readonly property bool chosen: Prefs.lang === modelData.k
                width: parent.width
                height: 12 + nameText.height + 1 + ownText.height + 12
                Rectangle { anchors.fill: parent; color: Theme.highlight; visible: langHit.pressed }
                Text {
                    id: nameText
                    x: 16; y: 12; width: parent.width - 16 - 44
                    elide: Text.ElideRight
                    text: lang.modelData.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                }
                Text {
                    id: ownText
                    x: 16; y: nameText.y + nameText.height + 1; width: nameText.width
                    elide: Text.ElideRight
                    text: lang.modelData.own
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                }
                Icon {
                    visible: lang.chosen
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    name: "check"
                    color: Theme.accent
                }
                Rectangle {
                    visible: lang.index < 2
                    x: 16; anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
                MouseArea { id: langHit; anchors.fill: parent; onClicked: Prefs.lang = lang.modelData.k }
            }
        }
    }
}
