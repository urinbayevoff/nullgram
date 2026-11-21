// A row of a settings group, as Telegram-iOS lists them: an icon on a coloured square, the
// name, a value in grey, the chevron (when it opens something) or a switch. `art`: one of Telegram-iOS's own
// icons (settings-icons/<art>.png, made by tools/settings-icons.py: its picture on its gradient, 30 pt, corners 8);
// else `icon`, our line glyph on a square of `tint`.
import QtQuick

Item {
    id: row
    property string art: ""
    property string icon: ""
    property color tint: Theme.accent
    property string text: ""
    property string value: ""
    // the room for the name and the value; a long value (an e-mail) gives way, shortened in the middle, so the name stays
    readonly property real room: width - ((icon || art) ? 56 : 16) - (toggle ? 76 : chevron ? 40 : 16)
    readonly property real valueW: Math.min(valueText.implicitWidth, Math.max(room * 0.45, room - label.implicitWidth - 12))
    property string sub: ""             // grey words under the name (ItemListSwitchItem's text: 14, 2 under it)
    property bool dim: false            // a switch that cannot be changed now: half seen, a tap still comes
    property bool chevron: true
    property bool toggle: false         // a switch instead of the chevron
    property bool on: false
    property bool redOff: false         // (the switch red when off: Switch.redOff)
    property bool danger: false
    property bool accent: false         // the name in the accent (iOS's action rows: «Set a Color»)
    property bool bare: false           // the icon itself in `tint`, no square under it (iOS's action rows' glyphs)
    property bool last: false           // no line under it
    property bool tick: false           // a ✓ on the right (a choice of a few: set chevron false)
    signal clicked()
    width: parent ? parent.width : 300
    height: row.sub ? Math.max(46, 11 + label.height + 2 + subText.height + 11) : 46

    Rectangle {
        anchors.fill: parent
        color: Theme.highlight
        visible: hit.pressed && !row.toggle
    }
    Image {
        visible: row.art !== ""
        x: 14; anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30
        source: row.art ? "settings-icons/" + row.art + ".png" : ""
        sourceSize: Qt.size(120, 120)
        smooth: true; mipmap: true
    }
    Rectangle {
        id: square
        visible: row.icon !== "" && row.art === ""
        x: 14; anchors.verticalCenter: parent.verticalCenter
        width: 29; height: 29; radius: 7
        color: row.bare ? "transparent" : row.tint
        Icon { anchors.centerIn: parent; width: row.bare ? 24 : 19; height: width; name: row.icon; color: row.bare ? row.tint : "white" }
    }
    Text {
        id: label
        x: row.icon || row.art ? 56 : 16
        y: row.sub ? 11 : (parent.height - height) / 2
        width: row.room - (valueText.visible ? row.valueW + 12 : 0)
        elide: Text.ElideRight
        text: row.text
        color: row.danger ? Theme.danger : row.accent ? Theme.accent : Theme.text
        opacity: row.dim ? 0.5 : 1
        font.family: Theme.font; font.pixelSize: 16
    }
    Text {
        id: subText
        visible: row.sub !== ""
        x: label.x; y: label.y + label.height + 2
        width: label.width
        wrapMode: Text.Wrap
        text: row.sub
        color: Theme.grey
        opacity: row.dim ? 0.5 : 1
        font.family: Theme.font; font.pixelSize: 13
    }
    Text {
        id: valueText
        visible: row.value !== ""
        anchors.right: parent.right; anchors.rightMargin: row.chevron ? 32 : row.toggle ? 76 : 16
        anchors.verticalCenter: parent.verticalCenter
        width: row.valueW
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
        text: row.value
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 16
    }
    Text {
        visible: row.chevron && !row.toggle
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Theme.dark ? "#5a5a5e" : "#c4c4c7"
        font.family: Theme.font; font.pixelSize: 24
    }
    Icon {
        visible: row.tick
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20
        name: "check"
        color: Theme.accent
    }
    Switch {
        visible: row.toggle
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        on: row.on
        redOff: row.redOff
        opacity: row.dim ? 0.5 : 1
    }
    Rectangle {
        visible: !row.last
        x: label.x; anchors.bottom: parent.bottom
        width: parent.width - x; height: 0.5
        color: Theme.separator
    }
    MouseArea { id: hit; anchors.fill: parent; onClicked: row.clicked() }
}
