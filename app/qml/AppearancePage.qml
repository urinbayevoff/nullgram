// How it looks, as Telegram-iOS's ThemeSettingsController: «RANGLI MAVZU» — a chat in small over the chats' background
// (ThemeSettingsChatPreviewItem), Telegram's chat themes in a row (ThemeCarouselThemeItem: the Classic one, then
// TDLib's emoji themes; one tapped is the app's — its accent, our bubbles, its background, by day and by night),
// «Chat mavzulari» (ChatThemesPage: all of them, and the app's own base and accent), «Chat fon rasmi» (WallpaperPage);
// «Matn o'lchami» (TextSizePage), «Xabar burchaklari» (MessageCornersPage), «Animatsiyalar» (PowerPage, iOS's way);
// «Sizning rangingiz» (YourColorPage); then «Tungi rejim» and «Avtomatik tungi rejim» (AutoNightPage).
import QtQuick

SubPage {
    id: page
    title: Tr.t("Ko'rinish")
    property var makers: ({})
    function open(file) {
        let m = makers[file]
        if (!m) {
            m = Qt.createComponent(file)
            makers[file] = m
        }
        if (m.status === Component.Error)
            console.warn("nullgram:", m.errorString())
        nav.push(m, {})
    }
    readonly property string clock: Qt.formatTime(new Date(), "HH:mm")

    SettingsGroup {
        title: Tr.t("Rangli mavzu")
        SamplePane { clock: page.clock }
        ListView {          // the themes
            id: themes
            width: parent.width; height: 133
            orientation: ListView.Horizontal
            leftMargin: 11; rightMargin: 11
            clip: true
            model: [{ name: "" }].concat(page.store ? page.store.emojiThemes : [])
            delegate: Item {
                id: slot
                required property var modelData
                width: 90; height: 133
                ThemeTile {
                    y: 6
                    store: page.store
                    emoji: slot.modelData.name || "🏠"
                    set: slot.modelData.name ? (Theme.dark ? slot.modelData.dark_settings : slot.modelData.light_settings) || null : null
                    chosen: Prefs.theme === slot.modelData.name
                    onClicked: page.store.chooseTheme(slot.modelData.name)
                }
            }
        }
        Rectangle { x: 16; width: parent.width - 16; height: 0.5; color: Theme.separator }
        SettingsRow { text: Tr.t("Chat mavzulari"); onClicked: page.open("ChatThemesPage.qml") }
        SettingsRow { text: Tr.t("Chat fon rasmi"); onClicked: page.open("WallpaperPage.qml") }
        // (iOS: «Your Color» under the wallpaper, a dot of the name's colour on its right)
        SettingsRow {
            text: Tr.t("Sizning rangingiz"); last: true
            onClicked: page.open("YourColorPage.qml")
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 36; anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: { Theme.dark; page.store.accentColors; return page.store.me ? page.store.nameColors(page.store.me.accent_color_id || 0)[0] : Theme.accent }
            }
        }
    }
    SettingsGroup {         // (iOS: the text size as a share of the regular one, or «System»)
        SettingsRow {
            text: Tr.t("Matn o'lchami")
            value: Prefs.textSize === 0 ? Tr.t("Tizim") : Math.round(Prefs.textSize / Prefs.systemTextSize * 100) + "%"
            onClicked: page.open("TextSizePage.qml")
        }
        SettingsRow { text: Tr.t("Xabar burchaklari"); onClicked: page.open("MessageCornersPage.qml") }
        // (iOS: «Animations» opens the Power Saving page itself, EnergySavingSettingsScreen)
        SettingsRow { text: Tr.t("Animatsiyalar"); onClicked: page.open("PowerPage.qml") }
        SettingsRow { text: Tr.t("Stikerlar va emoji"); last: true; onClicked: page.open("StickersPage.qml") }
    }
    SettingsGroup {
        SettingsRow { text: Tr.t("Tungi rejim"); toggle: true; on: Theme.dark; onClicked: Theme.dark = !Theme.dark }
        // (iOS: «Auto-Night Theme», its value Disabled or Scheduled)
        SettingsRow {
            text: Tr.t("Avtomatik tungi rejim"); last: true
            value: Prefs.autoNight === 0 ? Tr.t("O'chiq") : Tr.t("Jadval bo'yicha")
            onClicked: page.open("AutoNightPage.qml")
        }
    }
    SettingsGroup {         // (iOS: «OTHER»)
        title: Tr.t("Boshqa")
        note: Tr.t("Media ko'rayotganda ekran chetiga bosib, rasmlar orasida o'ting.")
        SettingsRow { text: Tr.t("Bosilganda keyingi media"); toggle: true; on: Prefs.tapNext; last: true; onClicked: Prefs.tapNext = !Prefs.tapNext }
    }
    Item { width: 1; height: 20 }
}
