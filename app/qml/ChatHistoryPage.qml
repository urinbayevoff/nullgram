// Chat History Settings (Telegram-iOS's GroupPreHistorySetupController): do new members see what was sent before
// they joined — Visible / Hidden; «Saqlash» (toggleSupergroupIsAllHistoryAvailable). A basic group's history is always
// seen: hiding it makes it a supergroup first (store.upgrade).
import QtQuick

SubPage {
    id: page
    property var chatId: 0
    readonly property bool follows: true
    property bool shown: true           // as it is now (the opener's)
    property bool want: shown
    readonly property var chat: (store.seen, store.chats[chatId])
    title: Tr.t("Chat tarixi")
    action: Tr.t("Saqlash")
    actionBold: true
    actionOn: want !== shown
    onActed: save()

    function save() {
        const set = (id) => {
            const c = store.chats[id]
            store.send({ "@type": "toggleSupergroupIsAllHistoryAvailable", supergroup_id: c.type.supergroup_id,
                         is_all_history_available: page.want }, (r) => {
                if (r["@type"] === "error")
                    return page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
                page.nav.pop()
            })
        }
        store.upgrade(chatId, nav, set)
    }

    SettingsGroup {
        title: Tr.t("Yangi a'zolar uchun chat tarixi")
        note: Tr.t(page.want ? "Yangi a'zolar ular qo'shilishidan oldin yuborilgan xabarlarni ko'radi."
                             : "Yangi a'zolar ular qo'shilishidan oldingi 100 tagacha xabarni ko'rmaydi.")
        SettingsRow { text: Tr.t("Ko'rinadi"); chevron: false; tick: page.want; onClicked: page.want = true }
        SettingsRow { text: Tr.t("Yashirin"); chevron: false; tick: !page.want; last: true; onClicked: page.want = false }
    }
    Item { width: 1; height: 30 + safe.bottom }
}
