// Proksi qo'shish (Telegram-iOS's ProxyServerSettingsController): SOCKS5 / MTProto / HTTP, server and port, then
// the user name and password or the secret; «Saqlash» adds it in use (addProxy enable). A t.me/socks or
// t.me/proxy link pasted into the server field is read into the fields.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Proksi")
    signal added()
    property int kind: 0                // 0 SOCKS5, 1 MTProto, 2 HTTP
    property string error: ""
    readonly property bool ready: server.text.trim() !== "" && Number(port.text) > 0 && Number(port.text) < 65536
                                  && (kind !== 1 || secret.text.trim() !== "")
    action: Tr.t("Saqlash")
    actionBold: true
    actionOn: ready
    onActed: save()
    function readLink(s) {
        const m = s.match(/(?:tg:\/\/|t\.me\/)(socks|proxy)\?(.*)/)
        if (!m)
            return false
        const q = {}
        for (const kv of m[2].split("&")) {
            const i = kv.indexOf("=")
            if (i > 0)
                q[kv.slice(0, i)] = decodeURIComponent(kv.slice(i + 1))
        }
        kind = m[1] === "proxy" ? 1 : 0
        server.text = q.server || ""
        port.text = q.port || ""
        user.text = q.user || ""
        pass.text = q.pass || ""
        secret.text = q.secret || ""
        return true
    }
    function save() {
        if (!ready)
            return
        const type = kind === 1 ? { "@type": "proxyTypeMtproto", secret: secret.text.trim() }
                   : kind === 2 ? { "@type": "proxyTypeHttp", username: user.text, password: pass.text, http_only: false }
                   : { "@type": "proxyTypeSocks5", username: user.text, password: pass.text }
        store.send({ "@type": "addProxy", server: server.text.trim(), port: Number(port.text), enable: true, type: type }, (r) => {
            if (r["@type"] === "error") {
                page.error = Tr.f("Bo'lmadi: %1", r.message)
                return
            }
            page.added()
            page.nav.pop()
        })
    }

    component Field: Item {
        id: f
        property alias text: input.text
        property string hintText: ""
        property bool secretText: false
        property bool digits: false
        property bool last: false
        width: parent ? parent.width : 300; height: 48
        TextInput {
            id: input
            x: 16; width: parent.width - 32
            anchors.verticalCenter: parent.verticalCenter
            echoMode: f.secretText ? TextInput.Password : TextInput.Normal
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

    Item {
        width: parent.width; height: 52
        Segments {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width - 32, 300)
            items: ["SOCKS5", "MTProto", "HTTP"]
            index: page.kind
            onPicked: (i) => page.kind = i
        }
    }
    SettingsGroup {
        title: Tr.t("ULANISH")
        Field { id: server; hintText: Tr.t("Server"); onTextChanged: if (text.indexOf("t.me/") >= 0 || text.indexOf("tg://") >= 0) page.readLink(text) }
        Field { id: port; hintText: Tr.t("Port"); digits: true; last: true }
    }
    SettingsGroup {
        visible: page.kind !== 1
        title: Tr.t("KIRISH (IXTIYORIY)")
        Field { id: user; hintText: Tr.t("Foydalanuvchi nomi") }
        Field { id: pass; hintText: Tr.t("Parol"); secretText: true; last: true }
    }
    SettingsGroup {
        visible: page.kind === 1
        title: Tr.t("MAXFIY KALIT")
        note: page.error || Tr.t("t.me/proxy yoki t.me/socks havolasini Server maydoniga qo'ysangiz, qolgani o'zi to'ladi.")
        Field { id: secret; hintText: Tr.t("Secret"); last: true }
    }
    Text {
        visible: page.kind !== 1 && page.error !== ""
        x: 32; width: parent.width - 64; wrapMode: Text.Wrap
        text: page.error; color: Theme.danger
        font.family: Theme.font; font.pixelSize: 13
    }
    Item { width: 1; height: 20 }
}
