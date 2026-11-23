// What the user chose in the settings, beyond the night theme (Theme.dark); kept by Main.qml's
// Settings in ~/.config/OmonullOS/Nullgram.conf.
pragma Singleton
import QtQuick

QtObject {
    property bool autoGif: true         // GIFs come down and play by themselves
    property bool autoVoice: true       // voice notes and round videos come down by themselves
    property string silent: ""          // the channels whose posts go without a sound (their 🔔 off): ids, comma between
    property string lang: ""            // the Til page: "uz", "en", or "" for omonullOS Settings' language (Tr)
    property string recentEmoji: ""     // the emoji panel's «Yaqinda»: the last ones picked, newest first, space between
    property real playRate: 1           // voice notes' and songs' speed: 1, 1.5 or 2 (the mini player's 1x)
    property bool translateButton: true // the Til page's «Tarjima tugmasini ko'rsatish»: «Tarjima qilish» in a message's menu
    property bool translateChats: true  // its «Butun chatni tarjima qilish»: the chat's panel to translate it all
    // the Bildirishnomalar page (Telegram-iOS's InAppNotificationSettings): with the app in front, banners and their sound;
    // the names in banners (they show on the lock screen too); the Start tile's count: channels in it, messages or chats
    property bool inAppSounds: true
    property bool inAppPreview: true
    property bool lockNames: true
    property bool badgeChannels: true
    property bool badgeMessages: false

    // The Ko'rinish page: the chat theme chosen (Telegram's, by its emoji; "" the Classic one) and whether the chats'
    // background is that theme's (true: one was just chosen) or the one set since on «Chat fon rasmi» (TDLib's default)
    property string theme: ""
    property bool themeWall: false
    // The Chat mavzulari page («O'z mavzungizni yaratish»): the base theme by day ("classic" or "day") and by night
    // ("night" or "tinted") and each base's accent (Looks.js's key: a colour's name or a preset's; none: the base's first),
    // as JSON: { classic: "p106", night: "cyan" }. A chat theme chosen (`theme`) is over them.
    property string dayBase: "classic"
    property string nightBase: "night"
    property string accents: "{}"
    // The Matn o'lchami page (Telegram-iOS's TextSizeSelectionController): the chat's words, in points; 0 — the system's
    // («Tizim matn o'lchamidan foydalanish», iOS's default). iOS's seven PresentationFontSize stops (14 15 16 17 19 23 26,
    // its regular 17) a point under, as our words are 16 where iOS's are 17. omonullOS has no text size of its own yet:
    // the system's is the regular one.
    readonly property var textSizes: [13, 14, 15, 16, 18, 22, 25]
    readonly property int systemTextSize: 16
    property int textSize: 0
    readonly property int chatSize: textSize > 0 ? textSize : systemTextSize
    // The Xabar burchaklari page (Telegram-iOS's BubbleSettingsController): the bubbles' big corners in points, one of
    // `cornerStops`. iOS's slider is 8..16 (mainRadius, 16 by default); ours goes further down, to nearly square: iOS's
    // span was too little to see on the phone (owner, 2026-11-11). Not above 17: a one-line bubble (~34 pt) is a capsule
    // at 17 already (and our corners are quadratic: 17 looks iOS's circle of 16). The small ones, where a sender's
    // messages run together, iOS's auxiliaryRadius (main / 2) — ours 6 at 17, kept at that share. `mergeCorners` off
    // («Qo'shni burchaklarni moslash», iOS's «Adjust Adjacent Corners»): all big. `bubbleB`: nullgram.py Bubble's border
    // on the bottom and the tail's side (the tail needs 10).
    readonly property var cornerStops: [3, 5, 7, 9, 11, 13, 15, 17]
    // Avtomatik tungi rejim (Telegram-iOS's AutomaticThemeSwitchSetting): 0 off, 1 by the schedule — from nightFrom to
    // nightTo (minutes in the day; iOS's 22:00 and 9:00), or the sun's set and rise at `place` [lat, lon] (nightSun)
    property int autoNight: 0
    // ---- Ma'lumotlar va xotira (Telegram-iOS's DataAndStorageSettingsController) ----
    // auto-download per network (Using Cellular / Using Wi-Fi): JSON { mobile: net, wifi: net }, a net
    // { on, level 0..2 (Low/Medium/High), photo: kinds, video: kinds, file: kinds, videoMax, fileMax } and kinds
    // { contacts, others, groups, channels } (iOS's per media type: which chats); "" -> dlDefaults
    property string autoDl: ""
    readonly property var dlDefaults: ({
        mobile: { on: true, level: 1, photo: { contacts: true, others: true, groups: true, channels: true },
                  video: { contacts: true, others: true, groups: true, channels: true },
                  file: { contacts: false, others: false, groups: false, channels: false },
                  videoMax: 2621440, fileMax: 1048576 },
        wifi: { on: true, level: 1, photo: { contacts: true, others: true, groups: true, channels: true },
                video: { contacts: true, others: true, groups: true, channels: true },
                file: { contacts: true, others: true, groups: true, channels: true },
                videoMax: 15728640, fileMax: 3145728 } })
    readonly property var dl: { try { return autoDl ? JSON.parse(autoDl) : dlDefaults } catch (e) { return dlDefaults } }
    function setDl(network, net) {
        const all = JSON.parse(JSON.stringify(dl))
        all[network] = net
        autoDl = JSON.stringify(all)
    }
    // «Galereyaga saqlash» (iOS's Save to Photos): JSON { private|groups|channels: { photo, video } } -> ~/Downloads
    property string saveMedia: ""
    readonly property var saveTo: { try { return saveMedia ? JSON.parse(saveMedia) : ({}) } catch (e) { return ({}) } }
    // «Keshdagi mediani o'chirish» (iOS's Auto-Remove Cached Media): JSON { private|groups|channels: seconds, 0 never }
    property string keepMedia: ""
    readonly property var keep: { try { return keepMedia ? JSON.parse(keepMedia) : ({}) } catch (e) { return ({}) } }
    property int maxCache: 0            // «Keshning eng katta hajmi»: GB, 0 no limit
    property bool pauseMusic: true      // «Yozayotganda musiqani to'xtatish» (iOS's Pause Music While Recording)
    property bool storyHint: false      // the stories' gestures told once (the viewer's first opening)
    property bool tapNext: true         // Ko'rinish's «Bosilganda keyingi media» (iOS's Show Next Media on Tap; on there too)
    property bool callsTab: false       // So'nggi qo'ng'iroqlar's «Qo'ng'iroqlar yorlig'ini ko'rsatish» (iOS's Show Calls Tab)
    property string emojiSet: ""        // Ko'rinish › Emoji: "apple" (the downloaded set), "system" (the font), "" as omonullOS Settings say
    property bool largeEmoji: true      // Stikerlar va emoji's «Katta emoji» (iOS's Large Emoji): one to three alone big
    property bool nightSun: false
    property int nightFrom: 22 * 60
    property int nightTo: 9 * 60
    property string passcode: ""       // Kod-parol: this app's lock (Qt.md5 of «nullgram:» + the digits), "" off
    property int autoLock: 60           // «Avtomatik qulflash»: minutes away before it locks again (0: only at start)
    property var place: [41.3111, 69.2797]      // (Toshkent; iOS asks for the location once — we have none)
    // the sun's rise and set that day at `place` in local minutes (NOAA's sunrise equation), null where it does not
    function sunTimes(day) {
        const rad = Math.PI / 180, lat = place[0], lon = place[1]
        const start = new Date(day.getFullYear(), 0, 0)
        const n = Math.floor((day - start) / 86400000)
        const g = 2 * Math.PI / 365 * (n - 1)
        const eq = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g)
                             - 0.040849 * Math.sin(2 * g))
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
                     + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g)
        const c = (Math.cos(90.833 * rad) - Math.sin(lat * rad) * Math.sin(decl)) / (Math.cos(lat * rad) * Math.cos(decl))
        if (c < -1 || c > 1)
            return null
        const ha = Math.acos(c) / rad
        const tz = -day.getTimezoneOffset()
        const norm = (m) => ((Math.round(m) % 1440) + 1440) % 1440
        return { rise: norm(720 - 4 * (lon + ha) - eq + tz), set: norm(720 - 4 * (lon - ha) - eq + tz) }
    }
    // is it night now by the schedule
    function nightNow(now) {
        let from = nightFrom, to = nightTo
        if (nightSun) {
            const s = sunTimes(now)
            if (!s)
                return false
            from = s.set; to = s.rise
        }
        const m = now.getHours() * 60 + now.getMinutes()
        return from <= to ? m >= from && m < to : m >= from || m < to
    }
    property int corners: 17
    property bool mergeCorners: true
    function nearCorner(c) {
        let best = cornerStops[cornerStops.length - 1]
        for (const v of cornerStops)
            if (Math.abs(v - c) < Math.abs(best - c))
                best = v
        return best
    }
    function bubbleSmall(c, merge) { return merge ? Math.max(2, Math.round(c * 6 / 17)) : c }
    readonly property int bubbleR: corners
    readonly property int bubbleS: bubbleSmall(corners, mergeCorners)
    readonly property int bubbleB: Math.max(corners, 10)

    // The Quvvat tejash page (Telegram-iOS's EnergySavingSettingsScreen): below `saveBelow` % of charge, and not
    // charging, all of the heavy things go off; 4 or less — never, 96 or more — always (EnergyUsageSettings,
    // activationThreshold 15 by default). `saving` is set by Main.qml from the battery.
    property int saveBelow: 15
    property bool loopStickers: true    // «Stiker animatsiyalari»: stickers move (else their still)
    property bool loopEmoji: true       // «Emoji animatsiyalari»: an emoji alone plays (else the plain big emoji)
    property bool effects: true         // «Interfeys effektlari»: a tapped emoji's burst, the gifts' sparkles
    property bool saving: false
    // what is on now: each its own switch, unless saving
    readonly property bool gifs: autoGif && !saving
    readonly property bool stickers: loopStickers && !saving
    readonly property bool emoji: loopEmoji && !saving
    readonly property bool fx: effects && !saving
}
