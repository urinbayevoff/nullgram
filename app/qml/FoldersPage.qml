// The chat folders, as Telegram-iOS's ChatListFilterPresetListController: its Folders animation (ChatListFilterSettingsHeaderItem:
// ChatListFolders, 96 at −10, once; tapped, again) with its words (13, grey, 92 + 8 down); «PAPKALAR»: «Papka yaratish» (the
// accent), «Barcha chatlar» and each folder, its tag's colour when tags are shown; «Tahrirlash»: a red ⊖ by each folder («O'chirish»
// on the row's right, asked: deleteChatFolder) and a grip on every row's right to drag it to another place (reorderChatFolders on
// «Tayyor»; «Barcha chatlar» moves only with Premium, else back with iOS's note); «TAVSIYA ETILGAN PAPKALAR» (getRecommendedChatFolders)
// with «QO'SHISH» (createChatFolder); «Papka teglarini ko'rsatish» (toggleChatFolderTags; locked without Premium). A folder
// tapped, or «Papka yaratish»: FolderPage.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Papkalar")
    property bool editing: false
    property var order: null            // while editing: the rows' ids in their new order (0: «Barcha chatlar»)
    property var kept: null             // the order before a drag (put back when «Barcha chatlar» may not move)
    property int dragged: -1            // the row held by its grip
    property real dragY: 0
    property int revealed: -1           // the folder showing «O'chirish»
    property var recommended: []
    readonly property bool premium: !!store.me && !!store.me.is_premium
    readonly property var stored: {
        const ids = store.folders.map((f) => f.id)
        ids.splice(Math.min(store.mainPosition, ids.length), 0, 0)
        return ids
    }
    readonly property var rows: order || stored
    action: store.folders.length ? (editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")) : ""
    actionBold: editing
    onActed: editing ? done() : edit()

    function folder(id) {
        return store.folders.find((f) => f.id === id) || null
    }
    function edit() {
        editing = true
        order = stored.slice()
        revealed = -1
    }
    function done() {
        editing = false
        revealed = -1
        const o = order
        order = null
        if (o && o.join() !== stored.join())
            store.send({ "@type": "reorderChatFolders", chat_folder_ids: o.filter((id) => id !== 0),
                         main_chat_list_position: o.indexOf(0) }, store.check)
    }
    // the shell's back: what is over the page first, then the editing
    function dismiss() {
        if (alert.open)
            alert.open = false
        else if (editing)
            done()
        else
            return false
        return true
    }

    function loadRecommended() {
        store.send({ "@type": "getRecommendedChatFolders" }, (r) => {
            if (page && r.chat_folders)
                page.recommended = r.chat_folders.filter((c) => !store.folders.some((f) => f.name === c.folder.name.text.text))
        })
    }
    Component.onCompleted: loadRecommended()
    Connections {
        target: store
        function onFoldersChanged() {
            if (page.order)         // (one added or taken away elsewhere while editing)
                page.order = page.order.filter((id) => id === 0 || page.folder(id)).concat(
                    store.folders.map((f) => f.id).filter((id) => page.order.indexOf(id) < 0))
            page.recommended = page.recommended.filter((c) => !store.folders.some((f) => f.name === c.folder.name.text.text))
        }
    }
    function addRecommended(c) {
        page.recommended = page.recommended.filter((x) => x !== c)
        store.send({ "@type": "createChatFolder", folder: c.folder }, (r) => {
            if (r["@type"] === "error") {
                page.say(r.message === "CHAT_FOLDER_COUNT_EXCEEDED" || /LIMIT|TOO_MUCH/.test(r.message)
                         ? Tr.t("Papkalar soni chegarasiga yetdingiz.") : r.message)
                page.loadRecommended()
            }
        })
    }
    property Component maker: null
    function open(id) {
        if (!maker)
            maker = Qt.createComponent("FolderPage.qml")
        nav.push(maker, { folderId: id })
    }
    function askRemove(f) {
        if (f.shared && f.links)
            alert.show(Tr.t("Papkani o'chirish"), Tr.t("Bu papkani o'chirasizmi? Uni ulashish uchun yaratilgan barcha taklif havolalari ham ishlamay qoladi."),
                       [{ t: Tr.t("O'chirish"), red: true, run: () => page.remove(f) }, { t: Tr.t("Bekor qilish"), bold: true }], true)
        else
            alert.show(Tr.f("«%1» olib tashlansinmi?", f.name), Tr.t("Papka olib tashlanadi, chatlaringiz o'chirilmaydi."),
                       [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("Olib tashlash"), red: true, run: () => page.remove(f) }])
    }
    function remove(f) {
        revealed = -1
        if (order)
            order = order.filter((id) => id !== f.id)
        store.send({ "@type": "deleteChatFolder", chat_folder_id: f.id, leave_chat_ids: [] }, (r) => {
            if (r["@type"] === "error" && page)
                page.say(r.message)
        })
    }
    function toggleTags() {
        if (!premium)
            return say(Tr.t("Papka teglari — Telegram Premium imkoniyati."))
        store.folderTags = !store.folderTags
        store.send({ "@type": "toggleChatFolderTags", are_tags_enabled: store.folderTags }, store.check)
    }
    // a row held by its grip: the others make room as it passes them
    function drag(id, y) {
        dragY = Math.max(-23, Math.min(y, (rows.length - 1) * 46 + 23))
        const to = Math.max(0, Math.min(rows.length - 1, Math.round(dragY / 46)))
        const at = order.indexOf(id)
        if (to !== at) {
            const o = order.slice()
            o.splice(at, 1)
            o.splice(to, 0, id)
            order = o
        }
    }
    function dropped() {
        dragged = -1
        if (!premium && order[0] !== 0) {
            order = kept
            say(Tr.t("«Barcha chatlar» papkasini ko'chirish uchun Telegram Premium'ga obuna bo'ling."))
        }
    }

    // ---- the head ----
    Item {
        width: parent.width
        height: 92 + 8 - 16 + intro.height
        Lottie {
            id: anim
            anchors.horizontalCenter: parent.horizontalCenter
            y: -10 - 16
            width: 96; height: 96
            path: Qt.resolvedUrl("animations/ChatListFolders.tgs").toString().replace(/^file:\/\//, "")
            once: true
            MouseArea { anchors.fill: parent; onClicked: anim.replay() }
        }
        Text {
            id: intro
            x: 32; y: 92 + 8 - 16
            width: parent.width - 64
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("Turli chatlar uchun papkalar yarating va ular orasida tez almashing.")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 13
        }
    }

    // ---- the folders ----
    SettingsGroup {
        title: Tr.t("Papkalar")
        note: store.folders.length || !page.recommended.length ? Tr.t("Tartibni o'zgartirish yoki papkalarni o'chirish uchun «Tahrirlash»ni bosing.") : ""
        Item {          // «Papka yaratish» (ItemListPeerActionItem, no icon)
            width: parent.width; height: 46
            Rectangle { anchors.fill: parent; color: Theme.highlight; visible: newHit.pressed }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Papka yaratish")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { id: newHit; anchors.fill: parent; onClicked: page.open(0) }
            Rectangle { x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator }
        }
        Item {
            width: parent.width
            height: page.rows.length * 46
            Repeater {
                model: [0].concat(store.folders.map((f) => f.id))
                FolderRow {}
            }
        }
    }

    // ---- the recommended ones ----
    SettingsGroup {
        visible: page.recommended.length > 0
        title: Tr.t("Tavsiya etilgan papkalar")
        Repeater {
            model: page.recommended
            Item {          // ChatListFilterPresetListSuggestedItem: the name, what it holds, «QO'SHISH»
                id: rec
                required property var modelData
                required property int index
                width: parent.width
                height: 11 + recName.height + 2 + recText.height + 11
                Text {
                    id: recName
                    x: 16; y: 11
                    width: parent.width - x - addBtn.width - 32
                    elide: Text.ElideRight
                    text: rec.modelData.folder.name.text.text
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17
                }
                Text {
                    id: recText
                    x: 16; y: recName.y + recName.height + 2
                    width: recName.width
                    wrapMode: Text.Wrap
                    text: rec.modelData.description
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Rectangle {
                    id: addBtn
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: addText.implicitWidth + 28; height: 28; radius: 14
                    color: Theme.accent
                    opacity: addHit.pressed ? 0.7 : 1
                    Text {
                        id: addText
                        anchors.centerIn: parent; anchors.verticalCenterOffset: 1
                        text: Tr.t("QO'SHISH")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    MouseArea { id: addHit; anchors.fill: parent; anchors.margins: -8; onClicked: page.addRecommended(rec.modelData) }
                }
                Rectangle {
                    visible: rec.index < page.recommended.length - 1 || !store.folders.length
                    x: 16; anchors.bottom: parent.bottom; width: parent.width - 16; height: 0.5; color: Theme.separator
                }
            }
        }
        Item {          // with no folders yet: one of their own
            visible: !store.folders.length
            width: parent.width; height: 46
            Rectangle { anchors.fill: parent; color: Theme.highlight; visible: customHit.pressed }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Boshqa papka qo'shish")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { id: customHit; anchors.fill: parent; onClicked: page.open(0) }
        }
    }

    // ---- the tags ----
    SettingsGroup {
        note: Tr.t("Ro'yxatda har bir chat yonida uning papkalari nomini ko'rsatish.")
        Item {
            width: parent.width; height: 46
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 100
                elide: Text.ElideRight
                text: Tr.t("Papka teglarini ko'rsatish")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
            }
            Switch {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                on: page.premium && store.folderTags
                opacity: page.premium ? 1 : 0.5
                Icon {          // (displayLocked)
                    visible: !page.premium
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    name: "lock"; color: Theme.grey
                }
            }
            MouseArea { anchors.fill: parent; onClicked: page.toggleTags() }
        }
    }

    // ---- a row: «Barcha chatlar» (id 0) or a folder ----
    component FolderRow: Item {
        id: frow
        required property int modelData
        readonly property var f: page.folder(modelData)
        readonly property int slot: page.rows.indexOf(modelData)
        readonly property bool held: page.dragged === modelData
        readonly property real shift: page.editing ? 38 : 0                 // the ⊖'s room (editableControlLayout)
        readonly property real slide: page.revealed === modelData && modelData !== 0 ? -delBtn.width : 0
        visible: slot >= 0
        width: parent.width; height: 46
        y: held ? page.dragY : slot * 46
        z: held ? 2 : 0
        Behavior on y { enabled: !frow.held; NumberAnimation { duration: 300; easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
        clip: true
        Rectangle {
            anchors.fill: parent
            color: frow.held ? Theme.card : rowHit.pressed && !page.editing ? Theme.highlight : "transparent"     // (the card's corners show)
            opacity: frow.held ? 0.92 : 1
        }
        MouseArea {
            id: rowHit
            anchors.fill: parent
            onClicked: {
                if (page.revealed >= 0)
                    page.revealed = -1
                else if (!page.editing && frow.modelData !== 0)
                    page.open(frow.modelData)
            }
        }
        Item {
            x: frow.shift + frow.slide
            width: parent.width; height: parent.height
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - frow.shift - 70
                elide: Text.ElideMiddle
                text: frow.modelData === 0 ? Tr.t("Barcha chatlar") : frow.f ? frow.f.name : ""
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
            }
            Rectangle {         // its tag's colour (24, by the chevron)
                visible: store.folderTags && page.premium && !!frow.f && frow.f.color >= 0
                anchors.right: parent.right; anchors.rightMargin: 34 + frow.shift
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: 12
                color: frow.f ? store.nameColor(frow.f.color) : "transparent"
                opacity: page.editing ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Text {
                visible: frow.modelData !== 0
                anchors.right: parent.right; anchors.rightMargin: 14 + frow.shift
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: Theme.grey
                opacity: page.editing ? 0 : 0.6
                Behavior on opacity { NumberAnimation { duration: 200 } }
                font.family: Theme.font; font.pixelSize: 24
            }
        }
        Rectangle {         // ⊖ (not for «Barcha chatlar»)
            x: 12 + frow.slide + (page.editing ? 0 : -40)
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 11
            color: Theme.danger
            visible: frow.modelData !== 0
            opacity: page.editing ? 1 : 0
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Behavior on opacity { NumberAnimation { duration: 250 } }
            Rectangle { anchors.centerIn: parent; width: 11; height: 2; radius: 1; color: "white" }
            MouseArea {
                anchors.fill: parent; anchors.margins: -10
                enabled: page.editing
                onClicked: page.revealed = page.revealed === frow.modelData ? -1 : frow.modelData
            }
        }
        Item {              // the grip (ItemListEditableReorderControlNode): held, the row goes with the finger
            visible: page.rows.length > 1
            anchors.right: parent.right; anchors.rightMargin: -frow.slide
            width: 52; height: parent.height
            opacity: page.editing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            Column {
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: 3
                    Rectangle { width: 22; height: 2; radius: 1; color: Theme.grey; opacity: 0.7 }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: page.editing && page.revealed < 0
                preventStealing: true
                property real from: 0
                onPressed: (m) => {
                    from = mapToItem(frow.parent, m.x, m.y).y - frow.y
                    page.kept = page.order.slice()
                    page.dragY = frow.y
                    page.dragged = frow.modelData
                }
                onPositionChanged: (m) => page.drag(frow.modelData, mapToItem(frow.parent, m.x, m.y).y - from)
                onReleased: page.dropped()
                onCanceled: page.dropped()
            }
        }
        Rectangle {         // «O'chirish» (ItemListRevealOption, destructive)
            id: delBtn
            x: parent.width + frow.slide
            width: delText.implicitWidth + 32; height: parent.height
            color: Theme.danger
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
            Text {
                id: delText
                anchors.centerIn: parent
                text: Tr.t("O'chirish")
                color: "white"
                font.family: Theme.font; font.pixelSize: 17
            }
            MouseArea { anchors.fill: parent; onClicked: if (frow.f) page.askRemove(frow.f) }
        }
        Rectangle {
            visible: frow.slot < page.rows.length - 1 && !frow.held
            x: 16 + frow.shift; anchors.bottom: parent.bottom
            width: parent.width - x; height: 0.5
            color: Theme.separator
        }
    }

    // ---- over the page ----
    Alert { id: alert; parent: page; anchors.fill: parent }
    function say(text) {
        note.text = text
        noteBox.opacity = 1
        noteAway.restart()
    }
    Rectangle {
        id: noteBox
        parent: page
        z: 45
        x: 12; width: page.width - 24
        y: page.height - height - 24
        height: note.height + 24
        radius: 14
        color: Qt.rgba(0, 0, 0, 0.85)
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: note
            x: 16; y: 12; width: parent.width - 32
            wrapMode: Text.Wrap
            color: "white"
            font.family: Theme.font; font.pixelSize: 14
        }
        Timer { id: noteAway; interval: 3000; onTriggered: noteBox.opacity = 0 }
    }
}
