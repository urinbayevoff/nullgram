pragma ComponentBehavior: Bound
// Channel boosts bottom sheet (1.0): displays getChatBoostStatus (level, current/next level
// boost counts, progress bar, boost_url copy) and lets Premium users boost the channel via
// getAvailableChatBoostSlots -> Alert confirmation -> boostChat. Respects safe.bottom and Theme.
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 95

    property var store: null
    property var chatId: 0
    property string chatTitle: ""
    property real safeBottom: 0
    property bool open: false

    property var status: null           // chatBoostStatus
    property var slots: []              // chatBoostSlot[]
    property bool loading: false
    property bool busy: false
    property string errorText: ""
    property int _reqId: 0

    signal said(string text)
    signal boosted()
    signal closed()

    readonly property bool isPremium: !!(store && store.me && store.me.is_premium)
    readonly property int level: status ? Number(status.level || 0) : 0
    readonly property int boostCount: status ? Number(status.boost_count || 0) : 0
    readonly property int curLevelCount: status ? Number(status.current_level_boost_count || 0) : 0
    readonly property int nextLevelCount: status ? Number(status.next_level_boost_count || 0) : 0
    readonly property bool maxLevel: !!status && nextLevelCount <= 0
    readonly property int remaining: maxLevel ? 0 : Math.max(0, nextLevelCount - boostCount)
    readonly property real progress: {
        if (!status)
            return 0
        if (maxLevel)
            return 1
        const span = Math.max(1, nextLevelCount - curLevelCount)
        return Math.max(0, Math.min(1, (boostCount - curLevelCount) / span))
    }
    readonly property string boostUrl: status && status.boost_url ? String(status.boost_url) : ""
    readonly property int appliedCount: status && status.applied_slot_ids ? status.applied_slot_ids.length : 0

    readonly property var freeSlot: {
        const now = Math.floor(Date.now() / 1000)
        for (const s of slots) {
            if (!s)
                continue
            const cid = Number(s.currently_boosted_chat_id || 0)
            const cd = Number(s.cooldown_until_date || 0)
            if (cid === 0 && cd <= now)
                return s
        }
        return null
    }

    readonly property var movableSlot: {
        const now = Math.floor(Date.now() / 1000)
        for (const s of slots) {
            if (!s)
                continue
            const cid = Number(s.currently_boosted_chat_id || 0)
            const cd = Number(s.cooldown_until_date || 0)
            if (cid !== 0 && cid !== chatId && cd <= now)
                return s
        }
        return null
    }

    readonly property int nextCooldown: {
        const now = Math.floor(Date.now() / 1000)
        let earliest = 0
        for (const s of slots) {
            if (!s)
                continue
            const cid = Number(s.currently_boosted_chat_id || 0)
            const cd = Number(s.cooldown_until_date || 0)
            if (cid !== chatId && cd > now && (earliest === 0 || cd < earliest))
                earliest = cd
        }
        return earliest
    }

    readonly property bool canBoost: isPremium && !loading && !busy && !!status && (freeSlot !== null || movableSlot !== null)

    function show(cid, title, initialStatus) {
        chatId = cid
        chatTitle = title || ""
        status = initialStatus || null
        slots = []
        errorText = ""
        busy = false
        open = true
        visible = true
        fall.stop()
        shade.stop()
        panelSlide.y = panel.height
        dim.opacity = 0
        rise.from = panel.height
        rise.restart()
        shade.restart()
        loadAll()
    }

    function close() {
        if (!open)
            return
        alert.open = false
        open = false
        _reqId++
        loading = false
        busy = false
        rise.stop()
        shade.stop()
        fallY.to = panel.height
        fall.restart()
        closed()
    }

    function dismiss() {
        if (alert.open) {
            alert.open = false
            return true
        }
        if (open) {
            close()
            return true
        }
        return false
    }

    function loadAll() {
        if (!store || !chatId)
            return
        const req = ++_reqId
        loading = true
        errorText = ""
        store.getChatBoostStatus(chatId, (st, err) => {
            if (!sheet || req !== sheet._reqId || !sheet.open)
                return
            if (!st) {
                sheet.loading = false
                sheet.errorText = err || Tr.t("Boost holatini yuklab bo'lmadi")
                return
            }
            sheet.status = st
            if (!sheet.isPremium) {
                sheet.loading = false
                return
            }
            store.getAvailableBoostSlots((sl, slErr) => {
                if (!sheet || req !== sheet._reqId || !sheet.open)
                    return
                sheet.loading = false
                sheet.slots = sl || []
                if (slErr && !sl.length)
                    console.warn("nullgram: boost slots", slErr)
            })
        })
    }

    function copyUrl() {
        if (!boostUrl)
            return
        clip.text = boostUrl
        clip.selectAll()
        clip.copy()
        said(Tr.t("Boost havolasi nusxalandi"))
    }

    function askBoost() {
        if (!isPremium) {
            said(Tr.t("Kanalga boost berish uchun Telegram Premium kerak"))
            return
        }
        if (!canBoost)
            return
        const slot = freeSlot || movableSlot
        if (!slot)
            return
        const moving = freeSlot === null
        if (moving) {
            const otherChat = store && store.chats ? store.chats[slot.currently_boosted_chat_id] : null
            const otherName = otherChat ? store.title(otherChat) : Tr.t("boshqa kanal")
            alert.show(
                Tr.t("Boostni ko'chirish"),
                Tr.f("Bo'sh o'rin yo'q. «%1» kanalidagi boostni «%2» kanaliga ko'chirasizmi?", otherName, chatTitle),
                [{ t: Tr.t("Bekor qilish") },
                 { t: Tr.t("Ko'chirish"), bold: true, run: () => sheet.doBoost(slot.slot_id) }]
            )
        } else {
            alert.show(
                Tr.t("Kanalga boost berish"),
                Tr.f("«%1» kanaliga boost berasizmi?", chatTitle),
                [{ t: Tr.t("Bekor qilish") },
                 { t: Tr.t("Boost berish"), bold: true, run: () => sheet.doBoost(slot.slot_id) }]
            )
        }
    }

    function doBoost(slotId) {
        if (!store || !chatId || busy)
            return
        const req = ++_reqId
        busy = true
        store.boostChat(chatId, [slotId], (updatedSlots, err) => {
            if (!sheet || req !== sheet._reqId)
                return
            if (!updatedSlots) {
                sheet.busy = false
                const msg = /PREMIUM/i.test(err || "")
                    ? Tr.t("Kanalga boost berish uchun Telegram Premium kerak")
                    : /COOLDOWN/i.test(err || "")
                    ? Tr.t("Bu boost o'rnini hozircha ko'chirib bo'lmaydi")
                    : Tr.f("Boost berib bo'lmadi: %1", err || "")
                sheet.said(msg)
                return
            }
            sheet.slots = updatedSlots
            store.getChatBoostStatus(chatId, (st, stErr) => {
                if (!sheet || req !== sheet._reqId)
                    return
                sheet.busy = false
                if (st)
                    sheet.status = st
                sheet.said(Tr.t("Kanalga boost berildi"))
                sheet.boosted()
            })
        })
    }

    TextEdit { id: clip; visible: false }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(sheet.height * 0.85, contentCol.implicitHeight + 28 + sheet.safeBottom)
        radius: 18
        color: Theme.bg
        clip: true
        transform: Translate { id: panelSlide; y: panel.height }

        // Flat bottom corners
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 18; color: Theme.bg
        }
        MouseArea { anchors.fill: parent }

        // Handle pill
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8; width: 36; height: 4; radius: 2
            color: Theme.grey; opacity: 0.35
        }

        Column {
            id: contentCol
            x: 16; y: 20
            width: parent.width - 32
            spacing: 14

            // Header row
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: "#af52de"
                        anchors.verticalCenter: parent.verticalCenter
                        Icon { anchors.centerIn: parent; width: 16; height: 16; name: "sparkle"; color: "white" }
                    }
                    Text {
                        text: Tr.t("Kanal boostlari")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    color: closeHit.pressed ? Theme.highlight : Theme.card
                    Icon { anchors.centerIn: parent; width: 14; height: 14; name: "cross"; color: Theme.grey }
                    MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.close() }
                }
            }

            // Loading state
            Row {
                visible: sheet.loading && !sheet.status
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                topPadding: 20; bottomPadding: 20
                Ring { width: 18; height: 18; value: 0.7; color: Theme.accent; cross: false; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: Tr.t("Yuklanmoqda…")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Error state
            Column {
                visible: !sheet.loading && sheet.errorText !== "" && !sheet.status
                width: parent.width
                spacing: 10
                topPadding: 14; bottomPadding: 14
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: sheet.errorText
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: retryText.implicitWidth + 28; height: 34; radius: 17
                    color: retryArea.pressed ? Theme.highlight : Theme.card
                    Text {
                        id: retryText
                        anchors.centerIn: parent
                        text: Tr.t("Qayta urinish")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    MouseArea { id: retryArea; anchors.fill: parent; onClicked: sheet.loadAll() }
                }
            }

            // Boost level & progress card
            Rectangle {
                visible: !!sheet.status
                width: parent.width
                height: levelCol.implicitHeight + 28
                radius: 14
                color: Theme.card
                Column {
                    id: levelCol
                    x: 16; y: 14
                    width: parent.width - 32
                    spacing: 10

                    Item {
                        width: parent.width; height: 26
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Tr.f("%1-daraja", sheet.level)
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: sheet.maxLevel
                                ? Tr.n("%1 boost", sheet.boostCount)
                                : sheet.boostCount + " / " + sheet.nextLevelCount
                            color: "#af52de"
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                    }

                    // Progress bar
                    Rectangle {
                        width: parent.width; height: 8; radius: 4
                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                        clip: true
                        Rectangle {
                            width: Math.max(sheet.progress > 0 ? 10 : 0, parent.width * sheet.progress)
                            height: parent.height; radius: 4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#af52de" }
                                GradientStop { position: 1; color: Theme.accent }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: sheet.maxLevel
                            ? Tr.t("Kanal maksimal boost darajasiga yetgan.")
                            : Tr.f("Keyingi daraja (%1) uchun yana %2 ta boost kerak.", sheet.level + 1, sheet.remaining)
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }

                    Text {
                        visible: sheet.appliedCount > 0
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: Tr.f("Siz ushbu kanalga %1 ta boost bergansiz.", sheet.appliedCount)
                        color: "#34c759"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
            }

            // Boost URL copy card
            Rectangle {
                visible: !!sheet.status && sheet.boostUrl !== ""
                width: parent.width
                height: 52
                radius: 12
                color: urlHit.pressed ? Theme.highlight : Theme.card
                Column {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - copyPill.width - 36
                    spacing: 2
                    Text {
                        text: Tr.t("Boost havolasi")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: sheet.boostUrl.replace(/^https?:\/\//, "")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    id: copyPill
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: copyLbl.implicitWidth + 20; height: 30; radius: 15
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 122, 255, 0.12)
                    Text {
                        id: copyLbl
                        anchors.centerIn: parent
                        text: Tr.t("Nusxa olish")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: urlHit
                    anchors.fill: parent
                    onClicked: sheet.copyUrl()
                }
            }

            // Premium / slot status notice
            Rectangle {
                visible: !!sheet.status && (!sheet.isPremium || (!sheet.loading && !sheet.canBoost))
                width: parent.width
                height: noticeText.implicitHeight + 20
                radius: 12
                color: Theme.dark ? Qt.rgba(175 / 255, 82 / 255, 222 / 255, 0.18) : Qt.rgba(175 / 255, 82 / 255, 222 / 255, 0.1)
                Text {
                    id: noticeText
                    x: 14; y: 10
                    width: parent.width - 28
                    wrapMode: Text.Wrap
                    text: !sheet.isPremium
                        ? Tr.t("Kanalga boost berish uchun Telegram Premium kerak. Premium bilan kanalga hikoya va maxsus imkoniyatlarni ochasiz.")
                        : sheet.nextCooldown > 0
                        ? Tr.f("Barcha boost o'rinlari band. Keyingi o'rin %1 da ochiladi.", Qt.formatDateTime(new Date(sheet.nextCooldown * 1000), "dd.MM HH:mm"))
                        : sheet.appliedCount > 0
                        ? Tr.t("Barcha boost o'rinlaringiz shu kanalga berilgan.")
                        : Tr.t("Bo'sh boost o'rinlari yo'q.")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                }
            }

            // Primary Boost action button
            Rectangle {
                visible: !!sheet.status
                width: parent.width
                height: 48
                radius: 12
                color: !sheet.canBoost
                    ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                    : boostBtnHit.pressed ? "#933bc4" : "#af52de"
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Ring {
                        visible: sheet.busy
                        width: 16; height: 16
                        value: 0.7
                        color: "white"
                        cross: false
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Icon {
                        visible: !sheet.busy
                        width: 18; height: 18
                        name: "sparkle"
                        color: sheet.canBoost ? "white" : Theme.grey
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: !sheet.isPremium
                            ? Tr.t("Telegram Premium kerak")
                            : sheet.freeSlot === null && sheet.movableSlot !== null
                            ? Tr.t("Boostni ko'chirish")
                            : sheet.appliedCount > 0
                            ? Tr.t("Yana boost berish")
                            : Tr.t("Boost berish")
                        color: sheet.canBoost ? "white" : Theme.grey
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: boostBtnHit
                    anchors.fill: parent
                    enabled: !sheet.busy && !sheet.loading
                    onClicked: sheet.askBoost()
                }
            }
        }
    }

    Alert { id: alert; anchors.fill: parent }

    NumberAnimation {
        id: rise
        target: panelSlide; property: "y"
        to: 0; duration: 300
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: shade
        target: dim; property: "opacity"
        to: 1; duration: 240
    }
    ParallelAnimation {
        id: fall
        NumberAnimation { id: fallY; target: panelSlide; property: "y"; duration: 240; easing.type: Easing.InCubic }
        NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 200 }
        onFinished: if (!sheet.open) sheet.visible = false
    }
}
