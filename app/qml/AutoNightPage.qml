// «Avtomatik tungi rejim» (iOS's «Auto-Night Theme»), as Telegram-iOS's ThemeAutoNightSettingsController: «O'chiq» /
// «Jadval bo'yicha» ticked; with the schedule «JADVAL»: «Quyosh botishi va chiqishidan foydalanish» (then the times
// under it, worked out for Prefs.place — Toshkent unless set; iOS asks for the location once, we have none) or «Dan» /
// «Gacha» — a tap opens the wheels under the row (iOS's inline date picker). iOS's «Automatic» (the screen's
// brightness) and «System» wait: omonullOS has no backlight file and no night setting of its own. Main.qml's timer
// turns the night on and off at the times (Prefs.nightNow).
import QtQuick

SubPage {
    id: page
    title: Tr.t("Avtomatik tungi rejim")
    property string open: ""            // the wheels shown: "from", "to" or none

    function hm(min) {
        return String(Math.floor(min / 60)).padStart(2, "0") + ":" + String(min % 60).padStart(2, "0")
    }
    readonly property var sun: Prefs.sunTimes(new Date())

    SettingsGroup {
        SettingsRow { text: Tr.t("O'chiq"); chevron: false; tick: Prefs.autoNight === 0; onClicked: Prefs.autoNight = 0 }
        SettingsRow { text: Tr.t("Jadval bo'yicha"); chevron: false; tick: Prefs.autoNight === 1; last: true; onClicked: Prefs.autoNight = 1 }
    }
    SettingsGroup {
        visible: Prefs.autoNight === 1
        title: Tr.t("Jadval")
        note: Prefs.nightSun ? Tr.f("Quyosh botishi: %1\nQuyosh chiqishi: %2",
                                       page.sun ? page.hm(page.sun.set) : "—", page.sun ? page.hm(page.sun.rise) : "—") : ""
        SettingsRow {
            text: Tr.t("Quyosh botishi va chiqishi"); toggle: true; on: Prefs.nightSun; last: Prefs.nightSun
            onClicked: { Prefs.nightSun = !Prefs.nightSun; page.open = "" }
        }
        SettingsRow {
            visible: !Prefs.nightSun
            text: Tr.t("Dan"); chevron: false; value: page.hm(Prefs.nightFrom)
            onClicked: page.open = page.open === "from" ? "" : "from"
        }
        TimeWheels { visible: !Prefs.nightSun && page.open === "from"; minutes: Prefs.nightFrom; onPicked: (m) => Prefs.nightFrom = m }
        SettingsRow {
            visible: !Prefs.nightSun
            text: Tr.t("Gacha"); chevron: false; value: page.hm(Prefs.nightTo); last: page.open !== "to"
            onClicked: page.open = page.open === "to" ? "" : "to"
        }
        TimeWheels { visible: !Prefs.nightSun && page.open === "to"; minutes: Prefs.nightTo; onPicked: (m) => Prefs.nightTo = m }
    }

    // hours and minutes on two wheels (iOS's UIDatePicker .time): the middle one is it
    component TimeWheels: Item {
        id: tw
        property int minutes: 0
        signal picked(int minutes)
        width: parent ? parent.width : 300; height: visible ? 180 : 0
        Rectangle {         // the band over the chosen ones
            x: 16; width: parent.width - 32; y: (parent.height - 36) / 2; height: 36; radius: 8
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
        }
        Row {
            anchors.centerIn: parent
            spacing: 24
            Wheel { id: hh; count: 24; at: Math.floor(tw.minutes / 60); onMoved: tw.picked(hh.at * 60 + mm.at) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ":"; color: Theme.text; font.family: Theme.font; font.pixelSize: 22 }
            Wheel { id: mm; count: 60; at: tw.minutes % 60; onMoved: tw.picked(hh.at * 60 + mm.at) }
        }
    }
    component Wheel: ListView {
        id: wheel
        property int count: 24
        property int at: 0
        signal moved()
        width: 60; height: 180
        clip: true
        model: count
        snapMode: ListView.SnapToItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 72; preferredHighlightEnd: 108
        Component.onCompleted: positionViewAtIndex(at, ListView.Center), currentIndex = at
        onCurrentIndexChanged: if (moving || flicking || dragging) { at = currentIndex; moved() }
        onMovementEnded: { at = currentIndex; moved() }
        delegate: Text {
            required property int index
            width: 60; height: 36
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: String(index).padStart(2, "0")
            color: Theme.text
            opacity: ListView.isCurrentItem ? 1 : 0.35
            font.family: Theme.font; font.pixelSize: 22
        }
    }
}
