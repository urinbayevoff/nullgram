// A TGS sticker (Lottie) playing: its frames drawn by libtlottie (image://lottie, nullgram.py's Lottie) and
// shown two pictures in turn -- the next one asked for while the last stays on the screen, so it never
// blinks empty. On Tick's clock, as every other sticker: a tick shows the frame the last one asked for,
// if it has come, and asks for the next. The frame is found by the time since it started, so one that
// came late is skipped past, not played late; 30 a second (Telegram's stickers are 60: half is as smooth
// to see here and half the work). Not playing: it stays on the frame it was at (the first, at first).
//
// A sticker loops. An emoji alone (`once`) plays to its end and stays on its last frame, as Telegram-iOS
// has them (ChatMessageAnimatedStickerItemNode: .still(.end), playOnce the first time it is seen in the
// chat); `atEnd`: seen already, its last frame only. replay(): from the start again (a tap on it).
// An emoji's effect (ChatPage's burst) is one too, `once`, gone when `ended`.
import QtQuick
import QtQuick.Window

Item {
    id: l
    property string path: ""
    property bool running: true
    property bool once: false
    property int fitz: 0            // an emoji's skin tone (tlottie's fitz modifier, 1-5)
    property bool atEnd: false      // (read as it is made)
    signal ended()                  // a `once` one has played to its end
    // pixels a frame: 384 at most (Qt asks for the size in points times the ratio); drawn bigger, three
    // stickers cost a big core (nullgram.py, Lottie). An emoji's effect, three times its size and played
    // once, is let have more.
    property int most: 384
    readonly property real side: Math.min(Math.max(width, height), most / Screen.devicePixelRatio)
    readonly property bool shown: a.status === Image.Ready || b.status === Image.Ready
    readonly property bool playing: running && path !== "" && visible && !failed && !over

    property int front: 1       // 0: a is on the screen, 1: b (neither has a frame at first)
    property bool asking: false // the other one is bringing a frame
    property bool failed: false // a frame it could not draw (not a Lottie, no libtlottie): it stops there
    property bool over: false   // a `once` one played: on its last frame
    property real started: 0    // when frame 0 was (Date.now()), moved on by the time it stood paused
    property real stopped: 0
    property bool counted: false    // one of Tick's users

    function url(ms) {
        const how = (once ? "o" : "") + (fitz > 0 ? fitz : "")
        return "image://lottie/" + Math.round(ms) + "/" + (how || "-") + "/" + path
    }
    function ask(ms) {
        if (!path || asking)
            return
        const back = front === 0 ? b : a
        if (back.source == url(ms))     // (the same frame again: no change would come)
            return
        asking = true
        back.source = url(ms)
    }
    function came(img) {
        if (img === (front === 0 ? a : b))
            return
        asking = false
        if (img.status === Image.Error) {
            if (once && !over && img.source != url(-1)) {   // past the end: its last frame, and it stays there
                over = true
                ask(-1)
                ended()
            } else {
                failed = true
            }
            return
        }
        if (!shown || !playing)     // the first frame, the last, or one asked before it stopped: up at once
            swap()
    }
    function swap() {
        const back = front === 0 ? b : a
        if (!asking && back.status === Image.Ready)
            front = 1 - front
    }
    function step() {
        swap()
        ask(Date.now() - started + 1000 / Tick.fps)    // (shown on the next tick)
    }
    function count(on) {
        if (on !== counted) {
            counted = on
            Tick.users += on ? 1 : -1
        }
    }
    function replay(gently) {      // gently: only if it has stopped (the other one's tap, not ours)
        if (!path || failed || (gently && !over))
            return
        started = Date.now()
        stopped = started
        over = false
    }
    function begin() {
        started = Date.now()
        stopped = started
        asking = false
        failed = false
        over = once && atEnd
        if (path)
            ask(over ? -1 : 0)
    }

    onPlayingChanged: {
        if (playing)
            started += Date.now() - stopped
        else
            stopped = Date.now()
        count(playing)
    }
    onPathChanged: {
        a.source = ""
        b.source = ""
        front = 1
        begin()
    }
    Component.onCompleted: {
        begin()
        count(playing)
    }
    Component.onDestruction: count(false)

    Connections {
        target: Tick
        enabled: l.playing
        function onNChanged() { l.step() }
    }

    Image {
        id: a
        anchors.fill: parent
        asynchronous: true
        cache: false
        smooth: true
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(l.side, l.side)
        visible: l.front === 0
        onStatusChanged: if (status === Image.Ready || status === Image.Error) l.came(a)
    }
    Image {
        id: b
        anchors.fill: parent
        asynchronous: true
        cache: false
        smooth: true
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(l.side, l.side)
        visible: l.front === 1
        onStatusChanged: if (status === Image.Ready || status === Image.Error) l.came(b)
    }
}
