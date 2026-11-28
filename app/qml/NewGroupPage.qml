// New Group (Telegram-iOS's two-step group creation):
// Step 1: pick members from contacts (with selected chips at the top + live search).
// Step 2: group name + optional photo (AttachSheet) + preview of chosen members → createNewBasicGroupChat.
// Double-tap protected: the Create button locks with a spinner until TDLib answers.
pragma ComponentBehavior: Bound
import QtQuick

Page {
    id: page
    property int step: 1                // 1: pick members, 2: name & photo
    property int now: Date.now() / 1000
    property bool loaded: false
    property var allContacts: []        // [user]
    property var pickedIds: []          // [userId]
    property string query: ""
    property string photo: ""           // local path for group photo
    property bool creating: false
    property string errorText: ""
    property var sheet: null

    color: step === 1 ? Theme.bg : Theme.grouped

    Component.onCompleted: {
        now = Date.now() / 1000
        store.contacts((list) => {
            page.allContacts = list
            page.loaded = true
            page.rebuildList()
        })
    }

    function keyboardDown() {
        searchField.focus = false
        groupName.focus = false
        if (osk.h > 0)
            osk.hide()
    }

    function dismiss() {
        if (sheet && sheet.open) {
            sheet.close()
            return true
        }
        if (alert.open) {
            alert.open = false
            return true
        }
        if (step === 2 && !creating) {
            keyboardDown()
            step = 1
            return true
        }
        return false
    }

    function isPicked(uid) {
        return pickedIds.indexOf(uid) >= 0
    }

    function toggleUser(uid) {
        if (isPicked(uid))
            pickedIds = pickedIds.filter((id) => id !== uid)
        else
            pickedIds = pickedIds.concat([uid])
        rebuildChips()
    }

    function userPhotoNow(u) {
        return store.userPhotoNow(u)
    }

    function rebuildChips() {
        chips.clear()
        for (const uid of pickedIds) {
            const u = store.users[uid]
            const full = u ? (u.first_name + " " + u.last_name).trim() : String(uid)
            const first = u && u.first_name ? u.first_name : full
            chips.append({
                userId: uid, firstName: first, fullName: full,
                photo: userPhotoNow(u), letters: store.letters(full),
                tint: store.tints[Math.abs(uid) % store.tints.length]
            })
            store.askUserPhoto(u, chips, "userId")
        }
    }

    function rebuildList() {
        contactRows.clear()
        const f = store.fold(query)
        for (const u of allContacts) {
            const full = (u.first_name + " " + u.last_name).trim()
            if (f && store.fold(full).indexOf(f) < 0)
                continue
            contactRows.append({
                userId: u.id, name: full,
                photo: userPhotoNow(u), letters: store.letters(full),
                tint: store.tints[Math.abs(u.id) % store.tints.length]
            })
            store.askUserPhoto(u, contactRows, "userId")
        }
    }

    function openPicker() {
        keyboardDown()
        if (!sheet)
            sheet = sheetMaker.createObject(page)
        sheet.show()
    }

    function pickPhoto() {
        if (creating)
            return
        if (!photo)
            return openPicker()
        alert.title = Tr.t("Guruh rasmi")
        alert.text = ""
        alert.answers = [
            { t: Tr.t("Rasm tanlash"), run: () => page.openPicker() },
            { t: Tr.t("Rasmni o'chirish"), red: true, run: () => page.photo = "" },
            { t: Tr.t("Bekor qilish") }
        ]
        alert.open = true
    }

    function createNow() {
        const t = groupName.text.trim()
        if (creating || !t || pickedIds.length === 0)
            return
        creating = true
        errorText = ""
        keyboardDown()
        store.createGroup(t, pickedIds, photo, (chatId, err, failed) => {
            if (!page)
                return
            if (!chatId) {
                page.creating = false
                page.errorText = err || Tr.t("Bo'lmadi")
                page.nav.say(Tr.f("Bo'lmadi: %1", page.errorText))
                return
            }
            page.nav.openCreatedChat(chatId)
            if (failed > 0)     // (Telegram-iOS says so too; they can still be sent an invite link)
                page.nav.say(Tr.n("%1 kishini maxfiylik sozlamasi tufayli qo'shib bo'lmadi", failed))
        })
    }

    ListModel { id: contactRows }
    ListModel { id: chips }

    // ---- header bar ----
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: page.step === 1 ? Theme.bg : Theme.grouped
        z: 5

        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: page.creating ? Theme.grey : Theme.accent
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea {
            id: backHit
            width: 72; height: parent.height
            enabled: !page.creating
            onClicked: {
                page.keyboardDown()
                if (page.step === 2)
                    page.step = 1
                else
                    page.nav.pop()
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Tr.t("Yangi guruh")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.step === 1
                text: page.pickedIds.length > 0 ? Tr.f("%1 / 200", page.pickedIds.length) : Tr.t("A'zolarni tanlang")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }

        readonly property bool canAct: page.step === 1 ? page.pickedIds.length > 0
                                                       : (groupName.text.trim() !== "" && !page.creating)

        Text {
            id: actText
            visible: !page.creating
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: page.step === 1 ? Tr.t("Keyingi") : Tr.t("Yaratish")
            color: bar.canAct ? Theme.accent : Theme.grey
            opacity: actHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
        Ring {
            visible: page.creating
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22
            value: 0.72
            cross: false
            color: Theme.accent
            thickness: 2.2
        }
        MouseArea {
            id: actHit
            enabled: bar.canAct && !page.creating
            anchors.right: parent.right
            width: actText.width + 32; height: parent.height
            onClicked: {
                if (page.step === 1) {
                    page.keyboardDown()
                    page.step = 2
                } else {
                    page.createNow()
                }
            }
        }
        Rectangle {
            visible: page.step === 1
            anchors.bottom: parent.bottom
            width: parent.width; height: 0.5
            color: Theme.separator
        }
    }

    // ---- STEP 1: selected chips + search + contact picker ----
    Item {
        id: step1
        visible: page.step === 1
        y: bar.height
        width: parent.width; height: parent.height - y

        // selected member chips strip
        Item {
            id: chipStrip
            width: parent.width
            height: chips.count > 0 ? 48 : 0
            clip: true
            ListView {
                id: chipView
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                orientation: ListView.Horizontal
                spacing: 8
                model: chips
                delegate: Rectangle {
                    id: chip
                    required property var userId
                    required property string firstName
                    required property string photo
                    required property string letters
                    required property string tint
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    height: 32
                    width: chipLabel.x + chipLabel.implicitWidth + 26
                    radius: 16
                    color: chipTap.pressed ? Theme.highlight
                         : (Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.28) : Qt.rgba(0.46, 0.46, 0.5, 0.14))

                    Avatar {
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        source: chip.photo
                        letters: chip.letters
                        tint: chip.tint || Theme.accent
                    }
                    Text {
                        id: chipLabel
                        x: 36; anchors.verticalCenter: parent.verticalCenter
                        text: chip.firstName
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Icon {
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12
                        name: "cross"
                        color: Theme.grey
                    }
                    MouseArea {
                        id: chipTap
                        anchors.fill: parent
                        onClicked: page.toggleUser(chip.userId)
                    }
                }
            }
            Rectangle {
                visible: chips.count > 0
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }

        // search box
        Item {
            id: searchBox
            y: chipStrip.height
            width: parent.width; height: 48
            Rectangle {
                x: 14; y: 6
                width: parent.width - 28; height: 36; radius: 18
                color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
                Icon {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    name: "search"; width: 17; height: 17; color: Theme.grey
                }
                TextInput {
                    id: searchField
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 14
                    color: Theme.text; selectionColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onTextChanged: {
                        page.query = text.trim()
                        page.rebuildList()
                    }
                    Text {
                        visible: !searchField.text
                        text: Tr.t("Kimni qo'shmoqchisiz?")
                        color: Theme.grey
                        font: searchField.font
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }

        // contacts list with check circles
        ListView {
            id: pickList
            y: searchBox.y + searchBox.height
            width: parent.width; height: parent.height - y
            clip: true
            model: contactRows
            cacheBuffer: 400
            maximumFlickVelocity: 6000
            flickDeceleration: 2200
            bottomMargin: Math.max(osk.h, safe.bottom) + 16
            onMovementStarted: page.keyboardDown()

            delegate: Rectangle {
                id: prow
                required property var userId
                required property string name
                required property string photo
                required property string letters
                required property string tint
                readonly property bool chosen: page.pickedIds.indexOf(userId) >= 0
                width: pickList.width; height: 60
                color: ptap.pressed ? Theme.highlight : Theme.bg
                property string pic: photo
                Component.onCompleted: {
                    if (!pic && userId > 0)
                        page.store.userPhoto(page.store.users[userId], (p) => { if (prow) prow.pic = p })
                }

                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: prow.chosen ? Theme.accent : "transparent"
                    border.width: prow.chosen ? 0 : 1.5
                    border.color: Theme.separator
                    Icon {
                        visible: prow.chosen
                        anchors.centerIn: parent
                        width: 15; height: 15; name: "check"; color: "white"
                    }
                }
                Avatar {
                    x: 52; anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 44
                    source: prow.pic; letters: prow.letters; tint: prow.tint || Theme.accent
                }
                Text {
                    x: 108; y: 10
                    width: parent.width - x - 14
                    elide: Text.ElideRight
                    text: prow.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    x: 108; y: 32
                    width: parent.width - x - 14
                    elide: Text.ElideRight
                    readonly property string st: page.store.seen >= 0 ? page.store.userStatus(page.store.users[prow.userId], page.now) : ""
                    text: st
                    color: st === Tr.t("onlayn") ? Theme.accent : Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Rectangle {
                    x: 108; anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
                MouseArea {
                    id: ptap
                    anchors.fill: parent
                    onClicked: page.toggleUser(prow.userId)
                }
            }
        }

        Text {
            visible: page.loaded && contactRows.count === 0
            y: searchBox.y + searchBox.height + 90
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.query ? Tr.t("Hech narsa topilmadi") : Tr.t("Kontaktlar yo'q")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    // ---- STEP 2: group photo + title + selected members summary ----
    Flickable {
        id: step2
        visible: page.step === 2
        y: bar.height
        width: parent.width; height: parent.height - y
        clip: true
        contentHeight: step2Col.height + 40 + Math.max(osk.h, safe.bottom)
        onMovementStarted: page.keyboardDown()

        Column {
            id: step2Col
            y: 16
            width: parent.width
            spacing: 22

            SettingsGroup {
                Item {
                    width: parent.width; height: 84
                    // circular photo picker
                    Rectangle {
                        id: camCircle
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 60; height: 60; radius: 30
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        visible: page.photo === ""
                        Icon {
                            anchors.centerIn: parent
                            width: 26; height: 26
                            name: "camera"
                            color: Theme.accent
                        }
                    }
                    Avatar {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 60; height: 60
                        visible: page.photo !== ""
                        source: page.photo
                        letters: page.store.letters(groupName.text)
                        tint: Theme.accent
                    }
                    MouseArea {
                        x: 10; y: 6; width: 72; height: 72
                        enabled: !page.creating
                        onClicked: page.pickPhoto()
                    }

                    TextInput {
                        id: groupName
                        x: 92; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 16
                        enabled: !page.creating
                        maximumLength: 128
                        color: Theme.text; selectionColor: Theme.accent
                        font.family: Theme.font; font.pixelSize: 17
                        clip: true
                        onAccepted: page.createNow()
                        Text {
                            visible: !groupName.text
                            text: Tr.t("Guruh nomi")
                            color: Theme.grey
                            font: groupName.font
                        }
                    }
                }
            }

            Text {
                visible: page.errorText !== ""
                x: 32; width: parent.width - 64
                wrapMode: Text.Wrap
                text: page.errorText
                color: Theme.danger
                font.family: Theme.font; font.pixelSize: 14
            }

            SettingsGroup {
                title: Tr.n("%1 a'zo", chips.count)
                Repeater {
                    model: chips
                    Item {
                        id: mrow
                        required property int index
                        required property var userId
                        required property string fullName
                        required property string photo
                        required property string letters
                        required property string tint
                        width: parent ? parent.width : 300; height: 56
                        Avatar {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 40
                            source: mrow.photo; letters: mrow.letters; tint: mrow.tint || Theme.accent
                        }
                        Text {
                            x: 66; y: 9
                            width: parent.width - x - 16
                            elide: Text.ElideRight
                            text: mrow.fullName
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                        }
                        Text {
                            x: 66; y: 30
                            width: parent.width - x - 16
                            elide: Text.ElideRight
                            readonly property string st: page.store.seen >= 0 ? page.store.userStatus(page.store.users[mrow.userId], page.now) : ""
                            text: st
                            color: st === Tr.t("onlayn") ? Theme.accent : Theme.grey
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        Rectangle {
                            visible: mrow.index + 1 < chips.count
                            x: 66; anchors.bottom: parent.bottom
                            width: parent.width - x; height: 0.5
                            color: Theme.separator
                        }
                    }
                }
            }
        }
    }

    Alert { id: alert; parent: page; anchors.fill: parent }
    Component {
        id: sheetMaker
        AttachSheet {
            rights: ({ photos: true, videos: false, files: false, music: false, other: false, voice: false, round: false })
            onRefused: (text) => page.nav.say(Tr.t("Faqat rasm tanlang"))
            onSend: (picked) => {
                const p = picked.find((f) => f.kind === "photo")
                if (p)
                    page.photo = p.path
            }
        }
    }
}
