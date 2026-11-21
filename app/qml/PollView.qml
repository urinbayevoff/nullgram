// A poll in its bubble (Telegram-iOS's ChatMessagePollBubbleContentNode): the question, what kind it
// is, the answers. Not yet voted: a circle by each (a square-ish tick for several answers, then
// «Ovoz berish»); a tap votes. Voted or closed: each answer's share in per cent, a bar growing to it,
// ours ticked; a quiz's right answer green, ours red when wrong, its 💡 the explanation. At the foot
// how many voted, or «Natijalarni ko'rish» when voters may be seen; the bubble's time goes by it.
import QtQuick

Item {
    id: pv
    property var poll: null             // TDLib's poll
    property bool out: false
    signal vote(var ids)                // 0-based answers chosen ([] takes the vote back)
    signal voters()
    signal explain(string text)
    signal held()                       // a long press on it: the message's menu

    readonly property bool quiz: !!poll && poll.type["@type"] === "pollTypeQuiz"
    readonly property bool closed: !!poll && poll.is_closed
    readonly property bool voted: !!poll && poll.options.some((o) => o.is_chosen)
    readonly property bool sending: !!poll && poll.options.some((o) => o.is_being_chosen)
    readonly property bool results: (voted || closed) && (!poll || poll.can_see_results !== false)
    readonly property bool many: !!poll && poll.allows_multiple_answers && !quiz
    readonly property var rightOnes: quiz && poll.type.correct_option_ids ? poll.type.correct_option_ids : []
    // the answers in the order to show them (option_order, when the poll is shuffled)
    readonly property var order: !poll ? [] : poll.option_order && poll.option_order.length === poll.options.length
                                 ? poll.option_order : poll.options.map((o, k) => k)
    property var picked: []             // several answers: the ones ticked, not yet sent
    onPollChanged: if (voted || closed) picked = []

    readonly property color ink: out ? Theme.outText : Theme.inText
    readonly property color tint: out ? Theme.check : Theme.accent
    readonly property color meta: out ? Theme.outMeta : Theme.inMeta
    readonly property color good: "#34c759"
    readonly property color bad: Theme.danger

    // the kind, as Telegram-iOS words it (Anonymous Poll, Quiz, Final Results...)
    readonly property string kindText: !poll ? "" : closed ? Tr.t(quiz ? "Yakunlangan viktorina" : "Yakunlangan so'rovnoma")
        : Tr.t((poll.is_anonymous ? "Anonim " : "Ochiq ") + (quiz ? "viktorina" : "so'rovnoma"))

    function votes(n) {
        return n === 0 ? Tr.t("Hali ovoz yo'q") : Tr.n("%1 ta ovoz", n)
    }

    width: 260
    height: col.height

    Column {
        id: col
        width: parent.width
        spacing: 0
        Text {
            width: parent.width - (lamp.visible ? 28 : 0)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: pv.poll ? pv.poll.question.text : ""
            color: pv.ink
            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
        }
        Item { width: 1; height: 3 }
        Text {
            text: pv.kindText
            color: pv.meta
            font.family: Theme.font; font.pixelSize: 13
        }
        Item { width: 1; height: 8 }
        Repeater {
            model: pv.order
            delegate: Item {
                id: opt
                required property int modelData
                readonly property var o: pv.poll.options[modelData]
                readonly property bool mine: o.is_chosen || o.is_being_chosen
                readonly property bool ticked: pv.picked.indexOf(modelData) >= 0
                readonly property bool isRight: pv.rightOnes.indexOf(modelData) >= 0
                readonly property real share: pv.results ? o.vote_percentage / 100 : 0
                width: col.width
                height: Math.max(44, words.implicitHeight + 22)
                Text {           // the share, where the circle was
                    visible: pv.results
                    x: 0; y: 11
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    text: opt.o.vote_percentage + "%"
                    color: pv.ink
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                Rectangle {      // the circle (several answers: a rounder square), ticked when chosen
                    visible: !pv.results
                    x: 6; y: 10
                    width: 22; height: 22; radius: pv.many ? 7 : 11
                    color: opt.ticked || opt.o.is_being_chosen ? pv.tint : "transparent"
                    border.color: opt.ticked || opt.o.is_being_chosen ? pv.tint : pv.meta; border.width: 1.5
                    Icon {
                        visible: opt.ticked || opt.o.is_being_chosen
                        anchors.centerIn: parent
                        width: 16; height: 16
                        name: "check"
                        color: "white"
                    }
                }
                Text {
                    id: words
                    x: 42; y: 11
                    width: parent.width - x - (badge.visible ? 26 : 0)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: opt.o.text.text
                    color: pv.ink
                    font.family: Theme.font; font.pixelSize: 15
                }
                Rectangle {      // ours (✓), a quiz's right (✓ green) or ours wrong (✕ red), by the bar's end
                    id: badge
                    visible: pv.results && (opt.mine || (pv.quiz && opt.isRight))
                    anchors.right: parent.right
                    y: 11
                    width: 18; height: 18; radius: 9
                    color: pv.quiz ? (opt.isRight ? pv.good : pv.bad) : pv.tint
                    Icon {
                        anchors.centerIn: parent
                        width: 13; height: 13
                        name: pv.quiz && !opt.isRight ? "cross" : "check"
                        color: "white"
                    }
                }
                Rectangle {      // the bar: grows to the share when the results come (iOS animates it)
                    visible: pv.results
                    x: 42
                    y: parent.height - 9
                    height: 4; radius: 2
                    width: Math.max(4, (parent.width - 42) * opt.share)
                    color: pv.quiz && (opt.mine || opt.isRight) ? (opt.isRight ? pv.good : pv.bad) : pv.tint
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
                Rectangle {      // the line under each answer, while voting
                    visible: !pv.results
                    x: 42; y: parent.height - 0.5
                    width: parent.width - 42; height: 0.5
                    color: Qt.rgba(pv.meta.r, pv.meta.g, pv.meta.b, 0.35)
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !pv.results && !pv.closed && !pv.sending
                    pressAndHoldInterval: 350
                    onPressAndHold: pv.held()
                    onClicked: {
                        if (!pv.many)
                            return pv.vote([opt.modelData])
                        const p = pv.picked.slice(), k = p.indexOf(opt.modelData)
                        if (k >= 0)
                            p.splice(k, 1)
                        else
                            p.push(opt.modelData)
                        pv.picked = p
                    }
                }
            }
        }
        Item {               // the foot: how many voted, «Ovoz berish» (several), or the results' voters
            width: col.width; height: 30
            Text {
                id: foot
                anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: -24
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool button: (pv.many && !pv.results && !pv.closed)
                                              || (pv.results && pv.poll && pv.poll.can_get_voters && !pv.poll.is_anonymous)
                text: pv.many && !pv.results && !pv.closed ? Tr.t("Ovoz berish")
                    : button ? Tr.t("Natijalarni ko'rish") : pv.poll ? pv.votes(pv.poll.total_voter_count) : ""
                color: button ? pv.tint : pv.meta
                opacity: pv.many && !pv.results && !pv.picked.length ? 0.5 : 1
                font.family: Theme.font; font.pixelSize: button ? 15 : 13; font.weight: button ? Font.DemiBold : Font.Normal
                MouseArea {
                    anchors.fill: parent; anchors.margins: -10
                    enabled: foot.button
                    onClicked: {
                        if (pv.many && !pv.results) {
                            if (pv.picked.length)
                                pv.vote(pv.picked.slice().sort((a, b) => a - b))
                        } else {
                            pv.voters()
                        }
                    }
                }
            }
        }
    }
    Text {                   // a quiz answered: 💡 shows why
        id: lamp
        visible: pv.quiz && pv.results && !!pv.poll.type.explanation && pv.poll.type.explanation.text !== ""
        anchors.right: parent.right
        y: 0
        text: "💡"
        font.pixelSize: 18
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: pv.explain(pv.poll.type.explanation.text) }
    }
}
