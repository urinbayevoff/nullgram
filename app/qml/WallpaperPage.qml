// «Chat fon rasmi», as Telegram-iOS's ThemeGridController: «Rang o'rnatish» (WallpaperColorsPage) and «Galereyadan
// tanlash» (the phone's pictures: WallpaperPhotosPage), then the backgrounds in three columns (tiles 150 high, corners
// 16, 6 between): Telegram's own first, then the installed ones (getInstalledBackgrounds; not the bare patterns), the one in use ticked.
// One tapped opens before it is set (WallpaperPreview). «Tahrirlash»: the installed ones ticked, «O'chirish» takes them
// away (removeInstalledBackground). At the foot «Chat fon rasmlarini asliga qaytarish» (resetInstalledBackgrounds; asked).
// For one chat (`chatId`: its profile's «Fon rasmini o'zgartirish», iOS's Change Wallpaper): the same grid, its own one
// ticked, set with setChatBackground (WallpaperPreview), no editing; it has one: «Fon rasmini olib tashlash» at the foot.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Chat fon rasmi")
    property var chatId: 0
    property Item home: null            // a chat's: the page to go back to once set (its profile)
    readonly property var chat: chatId ? (store.seen, store.chats[chatId]) : null
    property int changed: 0
    readonly property var own: (changed, chat && chat.background ? chat.background.background : null)
    Connections {
        target: store
        function onChatChanged(id) { if (id === page.chatId) page.changed++ }
    }
    action: chatId ? "" : !items.some((it) => it.background && !it.builtin) ? "" : editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")
    actionBold: editing
    onActed: { editing = !editing; picked = [] }

    property bool editing: false
    property var picked: []             // while editing: the ids ticked
    property var installed: []
    property var builtin: null          // Telegram's own pattern (Store.builtin)
    // the grid's: Telegram's own, then the installed (not its pattern again with its own colours)
    readonly property var items: {
        const own = builtin ? [{ background: builtin, type: store.builtinType(Theme.dark), builtin: true }] : []
        return own.concat(installed.filter((b) => !(builtin && b.id === builtin.id) && !bare(b)).map((b) => ({ background: b, type: b.type, builtin: false })))
    }
    // a pattern with no colours of its own (the server lists them for the colour picker): not a background, iOS skips them
    function bare(b) {
        const t = b.type
        return t["@type"] === "backgroundTypePattern" && t.fill["@type"] === "backgroundFillSolid" && !t.fill.color && !t.intensity
    }
    readonly property var now: { Prefs.theme; Prefs.themeWall; store.backgrounds; store.emojiThemes; return store.wallNow(Theme.dark) }
    function inUse(it) {
        if (chatId)
            return !!own && !it.builtin && it.background.id === own.id
        if (now.builtin || !now.background)
            return it.builtin && now.builtin
        return !it.builtin && it.background.id === now.background.id
    }
    function load() {
        const dark = Theme.dark
        store.send({ "@type": "getInstalledBackgrounds", for_dark_theme: dark }, (r) => {
            if (r["@type"] === "backgrounds" && dark === Theme.dark)
                installed = r.backgrounds
        })
    }
    Component.onCompleted: {
        store.builtin((p) => builtin = p)
        load()
    }
    Connections { target: Theme; function onDarkChanged() { page.load() } }
    Connections { target: page.store; function onBackgroundsChanged() { page.load() } }

    property var makers: ({})
    function open(file, props) {
        let m = makers[file]
        if (!m) {
            m = Qt.createComponent(file)
            makers[file] = m
        }
        if (m.status === Component.Error)
            console.warn("nullgram:", m.errorString())
        props = props || {}
        if (chatId) {
            props.chatId = chatId
            props.home = home
        }
        nav.push(m, props)
    }
    function preview(it) {
        store.wallOf(it.background, it.type, (s) => {})     // (its file asked for now: the preview has it sooner)
        open("WallpaperPreview.qml", { background: it.background, type: it.type })
    }
    function toggle(id) {
        const p = picked.slice()
        const at = p.indexOf(id)
        if (at < 0)
            p.push(id)
        else
            p.splice(at, 1)
        picked = p
    }
    function removePicked() {
        for (const id of picked)
            store.send({ "@type": "removeInstalledBackground", background_id: id })
        installed = installed.filter((b) => picked.indexOf(b.id) < 0)
        picked = []
        editing = false
    }
    function askReset() {
        alert.show(Tr.t("Chat fon rasmlarini asliga qaytarish"), Tr.t("Barcha fon rasmlari asl holiga qaytarilsinmi?"),
                   [{ t: Tr.t("Bekor qilish"), run: () => {} },
                    { t: Tr.t("Qaytarish"), red: true, run: () => store.send({ "@type": "resetInstalledBackgrounds" }, () => {
                        for (const dark of [false, true])
                            store.send({ "@type": "deleteDefaultBackground", for_dark_theme: dark }, () => store.setBackground(dark, null))
                        page.load()
                    }) }])
    }

    SettingsGroup {
        note: Tr.t("Maxsus fon o'rnatishingiz va uni tanishlaringizga ulashishingiz mumkin.")
        SettingsRow { text: Tr.t("Rang o'rnatish"); accent: true; chevron: false; onClicked: page.open("WallpaperColorsPage.qml") }
        SettingsRow { text: Tr.t("Galereyadan tanlash"); accent: true; chevron: false; last: true; onClicked: page.open("WallpaperPhotosPage.qml") }
    }
    Rectangle {             // the grid's card
        x: 16; width: parent.width - 32
        height: grid.height + 24
        radius: 12
        color: Theme.card
        Grid {
            id: grid
            x: 12; y: 12
            columns: 3
            spacing: 6
            readonly property real cell: Math.floor((parent.width - 24 - 12) / 3)
            Repeater {
                model: page.items
                Item {
                    id: tile
                    required property var modelData
                    width: grid.cell; height: 150
                    property string spec: ""
                    Component.onCompleted: page.store.wallOf(modelData.background, modelData.type, (s) => { if (s) tile.spec = s })
                    Wallpaper { anchors.fill: parent; radius: 16; spec: tile.spec || "efeff4;0;;" }
                    Rectangle {         // in use: iOS's tick on a dark disc
                        visible: !page.editing && page.inUse(tile.modelData)
                        anchors.centerIn: parent
                        width: 32; height: 32; radius: 16
                        color: Qt.rgba(0, 0, 0, 0.3)
                        Icon { anchors.centerIn: parent; width: 20; height: 20; name: "check"; color: "white" }
                    }
                    Check {
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 6
                        on: page.editing && !tile.modelData.builtin
                        checked: page.picked.indexOf(tile.modelData.background.id) >= 0
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.editing ? (tile.modelData.builtin ? 0 : page.toggle(tile.modelData.background.id)) : page.preview(tile.modelData)
                    }
                }
            }
        }
    }
    SettingsGroup {
        visible: page.editing
        SettingsRow { text: Tr.t("O'chirish"); danger: true; chevron: false; last: true; dim: !page.picked.length
                      onClicked: if (page.picked.length) page.removePicked() }
    }
    SettingsGroup {         // a chat's own one: away with it (deleteChatBackground), the app's again
        visible: !!page.chatId && !!page.own
        SettingsRow { text: Tr.t("Fon rasmini olib tashlash"); danger: true; chevron: false; last: true; onClicked: page.removeOwn() }
    }
    function removeOwn() {
        store.send({ "@type": "deleteChatBackground", chat_id: chatId, restore_previous: false }, (r) => {
            if (r["@type"] === "error")
                nav.say(Tr.f("Bo'lmadi: %1", r.message))
            else
                nav.say(Tr.t("Fon rasmi olib tashlandi"))
        })
    }
    SettingsGroup {
        visible: !page.editing && !page.chatId
        note: Tr.t("Barcha o'rnatilgan fon rasmlarini olib tashlaydi va standart to'plamni tiklaydi.")
        SettingsRow { text: Tr.t("Chat fon rasmlarini asliga qaytarish"); accent: true; chevron: false; last: true; onClicked: page.askReset() }
    }
    Item { width: 1; height: 20 }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
