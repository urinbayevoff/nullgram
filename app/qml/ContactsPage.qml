// The contacts: search (local + searchContacts), sorting (last seen / name), quick actions
// (New Group, New Channel, Add Contact by phone), and tapping a contact opens their chat.
pragma ComponentBehavior: Bound
import QtQuick

Page {
    id: page
    property bool loaded: false
    property int now: Date.now() / 1000
    property var allContacts: []        // [user] from getContacts
    property var searchUsers: []        // [user] from searchContacts when query is non-empty
    property string sortMode: "seen"    // "seen" (last seen / online first) | "name" (alphabetical)
    property string query: ""
    property int _searchSeq: 0
    property bool sortOpen: false

    onVisibleChanged: if (visible) {
        now = Date.now() / 1000
        if (!loaded)
            reload()
        else
            rebuild()
    }

    function reload() {
        now = Date.now() / 1000
        store.contacts((list) => {
            page.allContacts = list
            page.loaded = true
            page.rebuild()
        })
    }

    function keyboardDown() {
        searchField.focus = false
        if (osk.h > 0)
            osk.hide()
    }

    function dismiss() {
        if (sortOpen) {
            sortOpen = false
            return true
        }
        if (searchField.text !== "") {
            searchField.text = ""
            keyboardDown()
            return true
        }
        if (osk.h > 0) {
            keyboardDown()
            return true
        }
        return false
    }

    function openPage(file, props) {
        keyboardDown()
        const c = Qt.createComponent(file)
        if (c.status === Component.Error) {
            console.warn("nullgram:", c.errorString())
            return null
        }
        return nav.push(c, props || {})
    }

    function openAddContact() {
        const p = openPage("ContactPage.qml", { adding: true, byPhone: true })
        if (p)
            p.added.connect(() => page.reload())
    }

    function setSort(mode) {
        sortMode = mode
        sortOpen = false
        rebuild()
    }

    function userPhotoNow(u) {
        const f = u && u.profile_photo && u.profile_photo.small
        return f && f.local && f.local.is_downloading_completed ? f.local.path : ""
    }

    Timer {
        id: searchTimer
        interval: 220
        onTriggered: page.runSearch(page.query)
    }

    function runSearch(q) {
        const seq = ++_searchSeq
        searchUsers = []
        if (!q) {
            rebuild()
            return
        }
        const f = store.fold(q)
        const digits = q.replace(/[^0-9]/g, "")
        const local = allContacts.filter((u) => {
            const full = (u.first_name + " " + u.last_name).trim()
            const un = u.usernames && u.usernames.active_usernames ? u.usernames.active_usernames.join(" ") : ""
            return store.fold(full + " " + un).indexOf(f) >= 0
                || (digits.length >= 3 && u.phone_number && u.phone_number.indexOf(digits) >= 0)
        })
        searchUsers = local
        rebuild()
        store.searchContacts(q, 50, (list) => {
            if (seq !== page._searchSeq)
                return
            const seen = {}
            const merged = []
            for (const u of local.concat(list)) {
                if (!seen[u.id]) {
                    seen[u.id] = true
                    merged.push(u)
                }
            }
            page.searchUsers = merged
            page.rebuild()
        })
    }

    function sortedUsers(list) {
        const copy = list.slice()
        const t = now
        if (sortMode === "seen") {
            copy.sort((a, b) => {
                const diff = store.userLastSeenRank(b, t) - store.userLastSeenRank(a, t)
                if (diff !== 0)
                    return diff
                const na = store.fold(a.first_name + " " + a.last_name)
                const nb = store.fold(b.first_name + " " + b.last_name)
                return na < nb ? -1 : na > nb ? 1 : 0
            })
        } else {
            copy.sort((a, b) => {
                const na = store.fold(a.first_name + " " + a.last_name)
                const nb = store.fold(b.first_name + " " + b.last_name)
                return na < nb ? -1 : na > nb ? 1 : 0
            })
        }
        return copy
    }

    function rebuild() {
        people.clear()
        const src = query ? searchUsers : allContacts
        for (const u of sortedUsers(src)) {
            const full = (u.first_name + " " + u.last_name).trim()
            people.append({
                userId: u.id, name: full,
                photo: userPhotoNow(u), letters: store.letters(full),
                tint: store.tints[Math.abs(u.id) % store.tints.length]
            })
        }
    }

    ListModel { id: people }

    // ---- top header bar ----
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: Theme.bg
        z: 5

        Text {
            id: sortBtn
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: Tr.t("Saralash")
            color: Theme.accent
            opacity: sortHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 16
        }
        MouseArea {
            id: sortHit
            width: sortBtn.width + 32; height: parent.height
            onClicked: { page.keyboardDown(); page.sortOpen = true }
        }

        Text {
            anchors.centerIn: parent
            text: Tr.t("Kontaktlar")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }

        Icon {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24
            name: "plus"
            color: Theme.accent
            opacity: addHit.pressed ? 0.4 : 1
        }
        MouseArea {
            id: addHit
            anchors.right: parent.right
            width: 56; height: parent.height
            onClicked: page.openAddContact()
        }
    }

    // ---- search field ----
    Item {
        id: searchWrap
        y: bar.height
        width: parent.width; height: 50
        z: 5
        Rectangle {
            x: 14; y: 4
            width: parent.width - 28; height: 38; radius: 19
            color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)
            Icon {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                name: "search"; width: 18; height: 18; color: Theme.grey
            }
            TextInput {
                id: searchField
                x: 38; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (clearBtn.visible ? 36 : 14)
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: {
                    page.query = text.trim()
                    if (!page.query) {
                        searchTimer.stop()
                        page.runSearch("")
                    } else {
                        searchTimer.restart()
                    }
                }
                Text {
                    visible: !searchField.text
                    text: Tr.t("Qidiruv")
                    color: Theme.grey
                    font: searchField.font
                }
            }
            Item {
                id: clearBtn
                visible: searchField.text !== ""
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: Theme.grey; opacity: 0.45
                }
                Icon {
                    anchors.centerIn: parent
                    width: 11; height: 11; name: "cross"; color: Theme.bg
                }
                MouseArea { anchors.fill: parent; onClicked: searchField.text = "" }
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 0.5
            color: Theme.separator
        }
    }

    // ---- contacts list ----
    ListView {
        id: list
        y: searchWrap.y + searchWrap.height
        width: parent.width; height: parent.height - y
        clip: true
        model: people
        cacheBuffer: 600
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        onMovementStarted: page.keyboardDown()

        header: Column {
            width: list.width
            visible: page.query === ""
            height: visible ? implicitHeight : 0

            component ActionRow: Rectangle {
                id: arow
                property string iconName: ""
                property string label: ""
                signal tapped()
                width: list.width; height: 48
                color: ahit.pressed ? Theme.highlight : Theme.bg
                Icon {
                    x: 22; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                    name: arow.iconName
                    color: Theme.accent
                }
                Text {
                    x: 68; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 16
                    elide: Text.ElideRight
                    text: arow.label
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                Rectangle {
                    x: 68; anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
                MouseArea { id: ahit; anchors.fill: parent; onClicked: arow.tapped() }
            }

            ActionRow {
                iconName: "group"
                label: Tr.t("Yangi guruh")
                onTapped: page.openPage("NewGroupPage.qml", {})
            }
            ActionRow {
                iconName: "channel"
                label: Tr.t("Yangi kanal")
                onTapped: page.openPage("NewChannelPage.qml", {})
            }
            ActionRow {
                iconName: "adduser"
                label: Tr.t("Kontakt qo'shish")
                onTapped: page.openAddContact()
            }

            Rectangle {
                width: list.width; height: 30
                color: Theme.dark ? "#1c1c1d" : "#f2f2f7"
                Text {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t(page.sortMode === "seen" ? "Oxirgi faollik bo'yicha" : "Ism bo'yicha").toUpperCase()
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { page.keyboardDown(); page.sortOpen = true }
                }
            }
        }

        // room over the floating TabBar + safe.bottom (or over keyboard when open)
        footer: Item { width: 1; height: Math.max(osk.h, 96 + safe.bottom) }

        delegate: Rectangle {
            id: row
            required property var userId
            required property string name
            required property string photo
            required property string letters
            required property string tint
            width: list.width; height: 62
            color: tap.pressed ? Theme.highlight : Theme.bg
            property string pic: photo
            Component.onCompleted: {
                if (!pic && userId > 0)
                    page.store.userPhoto(page.store.users[userId], (path) => { if (row) row.pic = path })
            }
            Avatar {
                x: 14; y: 8
                width: 46; height: 46
                source: row.pic; letters: row.letters; tint: row.tint
            }
            Text {
                x: 72; y: 11
                width: parent.width - x - 14
                text: row.name
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                x: 72; y: 33
                width: parent.width - x - 14
                readonly property string s: page.store.seen >= 0 ? page.store.userStatus(page.store.users[row.userId], page.now) : ""
                text: s
                elide: Text.ElideRight
                color: s === Tr.t("onlayn") ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }
            Rectangle {
                x: 72; y: parent.height - 0.5
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: tap
                anchors.fill: parent
                onClicked: {
                    page.keyboardDown()
                    page.store.chatWith(row.userId, (id) => page.nav.pushChat(chatPage, { chatId: id }))
                }
            }
        }
    }

    Text {
        visible: page.loaded && people.count === 0 && !searchTimer.running
        y: searchWrap.y + searchWrap.height + (page.query ? 90 : 210)
        anchors.horizontalCenter: parent.horizontalCenter
        text: page.query ? Tr.t("Hech narsa topilmadi") : Tr.t("Kontaktlar yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    // ---- iOS sort action sheet (over the whole window including TabBar, above safe.bottom) ----
    Item {
        id: sortSheet
        parent: page.nav || page
        anchors.fill: parent
        z: 100
        visible: sortDim.opacity > 0
        Rectangle {
            id: sortDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: page.sortOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent; onClicked: page.sortOpen = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: page.sortOpen ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            spacing: 8
            Rectangle {
                width: parent.width
                height: sortCol.height
                radius: 14
                color: Theme.menu
                clip: true
                Column {
                    id: sortCol
                    width: parent.width
                    Item {
                        width: parent.width; height: 40
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Saralash")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
                    }
                    Repeater {
                        model: [
                            { mode: "seen", label: Tr.t("Oxirgi faollik bo'yicha") },
                            { mode: "name", label: Tr.t("Ism bo'yicha") }
                        ]
                        Rectangle {
                            id: opt
                            required property int index
                            required property var modelData
                            width: parent.width; height: 54
                            color: optHit.pressed ? Theme.highlight : "transparent"
                            Text {
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                text: opt.modelData.label
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 17
                            }
                            Icon {
                                visible: page.sortMode === opt.modelData.mode
                                anchors.right: parent.right; anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20
                                name: "check"
                                color: Theme.accent
                            }
                            Rectangle {
                                visible: opt.index === 0
                                anchors.bottom: parent.bottom; width: parent.width; height: 0.5
                                color: Theme.separator
                            }
                            MouseArea {
                                id: optHit
                                anchors.fill: parent
                                onClicked: page.setSort(opt.modelData.mode)
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 54; radius: 14
                color: cancelSortHit.pressed ? Theme.highlight : Theme.menu
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                }
                MouseArea { id: cancelSortHit; anchors.fill: parent; onClicked: page.sortOpen = false }
            }
        }
    }

    Component { id: chatPage; ChatPage {} }
}
