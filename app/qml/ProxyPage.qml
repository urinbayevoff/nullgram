// Proksi (Telegram-iOS's ProxySettingsController): «Proksi ishlatish», the saved ones (server:port, kind, how fast
// — pingProxy) with ✓ by the one in use (a tap uses it: enableProxy), «Proksi qo'shish» -> ProxyEditPage;
// «Tahrirlash»: ⊖ removes one (removeProxy, asked). changed() when anything was (the page under it shows it).
import QtQuick

SubPage {
    id: page
    title: Tr.t("Proksi")
    signal changed()
    property var proxies: []
    property var pings: ({})            // id -> "45 ms" / "mavjud emas"
    property bool editing: false
    property int lastUsed: 0
    action: proxies.length ? (editing ? Tr.t("Tayyor") : Tr.t("Tahrirlash")) : ""
    actionBold: editing
    onActed: editing = !editing
    readonly property bool using: proxies.some((p) => p.is_enabled)
    Component.onCompleted: refresh()
    function refresh() {
        store.send({ "@type": "getProxies" }, (r) => {
            if (r["@type"] !== "proxies")
                return
            page.proxies = r.proxies
            let best = null
            for (const p of r.proxies) {
                if (!best || p.last_used_date > best.last_used_date)
                    best = p
                page.ping(p)
            }
            page.lastUsed = best ? best.id : 0
        })
    }
    function ping(p) {
        store.send({ "@type": "pingProxy", proxy_id: p.id }, (r) => {
            const o = Object.assign({}, page.pings)
            o[p.id] = r["@type"] === "seconds" ? Tr.f("mavjud (%1 ms)", Math.round(r.seconds * 1000)) : Tr.t("mavjud emas")
            page.pings = o
        })
    }
    function kindName(t) {
        return t["@type"] === "proxyTypeMtproto" ? "MTProto" : t["@type"] === "proxyTypeHttp" ? "HTTP" : "SOCKS5"
    }
    function use(p) {
        store.send({ "@type": "enableProxy", proxy_id: p.id }, () => { page.refresh(); page.changed() })
    }
    function toggle() {
        if (using)
            store.send({ "@type": "disableProxy" }, () => { page.refresh(); page.changed() })
        else if (lastUsed)
            store.send({ "@type": "enableProxy", proxy_id: lastUsed }, () => { page.refresh(); page.changed() })
    }
    function addNew() {
        const p = page.nav.push(Qt.createComponent("ProxyEditPage.qml"), {})
        if (p)
            p.added.connect(() => { page.refresh(); page.changed() })
        return p
    }
    function remove(p) {
        alert.show("", Tr.f("%1 proksisi o'chirilsinmi?", p.server),
                   [{ t: Tr.t("Bekor qilish") }, { t: Tr.t("O'chirish"), red: true, run: () =>
                       store.send({ "@type": "removeProxy", proxy_id: p.id }, () => { page.refresh(); page.changed() }) }])
    }

    SettingsGroup {
        SettingsRow {
            text: Tr.t("Proksi ishlatish"); toggle: true; on: page.using; last: true
            dim: !page.proxies.length
            onClicked: if (page.proxies.length) page.toggle()
        }
    }
    SettingsGroup {
        title: Tr.t("SAQLANGAN PROKSILAR")
        note: Tr.t("Telegram'ga to'g'ridan-to'g'ri ulanib bo'lmasa, proksi orqali ulanadi.")
        Repeater {
            model: page.proxies
            Item {
                id: row
                required property var modelData
                required property int index
                width: parent.width; height: 58
                Rectangle {
                    x: page.editing ? 14 : -30; anchors.verticalCenter: parent.verticalCenter
                    Behavior on x { NumberAnimation { duration: 200 } }
                    width: 22; height: 22; radius: 11
                    color: "#ff3b30"
                    Rectangle { anchors.centerIn: parent; width: 10; height: 2; color: "white" }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.remove(row.modelData) }
                }
                Icon {
                    x: page.editing ? 48 : 16; anchors.verticalCenter: parent.verticalCenter
                    Behavior on x { NumberAnimation { duration: 200 } }
                    width: 20; height: 20
                    name: "check"; color: Theme.accent
                    opacity: row.modelData.is_enabled ? 1 : 0
                }
                Column {
                    x: page.editing ? 82 : 50; anchors.verticalCenter: parent.verticalCenter
                    Behavior on x { NumberAnimation { duration: 200 } }
                    width: parent.width - x - 16
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: row.modelData.server + ":" + row.modelData.port
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 17
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: page.kindName(row.modelData.type) + ", " + (row.modelData.is_enabled ? Tr.t("ulangan") : (page.pings[row.modelData.id] || Tr.t("tekshirilmoqda...")))
                        color: row.modelData.is_enabled ? Theme.accent : Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }
                Rectangle { x: 50; width: parent.width - 50; height: 0.5; anchors.bottom: parent.bottom; color: Theme.separator }
                MouseArea { anchors.fill: parent; anchors.leftMargin: page.editing ? 44 : 0; onClicked: if (!page.editing) page.use(row.modelData) }
            }
        }
        SettingsRow {
            text: Tr.t("Proksi qo'shish"); accent: true; chevron: false; last: true
            onClicked: page.addNew()
        }
    }
    Item { width: 1; height: 20 }

    Alert { id: alert; parent: page; anchors.fill: parent }
}
