// Colours, from Telegram-iOS's own themes (TelegramPresentationData/Sources/
// DefaultDayPresentationTheme.swift, DefaultDarkPresentationTheme.swift). Day is
// what the owner's iPhone shows: white lists, the green freeform wallpaper,
// light green bubbles of ours.
pragma Singleton
import QtQuick

QtObject {
    property bool dark: false

    // the theme chosen (Store.retheme): Looks.js's look of a base and its accent, or a chat theme's themeSettings as
    // one ({}: Telegram-iOS's own, the Classic theme by day, its Night by night). `tint`: the tinted night's surfaces.
    property var look: ({})
    readonly property var tint: look.tint || null
    readonly property bool own: !!look.out
    // dark words on our bubbles (light ones) or white
    readonly property bool outLight: own ? !!look.outLight : !dark

    readonly property color bg: tint ? tint.page : dark ? "#000000" : "#ffffff"
    readonly property color bar: tint ? tint.bar : dark ? Qt.rgba(0.11, 0.11, 0.11, 0.92) : Qt.rgba(0.97, 0.97, 0.97, 0.92)
    readonly property color keys: tint ? tint.card : dark ? Qt.rgba(0.11, 0.11, 0.11, 1) : Qt.rgba(0.97, 0.97, 0.97, 1)       // the emoji/sticker panel where the keyboard was: whole, as the keyboard (see-through, a video sticker behind it showed)
    readonly property color glass: tint ? tint.card : dark ? Qt.rgba(0.13, 0.13, 0.14, 1) : Qt.rgba(0.99, 0.99, 0.99, 1)     // iOS 26's glass over the chat (whole: without a blur, any see-through lets the words under it be read)
    readonly property color glassEdge: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.9)
    readonly property color field: tint ? tint.field : dark ? "#1c1c1d" : "#ffffff"
    readonly property color fieldBorder: tint ? tint.separator : dark ? "#3a3a3c" : "#d9d9de"
    readonly property color text: dark ? "#ffffff" : "#000000"
    readonly property color grey: tint ? tint.grey : "#8e8e93"
    readonly property color separator: tint ? tint.separator : dark ? "#38383a" : "#c8c7cc"
    readonly property color accent: look.accent ? look.accent : dark ? "#3e88f7" : "#0088ff"
    readonly property color badge: accent
    readonly property color badgeText: look.badgeText ? look.badgeText : "#ffffff"      // (a light accent by night: black on it)
    readonly property color mutedBadge: dark ? "#666666" : "#b6b6bb"
    readonly property color grouped: tint ? tint.page : dark ? "#000000" : "#efeff4"      // iOS's grouped lists: the page
    readonly property color card: tint ? tint.card : dark ? "#1c1c1d" : "#ffffff"         // and their cards
    readonly property color highlight: tint ? tint.highlight : dark ? "#2c2c2e" : "#e5e5ea"
    readonly property color menu: tint ? tint.menu : dark ? Qt.rgba(0.14, 0.14, 0.15, 0.96) : Qt.rgba(1, 1, 1, 0.96)
    readonly property color dayPill: dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(0.2, 0.33, 0.22, 0.35)
    readonly property color danger: dark ? "#ff453a" : "#ff3b30"
    readonly property color bubbleIn: look.bubbleIn ? look.bubbleIn : tint ? tint.bubbleIn : dark ? "#1d1d1d" : "#ffffff"
    readonly property color bubbleOut: own ? look.out : dark ? "#3e88f7" : "#e1ffc7"
    readonly property color inText: text
    readonly property color outText: outLight ? "#000000" : "#ffffff"
    readonly property color inMeta: dark ? Qt.rgba(1, 1, 1, 0.5) : "#8e8e93"
    readonly property color outMeta: !outLight ? Qt.rgba(1, 1, 1, 0.65) : look.outMeta ? look.outMeta
                                     : own ? Qt.rgba(accent.r * 0.75, accent.g * 0.75, accent.b * 0.75, 0.8) : Qt.rgba(0, 0.549, 0.035, 0.8)
    readonly property color check: !outLight ? "#ffffff" : look.check ? look.check : own ? accent : "#19c700"
    // a voice note's button and waveform (Telegram-iOS: the bubble's accent, faint where not yet played)
    readonly property color voiceOut: !outLight ? "#ffffff" : look.control ? look.control : own ? accent : "#3fc33b"
    readonly property color voiceOutFaint: !outLight ? Qt.rgba(1, 1, 1, 0.4) : own ? Qt.rgba(voiceOut.r, voiceOut.g, voiceOut.b, 0.35)
                                                                                    : Qt.rgba(0.25, 0.76, 0.23, 0.35)
    readonly property color voiceInFaint: dark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0.53, 1, 0.3)
    // the chats' background (Wallpaper.qml's spec): Telegram-iOS's own until Store has the one chosen (TDLib's
    // default background for each, or ours: the freeform four colours under Telegram's pattern, 50 % by day;
    // by night four others, the pattern inverted at 34 % — defaultBuiltinWallpaper, DefaultDarkPresentationTheme)
    property string wallDay: "dbddbb,6ba587,d5d88d,88b884;50;p;"
    property string wallNight: "598bf6,7a5eef,d67cff,f38b58;-34;p;"
    readonly property string wall: dark ? wallNight : wallDay
    readonly property string font: "Adwaita Sans"
}
