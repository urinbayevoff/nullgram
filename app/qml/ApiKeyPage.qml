// O'z API kalitingiz: the Telegram API key (api_id and api_hash, from my.telegram.org) this phone uses instead
// of the one Nullgram comes with: if Telegram blocks the packaged key, or a build came without one (then this
// page is the first one, before the sign-in: `first`). Saved, the app starts again with it.
import QtQuick

SubPage {
    id: page
    title: Tr.t("API kaliti")
    property bool first: false          // no key at all: the first page, nothing to go back to
    backable: !first
    property string error: ""
    readonly property var own: td.ownKey()
    readonly property bool ready: /^\d+$/.test(apiId.text.trim()) && /^[0-9a-fA-F]{32}$/.test(apiHash.text.trim())
    action: Tr.t("Saqlash")
    actionBold: true
    actionOn: ready
    onActed: save()
    Component.onCompleted: {
        apiId.text = own.id || ""
        apiHash.text = own.hash || ""
    }

    function save() {
        if (!ready)
            return
        if (!td.setOwnKey(apiId.text, apiHash.text)) {
            error = Tr.t("Bu kalitga o'xshamaydi: api_id raqam, api_hash 32 belgi (0-9, a-f).")
            return
        }
        td.restart()            // the key is read at the start
    }
    function reset() {
        td.setOwnKey("", "")
        td.restart()
    }

    component Field: Item {
        id: f
        property alias text: input.text
        property string hintText: ""
        property bool digits: false
        property bool last: false
        width: parent ? parent.width : 300; height: 48
        TextInput {
            id: input
            x: 16; width: parent.width - 32
            anchors.verticalCenter: parent.verticalCenter
            inputMethodHints: f.digits ? Qt.ImhDigitsOnly : Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17
            selectionColor: Theme.accent
            clip: true
        }
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            text: f.hintText
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 17
        }
        Rectangle { visible: !f.last; x: 16; anchors.bottom: parent.bottom; width: parent.width - x; height: 0.5; color: Theme.separator }
    }

    Text {
        x: 32; width: parent.width - 64; topPadding: 16; bottomPadding: 8
        wrapMode: Text.Wrap
        text: page.first
              ? Tr.t("Bu Nullgram nusxasida Telegram API kaliti yo'q. my.telegram.org saytiga Telegram raqamingiz bilan kiring, «API development tools» bo'limida ilova yarating va api_id hamda api_hash'ni shu yerga yozing.")
              : Tr.t("Nullgram o'z kaliti bilan keladi. Telegram uni bloklasa yoki o'zingiznikini ishlatmoqchi bo'lsangiz, my.telegram.org → «API development tools» dan olingan kalitni yozing. Saqlangach, ilova qayta ochiladi.")
        color: Theme.grey
        font.family: Theme.font; font.pixelSize: 14
    }
    SettingsGroup {
        title: Tr.t("O'Z API KALITINGIZ")
        note: page.error
        Field { id: apiId; hintText: "api_id"; digits: true }
        Field { id: apiHash; hintText: "api_hash"; last: true }
    }
    SettingsGroup {
        visible: !page.first && td.keySource === "own"
        SettingsRow { text: Tr.t("Nullgram kalitiga qaytish"); danger: true; chevron: false; last: true; onClicked: page.reset() }
    }
    Item { width: 1; height: 20 }
}
