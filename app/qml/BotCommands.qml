// Bot slash-command popup panel above the chat composer (TDLib 1.8.68 botInfo.commands / bot_commands).
// Shows matching /commands with descriptions (and @bot username in groups); tapping sends immediately.
pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    property var commands: []
    property string query: ""
    property bool isGroup: false

    signal picked(var cmd)

    readonly property var filtered: {
        const all = commands || []
        const q = (query || "").toLowerCase()
        if (!q)
            return all
        const head = []
        const rest = []
        for (const c of all) {
            const name = (c.command || "").toLowerCase()
            const desc = (c.description || "").toLowerCase()
            if (name.indexOf(q) === 0)
                head.push(c)
            else if (name.indexOf(q) > 0 || desc.indexOf(q) >= 0)
                rest.push(c)
        }
        return head.concat(rest)
    }
    readonly property int count: filtered.length

    radius: 16
    color: Theme.glass
    border.width: 0.5
    border.color: Theme.separator
    clip: true
    implicitHeight: count > 0 ? Math.min(240, count * 50 + 8) : 0
    height: implicitHeight
    visible: count > 0

    ListView {
        id: cmdList
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.filtered

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property string cmdName: modelData ? (modelData.command || "") : ""
            readonly property string desc: modelData ? (modelData.description || "") : ""
            readonly property string botUser: modelData ? (modelData.botUsername || "") : ""
            readonly property bool hasDesc: desc !== ""

            width: cmdList.width
            height: 50

            Rectangle {
                anchors.fill: parent
                color: hit.pressed ? Theme.highlight : "transparent"
            }

            Row {
                x: 14
                y: row.hasDesc ? 7 : 15
                width: parent.width - 28
                spacing: 4

                Text {
                    text: "/" + row.cmdName
                    textFormat: Text.PlainText
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Text {
                    visible: root.isGroup && row.botUser !== ""
                    text: "@" + row.botUser
                    textFormat: Text.PlainText
                    color: Theme.grey
                    font.family: Theme.font
                    font.pixelSize: 13
                    anchors.baseline: parent.children[0].baseline
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: row.hasDesc
                x: 14
                y: 27
                width: parent.width - 28
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
                text: row.desc
                color: Theme.grey
                font.family: Theme.font
                font.pixelSize: 13
            }

            Rectangle {
                visible: row.index < root.count - 1
                x: 14
                y: parent.height - 0.5
                width: parent.width - 28
                height: 0.5
                color: Theme.separator
            }

            MouseArea {
                id: hit
                anchors.fill: parent
                onClicked: root.picked(row.modelData)
            }
        }
    }
}
