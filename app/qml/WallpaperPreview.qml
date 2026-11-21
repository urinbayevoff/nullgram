// A background before it is set, as Telegram-iOS's WallpaperGalleryController: the whole screen of it, its
// title on glass over it («Fon rasmiga razm solish»), two messages saying what to do (WallpaperPreview.PreviewTopText /
// PreviewBottomText), «Bekor qilish» and «O'rnatish» at the foot (its toolbar). Set:
// setDefaultBackground for the day or the night, whichever is on, then back to the grid.
// `background`: TDLib's (an installed one or Telegram's own), `type` its BackgroundType (a colour's own, made by the
// grid; for Telegram's own the day's or the night's), `local`: a picture of the phone's (inputBackgroundLocal).
// One chat's (`chatId`): setChatBackground — only for us, or (Premium, as iOS asks) for them too — then back to `home`.
import QtQuick

Page {
    id: page
    property var background: null
    property var type: null
    property string local: ""
    property string spec: ""
    property var chatId: 0
    property Item home: null
    readonly property bool fill: !!type && type["@type"] === "backgroundTypeFill"
    color: "black"

    Wallpaper { anchors.fill: parent; spec: page.spec }

    Item {           // the bar: ‹ and the title, on glass
        width: parent.width; height: 60
        Glass {
            id: backCap
            x: 10; y: 8
            width: 44; height: 44
            opacity: backHit.pressed ? 0.5 : 1
            Text {
                anchors.centerIn: parent; anchors.verticalCenterOffset: -2; anchors.horizontalCenterOffset: -1
                text: "‹"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Light
            }
        }
        MouseArea { id: backHit; width: 64; height: parent.height; onClicked: page.nav.pop() }
        Glass {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: Math.min(parent.width - 2 * 60, titleText.implicitWidth + 32); height: 44
            Text {
                id: titleText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 24)
                elide: Text.ElideRight
                text: Tr.t("Fon rasmiga razm solish")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
        }
    }

    ChatSample {
        anchors.bottom: buttons.top; anchors.bottomMargin: 18
        messages: [{ text: Tr.t("Fon rasmini tatbiq qilish uchun O'rnatish tugmasini bosing"), time: page.clock },
                   { out: true, text: Tr.t("Chiroyli!"), time: page.clock }]
    }
    readonly property string clock: Qt.formatTime(new Date(), "HH:mm")

    Row {            // the toolbar's two
        id: buttons
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        spacing: 12
        Repeater {
            model: [{ t: Tr.t("Bekor qilish"), set: false }, { t: Tr.t("O'rnatish"), set: true }]
            Glass {
                required property var modelData
                width: (page.width - 44) / 2; height: 50
                opacity: hit.pressed ? 0.6 : 1
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.t
                    color: parent.modelData.set ? Theme.accent : Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: parent.modelData.set ? Font.DemiBold : Font.Normal
                }
                MouseArea { id: hit; anchors.fill: parent; onClicked: parent.modelData.set ? page.apply() : page.nav.pop() }
            }
        }
    }

    Component.onCompleted: {
        if (spec)
            return
        if (local)
            spec = "000000;0;photo;" + local
        else if (background)
            store.wallOf(background, type, (s) => { if (s) page.spec = s })
        else
            spec = store.wallSpec(null, type, "")
    }

    function apply() {
        if (chatId)
            return applyChat()
        Prefs.themeWall = false         // (the one set from here on, not the chosen theme's)
        const input = page.local ? { "@type": "inputBackgroundLocal", background: { "@type": "inputFileLocal", path: page.local } }
                    : page.background ? { "@type": "inputBackgroundRemote", background_id: page.background.id } : null
        const dark = Theme.dark
        store.send({ "@type": "setDefaultBackground", background: input, type: page.type, for_dark_theme: dark }, (r) => {
            if (r["@type"] === "background")
                store.setBackground(dark, r)        // (TDLib tells it too: updateDefaultBackground)
            else
                console.warn("nullgram: setDefaultBackground", JSON.stringify(r))
        })
        page.nav.pop()
    }

    // one chat's: Premium asks whether for them too (iOS's «Men uchun» / «Men va X uchun»)
    function applyChat() {
        const c = store.chats[chatId]
        const user = c && c.type["@type"] === "chatTypePrivate" && !store.isSaved(c)
        if (user && store.me && store.me.is_premium)
            alert.show(Tr.t("Fon rasmini o'rnatish"), "", [{ t: Tr.t("Faqat men uchun"), run: () => page.setChat(true) },
                                { t: Tr.f("Men va %1 uchun", store.title(c)), run: () => page.setChat(false) },
                                { t: Tr.t("Bekor qilish"), run: () => {} }], true)
        else
            setChat(true)
    }
    function setChat(self) {
        const input = page.local ? { "@type": "inputBackgroundLocal", background: { "@type": "inputFileLocal", path: page.local } }
                    : page.background ? { "@type": "inputBackgroundRemote", background_id: page.background.id } : null
        store.send({ "@type": "setChatBackground", chat_id: chatId, background: input, type: page.type, dark_theme_dimming: 0,
                     only_for_self: self }, (r) => {
            if (r["@type"] === "error") {
                console.warn("nullgram: setChatBackground", JSON.stringify(r))
                page.nav.say(Tr.f("Bo'lmadi: %1", r.message))
            } else
                page.nav.say(Tr.t("Fon rasmi o'rnatildi"))
        })
        if (home)
            page.nav.popTo(home)
        else
            page.nav.pop()
    }
    Alert { id: alert; parent: page; anchors.fill: parent; z: 10 }
}
