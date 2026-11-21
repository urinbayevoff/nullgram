// A chat in small over the chats' background, as Telegram-iOS's ThemeSettingsChatPreviewItem (Bob Harris's two
// messages): the head of a settings card (its top corners the card's).
import QtQuick

Item {
    id: pane
    property string clock: Qt.formatTime(new Date(), "HH:mm")
    width: parent ? parent.width : 328; height: sample.height + 16
    clip: true
    Wallpaper { anchors.fill: parent }
    ChatSample {
        id: sample
        y: 8
        messages: [{ text: Tr.t("Soat necha bo'lganini bilasizmi?"), time: pane.clock,
                     reply: { name: "Bob Harris", text: Tr.t("Xayrli tong! 👋") } },
                   { out: true, text: Tr.t("Tokioda hozir tong 😎"), time: pane.clock }]
    }
    Rectangle {         // the card's top corners over it (a clip is square)
        x: -12; y: -12; width: parent.width + 24; height: parent.height + 60
        radius: 24
        color: "transparent"
        border.width: 12; border.color: Theme.grouped
    }
}
