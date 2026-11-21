// A channel's discussion group (Telegram-iOS's ChannelDiscussionGroupSetupController): linked — the group and
// «Guruhni ajratish»; none — the groups that may be linked (getSuitableDiscussionChats), a tap links one after a
// question (setChatDiscussionGroup).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    property var linkedId: 0
    property var groups: []
    property bool loaded: false
    readonly property var linked: linkedId ? (store.seen, store.chats[linkedId]) : null
    title: Tr.t("Muhokama")
    Component.onCompleted: if (!linkedId) load()
    function load() {
        store.send({ "@type": "getSuitableDiscussionChats" }, (r) => {
            page.loaded = true
            if (r["@type"] === "chats")
                page.groups = r.chat_ids
        })
    }
    function link(id) {
        store.send({ "@type": "setChatDiscussionGroup", chat_id: chatId, discussion_chat_id: id }, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.linkedId = id
            if (!id)
                page.load()
        })
    }
    function ask(id) {
        alert.title = ""
        alert.text = id ? Tr.f("«%1» guruhi kanal muhokamasi bo'lsinmi? Har bir post ostida izohlar chiqadi.", store.title(store.chats[id]))
                        : Tr.t("Guruh kanaldan ajratilsinmi? Postlar ostida izoh qoldirib bo'lmay qoladi.")
        alert.answers = [{ t: Tr.t("Bekor qilish") }, { t: Tr.t(id ? "Bog'lash" : "Ajratish"), red: !id, run: () => page.link(id) }]
        alert.open = true
    }

    Text {
        x: 32; width: parent.width - 64
        topPadding: 8; bottomPadding: 20
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.linked ? Tr.t("Shu guruhdagi har bir post ostida izohlar chiqadi.")
                          : Tr.t("Guruhni bog'lasangiz, har bir post ostida izoh qoldirish mumkin bo'ladi.")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 15
    }
    SettingsGroup {
        visible: !!page.linked
        SettingsRow { icon: "chats"; tint: "#34c759"; text: page.linked ? page.linked.title : ""; chevron: false }
        SettingsRow { text: Tr.t("Guruhni ajratish"); danger: true; chevron: false; last: true; onClicked: page.ask(0) }
    }
    SettingsGroup {
        visible: !page.linked
        title: Tr.t("Guruhni tanlang")
        note: page.loaded && !page.groups.length ? Tr.t("Siz admin bo'lgan mos guruh yo'q.") : ""
        Repeater {
            model: page.linked ? [] : page.groups
            SettingsRow {
                required property var modelData
                required property int index
                icon: "chats"; tint: "#34c759"
                text: (store.seen, store.chats[modelData] ? store.chats[modelData].title : "…")
                last: index === page.groups.length - 1
                onClicked: page.ask(modelData)
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
