// Custom reply keyboard shown in place of the on-screen keyboard (TDLib 1.8.68 replyMarkupShowKeyboard).
// Respects resize_keyboard, safeBottom (nav line inset), and light/dark themes.
pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    property var info: null
    property real maxPanelH: 280
    property real safeBottom: 0

    signal buttonTapped(var btn)

    readonly property var rows: info && info.rows ? info.rows : []
    readonly property bool resizeKb: !!(info && info.resize)
    readonly property real contentH: rows.length * 46 + Math.max(0, rows.length - 1) * 6 + 16
    readonly property real panelH: resizeKb
        ? Math.min(Math.max(maxPanelH, 240), Math.max(64, contentH) + safeBottom)
        : Math.max(maxPanelH, 240)

    color: Theme.keys

    Rectangle {
        width: parent.width
        height: 0.5
        color: Theme.separator
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: 1
        topMargin: 8
        bottomMargin: 8 + root.safeBottom
        leftMargin: 8
        rightMargin: 8
        contentWidth: Math.max(0, width - 16)
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.contentWidth
            spacing: 6

            Repeater {
                model: root.rows
                delegate: Row {
                    id: rowItem
                    required property var modelData
                    width: col.width
                    spacing: 6
                    readonly property int count: modelData ? modelData.length : 0
                    readonly property real btnW: (width - Math.max(0, count - 1) * 6) / Math.max(1, count)

                    Repeater {
                        model: rowItem.modelData
                        delegate: Rectangle {
                            id: btn
                            required property var modelData
                            width: rowItem.btnW
                            height: 46
                            radius: 10
                            color: hit.pressed ? Theme.highlight : (Theme.dark ? "#2c2c2e" : "#ffffff")
                            border.width: 0.5
                            border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)

                            Text {
                                anchors.centerIn: parent
                                width: Math.max(12, parent.width - 14)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                text: btn.modelData ? (btn.modelData.text || "") : ""
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 15
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: hit
                                anchors.fill: parent
                                onClicked: root.buttonTapped(btn.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
