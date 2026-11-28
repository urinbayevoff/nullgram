// Topics (Telegram-iOS's ForumSettingsScreen): a picture of chat bubbles, «Mavzularni yoqish»; on, «KO'RINISHI» — two
// drawn phones, Tabs (topics down the left) or List (topics as chats). Each change goes at once
// (toggleSupergroupIsForum is_forum, has_forum_tabs); a basic group is made a supergroup first (store.upgrade).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property bool follows: true
    readonly property var chat: (store.seen, store.chats[chatId])
    readonly property var group: (store.seen, store.groupOf(chat))
    property bool on: !!group && !!group.is_forum
    property bool tabs: !group || !group.is_forum || !!group.has_forum_tabs
    property bool busy: false
    title: Tr.t("Mavzular")

    function apply(forum, withTabs) {
        if (busy)
            return
        const was = [on, tabs]
        on = forum
        tabs = withTabs
        busy = true
        store.upgrade(chatId, nav, (id) => {
            store.send({ "@type": "toggleSupergroupIsForum", supergroup_id: store.chats[id].type.supergroup_id,
                         is_forum: forum, has_forum_tabs: forum && withTabs }, (r) => {
                page.busy = false
                if (r["@type"] === "error") {
                    page.on = was[0]
                    page.tabs = was[1]
                    page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                }
            })
        })
    }

    // ---- the picture: two bubbles, blue and violet, the small green ones round them ----
    Item {
        width: parent.width; height: 150
        Repeater {
            model: [{ x: -58, y: 10, s: 64, c1: "#5ac8fa", c2: "#007aff" }, { x: -8, y: 40, s: 72, c1: "#c86dd7", c2: "#5856d6" },
                    { x: 42, y: 4, s: 30, c1: "#4cd964", c2: "#30b0c7" }, { x: 36, y: 92, s: 24, c1: "#4cd964", c2: "#248a3d" }]
            Item {
                id: bub
                required property var modelData
                x: parent.width / 2 + modelData.x; y: modelData.y
                width: modelData.s; height: modelData.s
                Rectangle {         // the bubble's tail
                    x: parent.width * 0.06; y: parent.height * 0.62
                    width: parent.width * 0.3; height: width
                    radius: width * 0.2
                    rotation: 20
                    color: bub.modelData.c2
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: bub.modelData.c1 }
                        GradientStop { position: 1; color: bub.modelData.c2 }
                    }
                }
                Rectangle {         // the lines of words in it
                    anchors.centerIn: parent
                    visible: parent.width > 50
                    width: parent.width * 0.42; height: 5; radius: 2.5
                    color: Qt.rgba(1, 1, 1, 0.85)
                }
            }
        }
    }
    Text {
        width: parent.width - 64; x: 32
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Tr.t("Guruh chati admin yoki a'zolar ochadigan mavzularga bo'linadi.")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }

    SettingsGroup {
        SettingsRow {
            text: Tr.t("Mavzularni yoqish")
            toggle: true; chevron: false; last: true
            on: page.on
            onClicked: page.apply(!page.on, page.tabs)
        }
    }

    SettingsGroup {
        visible: page.on
        title: Tr.t("Ko'rinishi")
        note: Tr.t("Mavzular barcha a'zolarga qanday ko'rinishini tanlang.")
        Item {
            width: parent.width; height: 196
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                spacing: 28
                Repeater {
                    model: [{ tabs: true, t: Tr.t("Yorliqlar") }, { tabs: false, t: Tr.t("Ro'yxat") }]
                    Column {
                        id: look
                        required property var modelData
                        readonly property bool chosen: page.tabs === modelData.tabs
                        spacing: 10
                        Rectangle {         // the phone
                            width: 96; height: 128; radius: 16
                            color: Theme.card
                            border.width: look.chosen ? 2.5 : 1.5
                            border.color: look.chosen ? Theme.accent : Theme.grey
                            clip: true
                            // tabs: a strip of topic icons down the left, the chat beside it
                            Column {
                                visible: look.modelData.tabs
                                x: 8; y: 14; spacing: 7
                                Repeater {
                                    model: 6
                                    Rectangle { width: 9; height: 9; radius: 2; color: index === 1 ? Theme.accent : Theme.grey; opacity: 0.8 }
                                }
                            }
                            Rectangle {
                                visible: look.modelData.tabs
                                x: 24; y: 14; width: parent.width - 32; height: parent.height - 28; radius: 6
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                            }
                            // list: a round icon and two lines for each topic
                            Column {
                                visible: !look.modelData.tabs
                                x: 10; y: 16; spacing: 10
                                Repeater {
                                    model: 6
                                    Row {
                                        spacing: 6
                                        Rectangle { width: 9; height: 9; radius: 4.5; color: Theme.grey; opacity: 0.8 }
                                        Column {
                                            spacing: 2
                                            Rectangle { width: 46; height: 3; radius: 1.5; color: Theme.grey; opacity: 0.7 }
                                            Rectangle { width: 30; height: 3; radius: 1.5; color: Theme.grey; opacity: 0.4 }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: pick.width + 22; height: 26; radius: 13
                            color: look.chosen ? Theme.accent : "transparent"
                            Text {
                                id: pick
                                anchors.centerIn: parent
                                text: look.modelData.t
                                color: look.chosen ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                        }
                        TapHandler { onTapped: if (!look.chosen) page.apply(true, look.modelData.tabs) }
                    }
                }
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
