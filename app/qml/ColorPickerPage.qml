// «Rang tanlash» (iOS's «Set Custom Color»), as Telegram-iOS's ThemeAccentColorController colour picker: a live
// preview of the base with the colour, a hue/saturation wheel (hue is the angle, saturation the radius), a brightness
// slider under it, and the colour's hex. The colour is the base's accent (Store.chooseAccent(base, "#rrggbb")) only on
// «Tayyor»; ‹ leaves the base as it was.
import QtQuick
import "Looks.js" as Looks

SubPage {
    id: page
    property var store
    property string base: "classic"
    title: Tr.t("Rang tanlash")
    action: Tr.t("Tayyor")
    actionBold: true
    onActed: { page.store.chooseAccent(page.base, "#" + page.hex); nav.pop() }

    // the colour as hue, saturation, brightness (0..1); its number and hex
    property real hue: 0
    property real sat: 0
    property real bri: 1
    readonly property int num: Looks.ofHsb(hue, sat, bri)
    readonly property string hex: ("000000" + (num >>> 0).toString(16)).slice(-6)
    readonly property var look: { num; page.base; return page.store ? Looks.look(page.base, "#" + hex) : ({}) }
    readonly property color shown: look.accent ? look.accent : Looks.css(num)

    function seed(c) {
        const x = Looks.hsb(c)
        hue = x[0]; sat = x[1]; bri = x[2]
    }
    Component.onCompleted: {
        const l = Looks.look(base, store.accentOf(base))
        seed(l.accent ? parseInt(l.accent.slice(1), 16) : 0x0088ff)
        reviewWall()
    }

    // the preview's background: the look's wallpaper (a fill at once, its pattern when found)
    property string previewSpec: "ffffff;0;;"
    function reviewWall() {
        if (!store)
            return
        const want = page.num
        store.wallOfLook(page.look, (s) => { if (s && want === page.num) page.previewSpec = s })
    }
    Timer { id: wallTimer; interval: 100; onTriggered: page.reviewWall() }
    onLookChanged: wallTimer.restart()

    // ---- the preview: the chat in small over the look's background, our bubble in the colour ----
    Item {
        width: parent.width; height: 168
        clip: true
        Wallpaper { anchors.fill: parent; spec: page.previewSpec }
        Column {
            x: 14; width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {         // incoming: a reply (the accent), their bubble
                width: Math.min(parent.width * 0.74, 230); height: quote.height + inWords.height + 18
                radius: 14
                color: page.look.bubbleIn ? page.look.bubbleIn : page.look.tint ? page.look.tint.bubbleIn
                     : Looks.BASES.find((x) => x.id === page.base).dark ? "#1d1d1d" : "#ffffff"
                Rectangle {
                    id: quote
                    x: 8; y: 8; width: parent.width - 16; height: qName.height + qText.height + 8
                    radius: 6
                    color: Qt.rgba(page.shown.r, page.shown.g, page.shown.b, 0.1)
                    Rectangle { width: 3; height: parent.height; radius: 1.5; color: page.shown }
                    Text {
                        id: qName
                        x: 9; y: 4; text: "Bob Harris"; color: page.shown
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        id: qText
                        x: 9; y: qName.y + qName.height; text: Tr.t("Xayrli tong! 👋")
                        color: Looks.BASES.find((x) => x.id === page.base).dark ? "#ffffff" : "#000000"
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                Text {
                    id: inWords
                    x: 12; y: quote.y + quote.height + 3
                    text: Tr.t("Soat necha bo'lganini bilasizmi?")
                    color: Looks.BASES.find((x) => x.id === page.base).dark ? "#ffffff" : "#000000"
                    font.family: Theme.font; font.pixelSize: 15
                }
            }
            Item {              // outgoing: our bubble in the colour
                width: parent.width; height: outBubble.height
                Rectangle {
                    id: outBubble
                    anchors.right: parent.right
                    width: outWords.width + 20; height: outWords.height + 14
                    radius: 14
                    readonly property color out: page.look.out ? page.look.out
                                               : Looks.BASES.find((x) => x.id === page.base).dark ? "#3e88f7" : "#e1ffc7"
                    color: out
                    Text {
                        id: outWords
                        x: 10; y: 7
                        text: Tr.t("Tokioda hozir tong 😎")
                        color: page.look.outLight ? "#000000" : "#ffffff"
                        font.family: Theme.font; font.pixelSize: 15
                    }
                }
            }
        }
    }

    // ---- the wheel and the brightness slider ----
    Rectangle {
        x: 16; width: parent.width - 32; height: wheelBox.height + 28
        radius: 12
        color: Theme.card
        Column {
            id: wheelBox
            x: 20; y: 14; width: parent.width - 40
            spacing: 18
            Item {
                width: parent.width; height: wheel.height
                readonly property real r: wheel.width / 2
                Canvas {
                    id: wheel
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 236); height: width
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
                            ctx.fillStyle = Looks.css(Looks.ofHsb(i / 360, 1, 1))
                            ctx.fill()
                        }
                        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, R)
                        g.addColorStop(0, "#ffffff")
                        g.addColorStop(1, "rgba(255,255,255,0)")
                        ctx.fillStyle = g
                        ctx.beginPath(); ctx.arc(cx, cy, R, 0, 2 * Math.PI); ctx.closePath(); ctx.fill()
                    }
                }
                Rectangle {         // the brightness: the wheel darkened
                    anchors.fill: wheel
                    radius: width / 2
                    color: "#000000"
                    opacity: 1 - page.bri
                }
                Item {              // the knob at hue (angle) and saturation (radius)
                    readonly property real rad: wheel.width / 2
                    x: wheel.x + rad + Math.cos(page.hue * 2 * Math.PI) * page.sat * rad
                    y: wheel.y + rad + Math.sin(page.hue * 2 * Math.PI) * page.sat * rad
                    Rectangle {
                        x: -13; y: -13; width: 26; height: 26; radius: 13
                        color: page.shown
                        border.width: 3; border.color: "#ffffff"
                    }
                }
                MouseArea {
                    anchors.fill: wheel
                    function pick(mx, my) {
                        const R = wheel.width / 2
                        const dx = mx - R, dy = my - R
                        page.hue = (Math.atan2(dy, dx) / (2 * Math.PI) + 1) % 1
                        page.sat = Math.min(1, Math.sqrt(dx * dx + dy * dy) / R)
                    }
                    onPressed: (m) => pick(m.x, m.y)
                    onPositionChanged: (m) => pick(m.x, m.y)
                }
            }
            Rectangle {             // the brightness slider: black to the colour at full brightness
                width: parent.width; height: 28; radius: 14
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#000000" }
                    GradientStop { position: 1; color: Looks.css(Looks.ofHsb(page.hue, page.sat, 1)) }
                }
                Rectangle {
                    x: page.bri * (parent.width - 28); width: 28; height: 28; radius: 14
                    color: page.shown
                    border.width: 3; border.color: "#ffffff"
                }
                MouseArea {
                    anchors.fill: parent
                    function pick(mx) { page.bri = Math.min(1, Math.max(0, (mx - 14) / (width - 28))) }
                    onPressed: (m) => pick(m.x)
                    onPositionChanged: (m) => pick(m.x)
                }
            }
        }
    }

    // ---- the hex ----
    Rectangle {
        x: 16; width: parent.width - 32; height: 48
        radius: 12
        color: Theme.card
        Rectangle { x: 14; y: 11; width: 26; height: 26; radius: 6; color: page.shown }
        Text {
            x: 52; anchors.verticalCenter: parent.verticalCenter
            text: "#"; color: Theme.grey
            font.family: Theme.font; font.pixelSize: 17
        }
        TextInput {
            id: hexField
            x: 66; width: parent.width - 80
            anchors.verticalCenter: parent.verticalCenter
            text: page.hex.toUpperCase()
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17
            maximumLength: 6
            inputMethodHints: Qt.ImhUppercaseOnly | Qt.ImhPreferUppercase | Qt.ImhNoPredictiveText
            // (while typing, read what makes six hex digits; the field keeps its own text till then)
            onTextEdited: {
                const clean = text.replace(/[^0-9a-fA-F]/g, "").toUpperCase()
                if (clean !== text)
                    text = clean
                if (clean.length === 6)
                    page.seed(parseInt(clean, 16))
            }
            Connections {
                target: page
                function onNumChanged() { if (!hexField.activeFocus) hexField.text = page.hex.toUpperCase() }
            }
        }
    }
    Item { width: 1; height: 20 }
}
