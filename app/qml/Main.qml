// Nullgram. Pages go on and off as Telegram-iOS's navigation does
// (Display/NavigationTransitionCoordinator.swift): the new page from the right,
// the one under it 0.3 of the width to the left and dimmed to 0.15, a shadow at
// the new page's edge; 0.5 s on the iOS 26 spring. A page is made, filled and
// laid out before it moves (it says so with `ready`), so the motion has nothing
// to wait for. The motion is Animators: they run on the render thread.
import QtQuick
import QtCore

Rectangle {
    id: root
    width: 360; height: 760
    color: Theme.bg

    Store { id: store }
    Player { id: player; store: store }     // the sound playing, on over every page

    // iOS 26's spring (CASpringAnimation mass 1, stiffness 555, damping 47.1: 1 - (1 + wt)e^(-wt),
    // w = 23.56/s) over 0.5 s as two bezier segments, within 0.3 % of it
    readonly property var spring: [0.0744, 0.0298, 0.1307, 0.7931, 0.3680, 0.9301,
                                   0.4409, 0.9722, 0.4273, 0.9999, 1.0, 1.0]
    readonly property var easeInOut: [0.42, 0.0, 0.58, 1.0, 1.0, 1.0]

    property var pages: []              // bottom first
    property Item topPage: pages.length ? pages[pages.length - 1] : null
    property Item underPage: pages.length > 1 ? pages[pages.length - 2] : null
    property bool moving: motion.running

    Component { id: loginPage; LoginPage {} }
    Component { id: apiKeyPage; ApiKeyPage { first: true } }
    Component { id: chatsPage; HomePage {} }

    // the night theme and the other choices, kept (~/.config/OmonullOS/Nullgram.conf)
    Settings {
        id: prefs
        property bool dark: false
        property bool autoGif: true
        property bool autoVoice: true
        property string silent: ""
        property string recentEmoji: ""
        property string lang: ""
        property real playRate: 1
        property bool translateButton: true
        property bool translateChats: true
        property int saveBelow: 15
        property bool loopStickers: true
        property bool loopEmoji: true
        property bool effects: true
        property bool inAppSounds: true
        property bool inAppPreview: true
        property bool lockNames: true
        property bool badgeChannels: true
        property bool badgeMessages: false
        property string theme: ""
        property bool themeWall: false
        property string dayBase: "classic"
        property string nightBase: "night"
        property string accents: "{}"
        property int textSize: 0
        property int corners: 17
        property bool mergeCorners: true
        property int autoNight: 0
        property bool tapNext: true
        property bool callsTab: false
        property bool storyHint: false
        property bool largeEmoji: true
        property string emojiSet: ""
        property string autoDl: ""
        property string saveMedia: ""
        property string keepMedia: ""
        property int maxCache: 0
        property bool pauseMusic: true
        property bool nightSun: false
        property int nightFrom: 1320
        property int nightTo: 540
        property string passcode: ""
        property int autoLock: 60
    }
    Component.onCompleted: {
        Theme.dark = prefs.dark
        Prefs.autoGif = prefs.autoGif
        Prefs.autoVoice = prefs.autoVoice
        Prefs.silent = prefs.silent
        Prefs.recentEmoji = prefs.recentEmoji
        Prefs.lang = prefs.lang
        Prefs.playRate = prefs.playRate
        Prefs.translateButton = prefs.translateButton
        Prefs.translateChats = prefs.translateChats
        Prefs.saveBelow = prefs.saveBelow
        Prefs.loopStickers = prefs.loopStickers
        Prefs.loopEmoji = prefs.loopEmoji
        Prefs.effects = prefs.effects
        Prefs.inAppSounds = prefs.inAppSounds
        Prefs.inAppPreview = prefs.inAppPreview
        Prefs.lockNames = prefs.lockNames
        Prefs.badgeChannels = prefs.badgeChannels
        Prefs.badgeMessages = prefs.badgeMessages
        Prefs.theme = prefs.theme
        Prefs.themeWall = prefs.themeWall
        Prefs.dayBase = prefs.dayBase
        Prefs.nightBase = prefs.nightBase
        Prefs.accents = prefs.accents
        Prefs.textSize = prefs.textSize
        Prefs.corners = Prefs.nearCorner(prefs.corners)     // (16 was the default before the stops)
        Prefs.mergeCorners = prefs.mergeCorners
        Prefs.autoNight = prefs.autoNight
        Prefs.tapNext = prefs.tapNext
        Prefs.callsTab = prefs.callsTab
        Prefs.storyHint = prefs.storyHint
        Prefs.largeEmoji = prefs.largeEmoji
        Prefs.emojiSet = prefs.emojiSet
        Prefs.autoDl = prefs.autoDl
        Prefs.saveMedia = prefs.saveMedia
        Prefs.keepMedia = prefs.keepMedia
        Prefs.maxCache = prefs.maxCache
        Prefs.pauseMusic = prefs.pauseMusic
        Prefs.nightSun = prefs.nightSun
        Prefs.nightFrom = prefs.nightFrom
        Prefs.nightTo = prefs.nightTo
        Prefs.passcode = prefs.passcode
        Prefs.autoLock = prefs.autoLock
        locked = Prefs.passcode !== ""
        nightClock.look()
    }
    // Avtomatik tungi rejim: once a minute (and when the schedule changes) the night by it — only when that changes,
    // so «Tungi rejim» turned by hand stays till the next turn of the schedule (as iOS)
    Timer {
        id: nightClock
        property int was: -1
        interval: 60000; repeat: true; running: Prefs.autoNight > 0
        onTriggered: look()
        function look() {
            if (Prefs.autoNight === 0) {
                was = -1
                return
            }
            const now = Prefs.nightNow(new Date()) ? 1 : 0
            if (now !== was)
                Theme.dark = now === 1
            was = now
        }
    }
    Connections {
        target: Prefs
        function onTapNextChanged() { prefs.tapNext = Prefs.tapNext }
        function onCallsTabChanged() { prefs.callsTab = Prefs.callsTab }
        function onStoryHintChanged() { prefs.storyHint = Prefs.storyHint }
        function onLargeEmojiChanged() { prefs.largeEmoji = Prefs.largeEmoji }
        function onEmojiSetChanged() { prefs.emojiSet = Prefs.emojiSet }
        function onAutoDlChanged() { prefs.autoDl = Prefs.autoDl }
        function onSaveMediaChanged() { prefs.saveMedia = Prefs.saveMedia }
        function onKeepMediaChanged() { prefs.keepMedia = Prefs.keepMedia }
        function onMaxCacheChanged() { prefs.maxCache = Prefs.maxCache }
        function onPauseMusicChanged() { prefs.pauseMusic = Prefs.pauseMusic }
        function onAutoNightChanged() { prefs.autoNight = Prefs.autoNight; nightClock.was = -1; nightClock.look() }
        function onNightSunChanged() { prefs.nightSun = Prefs.nightSun; nightClock.was = -1; nightClock.look() }
        function onNightFromChanged() { prefs.nightFrom = Prefs.nightFrom; nightClock.was = -1; nightClock.look() }
        function onPasscodeChanged() { prefs.passcode = Prefs.passcode }
        function onAutoLockChanged() { prefs.autoLock = Prefs.autoLock }
        function onNightToChanged() { prefs.nightTo = Prefs.nightTo; nightClock.was = -1; nightClock.look() }
    }
    // power saving on now (Telegram-iOS's automaticEnergyUsageShouldBeOnNow): always at 96 and over, never at 4 and
    // under, else when the battery is under the level and not charging
    Binding {
        target: Prefs; property: "saving"
        value: Prefs.saveBelow >= 96 || (Prefs.saveBelow > 4 && battery.level >= 0 && battery.level < Prefs.saveBelow
                                         && !battery.charging)
    }
    Connections { target: Theme; function onDarkChanged() { prefs.dark = Theme.dark } }
    Connections {
        target: Prefs
        function onAutoGifChanged() { prefs.autoGif = Prefs.autoGif }
        function onAutoVoiceChanged() { prefs.autoVoice = Prefs.autoVoice }
        function onSilentChanged() { prefs.silent = Prefs.silent }
        function onRecentEmojiChanged() { prefs.recentEmoji = Prefs.recentEmoji }
        function onLangChanged() { prefs.lang = Prefs.lang }
        function onPlayRateChanged() { prefs.playRate = Prefs.playRate }
        function onTranslateButtonChanged() { prefs.translateButton = Prefs.translateButton }
        function onTranslateChatsChanged() { prefs.translateChats = Prefs.translateChats }
        function onSaveBelowChanged() { prefs.saveBelow = Prefs.saveBelow }
        function onLoopStickersChanged() { prefs.loopStickers = Prefs.loopStickers }
        function onLoopEmojiChanged() { prefs.loopEmoji = Prefs.loopEmoji }
        function onEffectsChanged() { prefs.effects = Prefs.effects }
        function onInAppSoundsChanged() { prefs.inAppSounds = Prefs.inAppSounds }
        function onInAppPreviewChanged() { prefs.inAppPreview = Prefs.inAppPreview }
        function onLockNamesChanged() { prefs.lockNames = Prefs.lockNames }
        function onBadgeChannelsChanged() { prefs.badgeChannels = Prefs.badgeChannels }
        function onBadgeMessagesChanged() { prefs.badgeMessages = Prefs.badgeMessages }
        function onThemeChanged() { prefs.theme = Prefs.theme }
        function onThemeWallChanged() { prefs.themeWall = Prefs.themeWall }
        function onDayBaseChanged() { prefs.dayBase = Prefs.dayBase }
        function onNightBaseChanged() { prefs.nightBase = Prefs.nightBase }
        function onAccentsChanged() { prefs.accents = Prefs.accents }
        function onTextSizeChanged() { prefs.textSize = Prefs.textSize }
        function onCornersChanged() { prefs.corners = Prefs.corners }
        function onMergeCornersChanged() { prefs.mergeCorners = Prefs.mergeCorners }
    }

    // the first page: the sign-in until Telegram says we are in, then the chats (none while TDLib opens its
    // database: a signed-in start made the sign-in page there, for the ~0.3 s until Ready, for nothing)
    property string base: store.auth === "Ready" ? "chats"
                        : store.auth === "NeedApiKey" ? "apikey"
                        : store.renewing ? "login"
                        : store.auth === "" || store.auth === "LoggingOut" || store.auth === "Closed"
                          || (store.auth === "WaitTdlibParameters" && store.error === "") ? "" : "login"
    onBaseChanged: {
        for (const p of pages)
            p.destroy()
        pages = []
        dropSpare()
        if (base)
            pages = [(base === "chats" ? chatsPage : base === "apikey" ? apiKeyPage : loginPage)
                     .createObject(stack, { store: store, nav: root, player: player })]
        if (base)
            safe.ready()        // (the shell's "Loading..." off: Safe.ready)
    }

    Item { id: stack; anchors.fill: parent }

    Rectangle {          // over the page under, darker as the new one covers it
        id: dim
        parent: stack
        anchors.fill: parent
        color: "black"
        opacity: 0
        visible: opacity > 0
        z: 1.5
    }

    // a new page in from the right, as soon as it has what it shows (or after 0.7 s anyway)
    function push(component, props) {
        if (moving)
            return null
        props.store = store
        props.nav = root
        props.player = player
        const p = component.createObject(stack, props)
        p.x = root.width
        p.z = 2
        if (underPage)
            underPage.visible = false
        topPage.z = 1
        pages = pages.concat([p])
        const go = () => { if (topPage === p && !p.started) { p.started = true; slide(1, 500, spring) } }
        if (p.ready)
            Qt.callLater(go)
        else {
            p.readyChanged.connect(go)
            wait.callback = go
            wait.restart()
        }
        return p
    }

    // A chat page made ahead while nothing moves (Telegram X keeps one MessagesController and reuses it):
    // making ChatPage took ~60-100 ms of the tap's frame and its first layout as much again. It is made a
    // bit at a time between frames (an asynchronous incubator: QQuickView's controller), hidden, without
    // a chat; pushChat gives it the chat. One is made again a while after it was taken.
    property var spare: null
    property var spareIncubator: null
    Component { id: spareMaker; ChatPage {} }
    function makeSpare() {
        if (spare || spareIncubator || base !== "chats" || moving)
            return
        const t0 = Date.now()
        const inc = spareMaker.incubateObject(stack, { store: store, nav: root, player: player, chatId: 0,
                                                       spare: true, x: root.width },
                                              Qt.Asynchronous)
        const took = () => {
            if (spareIncubator !== inc)
                return
            spareIncubator = null
            if (inc.status === Component.Ready) {
                spare = inc.object
                if (td.fps)
                    console.warn("nullgram: spare chat page made in", Date.now() - t0, "ms")
            } else if (inc.status === Component.Error) {
                console.warn("nullgram: spare chat page:", spareMaker.errorString())
            }
        }
        spareIncubator = inc
        if (inc.status === Component.Loading)
            inc.onStatusChanged = took
        else
            took()
    }
    function dropSpare() {
        if (spareIncubator) {
            spareIncubator.forceCompletion()
            spareIncubator = null
        }
        if (spare) {
            spare.destroy()
            spare = null
        }
    }
    Timer {             // a spare when nothing has moved and no finger has touched for a while (td.quietMs):
        id: spareTimer  // its last step holds a frame (~25 ms of QML, the page's first drawing more)
        interval: 1200
        repeat: true
        running: root.base === "chats" && !root.spare && !root.spareIncubator && !root.moving
        onTriggered: if (td.quietMs() > 2500) root.makeSpare()
    }

    // Fonts made ready while nothing moves. The first name in a script not met yet at a size and weight
    // (𝓐𝓵𝓲, ᗩᒪI, Arabic, Han...) had Qt open its fallback fonts one by one until one had it -- 𝓐 is in the
    // 165th of ~180 here -- and one Text took 30-50 ms in a flick. A character no font has opens them all for
    // the common script; one of each other script, its own list. Measured once each here (a few ms a step,
    // only when no finger has touched for a while), the rows' Texts find them open. Nothing drawn: the same
    // fonts as before, only opened earlier. (TextMetrics, not a hidden Text: that one in the scene had the
    // window draw a frame for every step, ~13 a second for the first ~10 s after start.)
    TextMetrics { id: fontWarm; font.family: Theme.font }
    property int fontStep: 0
    readonly property var fontKinds: [12, 13, 14, 15, 16, 17, Prefs.chatSize].map((px) => [px, Font.Normal])
                                     .concat([13, 14, 15, 16, 17, 19, 23].map((px) => [px, Font.DemiBold]))   // (19, 23: the chat list's initials)
    readonly property var fontChars: [String.fromCodePoint(0x10FFFD), "😀", "ب", "王", "한", "あ", "ש", "ह", "ก", "ব", "ᗷ"]
    Timer {
        interval: 60
        repeat: true
        running: root.fontStep < root.fontKinds.length * root.fontChars.length
        onTriggered: {
            if (root.moving || td.quietMs() < 800)
                return
            const kind = root.fontKinds[Math.floor(root.fontStep / root.fontChars.length)]
            fontWarm.font.pixelSize = kind[0]
            fontWarm.font.weight = kind[1]
            fontWarm.text = "A" + root.fontChars[root.fontStep % root.fontChars.length]
            void fontWarm.advanceWidth              // (shaped now: the fallback fonts opened)
            root.fontStep++
        }
    }

    // a chat, on the spare page when there is one (as push(component, props) does otherwise)
    function pushChat(component, props) {
        const p = spare
        if (!p || moving)
            return push(component, props)
        spare = null
        if (td.fps && store.tapAt)
            console.warn("nullgram: open on the spare page")
        const t0 = Date.now()
        for (const k in props)
            p[k] = props[k]
        if (td.fps && store.tapAt)
            console.warn("nullgram: open props set in", Date.now() - t0, "ms, tap +", Date.now() - store.tapAt)
        p.z = 2
        p.x = root.width
        p.visible = true
        if (underPage)
            underPage.visible = false
        topPage.z = 1
        pages = pages.concat([p])
        p.begin()
        const go = () => { if (topPage === p && !p.started) { p.started = true; slide(1, 500, spring) } }
        if (p.ready)
            Qt.callLater(go)
        else {
            p.readyChanged.connect(go)
            wait.callback = go
            wait.restart()
        }
        return p
    }

    // the shell's back: a menu or the like on the page closes first
    function back() {
        if (storyView && storyView.open) {
            storyView.back()
            return
        }
        if (player.sheetOpen) {
            player.sheetOpen = false
            return
        }
        if (!(topPage && topPage.dismiss && topPage.dismiss()))
            pop()
    }

    function pop() {
        if (pages.length > 1 && !moving) {
            underPage.visible = true
            slide(0, 500, spring)
        }
    }

    // a basic group became a supergroup: the pages about it (`follows`) now about the new chat
    function rechat(from, to) {
        for (const p of pages)
            if (p.follows && p.chatId === from)
                p.chatId = to
    }

    // back to `to`, a page under the top (what was between goes at once): a chat's background set, its profile again
    function popTo(to) {
        const at = pages.indexOf(to)
        if (at < 0 || moving)
            return
        if (pages.length - at > 2) {
            const mid = pages.slice(at + 1, -1)
            pages = pages.slice(0, at + 1).concat([pages[pages.length - 1]])
            mid.forEach((p) => p.destroy())
        }
        pop()
    }

    // back to the first page (what was between goes at once): a chat that is gone, its pages over it
    function popHome() {
        if (pages.length > 2 && !moving) {
            const mid = pages.slice(1, -1)
            pages = [pages[0], pages[pages.length - 1]]
            mid.forEach((p) => p.destroy())
        }
        pop()
    }

    // Yangi suhbat (0.9.5): entry point for ChatListPage's compose button (and ContactsPage)
    function newChat() {
        const c = Qt.createComponent("NewChatPage.qml")
        if (c.status === Component.Error) {
            console.warn("nullgram:", c.errorString())
            return null
        }
        return push(c, {})
    }

    // our story posted in the background (StoryCreatePage left at once): how it ended
    Connections {
        target: store
        function onStoryPosted(ok, err) { root.say(ok ? Tr.t("Hikoya joylandi") : (err || Tr.t("Hikoya joylanmadi"))) }
    }

    // Hikoya joylash: entry point for ChatListPage's ⊕ and «Hikoyam» (checks canPostStory first)
    property bool _storyChecking: false
    function storyCreate() {
        if (_storyChecking || moving)
            return
        if (store.storyPostingActive) {
            say(Tr.t("Hikoya yuklanmoqda…"))
            return
        }
        _storyChecking = true
        store.canPostStory((res) => {
            root._storyChecking = false
            if (!res.ok) {
                root.say(res.text || Tr.t("Hikoya joylab bo'lmaydi"))
                return
            }
            const c = Qt.createComponent("StoryCreatePage.qml")
            if (c.status === Component.Error) {
                console.warn("nullgram:", c.errorString())
                return
            }
            root.push(c, {})
        })
    }

    // drop intermediate pages under the top page (like popHome, keeping the newly opened chat on top)
    property var _trimFor: null
    function trimToHome() {
        if (pages.length > 2 && !moving) {
            const mid = pages.slice(1, -1)
            pages = [pages[0], pages[pages.length - 1]]
            mid.forEach((p) => p.destroy())
        }
    }
    function openCreatedChat(chatId) {
        const p = pushChat(spareMaker, { chatId: chatId })
        if (p)
            _trimFor = p
        return p
    }
    onMovingChanged: if (!moving && _trimFor) {
        const target = _trimFor
        _trimFor = null
        if (topPage === target)
            trimToHome()
    }

    Timer {
        id: wait
        interval: 700
        property var callback: null
        onTriggered: if (callback) callback()
    }

    // progress p: 0 the page under alone, 1 the top page over it
    function place(p) {
        topPage.x = root.width * (1 - p)
        underPage.x = -root.width * 0.3 * p
        dim.opacity = 0.15 * p
    }

    property real _target: 1
    function slide(p, ms, curve) {
        motion.stop()
        // the page goes: its keyboard with it, not after it is gone (IMG_0086; Qt's text input
        // tells the shell only when the field is destroyed)
        if (p === 0 && osk.h > 0)
            osk.hide()
        for (const a of [toTop, toUnder, toDim]) {
            a.duration = ms
            a.easing.bezierCurve = curve
        }
        toTop.target = topPage
        toUnder.target = underPage
        toTop.to = root.width * (1 - p)
        toUnder.to = -root.width * 0.3 * p
        toDim.to = 0.15 * p
        _target = p
        motion.start()
    }

    ParallelAnimation {
        id: motion
        XAnimator { id: toTop; easing.type: Easing.BezierSpline }
        XAnimator { id: toUnder; easing.type: Easing.BezierSpline }
        OpacityAnimator { id: toDim; target: dim; easing.type: Easing.BezierSpline }
        onFinished: {
            if (root._target === 0) {         // popped: the top page goes
                const p = root.topPage
                root.pages = root.pages.slice(0, -1)
                p.destroy()
                root.topPage.z = 2
                root.topPage.x = 0
            } else if (root.underPage) {
                root.underPage.visible = false   // covered: nothing to draw under the top page
            }
        }
    }

    // the left edge of a pushed page pulls it back: let go past half (or flung) it goes
    // in distance/velocity clamped to 0.05..0.2 s, else it comes back in 0.1 s
    MouseArea {          // (below the header: its back button is under the left edge too)
        y: 56
        width: 20; height: parent.height - y
        z: 10
        enabled: root.pages.length > 1 && !root.moving
        property real lastX: 0
        property real lastT: 0
        property real velocity: 0
        onPressed: (m) => {
            lastX = m.x; lastT = Date.now(); velocity = 0
            root.underPage.visible = true
        }
        onPositionChanged: (m) => {
            const t = Date.now()
            if (t > lastT)
                velocity = 0.6 * velocity + 0.4 * (m.x - lastX) * 1000 / (t - lastT)
            root.place(1 - Math.max(0, Math.min(root.width, root.topPage.x + m.x - lastX)) / root.width)
            lastX = m.x; lastT = t
        }
        onReleased: {
            if (root.topPage.x > root.width / 2 || velocity > 500)
                root.slide(0, 1000 * Math.max(0.05, Math.min(0.2, (root.width - root.topPage.x) / Math.max(1, Math.abs(velocity)))),
                           root.easeInOut)
            else
                root.slide(1, 100, root.easeInOut)
        }
    }

    // the shell's back button (it sends Escape). A shortcut, not Keys on this item: those only
    // hear it while nothing under them has the focus, and the field or a page soon takes it
    Shortcut {
        sequences: ["Esc", "Back"]
        context: Qt.ApplicationShortcut
        onActivated: root.back()
    }

    PlayerSheet { player: player; store: store }     // a song's player, over every page

    // the speed changed: said at the foot (Telegram-iOS's Conversation.AudioRateTooltip…)
    Toast {
        id: toast
        floor: root.topPage && root.topPage.toastFloor !== undefined ? root.topPage.toastFloor : 0
    }
    Connections {
        target: player
        function onRated(r) {
            toast.show(r === 1.5 ? Tr.t("Ovoz 1.5X tezlikda ijro etiladi.")
                     : r === 2 ? Tr.t("Ovoz ikki baravar tez ijro etiladi.")
                     : Tr.t("Ovoz odatiy tezlikda ijro etiladi."), player.rateText(r).toUpperCase())
        }
    }

    // Kod-parol (PasscodePage): locked at the start and after «Avtomatik qulflash»'s minutes away (iOS's
    // PasscodeEntryController over everything); the window gone from the screen counts as away
    property bool locked: false
    property real awayAt: 0
    function say(words) { toast.show(words) }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                if (!root.awayAt)
                    root.awayAt = Date.now()
            } else {
                if (Prefs.passcode && Prefs.autoLock > 0 && root.awayAt && Date.now() - root.awayAt >= Prefs.autoLock * 60000)
                    root.locked = true
                root.awayAt = 0
            }
        }
    }
    // Hikoyalar (Q): over every page. Not made with the window: its ~200 ms (a hidden viewer's texts, field,
    // sheets) held the first frame. Made in the background once the app is quiet after start, or at once
    // when stories are opened sooner (stories()); null until then.
    Loader {
        id: storyLoader
        z: 900
        anchors.fill: parent
        active: false
        asynchronous: true
        sourceComponent: Component { StoryViewer {} }
    }
    readonly property Item storyView: storyLoader.item
    function stories() {
        if (!storyLoader.item) {
            storyLoader.asynchronous = false        // (one being made in the background: finished now)
            storyLoader.active = true
        }
        return storyLoader.item
    }
    Timer {
        interval: 1000
        repeat: true
        running: !storyLoader.active
        onTriggered: if (td.quietMs() > 0 && !root.moving) storyLoader.active = true
    }
    readonly property alias lockPad: lockPad
    PasscodePad {
        id: lockPad
        visible: root.locked && Prefs.passcode !== ""
        z: 1000
        mode: "check"
        onPassed: root.locked = false
    }
}
