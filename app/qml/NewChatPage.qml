// New Message (Telegram-iOS's Contacts / Compose screen): search over contacts (searchContacts)
// and global public chats (searchPublicChats); at the top «Yangi guruh», «Yangi kanal» and
// «Kontakt qo'shish», then the contacts list. Tapping a contact opens their chat (createPrivateChat).
pragma ComponentBehavior: Bound
import QtQuick

Page {
    id: page
    property int now: Date.now() / 1000
    property bool loaded: false
    property var allContacts: []        // [user] loaded from store.contacts
    property var searchUsers: []        // [user] from searchContacts
    property var globalIds: []          // [chatId] from searchPublicChats
    property string query: ""
    property int _searchSeq: 0
    property bool opening: false

    Component.onCompleted: loadContacts()

    function loadContacts() {
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
            p.added.connect(() => page.loadContacts())
    }

    function openUserChat(userId) {
        if (opening)
            return
        opening = true
        keyboardDown()
        store.chatWith(userId, (chatId) => {
            page.opening = false
            if (chatId)
                page.nav.openCreatedChat(chatId)
        })
    }

    function openPublicChat(chatId) {
        if (opening)
            return
        keyboardDown()
        nav.openCreatedChat(chatId)
    }

    function userPhotoNow(u) {
        const f = u && u.profile_photo && u.profile_photo.small
        return f && f.local && f.local.is_downloading_completed ? f.local.path : ""
    }

    function chatUsername(c) {
        if (!c || !c.type)
            return ""
        let names = null
        if (c.type["@type"] === "chatTypeSupergroup") {
            const g = store.groups["s" + c.type.supergroup_id]
            names = g && g.usernames
        } else if (c.type["@type"] === "chatTypePrivate") {
            const u = store.users[c.type.user_id]
            names = u && u.usernames
        }
        return names && names.active_usernames && names.active_usernames.length ? "@" + names.active_usernames[0] : ""
    }

    Timer {
        id: searchTimer
        interval: 220
        onTriggered: page.runSearch(page.query)
    }

    function runSearch(q) {
        const seq = ++_searchSeq
        searchUsers = []
        globalIds = []
        if (!q) {
            rebuild()
            return
        }
        // immediate local match (handles Uzbek Latin/Cyrillic via store.fold)
        const f = store.fold(q)
        const local = allContacts.filter((u) => {
            const full = (u.first_name + " " + u.last_name).trim()
            const un = u.usernames && u.usernames.active_usernames ? u.usernames.active_usernames.join(" ") : ""
            return store.fold(full + " " + un).indexOf(f) >= 0 || (u.phone_number && u.phone_number.indexOf(q.replace(/[^0-9]/g, "")) >= 0 && q.replace(/[^0-9]/g, "").length >= 3)
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
        if (q.replace(/^@/, "").length >= 4) {
            store.searchPublic(q, (ids) => {
                if (seq !== page._searchSeq)
                    return
                page.globalIds = ids
                page.rebuild()
            })
        }
    }

    function rebuild() {
        rows.clear()
        const pushHead = (label) => rows.append({
            kind: "head", userId: 0, chatId: 0, title: label, sub: "", photo: "", letters: "", tint: "", icon: ""
        })
        const pushUser = (u) => {
            const full = (u.first_name + " " + u.last_name).trim()
            rows.append({
                kind: "user", userId: u.id, chatId: 0, title: full,
                sub: store.userStatus(u, now),
                photo: userPhotoNow(u), letters: store.letters(full),
                tint: store.tints[Math.abs(u.id) % store.tints.length], icon: ""
            })
        }
        if (!query) {
            rows.append({ kind: "action", userId: 0, chatId: 0, title: Tr.t("Yangi guruh"), sub: "", photo: "", letters: "", tint: "", icon: "group" })
            rows.append({ kind: "action", userId: 0, chatId: 0, title: Tr.t("Yangi kanal"), sub: "", photo: "", letters: "", tint: "", icon: "channel" })
            rows.append({ kind: "action", userId: 0, chatId: 0, title: Tr.t("Kontakt qo'shish"), sub: "", photo: "", letters: "", tint: "", icon: "adduser" })
            if (allContacts.length > 0) {
                pushHead(Tr.t("Kontaktlar"))
                for (const u of allContacts)
                    pushUser(u)
            }
            return
        }
        if (searchUsers.length > 0) {
            pushHead(Tr.t("Kontaktlar"))
            for (const u of searchUsers)
                pushUser(u)
        }
        if (globalIds.length > 0) {
            pushHead(Tr.t("Global qidiruv"))
            for (const cid of globalIds) {
                const c = store.chats[cid]
                if (!c)
                    continue
                const sub = chatUsername(c) || store.status(c, now)
                rows.append({
                    kind: "chat", userId: 0, chatId: cid, title: store.title(c), sub: sub,
                    photo: store.photoPath(c), letters: store.letters(c.title),
                    tint: store.tints[Math.abs(cid) % store.tints.length], icon: ""
                })
            }
        }
    }

    ListModel { id: rows }

    // ---- top bar ----
    Rectangle {
        id: bar
        width: parent.width; height: 56
        color: Theme.bg
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            color: Theme.accent
            opacity: backHit.pressed ? 0.4 : 1
            font.family: Theme.font; font.pixelSize: 34
        }
        MouseArea {
            id: backHit
            width: 72; height: parent.height
            onClicked: { page.keyboardDown(); page.nav.pop() }
        }
        Text {
            anchors.centerIn: parent
            text: Tr.t("Yangi xabar")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
        }
    }

    // ---- search field ----
    Item {
        id: searchWrap
        y: bar.height
        width: parent.width; height: 50
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
                color: Theme.text
                selectionColor: Theme.accent
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
                    color: Theme.grey
                    opacity: 0.45
                }
                Icon {
                    anchors.centerIn: parent
                    width: 11; height: 11; name: "cross"; color: Theme.bg
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: searchField.text = ""
                }
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 0.5
            color: Theme.separator
        }
    }

    // ---- list of actions, contacts and global results ----
    ListView {
        id: list
        y: searchWrap.y + searchWrap.height
        width: parent.width
        height: parent.height - y
        clip: true
        model: rows
        cacheBuffer: 400
        maximumFlickVelocity: 6000
        flickDeceleration: 2200
        bottomMargin: Math.max(osk.h, safe.bottom) + 16
        onMovementStarted: page.keyboardDown()

        delegate: Rectangle {
            id: row
            required property string kind
            required property var userId
            required property var chatId
            required property string title
            required property string sub
            required property string photo
            required property string letters
            required property string tint
            required property string icon
            width: list.width
            height: kind === "head" ? 30 : kind === "action" ? 50 : 60
            color: kind === "head" ? (Theme.dark ? "#1c1c1d" : "#f2f2f7")
                 : tap.pressed ? Theme.highlight : Theme.bg

            property string pic: photo
            Component.onCompleted: {
                if (kind === "user" && !pic && userId > 0)
                    page.store.userPhoto(page.store.users[userId], (p) => { if (row) row.pic = p })
            }

            // section header
            Text {
                visible: row.kind === "head"
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: row.title.toUpperCase()
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }

            // action row (New Group / New Channel / Add Contact)
            Icon {
                visible: row.kind === "action"
                x: 22; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24
                name: row.icon
                color: Theme.accent
            }
            Text {
                visible: row.kind === "action"
                x: 68; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 16
                elide: Text.ElideRight
                text: row.title
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
            }

            // user or global chat row
            Avatar {
                visible: row.kind === "user" || row.kind === "chat"
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                source: row.pic
                letters: row.letters
                tint: row.tint || Theme.accent
            }
            Text {
                visible: row.kind === "user" || row.kind === "chat"
                x: 70; y: 10
                width: parent.width - x - 14
                elide: Text.ElideRight
                text: row.title
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                visible: row.kind === "user" || row.kind === "chat"
                x: 70; y: 32
                width: parent.width - x - 14
                elide: Text.ElideRight
                text: row.kind === "user" ? (page.store.seen >= 0 ? page.store.userStatus(page.store.users[row.userId], page.now) : "") : row.sub
                color: text === Tr.t("onlayn") ? Theme.accent : Theme.grey
                font.family: Theme.font; font.pixelSize: 14
            }

            Rectangle {
                visible: row.kind !== "head"
                x: row.kind === "action" ? 68 : 70
                anchors.bottom: parent.bottom
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }

            MouseArea {
                id: tap
                anchors.fill: parent
                enabled: row.kind !== "head"
                onClicked: {
                    if (row.kind === "action") {
                        if (row.icon === "group")
                            page.openPage("NewGroupPage.qml", {})
                        else if (row.icon === "channel")
                            page.openPage("NewChannelPage.qml", {})
                        else if (row.icon === "adduser")
                            page.openAddContact()
                    } else if (row.kind === "user") {
                        page.openUserChat(row.userId)
                    } else if (row.kind === "chat") {
                        page.openPublicChat(row.chatId)
                    }
                }
            }
        }
    }

    Text {
        visible: page.query !== "" && rows.count === 0 && !searchTimer.running
        y: searchWrap.y + searchWrap.height + 90
        anchors.horizontalCenter: parent.horizontalCenter
        text: Tr.t("Hech narsa topilmadi")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    Text {
        visible: page.loaded && page.query === "" && page.allContacts.length === 0
        y: searchWrap.y + searchWrap.height + 210
        anchors.horizontalCenter: parent.horizontalCenter
        text: Tr.t("Kontaktlar yo'q")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
}
