// The sessions signed in to this account (getActiveSessions), as Telegram-iOS's RecentSessionsController:
// its Devices animation (RecentSessionsHeaderItem: 128 at −10, played once after 0.3 s), the words with
// Telegram Desktop and Web as links (14, at 124 + 8), «Qurilma qo'shish» (52 high, QR icon) — there is no
// camera to scan with yet, so it says that; «SHU QURILMA» with «Boshqa barcha seanslarni tugatish» (red, a
// hand), «TUGALLANMAGAN KIRISHLAR» (password pending), «FAOL SEANSLAR» by when last active, and when old
// ones end by themselves (7, 30, 90 or 180 days: setInactiveSessionTtl). A row as ItemListRecentSessionItem:
// the device's icon (iconForSession, 30 at 16/15), the device in semibold 17, the app and its version, the
// place • when in grey (15). «Tahrirlash»: a red ⊖ by each other session, tapped it shows «Tugatish» on the
// row's right. A tap on a session shows it (RecentSessionScreen): its icon at 92, the device, the app, the
// place, what it accepts (secret chats, calls), «Seansni tugatish». Each ending is asked first.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Qurilmalar")
    property var sessions: []
    property int ttl: 0                 // days an unused session lives
    property bool editing: false
    property string revealed: ""        // the session showing «Tugatish» (its id)
    property string ending: ""          // the session being ended, faint meanwhile ("*": all the others)
    property int now: Date.now() / 1000
    readonly property var current: sessions.filter((s) => s.is_current)
    readonly property var pending: sessions.filter((s) => !s.is_current && s.is_password_pending)
    readonly property var others: sessions.filter((s) => !s.is_current && !s.is_password_pending)
                                          .sort((a, b) => b.last_active_date - a.last_active_date)
    action: others.length || pending.length ? (editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")) : ""
    actionBold: editing
    onActed: { editing = !editing; revealed = "" }

    function load() {
        store.send({ "@type": "getActiveSessions" }, (r) => {
            if (!page || !r.sessions)
                return
            page.sessions = r.sessions
            page.ttl = r.inactive_session_ttl_days
            page.now = Date.now() / 1000
            if (page.shown)
                page.shown = r.sessions.find((s) => s.id === page.shown.id) || null
        })
    }
    Component.onCompleted: load()
    Timer { interval: 60000; repeat: true; running: true; onTriggered: page.now = Date.now() / 1000 }

    // iconForSession: by the device's, platform's and system's names, as Telegram-iOS reads them (TDLib's sessionType is
    // not in every TDLib): the picture's name and its colour (under the big one, RecentSessionScreen)
    function kind(s) {
        const p = (s.platform || "").toLowerCase(), d = (s.device_model || "").toLowerCase(), v = (s.system_version || "").toLowerCase()
        const blue = "#0079ff", green = "#35c759", orange = "#ff9500", red = "#ff3c30", grey = "#8e8e93"
        if (d.includes("xbox")) return ["xbox", green]
        if (d.includes("chrome") && !d.includes("chromebook")) return ["chrome", green]
        if (d.includes("brave")) return ["brave", orange]
        if (d.includes("vivaldi")) return ["vivaldi", red]
        if (d.includes("safari")) return ["safari", blue]
        if (d.includes("firefox")) return ["firefox", orange]
        if (d.includes("opera")) return ["opera", red]
        if (p.includes("android")) return ["android", green]
        if (d.includes("iphone")) return ["iphone", blue]
        if (d.includes("ipad")) return ["ipad", blue]
        if ((p.includes("macos") || v.includes("macos")) && d.includes("mac")) return ["mac", blue]
        if (p.includes("ios") || p.includes("macos") || v.includes("macos")) return ["ios", blue]
        if (p.includes("ubuntu") || v.includes("ubuntu")) return ["ubuntu", orange]
        if (p.includes("linux") || v.includes("linux")) return ["linux", grey]
        if (p.includes("windows") || v.includes("windows")) return ["windows", blue]
        return ["generic", grey]
    }
    function icon(s) {
        return "settings-icons/device-" + kind(s)[0] + ".png"
    }
    function tint(s) {
        return kind(s)[1]
    }
    // the app and its version, without the store's words and the build in brackets
    function app(s) {
        const v = (s.application_version || "").replace("APPSTORE", "").replace("BETA", "Beta").replace(/ \(.*\)/, "").trim()
        return (s.application_name + " " + v).trim()
    }
    // stringForRelativeActivityTimestamp
    function ago(unix) {
        const d = now - unix
        if (d < 60)
            return Tr.t("hozirgina")
        if (d < 3600)
            return Tr.n("%1 daqiqa oldin", Math.floor(d / 60))
        const t = new Date(unix * 1000), today = new Date(now * 1000)
        if (t.toDateString() === today.toDateString())
            return Tr.f("bugun %1 da", Qt.formatTime(t, "HH:mm"))
        if (t.toDateString() === new Date(now * 1000 - 86400000).toDateString())
            return Tr.f("kecha %1 da", Qt.formatTime(t, "HH:mm"))
        return Qt.formatDate(t, "dd.MM.yy")
    }
    function when(s) {
        return s.is_current ? Tr.t("onlayn") : ago(s.last_active_date)
    }
    function days(n) {
        return n >= 365 ? Tr.n("%1 yil", Math.round(n / 365)) : n >= 30 ? Tr.n("%1 oy", Math.round(n / 30))
             : n % 7 === 0 ? Tr.n("%1 hafta", n / 7) : Tr.n("%1 kun", n)
    }

    function askEnd(s) {
        alert.show(Tr.t("Bu seansni tugatasizmi?"), Tr.t("Seansni tugatish"), () => page.end(s))
    }
    function end(s) {
        ending = s.id
        sheet.open = false
        store.send({ "@type": "terminateSession", session_id: s.id }, (r) => {
            if (!page)
                return
            page.ending = ""
            if (r["@type"] === "error")
                return page.say(r.message)
            page.revealed = ""
            page.sessions = page.sessions.filter((x) => x.id !== s.id)
            if (!page.others.length && !page.pending.length)
                page.editing = false
        })
    }
    function askEndOthers() {
        alert.show(Tr.t("Boshqa barcha seanslarni tugatasizmi?"), Tr.t("Boshqa barcha seanslarni tugatish"), () => page.endOthers())
    }
    function endOthers() {
        ending = "*"
        store.send({ "@type": "terminateAllOtherSessions" }, (r) => {
            if (!page)
                return
            page.ending = ""
            if (r["@type"] === "error")
                return page.say(r.message)
            page.editing = false
            page.load()
        })
    }
    function setTtl(n) {
        ttl = n
        store.send({ "@type": "setInactiveSessionTtl", inactive_session_ttl_days: n }, store.check)
    }
    function accept(s, calls, on) {
        const req = calls ? { "@type": "toggleSessionCanAcceptCalls", session_id: s.id, can_accept_calls: on }
                          : { "@type": "toggleSessionCanAcceptSecretChats", session_id: s.id, can_accept_secret_chats: on }
        s[calls ? "can_accept_calls" : "can_accept_secret_chats"] = on
        shown = Object.assign({}, s)
        store.send(req, store.check)
    }
    function say(text) {
        note.text = text
        noteBox.opacity = 1
        noteAway.restart()
    }
    // the shell's back: what is over the page closes first
    function dismiss() {
        if (alert.open)
            alert.open = false
        else if (menu.open)
            menu.open = false
        else if (sheet.open)
            sheet.open = false
        else if (editing) {
            editing = false
            revealed = ""
        } else
            return false
        return true
    }

    // ---- the head ----
    Item {
        width: parent.width
        height: 124 - 16 + intro.height + 69       // (RecentSessionsHeaderItem; the list starts 16 down)
        Lottie {
            id: devicesAnim
            anchors.horizontalCenter: parent.horizontalCenter
            y: -10 - 16
            width: 128; height: 128
            path: Qt.resolvedUrl("animations/Devices.tgs").toString().replace(/^file:\/\//, "")
            once: true
            running: false
            Timer { interval: 300; running: true; onTriggered: devicesAnim.running = true }
        }
        Text {
            id: intro
            x: 32; y: 124 + 8 - 16
            width: parent.width - 64
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.RichText      // (StyledText underlines a link; iOS does not)
            text: "<style>a { color: " + Theme.accent + "; text-decoration: none }</style>"
                  + Tr.f("%1 yoki %2 ilovasiga QR kodni skanerlab kiring.", "<a href='https://desktop.telegram.org'>Telegram Desktop</a>",
                         "<a href='https://web.telegram.org'>Telegram Web</a>")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 14
            onLinkActivated: (url) => Qt.openUrlExternally(url)
        }
        Rectangle {         // «Qurilma qo'shish» (AuthSessions.LinkDesktopDevice): no camera to scan with yet
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: -4
            width: Math.min(375, parent.width - 32); height: 52
            radius: 26
            color: Theme.accent
            opacity: addHit.pressed ? 0.8 : 1
            Row {
                anchors.centerIn: parent
                spacing: 6
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "qr"; color: "white" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Qurilma qo'shish")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
            }
            MouseArea {
                id: addHit
                anchors.fill: parent
                onClicked: page.say(Tr.t("QR kodni skanerlash uchun kamera kerak — telefonning kamerasi hali ulanmagan"))
            }
        }
    }

    // ---- this one, and the others' end ----
    SettingsGroup {
        visible: page.current.length > 0
        title: Tr.t("Shu qurilma")
        note: page.others.length || page.pending.length ? Tr.t("Bu qurilmadan boshqa barcha qurilmalardan chiqadi.") : ""
        Repeater {
            model: page.current
            SessionRow { last: !page.others.length && !page.pending.length }
        }
        Item {
            visible: page.others.length > 0 || page.pending.length > 0
            width: parent.width; height: 46
            opacity: page.ending === "*" ? 0.5 : 1
            Rectangle { anchors.fill: parent; color: Theme.highlight; visible: endAllHit.pressed }
            Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; name: "hand"; color: Theme.danger }
            Text {
                x: 59; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 16
                elide: Text.ElideRight
                text: Tr.t("Boshqa barcha seanslarni tugatish")
                color: Theme.danger
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { id: endAllHit; anchors.fill: parent; enabled: page.ending === ""; onClicked: page.askEndOthers() }
        }
    }

    SettingsGroup {
        visible: page.pending.length > 0
        title: Tr.t("Tugallanmagan kirishlar")
        note: Tr.t("Bu qurilmalar hisobingizga kira olmaydi. Kod to'g'ri kiritilgan, lekin parol to'g'ri kiritilmagan.")
        Repeater {
            model: page.pending
            SessionRow { last: index === page.pending.length - 1 }
        }
    }

    SettingsGroup {
        visible: page.others.length > 0
        title: Tr.t("Faol seanslar")
        Repeater {
            model: page.others
            SessionRow { last: index === page.others.length - 1 }
        }
    }

    SettingsGroup {
        visible: page.ttl > 0
        title: Tr.t("Eski seanslarni avtomatik tugatish")
        SettingsRow {
            id: ttlRow
            text: Tr.t("Faol bo'lmasa")
            value: page.days(page.ttl)
            last: true
            onClicked: menu.show(ttlRow)
        }
    }

    // ---- a session's row ----
    component SessionRow: Item {
        id: srow
        required property var modelData
        required property int index
        property bool last: false
        readonly property bool editable: !modelData.is_current
        readonly property real shift: page.editing && editable ? 38 : 0         // the ⊖'s room (editableControlLayout)
        readonly property real slide: page.revealed === modelData.id ? -endBtn.width : 0
        width: parent ? parent.width : 300
        height: place.y + place.height + 9
        clip: true
        opacity: page.ending === modelData.id || (page.ending === "*" && editable) ? 0.5 : 1
        Rectangle { anchors.fill: parent; color: Theme.highlight; visible: rowHit.pressed }
        MouseArea {
            id: rowHit
            anchors.fill: parent
            onClicked: {
                if (page.revealed !== "")
                    page.revealed = ""
                else if (!page.editing)
                    sheet.show(srow.modelData)
            }
        }
        Item {
            x: srow.shift + srow.slide
            width: parent.width; height: parent.height
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Image {
                x: 16; y: 15
                width: 30; height: 30
                source: page.icon(srow.modelData)
                sourceSize: Qt.size(120, 120)
                smooth: true; mipmap: true
            }
            Text {
                id: dev
                x: 59; y: 9
                width: parent.width - x - 16 - srow.shift
                elide: Text.ElideRight
                text: srow.modelData.device_model || srow.modelData.platform || srow.modelData.application_name
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                id: appName
                x: 59; y: dev.y + dev.height + 1
                width: dev.width
                elide: Text.ElideRight
                text: page.app(srow.modelData)
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
            Text {
                id: place
                x: 59; y: appName.y + appName.height + 2
                width: dev.width
                elide: Text.ElideRight
                text: [srow.modelData.location, page.when(srow.modelData)].filter((t) => t).join(" • ")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 15
            }
        }
        Rectangle {         // ⊖: the row's «Tugatish» shown
            x: 12 + srow.slide + (page.editing && srow.editable ? 0 : -40)     // (with the row when «Tugatish» shows)
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 11
            color: Theme.danger
            opacity: page.editing && srow.editable ? 1 : 0
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Behavior on opacity { NumberAnimation { duration: 250 } }
            Rectangle { anchors.centerIn: parent; width: 11; height: 2; radius: 1; color: "white" }
            MouseArea {
                anchors.fill: parent; anchors.margins: -10
                enabled: page.editing && srow.editable
                onClicked: page.revealed = page.revealed === srow.modelData.id ? "" : srow.modelData.id
            }
        }
        Rectangle {         // «Tugatish» (ItemListRevealOption, destructive)
            id: endBtn
            x: parent.width + srow.slide
            width: endText.implicitWidth + 32; height: parent.height
            color: Theme.danger
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Text {
                id: endText
                anchors.centerIn: parent
                text: Tr.t("Tugatish")
                color: "white"
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { anchors.fill: parent; onClicked: page.askEnd(srow.modelData) }
        }
        Rectangle {
            visible: !srow.last
            x: 59 + srow.shift; anchors.bottom: parent.bottom
            width: parent.width - x - 16; height: 0.5
            color: Theme.separator
        }
    }

    // ---- over the page: a session shown, the asking, the days' menu, a note ----
    Item {
        id: sheet           // RecentSessionScreen: a sheet from the foot
        parent: page
        anchors.fill: parent
        z: 30
        property bool open: false
        property var s: page.shown
        function show(s) {
            page.shown = s
            open = true
        }
        visible: sheetDim.opacity > 0
        Rectangle {
            id: sheetDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: sheet.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
        }
        Rectangle {
            id: card
            width: parent.width
            height: body.y + body.height + (sheet.s && !sheet.s.is_current ? 16 + 52 + 30 : 30)
            y: sheet.open ? parent.height - height : parent.height + 20
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301, 0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0] } }
            radius: 38
            color: Theme.grouped
            MouseArea { anchors.fill: parent }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 38; color: parent.color }
            Glass {         // ✕
                x: 16; y: 16
                width: 44; height: 44
                opacity: closeHit.pressed ? 0.7 : 1
                Icon { anchors.centerIn: parent; name: "cross"; color: Theme.text }
                MouseArea { id: closeHit; anchors.fill: parent; onClicked: sheet.open = false }
            }
            Column {
                id: body
                y: 32
                width: parent.width
                Rectangle {         // the device's colour, its picture on it (corners 20)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 92; height: 92; radius: 20
                    color: sheet.s ? page.tint(sheet.s) : "transparent"
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: sheet.s ? page.icon(sheet.s) : ""
                        sourceSize: Qt.size(368, 368)
                        smooth: true; mipmap: true
                    }
                }
                Item { width: 1; height: 16 }
                Text {
                    x: 46; width: parent.width - 92
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    horizontalAlignment: Text.AlignHCenter
                    text: sheet.s ? sheet.s.device_model || sheet.s.application_name : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold
                }
                Item { width: 1; height: 2 }
                Text {
                    x: 46; width: parent.width - 92
                    horizontalAlignment: Text.AlignHCenter
                    text: sheet.s ? page.when(sheet.s) : ""
                    color: sheet.s && sheet.s.is_current ? Theme.accent : Theme.grey
                    font.family: Theme.font; font.pixelSize: 15
                }
                Item { width: 1; height: 22 }
                SettingsGroup {
                    note: Tr.t("Bu joylashuv IP manzil bo'yicha taxmin qilingan va har doim ham aniq bo'lmasligi mumkin.")
                    Repeater {
                        model: sheet.s ? [[Tr.t("Ilova"), page.app(sheet.s)], [Tr.t("Joylashuv"), sheet.s.location]]
                                         .filter((r) => r[1]) : []
                        Item {
                            required property var modelData
                            required property int index
                            width: parent.width; height: 46
                            Text {
                                x: 16; anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData[0]
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 17
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, parent.width - 140)
                                elide: Text.ElideRight
                                text: parent.modelData[1]
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 17
                            }
                            Rectangle {
                                visible: parent.index === 0
                                x: 16; anchors.bottom: parent.bottom
                                width: parent.width - 32; height: 0.5
                                color: Theme.separator
                            }
                        }
                    }
                }
                Item { width: 1; height: 22; visible: accepts.visible }
                SettingsGroup {
                    id: accepts
                    visible: !!sheet.s && !sheet.s.is_current && !sheet.s.is_password_pending
                    title: Tr.t("Bu qurilmada qabul qilish")
                    SettingsRow {
                        text: Tr.t("Yangi maxfiy chatlar")
                        toggle: true
                        on: !!sheet.s && sheet.s.can_accept_secret_chats
                        onClicked: page.accept(sheet.s, false, !on)
                    }
                    SettingsRow {
                        text: Tr.t("Kiruvchi qo'ng'iroqlar")
                        toggle: true
                        last: true
                        on: !!sheet.s && sheet.s.can_accept_calls
                        onClicked: page.accept(sheet.s, true, !on)
                    }
                }
            }
            Rectangle {     // «Seansni tugatish» (itemDestructiveColor, white)
                visible: !!sheet.s && !sheet.s.is_current
                x: 30; width: parent.width - 60; height: 52
                y: body.y + body.height + 16
                radius: 26
                color: Theme.danger
                opacity: endHit.pressed ? 0.8 : 1
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Seansni tugatish")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea { id: endHit; anchors.fill: parent; onClicked: page.askEnd(sheet.s) }
            }
        }
    }
    property var shown: null            // the session the sheet shows

    Item {
        id: alert           // textAlertController: the question, the red answer, «Bekor qilish» (vertical)
        parent: page
        anchors.fill: parent
        z: 40
        property bool open: false
        property string text: ""
        property string act: ""
        property var run: null
        function show(t, a, r) {
            text = t; act = a; run = r
            open = true
        }
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.4) }
        MouseArea { anchors.fill: parent; onClicked: alert.open = false }
        Rectangle {
            anchors.centerIn: parent
            scale: alert.open ? 1 : 1.1
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            width: 280; height: alertText.height + 36 + 2 * 46
            radius: 14
            color: Theme.menu
            MouseArea { anchors.fill: parent }
            Text {
                id: alertText
                x: 16; y: 20; width: parent.width - 32
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                text: alert.text
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
            }
            Repeater {
                model: [{ t: alert.act, go: true }, { t: Tr.t("Bekor qilish"), go: false }]
                Rectangle {
                    required property var modelData
                    required property int index
                    y: alertText.y + alertText.height + 16 + index * 46
                    width: parent.width; height: 46
                    color: alertHit.pressed ? Theme.highlight : "transparent"
                    radius: index === 1 ? 14 : 0
                    Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        horizontalAlignment: Text.AlignHCenter
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: 13      // (as UIKit's alert shrinks a long one)
                        text: parent.modelData.t
                        color: parent.modelData.go ? Theme.danger : Theme.accent
                        font.family: Theme.font; font.pixelSize: 17
                        font.weight: parent.modelData.go ? Font.Normal : Font.DemiBold
                    }
                    MouseArea {
                        id: alertHit
                        anchors.fill: parent
                        onClicked: {
                            alert.open = false
                            if (parent.modelData.go && alert.run)
                                alert.run()
                        }
                    }
                }
            }
        }
    }

    Item {
        id: menu            // the days, as iOS's context menu by the row's value, ✓ by the one set
        parent: page
        anchors.fill: parent
        z: 35
        property bool open: false
        property real at: 0
        function show(row) {
            at = row.mapToItem(page, 0, row.height).y + 6
            open = true
        }
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea { anchors.fill: parent; onClicked: menu.open = false }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 16
            y: Math.min(menu.at, page.height - height - 16)
            width: 220; height: 4 * 44
            radius: 14
            color: Theme.menu
            border.color: Theme.separator; border.width: 0.5
            scale: menu.open ? 1 : 0.8
            transformOrigin: Item.TopRight
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
            Repeater {
                model: [7, 30, 90, 180]
                Rectangle {
                    required property int modelData
                    required property int index
                    y: index * 44
                    width: parent.width; height: 44
                    radius: index === 0 || index === 3 ? 14 : 0
                    color: dayHit.pressed ? Theme.highlight : "transparent"
                    Rectangle { visible: parent.index > 0; width: parent.width; height: 0.5; color: Theme.separator }
                    Text {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        text: page.days(parent.modelData)
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Text {
                        visible: page.ttl === parent.modelData
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: dayHit
                        anchors.fill: parent
                        onClicked: {
                            menu.open = false
                            page.setTtl(parent.modelData)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: noteBox
        parent: page
        z: 45
        x: 12; width: page.width - 24
        y: page.height - height - 24
        height: note.height + 24
        radius: 14
        color: Qt.rgba(0, 0, 0, 0.85)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: note
            x: 16; y: 12; width: parent.width - 32
            wrapMode: Text.Wrap
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
        Timer { id: noteAway; interval: 3000; onTriggered: noteBox.opacity = 0 }
    }
}
