// A message's words as Telegram draws them. Plain words are one Text; formatted ones (Store.rich's
// parts) a column: words as StyledText (bold, italic, links a tap opens), a quote a tinted block with
// a bar down its left and „ in its corner (one that folds shows three lines and ⌄ until tapped),
// code a block of its own in a fixed-width face, a spoiler's letters hidden under Dust until tapped.
import QtQuick

Item {
    id: words
    property string text            // the plain words, when there are no parts
    property string parts           // Store.rich's JSON, "" for none
    property color ink
    property color tint             // the links, a quote's bar and its tint
    property int size: 16
    // the most it may be across: formatted words are laid out at that from the start (laid out at
    // their own width, they were laid out at none first, a word a line, then again: a long post
    // took 0.1 s to make while scrolling). Left-aligned, they look the same either way.
    property real room: width
    property bool open: false       // a folding quote shown whole
    property bool shown: false      // the spoilers tapped: their dust blows off, then link("spoiler")
    onPartsChanged: shown = false
    property bool live: true        // on the screen (a spoiler's dust moves only then)
    property Component richComponent: null
    property var richCol: null
    signal link(string url)
    signal fold()                   // a folding quote tapped
    // formatted words take the touch themselves (a link would keep a long press from the bubble):
    // a tap on a link or a folding quote is theirs, the rest is the bubble's as if on it
    signal touched(bool down)
    signal held()
    signal tapped()

    // (Emo's pictures are 20 for 16-point words, a little over the letters; a jumbo emoji's (94, 79, 65:
    // Telegram-iOS's font sizes) as big as its size, as its glyph there is)
    readonly property var list: {
        if (!parts)
            return []
        const l = JSON.parse(parts)
        if (size !== 16) {
            const px = Math.round(size * (size > 30 ? 1 : 1.25))
            for (const p of l)
                p.h = p.h.replace(/ width="20" height="20"/g, " width=\"" + px + "\" height=\"" + px + "\"")
        }
        return l
    }
    function syncRich() {
        if (list.length > 0) {
            if (!richCol && richComponent)
                richCol = richComponent.createObject(words, { words: words })
        } else if (richCol) {
            richCol.destroy()
            richCol = null
        }
    }
    onListChanged: syncRich()
    onRichComponentChanged: syncRich()
    Component.onCompleted: syncRich()

    // the last line's width: where the time may go
    readonly property real last: list.length ? (richCol ? richCol.last : 0) : plain.last
    // as wide as the words unwrapped, at most `room`, from one layout at `room`: a Text's implicitWidth,
    // asked of one with a width, lays it out a second time unwrapped (a 2199-letter message: 8.7 ms to
    // make, 2.9 without). More lines than paragraphs: one wrapped, wider than room; else the widest line
    implicitWidth: list.length ? (richCol ? richCol.wants : 0)
                 : plain.lineCount > plain.paragraphs ? room : plain.contentWidth
    implicitHeight: list.length ? (richCol ? richCol.height : 0) : plain.implicitHeight

    Text {
        id: plain
        visible: !words.list.length
        // laid out once, at the most it may be (words.width is its widest line, or less): right-aligned
        // words (Arabic, Hebrew) are moved left by the difference, their lines' ends at words' right
        x: effectiveHorizontalAlignment === Text.AlignRight ? words.width - width : 0
        width: words.room
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        property real last: 0
        onLineLaidOut: (line) => { if (line.isLast) last = line.implicitWidth }
        text: visible ? words.text : ""
        readonly property int paragraphs: text.indexOf("\n") < 0 && text.indexOf("\u2028") < 0 ? 1 : text.split(/[\n\u2028]/).length
        color: words.ink
        font.family: Theme.font; font.pixelSize: words.size
    }
}
