// The signed-in user (Telegram-iOS's My Profile, PeerInfoScreen of oneself): the picture, the name, online; the
// profile's song («♫ Nom  Ijrochi ›», userFullInfo.first_profile_audio: tapped, it plays); the card — mobile, bio,
// username, birthday; then «Postlar | Arxivlangan postlar» — the stories kept on the profile
// (getChatPostedToChatPageStories) or archived (getChatArchivedStories), three a row with the views and a video's
// length, a tap opens them (StoryViewer.showOne). «Tahrirlash» on the bar: ProfileEditPage.
import QtQuick

SubPage {
    id: page
    title: ""
    action: Tr.t("Tahrirlash")
    onActed: {
        const c = Qt.createComponent("ProfileEditPage.qml")
        if (c.status === Component.Error)
            return console.warn("nullgram:", c.errorString())
        nav.push(c, { full: page.full })
    }
    property string photo: ""
    property var full: null
    property int tab: 0                     // 0 posts, 1 archived
    property var posts: null                // stories, as got
    property var archived: null
    readonly property var me: (store.seen, store.me)
    readonly property var shown: tab ? archived : posts
    readonly property var song: full && full.first_profile_audio ? full.first_profile_audio : null

    Component.onCompleted: load()
    onVisibleChanged: if (visible && full) load()       // (back from editing: what was changed)
    function load() {
        if (!me)
            return
        store.userPhoto(me, (path) => page.photo = path)
        store.send({ "@type": "getUserFullInfo", user_id: me.id }, (r) => {
            if (r["@type"] === "userFullInfo")
                page.full = r
        })
        store.send({ "@type": "getChatPostedToChatPageStories", chat_id: me.id, from_story_id: 0, limit: 60 }, (r) => {
            page.posts = r["@type"] === "stories" ? r.stories : []
            page.pinned = r["@type"] === "stories" ? r.pinned_story_ids || [] : []
        })
        store.send({ "@type": "getChatArchivedStories", chat_id: me.id, from_story_id: 0, limit: 60 }, (r) => {
            page.archived = r["@type"] === "stories" ? r.stories : []
        })
    }
    function clock(s) {
        s = Math.round(s || 0)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function play() {           // (our songs, as Telegram-iOS's playlist: Player.openProfile)
        player.openProfile(me.id, me.first_name || "", song)
    }
    TextEdit { id: clip; visible: false }
    function copy(text, said) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        nav.say(said)
    }

    // ---- the picture, the name, online ----
    Item {
        width: parent.width; height: 186
        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100; height: 100
            source: page.photo
            letters: page.me ? store.letters(page.me.first_name + " " + page.me.last_name) : ""
            tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 114; width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: page.me ? (page.me.first_name + " " + page.me.last_name).trim() : ""
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 148
            text: Tr.t("onlayn")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    // ---- the profile's song ----
    SettingsGroup {
        visible: !!page.song
        Item {
            width: parent.width; height: 44
            Text {
                x: 16; width: parent.width - 48
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: page.song ? "♫ <b>" + (page.song.title || page.song.file_name || Tr.t("Musiqa")) + "</b>"
                                  + (page.song.performer ? "  <font color='" + Theme.grey + "'>" + page.song.performer + "</font>" : "") : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
            Text { text: "›"; color: Theme.grey; font.pixelSize: 24; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter }
            MouseArea { anchors.fill: parent; onClicked: page.play() }
        }
    }

    // ---- mobile, bio, username, birthday ----
    SettingsGroup {
        Repeater {
            id: facts
            model: {
                const out = []
                const me = page.me, f = page.full
                if (me && me.phone_number)
                    out.push({ k: Tr.t("mobil"), v: "+" + me.phone_number, copy: "+" + me.phone_number, said: Tr.t("Raqam nusxalandi") })
                if (f && f.bio && f.bio.text)
                    out.push({ k: Tr.t("bio"), v: f.bio.text })
                if (me && me.usernames && me.usernames.active_usernames.length)
                    out.push({ k: Tr.t("foydalanuvchi nomi"), v: "@" + me.usernames.active_usernames.join(", @"),
                               copy: "https://t.me/" + me.usernames.active_usernames[0], said: Tr.t("Havola nusxalandi") })
                if (f && f.birthdate)
                    out.push({ k: Tr.t("tug'ilgan kun"), v: Tr.date(f.birthdate.day, f.birthdate.month, f.birthdate.year) })
                return out
            }
            Item {
                required property var modelData
                required property int index
                width: parent.width; height: value.y + value.height + 10
                Text {
                    x: 16; y: 9
                    text: parent.modelData.k
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Text {
                    id: value
                    x: 16; y: 29
                    width: parent.width - 32
                    wrapMode: Text.Wrap
                    text: parent.modelData.v
                    color: parent.modelData.copy ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: 16
                }
                Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                            visible: parent.index < facts.count - 1 }
                MouseArea {
                    anchors.fill: parent
                    enabled: !!parent.modelData.copy
                    onClicked: page.copy(parent.modelData.copy, parent.modelData.said)
                }
            }
        }
    }
    Item { width: 1; height: 4 }

    // ---- posts / archived posts ----
    Segments {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 32, 300)
        items: [Tr.t("Postlar"), Tr.t("Arxivlangan postlar")]
        index: page.tab
        onPicked: (i) => page.tab = i
    }
    Item { width: 1; height: 12 }
    Item {
        width: parent.width
        visible: !!page.shown && page.shown.length === 0
        height: visible ? 120 : 0
        Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 6
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: Tr.t(page.tab ? "Arxivda hikoya yo'q" : "Hali post yo'q")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.t(page.tab ? "Muddati o'tgan hikoyalaringiz shu yerda saqlanadi — faqat sizga ko'rinadi."
                                    : "Profilda saqlagan hikoyalaringiz shu yerda — hamma ko'radi.")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
        }
    }
    Grid {
        x: 1
        columns: 3
        spacing: 1
        readonly property real cell: (page.width - 4) / 3
        Repeater {
            model: page.shown || []
            Item {
                id: tile
                required property var modelData
                required property int index
                width: parent.cell; height: parent.cell * 1.6
                readonly property var c: modelData.content
                readonly property bool video: c["@type"] === "storyContentVideo"
                property string pic: ""
                Component.onCompleted: {
                    let f = null
                    if (video)
                        f = c.video.thumbnail ? c.video.thumbnail.file : null
                    else if (c["@type"] === "storyContentPhoto") {
                        for (const z of c.photo.sizes || [])         // the smallest that still fills a third
                            if (!f || (z.width >= 240 && z.width < f.w) || f.w < 240)
                                f = { file: z.photo, w: z.width }
                        f = f ? f.file : null
                    }
                    if (f)
                        store.fetch(f, 8, (p) => tile.pic = p)
                }
                Rectangle { anchors.fill: parent; color: Theme.dark ? "#2c2c2e" : "#e5e5ea" }
                Image {
                    anchors.fill: parent
                    source: tile.pic ? "file://" + tile.pic : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 256
                }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width; height: 28
                    gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "#80000000" } }
                }
                Text {
                    x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                    text: tile.modelData.interaction_info ? "👁 " + store.short(tile.modelData.interaction_info.view_count) : ""
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                    visible: tile.video
                    text: tile.video ? page.clock(tile.c.video.duration) : ""
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Rectangle {     // pinned on the profile
                    visible: !page.tab && !!page.posts && (page.pinned || []).indexOf(tile.modelData.id) >= 0
                    x: parent.width - 22; y: 6; width: 16; height: 16; radius: 8
                    color: "#80000000"
                    Icon { anchors.centerIn: parent; name: "pin"; width: 10; height: 10; color: "white" }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: storyView.showOne(page.me.id, page.shown.map((s) => s.id), tile.index)
                }
            }
        }
    }
    property var pinned: []
    Item { width: 1; height: 24 }
}
