// A few messages to show a background and the bubbles over it, as Telegram-iOS's ThemeSettingsChatPreviewItem and
// the wallpaper gallery's: [{ out, text, time, name, colors, reply: { name, text }, link: { site, title, text } }], one
// under another, last at the bottom; the bubbles nullgram_app.py's (Bubble), their colours the theme's. `name` over the
// words, and `colors` (Your Color: "#rrggbb" one to three) its, the quote's and the link's — the bar striped by the others.
import QtQuick
import QtQuick.Window

Column {
    id: sample
    property var messages: []
    property real size: Prefs.chatSize  // the words' (iOS: the chat's font size; Matn o'lchami)
    property int radius: Prefs.bubbleR  // the bubbles' corners, big and small (Xabar burchaklari)
    property int small: Prefs.bubbleS
    spacing: 4
    width: parent ? parent.width : 360

    Repeater {
        model: sample.messages
        Item {
            id: msg
            required property var modelData
            required property int index
            readonly property bool out: !!modelData.out
            readonly property bool last: index === sample.messages.length - 1 || !!sample.messages[index + 1].out !== out
            readonly property bool first: index === 0 || !!sample.messages[index - 1].out !== out
            readonly property var colors: modelData.colors || [Theme.accent]
            readonly property real inner: Math.min(sample.width * 0.75, Math.max(words.implicitWidth + 12 + stamp.width,
                                                   quote.visible ? quote.implicitW + 8 : 0, who.visible ? who.implicitWidth : 0) + 24)
            width: sample.width; height: box.height
            Item {
                id: box
                x: msg.out ? sample.width - width - 14 : 14
                width: msg.inner
                height: (who.visible ? who.height + 2 : 0) + (quote.visible ? quote.height + 6 : 0) + words.height + 14
                        + (link.visible ? link.height + 6 : 0)
                BorderImage {
                    readonly property real d: Screen.devicePixelRatio
                    x: msg.out ? 0 : -6
                    width: (parent.width + 6) * d; height: parent.height * d
                    scale: 1 / d; transformOrigin: Item.TopLeft
                    readonly property int r: sample.radius
                    readonly property int b: Math.max(r, 10)    // (nullgram_app.py Bubble: the tail's room)
                    border { left: (msg.out ? r : b + 6) * d; right: (msg.out ? b + 6 : r) * d; top: r * d; bottom: b * d }
                    source: "image://bubble/" + (msg.out ? "out/" : "in/") + (msg.first ? "b/" : "s/") + (msg.last ? "t/" : "s/")
                            + String(msg.out ? Theme.bubbleOut : Theme.bubbleIn).slice(1) + "/" + d + "/" + r + "/" + sample.small
                    smooth: true
                }
                Text {              // the sender's name (Your Color)
                    id: who
                    visible: !!msg.modelData.name
                    x: 12; y: 6; width: parent.width - 24
                    elide: Text.ElideRight
                    text: msg.modelData.name || ""
                    color: msg.colors[0]
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Rectangle {         // a reply's quote: the name's colour, a bar on its left
                    id: quote
                    visible: !!msg.modelData.reply
                    readonly property real implicitW: Math.max(qName.implicitWidth, qText.implicitWidth) + 18
                    readonly property color ink: msg.colors[0]
                    x: 6; y: who.visible ? who.y + who.height + 2 : 6
                    width: parent.width - 12; height: qName.height + qText.height + 8
                    radius: 6
                    color: Qt.rgba(ink.r, ink.g, ink.b, 0.1)
                    clip: true
                    Stripes { colors: msg.colors }
                    Text {
                        id: qName
                        x: 10; y: 4; width: parent.width - 14
                        elide: Text.ElideRight
                        text: msg.modelData.reply ? msg.modelData.reply.name : ""
                        color: quote.ink
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        id: qText
                        x: 10; y: qName.y + qName.height; width: parent.width - 14
                        elide: Text.ElideRight
                        text: msg.modelData.reply ? msg.modelData.reply.text : ""
                        color: msg.out ? Theme.outText : Theme.inText
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }
                Text {
                    id: words
                    x: 12; y: quote.visible ? quote.y + quote.height + 4 : who.visible ? who.y + who.height + 1 : 7
                    width: Math.min(implicitWidth, parent.width - 24 - stamp.width - 6)
                    wrapMode: Text.Wrap
                    text: msg.modelData.text
                    color: msg.out ? Theme.outText : Theme.inText
                    font.family: Theme.font; font.pixelSize: sample.size
                }
                Rectangle {         // a link's preview: the site in the colour, its title, its words
                    id: link
                    visible: !!msg.modelData.link
                    readonly property color ink: msg.colors[0]
                    x: 6; y: words.y + words.height + 6
                    width: parent.width - 12; height: lCol.height + 8
                    radius: 6
                    color: Qt.rgba(ink.r, ink.g, ink.b, 0.1)
                    clip: true
                    Stripes { colors: msg.colors }
                    Column {
                        id: lCol
                        x: 10; y: 4; width: parent.width - 14
                        Repeater {
                            model: msg.modelData.link ? [[msg.modelData.link.site, true], [msg.modelData.link.title, true],
                                                         [msg.modelData.link.text, false]] : []
                            Text {
                                required property var modelData
                                required property int index
                                width: lCol.width
                                wrapMode: Text.Wrap
                                text: modelData[0]
                                color: index === 0 ? link.ink : msg.out ? Theme.outText : Theme.inText
                                font.family: Theme.font; font.pixelSize: 14; font.weight: modelData[1] ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
                Row {
                    id: stamp
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    spacing: 2
                    Text {
                        text: msg.modelData.time || ""
                        color: msg.out ? Theme.outMeta : Theme.inMeta
                        font.family: Theme.font; font.pixelSize: 11
                    }
                    Text {
                        visible: msg.out
                        text: "✓✓"
                        color: Theme.check
                        font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: -4
                    }
                }
            }
        }
    }
}
