// The four digits' pad, as Telegram-iOS's PasscodeEntryController (dark, round keys with their letters, the dots
// filling, a wrong one shaken off). `mode`: "check" — the app's lock (or asked before turning it off): passed() on the
// right one; "set" — a new one twice, then Prefs.passcode set and passed(). `cancel`: «Bekor qilish» at the foot.
import QtQuick

Rectangle {
    id: pad
    property string mode: "check"
    property bool cancel: false
    property string heading: ""
    property string typed: ""
    property string first: ""           // ("set": the first time's digits)
    property bool wrong: false
    signal passed()
    signal cancelled()
    anchors.fill: parent
    color: "#101418"
    gradient: Gradient {
        GradientStop { position: 0; color: "#1d2a3a" }
        GradientStop { position: 1; color: "#0b0f14" }
    }
    onVisibleChanged: { typed = ""; first = ""; wrong = false }

    function hash(d) { return Qt.md5("nullgram:" + d) }
    readonly property string prompt: heading ? heading
        : mode === "set" ? (first ? Tr.t("Kod-parolni qayta kiriting") : Tr.t("Yangi kod-parolni kiriting"))
        : Tr.t("Kod-parolni kiriting")

    function key(d) {
        if (shake.running) {          // (typing on while the wrong one shakes off: a fresh start)
            shake.stop()
            shift.x = 0
            typed = ""
        }
        if (typed.length >= 4)
            return
        wrong = false
        typed += d
        if (typed.length === 4)
            settle.restart()
    }
    function back() { typed = typed.slice(0, -1) }
    Timer {                 // (the fourth dot seen filled first)
        id: settle
        interval: 160
        onTriggered: {
            if (pad.mode === "check") {
                if (pad.hash(pad.typed) === Prefs.passcode) {
                    pad.typed = ""
                    pad.passed()
                } else
                    pad.fail()
            } else if (!pad.first) {
                pad.first = pad.typed
                pad.typed = ""
            } else if (pad.first === pad.typed) {
                Prefs.passcode = pad.hash(pad.typed)
                pad.typed = ""
                pad.first = ""
                pad.passed()
            } else {
                pad.first = ""
                pad.fail()
            }
        }
    }
    function fail() {
        wrong = true
        shake.restart()
    }

    MouseArea { anchors.fill: parent }          // (nothing under it reached)

    Column {
        id: top
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(40, keys.y * 0.3)
        spacing: 22
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pad.prompt
            color: "white"
            font.family: Theme.font; font.pixelSize: 20
        }
        Row {
            id: dots
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            transform: Translate { id: shift }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shift; property: "x"; to: -18; duration: 50 }
                NumberAnimation { target: shift; property: "x"; to: 18; duration: 80 }
                NumberAnimation { target: shift; property: "x"; to: -10; duration: 70 }
                NumberAnimation { target: shift; property: "x"; to: 0; duration: 60 }
                ScriptAction { script: pad.typed = "" }
            }
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    width: 14; height: 14; radius: 7
                    color: index < pad.typed.length ? "white" : "transparent"
                    border.color: "white"; border.width: 1.2
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pad.wrong ? (pad.mode === "set" ? Tr.t("Kodlar mos kelmadi, qaytadan kiriting.") : Tr.t("Kod noto'g'ri"))
                            : " "
            color: "#ff8a80"
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    Grid {
        id: keys
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36 + safe.bottom
        columns: 3
        columnSpacing: 26; rowSpacing: 16
        Repeater {
            model: [["1", ""], ["2", "ABC"], ["3", "DEF"], ["4", "GHI"], ["5", "JKL"], ["6", "MNO"],
                    ["7", "PQRS"], ["8", "TUV"], ["9", "WXYZ"], ["", ""], ["0", ""], ["⌫", ""]]
            Item {
                id: k
                required property var modelData
                required property int index
                readonly property bool digit: modelData[0] !== "" && modelData[0] !== "⌫"
                width: 78; height: 78
                Rectangle {
                    anchors.fill: parent
                    radius: 39
                    visible: k.digit
                    color: hit.pressed ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.14)
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                Column {
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: k.index === 9 ? (pad.cancel ? Tr.t("Bekor") : "") : k.modelData[0]
                        visible: k.index !== 11 || pad.typed.length > 0
                        color: "white"
                        font.family: Theme.font; font.pixelSize: k.digit ? 34 : k.index === 11 ? 26 : 17
                        font.weight: Font.Light
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: k.modelData[1] !== ""
                        text: k.modelData[1]
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 10; font.letterSpacing: 2; font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    // (on the touch, as iOS: the same digit fast twice is two, not a double click)
                    onPressed: k.digit ? pad.key(k.modelData[0]) : k.index === 11 ? pad.back()
                               : pad.cancel ? pad.cancelled() : undefined
                }
            }
        }
    }
}
