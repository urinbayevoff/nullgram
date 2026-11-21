// 🎁 for a channel, as Telegram-iOS has it (its sources, and the owner's iPad: #26418–26421): GiftOptionsScreen —
// ✕ on the left, our Stars on the right, the channel's picture among gold sparkles, «Hadya yuborish», «X uchun hadya
// tanlang.», the «Barcha hadyalar» chip, the gifts three a row (sticker 88 pt, the price on a gold capsule with
// sparkles, «premium» on an orange ribbon); scrolled, its name goes up into the bar. A gift tapped: GiftSetupScreen,
// a second sheet over the first (the first steps back): the gift as the channel will see it over the wallpaper — the
// service line «Siz N yulduzga hadya yubordingiz» over a card with the sticker (played once, then still on its last
// frame, as an emoji alone in a chat), «Hadya», what the channel may do with it, «Ko'rish» — the words for it under
// the card, «Ismimni berkitish», and «Hadya yuborish. Narxi: ⭐ N» at the foot. That asks once more (Telegram-iOS asks
// so for Premium; here for every gift: it costs Stars), then canSendGift and sendGift. The words are Telegram's own
// Uzbek (the owner's iPad), «hadya», not «sovg'a».
// Limited gifts can't go to channels (TDLib's sendGift); Telegram-iOS shows a channel only those of them on resale,
// and they open its store, which we don't have: none here. Nor auction gifts (a bid, not sendGift).
import QtQuick
import QtQuick.Window

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 15

    property var store
    property var chatId: 0
    readonly property var chat: store && chatId ? store.chats[chatId] : null
    readonly property string title: chat ? chat.title : ""
    // a person's chat (their page's «yana» › «Hadya yuborish»): the gift goes to them (messageSenderUser), limited
    // ones too while there are some left (only channels can't have those), in words for a person
    readonly property bool person: !!chat && chat.type["@type"] === "chatTypePrivate"
    property bool open: false
    property bool second: false     // the gift's own sheet is up
    property var gifts: []          // availableGift's that can go to a channel, in TDLib's order
    property bool loaded: false
    property var picked: null       // the availableGift on the second sheet
    property bool hideName: false
    property bool sending: false
    property int textMax: 128       // getOption("gift_text_length_max")
    property var paths: ({})        // a sticker's file id -> where it is ("" on its way)
    property int got: 0
    signal say(string text)         // a word for the chat's toast
    property alias words: words.text    // the few words written for the gift

    readonly property real stars: store ? store.stars : -1
    // iOS 26's spring (Main.qml's)
    readonly property var spring: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]
    // Telegram's gold for Stars (GiftItemComponent: the price's words, its capsule at 0.2)
    readonly property color gold: Theme.dark ? "#ffc337" : "#d3720a"

    function show() {
        if (open)
            return
        open = true
        visible = true
        second = false
        picked = null
        grid.contentY = 0
        panel.scale = 1
        back2.opacity = 0
        panel2.y = height
        panel.y = height
        rise.to = height - panel.height + 40
        rise.restart()
        shade.restart()
        load()
    }
    function close() {
        if (!open)
            return
        open = false
        words.focus = false
        confirm.visible = false
        rise.stop()
        down.to = height
        down2.to = height
        fall.restart()
    }
    // the gifts, our balance, how long the words may be
    function load() {
        store.send({ "@type": "getAvailableGifts" }, (r) => {
            if (!sheet)
                return
            sheet.gifts = (r.gifts || []).filter((a) => !a.gift.auction_info && (sheet.person
                ? !a.gift.overall_limits || a.gift.overall_limits.remaining_count > 0 : !a.gift.overall_limits))
            sheet.loaded = true
        })
        if (store.me)
            store.send({ "@type": "getStarTransactions", owner_id: { "@type": "messageSenderUser", user_id: store.me.id },
                         subscription_id: "", direction: null, offset: "", limit: 1 }, (r) => {
                if (r["@type"] === "starTransactions")
                    store.stars = r.star_amount.star_count
            })
        store.send({ "@type": "getOption", name: "gift_text_length_max" }, (r) => {
            if (r["@type"] === "optionValueInteger" && Number(r.value) > 0)
                sheet.textMax = Number(r.value)
        })
    }
    function want(f) {
        if (!f || paths[f.id] !== undefined)
            return
        paths[f.id] = ""
        store.fetch(f, 2, (path) => {
            sheet.paths[f.id] = path
            sheet.got++
        })
    }
    function fmt(n) {
        return String(Math.floor(n)).replace(/\B(?=(\d{3})+(?!\d))/g, Tr.en ? "," : " ")
    }

    // a gift tapped: what keeps it from going, else its sheet over this one
    function pick(a) {
        const g = a.gift
        if (g.is_premium && !(store.me && store.me.is_premium))
            return say(Tr.t("Bu hadya uchun Telegram Premium kerak"))
        if (g.next_send_date && g.next_send_date > Date.now() / 1000)
            return say(Tr.t("Bu hadyani hozircha yuborib bo'lmaydi"))
        picked = a
        hideName = false
        words.text = ""
        second = true
        flick2.contentY = 0
        panel2.y = height
        up2.restart()
    }
    // the phone's ← : the alert, the gift's sheet, the gifts, one at a time
    function backOne() {
        if (confirm.visible)
            confirm.visible = false
        else if (second)
            back()
        else
            close()
    }
    function back() {
        words.focus = false
        second = false
        away2.restart()
    }
    // «Hadya yuborish»: enough Stars? then asked once more
    function ask() {
        if (!picked || sending)
            return
        if (stars >= 0 && stars < picked.gift.star_count)
            return say(Tr.t("Yulduz yetmaydi"))
        words.focus = false
        confirm.show()
    }
    function send() {
        const g = picked.gift, to = title
        sending = true
        store.send({ "@type": "canSendGift", gift_id: g.id }, (r) => {
            if (r["@type"] === "canSendGiftResultFail" || r["@type"] === "error") {
                sheet.sending = false
                return sheet.say(r.reason ? r.reason.text : Tr.t("Xatolik yuz berdi. Qayta urinib ko'ring."))
            }
            store.send({ "@type": "sendGift", gift_id: g.id, owner_id: sheet.person ? { "@type": "messageSenderUser", user_id: sheet.chat.type.user_id }
                                                                  : { "@type": "messageSenderChat", chat_id: sheet.chatId },
                         text: { "@type": "formattedText", text: words.text.trim(), entities: [] },
                         is_private: sheet.hideName, pay_for_upgrade: false }, (r) => {
                sheet.sending = false
                if (r["@type"] === "ok") {
                    sheet.close()
                    return sheet.say(Tr.f(sheet.person ? "%1ga %2 yulduzlik hadya yubordingiz." : "«%1» kanaliga %2 yulduzlik hadya yubordingiz.",
                                          to, sheet.fmt(g.star_count)))
                }
                const m = r.message || ""
                sheet.say(/USAGE_LIMITED|SOLD_OUT/.test(m) ? Tr.t("Bu hadya sotilib bo'lgan. Boshqasini tanlang.")
                        : /BALANCE_TOO_LOW/.test(m) ? Tr.t("Yulduz yetmaydi")
                        : Tr.t("Xatolik yuz berdi. Qayta urinib ko'ring."))
            })
        })
    }

    // a gift's sticker: its first frame (a TGS one by libtlottie), or played once to its last (the second sheet's)
    component GiftPic: Item {
        id: gp
        property var sticker: null
        property bool play: false
        readonly property bool tgs: !!sticker && sticker.format["@type"] === "stickerFormatTgs"
        readonly property var f: !sticker ? null : tgs || sticker.format["@type"] === "stickerFormatWebp" ? sticker.sticker
                                 : sticker.thumbnail ? sticker.thumbnail.file : null
        readonly property string path: f ? (sheet.got, sheet.paths[f.id] || "") : ""
        onFChanged: sheet.want(f)
        Component.onCompleted: sheet.want(f)
        Image {
            anchors.fill: parent
            visible: !gp.play || !anim.shown
            source: gp.path === "" ? "" : gp.tgs ? "image://lottie/0/-/" + gp.path : "image://thumb/" + gp.path
            sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        Lottie {
            id: anim
            anchors.fill: parent
            visible: gp.play && gp.tgs
            path: visible ? gp.path : ""
            once: true
            running: sheet.visible
        }
    }
    // ⭐ and a price
    component Price: Row {
        property real n: 0
        property color color: sheet.gold
        property int size: 11
        spacing: 2
        Icon { anchors.verticalCenter: parent.verticalCenter; width: parent.size + 4; height: width; name: "star"; color: "#ffb10a" }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sheet.fmt(parent.n)
            color: parent.color
            font.family: Theme.font; font.pixelSize: parent.size; font.weight: Font.DemiBold
        }
    }
    // gold sparkles strewn over an area (Telegram's StarsButtonEffectLayer and the header's stars, still here:
    // a few small four-pointed stars, the same for the same seed)
    component Sparkles: Item {
        id: sp
        property int count: 6
        property int seed: 1
        property real most: 5           // the biggest one's size
        property color color: "#ffb10a"
        Repeater {
            model: sp.count
            Icon {
                required property int index
                readonly property real r1: ((sp.seed * 37 + index * 73) % 101) / 101
                readonly property real r2: ((sp.seed * 53 + index * 29) % 97) / 97
                readonly property real r3: ((sp.seed * 17 + index * 41) % 89) / 89
                x: r1 * (sp.width - width); y: r2 * (sp.height - height)
                width: sp.most * (0.45 + 0.55 * r3); height: width
                opacity: 0.35 + 0.6 * r3
                name: index % 3 === 0 ? "star" : "sparkle"
                color: sp.color
            }
        }
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.4; duration: 300 }

    // ---- 1: the gifts ----
    Rectangle {
        id: panel
        width: parent.width
        height: parent.height - 10 + 40         // (the foot's corners below the screen)
        radius: 38
        color: Theme.grouped
        clip: true
        transformOrigin: Item.Top
        MouseArea { anchors.fill: parent }
        Flickable {
            id: grid
            width: parent.width; height: parent.height - 40
            contentHeight: optCol.height + 40 + safe.bottom
            boundsBehavior: Flickable.DragOverBounds
            Column {
                id: optCol
                width: parent.width
                Item {
                    width: parent.width; height: 140
                    Sparkles {          // the channel's picture among gold stars (GiftAvatarComponent's)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 6
                        width: Math.min(parent.width - 40, 300); height: 132
                        count: 34; seed: 7; most: 9
                    }
                    Avatar {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 20
                        width: 100; height: 100
                        source: sheet.chat ? sheet.store.photoPath(sheet.chat) : ""
                        letters: sheet.store ? sheet.store.letters(sheet.title) : ""
                        tint: sheet.store ? sheet.store.tints[Math.abs(sheet.chatId) % sheet.store.tints.length] : "grey"
                    }
                }
                Text {
                    id: bigTitle
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Hadya yuborish")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 28; font.weight: Font.Bold
                }
                Item { width: 1; height: 8 }
                Text {
                    x: 16; width: parent.width - 32
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: Tr.f("%1 uchun hadya tanlang.", "<b>" + (sheet.store ? sheet.store.escaped(sheet.title) : "") + "</b>")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15
                }
                Item { width: 1; height: 16 }
                Item {               // the chips (Telegram's tab selector): for a channel, all there is
                    width: parent.width; height: 30
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: allText.implicitWidth + 24; height: 30
                        radius: 15
                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06)
                        Text {
                            id: allText
                            anchors.centerIn: parent
                            text: Tr.t("Barcha hadyalar")
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                        }
                    }
                }
                Item { width: 1; height: 19 }
                Text {
                    visible: sheet.loaded && !sheet.gifts.length
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Hozircha hadyalar yo'q")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
                Flow {
                    id: cells
                    x: 16; width: parent.width - 32
                    spacing: 10
                    readonly property real side: (width - 20) / 3
                    Repeater {
                        model: sheet.gifts
                        Rectangle {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var g: modelData.gift
                            width: cells.side; height: 154
                            radius: 16
                            color: Theme.card
                            scale: cellHit.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            GiftPic {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 16
                                width: 88; height: 88
                                sticker: cell.g.sticker
                            }
                            Rectangle {          // the price (StarsButtonContentComponent: 30 pt, gold at 0.2, sparkles)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height - height - 10
                                width: price.width + 18; height: 30
                                radius: 15
                                color: Qt.rgba(1, 0.784, 0.239, 0.2)
                                Sparkles { anchors.fill: parent; anchors.margins: 3; count: 5; seed: cell.index + 3; most: 5 }
                                Price { id: price; anchors.centerIn: parent; n: cell.g.star_count }
                            }
                            Item {               // «premium»: a ribbon over the corner, its words at 45°
                                visible: cell.g.is_premium
                                anchors.right: parent.right
                                width: 48; height: 48
                                clip: true
                                Rectangle {
                                    x: 48 - 22 - width / 2; y: 22 - height / 2
                                    width: 76; height: 18
                                    rotation: 45
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "#ea8b01" }
                                        GradientStop { position: 1; color: "#fab625" }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: Tr.t("premium")
                                        color: "white"
                                        font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                                    }
                                }
                            }
                            MouseArea { id: cellHit; anchors.fill: parent; onClicked: sheet.pick(cell.modelData) }
                        }
                    }
                }
            }
        }
        Rectangle {          // scrolled past the big title: the bar, the name in it (as iOS's)
            width: parent.width; height: 68
            color: Theme.grouped
            opacity: Math.max(0, Math.min(1, (grid.contentY - bigTitle.y + 40) / 30))
            visible: opacity > 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 38 - height / 2
                text: Tr.t("Hadya yuborish")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
        }
        Glass {              // ✕ on the left, our Stars on the right
            x: 16; y: 16
            width: 44; height: 44
            opacity: closeHit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; name: "cross"; color: Theme.text }
            MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.close() }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 18
            visible: sheet.stars >= 0
            Text {
                anchors.right: parent.right
                text: Tr.t("Balans")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14
            }
            Price { anchors.right: parent.right; n: Math.max(0, sheet.stars); color: Theme.text; size: 14 }
        }
        Rectangle {          // the gift's sheet over it: this one steps back, darker
            id: back2
            anchors.fill: parent
            radius: parent.radius
            color: "black"
            opacity: 0
        }
    }

    // ---- 2: the gift as it will go: a sheet of its own over the first ----
    Rectangle {
        id: panel2
        width: parent.width
        height: Math.min(parent.height - 34, setCol.height + foot.height + safe.bottom) + 40
        y: parent.height
        radius: 38
        color: Theme.grouped
        clip: true
        MouseArea { anchors.fill: parent }
        Flickable {
            id: flick2
            width: parent.width
            height: parent.height - 40 - foot.height - Math.max(osk.h, safe.bottom)
            contentHeight: setCol.height
            boundsBehavior: Flickable.DragOverBounds
            clip: true
            Column {
                id: setCol
                width: parent.width
                Item {               // the wallpaper; the gift on it as the channel will see it; the words under it
                    width: parent.width; height: preview.height + 24 + field.height + 16
                    Wallpaper { anchors.fill: parent }
                    Column {
                        id: preview
                        y: 18
                        width: parent.width
                        spacing: 8
                        Rectangle {      // the service line over it
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width - 100, sentLine.implicitWidth + 20); height: sentLine.height + 6
                            radius: height / 2
                            color: Theme.dayPill
                            Text {
                                id: sentLine
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, preview.width - 120)
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                textFormat: Text.StyledText
                                text: Tr.f("Siz %1ga hadya yubordingiz", "<b>" + Tr.f("%1 yulduz", sheet.fmt(sheet.picked ? sheet.picked.gift.star_count : 0)) + "</b>")
                                color: "white"
                                font.family: Theme.font; font.pixelSize: 13
                            }
                        }
                        Rectangle {      // the card
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 230; height: cardCol.height + 28
                            radius: 24
                            color: Theme.dayPill
                            Column {
                                id: cardCol
                                y: 10
                                width: parent.width
                                spacing: 6
                                GiftPic {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 140; height: 140
                                    sticker: sheet.picked ? sheet.picked.gift.sticker : null
                                    play: sheet.second
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Tr.t("Hadya")
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                                }
                                Text {
                                    x: 14; width: parent.width - 28
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    textFormat: Text.StyledText
                                    text: sheet.person ? Tr.f("%1 bu hadyani profilida ko'rsatishi yoki uni %2ga ayirboshlashi mumkin.", sheet.store.escaped(sheet.title),
                                                           "<b>" + Tr.f("%1 yulduz", sheet.fmt(sheet.picked ? sheet.picked.gift.default_sell_star_count : 0)) + "</b>")
                                        : Tr.f("Bu hadyani kanalingiz profiliga qo'shing yoki uni %1ga ayirboshlang.",
                                               "<b>" + Tr.f("%1 yulduz", sheet.fmt(sheet.picked ? sheet.picked.gift.default_sell_star_count : 0)) + "</b>")
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 13
                                }
                                Text {
                                    x: 14; width: parent.width - 28
                                    visible: words.text.trim() !== ""
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                    text: words.text.trim()
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 14; font.italic: true
                                }
                                Item { width: 1; height: 2 }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: viewText.implicitWidth + 32; height: 32
                                    radius: 16
                                    color: Qt.rgba(1, 1, 1, 0.2)
                                    Sparkles { anchors.fill: parent; anchors.margins: 4; count: 4; seed: 11; most: 5; color: "white" }
                                    Text {
                                        id: viewText
                                        anchors.centerIn: parent
                                        text: Tr.t("Ko'rish")
                                        color: "white"
                                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }
                    Glass {          // the words, as the chat's field
                        id: field
                        x: 16; y: preview.y + preview.height + 16
                        width: parent.width - 32; height: Math.max(44, words.contentHeight + 22)
                        radius: 22
                        TextInput {
                            id: words
                            x: 16; y: 11
                            width: parent.width - 32 - (left.visible ? left.width + 6 : 0)
                            wrapMode: TextInput.Wrap
                            maximumLength: sheet.textMax
                            color: Theme.text
                            selectionColor: Theme.accent
                            font.family: Theme.font; font.pixelSize: 16
                            Text {
                                visible: !words.text && !words.preeditText
                                text: Tr.t("Xabar kiriting (ixtiyoriy)")
                                color: Theme.grey
                                font: words.font
                            }
                        }
                        Text {           // how many letters are left, near the end
                            id: left
                            visible: words.length > sheet.textMax - 30
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 13
                            text: sheet.textMax - words.length
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                }
                Item { width: 1; height: 24 }
                SettingsGroup {
                    note: sheet.person ? Tr.f("Ismim va xabarimni %1 profiliga kirganlardan berkitish. %1 ularni baribir ko'radi.", sheet.title)
                                      : Tr.t("Ismim va xabarimni bu kanalning barcha mehmonlaridan berkitish. Kanal adminlari shunda ham ularni ko'radi.")
                    Item {
                        width: parent.width; height: 48
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: Tr.t("Ismimni berkitish")
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 17
                        }
                        Switch {
                            anchors.right: parent.right; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            on: sheet.hideName
                        }
                        MouseArea { anchors.fill: parent; onClicked: sheet.hideName = !sheet.hideName }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }
        Glass {              // ✕: back to the gifts
            x: 16; y: 16
            width: 44; height: 44
            opacity: back2Hit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; name: "cross"; color: Theme.text }
            MouseArea { id: back2Hit; anchors.fill: parent; onClicked: sheet.back() }
        }
        Item {               // the foot: our balance if short, «Hadya yuborish. Narxi: ⭐ N» (52 pt, 32 from the sides)
            id: foot
            y: parent.height - 40 - height - Math.max(osk.h, safe.bottom)    // over the keyboard, or clear of the nav line
            width: parent.width; height: short.visible ? 108 : 84
            readonly property bool few: !!sheet.picked && sheet.stars >= 0 && sheet.stars < sheet.picked.gift.star_count
            Row {
                id: short
                visible: foot.few
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                spacing: 4
                Text {
                    text: Tr.t("Yulduz yetmaydi. Balansingiz:")
                    color: Theme.danger
                    font.family: Theme.font; font.pixelSize: 13
                }
                Price { n: Math.max(0, sheet.stars); color: Theme.danger; size: 13 }
            }
            Rectangle {
                x: 32; width: parent.width - 64; height: 52
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                radius: 26
                color: Theme.accent
                opacity: foot.few || sheet.sending ? 0.5 : sendHit.pressed ? 0.8 : 1
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Hadya yuborish. Narxi:")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    Price {
                        anchors.verticalCenter: parent.verticalCenter
                        n: sheet.picked ? sheet.picked.gift.star_count : 0
                        color: "white"; size: 17
                    }
                }
                MouseArea { id: sendHit; anchors.fill: parent; onClicked: sheet.ask() }
            }
        }
    }

    // ---- once more: are you sure (an alert over it all) ----
    Item {
        id: confirm
        anchors.fill: parent
        visible: false
        z: 2
        function show() {
            visible = true
            alertCard.scale = 1.1
            alertCard.opacity = 0
            alertIn.restart()
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.3) }
        MouseArea { anchors.fill: parent; onClicked: confirm.visible = false }
        Rectangle {
            id: alertCard
            anchors.centerIn: parent
            width: 290; height: alertCol.height
            radius: 26
            color: Theme.menu
            MouseArea { anchors.fill: parent }
            Column {
                id: alertCol
                width: parent.width
                Item { width: 1; height: 20 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Hadya yuborish")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Text {
                    x: 18; width: parent.width - 36
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: !sheet.picked ? "" : Tr.f(sheet.person ? "%1ga %2 yulduzlik hadya yuborilsinmi?" : "%1 kanaliga %2 yulduzlik hadya yuborilsinmi?",
                                                    "<b>" + sheet.store.escaped(sheet.title) + "</b>",
                                                    "<b>" + sheet.fmt(sheet.picked.gift.star_count) + "</b>")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Item { width: 1; height: 18 }
                Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                Row {
                    width: parent.width; height: 48
                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        color: noHit.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Bekor qilish")
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 17
                        }
                        MouseArea { id: noHit; anchors.fill: parent; onClicked: confirm.visible = false }
                    }
                    Rectangle { width: 0.5; height: parent.height; color: Theme.separator }
                    Rectangle {
                        width: parent.width / 2 - 0.5; height: parent.height
                        color: yesHit.pressed ? Theme.highlight : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Tasdiqlash")
                            color: Theme.accent
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: yesHit
                            anchors.fill: parent
                            onClicked: {
                                confirm.visible = false
                                sheet.send()
                            }
                        }
                    }
                }
            }
            ParallelAnimation {
                id: alertIn
                ScaleAnimator { target: alertCard; to: 1; duration: 250; easing.type: Easing.OutCubic }
                OpacityAnimator { target: alertCard; to: 1; duration: 200 }
            }
        }
    }

    YAnimator {
        id: rise
        target: panel
        duration: 450
        easing.type: Easing.BezierSpline
        easing.bezierCurve: sheet.spring
    }
    ParallelAnimation {
        id: fall
        YAnimator { id: down; target: panel; duration: 250; easing.type: Easing.InCubic }
        YAnimator { id: down2; target: panel2; duration: 250; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 250 }
        onFinished: sheet.visible = false
    }
    // the gift's sheet up over the first, which steps back (smaller, darker), and down again
    ParallelAnimation {
        id: up2
        YAnimator { target: panel2; to: sheet.height - panel2.height + 40; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.spring }
        ScaleAnimator { target: panel; to: 0.94; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.spring }
        OpacityAnimator { target: back2; to: 0.25; duration: 300 }
    }
    ParallelAnimation {
        id: away2
        YAnimator { target: panel2; to: sheet.height; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.spring }
        ScaleAnimator { target: panel; to: 1; duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: sheet.spring }
        OpacityAnimator { target: back2; to: 0; duration: 300 }
    }
}
