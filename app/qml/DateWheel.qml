// iOS's date wheel (UIDatePicker .wheels), as the Birthday row opens it: day · month · year, each a column
// that snaps to the middle line; the year may be left out («—», the top of its column). Turned: changed().
import QtQuick

Item {
    id: wheel
    property int day: 1
    property int month: 1                // 1..12
    property int year: 0                 // 0: not told
    readonly property int first: 1900
    readonly property int last: new Date().getFullYear()
    readonly property int row: 34
    signal changed()
    width: 320; height: row * 5
    clip: true

    function days(m, y) { return new Date(y || 2000, m, 0).getDate() }      // (no year: 29-feb allowed)
    function set(d, m, y) {
        day = d; month = m; year = y
        dayCol.currentIndex = d - 1
        monthCol.currentIndex = m - 1
        yearCol.currentIndex = y ? y - first + 1 : 0
    }
    function pick() {
        const m = monthCol.currentIndex + 1
        const y = yearCol.currentIndex > 0 ? first + yearCol.currentIndex - 1 : 0
        const d = Math.min(dayCol.currentIndex + 1, days(m, y))
        if (d !== day || m !== month || y !== year) {
            day = d; month = m; year = y
            changed()
        }
        if (dayCol.currentIndex !== d - 1)
            dayCol.currentIndex = d - 1
    }

    Rectangle {         // the middle line's band
        x: 8; width: parent.width - 16; height: wheel.row
        anchors.verticalCenter: parent.verticalCenter
        radius: 8
        color: Theme.dark ? "#2c2c2e" : "#ececf0"
    }
    component Col: ListView {
        id: col
        property var words: []
        property int align: Text.AlignHCenter
        height: wheel.height
        model: words.length
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: wheel.row * 2
        preferredHighlightEnd: wheel.row * 3
        snapMode: ListView.SnapToItem
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 200
        onMovementEnded: wheel.pick()
        delegate: Text {
            required property int index
            width: col.width; height: wheel.row
            horizontalAlignment: col.align
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10; rightPadding: 10
            text: col.words[index]
            readonly property real off: Math.abs(y - col.contentY - wheel.row * 2) / wheel.row
            opacity: Math.max(0.25, 1 - off * 0.32)
            color: off < 0.5 ? Theme.text : Theme.grey
            font.family: Theme.font; font.pixelSize: 21
            MouseArea { anchors.fill: parent; onClicked: { col.currentIndex = parent.index; wheel.pick() } }
        }
    }
    Row {
        anchors.fill: parent
        Col {
            id: dayCol
            width: wheel.width * 0.22
            align: Text.AlignRight
            words: Array.from({ length: wheel.days(monthCol.currentIndex + 1, wheel.year) }, (_, i) => String(i + 1))
        }
        Col {
            id: monthCol
            width: wheel.width * 0.46
            words: Tr.en ? Tr.monthsEn : Tr.monthsUz.map((m) => m[0].toUpperCase() + m.slice(1))
        }
        Col {
            id: yearCol
            width: wheel.width * 0.32
            align: Text.AlignLeft
            words: ["—"].concat(Array.from({ length: wheel.last - wheel.first + 1 }, (_, i) => String(wheel.first + i)))
        }
    }
}
