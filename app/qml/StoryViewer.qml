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
    property bool streaming: false      // true when media is an HTTP Range loopback stream URL
    property string thumb: ""           // instant preview (video thumbnail or already-local smaller photo)
    property int waitFileId: 0          // file currently downloading for this story
    property real dlProgress: -1        // 0..1 while downloading, -1 otherwise
    property real progress: 0
    property bool muted: false
    property bool held: false
    property bool hint: false
    property real turn: 0               // -1..1: the cube turned to the chat before (−) or the next (+)
    property real drop: 0               // pulled down to close
    readonly property bool typing: field.activeFocus
    readonly property bool paused: held || hint || typing || share.open || menuSheet.open || viewersSheet.open
                                   || reportSheet.open || confirm.open || turn !== 0 || drop !== 0 || !media
                                   || Qt.application.state !== Qt.ApplicationActive
    readonly property bool buffering: isVideo && media !== ""
                                      && (player.mediaStatus === MediaPlayer.LoadingMedia
                                          || player.mediaStatus === MediaPlayer.BufferingMedia
                                          || (player.playbackState === MediaPlayer.PlayingState && player.position === 0))
    readonly property var chatId: chats[ci] || 0
    property var only: null             // showOne's: a profile's posted/archived stories instead of the chat's active ones
    property var pinnedIds: []          // profile's pinned story ids (from ProfilePage)
    signal mutated(var chatId)
    readonly property var active: only ? only : (store.storiesSeen, store.stories[chatId] || null)
    readonly property int count: active ? active.stories.length : 0
    readonly property bool isVideo: !!story && story.content["@type"] === "storyContentVideo"
    readonly property var poster: (store.seen, store.chats[chatId] || null)
    readonly property bool isUser: !!poster && poster.type["@type"] === "chatTypePrivate"
    readonly property bool mine: store.isSaved(poster) || (!!store.me && chatId === store.me.id)
    // own story: always (TDLib may not have sent interaction_info yet on the first open; the sheet asks for the list itself)
    readonly property bool canOpenViewers: !!story && (mine || !!story.interaction_info
                                                       && (!!story.can_get_interactions || !!story.can_get_statistics))
    readonly property string heart: story && story.chosen_reaction_type && story.chosen_reaction_type.emoji || ""
    readonly property var db: store
    property var shown: null            // [chat, story id] opened (TDLib told: closeStory when it goes)

    function show(list, i) {
        only = null
        pinnedIds = []
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
    function showOne(chat, ids, i, pinned) {
        only = { stories: ids.map((id) => ({ story_id: id })), max_read_story_id: 0 }
        pinnedIds = (pinned || []).slice()
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
        menuSheet.open = false
        viewersSheet.open = false
        reportSheet.close()
        confirm.open = false
        share.close()
        leave()
        open = false
        player.stop()
        shut.restart()
    }
    function back() {
        if (confirm.open)
            confirm.open = false
        else if (reportSheet.open)
            reportSheet.close()
        else if (menuSheet.open)
            menuSheet.open = false
        else if (viewersSheet.open)
            viewersSheet.open = false
        else if (share.open)
            share.close()
        else if (typing) {
            field.focus = false
            osk.hide()
        } else
            close()
    }
    function typeReply() { field.forceActiveFocus() }
    readonly property alias shareSheet: share
    readonly property alias menu: menuSheet
    readonly property alias viewers: viewersSheet
    readonly property alias reportMenu: reportSheet
    readonly property alias confirmAlert: confirm

    function openMenu() {
        if (!story)
            return
        const s = story
        const out = []
        if (sv.mine || s.can_toggle_is_posted_to_chat_page || s.can_be_deleted) {
            if (s.can_toggle_is_posted_to_chat_page) {
                if (s.is_posted_to_chat_page) {
                    const isPinned = pinnedIds.indexOf(s.id) >= 0
                    out.push({ t: Tr.t(isPinned ? "Profildan yechish" : "Profilga qadash"), run: () => sv.togglePin() })
                    out.push({ t: Tr.t("Arxivga olish"), run: () => sv.toggleArchive(false) })
                } else {
                    out.push({ t: Tr.t("Profilga joylash"), run: () => sv.toggleArchive(true) })
                }
            }
            if (sv.canOpenViewers)
                out.push({ t: Tr.t("Ko'rganlar"), run: () => sv.openViewers() })
            if (s.can_be_deleted)
                out.push({ t: Tr.t("Hikoyani o'chirish"), red: true, run: () => sv.askDelete() })
        } else {
            if (sv.canOpenViewers)
                out.push({ t: Tr.t("Ko'rganlar"), run: () => sv.openViewers() })
            if (!sv.only && store.hasStories(sv.chatId)) {
                const hidden = store.storyHidden(sv.chatId)
                out.push({ t: Tr.t(hidden ? "Hikoyalarni ko'rsatish" : "Hikoyalarni yashirish"), run: () => sv.toggleHide(!hidden) })
            }
            out.push({ t: Tr.t("Shikoyat qilish"), red: true, run: () => sv.report("", "") })
        }
        if (!out.length)
            return
        menuSheet.choices = out
        menuSheet.open = true
    }
    function openViewers() {
        if (!story)
            return
        viewersSheet.show(story)
    }
    function togglePin() {
        if (!story)
            return
        const id = story.id
        const was = pinnedIds.indexOf(id) >= 0
        const nextIds = was ? pinnedIds.filter((x) => x !== id) : [id].concat(pinnedIds)
        store.storyPin(chatId, nextIds, (r) => {
            if (r["@type"] === "error")
                return root.say(r.message)
            sv.pinnedIds = nextIds
            sv.mutated(sv.chatId)
            root.say(Tr.t(was ? "Hikoya profildan yechildi" : "Hikoya profilga qadaldi"))
        })
    }
    function toggleArchive(posted) {
        if (!story)
            return
        const id = story.id
        store.storyArchive(chatId, id, posted, (r) => {
            if (r["@type"] === "error")
                return root.say(r.message)
            if (sv.story && sv.story.id === id)
                sv.story = Object.assign({}, sv.story, { is_posted_to_chat_page: !!posted })
            sv.mutated(sv.chatId)
            root.say(Tr.t(posted ? "Hikoya profilga joylandi" : "Hikoya arxivga olindi"))
        })
    }
    function askDelete() {
        if (!story)
            return
        confirm.show(Tr.t("Hikoyani o'chirish"), Tr.t("Bu hikoya butunlay o'chirilsinmi?"),
                     [{ t: Tr.t("Bekor qilish") },
                      { t: Tr.t("O'chirish"), red: true, bold: true, run: () => sv.doDelete() }])
    }
    function doDelete() {
        if (!story)
            return
        const cid = chatId, id = story.id
        store.storyDelete(cid, id, (r) => {
            if (r["@type"] === "error")
                return root.say(r.message)
            sv.mutated(cid)
            root.say(Tr.t("Hikoya o'chirildi"))
            if (sv.only) {
                const rest = sv.only.stories.filter((x) => x.story_id !== id)
                if (!rest.length) {
                    sv.close()
                    return
                }
                sv.only = { stories: rest, max_read_story_id: 0 }
                if (sv.si >= rest.length)
                    sv.si = rest.length - 1
                sv.load()
            } else if (sv.count === 0) {
                if (sv.ci + 1 < sv.chats.length)
                    sv.turnTo(1)
                else
                    sv.close()
            } else {
                if (sv.si >= sv.count)
                    sv.si = sv.count - 1
                sv.load()
            }
        })
    }
    function toggleHide(hide) {
        const cid = chatId
        const title = poster ? store.title(poster) : ""
        store.storyHide(cid, hide, (r) => {
            if (r["@type"] === "error")
                return root.say(r.message)
            root.say(Tr.f(hide ? "%1 hikoyalari yashirildi" : "%1 hikoyalari ko'rsatiladi", title))
            if (hide) {
                if (sv.ci + 1 < sv.chats.length)
                    sv.turnTo(1)
                else
                    sv.close()
            }
        })
    }
    function report(option, text) {
        if (!story)
            return
        const cid = chatId, sid = story.id
        store.storyReport(cid, sid, option, text, (r) => {
            if (!sv.open)
                return
            const t = r["@type"]
            if (t === "reportStoryResultOk")
                root.say(Tr.t("Shikoyat yuborildi"))
            else if (t === "reportStoryResultOptionRequired")
                reportSheet.ask({ title: r.title, options: r.options })
            else if (t === "reportStoryResultTextRequired")
                reportSheet.ask({ option: r.option_id, optional: r.is_optional })
            else
                root.say(Tr.t("Shikoyat yuborilmadi"))
        })
    }
    function leave() {
        if (shown)
            store.openStory(shown[0], shown[1], false)
        shown = null
    }
    function load() {
        leave()
        player.stop()
        story = null; media = ""; streaming = false; thumb = ""; waitFileId = 0; dlProgress = -1; progress = 0
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
            if (s.interaction_info && s.interaction_info.recent_viewer_user_ids) {
                for (const uid of s.interaction_info.recent_viewer_user_ids.slice(0, 3))
                    if (!store.users[uid])
                        store.send({ "@type": "getUser", user_id: uid })
            }
            if (isVideo) {
                const th = s.content.video && s.content.video.thumbnail ? s.content.video.thumbnail.file : null
                if (th)
                    store.fetch(th, 32, (p) => { if (story === s) thumb = p })
                const vf = videoFile(s)
                if (vf) {
                    if (vf.local && vf.local.is_downloading_completed && vf.local.path) {
                        streaming = false
                        media = vf.local.path
                        start()
                    } else {
                        const url = td.streamUrl ? td.streamUrl(vf.id, vf.size || vf.expected_size || 0) : ""
                        if (url) {
                            streaming = true
                            waitFileId = vf.id
                            dlProgress = Math.max(0, store.progress(vf))
                            media = url
                            start()
                        } else {
                            waitFileId = vf.id
                            dlProgress = Math.max(0, store.progress(vf))
                            store.fetch(vf, 32, (p) => {
                                if (story === s) {
                                    waitFileId = 0; dlProgress = -1
                                    media = p
                                    start()
                                }
                            })
                        }
                    }
                }
            } else if (s.content.photo) {
                for (const z of s.content.photo.sizes || [])
                    if (z.photo && z.photo.local && z.photo.local.is_downloading_completed && z.photo.local.path) {
                        thumb = z.photo.local.path
                        break
                    }
                const pf = best(s.content.photo.sizes)
                if (pf) {
                    if (!pf.local.is_downloading_completed) {
                        waitFileId = pf.id
                        dlProgress = Math.max(0, store.progress(pf))
                    }
                    store.fetch(pf, 32, (p) => {
                        if (story === s) {
                            waitFileId = 0; dlProgress = -1
                            media = p
                            start()
                        }
                    })
                }
            }
            prefetchNext()
        })
    }
    function videoFile(s) {
        const v = s.content.video && s.content.video.video
        const alt = s.content.alternative_video && s.content.alternative_video.video
        if (v && v.local && v.local.is_downloading_completed)
            return v
        if (alt && alt.local && alt.local.is_downloading_completed)
            return alt
        return alt || v || null        // prefer H.264 alternative_video when available (faster SW decode & smaller)
    }
    function best(sizes) {
        let b = null
        for (const z of sizes || [])
            if (!b || (z.width >= 720 && z.width < b.width) || b.width < 720)
                b = z
        return b ? b.photo : null
    }
    function prefetchNext() {
        let nextChat = 0, nextId = 0
        if (active && si + 1 < count) {
            nextChat = chatId
            nextId = active.stories[si + 1].story_id
        } else if (!only && ci + 1 < chats.length) {
            nextChat = chats[ci + 1]
            const na = store.stories[nextChat]
            if (na && na.stories.length)
                nextId = na.stories[store.storyStart(nextChat)].story_id
        }
        if (!nextChat || !nextId)
            return
        store.story(nextChat, nextId, (s) => {
            if (!s || !s.content)
                return
            if (s.content["@type"] === "storyContentVideo") {
                const th = s.content.video && s.content.video.thumbnail ? s.content.video.thumbnail.file : null
                if (th)
                    store.fetch(th, 16, () => {})
                const vf = videoFile(s)
                if (vf)
                    store.fetchPrefix(vf, 12, (s.content.video && s.content.video.preload_prefix_size) || 524288)
            } else if (s.content["@type"] === "storyContentPhoto") {
                const pf = best(s.content.photo.sizes)
                if (pf)
                    store.fetch(pf, 16, () => {})
            }
        })
    }
    function start() {
        if (!open)          // a download that ends after the viewer was closed must not start the sound
            return
        if (isVideo) {
            player.source = streaming ? media : ("file://" + media)
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
    // iOS Chat_MessageSeenTimestamp: «bugun 14:05», «kecha 22:10», or «21.11 18:30»
    function seenTime(unix) {
        if (!unix)
            return ""
        const d = new Date(unix * 1000), now = new Date()
        const hm = Qt.formatDateTime(d, "HH:mm")
        const day0 = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        const dayD = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const diff = Math.round((day0 - dayD) / 86400000)
        if (diff === 0)
            return Tr.f("bugun %1", hm)
        if (diff === 1)
            return Tr.f("kecha %1", hm)
        return Qt.formatDateTime(d, "dd.MM HH:mm")
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
        function onFileUpdated(f) {
            if (sv.open && sv.waitFileId && f.id === sv.waitFileId)
                sv.dlProgress = Math.max(0, store.progress(f))
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
        onPositionChanged: (position) => { if (player.duration > 0) sv.progress = position / player.duration }
        onMediaStatusChanged: (status) => { if (status === MediaPlayer.EndOfMedia) sv.next() }
        onErrorOccurred: (error, errorString) => sv.streamFailed()
    }
    // the stream broke (network too slow for the server's wait, TDLib error): fetch the whole file as before
    // and play it from disk, instead of a spinner for ever
    function streamFailed() {
        if (!open || !streaming || !story)
            return
        const s = story, vf = videoFile(s)
        if (!vf)
            return
        streaming = false
        media = ""
        player.stop()
        waitFileId = vf.id
        dlProgress = Math.max(0, store.progress(vf))
        store.fetch(vf, 32, (p) => {
            if (story === s) {
                waitFileId = 0; dlProgress = -1
                media = p
                start()
            }
        })
    }
    // only while open: after close() story/media stay set, and coming back to the app (paused → false) played the
    // closed story's sound again
    onPausedChanged: if (open && isVideo && media) { if (paused) player.pause(); else player.play() }

    NumberAnimation { id: cube; target: sv; property: "turn"; duration: 320; easing.type: Easing.OutCubic; onFinished: sv.turned() }
    NumberAnimation { id: settle; target: sv; property: "drop"; to: 0; duration: 250; easing.type: Easing.OutCubic }
    NumberAnimation { id: come; target: stage; property: "scale"; from: 0.88; to: 1; duration: 200; easing.type: Easing.OutCubic }
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
            Image {        // Telegram's tiny preview while the picture/thumbnail comes
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                visible: !sv.media && !sv.thumb
                source: {
                    const m = sv.story ? (sv.isVideo ? sv.story.content.video.minithumbnail : sv.story.content.photo.minithumbnail) : null
                    return m ? "data:image/jpeg;base64," + m.data : ""
                }
            }
            Image {        // video thumbnail or already-cached photo shown immediately while downloading/buffering
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                visible: sv.thumb !== "" && (sv.isVideo ? (sv.media === "" || sv.buffering) : sv.media === "")
                source: sv.thumb ? "file://" + sv.thumb : ""
                sourceSize.width: 720
                asynchronous: true
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
                visible: sv.isVideo && sv.media !== "" && !sv.buffering
            }
            Rectangle {     // subtle progress ring while downloading/buffering a video or photo
                visible: sv.open && !!sv.story && (sv.media === "" || sv.buffering)
                anchors.centerIn: parent
                width: 52; height: 52; radius: 26
                color: Qt.rgba(0, 0, 0, 0.45)
                Ring {
                    anchors.centerIn: parent
                    width: 40; height: 40
                    cross: false
                    value: sv.dlProgress >= 0 ? Math.max(0.08, sv.dlProgress) : 0.25
                }
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
                    else if (dy < -24 && -dy > Math.abs(dx))
                        mode = "up"         // even with no viewers to show: an upward swipe is never a tap (a tap goes on / closes)
                    if (mode === "turn" || mode === "down" || mode === "up")
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
                } else if (mode === "up") {
                    if (sv.canOpenViewers)
                        sv.openViewers()
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
                width: parent.width - x - (sv.isVideo ? 130 : 92)
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
                x: parent.width - 122; y: 22
                width: 34; height: 34
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: sv.muted ? "🔇" : "🔊"
                font.pixelSize: 18
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: sv.muted = !sv.muted }
            }
            Icon {          // ⋯: story actions (pin, archive, delete / hide, report)
                visible: !!sv.story
                x: parent.width - 82; y: 26
                width: 26; height: 26
                name: "more"; color: "white"
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: sv.openMenu() }
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
            Rectangle {     // iOS bottom-left views pill: up to 3 overlapping viewer avatars + count (tap or swipe up → viewers)
                visible: !foot.canReply && !!sv.story && !!sv.story.interaction_info
                readonly property bool tappable: sv.canOpenViewers
                readonly property var recents: sv.story && sv.story.interaction_info && sv.story.interaction_info.recent_viewer_user_ids
                                               ? sv.story.interaction_info.recent_viewer_user_ids.slice(0, 3) : []
                readonly property int vc: sv.story && sv.story.interaction_info ? sv.story.interaction_info.view_count : 0
                readonly property int rc: sv.story && sv.story.interaction_info ? sv.story.interaction_info.reaction_count : 0
                x: 12; y: 8
                width: Math.min(parent.width - 110, viewRow.implicitWidth + (tappable ? 22 : 10)); height: 36; radius: 18
                color: tappable ? (viewHit.pressed ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.36)) : "transparent"
                Row {
                    id: viewRow
                    anchors.centerIn: parent
                    spacing: 6
                    Item {
                        visible: parent.parent.tappable && parent.parent.recents.length > 0
                        width: visible ? 24 + (parent.parent.recents.length - 1) * 15 : 0
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: parent.parent.parent.recents
                            Rectangle {
                                id: miniAv
                                required property var modelData
                                required property int index
                                x: index * 15; z: 3 - index
                                width: 24; height: 24; radius: 12
                                color: "#1c1c1e"
                                readonly property var u: (store.seen, store.users[modelData] || null)
                                property string pic: ""
                                function loadPic() {
                                    const f = u && u.profile_photo ? u.profile_photo.small : null
                                    if (f) store.fetch(f, 2, (p) => miniAv.pic = p)
                                }
                                onUChanged: if (!pic) loadPic()
                                Component.onCompleted: loadPic()
                                Avatar {
                                    anchors.centerIn: parent
                                    width: 21; height: 21
                                    source: miniAv.pic
                                    letters: miniAv.u ? store.letters((miniAv.u.first_name + " " + miniAv.u.last_name).trim()) : ""
                                    tint: store.tints[Math.abs(miniAv.modelData) % store.tints.length]
                                }
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.StyledText
                        text: {
                            const box = parent.parent
                            if (!box.tappable)
                                return "👁 " + store.short(box.vc)
                            if (box.vc <= 0)
                                return Tr.t("Ko'rilmagan")
                            return Tr.n("%1 marta ko'rildi", box.vc, store.count(box.vc))
                                   + (box.rc > 0 && box.recents.length === 0 ? "  ·  <font color='#ff3b30'>❤</font> " + box.rc : "")
                        }
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 14; font.weight: parent.parent.tappable ? Font.DemiBold : Font.Normal
                    }
                    Text {
                        visible: parent.parent.tappable
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: viewHit
                    anchors.fill: parent
                    enabled: parent.tappable
                    onClicked: sv.openViewers()
                }
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

    // 👁: Telegram-iOS StoryItemSetViewListComponent (tabs All/Contacts, sort Reactions/Forwards/Recent,
    // server search, StoryAvatar rows with ✓✓/↪/↻ timestamp, tap → profile, hold → hide stories, Premium footer)
    Item {
        id: viewersSheet
        anchors.fill: parent
        z: 6
        property bool open: false
        property var posterChatId: 0
        property int storyId: 0
        property bool isMine: true
        property bool expired: false
        property bool loading: false
        property int totalViews: 0      // story.interaction_info.view_count (overall views)
        property int totalFetched: 0    // storyInteractions.total_count (returned by current filter)
        property int reactions: 0
        property bool onlyContacts: false
        property int sortMode: 0        // mine: 0=reactions, 1=forwards, 2=recent; channel: 0=reposts, 1=recent
        property string searchQuery: ""
        property string nextOffset: ""
        property var recentIds: []
        property var items: []
        property int reqSeq: 0
        readonly property bool isPremium: !!store.me && !!store.me.is_premium
        readonly property bool showTabs: isMine && (totalViews >= 5 || onlyContacts || searchQuery !== "")
        readonly property bool showSearch: isMine && (totalViews >= 5 || searchQuery !== "" || onlyContacts)
        readonly property bool showPartialFooter: !loading && items.length > 0 && nextOffset === ""
                                                  && isMine && !onlyContacts && searchQuery === ""
                                                  && totalViews > totalFetched
        visible: vDim.opacity > 0

        function show(st) {
            posterChatId = st.poster_chat_id || sv.chatId
            storyId = st.id
            isMine = sv.mine
            expired = !!st.has_expired_viewers
            totalViews = st.interaction_info ? st.interaction_info.view_count : 0
            totalFetched = 0
            reactions = st.interaction_info ? st.interaction_info.reaction_count : 0
            recentIds = st.interaction_info && st.interaction_info.recent_viewer_user_ids ? st.interaction_info.recent_viewer_user_ids : []
            onlyContacts = false
            sortMode = 0
            searchQuery = ""
            vSearch.text = ""
            open = true
            reload()
        }
        function reload() {
            reqSeq++
            items = []
            nextOffset = ""
            loading = false
            more()
        }
        function more() {
            if (loading || !storyId)
                return
            loading = true
            const sid = storyId, cid = posterChatId, seq = reqSeq
            const opts = {
                query: searchQuery,
                onlyContacts: onlyContacts,
                preferForwards: isMine ? sortMode === 1 : sortMode === 0,
                preferWithReaction: isMine ? sortMode === 0 : false,
                offset: nextOffset
            }
            store.storyViewers(cid, sid, isMine, opts, (r) => {
                if (viewersSheet.storyId !== sid || viewersSheet.reqSeq !== seq)
                    return
                viewersSheet.loading = false
                if (r["@type"] === "storyInteractions") {
                    viewersSheet.totalFetched = r.total_count || 0
                    if (!viewersSheet.onlyContacts && viewersSheet.searchQuery === "")
                        viewersSheet.totalViews = Math.max(viewersSheet.totalViews, r.total_count || 0)
                    if (r.total_reaction_count !== undefined && r.total_reaction_count > 0)
                        viewersSheet.reactions = r.total_reaction_count
                    viewersSheet.nextOffset = r.next_offset || ""
                    const got = r.interactions || []
                    for (const it of got) {
                        const a = it.actor_id
                        if (a && a["@type"] === "messageSenderUser" && !store.users[a.user_id])
                            store.send({ "@type": "getUser", user_id: a.user_id })
                    }
                    viewersSheet.items = viewersSheet.items.concat(got)
                }
                if (viewersSheet.items.length === 0 && !viewersSheet.onlyContacts && viewersSheet.searchQuery === ""
                    && viewersSheet.recentIds.length > 0) {
                    const fallback = []
                    for (const uid of viewersSheet.recentIds) {
                        if (!store.users[uid])
                            store.send({ "@type": "getUser", user_id: uid })
                        fallback.push({ actor_id: { "@type": "messageSenderUser", user_id: uid },
                                        interaction_date: 0, type: { "@type": "storyInteractionTypeView" } })
                    }
                    viewersSheet.items = fallback
                }
            })
        }
        function openSortMenu() {
            const pick = (m) => () => { if (viewersSheet.sortMode !== m) { viewersSheet.sortMode = m; viewersSheet.reload() } }
            const mark = (m) => viewersSheet.sortMode === m ? "  ✓" : ""
            const out = isMine
                ? [{ t: Tr.t("Avval reaksiyalar") + mark(0), run: pick(0) },
                   { t: Tr.t("Avval uzatishlar") + mark(1), run: pick(1) },
                   { t: Tr.t("So'nggi ko'rganlar") + mark(2), run: pick(2) }]
                : [{ t: Tr.t("Avval repostlar") + mark(0), run: pick(0) },
                   { t: Tr.t("So'nggi reaksiyalar") + mark(1), run: pick(1) }]
            menuSheet.choices = out
            menuSheet.open = true
        }
        function openProfile(actor) {
            if (!actor)
                return
            const cid = actor["@type"] === "messageSenderUser" ? actor.user_id : actor.chat_id
            if (!cid)
                return
            sv.close()
            if (store.chats[cid]) {
                root.push(Qt.createComponent("ChatInfoPage.qml"), { chatId: cid })
            } else if (actor["@type"] === "messageSenderUser") {
                store.send({ "@type": "createPrivateChat", user_id: cid, force: false }, (r) => {
                    if (r["@type"] === "chat")
                        root.push(Qt.createComponent("ChatInfoPage.qml"), { chatId: r.id })
                })
            }
        }
        function openPremium() {
            sv.close()
            root.push(Qt.createComponent("PremiumPage.qml"), {})
        }
        function actorMenu(actor, name) {
            if (!actor || actor["@type"] !== "messageSenderUser" || !isMine)
                return
            const uid = actor.user_id
            menuSheet.choices = [
                { t: Tr.t("Profilni ochish"), run: () => viewersSheet.openProfile(actor) },
                { t: Tr.t("Hikoyalarimdan berkitish"), red: true, run: () => {
                    store.storyBlockViewer(uid, true, (r) => {
                        if (r["@type"] === "error")
                            root.say(r.message)
                        else
                            root.say(Tr.f("Hikoyalarim endi %1ga ko'rinmaydi", name))
                    })
                } }
            ]
            menuSheet.open = true
        }
        function actorOf(a) {
            if (!a)
                return { id: 0, name: "", file: null, letters: "", tint: Theme.accent }
            if (a["@type"] === "messageSenderUser") {
                const u = store.users[a.user_id]
                const name = u ? (u.first_name + " " + u.last_name).trim() : String(a.user_id)
                const f = u && u.profile_photo ? u.profile_photo.small : null
                return { id: a.user_id, name: name, file: f, letters: store.letters(name),
                         tint: store.tints[Math.abs(a.user_id) % store.tints.length] }
            }
            const c = store.chats[a.chat_id]
            const name = c ? store.title(c) : String(a.chat_id)
            const f = c && c.photo ? c.photo.small : null
            return { id: a.chat_id, name: name, file: f, letters: store.letters(name),
                     tint: store.tints[Math.abs(a.chat_id) % store.tints.length] }
        }
        Timer {
            id: vSearchDebounce
            interval: 300
            onTriggered: {
                viewersSheet.searchQuery = vSearch.text.trim()
                viewersSheet.reload()
            }
        }
        Rectangle {
            id: vDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
            opacity: viewersSheet.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent; onClicked: { vSearch.focus = false; osk.hide(); viewersSheet.open = false } }
        }
        Rectangle {
            id: vCard
            width: parent.width
            height: Math.round(parent.height * 0.74) + 20
            y: viewersSheet.open ? parent.height - height + 20 : parent.height + 10
            radius: 18
            color: Theme.card
            clip: true
            Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8; width: 36; height: 4; radius: 2
                color: Theme.separator
            }
            Item {
                id: vHead
                width: parent.width; height: 50; y: 14
                Segments {
                    visible: viewersSheet.showTabs
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(200, parent.width - 118)
                    items: [Tr.t("Hammasi"), Tr.t("Kontaktlar")]
                    index: viewersSheet.onlyContacts ? 1 : 0
                    onPicked: (i) => {
                        const c = i === 1
                        if (viewersSheet.onlyContacts !== c) {
                            viewersSheet.onlyContacts = c
                            viewersSheet.reload()
                        }
                    }
                }
                Text {
                    visible: !viewersSheet.showTabs
                    x: 16; width: parent.width - 114
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: !viewersSheet.isMine
                          ? Tr.t("Reaksiyalar") + (viewersSheet.reactions > 0 ? "  ·  <font color='#ff3b30'>❤</font> " + viewersSheet.reactions : "")
                          : viewersSheet.totalViews > 0
                            ? Tr.n("%1 marta ko'rildi", viewersSheet.totalViews, store.count(viewersSheet.totalViews))
                              + (viewersSheet.reactions > 0 ? "  ·  <font color='#ff3b30'>❤</font> " + viewersSheet.reactions : "")
                            : Tr.t("Ko'rganlar")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                // iOS sort selector pill (♥ ⌄ / ↪ ⌄ / ◷ ⌄)
                Rectangle {
                    visible: viewersSheet.items.length > 0 || viewersSheet.totalViews > 0
                    anchors.right: vClose.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: sortLabel.implicitWidth + 18; height: 30; radius: 15
                    color: sortHit.pressed ? Theme.highlight : (Theme.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06))
                    Text {
                        id: sortLabel
                        anchors.centerIn: parent
                        textFormat: Text.StyledText
                        text: (viewersSheet.isMine
                               ? (viewersSheet.sortMode === 0 ? "<font color='#ff3b30'>♥</font>"
                                  : viewersSheet.sortMode === 1 ? "↪" : "◷")
                               : (viewersSheet.sortMode === 0 ? "↪" : "◷")) + " ⌄"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    MouseArea { id: sortHit; anchors.fill: parent; onClicked: viewersSheet.openSortMenu() }
                }
                Icon {
                    id: vClose
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                    name: "cross"; color: Theme.grey
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { vSearch.focus = false; osk.hide(); viewersSheet.open = false } }
                }
                Rectangle {
                    visible: !viewersSheet.showSearch
                    anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator
                }
            }
            // iOS viewers search bar (getStoryInteractions query)
            Item {
                id: vSearchWrap
                visible: viewersSheet.showSearch
                x: 0; y: vHead.y + vHead.height
                width: parent.width; height: visible ? 46 : 0
                Rectangle {
                    x: 14; y: 2
                    width: parent.width - 28; height: 36; radius: 10
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.06)
                    Icon {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16; name: "search"; color: Theme.grey
                    }
                    TextInput {
                        id: vSearch
                        x: 32; width: parent.width - 62
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15
                        clip: true
                        onTextChanged: vSearchDebounce.restart()
                        Text {
                            visible: !vSearch.text
                            text: Tr.t("Qidirish")
                            color: Theme.grey
                            font: vSearch.font
                        }
                    }
                    Icon {
                        visible: vSearch.text !== ""
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16; name: "cross"; color: Theme.grey
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            onClicked: { vSearch.text = ""; vSearchDebounce.stop(); viewersSheet.searchQuery = ""; viewersSheet.reload() }
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
            }
            // Empty / Expired state (iOS StoryItemSetViewListComponent lines 1117–1213)
            Column {
                visible: !viewersSheet.loading && viewersSheet.items.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: vSearchWrap.y + vSearchWrap.height + Math.max(28, (vList.height - height - safe.bottom) * 0.35)
                width: parent.width - 56
                spacing: 16
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: viewersSheet.searchQuery !== ""
                          ? Tr.t("Hech kim topilmadi.")
                          : viewersSheet.onlyContacts
                            ? Tr.t("Kontaktlaringizdan hali hech kim ko'rmadi.")
                            : !viewersSheet.isMine
                              ? Tr.t("Hali hech kim reaksiya bildirmadi.")
                              : (viewersSheet.expired && viewersSheet.totalViews > 0)
                                ? (viewersSheet.isPremium
                                   ? Tr.t("Bu hikoyaning ko'ruvchilari yozib olinmagan.")
                                   : Tr.t("Ko'ruvchilar ro'yxati muddati o'tgan. Telegram Premium bilan doimiy ko'rishlar tarixini oching."))
                                : Tr.t("Hali hech kim ko'rmadi.")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
                Rectangle {
                    visible: viewersSheet.isMine && viewersSheet.expired && viewersSheet.totalViews > 0
                             && !viewersSheet.isPremium && viewersSheet.searchQuery === "" && !viewersSheet.onlyContacts
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 220); height: 44; radius: 12
                    color: premBtnHit.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Telegram Premium"
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    MouseArea { id: premBtnHit; anchors.fill: parent; onClicked: viewersSheet.openPremium() }
                }
            }
            ListView {
                id: vList
                x: 0; y: vSearchWrap.y + vSearchWrap.height
                width: parent.width; height: parent.height - y - 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                bottomMargin: Math.max(osk.h, safe.bottom) + 12
                model: viewersSheet.items
                onAtYEndChanged: if (atYEnd && viewersSheet.nextOffset !== "" && !viewersSheet.loading) viewersSheet.more()
                footer: Item {
                    width: vList.width
                    height: viewersSheet.showPartialFooter ? premFootCol.implicitHeight + 28 : 0
                    visible: viewersSheet.showPartialFooter
                    Column {
                        id: premFootCol
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 6
                        Text {
                            width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                            text: viewersSheet.isPremium
                                  ? Tr.t("Bu hikoyaning barcha ko'ruvchilari saqlanib qolmagan.")
                                  : Tr.t("To'liq ko'rishlar tarixi faqat Telegram Premium bilan saqlanadi.")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        Text {
                            visible: !viewersSheet.isPremium
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Telegram Premium ›"
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: viewersSheet.openPremium() }
                        }
                    }
                }
                delegate: Rectangle {
                    id: vRow
                    required property var modelData
                    required property int index
                    width: vList.width; height: 60
                    color: vRowHit.pressed ? Theme.highlight : "transparent"
                    readonly property var who: (store.seen, viewersSheet.actorOf(modelData.actor_id))
                    readonly property string kind: modelData.type ? modelData.type["@type"] : ""
                    readonly property var rx: kind === "storyInteractionTypeView" ? modelData.type.chosen_reaction_type : null
                    readonly property string reactEmoji: !rx ? ""
                                                         : rx["@type"] === "reactionTypeEmoji" ? (rx.emoji || "")
                                                         : rx["@type"] === "reactionTypePaid" ? "⭐" : "✨"
                    StoryAvatar {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        chatId: vRow.who.id
                        size: 42
                        under: Theme.card
                    }
                    Column {
                        x: 70; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 118
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: vRow.who.name
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            visible: text !== ""
                            text: {
                                const tm = sv.seenTime(vRow.modelData.interaction_date)
                                if (vRow.kind === "storyInteractionTypeForward")
                                    return "↪ " + Tr.t("Uzatdi") + (tm ? " · " + tm : "")
                                if (vRow.kind === "storyInteractionTypeRepost")
                                    return "↻ " + Tr.t("Repost qildi") + (tm ? " · " + tm : "")
                                return tm ? "✓✓ " + tm : ""
                            }
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    Text {
                        visible: vRow.reactEmoji !== ""
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: vRow.reactEmoji
                        color: vRow.reactEmoji.indexOf("❤") === 0 ? "#ff3b30"
                             : vRow.reactEmoji === "⭐" ? "#f5a623" : Theme.text
                        font.pixelSize: 22
                    }
                    Icon {
                        visible: vRow.kind === "storyInteractionTypeForward" || vRow.kind === "storyInteractionTypeRepost"
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        name: "forward"; color: Theme.accent
                    }
                    Rectangle {
                        x: 70; anchors.bottom: parent.bottom
                        width: parent.width - 70; height: 0.5
                        color: Theme.separator
                        visible: vRow.index < viewersSheet.items.length - 1 || viewersSheet.showPartialFooter
                    }
                    MouseArea {
                        id: vRowHit
                        anchors.fill: parent
                        onClicked: viewersSheet.openProfile(vRow.modelData.actor_id)
                        onPressAndHold: viewersSheet.actorMenu(vRow.modelData.actor_id, vRow.who.name)
                    }
                }
            }
        }
    }

    // ⋯: iOS-style bottom action sheet over the story
    Item {
        id: menuSheet
        anchors.fill: parent
        z: 7
        property bool open: false
        property var choices: []
        visible: mDim.opacity > 0
        Rectangle {
            id: mDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: menuSheet.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent; onClicked: menuSheet.open = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: menuSheet.open ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            spacing: 8
            Rectangle {
                width: parent.width; height: mCol.height
                radius: 14
                color: Theme.menu
                clip: true
                Column {
                    id: mCol
                    width: parent.width
                    Repeater {
                        model: menuSheet.choices
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: mCol.width; height: 54
                            color: mHit.pressed ? Theme.highlight : "transparent"
                            Rectangle { visible: index > 0; width: parent.width; height: 0.5; color: Theme.separator }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 32
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: parent.modelData.t
                                color: parent.modelData.red ? Theme.danger : Theme.accent
                                font.family: Theme.font; font.pixelSize: 19
                            }
                            MouseArea {
                                id: mHit
                                anchors.fill: parent
                                onClicked: {
                                    const run = parent.modelData.run
                                    menuSheet.open = false
                                    if (run)
                                        run()
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 54
                radius: 14
                color: mCancel.pressed ? Theme.highlight : Theme.menu
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold
                }
                MouseArea { id: mCancel; anchors.fill: parent; onClicked: menuSheet.open = false }
            }
        }
    }

    // Shikoyat qilish (reportStory): options or details, step by step
    Item {
        id: reportSheet
        anchors.fill: parent
        z: 8
        property bool open: false
        property var step: null
        visible: open
        function ask(st) {
            step = st
            whyField.text = ""
            open = true
            if (!st.options)
                whyField.forceActiveFocus()
        }
        function close() {
            open = false
            whyField.focus = false
            osk.hide()
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
        MouseArea { anchors.fill: parent; onClicked: reportSheet.close() }
        Rectangle {
            id: rCard
            readonly property real kb: Math.max(osk.h, safe.bottom)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(56, (parent.height - kb - height) / 2)
            width: Math.min(parent.width - 48, 300)
            height: Math.min(rSteps.height + 48, parent.height - kb - 110)
            radius: 16; clip: true
            color: Theme.menu
            MouseArea { anchors.fill: parent }
            Flickable {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: rCancel.top }
                contentHeight: rSteps.height
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Column {
                    id: rSteps
                    width: rCard.width
                    readonly property var st: reportSheet.step || {}
                    Text {
                        x: 16; width: parent.width - 32
                        topPadding: 14; bottomPadding: 8
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        text: rSteps.st.options ? (rSteps.st.title || Tr.t("Shikoyat sababi"))
                              : Tr.t(rSteps.st.optional ? "Batafsil yozing (ixtiyoriy)" : "Batafsil yozing")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: rSteps.st.options || []
                        Rectangle {
                            required property var modelData
                            width: rSteps.width; height: Math.max(44, rOpt.implicitHeight + 20)
                            color: rHit.pressed ? Theme.highlight : "transparent"
                            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                            Text {
                                id: rOpt
                                x: 16; width: parent.width - 48
                                anchors.verticalCenter: parent.verticalCenter
                                wrapMode: Text.Wrap
                                text: parent.modelData.text
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 16
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "›"; color: Theme.grey; font.pixelSize: 20
                            }
                            MouseArea {
                                id: rHit
                                anchors.fill: parent
                                onClicked: {
                                    const id = parent.modelData.id
                                    reportSheet.close()
                                    sv.report(id, "")
                                }
                            }
                        }
                    }
                    Rectangle {
                        visible: !rSteps.st.options
                        x: 16; width: parent.width - 32
                        height: visible ? Math.max(44, whyField.contentHeight + 20) : 0
                        radius: 10
                        color: Theme.field
                        TextEdit {
                            id: whyField
                            anchors { fill: parent; margins: 10 }
                            color: Theme.text
                            wrapMode: TextEdit.Wrap
                            font.family: Theme.font; font.pixelSize: 15
                        }
                    }
                    Item { visible: !rSteps.st.options; width: 1; height: 10 }
                    Rectangle {
                        visible: !rSteps.st.options
                        width: rSteps.width; height: 46
                        color: rSend.pressed ? Theme.highlight : "transparent"
                        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Yuborish")
                            color: !rSteps.st.optional && !whyField.text.trim() ? Theme.grey : Theme.accent
                            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: rSend
                            anchors.fill: parent
                            enabled: !!rSteps.st.optional || whyField.text.trim() !== ""
                            onClicked: {
                                const opt = rSteps.st.option || "", txt = whyField.text.trim()
                                reportSheet.close()
                                sv.report(opt, txt)
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: rCancel
                anchors.bottom: parent.bottom
                width: parent.width; height: 48
                color: rCanHit.pressed ? Theme.highlight : "transparent"
                Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                }
                MouseArea { id: rCanHit; anchors.fill: parent; onClicked: reportSheet.close() }
            }
        }
    }

    Alert { id: confirm; anchors.fill: parent; z: 9 }

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
