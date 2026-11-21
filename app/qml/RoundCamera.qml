// A round video being made (Telegram-iOS's VideoMessageCameraScreen): what the camera sees in a circle in the
// middle of the screen, a ring round it filling up to the 60 s, the camera's flip under it. Until omonullOS
// has a camera it is a file playing over and over (td.fakeCamera); the flip mirrors it. Also the made one,
// over and over, while it is listened to before it goes (`path` is then that file, `progress` -1).
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtMultimedia

Item {
    id: cam
    property string path: ""
    property bool mirrored: false
    property real progress: 0           // 0..1 of the 60 s; -1: no ring
    property bool sound: false
    readonly property real position: player.position       // where the file is now (ms): where the clip starts
    width: 280; height: 280

    MediaPlayer {
        id: player
        source: cam.path ? "file://" + cam.path : ""
        videoOutput: out
        audioOutput: cam.sound ? speaker : null
        loops: MediaPlayer.Infinite
        onSourceChanged: if (cam.visible && cam.path) play()
    }
    AudioOutput { id: speaker }
    onVisibleChanged: visible && path ? player.play() : player.stop()

    Rectangle {          // while the first frame comes
        anchors.fill: parent
        radius: width / 2
        color: "#202020"
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
        radius: width / 2
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        // (mirrored here: a layer's picture is drawn without its item's own transform)
        transform: Scale { origin.x: cam.width / 2; xScale: cam.mirrored ? -1 : 1 }
        source: out
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
    Shape {              // the 60 s, filling clockwise from the top
        visible: cam.progress >= 0
        anchors.fill: parent; anchors.margins: -8
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.25)
            strokeWidth: 4
            PathAngleArc { centerX: cam.width / 2 + 8; centerY: cam.height / 2 + 8; radiusX: cam.width / 2 + 4; radiusY: radiusX
                           startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.danger
            strokeWidth: 4
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: cam.width / 2 + 8; centerY: cam.height / 2 + 8; radiusX: cam.width / 2 + 4; radiusY: radiusX
                           startAngle: -90; sweepAngle: 360 * Math.max(0.005, Math.min(1, cam.progress)) }
        }
    }
}
