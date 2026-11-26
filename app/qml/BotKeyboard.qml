// Inline keyboard under a bot message bubble (TDLib 1.8.68 replyMarkupInlineKeyboard).
// Instantiated dynamically only for messages carrying reply_markup so plain rows add 0 objects.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property var rows: []
    property string busyKey: ""

    signal buttonTapped(var btn, string btnKey)

    implicitHeight: col.implicitHeight
    height: implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 4

        Repeater {
            model: root.rows
            delegate: Row {
                id: rowItem
                required property var modelData
                required property int index
                width: col.width
                spacing: 4
                readonly property int count: modelData ? modelData.length : 0
                readonly property real btnW: (width - Math.max(0, count - 1) * 4) / Math.max(1, count)

                Repeater {
                    model: rowItem.modelData
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        required property int index
                        readonly property string key: rowItem.index + ":" + index
                        readonly property bool busy: root.busyKey === key
                        readonly property string kind: modelData ? (modelData.kind || "") : ""
                        readonly property string badge: busy ? "…"
                            : kind === "url" ? "↗"
                            : kind === "copy" ? "⧉"
                            : kind === "switch_inline" ? "↪"
                            : (kind === "web_app" || kind === "login_url" || kind === "buy" || kind === "game") ? "↗"
                            : ""

                        width: rowItem.btnW
                        height: 38
                        radius: 10
                        color: Theme.dark
                            ? (hit.pressed ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0.14, 0.14, 0.16, 0.80))
                            : (hit.pressed ? Qt.rgba(0.08, 0.16, 0.11, 0.56) : Qt.rgba(0.10, 0.20, 0.14, 0.42))
                        border.width: 0.5
                        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.22)
                        opacity: busy ? 0.65 : 1

                        Text {
                            anchors.centerIn: parent
                            width: Math.max(12, parent.width - (btn.badge !== "" ? 26 : 14))
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                            text: btn.modelData ? (btn.modelData.text || "") : ""
                            color: "white"
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Text {
                            visible: btn.badge !== ""
                            anchors.right: parent.right
                            anchors.rightMargin: 5
                            anchors.top: parent.top
                            anchors.topMargin: 2
                            text: btn.badge
                            textFormat: Text.PlainText
                            color: "white"
                            opacity: 0.78
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: hit
                            anchors.fill: parent
                            enabled: !btn.busy
                            onClicked: root.buttonTapped(btn.modelData, btn.key)
                        }
                    }
                }
            }
        }
    }
}
