// «Chat mavzulari», as Telegram-iOS's ThemePickerController: Telegram's chat themes, all of them in three columns
// (ThemePickerGridItem; one tapped is the app's, as on Ko'rinish), then «O'z mavzungizni yaratish»: the chat in
// small, the four bases in a row (ThemeSettingsThemeItem: Klassik, Qorong'i — the tinted night, Kun, Tun; a dark one
// is the night's, and night falls with it) and the chosen base's accents (ThemeSettingsAccentColorItem: its presets —
// an accent, our bubbles and a background — and the plain colours, then «Rang tanlash»: iOS's own colour picker,
// ColorPickerPage). The moon on the bar: night and day. «Edit Current Theme» and «Create a New Theme» (the editor) wait.
import QtQuick
import "Looks.js" as Looks

SubPage {
    id: page
    title: Tr.t("Chat mavzulari")
    actionIcon: "moon"
    onActed: Theme.dark = !Theme.dark

    readonly property string base: { Prefs.dayBase; Prefs.nightBase; return store.baseNow(Theme.dark) }
    readonly property string accentKey: { Prefs.accents; return store.accentOf(base) }
    readonly property bool mine: Prefs.theme === ""             // (no chat theme over the base)

    SettingsGroup {
        title: Tr.t("Mavzu tanlash")
        Item {
            width: parent.width; height: grid.height + 20
            Grid {
                id: grid
                x: 8; y: 10
                columns: 3
                readonly property real cell: Math.floor((parent.width - 16) / 3)
                Repeater {
                    model: [{ name: "" }].concat(page.store ? page.store.emojiThemes : [])
                    Item {
                        id: slot
                        required property var modelData
                        width: grid.cell; height: Math.round(120 * grid.cell / 90)
                        ThemeTile {
                            scale: grid.cell / 90
                            transformOrigin: Item.TopLeft
                            store: page.store
                            emoji: slot.modelData.name || "🏠"
                            set: slot.modelData.name ? (Theme.dark ? slot.modelData.dark_settings : slot.modelData.light_settings) || null : null
                            chosen: Prefs.theme === slot.modelData.name
                            onClicked: page.store.chooseTheme(slot.modelData.name)
                        }
                    }
                }
            }
        }
    }

    SettingsGroup {
        title: Tr.t("O'z mavzungizni yaratish")
        SamplePane {}
        ListView {          // the bases
            id: bases
            width: parent.width; height: 116
            function show() { positionViewAtIndex(Looks.BASES.findIndex((b) => b.id === page.base), ListView.Contain) }
            Component.onCompleted: show()
            Connections { target: page; function onBaseChanged() { bases.show() } }
            orientation: ListView.Horizontal
            leftMargin: 6; rightMargin: 6
            clip: true
            model: Looks.BASES
            delegate: Item {
                id: baseSlot
                required property var modelData
                readonly property bool chosen: page.mine && page.base === modelData.id
                readonly property var look: { Prefs.accents; return Looks.look(modelData.id, page.store.accentOf(modelData.id)) }
                property string spec: ""
                function load() {
                    const l = look
                    page.store.wallOfLook(l, (s) => { if (s && l === baseSlot.look) baseSlot.spec = s })
                }
                onLookChanged: load()
                Component.onCompleted: load()
                width: 106; height: 116
                Rectangle {         // chosen: a ring of the accent
                    x: 3; y: 13; width: 100; height: 64; radius: 16
                    color: "transparent"
                    border.width: 2; border.color: Theme.accent
                    visible: baseSlot.chosen
                }
                Wallpaper { x: 7; y: 17; width: 92; height: 56; radius: 12; spec: baseSlot.spec || "ffffff;0;;" }
                Rectangle {
                    x: 7; y: 17; width: 92; height: 56; radius: 12
                    color: "transparent"
                    border.width: 0.5; border.color: Theme.separator
                }
                Rectangle {
                    x: 7 + 10; y: 17 + 8; width: 48; height: 17; radius: 8.5
                    color: baseSlot.look.bubbleIn || (baseSlot.look.tint ? baseSlot.look.tint.bubbleIn : baseSlot.modelData.dark ? "#1d1d1d" : "#ffffff")
                }
                Rectangle {
                    x: 7 + 92 - 10 - 52; y: 17 + 31; width: 52; height: 17; radius: 8.5
                    color: baseSlot.look.out || (baseSlot.modelData.dark ? "#3e88f7" : "#e1ffc7")
                }
                Text {
                    y: 86; width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t(baseSlot.modelData.name)
                    color: baseSlot.chosen ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: 12; font.weight: baseSlot.chosen ? Font.Bold : Font.Normal
                }
                MouseArea { anchors.fill: parent; onClicked: page.store.chooseBase(baseSlot.modelData.id) }
            }
        }
        Rectangle { x: 16; width: parent.width - 16; height: 0.5; color: Theme.separator }
        ListView {          // the base's accents
            id: accents
            width: parent.width; height: 58
            function show() { positionViewAtIndex(Math.max(0, model.findIndex((o) => o.key === page.accentKey)), ListView.Contain) }
            Component.onCompleted: show()
            onModelChanged: show()
            Connections { target: page; function onAccentKeyChanged() { accents.show() } }
            orientation: ListView.Horizontal
            leftMargin: 4; rightMargin: 4
            clip: true
            // the base's accents, then «Rang tanlash» (iOS's custom-colour wheel at the end of the row)
            model: Looks.options(page.base).concat([{ key: "__custom__", custom: true }])
            delegate: Item {
                id: dot
                required property var modelData
                readonly property bool custom: !!modelData.custom
                readonly property bool chosen: custom ? (page.mine && Looks.isCustom(page.accentKey))
                                                       : page.mine && page.accentKey === modelData.key
                readonly property color fill: custom ? Looks.css(Looks.customNum(page.accentKey)) : Looks.css(modelData.accent)
                // (a colour lost on the card: its edge grey)
                readonly property bool faint: Math.abs(fill.r - Theme.card.r) + Math.abs(fill.g - Theme.card.g) + Math.abs(fill.b - Theme.card.b) < 0.3
                width: 54; height: 58
                Rectangle {         // chosen: the ring
                    x: 7; y: 9; width: 40; height: 40; radius: 20
                    color: "transparent"
                    border.width: 2; border.color: dot.custom && !dot.chosen ? Theme.separator : dot.faint ? "#999999" : dot.fill
                    visible: dot.chosen || dot.custom
                }
                Rectangle {         // a named colour / preset, or the custom colour once chosen
                    visible: !dot.custom || dot.chosen
                    x: 11; y: 13; width: 32; height: 32; radius: 16
                    color: dot.fill
                    border.width: dot.faint ? 1 : 0; border.color: "#999999"
                }
                Rectangle {         // our bubbles' colours in its middle
                    id: mid
                    readonly property var bubbles: dot.modelData.bubbles || []
                    visible: !dot.custom && bubbles.length > 0
                    x: 17; y: 19; width: 20; height: 20; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: mid.bubbles.length ? Looks.css(mid.bubbles[0]) : "white" }
                        GradientStop { position: 1; color: mid.bubbles.length ? Looks.css(mid.bubbles[mid.bubbles.length - 1]) : "white" }
                    }
                }
                Canvas {            // the custom swatch (not chosen): a hue wheel to pick one
                    visible: dot.custom && !dot.chosen
                    x: 11; y: 13; width: 32; height: 32
                    renderStrategy: Canvas.Cooperative
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const cx = width / 2, cy = height / 2, R = width / 2
                        for (let i = 0; i < 360; i++) {
                            ctx.beginPath()
                            ctx.moveTo(cx, cy)
                            ctx.arc(cx, cy, R, (i - 1) * Math.PI / 180, (i + 1) * Math.PI / 180)
                            ctx.closePath()
                            ctx.fillStyle = Looks.css(Looks.ofHsb(i / 360, 0.85, 1))
                            ctx.fill()
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: dot.custom ? nav.push(Qt.createComponent("ColorPickerPage.qml"), { store: page.store, base: page.base })
                                          : page.store.chooseAccent(page.base, dot.modelData.key)
                }
            }
        }
    }
    Item { width: 1; height: 20 }
}
