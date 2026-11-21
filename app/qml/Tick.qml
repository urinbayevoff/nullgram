// One clock for every moving sticker (Lottie.qml): each shows its next frame on the same tick, so the
// window is drawn again 30 times a second however many there are -- each on a clock of its own, three
// stickers had it drawn 90 times (and the S10's screen takes 60). It goes with the window's frames
// (FrameAnimation), not a Timer: with the screen off the window draws none, and a Timer kept the
// stickers asking for frames there, half a core for nothing.
pragma Singleton
import QtQuick

QtObject {
    property int users: 0       // the stickers playing now (it runs only while there are any)
    property int n: 0           // the ticks so far
    readonly property int fps: 30
    property real due: 0        // seconds to the next tick
    property FrameAnimation clock: FrameAnimation {
        running: users > 0
        onTriggered: {
            due -= frameTime
            if (due <= 0.004) {         // (a 60 Hz screen: every other frame, give or take its jitter)
                due = Math.max(due + 1 / fps, 0)
                n++
            }
        }
    }
}
