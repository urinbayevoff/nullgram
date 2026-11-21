// Settings' QR (Telegram-iOS's QR code screen, the owner's #26428 top left): over a dimmed window a card with our avatar
// on its edge, our t.me link drawn as a QR code (td.qrHigh, level H, round dots, Telegram's plane in the middle), «@NAME» under it;
// «Havolani nusxalash» and ✕. No username → the card says so and offers UsernamePage (wantName). Someone else's
// (ChatInfoPage, the QR on their username, as iOS's): their avatar (`letters`, `tint`) and link.
import QtQuick

Item {
    id: sheet
    property var store
    property string photo: ""
    property string username: ""
    property string letters: store && store.me ? store.letters(store.me.first_name + " " + store.me.last_name) : ""
    property color tint: store && store.me ? store.tints[Math.abs(store.me.id) % store.tints.length] : Theme.accent
    property bool open: false
    signal wantName()
    signal copied()
    readonly property string link: username ? "https://t.me/" + username : ""
    readonly property var rows: open && link ? td.qrHigh(link) : []
    anchors.fill: parent
    visible: fade.opacity > 0

    function show() { open = true }
    function hide() { open = false }

    Rectangle {
        id: fade
        anchors.fill: parent
        opacity: sheet.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.dark ? "#1d2b3a" : "#8fc1f0" }
            GradientStop { position: 1; color: Theme.dark ? "#0e1620" : "#3e88d6" }
        }
        MouseArea { anchors.fill: parent; onClicked: sheet.hide() }

        Glass {             // ✕
            x: 16; y: 10
            width: 44; height: 44
            opacity: closeHit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; name: "cross"; color: Theme.text }
            MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.hide() }
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(110, (parent.height - height - 120 - safe.bottom) / 2 + 20)
            scale: sheet.open ? 1 : 0.9
            Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
            width: Math.min(parent.width - 64, 320)
            height: sheet.link ? width + 70 : 230
            radius: 32
            color: "white"
            MouseArea { anchors.fill: parent }
            Rectangle {     // the avatar on the card's edge, a white ring round it
                anchors.horizontalCenter: parent.horizontalCenter
                y: -46
                width: 92; height: 92; radius: 46
                color: "white"
                Avatar {
                    anchors.centerIn: parent
                    width: 84; height: 84
                    source: sheet.photo
                    letters: sheet.letters
                    tint: sheet.tint
                }
            }
            Canvas {
                id: code
                visible: !!sheet.link
                anchors.horizontalCenter: parent.horizontalCenter
                y: 62
                width: parent.width - 64; height: width
                readonly property var rows: sheet.rows
                onRowsChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    const n = rows.length
                    if (!n)
                        return
                    const c = width / n
                    const hole = Math.ceil(n * 0.22) | 1          // the middle left clear for the plane (level H: 30% may go)
                    const h0 = (n - hole) / 2, h1 = h0 + hole
                    const ink = "#1f4f80"
                    g.fillStyle = ink
                    const finder = (x, y) => x < 7 && y < 7 || x >= n - 7 && y < 7 || x < 7 && y >= n - 7
                    for (let y = 0; y < n; y++)
                        for (let x = 0; x < n; x++) {
                            if (rows[y].charAt(x) !== "1" || finder(x, y) || (x >= h0 && x < h1 && y >= h0 && y < h1))
                                continue
                            g.beginPath()
                            g.arc((x + 0.5) * c, (y + 0.5) * c, c * 0.46, 0, 2 * Math.PI)
                            g.fill()
                        }
                    // the three corner squares, rounded
                    const corner = (x, y) => {
                        g.lineWidth = c
                        g.strokeStyle = ink
                        rr(g, x * c + c / 2, y * c + c / 2, 6 * c, 6 * c, 2 * c)
                        g.stroke()
                        rr(g, (x + 2) * c, (y + 2) * c, 3 * c, 3 * c, c)
                        g.fill()
                    }
                    corner(0, 0); corner(n - 7, 0); corner(0, n - 7)
                }
                function rr(g, x, y, w, h, r) {
                    g.beginPath()
                    g.moveTo(x + r, y)
                    g.arcTo(x + w, y, x + w, y + h, r)
                    g.arcTo(x + w, y + h, x, y + h, r)
                    g.arcTo(x, y + h, x, y, r)
                    g.arcTo(x, y, x + w, y, r)
                    g.closePath()
                }
                Rectangle {     // Telegram's plane in the middle
                    anchors.centerIn: parent
                    width: parent.width * 0.2; height: width; radius: width / 2
                    color: "#2a9ef1"
                    Icon {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -parent.width * 0.04
                        width: parent.width * 0.6; height: width
                        name: "forward"
                        color: "white"
                        rotation: -20
                    }
                }
            }
            Text {
                visible: !!sheet.link
                anchors.horizontalCenter: parent.horizontalCenter
                y: code.y + code.height + 14
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: "@" + sheet.username.toUpperCase()
                color: "#1f4f80"
                font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold
            }
            Column {         // no username: no link to draw
                visible: !sheet.link
                y: 62
                width: parent.width
                spacing: 14
                Text {
                    x: 24; width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Tr.t("QR kod sizning foydalanuvchi nomingizdan yasaladi. Avval nom tanlang — shunda odamlar kodni skanerlab sizga yoza oladi.")
                    color: "#3c3c43"
                    font.family: Theme.font; font.pixelSize: 15
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: nameWord.implicitWidth + 36; height: 44; radius: 22
                    color: Theme.accent
                    opacity: nameHit.pressed ? 0.7 : 1
                    Text { id: nameWord; anchors.centerIn: parent; text: Tr.t("Foydalanuvchi nomini tanlash"); color: "white"; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                    MouseArea { id: nameHit; anchors.fill: parent; onClicked: { sheet.hide(); sheet.wantName() } }
                }
            }
        }

        Rectangle {          // «Havolani nusxalash»
            visible: !!sheet.link
            x: 16; width: parent.width - 32; height: 52; radius: 26
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + safe.bottom
            color: "white"
            opacity: copyHit.pressed ? 0.7 : 1
            Text {
                anchors.centerIn: parent
                text: Tr.t("Havolani nusxalash")
                color: "#1f4f80"
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            MouseArea {
                id: copyHit
                anchors.fill: parent
                onClicked: {
                    clip.text = sheet.link
                    clip.selectAll()
                    clip.copy()
                    sheet.hide()
                    sheet.copied()
                }
            }
        }
    }
    TextEdit { id: clip; visible: false }
}
