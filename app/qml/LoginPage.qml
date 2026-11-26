// Signing in: the QR code to scan from a phone already signed in (Settings → Devices →
// Link Desktop Device), or the number, its code and the cloud password.
//
// As Telegram-iOS (AuthorizationUI): every step a page of its own that slides in (a navigation push,
// 0.5 s on the spring; back the other way), on top its animation (100 pt, the Intro*.tgs of
// Telegram-iOS's Resources, GPL-2.0 as it is), a big title (semibold 28) and under it what to do
// (17), all centred. A code is typed into cells (CodeInputView: 51 pt high, 15 apart, one a digit,
// the next one's rim lit) and goes by itself once they are full; a wrong one turns them red and
// shakes them (addShakeAnimation: 30 pt, 6 times, dying away, 0.5 s), and they empty after 0.85 s.
import QtQuick

Page {
    id: page
    // (TDLib takes a number again in any later step: «Raqamni o'zgartirish» -- again)
    readonly property string step: again ? "phone"
                                  : store.auth === "WaitCode" ? "code"
                                  : store.auth === "WaitPassword" ? "password"
                                  : store.auth === "WaitEmailAddress" ? "email"
                                  : store.auth === "WaitEmailCode" ? "emailcode"
                                  : store.auth === "WaitRegistration" ? "name"
                                  : store.byPhone ? "phone" : "qr"
    property bool again: false
    property Item stage: null           // the step on the screen
    property Item leaving: null         // the one sliding away
    readonly property Item field: stage ? stage.field : null
    readonly property Item last: stage ? stage.last : null
    readonly property var order: ["qr", "phone", "code", "password", "email", "emailcode", "name"]
    readonly property var spring: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301,
                                   0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]

    Text {                  // a new account's sign-in (0.9.7): back to the one it was added from
        z: 5
        visible: accounts.adding
        x: 16; y: 14
        text: "‹ " + Tr.t("Bekor qilish")
        color: Theme.accent
        font.family: Theme.font; font.pixelSize: 17
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: accounts.cancelAdd(0) }
    }

    onStepChanged: show(true)
    Component.onCompleted: show(false)

    function show(moving) {
        if (stage && stage.step === step)
            return
        if (slide.running)
            slide.complete()
        const old = stage
        const back = old && order.indexOf(step) < order.indexOf(old.step)
        stage = stageMaker.createObject(page, { step: step, x: moving && old ? (back ? -0.3 * width : width) : 0,
                                                 z: back ? 0 : 2 })
        if (step !== "qr")
            stage.field.forceActiveFocus()
        else {                          // (nothing to type: the keyboard goes, the old field let go)
            stage.forceActiveFocus()
            osk.hide()
        }
        if (!moving || !old)
            return
        if (old) {
            old.z = 1
            leaving = old
            toNew.to = 0
            toOld.to = back ? width : -0.3 * width
            slide.start()
        }
    }

    ParallelAnimation {
        id: slide
        XAnimator { id: toNew; target: page.stage; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: page.spring }
        XAnimator { id: toOld; target: page.leaving; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: page.spring }
        onFinished: {
            if (page.leaving)
                page.leaving.destroy()
            page.leaving = null
        }
    }

    // a wrong number, code, password...: the step on the screen shakes (and a code's cells go red)
    Connections {
        target: store
        function onErrorChanged() { if (store.error && page.stage) page.stage.fail() }
    }

    // Telegram's error, as Telegram-iOS words it (AuthorizationSequenceController); others as they come
    function said(e) {
        const w = { PHONE_NUMBER_INVALID: "Raqam noto'g'ri. Qaytadan tekshiring.",
                    PHONE_NUMBER_BANNED: "Bu raqam Telegram'da bloklangan.",
                    PHONE_CODE_INVALID: "Kod noto'g'ri. Qaytadan urinib ko'ring.",
                    PHONE_CODE_EMPTY: "Kod noto'g'ri. Qaytadan urinib ko'ring.",
                    PHONE_CODE_EXPIRED: "Kodning muddati o'tdi. Qaytadan kiring.",
                    PASSWORD_HASH_INVALID: "Parol noto'g'ri.",
                    EMAIL_INVALID: "E-pochta manzili noto'g'ri.",
                    EMAIL_CODE_INVALID: "Kod noto'g'ri. Qaytadan urinib ko'ring.",
                    FIRSTNAME_INVALID: "Ism noto'g'ri." }[e]
        if (w)
            return Tr.t(w)
        if (/^Too Many Requests|FLOOD_WAIT/.test(e))
            return Tr.t("Juda ko'p urinish. Birozdan keyin qayta urinib ko'ring.")
        return e
    }

    // where the code went (Telegram-iOS AuthorizationSequenceCodeEntryController's wording)
    function codeWhere() {
        const i = store.authState.code_info
        const t = i && i.type ? i.type["@type"] : ""
        const number = "<b>+" + ((i && i.phone_number) || "").replace(/^\+/, "") + "</b>"
        if (t === "authenticationCodeTypeTelegramMessage")
            return Tr.t("Kodni boshqa qurilmangizdagi Telegram'ga yubordik")
        if (t === "authenticationCodeTypeSms" || t === "authenticationCodeTypeSmsWord" || t === "authenticationCodeTypeSmsPhrase")
            return Tr.f("Kodni SMS bilan %1 raqamiga yubordik", number)
        if (t === "authenticationCodeTypeCall")
            return Tr.f("%1 raqamiga qo'ng'iroq qilib kodni aytamiz", number)
        if (t === "authenticationCodeTypeFragment")
            return Tr.t("Kodni Fragment'dagi raqamingizga yubordik")
        return Tr.t("Telegram yuborgan kod")
    }
    function animation(s) {             // the step's Intro*.tgs, as a file's path
        const t = ((store.authState.code_info || {}).type || {})["@type"]
        const name = s === "code" ? (t === "authenticationCodeTypeFragment" ? "IntroFragment" : "IntroMessage")
                   : { phone: "IntroPhone", password: "IntroPassword", email: "IntroMail",
                       emailcode: "IntroLetter", name: "IntroPhone" }[s]
        return Qt.resolvedUrl("intro/" + name + ".tgs").toString().replace(/^file:\/\//, "")
    }
    function codeLength(s) {            // how many cells (TDLib says; Telegram's are 5, an e-mail's 6)
        const i = store.authState.code_info
        const n = s === "emailcode" ? (i && i.length) : (i && i.type && i.type.length)
        return n > 0 && n <= 8 ? n : s === "emailcode" ? 6 : 5
    }

    Component {
        id: stageMaker
        Rectangle {
            id: st
            required property string step
            readonly property bool code: step === "code" || step === "emailcode"
            readonly property int count: code ? page.codeLength(step) : 0
            property alias field: field
            property alias last: last
            property bool failed: false         // the cells red, until they empty
            property bool sent: false           // a full code gone, its answer awaited
            property real shakeAt: 0            // 0..1 through the shake
            property real amplitude: 3
            property int shakes: 4
            property bool dying: false
            width: page.width
            height: page.height
            color: Theme.bg

            function fail() {
                sent = false
                if (code) {
                    failed = true
                    amplitude = -30; shakes = 6; dying = true; shake.duration = 500
                    empty.restart()
                } else {
                    amplitude = 3; shakes = 4; dying = false; shake.duration = 300
                }
                shake.restart()
            }
            // CALayer.addShakeAnimation: 0, a, -a(/2), a(/3)... 0 at even steps, straight between them
            function shaken(t) {
                const n = shakes + 2, at = t * (n - 1), i = Math.floor(at)
                const v = (k) => k <= 0 || k >= n - 1 ? 0 : amplitude * (k % 2 ? 1 : -1) / (dying ? k : 1)
                return i >= n - 1 ? 0 : v(i) + (v(i + 1) - v(i)) * (at - i)
            }
            NumberAnimation { id: shake; target: st; property: "shakeAt"; from: 0; to: 1 }
            Timer {
                id: empty
                interval: 850
                onTriggered: { st.failed = false; field.text = "" }
            }

            Column {
                id: col
                x: 24
                width: parent.width - 48
                spacing: 0
                // up over the keyboard, as far as it takes (not past the top)
                y: Math.max(12, Math.min(st.step === "qr" ? 56 : 70, st.height - osk.h - height - 16))
                Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Lottie {            // the step's animation
                    visible: st.step !== "qr"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 100; height: visible ? 100 : 0
                    path: visible ? page.animation(st.step) : ""
                    once: true
                    // the password's lock waits on its first frame until the field is typed in (iOS: .still(.start))
                    running: st.step !== "password" || field.activeFocus
                }

                Rectangle {         // the QR code: black modules on a white card (Telegram Desktop's QR sign-in)
                    visible: st.step === "qr"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 208; height: visible ? 208 : 0
                    color: "white"
                    radius: 20
                    border.color: Theme.separator; border.width: Theme.dark ? 0 : 1
                    property var rows: store.qrLink ? td.qr(store.qrLink) : []
                    Grid {
                        id: modules
                        anchors.centerIn: parent
                        property real cell: parent.rows.length ? Math.floor(184 / parent.rows.length * 4) / 4 : 0
                        columns: parent.rows.length
                        Repeater {
                            model: parent.parent.rows.length * parent.parent.rows.length
                            Rectangle {
                                required property int index
                                readonly property var rows: modules.parent.rows
                                width: modules.cell; height: modules.cell
                                color: rows[Math.floor(index / rows.length)].charAt(index % rows.length) === "1" ? "black" : "white"
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !store.qrLink
                        text: Tr.t("kod tayyorlanmoqda...")
                        color: "#666666"
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }

                Item { width: 1; height: 18 }
                Text {              // the title
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 28; font.weight: Font.DemiBold
                    text: ({ qr: Tr.t("QR kod bilan kirish"), phone: Tr.t("Telefon raqamingiz"),
                             code: Tr.t("Kodni kiriting"), emailcode: Tr.t("E-pochtangizni tekshiring"),
                             password: Tr.t("Parolingiz"), email: Tr.t("E-pochta qo'shing"),
                             name: Tr.t("Ma'lumotlaringiz") })[st.step]
                }
                Item { width: 1; height: 10 }
                Text {              // what to do
                    visible: st.step !== "qr"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17
                    text: st.step === "qr" ? Tr.t("Boshqa telefoningizda Telegram → Sozlamalar → Qurilmalar → «Qurilma ulash», va shu kodni skanerlang.")
                        : st.step === "phone" ? Tr.t("Mamlakat kodini tekshirib, telefon raqamingizni kiriting.")
                        : st.step === "code" ? page.codeWhere()
                        : st.step === "email" ? Tr.t("Hisobingizga kirish yo'qolmasligi uchun e-pochta manzilingizni qo'shing.")
                        : st.step === "emailcode" ? Tr.f("Kodni %1 manziliga yubordik",
                                                         "<b>" + ((store.authState.code_info || {}).email_address_pattern || "") + "</b>")
                        : st.step === "name" ? Tr.t("Ismingiz va familiyangiz (familiya ixtiyoriy)")
                        : Tr.t("Hisobingiz ikki bosqichli tasdiqlash bilan himoyalangan: qo'shimcha parol kerak.")
                }

                Column {            // the QR's steps, numbered (Telegram Desktop: open, Settings › Devices, point)
                    visible: st.step === "qr"
                    x: 8; width: parent.width - 16
                    topPadding: 8
                    spacing: 14
                    Repeater {
                        model: st.step === "qr" ? [Tr.t("Telefonda Telegram'ni oching"),
                                                   Tr.t("Sozlamalar → Qurilmalar → «Qurilma ulash»"),
                                                   Tr.t("Telefonni shu kodga qarating")] : []
                        Row {
                            required property int index
                            required property string modelData
                            spacing: 14
                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: String(parent.parent.index + 1)
                                    color: "white"
                                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                                }
                            }
                            Text {
                                width: col.width - 16 - 40
                                anchors.verticalCenter: parent.children[0].verticalCenter
                                wrapMode: Text.Wrap
                                text: parent.modelData
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 17
                            }
                        }
                    }
                }
                Item { width: 1; height: st.step === "qr" ? 18 : st.code ? 30 : 26 }
                Item {              // the field: a number, a password...; or a code's cells over it
                    id: box
                    visible: st.step !== "qr"
                    width: parent.width
                    height: !visible ? 0 : st.code ? cells.h : 48
                    transform: Translate { x: st.shaken(st.shakeAt) }

                    Rectangle {
                        anchors.fill: parent
                        visible: !st.code
                        radius: 12
                        color: Theme.field
                        border.color: Theme.fieldBorder; border.width: 1
                    }
                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        opacity: st.code ? 0 : 1        // (a code: typed here, shown in the cells)
                        cursorVisible: !st.code && activeFocus
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 18
                        maximumLength: st.code ? st.count : 32767
                        echoMode: st.step === "password" ? TextInput.Password : TextInput.Normal
                        inputMethodHints: st.step === "password" || st.step === "name" ? Qt.ImhNone
                                        : st.step === "email" ? Qt.ImhEmailCharactersOnly
                                        : st.code ? Qt.ImhDigitsOnly
                                        : Qt.ImhDialableCharactersOnly
                        onAccepted: st.step === "name" ? last.forceActiveFocus() : page.next()
                        onTextChanged: {
                            if (st.code && !st.failed && text.length === st.count && !st.sent)
                                page.next()     // (a full code goes by itself)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !field.text && !st.code
                            text: st.step === "name" ? Tr.t("Ism")
                                : st.step === "phone" ? "+998 ..."
                                : st.step === "email" ? Tr.t("E-pochta")
                                : store.passwordHint || Tr.t("Parol")
                            color: Theme.grey
                            font: field.font
                        }
                    }
                    Row {               // a code's cells
                        id: cells
                        visible: st.code
                        readonly property real h: st.count > 5 && page.width <= 375 ? 44 : 51
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 15
                        Repeater {
                            model: st.count
                            Rectangle {
                                required property int index
                                width: Math.floor(24 * cells.h / 28); height: cells.h
                                radius: 15
                                color: "transparent"
                                border.width: 1.5
                                border.color: st.failed ? Theme.danger
                                            : field.activeFocus && index === Math.min(field.text.length, st.count - 1) ? Theme.accent
                                            : Theme.separator
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Text {
                                    id: digit
                                    anchors.centerIn: parent
                                    text: field.text.charAt(parent.index)
                                    color: Theme.text
                                    font.family: "monospace"; font.pixelSize: Math.floor(13 * cells.h / 28)
                                    // (a digit comes up from below, as on iOS)
                                    onTextChanged: if (text) { rise.restart() }
                                    NumberAnimation { id: rise; target: digit; property: "anchors.verticalCenterOffset"
                                                      from: cells.h * 0.35; to: 0; duration: 250; easing.type: Easing.OutBack }
                                }
                            }
                        }
                    }
                    MouseArea {         // a tap on the cells: the keyboard
                        anchors.fill: parent
                        enabled: st.code
                        onClicked: { field.forceActiveFocus(); Qt.inputMethod.show() }
                    }
                }

                Item { width: 1; height: st.step === "name" ? 12 : 0 }
                Rectangle {         // a new account's last name
                    visible: st.step === "name"
                    width: parent.width; height: visible ? 48 : 0
                    radius: 12
                    color: Theme.field
                    border.color: Theme.fieldBorder; border.width: 1
                    TextInput {
                        id: last
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 18
                        onAccepted: page.next()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !last.text
                            text: Tr.t("Familiya")
                            color: Theme.grey
                            font: last.font
                        }
                    }
                }

                Item { width: 1; height: error.visible ? 11 : 0 }
                Text {              // Telegram's error, red under the field
                    id: error
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: store.error !== "" && page.stage === st
                    text: visible ? page.said(store.error) : ""
                    color: Theme.danger
                    font.family: Theme.font; font.pixelSize: 14
                }

                Item {              // a new account (0.9.7): its contacts to be synced or not (Telegram-iOS's ContactSyncNode)
                    visible: accounts.adding && (st.step === "phone" || st.step === "qr")
                    width: parent.width; height: visible ? 52 : 0
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 70
                        elide: Text.ElideRight
                        text: Tr.t("Kontaktlarni sinxronlash")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Switch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        on: accounts.sync
                    }
                    MouseArea {     // (the Switch only draws: the whole row is what is tapped, as SettingsRow)
                        anchors.fill: parent
                        onClicked: accounts.setSync(!accounts.sync)
                    }
                }
                Item { width: 1; height: st.step === "qr" || st.code ? 0 : 18 }
                Rectangle {
                    visible: st.step !== "qr" && !st.code
                    width: parent.width; height: visible ? 50 : 0
                    radius: 12
                    color: Theme.accent
                    Text { anchors.centerIn: parent; text: Tr.t("Davom etish"); color: "white"; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: page.next() }
                }

                Item { width: 1; height: st.code ? 40 : 24 }
                Text {              // the other way in, or back to the number
                    id: other
                    readonly property bool later: st.step !== "qr" && st.step !== "phone"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: st.step === "qr" ? Tr.t("Raqam bilan kirish")
                        : st.step === "phone" ? (page.again ? Tr.t("Bekor qilish") : Tr.t("QR kod bilan kirish"))
                        : Tr.t("Raqamni o'zgartirish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 17
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -10
                        onClicked: page.other()
                    }
                }

                Item { width: 1; height: st.step === "name" ? 18 : 0 }
                Text {              // a new account: Telegram's terms (TDLib gives them with WaitRegistration)
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: st.step === "name"
                    text: Tr.t("«Davom etish» bilan Telegram xizmat shartlariga rozilik bildirasiz.")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
        }
    }

    function other() {
        const later = step !== "qr" && step !== "phone"
        store.error = ""
        if (later)
            again = true
        else if (again)
            again = false
        else
            store.signInBy(!store.byPhone)
    }

    function next() {
        const st = stage
        const v = st.field.text.trim()
        if (!v || st.sent)
            return
        store.error = ""            // (the same error again is a change too: it shakes again)
        if (step === "phone") {
            // (0.9.7: a number already signed in here: Telegram's apps offer to go there instead)
            const here = accounts.adding ? accounts.phoneUsed(v) : 0
            if (here) {
                alert.show("", Tr.t("Bu raqam bilan bu yerda allaqachon kirilgan."),
                           [{ t: "OK" }, { t: Tr.t("O'tish"), run: () => accounts.cancelAdd(here) }])
                return
            }
            again = false
            store.send({ "@type": "setAuthenticationPhoneNumber", phone_number: v }, store.check)
        } else if (step === "email")
            store.send({ "@type": "setAuthenticationEmailAddress", email_address: v }, store.check)
        else if (step === "emailcode")
            store.send({ "@type": "checkAuthenticationEmailCode",
                         code: { "@type": "emailAddressAuthenticationCode", code: v } }, store.check)
        else if (step === "name")
            store.send({ "@type": "registerUser", first_name: v, last_name: st.last.text.trim(),
                         disable_notification: false }, store.check)
        else if (step === "code")
            store.send({ "@type": "checkAuthenticationCode", code: v }, store.check)
        else if (step === "password")
            store.send({ "@type": "checkAuthenticationPassword", password: v }, store.check)
        if (st.code)
            st.sent = true          // (the cells keep the code: red and emptied if it was wrong)
    }

    Alert { id: alert; anchors.fill: parent; z: 10 }     // (0.9.7: a number already signed in here)
}
