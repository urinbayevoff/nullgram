// Galereyaga saqlash for one kind of chat (Telegram-iOS's SaveIncomingMediaController): Rasmlar, Videolar — new
// ones that come (not ours) go into ~/Downloads by themselves (Store.autoSave). Prefs.saveTo[group].
import QtQuick

SubPage {
    id: page
    property string group: "private"
    property string heading: ""
    title: heading
    readonly property var w: Prefs.saveTo[group] || ({})
    function flip(k) {
        const all = JSON.parse(JSON.stringify(Prefs.saveTo))
        const v = Object.assign({}, all[group] || {})
        v[k] = !v[k]
        all[group] = v
        Prefs.saveMedia = JSON.stringify(all)
    }
    SettingsGroup {
        title: Tr.t("AVTOMATIK SAQLASH")
        note: Tr.t("Bu chatlarga kelgan yangi rasm va videolar Downloads jildiga o'zi saqlanadi.")
        SettingsRow { art: "photos"; text: Tr.t("Rasmlar"); toggle: true; on: !!page.w.photo; onClicked: page.flip("photo") }
        SettingsRow { art: "videos"; text: Tr.t("Videolar"); toggle: true; on: !!page.w.video; last: true; onClicked: page.flip("video") }
    }
    Item { width: 1; height: 20 }
}
