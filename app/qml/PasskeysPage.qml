// «Passkey'lar» (Telegram-iOS's PasskeysScreen): the passkeys that may sign in to this account (getLoginPasskeys) —
// name, when added, last used; ⊖ asks and removes one (removeLoginPasskey). Adding one needs the phone's
// authenticator (WebAuthn), which OmonullOS has not: said in the note.
import QtQuick

SubPage {
    id: page
    property var keys: []
    property bool loaded: false
    property bool editing: false
    signal counted(int n)
    title: Tr.t("Passkey'lar")
    action: keys.length ? (editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")) : ""
    actionBold: editing
    onActed: editing = !editing

    function load() {
        store.send({ "@type": "getLoginPasskeys" }, (r) => {
            page.keys = r.passkeys || []
            page.loaded = true
            page.counted(page.keys.length)
        })
    }
    Component.onCompleted: load()
    function day(t) { return t ? new Date(t * 1000).toLocaleDateString(Qt.locale(Tr.en ? "en_US" : "uz_UZ"), "d MMM yyyy") : "" }
    function remove(k) {
        alert.show("", Tr.f("«%1» passkey'i o'chirilsinmi? U bilan endi kirib bo'lmaydi.", k.name || "Passkey"),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () =>
                       store.send({ "@type": "removeLoginPasskey", passkey_id: k.id }, () => page.load()) }])
    }

    Column {
        visible: page.loaded && !page.keys.length
        width: parent.width
        spacing: 10
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "🔑"; font.pixelSize: 72 }
        Text {
            x: 32; width: parent.width - 64
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Tr.t("Passkey'lar yo'q")
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 21; font.weight: Font.DemiBold
        }
    }
    SettingsGroup {
        visible: page.keys.length > 0
        Repeater {
            model: page.keys
            Item {
                id: row
                required property var modelData
                required property int index
                width: parent ? parent.width : 300; height: 60
                Rectangle {
                    x: page.editing ? 14 : -30; anchors.verticalCenter: parent.verticalCenter
                    Behavior on x { NumberAnimation { duration: 200 } }
                    width: 22; height: 22; radius: 11
                    color: "#ff3b30"
                    Rectangle { anchors.centerIn: parent; width: 10; height: 2; color: "white" }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.remove(row.modelData) }
                }
                Column {
                    x: page.editing ? 48 : 16; anchors.verticalCenter: parent.verticalCenter
                    Behavior on x { NumberAnimation { duration: 200 } }
                    width: parent.width - x - 16
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: row.modelData.name || "Passkey"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: Tr.f("Qo'shilgan: %1", page.day(row.modelData.addition_date)) +
                              (row.modelData.last_usage_date ? "  ·  " + Tr.f("Ishlatilgan: %1", page.day(row.modelData.last_usage_date)) : "")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }
                Rectangle { visible: row.index < page.keys.length - 1; x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
            }
        }
    }
    Text {
        visible: page.loaded
        x: 32; width: parent.width - 64
        wrapMode: Text.Wrap
        text: Tr.t("Passkey bilan SMS kodisiz, barmoq izi yoki ekran qulfi orqali kiriladi. Yangi passkey'ni iPhone, Android yoki kompyuterdagi Telegram'da qo'shing — OmonullOS'da hali autentifikator yo'q.")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 13
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
