// Rich message cards inside a ChatPage bubble (0.9.8): contact, call, forwarded story,
// gift / upgraded gift, dice, game, checklist, paid media, giveaway / giveaway winners, invoice.
// Instantiated only by ChatPage's existing `attach` Loader when rowKind === "card",
// adding 0 objects to non-card rows. Each card type loads only its own sub-component.
pragma ComponentBehavior: Bound
import QtQuick
import "Money.js" as Money

Item {
    id: card
    property var info: null
    property string picPath: ""
    property bool out: false
    property real room: 260
    property bool hasCaption: false

    signal openContactChat(var userId)
    signal addContact(var info)
    signal openStory(var chatId, var storyId)
    signal openGift()
    signal toggleTask(int taskId, bool doneNow)
    signal notice(string text)
    signal held()

    readonly property string kind: info ? (info.kind || "") : ""
    readonly property color ink: out ? Theme.outText : Theme.inText
    readonly property color meta: out ? Theme.outMeta : Theme.inMeta
    readonly property color tint: out ? Theme.check : Theme.accent
    readonly property color panelBg: Qt.rgba(tint.r, tint.g, tint.b, out ? (Theme.outLight ? 0.10 : 0.16) : (Theme.dark ? 0.14 : 0.09))
    readonly property color sepColor: Qt.rgba(meta.r, meta.g, meta.b, 0.28)
    readonly property color goodColor: "#34c759"
    readonly property color goldColor: Theme.dark ? "#ffc337" : "#d3720a"
    readonly property real bottomPad: hasCaption ? 0 : 18

    function fmtNum(n) {
        return String(Math.floor(n || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, Tr.en ? "," : " ")
    }
    function fmtWhen(ts) {
        if (!ts)
            return ""
        const d = new Date(ts * 1000)
        return Tr.date(d.getDate(), d.getMonth() + 1, d.getFullYear()) + ", " + Qt.formatTime(d, "HH:mm")
    }
    function slotText(v) {
        if (v <= 0)
            return ""
        const syms = ["BAR", "🍇", "🍋", "7"]
        const n = v - 1
        return syms[n & 3] + " · " + syms[(n >> 2) & 3] + " · " + syms[(n >> 4) & 3]
    }

    width: bodyLoad.item ? bodyLoad.item.width : Math.min(room, 220)
    height: (bodyLoad.item ? bodyLoad.item.height : 40) + bottomPad

    Loader {
        id: bodyLoad
        active: card.kind !== ""
        sourceComponent: card.kind === "contact" ? contactComp
                       : card.kind === "call" ? callComp
                       : card.kind === "story" ? storyComp
                       : card.kind === "gift" ? giftComp
                       : card.kind === "dice" ? diceComp
                       : card.kind === "game" ? gameComp
                       : card.kind === "checklist" ? checklistComp
                       : card.kind === "paid" ? paidComp
                       : card.kind === "giveaway" ? giveawayComp
                       : card.kind === "giveawayWinners" ? giveawayWinnersComp
                       : card.kind === "invoice" ? invoiceComp : null
    }

    // ---- 1. Contact (messageContact) -----------------------------------------
    Component {
        id: contactComp
        Column {
            id: cCol
            readonly property var d: card.info || ({})
            readonly property bool hasUser: (d.userId || 0) > 0
            width: Math.min(card.room, 252)
            spacing: 8

            Item {
                width: parent.width; height: 46
                MouseArea {
                    anchors.fill: parent
                    pressAndHoldInterval: 350
                    onPressAndHold: card.held()
                    onClicked: if (cCol.hasUser) card.openContactChat(cCol.d.userId)
                }
                Avatar {
                    x: 0; y: 1
                    width: 44; height: 44
                    source: card.picPath
                    letters: cCol.d.letters || "?"
                    tint: cCol.d.tint || Theme.accent
                }
                Column {
                    x: 54; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 54
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: cCol.d.name || ""
                        color: card.ink
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: cCol.d.phone || ""
                        color: card.meta
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
            }
            Rectangle { width: parent.width; height: 0.5; color: card.sepColor }
            Row {
                width: parent.width; height: 32; spacing: 8
                Rectangle {
                    visible: cCol.hasUser
                    width: cCol.hasUser ? (parent.width - 8) / 2 : 0
                    height: parent.height; radius: 8
                    color: writeHit.pressed ? Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.24) : card.panelBg
                    Text {
                        anchors.centerIn: parent
                        text: Tr.t("Yozish")
                        color: card.tint
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: writeHit; anchors.fill: parent
                        pressAndHoldInterval: 350
                        onPressAndHold: card.held()
                        onClicked: card.openContactChat(cCol.d.userId)
                    }
                }
                Rectangle {
                    width: cCol.hasUser ? (parent.width - 8) / 2 : parent.width
                    height: parent.height; radius: 8
                    color: addHit.pressed ? Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.24) : card.panelBg
                    Text {
                        anchors.centerIn: parent
                        text: cCol.d.isContact ? Tr.t("Kontaktlarda") : Tr.t("Qo'shish")
                        color: cCol.d.isContact ? card.meta : card.tint
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: addHit; anchors.fill: parent
                        pressAndHoldInterval: 350
                        onPressAndHold: card.held()
                        onClicked: {
                            if (cCol.d.isContact)
                                card.notice(Tr.t("Bu kontakt allaqachon ro'yxatingizda"))
                            else
                                card.addContact(cCol.d)
                        }
                    }
                }
            }
        }
    }

    // ---- 2. Call (messageCall) -----------------------------------------------
    Component {
        id: callComp
        Item {
            id: callBox
            readonly property var d: card.info || ({})
            readonly property bool red: !!(d.missed || d.cancelled)
            readonly property string heading: {
                if (d.missed)
                    return Tr.t(d.video ? "O'tkazib yuborilgan video qo'ng'iroq" : "O'tkazib yuborilgan qo'ng'iroq")
                if (d.cancelled)
                    return Tr.t(d.video ? "Bekor qilingan video qo'ng'iroq" : "Bekor qilingan qo'ng'iroq")
                if (d.out)
                    return Tr.t(d.video ? "Chiquvchi video qo'ng'iroq" : "Chiquvchi qo'ng'iroq")
                return Tr.t(d.video ? "Kiruvchi video qo'ng'iroq" : "Kiruvchi qo'ng'iroq")
            }
            readonly property string sub: {
                if (d.durText)
                    return d.durText
                if (d.declined)
                    return Tr.t("Rad etildi")
                if (d.missed)
                    return Tr.t("Javob berilmadi")
                if (d.cancelled)
                    return Tr.t("Bekor qilingan")
                return Tr.t(d.video ? "Video qo'ng'iroq" : "Ovozli qo'ng'iroq")
            }
            width: Math.min(card.room, Math.max(196, Math.min(252, callTitle.implicitWidth + 54)))
            height: Math.max(44, callCol.implicitHeight + 4)

            MouseArea {
                anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.notice(Tr.t("Nullgram'da ovozli va video qo'ng'iroqlar hali yo'q"))
            }
            Column {
                id: callCol
                x: 0; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 46
                spacing: 3
                Text {
                    id: callTitle
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: callBox.heading
                    color: card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Row {
                    spacing: 4
                    Text {
                        text: callBox.d.out ? "↗" : "↙"
                        color: callBox.red ? Theme.danger : card.goodColor
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: callBox.sub
                        color: callBox.red ? Theme.danger : card.meta
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
            }
            Rectangle {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 38; height: 38; radius: 19
                color: callBox.red ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14) : card.panelBg
                Icon {
                    anchors.centerIn: parent
                    width: 19; height: 19
                    name: callBox.d.video ? "camera" : "phone"
                    color: callBox.red ? Theme.danger : card.tint
                }
            }
        }
    }

    // ---- 3. Forwarded Story (messageStory) -----------------------------------
    Component {
        id: storyComp
        Rectangle {
            id: stBox
            readonly property var d: card.info || ({})
            readonly property bool hasThumb: card.picPath !== "" || (d.mini || "") !== ""
            width: Math.min(card.room, 246)
            height: 76
            radius: 10
            clip: true
            color: stHit.pressed ? Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.22) : card.panelBg

            Rectangle { width: 3; height: parent.height; color: card.tint }

            Rectangle {
                id: stThumb
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 60; radius: 8
                color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.24)
                border.width: stBox.d.expired ? 0 : 1.5
                border.color: card.tint
                clip: true
                Image {
                    anchors.fill: parent; anchors.margins: stBox.d.expired ? 0 : 1.5
                    visible: stBox.hasThumb
                    asynchronous: true; smooth: true
                    fillMode: Image.PreserveAspectCrop
                    source: card.picPath !== "" ? "image://pic/6/44/" + card.picPath
                          : (stBox.d.mini || "") !== "" ? "image://pic/6/44/mini/" + stBox.d.mini : ""
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !stBox.hasThumb || !!stBox.d.isVideo
                    width: 18; height: 18
                    name: stBox.d.expired ? "eyeoff" : "play"
                    color: stBox.hasThumb ? "white" : card.tint
                }
            }
            Column {
                x: 64; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 74
                spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: Tr.t(stBox.d.viaMention ? "Hikoyada eslatma" : "Hikoya")
                    color: card.tint
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: stBox.d.author || Tr.t("Hikoya")
                    color: card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: Tr.t(stBox.d.expired ? "Hikoya mavjud emas" : "Hikoyani ko'rish")
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            MouseArea {
                id: stHit; anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.openStory(stBox.d.chatId || 0, stBox.d.storyId || 0)
            }
        }
    }

    // ---- 4. Gift & Upgraded Gift (messageGift, messageUpgradedGift) ----------
    Component {
        id: giftComp
        Rectangle {
            id: gBox
            readonly property var d: card.info || ({})
            readonly property bool up: !!d.upgraded && (d.bg1 || "") !== ""
            width: Math.min(card.room, 232)
            height: gCol.implicitHeight + 22
            radius: 12
            clip: true
            gradient: Gradient {
                GradientStop { position: 0; color: gBox.up ? gBox.d.bg1 : card.panelBg }
                GradientStop { position: 1; color: gBox.up ? (gBox.d.bg2 || gBox.d.bg1) : card.panelBg }
            }

            Column {
                id: gCol
                x: 12; y: 11; width: parent.width - 24
                spacing: 6
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 82; height: 82
                    Image {
                        anchors.fill: parent
                        visible: card.picPath !== ""
                        asynchronous: true; smooth: true
                        fillMode: Image.PreserveAspectFit
                        source: card.picPath === "" ? ""
                              : gBox.d.tgs ? "image://lottie/0/-/" + card.picPath : "image://thumb/" + card.picPath
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: card.picPath === ""
                        width: 44; height: 44
                        name: "gift"
                        color: gBox.up ? "white" : card.tint
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gBox.d.title || Tr.t("Hadya")
                    color: gBox.up ? "white" : card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                }
                Text {
                    visible: (gBox.d.text || "") !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gBox.d.text || ""
                    color: gBox.up ? Qt.rgba(1, 1, 1, 0.88) : card.meta
                    font.family: Theme.font; font.pixelSize: 13
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: (gBox.d.stars || 0) > 0 || !!gBox.d.upgraded
                    height: 24; radius: 12
                    width: starTxt.implicitWidth + 18
                    color: gBox.up ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(card.goldColor.r, card.goldColor.g, card.goldColor.b, 0.16)
                    Text {
                        id: starTxt
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: (gBox.d.stars || 0) > 0 ? "⭐ " + card.fmtNum(gBox.d.stars) : Tr.t("Noyob kolleksiya")
                        color: gBox.up ? "white" : card.goldColor
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 148); height: 30; radius: 15
                    color: gHit.pressed
                        ? (gBox.up ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.26))
                        : (gBox.up ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.15))
                    Text {
                        anchors.centerIn: parent
                        text: Tr.t("Ko'rish")
                        color: gBox.up ? "white" : card.tint
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
            }
            MouseArea {
                id: gHit; anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.openGift()
            }
        }
    }

    // ---- 5a. Dice (messageDice) ----------------------------------------------
    Component {
        id: diceComp
        Column {
            id: dCol
            readonly property var d: card.info || ({})
            readonly property string emoUrl: Emo.ready && d.emoji ? Emo.fileUrl(d.emoji) : ""
            readonly property string valText: {
                const v = d.value || 0
                if (v <= 0)
                    return Tr.t("Tashlanmoqda…")
                if (d.emoji === "🎰")
                    return card.slotText(v)
                return Tr.f("Natija: %1", v)
            }
            width: Math.min(card.room, Math.max(120, resPill.width + 12))
            spacing: 6

            Item {
                id: dieWrap
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120; height: 120
                // the dice's own animation, its end the value (the final_state sticker, played once);
                // 🎰 is five of them over each other, each fetched here
                property var slotPaths: []
                Component.onCompleted: {
                    const parts = dCol.d.slot || []
                    const got = parts.map(() => "")
                    parts.forEach((f, i) => store.fetch(f, 1, (path) => {
                        got[i] = path
                        if (got.every((x) => x !== ""))
                            dieWrap.slotPaths = got.slice()
                    }))
                }
                function replay() {
                    if (die.visible)
                        die.replay()
                    for (let i = 0; i < slotRep.count; i++)
                        if (slotRep.itemAt(i))
                            slotRep.itemAt(i).replay()
                }
                Lottie {
                    id: die
                    anchors.fill: parent
                    visible: !dCol.d.slot && card.picPath !== "" && !!dCol.d.tgs
                    path: visible ? card.picPath : ""
                    once: true
                    atEnd: !dCol.d.fresh
                }
                Image {         // a WebP one (not Telegram's own dice), or the emoji till the animation comes
                    anchors.fill: parent
                    visible: !die.visible && slotRep.count === 0 && (card.picPath !== "" || dCol.emoUrl !== "")
                    asynchronous: true; smooth: true
                    fillMode: Image.PreserveAspectFit
                    source: card.picPath !== "" && !dCol.d.tgs ? "image://thumb/" + card.picPath : dCol.emoUrl
                }
                Repeater {
                    id: slotRep
                    model: dieWrap.slotPaths
                    Lottie {
                        required property string modelData
                        anchors.fill: parent
                        path: modelData
                        once: true
                        atEnd: !dCol.d.fresh
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !die.visible && slotRep.count === 0 && card.picPath === "" && dCol.emoUrl === ""
                    text: dCol.d.emoji || "🎲"
                    font.pixelSize: 56
                }
                MouseArea {
                    anchors.fill: parent
                    pressAndHoldInterval: 350
                    onPressAndHold: card.held()
                    onClicked: dieWrap.replay()
                }
            }
            Rectangle {
                id: resPill
                anchors.horizontalCenter: parent.horizontalCenter
                height: 24; radius: 12
                width: resTxt.implicitWidth + 18
                color: card.panelBg
                Text {
                    id: resTxt
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: dCol.valText
                    color: card.tint
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
            }
        }
    }

    // ---- 5b. Game (messageGame) ----------------------------------------------
    Component {
        id: gameComp
        Rectangle {
            id: gmBox
            readonly property var d: card.info || ({})
            readonly property real innerW: width - 20
            readonly property real picH: d.hasPhoto ? Math.max(96, Math.min(156, Math.round(innerW * (d.h || 9) / Math.max(1, d.w || 16)))) : 0
            width: Math.min(card.room, 256)
            height: gmCol.implicitHeight + 16
            radius: 8; clip: true
            color: card.panelBg

            Rectangle { width: 3; height: parent.height; color: card.tint }

            Column {
                id: gmCol
                x: 12; y: 8; width: gmBox.innerW
                spacing: 5
                Text {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: "🎮 " + Tr.t("O'yin")
                    color: card.tint
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gmBox.d.title || Tr.t("O'yin")
                    color: card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                }
                Text {
                    visible: (gmBox.d.desc || "") !== ""
                    width: parent.width
                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gmBox.d.desc || ""
                    color: card.ink; opacity: 0.88
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: (gmBox.d.scoreText || "") !== ""
                    width: parent.width
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gmBox.d.scoreText || ""
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
                Image {
                    visible: !!gmBox.d.hasPhoto
                    width: parent.width; height: gmBox.picH
                    asynchronous: true; smooth: true
                    sourceSize: Qt.size(Math.max(16, Math.round(width)), Math.max(16, Math.round(height)))
                    source: !gmBox.d.hasPhoto ? ""
                          : card.picPath !== "" ? "image://pic/6/" + Math.round(width) + "/" + card.picPath
                          : (gmBox.d.mini || "") !== "" ? "image://pic/6/" + Math.round(width) + "/mini/" + gmBox.d.mini : ""
                }
                Rectangle {
                    width: parent.width; height: 30; radius: 8
                    color: gmHit.pressed ? Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.28) : Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.16)
                    Text {
                        anchors.centerIn: parent
                        text: Tr.t("Rasmiy ilovada oching")
                        color: card.tint
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
            }
            MouseArea {
                id: gmHit; anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.notice(Tr.t("Rasmiy ilovada oching"))
            }
        }
    }

    // ---- 6. Checklist (messageChecklist) -------------------------------------
    Component {
        id: checklistComp
        Column {
            id: clCol
            readonly property var d: card.info || ({})
            readonly property var tasks: d.tasks || []
            readonly property int doneCount: {
                let n = 0
                for (let k = 0; k < tasks.length; k++)
                    if (tasks[k].done)
                        n++
                return n
            }
            width: Math.min(card.room, 268)
            spacing: 0

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: clCol.d.title || Tr.t("Vazifalar ro'yxati")
                color: card.ink
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Item { width: 1; height: 2 }
            Text {
                textFormat: Text.PlainText
                text: Tr.f("%1 / %2 bajarildi", clCol.doneCount, clCol.tasks.length)
                color: card.meta
                font.family: Theme.font; font.pixelSize: 12
            }
            Item { width: 1; height: 8 }
            Repeater {
                model: clCol.tasks
                Item {
                    id: tkRow
                    required property var modelData
                    required property int index
                    readonly property bool isDone: !!modelData.done
                    readonly property string who: modelData.by || ""
                    width: clCol.width
                    height: Math.max(36, tkTextCol.implicitHeight + 12)

                    Rectangle {
                        x: 0; y: 8
                        width: 20; height: 20; radius: 10
                        color: tkRow.isDone ? card.tint : "transparent"
                        border.width: 1.5
                        border.color: tkRow.isDone ? card.tint : card.meta
                        Icon {
                            visible: tkRow.isDone
                            anchors.centerIn: parent
                            width: 13; height: 13
                            name: "check"
                            color: "white"
                        }
                    }
                    Column {
                        id: tkTextCol
                        x: 28; y: 6
                        width: parent.width - 28
                        spacing: 1
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: tkRow.modelData.text || ""
                            color: card.ink
                            opacity: tkRow.isDone ? 0.62 : 1.0
                            font.family: Theme.font; font.pixelSize: 14
                            font.strikeout: tkRow.isDone
                        }
                        Text {
                            visible: tkRow.isDone && tkRow.who !== ""
                            width: parent.width; elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: Tr.f("%1 bajardi", tkRow.who)
                            color: card.meta
                            font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        visible: tkRow.index + 1 < clCol.tasks.length
                        x: 28; y: parent.height - 0.5
                        width: parent.width - 28; height: 0.5
                        color: card.sepColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        pressAndHoldInterval: 350
                        onPressAndHold: card.held()
                        onClicked: {
                            if (clCol.d.canMark)
                                card.toggleTask(tkRow.modelData.id, !tkRow.isDone)
                            else
                                card.notice(Tr.t("Bu ro'yxat faqat ko'rish uchun"))
                        }
                    }
                }
            }
        }
    }

    // ---- 7. Paid Media (messagePaidMedia) ------------------------------------
    Component {
        id: paidComp
        Rectangle {
            id: pmBox
            readonly property var d: card.info || ({})
            readonly property real aspectH: Math.round(width * (d.h || 10) / Math.max(1, d.w || 16))
            width: Math.min(card.room, 256)
            height: Math.max(126, Math.min(184, aspectH))
            radius: 10; clip: true
            color: Theme.dark ? "#20242c" : "#2f3542"

            Image {
                anchors.fill: parent
                visible: (pmBox.d.mini || "") !== ""
                asynchronous: true; smooth: true
                fillMode: Image.PreserveAspectCrop
                source: (pmBox.d.mini || "") !== "" ? "image://pic/10/" + Math.round(parent.width) + "/mini/" + pmBox.d.mini : ""
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, pmHit.pressed ? 0.52 : 0.40)
            }
            Column {
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 34; radius: 17
                    width: pmPillRow.implicitWidth + 24
                    color: Qt.rgba(0, 0, 0, 0.58)
                    border.width: 1; border.color: Qt.rgba(1, 0.82, 0.25, 0.55)
                    Row {
                        id: pmPillRow
                        anchors.centerIn: parent
                        spacing: 5
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15; height: 15
                            name: "lock"
                            color: "#ffd042"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: "⭐ " + card.fmtNum(pmBox.d.stars || 0)
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: (pmBox.d.mediaCount || 0) > 1
                        ? Tr.n("%1 ta pullik media", pmBox.d.mediaCount)
                        : Tr.t("Pullik media")
                    color: Qt.rgba(1, 1, 1, 0.90)
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
            }
            MouseArea {
                id: pmHit; anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.notice(Tr.t("Rasmiy ilovada oching"))
            }
        }
    }

    // ---- 8a. Giveaway (messageGiveaway) --------------------------------------
    Component {
        id: giveawayComp
        Rectangle {
            id: gaBox
            readonly property var d: card.info || ({})
            width: Math.min(card.room, 260)
            height: gaCol.implicitHeight + 18
            radius: 10; clip: true
            color: card.panelBg

            Rectangle { width: 3; height: parent.height; color: card.tint }

            Column {
                id: gaCol
                x: 12; y: 9; width: parent.width - 22
                spacing: 5
                Row {
                    spacing: 6
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        name: "gift"; color: card.tint
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Konkurs")
                        color: card.tint
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: Tr.n("%1 ta g'olib", gaBox.d.winners || 1) + " · " + (gaBox.d.prize || "")
                    color: card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    visible: (gaBox.d.extra || "") !== ""
                    width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gaBox.d.extra || ""
                    color: card.ink; opacity: 0.88
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: (gaBox.d.channel || "") !== ""
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gaBox.d.channel + ((gaBox.d.extraChats || 0) > 0 ? " +" + gaBox.d.extraChats : "")
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
                Text {
                    visible: (gaBox.d.until || 0) > 0
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: Tr.f("G'oliblar: %1", card.fmtWhen(gaBox.d.until))
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
                Text {
                    visible: !!gaBox.d.onlyNew
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: Tr.t("Faqat yangi obunachilar")
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            MouseArea {
                anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.notice(Tr.t("Rasmiy ilovada oching"))
            }
        }
    }

    // ---- 8b. Giveaway Winners (messageGiveawayWinners) -----------------------
    Component {
        id: giveawayWinnersComp
        Rectangle {
            id: gwBox
            readonly property var d: card.info || ({})
            readonly property var names: d.names || []
            width: Math.min(card.room, 260)
            height: gwCol.implicitHeight + 18
            radius: 10; clip: true
            color: card.panelBg

            Rectangle { width: 3; height: parent.height; color: card.goldColor }

            Column {
                id: gwCol
                x: 12; y: 9; width: parent.width - 22
                spacing: 5
                Row {
                    spacing: 6
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        name: "star"; color: card.goldColor
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Tr.t("Konkurs g'oliblari")
                        color: card.goldColor
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                    }
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: Tr.n("%1 ta g'olib", gwBox.d.winners || 1) + " · " + (gwBox.d.prize || "")
                    color: card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    visible: gwBox.names.length > 0
                    width: parent.width; wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: gwBox.names.join(", ") + ((gwBox.d.moreNames || 0) > 0 ? " (+" + gwBox.d.moreNames + ")" : "")
                    color: card.ink; opacity: 0.90
                    font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: (gwBox.d.channel || "") !== ""
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gwBox.d.channel || ""
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
                Text {
                    visible: !!gwBox.d.refunded || (gwBox.d.unclaimed || 0) > 0
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: gwBox.d.refunded ? Tr.t("Konkurs bekor qilindi")
                        : Tr.n("%1 ta sovrin egasiz qoldi", gwBox.d.unclaimed)
                    color: card.meta
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            MouseArea {
                anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.notice(Tr.t("Rasmiy ilovada oching"))
            }
        }
    }

    // ---- 8c. Invoice (messageInvoice) ----------------------------------------
    Component {
        id: invoiceComp
        Rectangle {
            id: invBox
            readonly property var d: card.info || ({})
            readonly property real innerW: width - 20
            readonly property real picH: d.hasPhoto ? Math.max(92, Math.min(144, Math.round(innerW * (d.h || 9) / Math.max(1, d.w || 16)))) : 0
            readonly property string priceText: d.currency === "XTR"
                ? "⭐ " + card.fmtNum(d.amount || 0)
                : Money.money(d.amount || 0, d.currency || "USD", Tr.en)
            width: Math.min(card.room, 256)
            height: invCol.implicitHeight + 16
            radius: 10; clip: true
            color: card.panelBg

            Rectangle { width: 3; height: parent.height; color: card.tint }

            Column {
                id: invCol
                x: 12; y: 8; width: invBox.innerW
                spacing: 5
                Image {
                    visible: !!invBox.d.hasPhoto
                    width: parent.width; height: invBox.picH
                    asynchronous: true; smooth: true
                    sourceSize: Qt.size(Math.max(16, Math.round(width)), Math.max(16, Math.round(height)))
                    source: !invBox.d.hasPhoto ? ""
                          : card.picPath !== "" ? "image://pic/6/" + Math.round(width) + "/" + card.picPath
                          : (invBox.d.mini || "") !== "" ? "image://pic/6/" + Math.round(width) + "/mini/" + invBox.d.mini : ""
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: invBox.d.title || Tr.t("To'lov")
                    color: card.ink
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                }
                Text {
                    visible: (invBox.d.desc || "") !== ""
                    width: parent.width
                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: invBox.d.desc || ""
                    color: card.ink; opacity: 0.88
                    font.family: Theme.font; font.pixelSize: 13
                }
                Row {
                    spacing: 6
                    Rectangle {
                        height: 24; radius: 12
                        width: prTxt.implicitWidth + 16
                        color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.16)
                        Text {
                            id: prTxt; anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: invBox.priceText
                            color: card.tint
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: invBox.d.paid ? Tr.t("To'langan")
                            : invBox.d.isTest ? Tr.t("Sinov hisobi")
                            : Tr.t("Hisob-faktura")
                        color: invBox.d.paid ? card.goodColor : card.meta
                        font.family: Theme.font; font.pixelSize: 12; font.weight: invBox.d.paid ? Font.DemiBold : Font.Normal
                    }
                }
                Rectangle {
                    visible: !invBox.d.paid
                    width: parent.width; height: 30; radius: 8
                    color: invHit.pressed ? Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.28) : Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.16)
                    Text {
                        anchors.centerIn: parent
                        text: Tr.t("Rasmiy ilovada oching")
                        color: card.tint
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                }
            }
            MouseArea {
                id: invHit; anchors.fill: parent
                pressAndHoldInterval: 350
                onPressAndHold: card.held()
                onClicked: card.notice(Tr.t("Rasmiy ilovada oching"))
            }
        }
    }
}
