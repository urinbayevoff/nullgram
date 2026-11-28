// A chat's picture with Telegram-iOS's story ring round it (StoryContainerScreen's avatar, the list's
// StoryPeerListItem): green to blue while something in it is unseen, a thin grey one when all are seen, none
// without stories. `plus`: ours with none — the small blue ⊕ at its foot (Mening hikoyam).
import QtQuick

Item {
    id: sa
    property var chatId: 0
    property real size: 60
    property color under: Theme.bg      // what the gap between the ring and the picture shows
    property bool plus: false
    property bool ringOn: true
    width: size; height: size

    readonly property var chat: (store.seen, store.chats[chatId] || null)
    readonly property var user: (store.seen, store.users[chatId] || null)
    readonly property bool any: ringOn && (store.storiesSeen, store.hasStories(chatId))
    readonly property bool fresh: any && (store.storiesSeen, store.unseen(chatId))
    readonly property real ring: fresh ? 2.3 : 1.3
    property string path: ""

    function look() {
        const f = chat && chat.photo ? chat.photo.small : user && user.profile_photo ? user.profile_photo.small : null
        path = ""
        if (f)
            store.fetch(f, 1, (p) => { if (sa) sa.path = p })     // (it may be gone by the time it comes)
    }
    onChatChanged: look()
    Component.onCompleted: look()

    Rectangle {         // seen: a thin grey ring
        visible: sa.any && !sa.fresh
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.color: Theme.dark ? "#48484a" : "#c7c7cc"; border.width: sa.ring
    }
    Rectangle {         // unseen: green to blue
        visible: sa.fresh
        anchors.fill: parent
        radius: width / 2
        rotation: 45
        gradient: Gradient {
            GradientStop { position: 0; color: "#34c76f" }
            GradientStop { position: 1; color: "#3da1fd" }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 2 * sa.ring; height: width
            radius: width / 2
            color: sa.under
        }
    }
    Avatar {
        anchors.centerIn: parent
        width: sa.any ? sa.size - 2 * (sa.ring + 2.2) : sa.size; height: width
        source: sa.path
        letters: store.letters(sa.chat ? sa.chat.title : sa.user ? sa.user.first_name + " " + sa.user.last_name : "")
        tint: store.tints[Math.abs(sa.chatId) % store.tints.length]
    }
    Rectangle {         // ⊕: ours, nothing posted
        visible: sa.plus && !sa.any
        x: sa.size - width + 1; y: sa.size - height + 1
        width: Math.round(sa.size * 0.36); height: width; radius: width / 2
        color: "#2a9ef1"
        border.color: sa.under; border.width: 2
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "+"; color: "white"
            font.family: Theme.font; font.pixelSize: parent.width * 0.8; font.weight: Font.DemiBold
        }
    }
}
