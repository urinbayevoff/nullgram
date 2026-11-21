// A video playing in its bubble: a GIF over and over without sound, a round video once with
// it, cut to the bubble's corners (or a circle) by a mask on the GPU.
import QtQuick
import QtQuick.Effects
import QtMultimedia

Item {
    id: v
    property string path: ""
    property real radius: 14            // -1: a circle
    property bool sound: false
    property bool loop: true
    property bool running: true
    property real rate: 1               // a round video: the voice notes' speed (Prefs.playRate)
    property real from: 0               // ms: where it starts (a round video going on from its other player)
    property var resumeFrom: null       // a function: where to go each time it starts (or goes on) running
    readonly property real position: player.position
    readonly property real duration: player.duration
    readonly property bool showing: player.playbackState !== MediaPlayer.StoppedState && player.hasVideo
    signal ended()

    MediaPlayer {
        id: player
        source: v.path ? "file://" + v.path : ""
        videoOutput: out
        audioOutput: v.sound ? audio : null
        loops: v.loop ? MediaPlayer.Infinite : 1
        playbackRate: v.rate
        onMediaStatusChanged: {
            begin()
            if (mediaStatus === MediaPlayer.EndOfMedia)
                v.ended()
        }
        onSeekableChanged: begin()
        // (a position given while it still loads is lost: once loaded)
        function begin() {
            if (v.from > 0 && seekable && mediaStatus !== MediaPlayer.LoadingMedia && mediaStatus !== MediaPlayer.NoMedia) {
                position = v.from
                v.from = 0
            }
        }
        // the path may come after it is made (a GIF brought down while on the screen): play then, once the
        // player has it -- on the path's own change play() came before the source, which then stopped it
        onSourceChanged: if (v.running && v.path) play()
    }
    AudioOutput { id: audio }
    onRunningChanged: {
        if (running) {
            if (resumeFrom)
                from = resumeFrom()
            player.begin()
            player.play()
        } else
            player.pause()
    }
    Component.onCompleted: {
        if (resumeFrom)
            from = resumeFrom()
        if (running && path)
            player.play()
    }

    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: false
        layer.enabled: true
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: v.radius < 0 ? width / 2 : v.radius
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: out
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
