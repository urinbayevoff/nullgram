// Long-press chat preview + context menu and bottom action/folder picker sheet for ChatListPage/ArchivePage.
// Respects ztMETRO's safe.bottom navigation line.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: menu
    anchors.fill: parent
    z: 25
    property var store
    property bool open: false
    property string mode: "chat"        // "chat" (preview + actions) or "list" (bottom sheet: folders / archive settings)
    property var chatId: 0
    property var actions: []            // [{ text, icon, danger, gap, checked, run }]
    property string sheetTitle: ""
    readonly property var peek: peekLoader.item
    signal openChat(var chatId, var messageId)

    readonly property var chat: (store && store.seen >= 0 && chatId) ? store.chats[chatId] : null

    function show(id, acts) {
        mode = "chat"
        chatId = id
        actions = acts || []
        open = true
    }

    function showList(title, items) {
        mode = "list"
        sheetTitle = title || ""
        actions = items || []
        open = true
    }

    function close() {
        open = false
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.62 : 0.42)
    }
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.close()
    }

    // ---- Mode 1: Chat Preview + Context Menu ----
    Item {
        visible: menu.mode === "chat"
        anchors.fill: parent
        scale: menu.open ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        readonly property real gapH: 8
        readonly property real rowH: 43
        readonly property real actsH: menu.actions.length * rowH + menu.actions.filter((a) => a.gap).length * gapH
        readonly property real availH: Math.max(240, parent.height - safe.bottom - 32)
        readonly property real previewH: Math.max(240, Math.min(380, Math.round(availH * 0.52)))
        readonly property real boxH: Math.min(actsH, Math.max(132, availH - previewH - 10))
        readonly property real totalH: previewH + 10 + boxH
        readonly property real startY: Math.max(16, Math.round((parent.height - safe.bottom - totalH) / 2))

        // Preview card (header + scrollable real-chat ChatPeek, true rounded corners)
        Item {
            id: previewCard
            x: 14; y: parent.startY
            width: parent.width - 28; height: parent.previewH

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: Theme.grouped
            }

            // Keep touches inside the card from reaching the dismiss backdrop
            MouseArea {
                anchors.fill: parent
                enabled: menu.open
            }

            // Scrollable chat preview (lazy-loaded only while menu is open/visible)
            Component {
                id: peekComp
                ChatPeek {
                    store: menu.store
                    chatId: menu.chatId
                    active: menu.open
                    topInset: pHead.height
                    cardRadius: 16
                    onPicked: (id, msgId) => {
                        menu.close()
                        menu.openChat(id, msgId)
                    }
                }
            }
            Loader {
                id: peekLoader
                anchors.fill: parent
                active: menu.mode === "chat" && (menu.open || menu.opacity > 0)
                sourceComponent: peekComp
            }

            // Preview header (top-rounded 16 pt corners; tap opens chat normally, as before)
            Item {
                id: pHead
                z: 2
                width: parent.width; height: 50
                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: Theme.bg
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 16
                    color: Theme.bg
                }
                Avatar {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34
                    source: menu.chat ? menu.store.photoPath(menu.chat) : ""
                    letters: menu.chat ? menu.store.letters(menu.chat.title) : ""
                    tint: menu.chat ? menu.store.tints[Math.abs(menu.chat.id) % menu.store.tints.length] : Theme.accent
                    saved: menu.chat ? menu.store.isSaved(menu.chat) : false
                }
                Column {
                    x: 54; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 66
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: menu.chat ? menu.store.title(menu.chat) : ""
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: menu.chat ? menu.store.status(menu.chat, Math.floor(Date.now() / 1000)) : ""
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 0.5
                    color: Theme.separator
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: menu.open
                    onClicked: {
                        const id = menu.chatId
                        menu.close()
                        menu.openChat(id, 0)
                    }
                }
            }
        }

        // Actions card
        Rectangle {
            id: actionCard
            x: 14; y: previewCard.y + previewCard.height + 10
            width: Math.min(264, parent.width - 28)
            height: parent.boxH
            radius: 16
            color: Theme.menu
            clip: true

            Flickable {
                anchors.fill: parent
                contentHeight: actCol.height
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: actCol
                    width: parent.width
                    Repeater {
                        model: menu.actions
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property real gap: modelData.gap ? 8 : 0
                            width: actionCard.width; height: 43 + gap
                            color: actHit.pressed ? Theme.highlight : "transparent"

                            Rectangle {
                                visible: parent.gap > 0
                                width: parent.width; height: parent.gap
                                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.07)
                            }
                            Rectangle {
                                visible: parent.index > 0 && parent.gap === 0
                                x: 16; width: parent.width - 16; height: 0.5
                                color: Theme.separator
                            }
                            Icon {
                                visible: !!parent.modelData.icon
                                x: 16; y: parent.gap + (43 - height) / 2
                                width: 19; height: 19
                                name: parent.modelData.icon || ""
                                color: parent.modelData.danger ? Theme.danger : Theme.text
                            }
                            Text {
                                x: parent.modelData.icon ? 46 : 16
                                y: parent.gap + (43 - height) / 2
                                width: parent.width - x - 14
                                elide: Text.ElideRight
                                text: parent.modelData.text || ""
                                color: parent.modelData.danger ? Theme.danger : Theme.text
                                font.family: Theme.font; font.pixelSize: 15
                            }
                            MouseArea {
                                id: actHit
                                anchors.fill: parent
                                onClicked: {
                                    const run = parent.modelData.run
                                    menu.close()
                                    if (run)
                                        run()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Mode 2: Bottom sheet list (Add to Folder / Archive Settings) ----
    Rectangle {
        visible: menu.mode === "list"
        x: 12
        width: parent.width - 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16 + safe.bottom
        height: Math.min(parent.height - safe.bottom - 80, sheetHead.height + sheetCol.height + cancelBtn.height + 1)
        radius: 16
        color: Theme.menu
        clip: true

        Item {
            id: sheetHead
            width: parent.width; height: menu.sheetTitle ? 44 : 0
            visible: menu.sheetTitle !== ""
            Text {
                anchors.centerIn: parent
                text: menu.sheetTitle
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }
        Flickable {
            anchors.top: sheetHead.bottom
            anchors.bottom: cancelBtn.top
            width: parent.width
            contentHeight: sheetCol.height
            interactive: contentHeight > height
            clip: true
            Column {
                id: sheetCol
                width: parent.width
                Repeater {
                    model: menu.mode === "list" ? menu.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: sheetCol.width; height: 48
                        color: shHit.pressed ? Theme.highlight : "transparent"
                        Rectangle {
                            visible: parent.index > 0
                            x: 16; width: parent.width - 32; height: 0.5
                            color: Theme.separator
                        }
                        Icon {
                            visible: !!parent.modelData.icon
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            name: parent.modelData.icon || ""
                            color: parent.modelData.danger ? Theme.danger : Theme.accent
                        }
                        Text {
                            x: parent.modelData.icon ? 48 : 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - (parent.modelData.checked !== undefined ? 44 : 16)
                            elide: Text.ElideRight
                            text: parent.modelData.text || ""
                            color: parent.modelData.danger ? Theme.danger : Theme.text
                            font.family: Theme.font; font.pixelSize: 15
                        }
                        Icon {
                            visible: parent.modelData.checked === true
                            anchors.right: parent.right; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            name: "check"
                            color: Theme.accent
                        }
                        MouseArea {
                            id: shHit
                            anchors.fill: parent
                            onClicked: {
                                const run = parent.modelData.run
                                menu.close()
                                if (run)
                                    run()
                            }
                        }
                    }
                }
            }
        }
        Rectangle {
            id: cancelBtn
            anchors.bottom: parent.bottom
            width: parent.width; height: 48
            color: cancelHit.pressed ? Theme.highlight : "transparent"
            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
            Text {
                anchors.centerIn: parent
                text: Tr.t("Bekor qilish")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            MouseArea { id: cancelHit; anchors.fill: parent; onClicked: menu.close() }
        }
    }
}
