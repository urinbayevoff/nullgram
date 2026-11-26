pragma ComponentBehavior: Bound
// Bottom sheet to pick a date and time for a scheduled message (Telegram-iOS ScheduleMessageController style):
// three wheels (day: Today / Tomorrow / next 365 days, hour 00..23, minute 00..59) and an accent send button
// («Bugun 18:30 da yuborish»), clear of ztMETRO's nav line (safe.bottom).
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 31

    property bool open: false
    property bool reschedule: false     // true when changing an existing scheduled message's time
    property bool allowOnline: false    // show a secondary "Send When Online" link (e.g. when rescheduling in private chat)
    property int dayIndex: 0            // 0 = today, 1 = tomorrow, ...
    property int hour: 0
    property int minute: 0
    property double baseDayMs: 0        // local midnight of "today" when opened (ms)
    property var dayLabels: []
    property bool _syncing: false

    signal picked(var schedulingState)
    signal cancelled()

    readonly property int rowH: 34

    function two(n) { return n < 10 ? "0" + n : String(n) }

    function buildDays(baseMs) {
        const out = []
        const months = Tr.en ? Tr.monthsEn : Tr.monthsUz
        for (let i = 0; i < 365; i++) {
            if (i === 0) {
                out.push(Tr.t("Bugun"))
            } else if (i === 1) {
                out.push(Tr.t("Ertaga"))
            } else {
                const d = new Date(baseMs + i * 86400000)
                const mShort = months[d.getMonth()].slice(0, 3)
                const wd = Tr.weekday(d.getDay())
                out.push(Tr.en ? mShort + " " + d.getDate() + ", " + wd
                               : d.getDate() + "-" + mShort + ", " + wd)
            }
        }
        return out
    }

    function targetDate() {
        const d = new Date(baseDayMs + dayIndex * 86400000)
        d.setHours(hour, minute, 0, 0)
        return d
    }

    function selectedUnix() {
        return Math.floor(targetDate().getTime() / 1000)
    }

    readonly property string actionLabel: {
        const hm = two(hour) + ":" + two(minute)
        if (dayIndex === 0)
            return Tr.f("Bugun %1 da yuborish", hm)
        if (dayIndex === 1)
            return Tr.f("Ertaga %1 da yuborish", hm)
        const base = new Date(baseDayMs)
        const d = new Date(baseDayMs + dayIndex * 86400000)
        const y = d.getFullYear() !== base.getFullYear() ? d.getFullYear() : 0
        return Tr.f("%1 %2 da yuborish", Tr.date(d.getDate(), d.getMonth() + 1, y), hm)
    }

    function clampToFuture() {
        const now = new Date()
        const minTarget = new Date(now.getTime() + 60000)
        minTarget.setSeconds(0, 0)
        const chosen = targetDate()
        if (chosen.getTime() < minTarget.getTime()) {
            const diffDays = Math.max(0, Math.min(364, Math.floor((new Date(minTarget.getFullYear(), minTarget.getMonth(), minTarget.getDate()).getTime() - baseDayMs) / 86400000)))
            applyWheels(diffDays, minTarget.getHours(), minTarget.getMinutes())
        }
    }

    function applyWheels(dIdx, h, m) {
        _syncing = true
        dayIndex = Math.max(0, Math.min(364, dIdx))
        hour = Math.max(0, Math.min(23, h))
        minute = Math.max(0, Math.min(59, m))
        dayCol.currentIndex = dayIndex
        dayCol.positionViewAtIndex(dayIndex, ListView.Center)
        hourCol.currentIndex = hour
        hourCol.positionViewAtIndex(hour, ListView.Center)
        minCol.currentIndex = minute
        minCol.positionViewAtIndex(minute, ListView.Center)
        _syncing = false
    }

    // Convenience for callers and tests: set day offset (0=today, 1=tomorrow, ...) and HH:mm
    function setDateTime(dIdx, h, m) {
        applyWheels(dIdx, h, m)
        clampToFuture()
    }

    function show(initialUnix, isReschedule, canOnline) {
        reschedule = !!isReschedule
        allowOnline = !!canOnline
        const now = new Date()
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        baseDayMs = midnight.getTime()
        dayLabels = buildDays(baseDayMs)

        let init
        if (initialUnix && initialUnix > Math.floor(now.getTime() / 1000) + 60) {
            init = new Date(initialUnix * 1000)
        } else {
            // Default: next 5-minute mark at least 5 minutes from now
            const stepMs = 5 * 60000
            init = new Date(Math.ceil((now.getTime() + 5 * 60000) / stepMs) * stepMs)
        }
        const initDay = new Date(init.getFullYear(), init.getMonth(), init.getDate()).getTime()
        const dIdx = Math.max(0, Math.min(364, Math.round((initDay - baseDayMs) / 86400000)))
        applyWheels(dIdx, init.getHours(), init.getMinutes())

        open = true
        visible = true
        fall.stop()
        panel.y = height
        rise.to = height - panel.height
        rise.restart()
        shade.restart()
    }

    function close(emitCancel) {
        if (!open)
            return
        open = false
        rise.stop()
        fallY.to = height
        fall.restart()
        if (emitCancel)
            cancelled()
    }

    function confirm() {
        clampToFuture()
        const unix = selectedUnix()
        close(false)
        picked({ "@type": "messageSchedulingStateSendAtDate", send_date: unix })
    }

    function pickFromWheels() {
        if (_syncing || !open)
            return
        dayIndex = dayCol.currentIndex
        hour = hourCol.currentIndex
        minute = minCol.currentIndex
        clampToFuture()
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close(true) }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.4; duration: 240 }

    Rectangle {
        id: panel
        width: parent.width
        height: 326 + (sheet.allowOnline ? 40 : 0) + safe.bottom
        radius: 16
        color: Theme.bg
        MouseArea { anchors.fill: parent }

        // Flat bottom extension so the sheet reaches the bottom edge cleanly under safe.bottom
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 20
            color: Theme.bg
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 7; width: 36; height: 4; radius: 2
            color: Theme.separator
        }

        Icon {
            x: 16; y: 20
            width: 22; height: 22
            name: "cross"
            color: Theme.grey
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: sheet.close(true) }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            text: sheet.reschedule ? Tr.t("Vaqtni o'zgartirish") : Tr.t("Xabarni rejalashtirish")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }

        Item {
            id: wheels
            x: 12; y: 58
            width: parent.width - 24
            height: sheet.rowH * 5
            clip: true

            Rectangle {
                x: 4; width: parent.width - 8; height: sheet.rowH
                anchors.verticalCenter: parent.verticalCenter
                radius: 8
                color: Theme.dark ? "#2c2c2e" : "#ececf0"
            }

            component WheelCol: ListView {
                id: wcol
                property var words: []
                property int align: Text.AlignHCenter
                height: wheels.height
                model: words.length
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: sheet.rowH * 2
                preferredHighlightEnd: sheet.rowH * 3
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 180
                onMovementEnded: sheet.pickFromWheels()
                onCurrentIndexChanged: if (!sheet._syncing && (moving || dragging || flicking)) sheet.pickFromWheels()
                delegate: Text {
                    required property int index
                    width: wcol.width; height: sheet.rowH
                    horizontalAlignment: wcol.align
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8; rightPadding: 8
                    text: wcol.words[index] || ""
                    readonly property real off: Math.abs(y - wcol.contentY - sheet.rowH * 2) / sheet.rowH
                    opacity: Math.max(0.25, 1 - off * 0.32)
                    color: off < 0.5 ? Theme.text : Theme.grey
                    font.family: Theme.font; font.pixelSize: 20
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            wcol.currentIndex = parent.index
                            sheet.pickFromWheels()
                        }
                    }
                }
            }

            Row {
                anchors.fill: parent
                WheelCol {
                    id: dayCol
                    width: wheels.width * 0.54
                    align: Text.AlignRight
                    words: sheet.dayLabels
                }
                WheelCol {
                    id: hourCol
                    width: wheels.width * 0.21
                    align: Text.AlignHCenter
                    words: Array.from({ length: 24 }, (_, i) => sheet.two(i))
                }
                Text {
                    width: wheels.width * 0.04
                    height: wheels.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ":"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
                }
                WheelCol {
                    id: minCol
                    width: wheels.width * 0.21
                    align: Text.AlignLeft
                    words: Array.from({ length: 60 }, (_, i) => sheet.two(i))
                }
            }
        }

        Rectangle {
            id: onlineBtn
            visible: sheet.allowOnline
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: confirmBtn.top; anchors.bottomMargin: 8
            width: parent.width - 32; height: 36; radius: 18
            color: onlineHit.pressed ? Theme.highlight : "transparent"
            Text {
                anchors.centerIn: parent
                text: Tr.t("Onlayn bo'lganda yuborish")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            MouseArea {
                id: onlineHit
                anchors.fill: parent
                onClicked: {
                    sheet.close(false)
                    sheet.picked({ "@type": "messageSchedulingStateSendWhenOnline" })
                }
            }
        }

        Rectangle {
            id: confirmBtn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + safe.bottom
            width: parent.width - 32; height: 50; radius: 25
            color: Theme.accent
            opacity: confirmHit.pressed ? 0.8 : 1
            Text {
                anchors.centerIn: parent
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: sheet.actionLabel
                color: "white"
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            MouseArea {
                id: confirmHit
                anchors.fill: parent
                onClicked: sheet.confirm()
            }
        }
    }

    YAnimator { id: rise; target: panel; duration: 280; easing.type: Easing.OutCubic }
    ParallelAnimation {
        id: fall
        YAnimator { id: fallY; target: panel; to: sheet.height; duration: 220; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 220 }
        onFinished: sheet.visible = false
    }
}
