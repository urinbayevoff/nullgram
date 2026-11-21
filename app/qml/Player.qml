// The one sound Nullgram plays, a voice note or a song, as Telegram-iOS's shared media player: it
// goes on when its chat closes (the mini player over the chats and every chat says what it is), at
// the speed chosen (1x, 1.5x, 2x: Prefs.playRate, kept), and when it ends the next one follows -- a
// voice note: the message right after it, if that is a voice note too (as ChatPage did); a song: the
// chat's next song (searchChatMessages, searchMessagesFilterAudio), newer ones first as the chat reads.
// Prev/next go through the chat's songs either way. A round video is in the same queue (Telegram-iOS's
// voice and instant video playlist): its picture and sound are its bubble's (ChatPage's InlineVideo, which
// tells how far it is: roundPos, roundDur), the player only says which one and whether it is paused;
// a voice note or a round video ended, the next message plays if it is one of the two.
import QtQuick
import QtMultimedia

Item {
    id: player
    property var store
    property var chatId: 0
    property var msgId: 0                // 0: nothing
    property string kind: ""             // voice | audio | round
    property string title: ""            // a song's title, a voice note's sender
    property string sub: ""              // its performer, a voice note's «Ovozli xabar»
    readonly property bool round: kind === "round"
    readonly property bool playing: round ? !roundPaused : sound.playbackState === MediaPlayer.PlayingState
    readonly property real position: round ? roundPos : sound.position
    readonly property real duration: round ? roundDur : sound.duration
    property bool roundPaused: false     // a round video: held (tapped while it played), its bubble still big
    property real roundPos: 0            // ms, as its bubble's player says
    property real roundDur: 0
    property string roundPath: ""        // its file (the corner's circle plays it when its bubble is off the screen)
    readonly property real rate: Prefs.playRate || 1
    property string cover: ""            // a song's album picture for PlayerSheet (image://pic, 48 pt, its corners
                                         // 8), first Telegram's tiny blurred one; "": none (a note there)
    property bool sheetOpen: false       // a song's player over everything (PlayerSheet)
    // the song as Telegram has it ({ file, duration, title, performer }: what addProfileAudio takes), and
    // whether it is in our profile's music: true, false, or null while not known (isProfileAudio)
    property var song: null
    property var onProfile: null
    function showSheet() { if (msgId) sheetOpen = true }
    // a profile's songs (Telegram-iOS's «X's Playlist», its profile song row tapped): { userId, name, songs: [audio] },
    // played in turn in place of a chat's; null: a chat's. msgId is then "p<user>:<file>" (no chat has it)
    property var list: null
    property int listAt: -1
    function listId(l, i) { return "p" + l.userId + ":" + l.songs[i].audio.id }
    // a profile's song row tapped: its songs asked (getUserProfileAudios; `first`, its first_profile_audio, if that
    // fails), the first played and the sheet over everything; already playing them: just the sheet
    function openProfile(userId, name, first) {
        if (list && list.userId === userId && msgId) {
            sheetOpen = true
            return
        }
        store.send({ "@type": "getUserProfileAudios", user_id: userId, offset: 0, limit: 100 }, (r) => {
            const songs = r["@type"] === "audios" && r.audios.length ? r.audios : first ? [first] : []
            if (!songs.length)
                return
            player.playList({ userId: userId, name: name, songs: songs }, 0)
            player.sheetOpen = true
        })
    }
    function playList(l, i) {
        const a = l.songs[i]
        if (!a)
            return
        const id = listId(l, i)
        if (msgId === id) {
            start({ chatId: 0, msgId: id })         // (the same one: paused or on again)
            return
        }
        list = l                // (the sheet lists them at once, while the song comes down)
        listAt = i
        waiting = id
        store.fetch(a.audio, 32, (path) => {
            if (player.waiting !== id)
                return
            player.start({ chatId: 0, msgId: id, path: path, kind: "audio", listed: true, dur: a.duration,
                           title: a.title || a.file_name || Tr.t("Musiqa"), sub: a.performer || "" })
        })
    }

    // play this one (o: { chatId, msgId, path, kind, title, sub, from }): the same one again pauses or
    // goes on (or, given `from`, goes there)
    function start(o) {
        if (o.chatId === chatId && o.msgId === msgId) {
            if (round) {
                roundPaused = !roundPaused
                return
            }
            if (o.from > 0) {
                sound.position = o.from
                sound.play()
            } else if (playing)
                sound.pause()
            else
                sound.play()
            return
        }
        waiting = 0
        if (!o.listed) {
            list = null
            listAt = -1
        }
        chatId = o.chatId
        msgId = o.msgId
        kind = o.kind
        title = o.title || ""
        sub = o.sub || ""
        roundPaused = false
        roundPos = 0
        roundDur = (o.dur || 0) * 1000
        roundPath = o.kind === "round" ? o.path || "" : ""
        sound.from = o.from || 0
        if (kind === "round") {     // (its bubble plays it)
            sound.stop()
            sound.source = ""
        } else {
            sound.source = "file://" + o.path
            sound.play()
        }
        findCover()
        if (kind === "voice" || kind === "round")       // heard (the other side's dot goes): Telegram-iOS's markMessageContentAsConsumed
            store.send({ "@type": "openMessageContent", chat_id: chatId, message_id: msgId })
    }
    function toggle() {
        if (round)
            roundPaused = !roundPaused
        else if (playing)
            sound.pause()
        else if (msgId)
            sound.play()
    }
    function pause() {
        if (round)
            roundPaused = true
        else
            sound.pause()
    }
    function stop() {
        sound.stop()
        sound.source = ""
        roundPaused = false
        waiting = 0             // (one being brought down to follow: not any more)
        msgId = 0
        chatId = 0
        kind = ""
        cover = ""
        list = null
        listAt = -1
        sheetOpen = false
    }

    // the song's album picture (Telegram-iOS's player shows it in place of the note): the file's own,
    // else one Telegram found for its title and performer (external_album_covers); its tiny blurred
    // preview while it comes down
    function findCover() {
        cover = ""
        song = null
        onProfile = null
        if (kind !== "audio")
            return
        const chat = chatId, id = msgId
        if (list) {
            useAudio(list.songs[listAt], chat, id)
            return
        }
        store.send({ "@type": "getMessage", chat_id: chat, message_id: id }, (m) => {
            const a = m["@type"] === "message" && m.content.audio
            if (a && player.msgId === id && player.chatId === chat)
                useAudio(a, chat, id)
        })
    }
    function useAudio(a, chat, id) {
        const still = () => player.msgId === id && player.chatId === chat
        song = { file: a.audio.id, duration: a.duration, title: a.title, performer: a.performer }
        store.send({ "@type": "isProfileAudio", file_id: a.audio.id }, (r) => {
            if (still())
                onProfile = r["@type"] === "ok"
        })
        if (a.album_cover_minithumbnail)
            cover = "image://pic/8/48/mini/" + a.album_cover_minithumbnail.data
        const t = a.album_cover_thumbnail || (a.external_album_covers || [])[0]
        if (t && t.file)
            store.fetch(t.file, 1, (path) => {
                if (still())
                    cover = "image://pic/8/48/" + path
            })
    }
    // the song put in our profile's music, or taken out of it (Telegram-iOS's «Add to Profile»); done(ok)
    function keepOnProfile(yes, done) {
        const s = song
        if (!s)
            return
        const req = yes ? { "@type": "addProfileAudio", audio: { "@type": "inputAudio", audio: { "@type": "inputFileId", id: s.file },
                                                                 album_cover_thumbnail: null, duration: s.duration,
                                                                 title: s.title, performer: s.performer } }
                        : { "@type": "removeProfileAudio", file_id: s.file }
        store.send(req, (r) => {
            const ok = r["@type"] === "ok"
            if (ok && song === s)
                onProfile = yes
            done(ok)
        })
    }
    function seek(ms) { sound.position = ms }
    // 1x → 1.5x → 2x → 1x, said at the foot (Main's Toast: Telegram-iOS's .audioRate tooltip)
    signal rated(real r)
    function nextRate() {
        Prefs.playRate = rate >= 2 ? 1 : rate >= 1.5 ? 2 : 1.5
        rated(Prefs.playRate)
    }
    function rateText(r) {
        return (r === 1.5 ? "1.5" : String(Math.round(r))) + "x"
    }

    // a message as the player says it, and what it plays (null: not a voice note, a song or an audio file)
    function about(m) {
        const c = m.content, t = c["@type"]
        if (t === "messageVoiceNote")
            return { kind: "voice", file: c.voice_note.voice,
                     title: m.is_outgoing ? Tr.t("Siz") : store.senderName(m.sender_id, false), sub: Tr.t("Ovozli xabar") }
        if (t === "messageVideoNote")
            return { kind: "round", file: c.video_note.video, dur: c.video_note.duration,
                     title: m.is_outgoing ? Tr.t("Siz") : store.senderName(m.sender_id, false), sub: Tr.t("Video xabar") }
        if (t === "messageAudio")
            return { kind: "audio", file: c.audio.audio, title: c.audio.title || c.audio.file_name || Tr.t("Musiqa"),
                     sub: c.audio.performer || "" }
        if (t === "messageDocument" && (c.document.mime_type || "").startsWith("audio/"))
            return { kind: "audio", file: c.document.document, title: c.document.file_name, sub: "" }
        return null
    }
    // m (a message) brought down if need be, then played
    function playMessage(m) {
        const a = about(m)
        if (!a) {
            stop()
            return
        }
        const want = m.id, chat = m.chat_id
        waiting = want          // (first: a file already here is handed back at once)
        store.fetch(a.file, 32, (path) => {
            if (player.waiting !== want)
                return      // (something else was started meanwhile)
            player.start({ chatId: chat, msgId: want, path: path, kind: a.kind, title: a.title, sub: a.sub, dur: a.dur })
        })
    }
    property var waiting: 0              // the message being brought down to be played next

    // the next (or, back, the one before) of the chat's songs; a voice note ended: the message after it
    function step(back) {
        if (!msgId)
            return
        if (list) {            // a profile's songs: the next in its list, or the one before
            const i = listAt + (back ? -1 : 1)
            if (i >= 0 && i < list.songs.length)
                playList(list, i)
            else if (!back)
                ended()
            else
                seek(0)
            return
        }
        const chat = chatId, id = msgId
        if ((kind === "voice" || kind === "round") && !back) {
            store.send({ "@type": "getChatHistory", chat_id: chat, from_message_id: id, offset: -2, limit: 3, only_local: false }, (r) => {
                if (player.msgId !== id)
                    return
                const newer = (r.messages || []).filter((m) => m.id > id).sort((a, b) => a.id - b.id)[0]
                const t = newer ? newer.content["@type"] : ""
                if (t === "messageVoiceNote" || t === "messageVideoNote")
                    player.playMessage(newer)
                else
                    player.ended()
            })
            return
        }
        store.send({ "@type": "searchChatMessages", chat_id: chat, topic_id: null, query: "", sender_id: null,
                     from_message_id: id, offset: -2, limit: 5, filter: { "@type": "searchMessagesFilterAudio" } }, (r) => {
            if (player.msgId !== id)
                return
            const all = r.messages || []
            const m = back ? all.filter((m) => m.id < id).sort((a, b) => b.id - a.id)[0]
                           : all.filter((m) => m.id > id).sort((a, b) => a.id - b.id)[0]
            if (m)
                player.playMessage(m)
            else if (!back)
                player.ended()
            else
                player.seek(0)
        })
    }
    // the last one played out: it stays in the mini player, at its start, paused (iOS keeps it until ✕); a round
    // video goes (its bubble small again)
    function ended() {
        if (round)
            stop()
        else
            sound.stop()
    }

    MediaPlayer {
        id: sound
        audioOutput: AudioOutput {}
        playbackRate: player.rate
        property real from: 0           // where it is to start (a timestamp tapped), once it can go there
        function begin() {
            // (seekable comes while it still loads, and a position given then is lost: once loaded)
            if (from > 0 && seekable && mediaStatus !== MediaPlayer.LoadingMedia && mediaStatus !== MediaPlayer.NoMedia) {
                position = from
                from = 0
            }
        }
        onSeekableChanged: begin()
        onMediaStatusChanged: {
            begin()
            if (mediaStatus === MediaPlayer.EndOfMedia)
                player.step(false)
        }
    }
}
