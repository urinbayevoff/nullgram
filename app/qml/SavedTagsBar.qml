pragma ComponentBehavior: Bound
// Top tag filter strip for Saved Messages (Premium only, TDLib 1.8.68:
// getSavedMessagesTags, setSavedMessagesTagLabel, searchSavedMessages).
// Tapping a tag filters Saved Messages by that reaction tag; tapping again or tapping
// "Hammasi" clears the filter. Long-pressing a tag opens a compact label editor overlay.
import QtQuick

Item {
    id: bar
    property var store: null
    property var tags: []
    property string activeKey: ""
    property Item overlayParent: null
    property real bottomInset: 0

    signal picked(var tagObj)
    signal labelSaved(var tagObj, string label)
    signal errorSaid(string msg)

    property var renamingTag: null
    property string renamingEmoji: ""
    property string renamingInitial: ""
    property bool renamingBusy: false

    height: 46

    function startRename(tagObj, currentLabel) {
        if (!tagObj)
            return
        renamingTag = tagObj
        renamingEmoji = store ? store.reactionLabel(tagObj) : ""
        renamingInitial = currentLabel || ""
        renamingBusy = false
        renameLoader.active = false
        renameLoader.active = true
    }

    function dismissRename() {
        if (renamingTag !== null) {
            renamingTag = null
            renamingBusy = false
            renameLoader.active = false
            return true
        }
        return false
    }

    function submitRename(newLabel) {
        if (!store || !renamingTag || renamingBusy)
            return
        const tag = renamingTag
        const clean = String(newLabel || "").trim()
        renamingBusy = true
        store.setSavedMessagesTagLabel(tag, clean, (ok, err) => {
            if (!bar)
                return
            bar.renamingBusy = false
            if (!ok) {
                bar.errorSaid(err || Tr.t("Bo'lmadi"))
                return
            }
            bar.dismissRename()
            bar.labelSaved(tag, clean)
        })
    }

    Flickable {
        id: strip
        anchors.fill: parent
        contentWidth: chipRow.implicitWidth + 20
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.DragOverBounds
        clip: true

        Row {
            id: chipRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // "Hammasi" chip (clear tag filter)
            Rectangle {
                readonly property bool on: bar.activeKey === ""
                width: allTxt.implicitWidth + 22
                height: 30
                radius: 15
                color: on ? Theme.accent
                     : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, allHit.pressed ? 0.14 : 0.08)
                Text {
                    id: allTxt
                    anchors.centerIn: parent
                    text: Tr.t("Hammasi")
                    color: parent.on ? "white" : Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    font.weight: parent.on ? Font.DemiBold : Font.Medium
                }
                MouseArea {
                    id: allHit
                    anchors.fill: parent
                    onClicked: bar.picked(null)
                }
            }

            Repeater {
                model: bar.tags
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property string tkey: bar.store ? bar.store.reactionKey(modelData.tag) : ""
                    readonly property bool on: tkey !== "" && tkey === bar.activeKey
                    readonly property string emoji: bar.store ? bar.store.reactionLabel(modelData.tag) : ""
                    readonly property string lbl: modelData.label || ""
                    readonly property int cnt: modelData.count || 0
                    width: chipContent.implicitWidth + 20
                    height: 30
                    radius: 15
                    color: on ? Theme.accent
                         : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, chipHit.pressed ? 0.14 : 0.08)
                    Row {
                        id: chipContent
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.emoji
                            font.pixelSize: 14
                        }
                        Text {
                            visible: chip.lbl !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.lbl
                            color: chip.on ? "white" : Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                            font.weight: chip.on ? Font.DemiBold : Font.Medium
                        }
                        Text {
                            visible: chip.cnt > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(chip.cnt)
                            color: chip.on ? Qt.rgba(1, 1, 1, 0.85) : Theme.grey
                            font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        id: chipHit
                        anchors.fill: parent
                        pressAndHoldInterval: 350
                        property bool wasHeld: false
                        onPressed: wasHeld = false
                        onPressAndHold: {
                            wasHeld = true
                            bar.startRename(chip.modelData.tag, chip.lbl)
                        }
                        onClicked: {
                            if (wasHeld)
                                return
                            bar.picked(chip.on ? null : chip.modelData.tag)
                        }
                    }
                }
            }
        }
    }

    // Lazy rename overlay reparented to the ChatPage root so it sits cleanly above everything
    Loader {
        id: renameLoader
        active: false
        parent: bar.overlayParent || bar
        anchors.fill: parent
        z: 42
        sourceComponent: Item {
            id: dlg
            anchors.fill: parent
            Component.onCompleted: {
                labelInput.text = bar.renamingInitial
                labelInput.forceActiveFocus()
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.42)
                MouseArea { anchors.fill: parent; onClicked: bar.dismissRename() }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(72, Math.round((parent.height - bar.bottomInset - height) / 2))
                width: Math.min(parent.width - 44, 300)
                height: dlgCol.implicitHeight + 28
                radius: 16
                color: Theme.menu
                MouseArea { anchors.fill: parent }
                Column {
                    id: dlgCol
                    x: 16; y: 16
                    width: parent.width - 32
                    spacing: 12
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: bar.renamingEmoji + " " + Tr.t("Teg nomini tahrirlash")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        width: parent.width
                        height: 40
                        radius: 10
                        color: Theme.field
                        border.width: 1
                        border.color: Theme.fieldBorder
                        TextInput {
                            id: labelInput
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24
                            color: Theme.text
                            selectionColor: Theme.accent
                            font.family: Theme.font; font.pixelSize: 15
                            maximumLength: 12
                            onAccepted: bar.submitRename(text)
                            Text {
                                visible: !labelInput.text
                                text: Tr.t("Teg nomi (ixtiyoriy)")
                                color: Theme.grey
                                font: labelInput.font
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: 8
                        Rectangle {
                            width: (parent.width - 8) / 2; height: 38; radius: 10
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, cancelHit.pressed ? 0.16 : 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: Tr.t("Bekor qilish")
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 15
                            }
                            MouseArea { id: cancelHit; anchors.fill: parent; onClicked: bar.dismissRename() }
                        }
                        Rectangle {
                            width: (parent.width - 8) / 2; height: 38; radius: 10
                            color: Theme.accent
                            opacity: bar.renamingBusy ? 0.5 : (saveHit.pressed ? 0.78 : 1)
                            Text {
                                anchors.centerIn: parent
                                text: Tr.t("Saqlash")
                                color: "white"
                                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: saveHit
                                anchors.fill: parent
                                enabled: !bar.renamingBusy
                                onClicked: bar.submitRename(labelInput.text)
                            }
                        }
                    }
                }
            }
        }
    }
}
