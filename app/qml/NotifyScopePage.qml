// One kind of notifications, as Telegram-iOS's NotificationsPeerCategoryController (private chats, groups, channels, stories) and
// ReactionNotificationSettingsController (reactions).
// Chats: «Bildirishnomalarni ko'rsatish» (the scope's mute_for), «PARAMETRLAR»: «Xabar ko'rinishi» (show_preview), «Ovoz»
// (the standard one or none); «ISTISNOLAR»: «Istisno qo'shish» (FolderChatsPage over the chats of that kind: a chat picked gets
// the other way than the rest, one unpicked its defaults back), the chats with their own settings (getChatNotificationSettingsExceptions:
// «Har doim yoqilgan», «Har doim o'chiq», «HH:mm gacha ovozsiz», the sound, the preview), swiped left for «O'chirish», then
// «Barcha istisnolarni o'chirish» (asked). Stories: «Yangi hikoyalar», else «Muhim hikoyalar» (TDLib's use_default_mute_stories: the
// five chats written to most), «Yuboruvchi ismini ko'rsatish» (show_story_poster). Reactions: to my messages, to my stories (each
// on or off, from everyone or from my contacts: a menu by the row), «Yuboruvchi ismini ko'rsatish».
import QtQuick

SubPage {
    id: page
    property string kind: "private"     // "private", "groups", "channels", "stories", "reactions"
    readonly property string scopeType: kind === "groups" ? "notificationSettingsScopeGroupChats"
                                      : kind === "channels" ? "notificationSettingsScopeChannelChats" : "notificationSettingsScopePrivateChats"
    readonly property bool chats: kind === "private" || kind === "groups" || kind === "channels"
    readonly property var s: store.scopes[scopeType] || null
    readonly property bool enabled: !!s && s.mute_for === 0
    property var excepted: []           // the chats with their own settings
    readonly property var reactions: store.reactionSettings
    property string revealed: ""
    property int known: 0
    readonly property int forever: 2147483647
    title: kind === "private" ? Tr.t("Shaxsiy chatlar") : kind === "groups" ? Tr.t("Guruhlar") : kind === "channels" ? Tr.t("Kanallar")
         : kind === "stories" ? Tr.t("Hikoyalar") : Tr.t("Reaksiyalar")

    function load() {
        store.send({ "@type": "getScopeNotificationSettings", scope: { "@type": scopeType } }, (r) => {
            if (!page || r["@type"] !== "scopeNotificationSettings")
                return
            delete r["@extra"]
            page.keep(r)
        })
        if (chats)
            store.send({ "@type": "getChatNotificationSettingsExceptions", scope: { "@type": scopeType }, compare_sound: false }, (r) => {
                if (!page || !r.chat_ids)
                    return
                page.excepted = r.chat_ids
                for (const id of r.chat_ids)
                    if (!store.chats[id])
                        store.send({ "@type": "getChat", chat_id: id }, () => { if (page) page.known++ })
            })
    }
    Component.onCompleted: load()
    Connections {           // (a chat's own settings changed: its words again)
        target: store
        function onChatChanged(id) { if (page.excepted.indexOf(id) >= 0) page.known++ }
    }
    function keep(r) {
        if (String(r.sound_id) !== "0")
            lastSound = r.sound_id
        const all = Object.assign({}, store.scopes)
        all[scopeType] = r
        store.scopes = all
    }
    function change(fields) {
        const n = Object.assign({}, s, fields)
        n["@type"] = "scopeNotificationSettings"
        keep(n)
        store.send({ "@type": "setScopeNotificationSettings", scope: { "@type": scopeType }, notification_settings: n }, store.check)
    }
    function setReactions(fields) {
        const n = Object.assign({}, reactions, fields)
        n["@type"] = "reactionNotificationSettings"
        delete n["@extra"]
        store.reactionSettings = n
        store.send({ "@type": "setReactionNotificationSettings", notification_settings: n }, store.check)
    }
    function source(on, contacts) {
        return { "@type": !on ? "reactionNotificationSourceNone" : contacts ? "reactionNotificationSourceContacts" : "reactionNotificationSourceAll" }
    }
    property var lastSound: null        // the sound before «Ovoz» was turned off (TDLib's id; 0: none)

    // ---- the chats with their own ----
    function chat(id) {
        known
        return store.chats[id] || null
    }
    // what a chat has of its own (NotificationsPeerCategoryController's exception titles)
    function label(c) {
        known           // (the chat is the same object when its settings change)
        const n = c && c.notification_settings
        if (!n)
            return ""
        const w = []
        let muted = false
        if (!n.use_default_mute_for) {
            if (n.mute_for === 0)
                w.push(Tr.t("Har doim yoqilgan"))
            else if (n.mute_for > 366 * 86400) {
                muted = true
                w.push(Tr.t("Har doim o'chiq"))
            } else {
                const until = new Date(Date.now() + n.mute_for * 1000)
                w.push(Tr.f("%1 gacha ovozsiz", until.toDateString() === new Date().toDateString()
                       ? Qt.formatTime(until, "HH:mm") : Qt.formatDateTime(until, "d MMM HH:mm")))
            }
        }
        if (!muted) {
            if (!n.use_default_sound)
                w.push(Tr.t("Ovoz: maxsus"))
            if (!n.use_default_show_preview)
                w.push(n.show_preview ? Tr.t("Ko'rinishni ko'rsatish") : Tr.t("Ko'rinishni yashirish"))
        }
        return w.join(", ")
    }
    function fits(c) {
        const t = c.type["@type"]
        return kind === "private" ? t === "chatTypePrivate" || t === "chatTypeSecret"
             : kind === "groups" ? t === "chatTypeBasicGroup" || (t === "chatTypeSupergroup" && !c.type.is_channel)
             : t === "chatTypeSupergroup" && c.type.is_channel
    }
    function own(id, mute) {
        store.send({ "@type": "setChatNotificationSettings", chat_id: id, notification_settings: mute === null ? defaults()
                     : Object.assign(defaults(), { use_default_mute_for: false, mute_for: mute ? forever : 0 }) }, store.check)
    }
    function defaults() {
        return { "@type": "chatNotificationSettings", use_default_mute_for: true, mute_for: 0, use_default_sound: true, sound_id: "0",
                 use_default_show_preview: true, show_preview: true, use_default_mute_stories: true, mute_stories: false,
                 use_default_story_sound: true, story_sound_id: "0", use_default_show_story_poster: true, show_story_poster: true,
                 use_default_disable_pinned_message_notifications: true, disable_pinned_message_notifications: false,
                 use_default_disable_mention_notifications: true, disable_mention_notifications: false }
    }
    property Component chooser: null
    function addException() {
        revealed = ""
        if (!chooser)
            chooser = Qt.createComponent("FolderChatsPage.qml")
        const p = nav.push(chooser, { heading: Tr.t("Istisno qo'shish"), pool: (c) => page.fits(c), chosen: excepted })
        if (p)
            p.done.connect((flags, ids) => {
                if (!page)
                    return
                for (const id of ids)
                    if (page.excepted.indexOf(id) < 0)
                        page.own(id, page.enabled)          // (the other way than the rest)
                for (const id of page.excepted)
                    if (ids.indexOf(id) < 0)
                        page.own(id, null)
                page.excepted = ids.slice()
            })
    }
    function drop(id) {
        revealed = ""
        own(id, null)
        excepted = excepted.filter((x) => x !== id)
    }
    function askDropAll() {
        alert.show("", Tr.t("Barcha istisnolarni o'chirasizmi?"),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () => {
                       for (const id of page.excepted)
                           page.own(id, null)
                       page.excepted = []
                   } }])
    }
    function dismiss() {
        if (alert.open)
            alert.open = false
        else if (menu.open)
            menu.open = false
        else if (revealed !== "")
            revealed = ""
        else
            return false
        return true
    }

    // ---- chats ----
    SettingsGroup {
        visible: page.chats && !!page.s
        SettingsRow {
            text: Tr.t("Bildirishnomalarni ko'rsatish"); toggle: true; on: page.enabled; last: true
            onClicked: page.change({ mute_for: page.enabled ? page.forever : 0 })
        }
    }
    SettingsGroup {
        visible: page.chats && !!page.s && (page.enabled || page.excepted.length > 0)
        title: Tr.t("Parametrlar")
        SettingsRow {
            text: Tr.t("Xabar ko'rinishi"); toggle: true; on: !!page.s && page.s.show_preview
            onClicked: page.change({ show_preview: !page.s.show_preview })
        }
        SettingsRow {
            text: Tr.t("Ovoz"); toggle: true; last: true
            on: !!page.s && String(page.s.sound_id) !== "0"
            onClicked: {
                if (on) {
                    page.lastSound = page.s.sound_id
                    page.change({ sound_id: "0" })
                } else
                    page.change({ sound_id: page.lastSound !== null ? page.lastSound : "-1" })
            }
        }
    }
    SettingsGroup {
        visible: page.chats
        title: Tr.t("Istisnolar")
        AddRow { text: Tr.t("Istisno qo'shish"); onTapped: page.addException() }
        Repeater {
            model: page.excepted
            Swiped {
                id: erow
                required property var modelData
                readonly property var c: page.chat(modelData)
                key: String(modelData)
                Avatar {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: erow.c ? store.photoPath(erow.c) : ""; letters: erow.c ? store.letters(erow.c.title) : ""
                    tint: store.tints[Math.abs(erow.modelData) % store.tints.length]; saved: !!erow.c && store.isSaved(erow.c)
                }
                Text {
                    id: eName
                    x: 65; y: 8
                    width: parent.width - x - 16
                    elide: Text.ElideRight
                    text: erow.c ? (store.isSaved(erow.c) ? Tr.t("Saqlangan xabarlar") : store.title(erow.c)) : "…"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
                }
                Text {
                    x: 65; y: eName.y + eName.height + 1
                    width: eName.width
                    elide: Text.ElideRight
                    text: page.label(erow.c)
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
            }
        }
        Item {          // «Barcha istisnolarni o'chirish»
            visible: page.excepted.length > 0
            width: parent.width; height: 46
            Rectangle { anchors.fill: parent; color: Theme.highlight; visible: allHit.pressed }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Barcha istisnolarni o'chirish")
                color: Theme.danger
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { id: allHit; anchors.fill: parent; onClicked: page.askDropAll() }
        }
    }

    // ---- stories ----
    readonly property bool allStories: !!s && !s.use_default_mute_stories && !s.mute_stories
    SettingsGroup {
        visible: page.kind === "stories" && !!page.s
        title: Tr.t("Menga xabar berish…")
        note: page.allStories ? "" : Tr.t("Eng ko'p yozishadigan 5 ta kontaktingizning yangi hikoyalari haqida xabar berish.")
        SettingsRow {
            text: Tr.t("Yangi hikoyalar"); toggle: true; on: page.allStories; last: page.allStories
            onClicked: page.change(page.allStories ? { use_default_mute_stories: true } : { use_default_mute_stories: false, mute_stories: false })
        }
        SettingsRow {
            visible: !page.allStories
            text: Tr.t("Muhim hikoyalar"); toggle: true; last: true
            on: !!page.s && page.s.use_default_mute_stories
            onClicked: page.change(on ? { use_default_mute_stories: false, mute_stories: true } : { use_default_mute_stories: true })
        }
    }
    SettingsGroup {
        visible: page.kind === "stories" && !!page.s
        title: Tr.t("Parametrlar")
        SettingsRow {
            text: Tr.t("Yuboruvchi ismini ko'rsatish"); toggle: true; last: true
            on: !!page.s && page.s.show_story_poster
            onClicked: page.change({ show_story_poster: !page.s.show_story_poster })
        }
    }

    // ---- reactions ----
    SettingsGroup {
        visible: page.kind === "reactions" && !!page.reactions
        title: Tr.t("Menga xabar berish…")
        Repeater {
            model: [["message_reaction_source", Tr.t("Xabarlarimga reaksiyalar")], ["story_reaction_source", Tr.t("Hikoyalarimga reaksiyalar")]]
            Item {
                id: rrow
                required property var modelData
                required property int index
                readonly property string src: page.reactions ? page.reactions[modelData[0]]["@type"] : ""
                width: parent.width; height: 11 + rName.height + 1 + rFrom.height + 11
                Rectangle { anchors.fill: parent; color: Theme.highlight; visible: rHit.pressed }
                Text {
                    id: rName
                    x: 16; y: 11
                    width: parent.width - x - 84
                    elide: Text.ElideRight
                    text: rrow.modelData[1]
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17
                }
                Text {
                    id: rFrom
                    x: 16; y: rName.y + rName.height + 1
                    text: rrow.src === "reactionNotificationSourceContacts" ? Tr.t("Kontaktlarimdan")
                        : rrow.src === "reactionNotificationSourceAll" ? Tr.t("Hammadan") : Tr.t("O'chiq")
                    color: rrow.src === "reactionNotificationSourceNone" ? Theme.grey : Theme.accent
                    font.family: Theme.font; font.pixelSize: 15
                }
                MouseArea { id: rHit; anchors.fill: parent; onClicked: menu.show(rrow, rrow.modelData[0]) }
                Switch {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    on: rrow.src !== "reactionNotificationSourceNone"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.setReactions({ [rrow.modelData[0]]: page.source(!parent.on, false) })
                    }
                }
                Rectangle {
                    visible: rrow.index === 0
                    x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                }
            }
        }
    }
    SettingsGroup {
        visible: page.kind === "reactions" && !!page.reactions
        title: Tr.t("Parametrlar")
        SettingsRow {
            text: Tr.t("Yuboruvchi ismini ko'rsatish"); toggle: true; last: true
            on: !!page.reactions && page.reactions.show_preview
            onClicked: page.setReactions({ show_preview: !page.reactions.show_preview })
        }
    }

    // ---- rows ----
    component AddRow: Item {        // ItemListPeerActionItem: the accent's plus, the words in the accent
        id: arow
        property string text: ""
        signal tapped()
        width: parent ? parent.width : 300; height: 52
        Rectangle { anchors.fill: parent; color: Theme.highlight; visible: aHit.pressed }
        Text {
            x: 28; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -2
            text: "+"
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Light
        }
        Text {
            x: 65; anchors.verticalCenter: parent.verticalCenter
            text: arow.text
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 17
        }
        MouseArea { id: aHit; anchors.fill: parent; onClicked: arow.tapped() }
        Rectangle { x: 65; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }
    component Swiped: Item {        // a row swiped left shows «O'chirish» (ItemListRevealOption)
        id: srow
        property string key: ""
        default property alias body: inner.data
        readonly property real slide: page.revealed === key ? -delBtn.width : 0
        width: parent ? parent.width : 300; height: 58
        clip: true
        Item {
            id: inner
            x: srow.slide
            width: parent.width; height: parent.height
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
        }
        MouseArea {
            anchors.fill: parent
            property real x0: 0
            property real y0: 0
            property bool swiped: false
            onPressed: (m) => { x0 = m.x; y0 = m.y; preventStealing = false; swiped = false }
            onPositionChanged: (m) => {
                const dx = m.x - x0
                if (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(m.y - y0))
                    preventStealing = swiped = true
                if (dx < -30)
                    page.revealed = srow.key
                else if (dx > 30 && page.revealed === srow.key)
                    page.revealed = ""
            }
            onClicked: if (!swiped && page.revealed !== "") page.revealed = ""     // (a release after a swipe is a click too)
        }
        Rectangle {
            id: delBtn
            x: parent.width + srow.slide
            width: delText.implicitWidth + 32; height: parent.height
            color: Theme.danger
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Text {
                id: delText
                anchors.centerIn: parent
                text: Tr.t("O'chirish")
                color: "white"
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { anchors.fill: parent; onClicked: page.drop(Number(srow.key)) }
        }
        Rectangle { x: 65; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }

    // ---- over the page: whose reactions (iOS's sheet: Hammadan / Kontaktlarimdan), the asking ----
    Item {
        id: menu
        parent: page
        anchors.fill: parent
        z: 35
        property bool open: false
        property real at: 0
        property string field: ""
        function show(row, f) {
            at = row.mapToItem(page, 0, row.height).y + 6
            field = f
            open = true
        }
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: menu.open = false }
        Rectangle {
            x: 16
            y: Math.min(menu.at, page.height - height - 16)
            width: 240; height: 2 * 44
            radius: 14
            color: Theme.menu
            border.color: Theme.separator; border.width: 0.5
            scale: menu.open ? 1 : 0.8
            transformOrigin: Item.TopLeft
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            Repeater {
                model: [["reactionNotificationSourceAll", Tr.t("Hammadan")], ["reactionNotificationSourceContacts", Tr.t("Kontaktlarimdan")]]
                Rectangle {
                    required property var modelData
                    required property int index
                    y: index * 44
                    width: parent.width; height: 44
                    radius: 14
                    color: mHit.pressed ? Theme.highlight : "transparent"
                    Rectangle { visible: parent.index > 0; width: parent.width; height: 0.5; color: Theme.separator }
                    Text {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData[1]
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Text {
                        visible: !!page.reactions && menu.field !== "" && page.reactions[menu.field]["@type"] === parent.modelData[0]
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: mHit
                        anchors.fill: parent
                        onClicked: {
                            menu.open = false
                            page.setReactions({ [menu.field]: { "@type": parent.modelData[0] } })
                        }
                    }
                }
            }
        }
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
