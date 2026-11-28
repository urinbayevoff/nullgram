// A folder made or changed, as Telegram-iOS's ChatListFilterPresetController: a new one under its animation (ChatListNewFolder, 96,
// once); «PAPKA NOMI» (12 letters at most); «KIRITILGAN CHATLAR»: «Chat qo'shish» (FolderChatsPage: the chat types and the chats),
// the types (ChatListFilterPresetCategoryItem: their pictures at 40, corners 12) and the chats (avatars at 40; past 6, five and
// «Yana N ta chatni ko'rsatish»), each swiped left for «O'chirish»; «CHIQARILGAN CHATLAR» the same with muted, read, archived;
// «PAPKA RANGI» (its tag in the list: Premium). «Tayyor» (bold, once it has a name and something in it): createChatFolder /
// editChatFolder. Left changed, it asks first. A new one named after the one type it holds while not named by hand.
import QtQuick

SubPage {
    id: page
    property int folderId: 0            // 0: a new one
    property var f: null                // the chatFolder as changed here
    property string was: ""             // it as it came (changed: asked before leaving)
    property bool named: false          // its name typed (no more named after its one type)
    property string revealed: ""        // the row showing «O'chirish»: "in:<flag>", "out:<flag>", "chat:<id>", "not:<id>"
    property bool moreIn: false
    property bool moreOut: false
    property bool saving: false
    property var inviteLinks: []
    property bool linkBusy: false
    readonly property bool premium: !!store.me && !!store.me.is_premium
    readonly property var included: f ? f.pinned_chat_ids.concat(f.included_chat_ids) : []
    readonly property bool changed: !!f && JSON.stringify(f) !== was
    readonly property bool complete: !!f && f.name.text.text.trim() !== "" && (folderId !== 0
        || page.ins.some((c) => f[c[0]]) || included.length > 0)
    readonly property var ins: [["include_contacts", "contacts", Tr.t("Kontaktlar")], ["include_non_contacts", "noncontacts", Tr.t("Kontakt bo'lmaganlar")],
                                ["include_groups", "groups", Tr.t("Guruhlar")], ["include_channels", "channels", Tr.t("Kanallar")],
                                ["include_bots", "bots", Tr.t("Botlar")]]
    readonly property var outs: [["exclude_muted", "muted", Tr.t("Ovozsizlar")], ["exclude_read", "read", Tr.t("O'qilganlar")],
                                 ["exclude_archived", "archived", Tr.t("Arxivdagilar")]]
    title: folderId ? Tr.t("Papkani tahrirlash") : Tr.t("Yangi papka")
    action: Tr.t("Tayyor")
    actionBold: true
    actionOn: complete && !saving
    onActed: save()
    guard: () => page.askLeave()

    Component.onCompleted: {
        if (!folderId) {
            f = { "@type": "chatFolder", name: { "@type": "chatFolderName", text: { "@type": "formattedText", text: "", entities: [] },
                  animate_custom_emoji: true }, icon: null, color_id: -1, is_shareable: false, pinned_chat_ids: [], included_chat_ids: [],
                  excluded_chat_ids: [], exclude_muted: false, exclude_read: false, exclude_archived: false, include_contacts: false,
                  include_non_contacts: false, include_bots: false, include_groups: false, include_channels: false }
            was = JSON.stringify(f)
            return
        }
        named = true
        store.send({ "@type": "getChatFolder", chat_folder_id: folderId }, (r) => {
            if (!page || r["@type"] !== "chatFolder")
                return
            delete r["@extra"]
            page.was = JSON.stringify(r)
            page.f = r
            page.fetch(r.pinned_chat_ids.concat(r.included_chat_ids, r.excluded_chat_ids))
            page.loadInviteLinks()
        })
    }
    function loadInviteLinks() {
        if (!folderId)
            return
        store.getFolderInviteLinks(folderId, (links) => {
            if (page)
                page.inviteLinks = links || []
        })
    }
    function copyLink(url) {
        if (!url)
            return
        clipCopy.text = url
        clipCopy.selectAll()
        clipCopy.copy()
        say(Tr.t("Havola nusxalandi"))
    }
    function shareFolderLink() {
        if (!folderId || linkBusy)
            return
        if (changed)
            return say(Tr.t("Avval papkadagi o'zgarishlarni saqlang"))
        linkBusy = true
        store.getChatsForFolderInviteLink(folderId, (shareIds) => {
            if (!page)
                return
            const ids = (shareIds && shareIds.length) ? shareIds : page.included
            if (!ids.length) {
                page.linkBusy = false
                return page.say(Tr.t("Ulashish uchun kamida bitta chat kerak"))
            }
            store.createFolderInviteLink(page.folderId, "", ids, (linkObj, err) => {
                if (!page)
                    return
                page.linkBusy = false
                if (!linkObj || !linkObj.invite_link)
                    return page.say(err || Tr.t("Havola yaratib bo'lmadi"))
                page.inviteLinks = page.inviteLinks.concat([linkObj])
                page.copyLink(linkObj.invite_link)
            })
        })
    }
    function removeInviteLink(url) {
        revealed = ""
        if (!folderId || !url)
            return
        store.deleteFolderInviteLink(folderId, url, (ok, err) => {
            if (!page)
                return
            if (!ok)
                return page.say(err || Tr.t("Bo'lmadi"))
            page.inviteLinks = page.inviteLinks.filter((x) => x.invite_link !== url)
            page.say(Tr.t("Havola o'chirildi"))
        })
    }
    // chats TDLib has not told us of yet (not in the lists loaded)
    property int known: 0               // (bumped as they come: the rows read it)
    function fetch(ids) {
        for (const id of ids)
            if (!store.chats[id])
                store.send({ "@type": "getChat", chat_id: id }, () => { if (page) page.known++ })
    }
    function peer(id) {
        known
        const c = store.chats[id]
        return c ? { title: store.title(c), photo: store.photoPath(c), letters: store.letters(c.title),
                     tint: store.tints[Math.abs(id) % store.tints.length], saved: store.isSaved(c) }
                 : { title: "…", photo: "", letters: "", tint: Theme.grey, saved: false }
    }

    // a change: a copy, so the bindings see it
    function set(fields) {
        const n = Object.assign({}, f, fields)
        if (!folderId && !named)
            n.name = Object.assign({}, n.name, { text: { "@type": "formattedText", text: autoName(n), entities: [] } })
        f = n
    }
    // ChatListFolder_Name…: a new folder of one type, or of all but the muted or the read ones, named after it
    function autoName(n) {
        const on = ins.filter((c) => n[c[0]])
        if (n.pinned_chat_ids.length || n.included_chat_ids.length || n.excluded_chat_ids.length)
            return ""
        if (on.length === ins.length && n.exclude_muted && !n.exclude_read)
            return Tr.t("Ovozlilar")
        if (on.length === ins.length && n.exclude_read && !n.exclude_muted)
            return Tr.t("O'qilmaganlar")
        if (on.length !== 1 || n.exclude_muted || n.exclude_read)
            return ""
        return ({ include_contacts: Tr.t("Kontaktlar"), include_non_contacts: Tr.t("Kontakt bo'lmaganlar"), include_groups: Tr.t("Guruhlar"),
                  include_channels: Tr.t("Kanallar"), include_bots: Tr.t("Botlar") })[on[0][0]]
    }
    function drop(key) {
        revealed = ""
        const [kind, v] = [key.slice(0, key.indexOf(":")), key.slice(key.indexOf(":") + 1)]
        if (kind === "link")
            return removeInviteLink(v)
        if (kind === "in" || kind === "out")
            set({ [v]: false })
        else if (kind === "chat")
            set({ pinned_chat_ids: f.pinned_chat_ids.filter((id) => String(id) !== v),
                  included_chat_ids: f.included_chat_ids.filter((id) => String(id) !== v) })
        else
            set({ excluded_chat_ids: f.excluded_chat_ids.filter((id) => String(id) !== v) })
    }
    property Component chooser: null
    function choose(excluding) {
        revealed = ""
        if (!chooser)
            chooser = Qt.createComponent("FolderChatsPage.qml")
        const types = (excluding ? outs : ins).map((c) => c.concat([!!f[c[0]]]))
        const p = nav.push(chooser, { excluding: excluding, types: types, chosen: excluding ? f.excluded_chat_ids : included })
        if (p)
            p.done.connect((flags, ids) => {
                if (!page)
                    return
                const fields = Object.assign({}, flags)
                if (excluding) {
                    fields.excluded_chat_ids = ids
                    fields.pinned_chat_ids = f.pinned_chat_ids.filter((id) => ids.indexOf(id) < 0)
                    fields.included_chat_ids = f.included_chat_ids.filter((id) => ids.indexOf(id) < 0)
                } else {
                    fields.pinned_chat_ids = f.pinned_chat_ids.filter((id) => ids.indexOf(id) >= 0)
                    fields.included_chat_ids = ids.filter((id) => fields.pinned_chat_ids.indexOf(id) < 0)
                    fields.excluded_chat_ids = f.excluded_chat_ids.filter((id) => ids.indexOf(id) < 0)
                }
                page.set(fields)
            })
    }
    function setColor(id) {
        if (!premium)
            return say(Tr.t("Papka rangini tanlash uchun Telegram Premium'ga obuna bo'ling."))
        f = Object.assign({}, f, { color_id: id })
    }

    function save() {
        if (!complete || saving)
            return
        saving = true
        const folder = Object.assign({}, f)
        folder.name = Object.assign({}, f.name, { text: { "@type": "formattedText", text: f.name.text.text.trim(), entities: [] } })
        const req = folderId ? { "@type": "editChatFolder", chat_folder_id: folderId, folder: folder }
                             : { "@type": "createChatFolder", folder: folder }
        store.send(req, (r) => {
            if (!page)
                return
            page.saving = false
            if (r["@type"] === "error")
                return page.say(r.message === "CHATLISTS_TOO_MUCH" || r.message === "FILTER_INCLUDE_TOO_MUCH" || /LIMIT|TOO_MUCH/.test(r.message)
                                ? Tr.t("Chegaraga yetdingiz: papkalar yoki ulardagi chatlar juda ko'p.") : r.message)
            page.was = JSON.stringify(page.f)
            page.nav.pop()
        })
    }
    function askLeave() {
        if (!changed)
            return false
        alert.show("", Tr.t("Papka o'zgartirildi. O'zgarishlar bekor qilinsinmi?"),
                   [{ t: Tr.t("Yo'q") }, { t: Tr.t("Saqlamaslik"), red: true, run: () => { page.was = JSON.stringify(page.f); page.nav.pop() } }])
        return true
    }
    function dismiss() {
        if (alert.open)
            alert.open = false
        else if (revealed !== "")
            revealed = ""
        else
            return askLeave()
        return true
    }

    // ---- a new one's animation ----
    Item {
        visible: !page.folderId
        width: parent.width; height: 92 - 16 - 8
        Lottie {
            id: anim
            anchors.horizontalCenter: parent.horizontalCenter
            y: -10 - 16
            width: 96; height: 96
            path: Qt.resolvedUrl("animations/ChatListNewFolder.tgs").toString().replace(/^file:\/\//, "")
            once: true
            MouseArea { anchors.fill: parent; onClicked: anim.replay() }
        }
    }

    // ---- its name ----
    SettingsGroup {
        title: Tr.t("Papka nomi")
        Item {
            width: parent.width; height: 46
            TextInput {
                id: nameField
                x: 16; width: parent.width - 32; height: 46
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17
                maximumLength: 12
                text: page.f ? page.f.name.text.text : ""
                onTextEdited: {
                    page.named = text !== ""
                    page.f = Object.assign({}, page.f, { name: Object.assign({}, page.f.name,
                        { text: { "@type": "formattedText", text: text, entities: [] } }) })
                }
                onAccepted: focus = false
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !nameField.text
                    text: Tr.t("Papka nomi")
                    color: Theme.grey
                    font: nameField.font
                }
            }
        }
    }

    // ---- what is in it ----
    SettingsGroup {
        title: Tr.t("Kiritilgan chatlar")
        note: Tr.t("Bu papkada ko'rinadigan chatlar va chat turlarini tanlang.")
        AddRow { text: Tr.t("Chat qo'shish"); onTapped: page.choose(false) }
        Repeater {
            model: page.f ? page.ins.filter((c) => page.f[c[0]]) : []
            TypeRow { key: "in:" + modelData[0] }
        }
        Repeater {
            model: page.included.length >= 7 && !page.moreIn ? page.included.slice(0, 5) : page.included
            ChatRow { key: "chat:" + modelData }
        }
        MoreRow {
            visible: page.included.length >= 7 && !page.moreIn
            count: page.included.length - 5
            onTapped: page.moreIn = true
        }
    }

    // ---- what never is ----
    SettingsGroup {
        visible: !!page.f && !page.f.is_shareable
        title: Tr.t("Chiqarilgan chatlar")
        note: Tr.t("Bu papkada hech qachon ko'rinmaydigan chatlar va chat turlarini tanlang.")
        AddRow { text: Tr.t("Chatlarni chiqarish"); onTapped: page.choose(true) }
        Repeater {
            model: page.f ? page.outs.filter((c) => page.f[c[0]]) : []
            TypeRow { key: "out:" + modelData[0] }
        }
        Repeater {
            readonly property var all: page.f ? page.f.excluded_chat_ids : []
            model: all.length >= 7 && !page.moreOut ? all.slice(0, 5) : all
            ChatRow { key: "not:" + modelData }
        }
        MoreRow {
            visible: !!page.f && page.f.excluded_chat_ids.length >= 7 && !page.moreOut
            count: page.f ? page.f.excluded_chat_ids.length - 5 : 0
            onTapped: page.moreOut = true
        }
    }

    // ---- shareable invite links (t.me/addlist/...) ----
    SettingsGroup {
        visible: page.folderId > 0 && !!page.f
        title: Tr.t("Havola orqali ulashish")
        note: Tr.t("Boshqalar ushbu havola orqali papkangizdagi chatlarni bitta bosishda qo'sha oladi.")
        AddRow {
            text: page.linkBusy ? Tr.t("Yuklanmoqda…") : Tr.t("Havola orqali ulashish")
            onTapped: page.shareFolderLink()
        }
        Repeater {
            model: page.inviteLinks
            Swiped {
                id: lrow
                required property var modelData
                key: "link:" + (modelData.invite_link || "")
                Column {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 32
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: (lrow.modelData.invite_link || "").replace(/^https?:\/\//, "")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Tr.n("%1 ta chat", (lrow.modelData.chat_ids || []).length) + " · " + Tr.t("Nusxalash uchun bosing")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.copyLink(lrow.modelData.invite_link)
                }
            }
        }
    }

    // ---- its tag's colour ----
    Column {
        width: parent.width
        spacing: 6
        Item {          // (ChatListFilterTagSectionHeaderItem: the words on the left, the tag as it will look on the right)
            x: 32; width: parent.width - 64; height: 18
            Text {
                anchors.bottom: parent.bottom
                text: Tr.t("Papka rangi").toUpperCase()
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 13
            }
            Rectangle {
                readonly property bool on: page.premium && !!page.f && page.f.color_id >= 0
                readonly property color c: on ? store.nameColor(page.f.color_id) : Theme.grey
                anchors.right: parent.right; anchors.bottom: parent.bottom
                width: tagText.implicitWidth + 12; height: 18; radius: 5
                color: Qt.rgba(c.r, c.g, c.b, 0.15)
                Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: (!page.premium ? Tr.t("Premium kerak")
                         : parent.on ? page.f.name.text.text || Tr.t("Papka") : Tr.t("Teg yo'q")).toUpperCase()
                    color: parent.c
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
        }
        SettingsGroup {
            note: Tr.t("Bu rang chatlar ro'yxatida papka tegi uchun ishlatiladi.")
            Item {
                width: parent.width; height: 62
                Row {
                    anchors.centerIn: parent
                    spacing: Math.min(14, (parent.width - 32 - 8 * 30) / 7)
                    Repeater {
                        model: [-1, 0, 1, 2, 3, 4, 5, 6]
                        Item {
                            required property int modelData
                            readonly property bool chosen: !!page.f && page.f.color_id === modelData
                            width: 30; height: 30
                            opacity: page.premium ? 1 : 0.5
                            Rectangle {
                                anchors.fill: parent; anchors.margins: parent.chosen ? 4 : 0
                                radius: width / 2
                                color: parent.modelData < 0 ? Theme.highlight : store.nameColor(parent.modelData)
                                Rectangle {         // none: a line across
                                    visible: parent.parent.modelData < 0
                                    anchors.centerIn: parent
                                    width: 14; height: 2; radius: 1; rotation: -45
                                    color: Theme.grey
                                }
                            }
                            Rectangle {         // the chosen one: a ring round it
                                visible: parent.chosen
                                anchors.fill: parent
                                radius: 15
                                color: "transparent"
                                border.width: 2
                                border.color: parent.modelData < 0 ? Theme.grey : store.nameColor(parent.modelData)
                            }
                            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: page.setColor(parent.modelData) }
                        }
                    }
                }
            }
        }
    }

    // ---- rows ----
    component AddRow: Item {        // ItemListPeerActionItem: the accent's plus, the words in the accent
        id: arow
        property string text: ""
        signal tapped()
        width: parent ? parent.width : 300; height: 52
        Rectangle { anchors.fill: parent; color: Theme.highlight; visible: aHit.pressed }
        Text {
            x: 16 + 12; anchors.verticalCenter: parent.verticalCenter
            text: "+"
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Light
            anchors.verticalCenterOffset: -2
        }
        Text {
            x: 65; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 16
            elide: Text.ElideRight
            text: arow.text
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 17
        }
        MouseArea { id: aHit; anchors.fill: parent; onClicked: arow.tapped() }
        Rectangle { x: 65; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }
    component MoreRow: Item {       // «Yana N ta chatni ko'rsatish»
        id: mrow
        property int count: 0
        signal tapped()
        width: parent ? parent.width : 300; height: visible ? 46 : 0
        Rectangle { anchors.fill: parent; color: Theme.highlight; visible: mHit.pressed }
        Text {
            x: 65; anchors.verticalCenter: parent.verticalCenter
            text: Tr.n("Yana %1 ta chatni ko'rsatish", mrow.count)
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 17
        }
        MouseArea { id: mHit; anchors.fill: parent; onClicked: mrow.tapped() }
    }
    component Swiped: Item {        // a row swiped left shows «O'chirish» (ItemListRevealOption)
        id: srow
        property string key: ""
        default property alias body: inner.data
        readonly property real slide: page.revealed === key ? -delBtn.width : 0
        width: parent ? parent.width : 300; height: 52
        clip: true
        Item {
            id: inner
            x: srow.slide
            width: parent.width; height: parent.height
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0] } }
        }
        MouseArea {
            anchors.fill: parent
            property real x0: 0
            property real y0: 0
            property bool swiped: false
            onPressed: (m) => { x0 = m.x; y0 = m.y; preventStealing = false; swiped = false }
            onPositionChanged: (m) => {
                const dx = m.x - x0
                if (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(m.y - y0))
                    preventStealing = swiped = true
                if (dx < -30)
                    page.revealed = srow.key
                else if (dx > 30 && page.revealed === srow.key)
                    page.revealed = ""
            }
            onClicked: if (!swiped && page.revealed !== "") page.revealed = ""     // (a release after a swipe is a click too)
        }
        Rectangle {
            id: delBtn
            x: parent.width + srow.slide
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
            MouseArea { anchors.fill: parent; onClicked: page.drop(srow.key) }
        }
        Rectangle { x: 65; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }
    component TypeRow: Swiped {     // ChatListFilterPresetCategoryItem
        id: trow
        required property var modelData
        Image {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            source: "settings-icons/filter-" + trow.modelData[1] + ".png"
            sourceSize: Qt.size(160, 160)
            smooth: true; mipmap: true
        }
        Text {
            x: 65; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 16
            elide: Text.ElideRight
            text: trow.modelData[2]
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
        }
    }
    component ChatRow: Swiped {     // ItemListPeerItem
        id: crow
        required property var modelData
        readonly property var p: page.peer(modelData)
        Avatar {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            source: crow.p.photo; letters: crow.p.letters; tint: crow.p.tint; saved: crow.p.saved
        }
        Text {
            x: 65; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 16
            elide: Text.ElideRight
            text: crow.p.saved ? Tr.t("Saqlangan xabarlar") : crow.p.title
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
        }
    }

    // ---- over the page ----
    TextEdit { id: clipCopy; visible: false }
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
        y: page.height - height - 24 - safe.bottom
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
