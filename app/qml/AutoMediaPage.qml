// One kind's auto-download (Telegram-iOS's AutoDownloadMediaCategoryController): which chats (contacts, other
// private chats, groups, channels) and, for videos and files, up to what size. Prefs.dl[network][kind].
import QtQuick

SubPage {
    id: page
    property string network: "mobile"
    property string kind: "photo"
    property string heading: ""
    title: heading
    readonly property var n: Prefs.dl[network]
    readonly property var sizes: [524288, 1048576, 2621440, 5242880, 10485760, 15728640, 26214400, 52428800,
                                  104857600, 524288000, 1572864000]
    readonly property real max: kind === "video" ? n.videoMax : n.fileMax
    readonly property int stop: { let best = 0; for (let i = 0; i < sizes.length; i++) if (Math.abs(sizes[i] - max) < Math.abs(sizes[best] - max)) best = i; return best }
    function put(changes) {
        const v = JSON.parse(JSON.stringify(n))
        Object.assign(v, changes)
        Prefs.setDl(network, v)
    }
    function flip(who) {
        const k = Object.assign({}, n[kind])
        k[who] = !k[who]
        const c = {}
        c[kind] = k
        put(c)
    }

    SettingsGroup {
        title: Tr.t("AVTOMATIK YUKLASH")
        Repeater {
            model: [{ w: "contacts", t: Tr.t("Kontaktlar"), art: "filter-contacts" },
                    { w: "others", t: Tr.t("Boshqa shaxsiy chatlar"), art: "filter-noncontacts" },
                    { w: "groups", t: Tr.t("Guruhlar"), art: "filter-groups" },
                    { w: "channels", t: Tr.t("Kanallar"), art: "filter-channels" }]
            SettingsRow {
                required property var modelData
                required property int index
                art: modelData.art
                text: modelData.t
                toggle: true
                on: !!page.n[page.kind][modelData.w]
                last: index === 3
                onClicked: page.flip(modelData.w)
            }
        }
    }
    SettingsGroup {
        visible: page.kind !== "photo"
        title: Tr.f("ENG KATTA HAJM: %1", store.size(page.max))
        note: Tr.t("Shundan katta fayllar faqat bosilganda yuklanadi.")
        StepSlider {
            labels: ["512 KB", "", "", "", "", "", "", "", "", "", "1.5 GB"]
            value: page.stop
            onMoved: (v) => page.put(page.kind === "video" ? { videoMax: page.sizes[v] } : { fileMax: page.sizes[v] })
        }
    }
    Item { width: 1; height: 20 }
}
