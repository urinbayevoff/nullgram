// A received gift shown in detail (Telegram-iOS's GiftViewScreen): sticker (TGS played once via Lottie or thumbnail)
// over sparkles (regular) or its upgraded backdrop gradient, title, message, sender/date/value/rarity table, and
// for the channel's admins (can_post_messages) or owner: show/hide on profile (toggleGiftIsSaved), pin/unpin
// (setPinnedGifts), or convert to Stars (sellGift, asked first).
import QtQuick
import QtQuick.Window

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 28

    property var store
    property var ownerId: null          // MessageSender of the profile owning this gift
    property var gift: null             // TDLib receivedGift
    property var allGifts: []           // currently loaded receivedGifts (needed to build pinned ids list)
    property bool canManage: false      // channel admin with can_post_messages (or creator)
    property bool canSell: false        // channel creator (owner privileges for sellGift)
    property bool open: false
    property bool busy: false
    property var paths: ({})
    property int got: 0
    signal say(string text)
    signal changed()
    signal openSender(var sender)

    readonly property var sent: gift ? gift.gift : null
    readonly property bool upgraded: !!sent && sent["@type"] === "sentGiftUpgraded"
    readonly property var inner: sent ? sent.gift : null
    readonly property var sticker: !inner ? null : upgraded ? (inner.model ? inner.model.sticker : null) : inner.sticker
    readonly property var backdrop: upgraded && inner && inner.backdrop ? inner.backdrop.colors : null
    readonly property color gold: Theme.dark ? "#ffc337" : "#d3720a"
    readonly property var spring: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]

    function hex(c) { return "#" + ((c >>> 0) & 0xffffff).toString(16).padStart(6, "0") }
    function fmt(n) { return String(Math.floor(n || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, Tr.en ? "," : " ") }
    function when(ts) {
        if (!ts)
            return ""
        const d = new Date(ts * 1000)
        return Tr.date(d.getDate(), d.getMonth() + 1, d.getFullYear()) + ", " + Qt.formatTime(d, "HH:mm")
    }
    function want(f) {
        if (!f || paths[f.id] !== undefined)
            return
        paths[f.id] = ""
        store.fetch(f, 4, (path) => {
            if (!sheet)
                return
            sheet.paths[f.id] = path
            sheet.got++
        })
    }

    function show(receivedGift, owner, list, manage, sell) {
        gift = receivedGift
        ownerId = owner
        allGifts = list || []
        canManage = !!manage
        canSell = !!sell
        busy = false
        confirm.visible = false
        flick.contentY = 0
        if (sticker)
            want(sticker.format["@type"] === "stickerFormatTgs" || sticker.format["@type"] === "stickerFormatWebp"
                 ? sticker.sticker : sticker.thumbnail ? sticker.thumbnail.file : null)
        open = true
        visible = true
        panel.y = height
        rise.to = height - panel.height + 40
        rise.restart()
        shade.restart()
    }
    function close() {
        if (!open)
            return
        open = false
        confirm.visible = false
        rise.stop()
        down.to = height
        fall.restart()
    }
    function backOne() {
        if (confirm.visible)
            confirm.visible = false
        else
            close()
    }

    function toggleSaved() {
        if (!gift || !gift.received_gift_id || busy)
            return
        const next = !gift.is_saved
        busy = true
        store.send({ "@type": "toggleGiftIsSaved", received_gift_id: gift.received_gift_id, is_saved: next }, (r) => {
            sheet.busy = false
            if (r["@type"] === "error")
                return sheet.say(Tr.f("Bo'lmadi: %1", r.message))
            sheet.gift = Object.assign({}, sheet.gift, { is_saved: next, is_pinned: next ? sheet.gift.is_pinned : false })
            sheet.say(Tr.t(next ? "Hadya profilda ko'rsatiladi" : "Hadya profildan yashirildi"))
            sheet.changed()
        })
    }
    function togglePinned() {
        if (!gift || !gift.received_gift_id || !ownerId || busy)
            return
        const id = gift.received_gift_id
        const ids = allGifts.filter((g) => g.is_pinned && g.received_gift_id).map((g) => g.received_gift_id)
        const next = !gift.is_pinned
        const out = next ? [id].concat(ids.filter((x) => x !== id)) : ids.filter((x) => x !== id)
        busy = true
        store.send({ "@type": "setPinnedGifts", owner_id: ownerId, received_gift_ids: out }, (r) => {
            sheet.busy = false
            if (r["@type"] === "error")
                return sheet.say(Tr.f("Bo'lmadi: %1", r.message))
            sheet.gift = Object.assign({}, sheet.gift, { is_pinned: next })
            sheet.say(Tr.t(next ? "Hadya profilga qadaldi" : "Hadya profildan yechildi"))
            sheet.changed()
        })
    }
    function doSell() {
        if (!gift || !gift.received_gift_id || busy)
            return
        busy = true
        store.send({ "@type": "sellGift", business_connection_id: "", received_gift_id: gift.received_gift_id }, (r) => {
            sheet.busy = false
            if (r["@type"] === "error")
                return sheet.say(Tr.f("Bo'lmadi: %1", r.message))
            sheet.say(Tr.f("Hadya ⭐ %1ga ayirboshlandi", sheet.fmt(sheet.gift.sell_star_count)))
            sheet.changed()
            sheet.close()
        })
    }

    readonly property bool tgs: !!sticker && sticker.format["@type"] === "stickerFormatTgs"
    readonly property var picFile: !sticker ? null
        : tgs || sticker.format["@type"] === "stickerFormatWebp" ? sticker.sticker
        : sticker.thumbnail ? sticker.thumbnail.file : null
    readonly property string picPath: picFile ? (got, paths[picFile.id] || "") : ""

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.4; duration: 300 }

    Rectangle {
        id: panel
        width: parent.width
        height: Math.min(parent.height - 44, body.height + foot.height + safe.bottom) + 40
        onHeightChanged: if (sheet.open && !rise.running) y = sheet.height - height + 40
        radius: 34
        color: Theme.grouped
        clip: true
        MouseArea { anchors.fill: parent }

        Flickable {
            id: flick
            width: parent.width
            height: parent.height - 40 - foot.height - safe.bottom
            contentHeight: body.height
            boundsBehavior: Flickable.DragOverBounds
            clip: true

            Column {
                id: body
                width: parent.width
                spacing: 0

                // ---- hero: backdrop (upgraded) or sparkles (regular) + animated sticker ----
                Rectangle {
                    width: parent.width
                    height: 220
                    gradient: Gradient {
                        GradientStop { position: 0; color: sheet.backdrop ? sheet.hex(sheet.backdrop.center_color) : Theme.grouped }
                        GradientStop { position: 1; color: sheet.backdrop ? sheet.hex(sheet.backdrop.edge_color) : Theme.grouped }
                    }
                    Repeater {      // subtle sparkles
                        model: 16
                        Icon {
                            required property int index
                            readonly property real r1: ((index * 67 + 19) % 97) / 97
                            readonly property real r2: ((index * 41 + 11) % 89) / 89
                            x: 36 + r1 * (parent.width - 72)
                            y: 20 + r2 * 140
                            width: 6 + (index % 3) * 2; height: width
                            opacity: sheet.upgraded ? 0.35 : 0.55
                            name: index % 2 === 0 ? "sparkle" : "star"
                            color: sheet.upgraded ? "white" : "#ffb10a"
                        }
                    }
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 26
                        width: 120; height: 120
                        Image {
                            anchors.fill: parent
                            visible: !anim.shown
                            source: sheet.picPath === "" ? "" : sheet.tgs ? "image://lottie/0/-/" + sheet.picPath : "image://thumb/" + sheet.picPath
                            sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                        }
                        Lottie {
                            id: anim
                            anchors.fill: parent
                            visible: sheet.tgs
                            path: visible && sheet.open ? sheet.picPath : ""
                            once: true
                            running: sheet.visible
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 154
                        width: parent.width - 32
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: sheet.upgraded && sheet.inner ? sheet.inner.title + " #" + sheet.inner.number : Tr.t("Hadya")
                        color: sheet.upgraded ? "white" : Theme.text
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 184
                        width: parent.width - 48
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: sheet.gift && sheet.gift.text && sheet.gift.text.text ? sheet.gift.text.text
                            : sheet.upgraded ? Tr.t("Noyob kolleksiya hadyasi")
                            : Tr.t(sheet.gift && sheet.gift.is_saved ? "Profilda ko'rsatilmoqda" : "Profildan yashirilgan")
                        color: sheet.upgraded ? Qt.rgba(1, 1, 1, 0.85) : Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }

                Item { width: 1; height: 14 }

                // ---- gift metadata table ----
                SettingsGroup {
                    SettingsRow {
                        readonly property var s: sheet.gift ? sheet.gift.sender_id : null
                        readonly property bool hidden: !s || (sheet.gift && sheet.gift.is_private && !sheet.canManage)
                        text: Tr.t("Kimdan")
                        value: hidden ? Tr.t("Noma'lum") : (sheet.store.seen, sheet.store.senderName(s, false) || Tr.t("Noma'lum"))
                        accent: false
                        chevron: !hidden && !!s
                        onClicked: if (!hidden && s) { sheet.close(); sheet.openSender(s) }
                    }
                    SettingsRow {
                        text: Tr.t("Sana")
                        value: sheet.gift ? sheet.when(sheet.gift.date) : ""
                        chevron: false
                    }
                    SettingsRow {
                        visible: !sheet.upgraded && !!sheet.inner
                        text: Tr.t("Qiymati")
                        value: sheet.inner ? "⭐ " + sheet.fmt(sheet.inner.star_count) : ""
                        chevron: false
                        last: !sheet.canManage && !(sheet.inner && sheet.inner.overall_limits)
                    }
                    SettingsRow {
                        visible: !sheet.upgraded && !!sheet.inner && !!sheet.inner.overall_limits
                        text: Tr.t("Mavjudligi")
                        value: sheet.inner && sheet.inner.overall_limits
                            ? Tr.f("%1 tadan %2 qoldi", sheet.fmt(sheet.inner.overall_limits.total_count), sheet.fmt(sheet.inner.overall_limits.remaining_count)) : ""
                        chevron: false
                        last: !sheet.canManage
                    }
                    SettingsRow {
                        visible: sheet.upgraded && !!sheet.inner && !!sheet.inner.model
                        text: Tr.t("Model")
                        value: sheet.inner && sheet.inner.model ? sheet.inner.model.name + " · " + (sheet.inner.model.rarity_per_mille / 10).toFixed(1) + "%" : ""
                        chevron: false
                    }
                    SettingsRow {
                        visible: sheet.upgraded && !!sheet.inner && !!sheet.inner.backdrop
                        text: Tr.t("Fon")
                        value: sheet.inner && sheet.inner.backdrop ? sheet.inner.backdrop.name + " · " + (sheet.inner.backdrop.rarity_per_mille / 10).toFixed(1) + "%" : ""
                        chevron: false
                    }
                    SettingsRow {
                        visible: sheet.upgraded && !!sheet.inner && !!sheet.inner.symbol
                        text: Tr.t("Belgi")
                        value: sheet.inner && sheet.inner.symbol ? sheet.inner.symbol.name + " · " + (sheet.inner.symbol.rarity_per_mille / 10).toFixed(1) + "%" : ""
                        chevron: false
                        last: !sheet.canManage
                    }
                    SettingsRow {
                        visible: sheet.canManage && !!sheet.gift
                        text: Tr.t("Holati")
                        value: Tr.t(sheet.gift && sheet.gift.is_saved ? "Profilda ko'rinadi" : "Yashirilgan")
                        chevron: false
                        last: true
                    }
                }

                // ---- admin quick actions (pin / convert to stars) ----
                Item { width: 1; height: sheet.canManage && (canPinRow.visible || canSellRow.visible) ? 14 : 0 }
                SettingsGroup {
                    visible: canPinRow.visible || canSellRow.visible
                    SettingsRow {
                        id: canPinRow
                        visible: sheet.canManage && sheet.upgraded && !!sheet.gift && sheet.gift.is_saved && !!sheet.gift.received_gift_id
                        text: Tr.t(sheet.gift && sheet.gift.is_pinned ? "Profildan yechish" : "Profilga qadash")
                        accent: true; chevron: false
                        last: !canSellRow.visible
                        onClicked: sheet.togglePinned()
                    }
                    SettingsRow {
                        id: canSellRow
                        visible: sheet.canSell && !sheet.upgraded && !!sheet.gift && sheet.gift.sell_star_count > 0 && !!sheet.gift.received_gift_id
                        text: Tr.f("⭐ %1ga ayirboshlash", sheet.fmt(sheet.gift ? sheet.gift.sell_star_count : 0))
                        danger: true; chevron: false; last: true
                        onClicked: confirm.show()
                    }
                }
                Item { width: 1; height: 14 }
            }
        }

        // ---- ✕ button ----
        Glass {
            x: 16; y: 16
            width: 40; height: 40
            opacity: closeHit.pressed ? 0.7 : 1
            Icon { anchors.centerIn: parent; width: 20; height: 20; name: "cross"; color: Theme.text }
            MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.close() }
        }

        // ---- bottom CTA button (safe.bottom aware) ----
        Rectangle {
            id: foot
            y: parent.height - 40 - height - safe.bottom
            width: parent.width; height: 76
            color: Theme.grouped
            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
            Rectangle {
                x: 20; width: parent.width - 40; height: 50
                anchors.bottom: parent.bottom; anchors.bottomMargin: 13
                radius: 25
                color: Theme.accent
                opacity: sheet.busy ? 0.5 : ctaHit.pressed ? 0.8 : 1
                Text {
                    anchors.centerIn: parent
                    text: sheet.canManage && sheet.gift && sheet.gift.received_gift_id
                        ? Tr.t(sheet.gift.is_saved ? "Profildan yashirish" : "Profilda ko'rsatish")
                        : Tr.t("Yopish")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea {
                    id: ctaHit
                    anchors.fill: parent
                    onClicked: sheet.canManage && sheet.gift && sheet.gift.received_gift_id ? sheet.toggleSaved() : sheet.close()
                }
            }
        }
    }

    // ---- sell confirmation alert ----
    Item {
        id: confirm
        anchors.fill: parent
        visible: false
        z: 4
        function show() { visible = true }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }
        MouseArea { anchors.fill: parent; onClicked: confirm.visible = false }
        Rectangle {
            anchors.centerIn: parent
            width: 290; height: alertCol.height
            radius: 24
            color: Theme.menu
            MouseArea { anchors.fill: parent }
            Column {
                id: alertCol
                width: parent.width
                Item { width: 1; height: 18 }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Yulduzga ayirboshlash")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Text {
                    x: 18; width: parent.width - 36
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: Tr.f("Bu hadya o'chiriladi va kanal balansiga ⭐ %1 qo'shiladi. Buni qaytarib bo'lmaydi.",
                               sheet.fmt(sheet.gift ? sheet.gift.sell_star_count : 0))
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14
                }
                Item { width: 1; height: 16 }
                Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                Row {
                    width: parent.width; height: 46
                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        color: noHit.pressed ? Theme.highlight : "transparent"
                        Text { anchors.centerIn: parent; text: Tr.t("Bekor qilish"); color: Theme.accent; font.family: Theme.font; font.pixelSize: 17 }
                        MouseArea { id: noHit; anchors.fill: parent; onClicked: confirm.visible = false }
                    }
                    Rectangle { width: 0.5; height: parent.height; color: Theme.separator }
                    Rectangle {
                        width: parent.width / 2 - 0.5; height: parent.height
                        color: yesHit.pressed ? Theme.highlight : "transparent"
                        Text { anchors.centerIn: parent; text: Tr.t("Ayirboshlash"); color: Theme.danger; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                        MouseArea { id: yesHit; anchors.fill: parent; onClicked: { confirm.visible = false; sheet.doSell() } }
                    }
                }
            }
        }
    }

    YAnimator {
        id: rise
        target: panel
        duration: 420
        easing.type: Easing.BezierSpline
        easing.bezierCurve: sheet.spring
        onFinished: if (sheet.open) panel.y = sheet.height - panel.height + 40
    }
    ParallelAnimation {
        id: fall
        YAnimator { id: down; target: panel; duration: 240; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 240 }
        onFinished: sheet.visible = false
    }
}
