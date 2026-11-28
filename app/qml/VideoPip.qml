// Regular video Picture-in-Picture (1.0): follows Telegram-iOS's OverlayInstantVideoNode pattern,
// living over Main's page stack so the video keeps playing across chat switches. 16:9 floating box
// snapped to any of the 4 corners (clear of headers, safe.bottom and osk.h), drag to another corner,
// tap to play/pause, double-tap (or expand) back to fullscreen, ✕ to close. Uses QtMultimedia's
// default AudioOutput (keeps audio-roles media route unchanged) and is mutually exclusive with the
// round-video PiP (Player.round).
pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

Item {
    id: pip
    anchors.fill: parent
    property bool fullVisible: false
    visible: active || fullVisible

    property var nav: null
    property var player: null
    property var store: null

    property bool active: false
    property string path: ""
    property string poster: ""
    property real aspect: 9 / 16
    property real rate: 1
    property bool playing: true
    property var chatId: 0
    property var msgId: 0
    property var thread: 0
    property real startPos: 0
    property real position: 0
    property real duration: 0

    // corner: 0 = left/top, 1 = right/bottom (default top-right, as round video PiP)
    property int cornerX: 1
    property int cornerY: 0

    readonly property real boxW: Math.min(208, Math.max(160, Math.round(width * 0.5333)))
    readonly property real boxH: Math.round(boxW * 9 / 16)
    readonly property real edgeGap: 8
    readonly property real topGap: 64
    readonly property real bottomGap: Math.max(osk.h, safe.bottom) + 64
    readonly property real targetX: cornerX === 0 ? edgeGap : Math.max(edgeGap, width - edgeGap - boxW)
    readonly property real targetY: cornerY === 0 ? topGap : Math.max(topGap, height - bottomGap - boxH)

    function _fv() { return fullViewerLoader.item }
    function _bx() { return boxLoader.item }

    function open(info) {
        if (!info || !info.path)
            return
        // one PiP at a time: a regular video replaces any playing round video (and its corner circle)
        if (player && player.round)
            player.stop()
        const fv = _fv()
        if (fv && fv.open)
            fv.closeImmediate()
        path = info.path
        poster = info.poster || ""
        aspect = info.aspect > 0 ? info.aspect : 9 / 16
        rate = info.rate > 0 ? info.rate : 1
        chatId = info.chatId || 0
        msgId = info.msgId || 0
        thread = info.thread || 0
        startPos = info.position > 0 ? info.position : 0
        position = startPos
        duration = info.duration > 0 ? info.duration : 0
        playing = info.playing !== false
        if (!active) {
            active = true
        } else {
            const b = _bx()
            if (b)
                b.reload()
        }
    }

    function close() {
        if (!active)
            return
        active = false
        path = ""
        poster = ""
        startPos = 0
        position = 0
        duration = 0
        playing = false
    }

    function toggle() {
        if (!active)
            return
        const b = _bx()
        if (b)
            b.togglePlay()
        else
            playing = !playing
    }

    function expand() {
        if (!active)
            return
        const info = {
            path: path,
            poster: poster,
            aspect: aspect,
            rate: rate,
            position: position,
            duration: duration,
            playing: playing,
            chatId: chatId,
            msgId: msgId,
            thread: thread
        }
        const top = nav ? nav.topPage : null
        if (top && top.chatId === info.chatId && typeof top.openPipVideo === "function") {
            close()
            top.openPipVideo(info)
            return
        }
        fullVisible = true
        fullViewerLoader.active = true
        const fv = _fv()
        close()
        if (fv) {
            fv.chatId = info.chatId
            fv.thread = info.thread
            fv.show(null, info.aspect, info.poster, info.path, info.msgId, info.position, info.rate)
        } else {
            fullVisible = false
        }
    }

    function dismiss() {
        const fv = _fv()
        if (fv && fv.open) {
            fv.close()
            return true
        }
        return false
    }

    // mutual exclusion: if a round video starts playing, close regular video PiP
    Connections {
        target: pip.player
        function onRoundChanged() {
            if (pip.player && pip.player.round && pip.active)
                pip.close()
        }
        function onMsgIdChanged() {
            if (pip.player && pip.player.round && pip.active)
                pip.close()
        }
    }
    Connections {
        target: pip.store
        function onAuthChanged() {
            if (pip.store && pip.store.auth !== "Ready" && pip.active)
                pip.close()
        }
    }

    // lazy PiP window: 0 objects when inactive
    Loader {
        id: boxLoader
        anchors.fill: parent
        active: pip.active
        sourceComponent: Item {
            id: stage
            anchors.fill: parent

            property bool dragging: false
            property bool hintVisible: false

            function reload() {
                media.stop()
                media.from = pip.startPos
                media.source = pip.path ? "file://" + pip.path : ""
                if (pip.playing)
                    media.play()
                else
                    media.pause()
            }

            function togglePlay() {
                if (pip.playing) {
                    pip.playing = false
                    media.pause()
                } else {
                    if (media.mediaStatus === MediaPlayer.EndOfMedia)
                        media.position = 0
                    pip.playing = true
                    media.play()
                    hintVisible = true
                    hintFade.restart()
                }
            }

            function snap(animated) {
                snapAnim.stop()
                if (animated) {
                    snapX.to = pip.targetX
                    snapY.to = pip.targetY
                    snapAnim.start()
                } else {
                    box.x = pip.targetX
                    box.y = pip.targetY
                }
            }

            Connections {
                target: pip
                function onTargetXChanged() { if (!stage.dragging && !inAnim.running) stage.snap(true) }
                function onTargetYChanged() { if (!stage.dragging && !inAnim.running) stage.snap(true) }
            }

            Component.onCompleted: {
                box.y = pip.targetY
                box.x = pip.cornerX === 1 ? pip.width + 4 : -pip.boxW - 4
                inAnim.to = pip.targetX
                inAnim.start()
                reload()
            }

            // drop shadow
            Rectangle {
                x: box.x - 2; y: box.y + 1
                width: box.width + 4; height: box.height + 4
                radius: 13
                color: Qt.rgba(0, 0, 0, Theme.dark ? 0.48 : 0.24)
            }

            Rectangle {
                id: box
                width: pip.boxW; height: pip.boxH
                radius: 12
                color: "#000000"
                clip: true

                Image {
                    anchors.fill: parent
                    source: pip.poster
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(pip.boxW * 2, pip.boxH * 2)
                    visible: !media.hasVideo || media.playbackState === MediaPlayer.StoppedState
                }

                VideoOutput {
                    id: screen
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                MediaPlayer {
                    id: media
                    videoOutput: screen
                    audioOutput: AudioOutput {}
                    playbackRate: pip.rate
                    property real from: 0
                    function begin() {
                        if (from > 0 && seekable && mediaStatus !== MediaPlayer.LoadingMedia && mediaStatus !== MediaPlayer.NoMedia) {
                            position = from
                            from = 0
                        }
                    }
                    onSeekableChanged: begin()
                    onMediaStatusChanged: {
                        begin()
                        if (mediaStatus === MediaPlayer.EndOfMedia)
                            pip.playing = false
                    }
                    onPositionChanged: (pos) => pip.position = pos
                    onDurationChanged: (dur) => { if (dur > 0) pip.duration = dur }
                }

                // subtle progress bar along the bottom edge (inset so rounded corners stay crisp)
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                    height: 3; radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.28)
                    Rectangle {
                        height: parent.height; radius: 1.5
                        width: pip.duration > 0 ? parent.width * Math.min(1, pip.position / pip.duration) : 0
                        color: Theme.accent
                    }
                }

                // center play/pause badge: always shown when paused, briefly shown when resumed
                Rectangle {
                    anchors.centerIn: parent
                    width: 42; height: 42; radius: 21
                    color: Qt.rgba(0, 0, 0, 0.5)
                    opacity: !pip.playing || stage.hintVisible ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Icon {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: name === "play" ? 1.5 : 0
                        width: 20; height: 20
                        name: pip.playing ? "pause" : "play"
                        color: "white"
                    }
                }

                // drag to any corner, single-tap to play/pause, double-tap back to fullscreen
                // (Pointer Handlers work identically for native touchscreen and mouse events)
                Item {
                    anchors.fill: parent
                    DragHandler {
                        id: dragHandler
                        target: box
                        xAxis.minimum: 4
                        xAxis.maximum: Math.max(4, stage.width - box.width - 4)
                        yAxis.minimum: 4
                        yAxis.maximum: Math.max(4, stage.height - box.height - 4)
                        onActiveChanged: {
                            stage.dragging = active
                            if (active) {
                                inAnim.stop()
                                snapAnim.stop()
                            } else {
                                pip.cornerX = (box.x + box.width / 2) < stage.width / 2 ? 0 : 1
                                pip.cornerY = (box.y + box.height / 2) < stage.height / 2 ? 0 : 1
                                stage.snap(true)
                            }
                        }
                    }
                    TapHandler {
                        id: tapHandler
                        enabled: !dragHandler.active
                        gesturePolicy: TapHandler.WithinBounds
                        onSingleTapped: singleTapTimer.restart()
                        onDoubleTapped: {
                            singleTapTimer.stop()
                            pip.expand()
                        }
                    }
                }

                // ⤢ expand button (top-left)
                Rectangle {
                    id: expandBtn
                    x: 6; y: 6
                    width: 24; height: 24; radius: 12
                    color: Qt.rgba(0, 0, 0, 0.52)
                    opacity: expandHit.pressed ? 0.5 : 0.9
                    Icon {
                        anchors.centerIn: parent
                        width: 12; height: 12
                        name: "expand"
                        color: "white"
                    }
                    MouseArea {
                        id: expandHit
                        anchors.fill: parent; anchors.margins: -6
                        onClicked: {
                            singleTapTimer.stop()
                            pip.expand()
                        }
                    }
                }

                // ✕ close button (top-right)
                Rectangle {
                    id: closeBtn
                    anchors.right: parent.right; anchors.rightMargin: 6
                    y: 6
                    width: 24; height: 24; radius: 12
                    color: Qt.rgba(0, 0, 0, 0.52)
                    opacity: closeHit.pressed ? 0.5 : 0.9
                    Icon {
                        anchors.centerIn: parent
                        width: 11; height: 11
                        name: "cross"
                        color: "white"
                    }
                    MouseArea {
                        id: closeHit
                        anchors.fill: parent; anchors.margins: -6
                        onClicked: {
                            singleTapTimer.stop()
                            pip.close()
                        }
                    }
                }

                // crisp border for dark & light theme separation
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14)
                }
            }

            Timer {
                id: singleTapTimer
                interval: 220
                onTriggered: stage.togglePlay()
            }
            Timer {
                id: hintFade
                interval: 650
                onTriggered: stage.hintVisible = false
            }
            NumberAnimation {
                id: inAnim
                target: box; property: "x"
                duration: 280; easing.type: Easing.OutCubic
            }
            ParallelAnimation {
                id: snapAnim
                NumberAnimation { id: snapX; target: box; property: "x"; duration: 240; easing.type: Easing.OutCubic }
                NumberAnimation { id: snapY; target: box; property: "y"; duration: 240; easing.type: Easing.OutCubic }
            }
        }
    }

    // fallback fullscreen viewer when expanded from a different chat or HomePage
    Loader {
        id: fullViewerLoader
        anchors.fill: parent
        active: false
        sourceComponent: PhotoViewer {
            id: fullViewer
            store: pip.store
            onVisibleChanged: pip.fullVisible = visible
            onEnterPip: (info) => pip.open(info)
            onSave: {
                const s = fullViewer.current
                if (s && s.file && pip.store)
                    pip.store.saveFile(s.file, s.name, (t) => { if (pip.nav) pip.nav.say(t) })
                else if (fullViewer.video) {
                    const name = fullViewer.video.split("/").pop() || "video.mp4"
                    const to = td.save(fullViewer.video, name)
                    if (pip.nav)
                        pip.nav.say(to ? Tr.f("Saqlandi: Downloads/%1", to.split("/").pop()) : Tr.t("Saqlab bo'lmadi"))
                }
            }
        }
    }
}
