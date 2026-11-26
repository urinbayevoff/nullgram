// Create or edit a forum topic (0.9.8): name input + 6 Telegram topic icon colors (create mode),
// bottom sheet aware of OSK and ztMETRO nav line (safe.bottom).
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: sheet
    required property var store
    required property var chatId
    property real safeBottom: 0
    property real oskH: 0

    property bool open: false
    property string mode: "create"      // "create" | "edit"
    property int topicId: 0
    property int chosenColor: 0x6FB9F0
    property bool busy: false
    property string errorText: ""

    signal saved(var info)
    signal hideKeyboardRequested()

    readonly property real lift: Math.max(oskH, safeBottom)
    readonly property string trimmedName: nameField.text.trim()
    readonly property bool canSubmit: trimmedName.length > 0 && !busy
    readonly property string previewLetter: {
        const t = trimmedName
        if (!t)
            return "#"
        const chars = Array.from(t)
        return chars.length ? chars[0].toUpperCase() : "#"
    }

    function showCreate() {
        mode = "create"
        topicId = 0
        chosenColor = store.forumIconColors[0]
        busy = false
        errorText = ""
        nameField.text = ""
        open = true
        Qt.callLater(() => { if (sheet && sheet.open) nameField.forceActiveFocus() })
    }

    function showEdit(tid, curName, colorInt) {
        mode = "edit"
        topicId = tid
        chosenColor = colorInt > 0 ? colorInt : store.forumIconColors[0]
        busy = false
        errorText = ""
        nameField.text = curName || ""
        nameField.cursorPosition = nameField.length
        open = true
        Qt.callLater(() => { if (sheet && sheet.open) nameField.forceActiveFocus() })
    }

    function close() {
        nameField.focus = false
        hideKeyboardRequested()
        open = false
    }

    function submit() {
        if (!canSubmit)
            return
        busy = true
        errorText = ""
        const title = trimmedName
        if (mode === "create") {
            store.createForumTopic(chatId, title, chosenColor, (r) => {
                if (!sheet)
                    return
                sheet.busy = false
                if (!r || r["@type"] === "error") {
                    sheet.errorText = r && r.message ? r.message : Tr.t("Bo'lmadi")
                    return
                }
                sheet.close()
                sheet.saved(r)
            })
        } else {
            store.editForumTopic(chatId, topicId, title, (r) => {
                if (!sheet)
                    return
                sheet.busy = false
                if (r && r["@type"] === "error") {
                    sheet.errorText = r.message || Tr.t("Bo'lmadi")
                    return
                }
                sheet.close()
                sheet.saved(null)
            })
        }
    }

    visible: dim.opacity > 0.001

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: sheet.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }

    Rectangle {
        id: card
        x: 0
        width: parent.width
        height: contentCol.implicitHeight + 28 + sheet.lift
        anchors.bottom: parent.bottom
        radius: 20
        color: Theme.card
        clip: true

        // Square off the bottom edge under the rounded top corners
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 20
            color: Theme.card
        }

        transform: Translate {
            y: sheet.open ? 0 : card.height + 24
            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        }

        // Absorb taps on the sheet body
        MouseArea { anchors.fill: parent }

        Column {
            id: contentCol
            x: 16; y: 14
            width: parent.width - 32
            spacing: 14

            // Header: title + close button
            Item {
                width: parent.width; height: 32
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: sheet.mode === "create" ? Tr.t("Yangi mavzu") : Tr.t("Mavzuni tahrirlash")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    color: closeHit.pressed ? Theme.highlight : (Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06))
                    Icon { anchors.centerIn: parent; width: 15; height: 15; name: "cross"; color: Theme.grey }
                    MouseArea { id: closeHit; anchors.fill: parent; anchors.margins: -6; onClicked: sheet.close() }
                }
            }

            // Live icon preview + name input
            Row {
                width: parent.width
                spacing: 12
                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: sheet.store.forumColorHex(sheet.chosenColor, sheet.topicId)
                    Text {
                        anchors.centerIn: parent
                        text: sheet.previewLetter
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 21; font.weight: Font.Bold
                    }
                }
                Rectangle {
                    width: parent.width - 60; height: 48; radius: 12
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                    border.width: nameField.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    TextInput {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Theme.font; font.pixelSize: 16
                        maximumLength: 128
                        clip: true
                        onAccepted: sheet.submit()
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !nameField.text
                            text: Tr.t("Mavzu nomi")
                            color: Theme.grey
                            font: nameField.font
                        }
                    }
                }
            }

            // Color palette (create mode only; TDLib editForumTopic does not change fallback color)
            Column {
                visible: sheet.mode === "create"
                width: parent.width
                spacing: 8
                Text {
                    text: Tr.t("Rang")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14
                    Repeater {
                        model: sheet.store.forumIconColors
                        Item {
                            id: swatch
                            required property int modelData
                            readonly property bool picked: sheet.chosenColor === modelData
                            width: 38; height: 38
                            Rectangle {
                                anchors.fill: parent
                                radius: 19
                                color: "transparent"
                                border.width: swatch.picked ? 2.5 : 0
                                border.color: Theme.accent
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                color: sheet.store.forumColorHex(swatch.modelData, 0)
                                Icon {
                                    visible: swatch.picked
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    name: "check"
                                    color: "white"
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                onClicked: sheet.chosenColor = swatch.modelData
                            }
                        }
                    }
                }
            }

            Text {
                visible: sheet.errorText !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: sheet.errorText
                color: Theme.danger
                font.family: Theme.font; font.pixelSize: 13
            }

            // Primary submit button (positioned above safe.bottom / OSK via card bottom padding)
            Rectangle {
                id: submitBtn
                width: parent.width; height: 48; radius: 14
                color: Theme.accent
                opacity: !sheet.canSubmit ? 0.45 : (submitHit.pressed ? 0.78 : 1)
                Text {
                    anchors.centerIn: parent
                    text: sheet.busy ? "…" : (sheet.mode === "create" ? Tr.t("Yaratish") : Tr.t("Saqlash"))
                    color: Theme.badgeText
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                MouseArea {
                    id: submitHit
                    anchors.fill: parent
                    enabled: sheet.canSubmit
                    onClicked: sheet.submit()
                }
            }
        }
    }
}
