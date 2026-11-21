// A new invite link, or one edited (Telegram-iOS's InviteLinkEditController): its name, «So'rov bilan qo'shilish»
// (an admin says yes: creates_join_request), how long it works, how many may join by it (not with requests).
// createChatInviteLink / editChatInviteLink.
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    property var link: null             // chatInviteLink being edited, null: a new one
    property bool asks: link ? link.creates_join_request : false
    property int lasts: 0               // seconds from now, 0 no end (an edited one: kept as it is, -1)
    property int limit: link ? link.member_limit : 0
    title: Tr.t(link ? "Havolani tahrirlash" : "Yangi havola")
    action: Tr.t(link ? "Saqlash" : "Yaratish")
    actionBold: true
    onActed: save()
    Component.onCompleted: {
        if (link) {
            name.text = link.name
            lasts = link.expiration_date ? -1 : 0
        }
    }
    readonly property var times: [{ t: Tr.t("1 soat"), v: 3600 }, { t: Tr.t("1 kun"), v: 86400 }, { t: Tr.t("1 hafta"), v: 604800 },
                                  { t: Tr.t("Cheklanmagan"), v: 0 }]
    readonly property var limits: [1, 10, 50, 100, 0]
    function save() {
        const until = lasts > 0 ? Math.floor(Date.now() / 1000) + lasts : lasts < 0 ? link.expiration_date : 0
        const q = { chat_id: chatId, name: name.text.trim(), expiration_date: until,
                    member_limit: asks ? 0 : limit, creates_join_request: asks }
        if (link) {
            q["@type"] = "editChatInviteLink"
            q.invite_link = link.invite_link
        } else
            q["@type"] = "createChatInviteLink"
        store.send(q, (r) => {
            if (r["@type"] === "error")
                return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            page.nav.pop()
        })
    }

    component Chip: Rectangle {
        property string t: ""
        property bool on: false
        signal tapped()
        width: chipText.width + 24; height: 32; radius: 16
        color: on ? Theme.accent : Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.06)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.t
            color: parent.on ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 15
        }
        MouseArea { anchors.fill: parent; onClicked: parent.tapped() }
    }

    SettingsGroup {
        note: Tr.t("Havola nomini faqat adminlar ko'radi.")
        Item {
            width: parent.width; height: 48
            TextInput {
                id: name
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                maximumLength: 32
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
            }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                visible: !name.text
                text: Tr.t("Havola nomi (ixtiyoriy)")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
        }
    }
    SettingsGroup {
        note: Tr.t("Yoqilsa, havola orqali kelganlar adminning roziligidan keyin qo'shiladi.")
        SettingsRow { text: Tr.t("So'rov bilan qo'shilish"); toggle: true; chevron: false; last: true; on: page.asks
                      onClicked: page.asks = !page.asks }
    }
    SettingsGroup {
        title: Tr.t("Amal qilish muddati")
        note: Tr.t("Shu vaqtdan keyin havola ishlamay qoladi.")
        Flow {
            x: 12; width: parent.width - 24
            topPadding: 12; bottomPadding: 12
            spacing: 8
            Chip { visible: page.lasts < 0; t: Tr.t("O'zgarmasin"); on: true }
            Repeater {
                model: page.times
                Chip { required property var modelData; t: modelData.t; on: page.lasts === modelData.v; onTapped: page.lasts = modelData.v }
            }
        }
    }
    SettingsGroup {
        visible: !page.asks
        title: Tr.t("Qo'shilishlar soni")
        note: Tr.t("Shuncha kishi qo'shilgach, havola ishlamay qoladi.")
        Flow {
            x: 12; width: parent.width - 24
            topPadding: 12; bottomPadding: 12
            spacing: 8
            Repeater {
                model: page.limits
                Chip { required property var modelData; t: modelData ? String(modelData) : Tr.t("Cheklanmagan")
                       on: page.limit === modelData; onTapped: page.limit = modelData }
            }
        }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
