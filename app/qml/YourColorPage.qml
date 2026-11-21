// «Sizning rangingiz» (iOS's «Your Color»), as Telegram-iOS's UserAppearanceScreen: «Profil» and «Ism» on the bar
// (its segmented title). Profil: the profile's head in small (PeerNameColorProfilePreviewItem: the picture, the name
// and «onlayn» over the profile colour's background), the profile colours (PeerNameColorItem .profile: 8 a row, the
// palette's), «Profil rangini tiklash» when one is set. Ism: one message of ours in small over the chats' background
// (PeerNameColorChatPreviewItem: the name, a reply to it, a link's preview — all in the colour), the names' colours
// (7 a row: the seven built in, then the server's striped ones). Nothing is set until «Uslubni qo'llash»: TDLib's
// setAccentColor / setProfileAccentColor. ‹ with changes asks first (iOS's «Unsaved Changes»). Icons (Premium's
// emoji on replies and the profile) and gifts' colours not yet.
import QtQuick

SubPage {
    id: page
    title: ""
    property int tab: 0                 // 0 Profil, 1 Ism
    readonly property var me: store ? store.me : null
    property int nameId: me ? me.accent_color_id || 0 : 0
    property int profileId: me && me.profile_accent_color_id !== undefined ? me.profile_accent_color_id : -1
    readonly property int nameWas: me ? me.accent_color_id || 0 : 0
    readonly property int profileWas: me && me.profile_accent_color_id !== undefined ? me.profile_accent_color_id : -1
    readonly property bool changed: nameId !== nameWas || profileId !== profileWas
    readonly property string myName: me ? (me.first_name + " " + (me.last_name || "")).trim() : ""
    readonly property var nameInk: { Theme.dark; store.accentColors; return store.nameColors(nameId) }
    readonly property var prof: { Theme.dark; store.profileColors; return profileId >= 0 ? store.profileColorsOf(profileId) : null }
    readonly property string clock: Qt.formatTime(new Date(), "HH:mm")
    property string photo: ""
    Component.onCompleted: store.userPhoto(me, (p) => { page.photo = p })

    function apply() {
        store.setYourColor(nameId, profileId, () => {})
        nav.pop()
    }
    guard: () => {
        if (!changed)
            return false
        alert.show(Tr.t("Saqlanmagan o'zgarishlar"), Tr.t("Rang sozlamalarini o'zgartirdingiz. O'zgarishlar qo'llansinmi?"),
                   [{ t: Tr.t("Bekor qilish"), run: () => page.nav.pop() }, { t: Tr.t("Qo'llash"), bold: true, run: () => page.apply() }])
        return true
    }

    // ---- Profil ----
    SettingsGroup {
        visible: page.tab === 0
        note: Tr.t("Profilingiz uchun rang tanlang")
        Item {
            id: head
            width: parent.width; height: 196
            Canvas {        // the profile colour's background: its first colour round the picture, the second out
                anchors.fill: parent
                visible: !!page.prof && page.prof.background.length > 0
                readonly property var bg: page.prof ? page.prof.background : []
                onBgChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d")
                    g.reset()
                    if (!bg.length)
                        return
                    const r = g.createRadialGradient(width / 2, 78, 0, width / 2, 78, width * 0.75)
                    r.addColorStop(0, bg[0])
                    r.addColorStop(1, bg[bg.length > 1 ? 1 : 0])
                    g.fillStyle = r
                    g.fillRect(0, 0, width, height)
                }
            }
            Avatar {
                x: (parent.width - 96) / 2; y: 26
                width: 96; height: 96
                source: page.photo
                letters: page.me ? store.letters(page.myName) : ""
                tint: page.me ? store.tints[Math.abs(page.me.id) % store.tints.length] : Theme.accent
            }
            Text {
                y: 134; width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: page.myName
                color: page.prof ? "white" : Theme.text
                font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold
            }
            Text {
                y: 164; width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Tr.t("onlayn")
                color: page.prof ? Qt.rgba(1, 1, 1, 0.75) : Theme.accent
                font.family: Theme.font; font.pixelSize: 15
            }
        }
        Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
        ColorGrid {
            perRow: 8
            ids: store.profileIds.length ? store.profileIds : store.profileColors.map((c) => c.id)
            chosen: page.profileId
            colorsOf: (id) => { Theme.dark; return store.profileColorsOf(id).palette }
            onPicked: (id) => page.profileId = id
        }
    }
    SettingsGroup {
        visible: page.tab === 0 && page.profileId >= 0
        SettingsRow { text: Tr.t("Profil rangini tiklash"); accent: true; chevron: false; last: true; onClicked: page.profileId = -1 }
    }

    // ---- Ism ----
    SettingsGroup {
        visible: page.tab === 1
        note: Tr.t("Ismingiz, yuborgan havolalaringiz va xabarlaringizga javoblar uchun rang tanlashingiz mumkin.")
        Item {
            width: parent.width; height: sample.height + 16
            clip: true
            Wallpaper { anchors.fill: parent }
            ChatSample {
                id: sample
                y: 8
                messages: [{ name: page.myName, colors: page.nameInk, time: page.clock,
                             reply: { name: page.myName, text: Tr.t("Xabaringizga javob") },
                             text: Tr.t("Ismingiz va xabarlaringizga javoblar tanlangan rangda ko'rinadi."),
                             link: { site: "Telegram", title: Tr.t("Havola ko'rinishi"),
                                     text: Tr.t("Tanlangan rang havola ko'rinishini ham bo'yaydi.") } }]
            }
            Rectangle {     // the card's top corners over it (a clip is square)
                x: -12; y: -12; width: parent.width + 24; height: parent.height + 24
                radius: 24
                color: "transparent"
                border.width: 12; border.color: Theme.grouped
            }
        }
        ColorGrid {
            perRow: 7
            ids: store.accentIds
            chosen: page.nameId
            colorsOf: (id) => { Theme.dark; store.accentColors; return store.nameColors(id) }
            onPicked: (id) => page.nameId = id
        }
    }
    Item { width: 1; height: 70 }       // (room for the button)

    // the bar's title: «Profil» | «Ism» (iOS's segmented control)
    Rectangle {
        parent: page
        z: 5
        x: (page.width - width) / 2; y: 12
        width: 210; height: 32; radius: 16
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)
        Rectangle {
            x: 2 + page.tab * (parent.width - 4) / 2; y: 2
            width: (parent.width - 4) / 2; height: parent.height - 4; radius: height / 2
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : "white"
            Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }
        Row {
            Repeater {
                model: [Tr.t("Profil"), Tr.en ? "Name" : "Ism"]     // ("Ism" alone is the First name field's)
                Text {
                    required property string modelData
                    required property int index
                    width: 105; height: 32
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    MouseArea { anchors.fill: parent; onClicked: page.tab = parent.index }
                }
            }
        }
    }

    // «Uslubni qo'llash» at the foot (iOS: a wide button over the list, grey till something changed)
    Rectangle {
        parent: page
        z: 5
        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 16
        anchors.bottom: parent.bottom; anchors.bottomMargin: 12 + safe.bottom
        height: 50; radius: 12
        color: page.changed ? Theme.accent : Theme.grey
        opacity: applyHit.pressed ? 0.7 : 1
        Text {
            anchors.centerIn: parent
            text: Tr.t("Uslubni qo'llash")
            color: "white"
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
        MouseArea { id: applyHit; anchors.fill: parent; enabled: page.changed; onClicked: page.apply() }
    }

    Alert { id: alert; parent: page; anchors.fill: parent }

    // the colours' grid (PeerNameColorItem): 32 round, as many a row as `perRow`, spread over the card's width;
    // one to three colours a circle (two: the first the top-left half — the night's swapped; three: the first the
    // bottom-right half, the third a turned square in the middle); the chosen one ringed
    component ColorGrid: Item {
        id: grid
        property int perRow: 7
        property var ids: []
        property int chosen: -1
        property var colorsOf: (id) => []
        signal picked(int id)
        width: parent ? parent.width : 300
        height: 20 + 42 * Math.ceil(ids.length / perRow)
        readonly property real gap: (width - 20 - 32 * perRow) / (perRow - 1)
        Repeater {
            model: grid.ids
            Item {
                id: cell
                required property int modelData
                required property int index
                readonly property var cs: grid.colorsOf(modelData)
                readonly property bool on: grid.chosen === modelData
                x: 10 + (index % grid.perRow) * (32 + grid.gap); y: 10 + Math.floor(index / grid.perRow) * 42
                width: 32; height: 32
                Rectangle {
                    anchors.fill: parent; radius: 16
                    color: "transparent"
                    border.width: 2; border.color: cell.cs[0] || Theme.grey
                    opacity: cell.on ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                Canvas {
                    anchors.fill: parent
                    scale: cell.on ? 0.72 : 1
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                    readonly property var cs: cell.cs
                    onCsChanged: requestPaint()
                    onPaint: {
                        const g = getContext("2d"), w = width, h = height
                        g.reset()
                        g.beginPath(); g.arc(w / 2, h / 2, w / 2, 0, Math.PI * 2); g.clip()
                        let c = cs.length ? cs.slice() : ["#798896"]
                        if (c.length === 2 && Theme.dark)
                            c = [c[1], c[0]]
                        g.fillStyle = c[c.length > 1 ? 1 : 0]
                        g.fillRect(0, 0, w, h)
                        if (c.length === 2) {
                            g.beginPath(); g.moveTo(0, 0); g.lineTo(w, 0); g.lineTo(0, h); g.closePath()
                            g.fillStyle = c[0]; g.fill()
                        } else if (c.length > 2) {
                            g.beginPath(); g.moveTo(w, 0); g.lineTo(w, h); g.lineTo(0, h); g.closePath()
                            g.fillStyle = c[0]; g.fill()
                            const s = w * 18 / 40, r = Math.round(w * 4 / 40)
                            g.translate(w / 2, h / 2); g.rotate(Math.PI / 4)
                            g.beginPath(); g.roundedRect(-s / 2, -s / 2, s, s, r, r)
                            g.fillStyle = c[2]; g.fill()
                        }
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: grid.picked(cell.modelData) }
            }
        }
    }
}
