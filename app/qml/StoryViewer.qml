// Hikoyalar (Q): Telegram-iOS's StoryContainerScreen over every page. Each chat's stories one after
// another: thin bars at the top fill as they play (a picture 5 s, a video its length), avatar · name · how long
// ago, 🔇 (a video), ✕. A tap on the right goes on, on the left back; held, it waits; a sideways swipe turns
// the cube to the next or the one before chat; down closes. At the foot: «Shaxsiy javob…» (a message to the
// poster, answering the story: inputMessageReplyToStory), ↪ (sent to a chat: inputMessageStory), ♥
// (setStoryReaction, hearts fly up). The field taken: the keyboard, and over it the reactions — one tapped goes
// as a private message. The first opening tells the gestures (Prefs.storyHint).
import QtQuick
import QtMultimedia
import QtQuick.Shapes

Item {
    id: sv
    anchors.fill: parent
    visible: open || shut.running
    property bool open: false
    property var chats: []              // chat ids, in the row's order
    property int ci: 0                  // the chat shown
    property int si: 0                  // its story shown
    property var story: null            // TDLib's story, once got
    property string media: ""           // its picture or video, once here
    property real progress: 0
    property bool muted: false
    property bool held: false
    property bool hint: false
    property real turn: 0               // -1..1: the cube turned to the chat before (−) or the next (+)
    property real drop: 0               // pulled down to close
    readonly property bool typing: field.activeFocus
    readonly property bool paused: held || hint || typing || share.open || turn !== 0 || drop !== 0 || !media
                                   || Qt.application.state !== Qt.ApplicationActive
    readonly property var chatId: chats[ci] || 0
    property var only: null             // showOne's: a profile's posted/archived stories instead of the chat's active ones
    readonly property var active: only ? only : (store.storiesSeen, store.stories[chatId] || null)
    readonly property int count: active ? active.stories.length : 0
    readonly property bool isVideo: !!story && story.content["@type"] === "storyContentVideo"
    readonly property var poster: (store.seen, store.chats[chatId] || null)
    readonly property bool isUser: !!poster && poster.type["@type"] === "chatTypePrivate"
    readonly property bool mine: store.isSaved(poster)     // our own (a profile's posts): no reply or heart, how many saw it
    readonly property string heart: story && story.chosen_reaction_type && story.chosen_reaction_type.emoji || ""
    readonly property var db: store
    property var shown: null            // [chat, story id] opened (TDLib told: closeStory when it goes)

    function show(list, i) {
        only = null
        chats = list
        ci = Math.max(0, i)
        si = store.storyStart(chatId)
        turn = 0; drop = 0; held = false
        open = true
        hint = !Prefs.storyHint
        come.restart()
        load()
    }
    // a profile's grid (B): those story ids of one chat, from the i-th, with nothing to turn to
    function showOne(chat, ids, i) {
        only = { stories: ids.map((id) => ({ story_id: id })), max_read_story_id: 0 }
        chats = [chat]
        ci = 0
        si = Math.max(0, i)
        turn = 0; drop = 0; held = false
        open = true
        hint = false
        come.restart()
        load()
    }
    function close() {
        if (!open)
            return
        field.focus = false
        osk.hide()
        leave()
        open = false
        player.stop()
        shut.restart()
    }
    function back() {
        if (share.open)
            share.close()
        else if (typing) {
            field.focus = false
            osk.hide()
        } else
            close()
    }
    function typeReply() { field.forceActiveFocus() }
    readonly property alias shareSheet: share
    function leave() {
        if (shown)
            store.openStory(shown[0], shown[1], false)
        shown = null
    }
    function load() {
        leave()
        player.stop()
        story = null; media = ""; progress = 0
        clock.stop()
        if (!active || si >= count)
            return
        const chat = chatId, id = active.stories[si].story_id
        store.story(chat, id, (s) => {
            if (!open || chat !== chatId || !active || !active.stories[si] || active.stories[si].story_id !== id)
                return
            story = s
            if (!s)
                return
            shown = [chat, id]
            store.openStory(chat, id, true)
            const f = isVideo ? s.content.video.video : best(s.content.photo.sizes)
            if (f)
                store.fetch(f, 32, (p) => { if (story === s) { media = p; start() } })
        })
    }
    function best(sizes) {
        let b = null
        for (const z of sizes || [])
            if (!b || z.width * z.height > b.width * b.height)
                b = z
        return b ? b.photo : null
    }
    function start() {
        if (isVideo) {
            player.source = "file://" + media
            player.play()
        } else {
            clock.duration = 5000
            clock.restart()
        }
    }
    function next() {
        if (si + 1 < count) {
            si++
            load()
        } else if (ci + 1 < chats.length)
            turnTo(1)
        else
            close()
    }
    function prev() {
        if (si > 0) {
            si--
            load()
        } else if (ci > 0)
            turnTo(-1)
        else
            load()          // (the first: from its start again)
    }
    function turnTo(dir) {
        cube.to = dir
        cube.restart()
    }
    function turned() {
        const dir = Math.round(turn)
        if (dir !== 0 && chats[ci + dir] !== undefined) {
            ci += dir
            si = store.storyStart(chatId)
            turn = 0
            load()
        } else
            turn = 0
    }
    function ago(unix) {
        const s = Math.max(0, Date.now() / 1000 - unix)
        return s < 60 ? Tr.t("hozirgina") : s < 3600 ? Tr.f("%1 daqiqa oldin", Math.floor(s / 60))
             : s < 86400 ? Tr.f("%1 soat oldin", Math.floor(s / 3600)) : store.stamp(unix)
    }
    function react() {
        if (!story)
            return
        const on = heart === ""
        store.storyReact(chatId, story.id, on ? "❤" : "")
        story = Object.assign({}, story)        // (its chosen reaction drawn again)
        if (on)
            hearts.createObject(sv, { x: heartButton.x + heartButton.width / 2, y: foot.y + heartButton.y })
    }
    function reply(text) {
        if (!story || !text.trim())
            return
        store.storyReply(chatId, story.id, text.trim())
        field.text = ""
        field.focus = false
        osk.hide()
        root.say(Tr.t("Xabar yuborildi"))
    }

    Connections {
        target: store
        function onStoryChanged(chatId, id) {
            if (sv.open && sv.story && chatId === sv.chatId && id === sv.story.id)
                store.story(chatId, id, (s) => { if (s && sv.story && s.id === sv.story.id) sv.story = s })
        }
    }

    NumberAnimation {
        id: clock
        target: sv; property: "progress"; from: 0; to: 1
        paused: running && sv.paused
        onFinished: if (sv.progress >= 1) sv.next()
    }
    MediaPlayer {
        id: player
        audioOutput: AudioOutput { muted: sv.muted }
        videoOutput: video
        onPositionChanged: if (duration > 0) sv.progress = position / duration
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) sv.next()
    }
    onPausedChanged: if (isVideo && media) { if (paused) player.pause(); else player.play() }

    NumberAnimation { id: cube; target: sv; property: "turn"; duration: 320; easing.type: Easing.OutCubic; onFinished: sv.turned() }
    NumberAnimation { id: settle; target: sv; property: "drop"; to: 0; duration: 250; easing.type: Easing.OutCubic }
    NumberAnimation { id: come; target: stage; property: "scale"; from: 0.85; to: 1; duration: 300; easing.type: Easing.OutCubic }
    ParallelAnimation {
        id: shut
        NumberAnimation { target: stage; property: "opacity"; from: 1; to: 0; duration: 220 }
        NumberAnimation { target: stage; property: "scale"; to: 0.85; duration: 220 }
        onFinished: { stage.opacity = 1; sv.drop = 0; sv.turn = 0 }
    }

    Rectangle {          // behind: the list shows through as it is pulled down
        anchors.fill: parent
        color: "black"
        opacity: sv.open ? 1 - Math.min(1, sv.drop / 400) : 0
    }

    Item {
        id: stage
        width: sv.width; height: sv.height
        y: sv.drop
        transformOrigin: Item.Top
        scale: 1 - Math.min(0.25, sv.drop / 1600)

        // the cube: both faces pushed back a little as it turns (their near edge stays on the screen)
        Item {
            id: cubeBox
            width: sv.width; height: sv.height
            scale: 1 - 0.3 * Math.sin(Math.PI * Math.abs(sv.turn))

        // the chat shown, turning away as the cube goes round
        Item {
            id: face
            width: sv.width; height: sv.height
            x: -sv.turn * sv.width
            transform: Rotation {
                origin.x: sv.turn > 0 ? face.width : 0; origin.y: face.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: sv.turn * 90
            }
            Rectangle { anchors.fill: parent; color: "#101010" }
            Image {        // Telegram's tiny preview while the picture comes
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                visible: !sv.media
                source: {
                    const m = sv.story ? (sv.isVideo ? sv.story.content.video.minithumbnail : sv.story.content.photo.minithumbnail) : null
                    return m ? "data:image/jpeg;base64," + m.data : ""
                }
            }
            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                visible: !sv.isVideo && sv.media !== ""
                source: !sv.isVideo && sv.media ? "file://" + sv.media : ""
                sourceSize.width: 1080
                asynchronous: true
            }
            VideoOutput {
                id: video
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                visible: sv.isVideo
            }
            Rectangle {         // the top's shade, under the bars and the name
                width: parent.width; height: 120
                gradient: Gradient { GradientStop { position: 0; color: "#66000000" } GradientStop { position: 1; color: "#00000000" } }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 220
                gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#99000000" } }
            }
            Rectangle { anchors.fill: parent; color: "black"; opacity: Math.abs(sv.turn) * 0.5 }
        }

        // the chat coming in: its picture and name on dark, until its story comes
        Item {
            id: nextFace
            readonly property var other: sv.turn > 0 ? sv.chats[sv.ci + 1] : sv.turn < 0 ? sv.chats[sv.ci - 1] : undefined
            visible: other !== undefined
            width: sv.width; height: sv.height
            x: sv.turn > 0 ? sv.width * (1 - sv.turn) : -sv.width * (1 + sv.turn)
            transform: Rotation {
                origin.x: sv.turn > 0 ? 0 : nextFace.width; origin.y: nextFace.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: sv.turn > 0 ? -(1 - sv.turn) * 90 : (1 + sv.turn) * 90
            }
            Rectangle { anchors.fill: parent; color: "#1c1c1e" }
            StoryAvatar {
                anchors.centerIn: parent
                chatId: nextFace.other || 0
                size: 96
                under: "#1c1c1e"
                ringOn: false
            }
            Rectangle { anchors.fill: parent; color: "black"; opacity: (1 - Math.abs(sv.turn)) * 0.5 }
        }
        }

        // the fingers: tap (left back, else on), hold (waits), sideways (the cube), down (closes)
        MouseArea {
            anchors.fill: parent
            enabled: !sv.hint
            property real x0: 0
            property real y0: 0
            property string mode: ""
            property real vx: 0
            property real lastX: 0
            property real lastT: 0
            pressAndHoldInterval: 220
            onPressed: (m) => { x0 = m.x; y0 = m.y; mode = ""; lastX = m.x; lastT = Date.now(); vx = 0 }
            onPressAndHold: if (mode === "") { mode = "hold"; sv.held = true }
            onPositionChanged: (m) => {
                const dx = m.x - x0, dy = m.y - y0
                if (mode === "" || mode === "hold") {
                    if (Math.abs(dx) > 14 && Math.abs(dx) > Math.abs(dy))
                        mode = "turn"
                    else if (dy > 14 && dy > Math.abs(dx))
                        mode = "down"
                    if (mode === "turn" || mode === "down")
                        sv.held = false
                }
                const t = Date.now()
                if (t > lastT)
                    vx = 0.6 * vx + 0.4 * (m.x - lastX) * 1000 / (t - lastT)
                lastX = m.x; lastT = t
                if (mode === "turn") {
                    let k = -dx / sv.width
                    if ((k > 0 && sv.ci + 1 >= sv.chats.length) || (k < 0 && sv.ci === 0))
                        k *= 0.25           // nothing there: it gives a little
                    sv.turn = Math.max(-1, Math.min(1, k))
                } else if (mode === "down")
                    sv.drop = Math.max(0, dy)
            }
            onReleased: (m) => {
                if (mode === "turn") {
                    const dir = sv.turn > 0 ? 1 : -1
                    const there = sv.chats[sv.ci + dir] !== undefined
                    cube.to = there && (Math.abs(sv.turn) > 0.3 || Math.abs(vx) > 600 && -vx * dir > 0) ? dir : 0
                    cube.restart()
                } else if (mode === "down") {
                    if (sv.drop > 120)
                        sv.close()
                    else
                        settle.restart()
                } else if (mode === "hold")
                    sv.held = false
                else if (sv.typing) {
                    field.focus = false
                    osk.hide()
                } else if (m.x < sv.width * 0.3)
                    sv.prev()
                else
                    sv.next()
                mode = ""
            }
            onCanceled: { sv.held = false; mode = ""; if (sv.turn !== 0) { cube.to = 0; cube.restart() } settle.restart() }
        }

        // the top: the bars, the poster, 🔇 and ✕ (gone while held, as iOS)
        Item {
            id: top
            width: parent.width; height: 70
            x: face.x
            opacity: sv.held || sv.hint ? 0 : 1 - Math.abs(sv.turn)
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Row {
                x: 8; y: 8
                spacing: 3
                Repeater {
                    model: sv.count
                    Rectangle {
                        required property int index
                        width: (sv.width - 16 - 3 * (sv.count - 1)) / Math.max(1, sv.count); height: 2.5; radius: 1.25
                        color: Qt.rgba(1, 1, 1, 0.35)
                        Rectangle {
                            height: parent.height; radius: parent.radius
                            color: "white"
                            width: parent.width * (index < sv.si ? 1 : index > sv.si ? 0 : sv.progress)
                        }
                    }
                }
            }
            StoryAvatar {
                x: 10; y: 20
                chatId: sv.chatId
                size: 34
                ringOn: false
            }
            Column {
                x: 52; y: 21
                width: parent.width - x - 100
                Text {
                    width: parent.width
                    text: sv.mine ? Tr.t("Hikoyam") : sv.poster ? store.title(sv.poster) : ""
                    color: "white"; elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    text: sv.story ? sv.ago(sv.story.date) + (sv.story.is_edited ? " · " + Tr.t("tahrirlangan") : "") : ""
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
            Text {          // 🔇 / 🔊: a video's sound
                visible: sv.isVideo
                x: parent.width - 86; y: 22
                width: 34; height: 34
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: sv.muted ? "🔇" : "🔊"
                font.pixelSize: 18
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: sv.muted = !sv.muted }
            }
            Icon {
                x: parent.width - 44; y: 26
                width: 26; height: 26
                name: "cross"; color: "white"
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: sv.close() }
            }
        }

        // the caption, over the foot
        Text {
            id: caption
            x: 16 + face.x
            width: parent.width - 32
            anchors.bottom: foot.top; anchors.bottomMargin: 10
            visible: !!sv.story && sv.story.caption.text !== "" && !sv.held && !sv.hint
            text: sv.story ? sv.story.caption.text : ""
            color: "white"
            wrapMode: Text.Wrap
            maximumLineCount: expanded ? 30 : 3
            elide: Text.ElideRight
            property bool expanded: false
            font.family: Theme.font; font.pixelSize: 15
            style: Text.Raised; styleColor: "#55000000"
            MouseArea { anchors.fill: parent; onClicked: caption.expanded = !caption.expanded }
        }

        // the foot: the field (a person's, can_be_replied), ↪, ♥
        Item {
            id: foot
            width: parent.width; height: 52
            x: face.x
            y: parent.height - height - 8 - Math.max(osk.h, safe.bottom)
            opacity: sv.held || sv.hint ? 0 : 1 - Math.abs(sv.turn)
            Behavior on opacity { NumberAnimation { duration: 150 } }
            readonly property bool canReply: sv.isUser && !sv.mine && !!sv.story && sv.story.can_be_replied
            Rectangle {
                id: box
                visible: foot.canReply
                x: 10; y: 6
                width: parent.width - x - (sv.typing ? 10 : 102); height: 40; radius: 20
                color: sv.typing ? Qt.rgba(0, 0, 0, 0.5) : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.45); border.width: 1
                TextInput {
                    id: field
                    x: 16; width: parent.width - 32 - (sv.typing && text ? 34 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    onAccepted: sv.reply(text)
                    Text {
                        visible: !field.text
                        text: Tr.t("Shaxsiy javob…")
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font: field.font
                    }
                }
                Rectangle {     // ↑ send
                    visible: sv.typing && field.text !== ""
                    anchors.right: parent.right; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32; radius: 16
                    color: "#2a9ef1"
                    Text { anchors.centerIn: parent; text: "↑"; color: "white"; font.pixelSize: 18; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: sv.reply(field.text) }
                }
            }
            Text {          // a channel's or ours: how many saw it
                visible: !foot.canReply && !!sv.story && !!sv.story.interaction_info
                x: 16; y: 16
                text: sv.story && sv.story.interaction_info ? "👁 " + store.short(sv.story.interaction_info.view_count) : ""
                color: "white"
                font.family: Theme.font; font.pixelSize: 15
            }
            Icon {
                id: shareButton
                visible: !sv.typing && !!sv.story && sv.story.can_be_forwarded
                x: parent.width - 92; y: 12
                width: 28; height: 28
                name: "forward"; color: "white"
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: share.show() }
            }
            Item {
                id: heartButton
                visible: !sv.typing && !sv.mine
                x: parent.width - 50; y: 6
                width: 40; height: 40
                Shape {         // (a heart drawn: the ♥ glyph comes as a colour emoji or not, by the font)
                    anchors.centerIn: parent
                    width: 24; height: 24
                    scale: 1.2
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: sv.heart === "❤" ? "#ff3b30" : "transparent"
                        strokeColor: sv.heart === "❤" ? "#ff3b30" : "white"
                        strokeWidth: 1.8
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M12 20.6 L10.7 19.4 C5.6 14.8 2.4 11.9 2.4 8.3 C2.4 5.4 4.7 3.1 7.6 3.1 C9.3 3.1 10.9 3.9 12 5.2 C13.1 3.9 14.7 3.1 16.4 3.1 C19.3 3.1 21.6 5.4 21.6 8.3 C21.6 11.9 18.4 14.8 13.3 19.4 Z" }
                    }
                    visible: sv.heart === "" || sv.heart === "❤"
                }
                Text {          // another reaction chosen elsewhere: that emoji
                    anchors.centerIn: parent
                    visible: sv.heart !== "" && sv.heart !== "❤"
                    text: sv.heart
                    font.pixelSize: 24
                }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: sv.react() }
            }
        }

        // the field taken: the reactions over it, one tapped goes as a private message (iOS's
        // «Send reaction as a private message»)
        Column {
            visible: sv.typing && foot.canReply
            x: 0; width: parent.width
            anchors.bottom: foot.top; anchors.bottomMargin: 6
            spacing: 8
            Text {
                x: 16
                text: Tr.t("Reaksiyani shaxsiy xabar sifatida yuboring")
                color: Qt.rgba(1, 1, 1, 0.75)
                font.family: Theme.font; font.pixelSize: 13
            }
            Row {
                x: 10
                spacing: Math.floor((sv.width - 20 - 7 * 40) / 6)
                Repeater {
                    model: ["❤", "👍", "🔥", "😂", "😮", "😢", "🎉"]
                    Text {
                        required property string modelData
                        width: 40; height: 40
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: modelData
                        font.pixelSize: 28
                        MouseArea { anchors.fill: parent; onClicked: sv.reply(parent.modelData) }
                    }
                }
            }
        }
    }

    // ♥: a few hearts fly up from the button
    Component {
        id: hearts
        Item {
            id: burst
            Repeater {
                model: 7
                Text {
                    required property int index
                    readonly property real drift: (index - 3) * 14 + (Math.random() - 0.5) * 16
                    x: -10; y: -10
                    text: "❤"
                    font.pixelSize: 18 + Math.random() * 10
                    ParallelAnimation {
                        running: true
                        NumberAnimation { target: parent; property: "y"; to: -150 - Math.random() * 90; duration: 900; easing.type: Easing.OutCubic }
                        NumberAnimation { target: parent; property: "x"; to: -10 + parent.drift; duration: 900; easing.type: Easing.OutQuad }
                        NumberAnimation { target: parent; property: "opacity"; from: 1; to: 0; duration: 900; easing.type: Easing.InQuad }
                        NumberAnimation { target: parent; property: "scale"; from: 0.4; to: 1.2; duration: 500 }
                    }
                }
            }
            Timer { interval: 1000; running: true; onTriggered: burst.destroy() }
        }
    }

    // ↪: to a chat — the story itself (inputMessageStory)
    ForwardSheet {
        id: share
        anchors.fill: parent
        store: sv.db
        z: 5
        onPicked: (to, title) => {
            if (!sv.story)
                return
            store.send({ "@type": "sendMessage", chat_id: to, input_message_content: { "@type": "inputMessageStory",
                         story_poster_chat_id: sv.chatId, story_id: sv.story.id } })
            share.close()
            root.say(Tr.f("Hikoya yuborildi: %1", title))
        }
    }

    // the first opening: the gestures told (iOS's StoryContentCaptionComponent tooltip screen)
    Rectangle {
        anchors.fill: parent
        visible: sv.hint && sv.open
        color: Qt.rgba(0, 0, 0, 0.8)
        z: 6
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30
            spacing: 26
            Repeater {
                model: [["›", Tr.t("Oldinga o'tish"), Tr.t("O'ng tomonni bosing")],
                        ["❙❙", Tr.t("Pauza va o'tkazish"), Tr.t("Bosib turing")],
                        ["‹", Tr.t("Orqaga qaytish"), Tr.t("Chap tomonni bosing")],
                        ["⇄", Tr.t("Hikoyalar orasida o'tish"), Tr.t("Chapga yoki o'ngga suring")]]
                Row {
                    required property var modelData
                    spacing: 16
                    Rectangle {
                        width: 48; height: 48; radius: 24
                        color: "transparent"; border.color: "white"; border.width: 2
                        Text { anchors.centerIn: parent; text: parent.parent.modelData[0]; color: "white"; font.pixelSize: 22; font.weight: Font.DemiBold }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData[1]; color: "white"; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                        Text { text: modelData[2]; color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.font; font.pixelSize: 14 }
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 40 + safe.bottom
            text: Tr.t("Ko'rishni davom ettirish uchun bosing")
            color: "white"
            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
        }
        MouseArea { anchors.fill: parent; onClicked: { sv.hint = false; Prefs.storyHint = true } }
    }
}
