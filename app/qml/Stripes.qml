// A quote's bar on its left (Telegram-iOS's reply and link bars): the first colour, and with a second (a third) the
// bar dashed by them as a name's colours are (PeerNameColors' secondary, tertiary). Put in a clipped quote.
import QtQuick

Rectangle {
    id: bar
    property var colors: []
    width: 3; height: parent ? parent.height : 0
    color: colors[0] || Theme.accent
    Column {
        visible: bar.colors.length > 1
        y: -3
        Repeater {
            model: Math.ceil((bar.height + 6) / 9)
            Item {
                required property int index
                width: 3; height: 9
                Rectangle { width: 3; height: 4.5; y: 4.5; color: bar.colors[bar.colors.length > 2 && index % 2 ? 2 : 1] || "transparent" }
            }
        }
    }
}
