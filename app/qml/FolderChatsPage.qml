// The chats a folder takes in or leaves out, as Telegram-iOS's ContactMultiselectionController in its chat selection (opened by
// ChatListFilterPresetController's «Chat qo'shish» / «Chiqariladigan chatlarni qo'shish»): the search over them, «CHAT TURLARI»
// (contacts … bots, or muted, read, archived) and «CHATLAR» (the main list in its order, the chosen ones not in it first),
// each with its check on the left. «Tayyor»: done(flags, ids). Also the notifications' exceptions' chats (`heading`, `pool`).
import QtQuick

SubPage {
    id: page
    property bool excluding: false
    property var types: []              // [[flag, picture, name, on]]
    property var chosen: []             // the chats' ids as they came
    property string heading: ""         // (another's title: the notifications' «Istisno qo'shish»)
    property var pool: null             // (only the chats this says yes to: a function of the chat)
    property var flags: ({})
    property var picked: []
    property string query: ""
    signal done(var flags, var ids)
    title: heading || (excluding ? Tr.t("Chatlarni chiqarish") : Tr.t("Chatlarni kiritish"))
    action: Tr.t("Tayyor")
    actionBold: true
    onActed: {
        done(flags, picked)
        nav.pop()
    }
    Component.onCompleted: {
        const fl = {}
        for (const t of types)
            fl[t[0]] = t[3]
        flags = fl
        picked = chosen.slice()
        const ids = []
        for (let i = 0; i < store.chatList.count; i++) {
            const id = store.chatList.get(i).chatId
            if (!pool || (store.chats[id] && pool(store.chats[id])))
                ids.push(id)
        }
        all = chosen.filter((id) => ids.indexOf(id) < 0).concat(ids)
    }
    property var all: []
    function matches(words) {
        return query === "" || words.toLowerCase().indexOf(query.toLowerCase()) >= 0
    }
    function peer(id) {
        const c = store.chats[id]
        return c ? { title: store.isSaved(c) ? Tr.t("Saqlangan xabarlar") : store.title(c), photo: store.photoPath(c),
                     letters: store.letters(c.title), tint: store.tints[Math.abs(id) % store.tints.length], saved: store.isSaved(c) }
                 : { title: "…", photo: "", letters: "", tint: Theme.grey, saved: false }
    }
    function flip(id) {
        picked = picked.indexOf(id) >= 0 ? picked.filter((x) => x !== id) : picked.concat([id])
    }

    // ---- the search ----
    Rectangle {
        x: 16; width: parent.width - 32; height: 36
        radius: 10
        color: Theme.highlight
        Icon { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; name: "search"; color: Theme.grey }
        TextInput {
            id: search
            x: 32; width: parent.width - 40; height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17
            onTextChanged: page.query = text.trim()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !search.text
                text: Tr.t("Chatlarni qidirish")
                color: Theme.grey
                font: search.font
            }
        }
    }

    SettingsGroup {
        visible: page.types.length > 0 && page.types.some((t) => page.matches(t[2]))
        title: Tr.t("Chat turlari")
        Repeater {
            model: page.types
            Pick {
                required property var modelData
                visible: page.matches(modelData[2])
                on: !!page.flags[modelData[0]]
                words: modelData[2]
                picture: "settings-icons/filter-" + modelData[1] + ".png"
                onTapped: page.flags = Object.assign({}, page.flags, { [modelData[0]]: !page.flags[modelData[0]] })
            }
        }
    }

    SettingsGroup {
        title: Tr.t("Chatlar")
        Repeater {
            model: page.all
            Pick {
                required property var modelData
                readonly property var p: page.peer(modelData)
                visible: page.matches(p.title)
                on: page.picked.indexOf(modelData) >= 0
                words: p.title
                photo: p.photo; letters: p.letters; tint: p.tint; saved: p.saved
                onTapped: page.flip(modelData)
            }
        }
    }

    // ---- a row: its check, its picture, its name ----
    component Pick: Item {
        id: row
        property bool on: false
        property string words: ""
        property string picture: ""     // a type's
        property string photo: ""       // a chat's
        property string letters: ""
        property color tint: Theme.accent
        property bool saved: false
        signal tapped()
        width: parent ? parent.width : 300; height: 52
        Rectangle { anchors.fill: parent; color: Theme.highlight; visible: hit.pressed }
        Rectangle {         // the check (iOS's selection circle)
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 11
            color: row.on ? Theme.accent : "transparent"
            border.width: row.on ? 0 : 1.5
            border.color: Theme.separator
            Icon { visible: row.on; anchors.centerIn: parent; width: 16; height: 16; name: "check"; color: "white" }
        }
        Image {
            visible: row.picture !== ""
            x: 52; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            source: row.picture
            sourceSize: Qt.size(160, 160)
            smooth: true; mipmap: true
        }
        Avatar {
            visible: row.picture === ""
            x: 52; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            source: row.photo; letters: row.letters; tint: row.tint; saved: row.saved
        }
        Text {
            x: 104; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 16
            elide: Text.ElideRight
            text: row.words
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
        }
        MouseArea { id: hit; anchors.fill: parent; onClicked: row.tapped() }
        Rectangle { x: 104; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }
}
