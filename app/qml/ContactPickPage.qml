// Pick Contact page (Telegram-iOS ContactSelectionController):
// Lists contacts (store.contacts) with local + searchContacts search; tapping a contact opens
// a confirmation sheet showing their name & phone number, then emits pickedContact(user) -> inputMessageContact.
pragma ComponentBehavior: Bound
import QtQuick

Page {
    id: page
    required property var chatId

    property bool loaded: false
    property int now: Date.now() / 1000
    property var allContacts: []
    property var searchUsers: []
    property string query: ""
    property int _searchSeq: 0
    property var confirmUser: null      // selected user awaiting confirmation

    signal pickedContact(var user)

    Component.onCompleted: reload()

    function reload() {
        now = Date.now() / 1000
        store.contacts((list) => {
            if (!page)
                return
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
        if (confirmUser) {
            confirmUser = null
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

    function userPhotoNow(u) {
        return store.userPhotoNow(u)
    }

    function fullNameOf(u) {
        if (!u)
            return ""
        return ((u.first_name || "") + " " + (u.last_name || "")).trim()
    }

    function phoneDisplay(u) {
        if (!u || !u.phone_number)
            return ""
        return store.formatPhone ? store.formatPhone(u.phone_number) : ("+" + u.phone_number)
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
            const full = fullNameOf(u)
            const un = u.usernames && u.usernames.active_usernames ? u.usernames.active_usernames.join(" ") : ""
            return store.fold(full + " " + un).indexOf(f) >= 0
                || (digits.length >= 3 && u.phone_number && u.phone_number.indexOf(digits) >= 0)
        })
        searchUsers = local
        rebuild()
        store.searchContacts(q, 50, (list) => {
            if (!page || seq !== page._searchSeq)
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

    function rebuild() {
        people.clear()
        const src = query ? searchUsers : allContacts
        for (const u of src) {
            const full = fullNameOf(u)
            const ph = phoneDisplay(u)
            people.append({
                userId: u.id,
                name: full,
                sub: ph || store.userStatus(u, now),
                photo: userPhotoNow(u),
                letters: store.letters(full),
                tint: store.tints[Math.abs(u.id) % store.tints.length]
            })
            store.askUserPhoto(u, people, "userId")
        }
    }

    function pickUserById(uid) {
        const src = query ? searchUsers : allContacts
        let u = src.find((x) => x.id === uid) || store.users[uid]
        if (!u)
            return
        keyboardDown()
        confirmUser = u
    }

    function confirmSend() {
        const u = confirmUser
        if (!u)
            return
        confirmUser = null
        pickedContact(u)
    }

    ListModel { id: people }

    // ---- Top bar ----
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: Theme.bg
        z: 5
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea { id: backHit; width: 72; height: parent.height; onClicked: page.nav.pop() }
        Text {
            anchors.centerIn: parent
            text: Tr.t("Kontakt yuborish")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
    }

    // ---- Search field ----
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
                Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: Theme.grey; opacity: 0.45 }
                Icon { anchors.centerIn: parent; width: 11; height: 11; name: "cross"; color: Theme.bg }
                MouseArea { anchors.fill: parent; onClicked: searchField.text = "" }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
    }

    // ---- Contacts list ----
    ListView {
        id: list
        y: searchWrap.y + searchWrap.height
        width: parent.width; height: parent.height - y
        clip: true
        model: people
        bottomMargin: Math.max(osk.h, safe.bottom)
        onMovementStarted: page.keyboardDown()

        delegate: Rectangle {
            id: row
            required property var userId
            required property string name
            required property string sub
            required property string photo
            required property string letters
            required property string tint
            width: list.width; height: 62
            color: tap.pressed ? Theme.highlight : Theme.bg
            property string pic: photo
            Component.onCompleted: {
                if (!pic && userId > 0)
                    store.userPhoto(store.users[userId], (path) => { if (row) row.pic = path })
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
                text: row.sub
                elide: Text.ElideRight
                color: Theme.grey
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
                onClicked: page.pickUserById(row.userId)
            }
        }
    }

    Text {
        visible: page.loaded && people.count === 0 && !searchTimer.running
        y: searchWrap.y + searchWrap.height + 90
        anchors.horizontalCenter: parent.horizontalCenter
        text: page.query ? Tr.t("Hech narsa topilmadi") : Tr.t("Kontaktlar yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    // ---- Confirmation bottom sheet (name, phone number, "Kontaktni yuborish") ----
    Item {
        id: confirmSheet
        anchors.fill: parent
        z: 30
        visible: confirmDim.opacity > 0

        Rectangle {
            id: confirmDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: page.confirmUser ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; onClicked: page.confirmUser = null }
        }

        Rectangle {
            id: confirmCard
            width: parent.width
            height: confirmCol.height + 24 + safe.bottom
            y: page.confirmUser ? parent.height - height : parent.height + 16
            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            radius: 14
            color: Theme.bg
            MouseArea { anchors.fill: parent }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6; width: 36; height: 5; radius: 2.5
                color: Theme.separator
            }
            Icon {
                anchors.right: parent.right; anchors.rightMargin: 16
                y: 18; width: 20; height: 20
                name: "cross"; color: Theme.grey
                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: page.confirmUser = null }
            }

            Column {
                id: confirmCol
                x: 16; y: 18
                width: parent.width - 32
                spacing: 14

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Kontaktni yuborish")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }

                Rectangle {
                    width: parent.width
                    height: 76; radius: 12
                    color: Theme.card
                    Avatar {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 50; height: 50
                        source: page.userPhotoNow(page.confirmUser)
                        letters: store.letters(page.fullNameOf(page.confirmUser))
                        tint: page.confirmUser ? store.tints[Math.abs(page.confirmUser.id) % store.tints.length] : Theme.accent
                    }
                    Column {
                        x: 76; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 14
                        spacing: 3
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: page.fullNameOf(page.confirmUser)
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: page.phoneDisplay(page.confirmUser) || Tr.t("Telefon raqami yashirin")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 14
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 50; radius: 25
                    color: sendContactHit.pressed ? Qt.darker(Theme.accent, 1.12) : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: Tr.t("Kontaktni yuborish")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: sendContactHit
                        anchors.fill: parent
                        onClicked: page.confirmSend()
                    }
                }
            }
        }
    }
}
