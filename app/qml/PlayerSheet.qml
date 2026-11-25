// A song's player, from the bottom over everything (the owner's iPad, #26406: Telegram-iOS's
// OverlayAudioPlayerController): the chat's songs above (a tap plays one, the one playing has ⏸), then
// what plays -- its picture, title and performer -- the bar to drag through it with the time gone and
// its length, and ⏮ ⏯ ⏭; under them «Profilga qo'shish» (Telegram-iOS's OverlayAudioPlayerControlsNode:
// a 52 pt button, in the accent with ♫+ — or grey «Profildan olib tashlash» once it is there — and a word
// that it was done). The dim over the rest, a tap there or the back button closes it.
import QtQuick
import QtQuick.Window

Item {
    id: sheet
    property var player
    property var store
    anchors.fill: parent
    visible: player && player.sheetOpen
    z: 20

    property var songs: []               // the chat's songs, as the list shows them: [{ id, title, sub, dur }]
    property var found: ({})             // id -> its message (to play)
    onVisibleChanged: if (visible) load()
    Connections { target: sheet.player; function onListChanged() { if (sheet.visible) sheet.load() } }
    // a profile's songs (Player.list): «X pleylisti» over them with ✕, and no list when it is the one song
    readonly property var list: player ? player.list : null
    readonly property bool listed: !!list
    function load() {
        if (player.list) {
            const l = player.list
            songs = l.songs.length > 1 ? l.songs.map((a, i) => ({ id: player.listId(l, i), at: i, title: a.title || a.file_name || Tr.t("Musiqa"),
                                                                  sub: a.performer || "", dur: a.duration })) : []
            found = ({})
            return
        }
        const chat = player.chatId
        store.send({ "@type": "searchChatMessages", chat_id: chat, topic_id: null, query: "", sender_id: null,
                     from_message_id: 0, offset: 0, limit: 50, filter: { "@type": "searchMessagesFilterAudio" } }, (r) => {
            if (player.chatId !== chat)
                return
            const out = [], f = {}
            for (const m of r.messages || []) {     // newest first, as iOS lists them
                const a = player.about(m)
                if (!a)
                    continue
                f[m.id] = m
                out.push({ id: m.id, title: a.title, sub: a.sub, dur: m.content.audio ? m.content.audio.duration : 0 })
            }
            found = f
            songs = out
        })
    }
    function close() { player.sheetOpen = false }
    function clock(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    Rectangle {
        id: box
        width: parent.width
        height: Math.min(parent.height - 80, (sheet.listed ? 56 + 206 + Math.min(sheet.songs.length, 5) * 56 + (sheet.songs.length ? 8 : 0) : 560)
                                             + (keep.visible ? 68 : 0) + safe.bottom)
        y: parent.height - height
        radius: 22
        color: Theme.card
        MouseArea { anchors.fill: parent }      // (taps stay in it)
        Rectangle {     // the grabber
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8; width: 36; height: 5; radius: 2.5
            color: Theme.separator
        }
        Item {          // a profile's: ✕ and «X pleylisti» (Telegram-iOS's playlist title)
            visible: sheet.listed
            width: parent.width; height: 56
            Item {
                x: 6; y: 8; width: 44; height: 44
                opacity: closeHit.pressed ? 0.5 : 1
                Icon { anchors.centerIn: parent; name: "cross"; color: Theme.text }
                MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.close() }
            }
            Text {
                anchors.centerIn: parent; anchors.verticalCenterOffset: 4
                width: Math.min(implicitWidth, parent.width - 120)
                elide: Text.ElideRight
                text: sheet.list ? Tr.f("%1 pleylisti", sheet.list.name) : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
        }
        ListView {
            id: list
            x: 12; y: sheet.listed ? 56 : 24
            width: parent.width - 24
            height: now.y - y - 8
            clip: true
            model: sheet.songs
            delegate: Item {
                required property var modelData
                readonly property bool current: sheet.player.msgId === modelData.id
                width: list.width; height: 56
                Rectangle {
                    x: 4; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 20
                    color: Theme.accent
                    Icon {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: name === "play" ? 1.5 : 0
                        width: 18; height: 18
                        name: current && sheet.player.playing ? "pause" : "play"
                        color: "white"
                    }
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 8
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: modelData.title
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: sheet.clock(modelData.dur) + (modelData.sub ? " · " + modelData.sub : "")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: current ? sheet.player.toggle()
                             : sheet.listed ? sheet.player.playList(sheet.list, modelData.at) : sheet.player.playMessage(sheet.found[modelData.id])
                }
            }
        }
        Rectangle {     // the song in our profile's music, or out of it (shown once it is known which)
            id: keep
            visible: sheet.player && sheet.player.onProfile !== null
            x: 30; width: parent.width - 60; height: 52; radius: 26
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + safe.bottom    // (clear of the shell's nav line)
            readonly property bool there: !!(sheet.player && sheet.player.onProfile)
            color: there ? Qt.rgba(0.5, 0.5, 0.55, 0.18) : Theme.accent
            opacity: keepHit.pressed ? 0.7 : 1
            Row {
                anchors.centerIn: parent
                spacing: 8
                Icon {
                    visible: !keep.there
                    anchors.verticalCenter: parent.verticalCenter
                    name: "savemusic"; color: "white"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: keep.there ? Tr.t("Profildan olib tashlash") : Tr.t("Profilga qo'shish")
                    color: keep.there ? Theme.text : "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
            }
            MouseArea {
                id: keepHit
                anchors.fill: parent
                onClicked: {
                    const yes = !keep.there
                    sheet.player.keepOnProfile(yes, (ok) => sheet.tell(!ok ? Tr.t("Bo'lmadi") : yes ? Tr.t("Profilingizga qo'shildi")
                                                                                             : Tr.t("Profilingizdan olib tashlandi")))
                }
            }
        }
        Item {          // what plays
            id: now
            width: parent.width
            height: 190
            anchors.bottom: keep.visible ? keep.top : parent.bottom; anchors.bottomMargin: keep.visible ? 16 : 16 + safe.bottom
            Rectangle { visible: !sheet.listed || sheet.songs.length > 0; x: 16; width: parent.width - 32; height: 0.5; color: Theme.separator }
            Rectangle {     // its picture: the album's, else a note
                x: 16; y: 16
                width: 48; height: 48; radius: 8
                color: Theme.highlight
                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready && !(art.status === Image.Loading && art.retained)
                    text: "♪"
                    color: Theme.grey
                    font.pixelSize: 26
                }
                Image {
                    id: art
                    anchors.fill: parent
                    source: sheet.player ? sheet.player.cover : ""
                    sourceSize: Qt.size(Math.ceil(48 * Screen.devicePixelRatio), Math.ceil(48 * Screen.devicePixelRatio))
                    asynchronous: true
                    cache: false
                    // the song before's picture kept while the next one's loads (else a blank, then ♪, at ⏭)
                    retainWhileLoading: true
                    property bool retained: false
                    onStatusChanged: if (status === Image.Ready) retained = true
                    onSourceChanged: if (String(source) === "") retained = false
                }
            }
            Column {
                x: 76; y: 18
                width: parent.width - x - 16
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: sheet.player ? sheet.player.title : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: sheet.player ? sheet.player.sub : ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
            Item {          // how far: drag to go there
                id: bar
                x: 16; y: 84
                width: parent.width - 32; height: 24
                readonly property real done: sheet.player && sheet.player.duration > 0
                                            ? Math.min(1, sheet.player.position / sheet.player.duration) : 0
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 4; radius: 2
                    color: Theme.separator
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * bar.done; height: 4; radius: 2
                    color: Theme.text
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    function go(x) {
                        if (sheet.player.duration > 0)
                            sheet.player.seek(Math.max(0, Math.min(1, (x - 8) / bar.width)) * sheet.player.duration)
                    }
                    onPressed: (e) => go(e.x)
                    onPositionChanged: (e) => go(e.x)
                }
            }
            Text {
                x: 16; y: 110
                text: sheet.player ? sheet.clock(sheet.player.position / 1000) : ""
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16; y: 110
                text: sheet.player ? sheet.clock(sheet.player.duration / 1000) : ""
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 132
                spacing: 36
                Repeater {
                    model: ["prev", "toggle", "next"]
                    Item {
                        required property string modelData
                        width: 52; height: 52
                        opacity: hit.pressed ? 0.5 : 1
                        Icon {
                            anchors.centerIn: parent
                            width: modelData === "toggle" ? 40 : 34; height: width
                            name: modelData === "toggle" ? (sheet.player && sheet.player.playing ? "pause" : "play") : modelData
                            color: Theme.text
                        }
                        MouseArea {
                            id: hit
                            anchors.fill: parent
                            onClicked: modelData === "toggle" ? sheet.player.toggle() : sheet.player.step(modelData === "prev")
                        }
                    }
                }
            }
        }
    }

    // a word that comes and goes over the sheet (Telegram-iOS's UndoOverlayController)
    function tell(text) {
        toastText.text = text
        toastBox.opacity = 1
        toastAway.restart()
    }
    Rectangle {
        id: toastBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: box.y - height - 12
        width: Math.min(parent.width - 40, toastText.implicitWidth + 28); height: toastText.implicitHeight + 16
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.75)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
    }
    Timer { id: toastAway; interval: 2200; onTriggered: toastBox.opacity = 0 }
}
