// A message's menu the way Telegram-iOS opens it (ContextControllerExtractedPresentationNode.swift,
// NOTES.md): the chat behind blurs, the bubble is lifted out of it and springs to where its
// actions fit under it, the actions grow from the bubble with a small overshoot. Everything
// that moves is an Animator (render thread); the blur is one picture taken as it opens. Over the
// bubble, the reactions it can get in a capsule (a tap puts one on). A bubble too tall for its actions
// under it (ContextControllerExtractedPresentationNode's scroller): its top under the reactions, the
// actions right under it, all of it scrolled to the actions at first; a drag shows the rest.
import QtQuick
import QtQuick.Effects

Item {
    id: menu
    anchors.fill: parent
    visible: false
    z: 10

    property Item behind                // what blurs (the chat without this menu)
    property real ceiling: 0            // the lifted bubble keeps below this (the header)
    property real floor: height         // and the actions above this
    property bool open: false
    property Item bubble: null
    property var actions: []            // [{ text, glyph, danger, gap, info, side, run }] (gap: set apart over it, as iOS's
                                        // «Select»; info: grey words, as iOS's «read at 14:32»; side: grey words on the right;
                                        // no run: nothing to tap)
    property var reactions: []          // emoji the message can get, over the bubble (iOS's row)
    property var chosen: []             // the ones already ours on it
    signal reacted(string emoji)
    property bool stripOurs: false      // the reactions' row lines up with the bubble's right edge (ours) or left
    property real stripEdge: 0

    // Telegram-iOS's spring for all of it (duration 0.42, damping 104, mass 5, stiffness 900:
    // ζ 0.78, its whole settling squeezed into 0.42 s → ω 19.6/s, peaks 2 % over at 0.25 s), as a
    // BezierSpline within 0.0015 of it. Measured on IMG_0300: the actions' width per frame fits it.
    readonly property var spring: [0.0333, 0.0, 0.0667, 0.1058, 0.1, 0.2201, 0.14, 0.3573, 0.18, 0.5086,
                                   0.22, 0.6252, 0.28, 0.8001, 0.34, 0.9024, 0.4, 0.9553, 0.4833, 1.0287,
                                   0.5667, 1.024, 0.65, 1.0199, 0.7667, 1.0141, 0.8833, 1.0032, 1, 1.0]
    readonly property real rowHeight: 46
    readonly property real boxWidth: 240
    readonly property real gapHeight: 8
    function boxHeight(acts) {
        return acts.length * rowHeight + acts.filter((a) => a.gap).length * gapHeight
    }
    readonly property real boxMost: 8 * rowHeight      // longer (a list of who saw it): it scrolls

    // other actions in the open menu (a row's words come, the list of who saw it): as tall as they are,
    // up to boxMost, and moved up if they would go under the floor
    function change(acts) {
        if (!open)
            return
        actions = acts
        list.contentY = 0
        const h = Math.min(boxMost, boxHeight(acts))
        box.y = Math.max(pane.contentY + ceiling + 8, Math.min(box.y, pane.contentY + floor - 16 - h))
    }
    property real homeX: 0              // where the bubble is in the chat
    property real homeY: 0

    // the finger that opened it, still down (iOS): what it is over lights up, lifted there it is done --
    // an action run, a reaction put on; lifted anywhere else the menu stays. x, y: in the menu
    property int hot: -1                // the action under the finger
    property string hotEmoji: ""        // the reaction under it
    function track(x, y) {
        hot = -1
        hotEmoji = ""
        if (!open)
            return
        for (let k = 0; k < rows.count; k++) {
            const r = rows.itemAt(k), at = r ? r.mapFromItem(menu, x, y) : null
            if (at && at.x >= 0 && at.x < r.width && at.y >= r.gap && at.y < r.height) {
                hot = k
                return
            }
        }
        if (!strip.visible)
            return
        const inStrip = strip.mapFromItem(menu, x, y)
        if (inStrip.x < 0 || inStrip.x >= strip.width || inStrip.y < 0 || inStrip.y >= strip.height)
            return
        for (let k = 0; k < cells.count; k++) {
            const c = cells.itemAt(k), at = c ? c.mapFromItem(menu, x, y) : null
            if (at && at.x >= 0 && at.x < c.width && at.y >= 0 && at.y < c.height) {
                hotEmoji = c.modelData
                return
            }
        }
    }
    function lift(x, y) {
        track(x, y)
        const k = hot, e = hotEmoji
        hot = -1
        hotEmoji = ""
        if (k >= 0 && k < actions.length && actions[k].run) {
            const run = actions[k].run
            close()
            run()
        } else if (e) {
            close()
            reacted(e)
        }
    }

    // the bubble and its actions: lift it out of `item`, put the menu up
    function show(item, ours, actions, reactions, chosen) {
        if (open)
            return
        bubble = item
        menu.actions = actions
        menu.reactions = reactions || []
        menu.chosen = chosen || []
        const at = item.mapToItem(menu, 0, 0)
        homeX = at.x; homeY = at.y
        const h = item.height
        const boxH = boxHeight(actions)
        const over = menu.reactions.length ? 56 : 0     // the reactions' row over the bubble
        // as low as it is, but with room for the actions under it and the reactions and the header over it
        const restY = Math.max(ceiling + 8 + over, Math.min(homeY, floor - 16 - boxH - 8 - h))
        // too tall for that: the pane longer than the screen, scrolled down to the actions (a bubble's
        // place there is where it is on the screen and that far down)
        const end = restY + h + 8 + boxH + 16
        pane.contentHeight = Math.max(height, end + height - floor)
        pane.contentY = pane.contentHeight - height
        const down = pane.contentY
        strip.y = restY - over
        stripOurs = ours
        stripEdge = ours ? Math.min(width - 12, homeX + item.width) : homeX
        strip.transformOrigin = ours ? Item.BottomRight : Item.BottomLeft
        lifted.x = homeX - 8
        lifted.y = homeY + down
        box.y = down ? restY + h + 8 : Math.min(restY + h + 8, floor - 16 - boxH)
        box.x = ours ? Math.min(width - 12, homeX + item.width) - boxWidth : Math.max(12, homeX)
        shot.scheduleUpdate()
        open = true
        visible = true
        shut.stop()
        liftY.to = restY
        opening.restart()
        for (let i = 0; i < cells.count; i++)
            cells.itemAt(i).popUp()
    }

    function close() {
        if (!open)
            return
        open = false
        hot = -1
        hotEmoji = ""
        opening.stop()
        dropY.to = homeY + pane.contentY     // (back where it was on the screen, however far the pane went)
        shut.restart()
    }

    function done() {
        visible = false
        bubble = null
        actions = []
        reactions = []
    }

    ShaderEffectSource {        // the chat as it was when the menu opened (the bubble left out)
        id: shot
        anchors.fill: parent
        sourceItem: menu.behind
        live: false
        visible: false
    }
    MultiEffect {
        id: blurred
        anchors.fill: parent
        source: shot
        blurEnabled: Prefs.fx               // (power saving: only darkened, as iOS without its translucency)
        blurMax: 40
        blur: 1.0
        brightness: Theme.dark ? -0.15 : -0.04
        saturation: 0.15
        opacity: 0
    }
    Rectangle {                 // (power saving, no blur: the chat dimmed instead, so the menu reads over it)
        anchors.fill: parent
        visible: !Prefs.fx
        opacity: blurred.opacity
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.6 : 0.4)
    }
    Flickable {                 // what is over the blur: scrolls only when it is longer than the screen
        id: pane
        anchors.fill: parent
        contentWidth: width
        interactive: contentHeight > height
        boundsBehavior: Flickable.DragOverBounds
        MouseArea {
            width: pane.width; height: pane.contentHeight
            onClicked: menu.close()
        }

        ShaderEffectSource {        // the bubble itself, lifted (8 pt either side for the tail)
            id: lifted
            width: (menu.bubble ? menu.bubble.width : 0) + 16
            height: menu.bubble ? menu.bubble.height : 0
            sourceItem: menu.bubble
            sourceRect: Qt.rect(-8, 0, width, height)
            hideSource: menu.visible
            live: true
        }

        Rectangle {
            id: box
            width: menu.boxWidth
            height: Math.min(menu.boxMost, menu.boxHeight(menu.actions))
            radius: 20
            color: Theme.menu
            opacity: 0
            scale: 0.01
            transformOrigin: Item.Top       // it grows out of the bubble's edge, from its middle
            clip: true
            Flickable {
                id: list
                anchors.fill: parent
                contentHeight: menu.boxHeight(menu.actions)
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
            Column {
                width: parent.width
                Repeater {
                    id: rows
                    model: menu.actions
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property real gap: modelData.gap ? menu.gapHeight : 0
                        width: box.width; height: menu.rowHeight + gap
                        color: modelData.run && (hit.pressed || menu.hot === index) ? Theme.highlight : "transparent"
                        Rectangle {     // the band setting it apart
                            visible: parent.gap > 0
                            width: parent.width; height: parent.gap
                            color: Theme.dark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.07)
                        }
                        Text {          // iOS 26: the icon first, then the words
                            width: 26; x: 14; y: parent.gap + (menu.rowHeight - height) / 2
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.glyph || ""
                            color: modelData.danger ? Theme.danger : modelData.info ? Theme.grey : Theme.text
                            font.family: Theme.font; font.pixelSize: modelData.info ? 14 : 17
                        }
                        Text {
                            id: words
                            x: 50; y: parent.gap + (menu.rowHeight - height) / 2
                            width: parent.width - x - 14 - (side.text ? side.implicitWidth + 8 : 0)
                            elide: Text.ElideRight
                            text: modelData.text
                            color: modelData.danger ? Theme.danger : modelData.info ? Theme.grey : Theme.text
                            font.family: Theme.font; font.pixelSize: modelData.info ? 14 : 16
                        }
                        Text {
                            id: side
                            anchors.right: parent.right; anchors.rightMargin: 14
                            y: parent.gap + (menu.rowHeight - height) / 2
                            text: modelData.side || ""
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 14
                        }
                        Rectangle {
                            visible: index > 0 && !parent.gap
                            width: parent.width; height: 0.5
                            color: Theme.separator
                        }
                        MouseArea {
                            id: hit
                            anchors.fill: parent; anchors.topMargin: parent.gap
                            enabled: !!modelData.run
                            onClicked: {
                                const run = modelData.run
                                if (modelData.stay) {       // (another list in the menu: it stays open)
                                    run()
                                    return
                                }
                                menu.close()
                                run()
                            }
                        }
                    }
                }
            }
            }
        }

        Rectangle {          // the reactions: a tap puts one on (or takes ours off) and closes
            id: strip
            visible: menu.reactions.length > 0
            width: Math.min(menu.width - 24, emojis.implicitWidth + 12); height: 48
            // (a binding: the row's width is known only after its emoji are laid out)
            x: menu.stripOurs ? Math.max(12, menu.stripEdge - width) : Math.max(12, Math.min(menu.stripEdge, menu.width - 12 - width))
            radius: 24
            color: Theme.menu
            opacity: 0
            scale: 0.01
            clip: true
            // drawn into a picture of its own at full size, which is then scaled: drawn straight at
            // 0.01 the emoji never showed (their glyphs are made at the size first drawn)
            layer.enabled: true
            layer.smooth: true
            Flickable {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                contentWidth: emojis.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: emojis
                    Repeater {
                        id: cells
                        model: menu.reactions
                        Item {
                            id: cell
                            required property string modelData
                            required property int index
                            width: 44; height: 48
                            // each pops in after the one on its left, as the capsule grows (Telegram-iOS's
                            // ReactionContextNode: ≈ 170 ms over the row, IMG_0300); those past the
                            // capsule's edge are there at once. Drawn into a picture of its own while it
                            // grows: a glyph is made at the size it is first drawn (as the capsule's layer)
                            Item {
                                id: pop
                                anchors.fill: parent
                                layer.enabled: scale < 1
                                layer.smooth: true
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 38; height: 38; radius: 19
                                    color: Theme.accent
                                    opacity: 0.18
                                    visible: menu.chosen.indexOf(cell.modelData) >= 0
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: cell.modelData
                                    font.pixelSize: 27
                                    scale: tapEmoji.pressed || menu.hotEmoji === cell.modelData ? 1.25 : 1
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                }
                            }
                            SequentialAnimation {
                                id: popIn
                                PauseAnimation { duration: 60 + cell.index * 25 }
                                ScaleAnimator { target: pop; from: 0.01; to: 1; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
                            }
                            function popUp() {
                                popIn.stop()
                                pop.scale = 1
                                if (cell.index * 44 < menu.width - 36) {
                                    pop.scale = 0.01
                                    popIn.start()
                                }
                            }
                            MouseArea {
                                id: tapEmoji
                                anchors.fill: parent
                                onClicked: {
                                    const e = cell.modelData
                                    menu.close()
                                    menu.reacted(e)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // in: the blur fades in, the bubble springs to its place, the actions grow from 0.01 (seen
    // in 0.05 s) and the reactions' capsule from the bubble's corner, all on the one spring
    ParallelAnimation {
        id: opening
        OpacityAnimator { target: blurred; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
        YAnimator { id: liftY; target: lifted; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
        ScaleAnimator { target: box; from: 0.01; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
        OpacityAnimator { target: box; from: 0; to: 1; duration: 50 }
        ScaleAnimator { target: strip; from: 0.01; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: menu.spring }
        OpacityAnimator { target: strip; from: 0; to: 1; duration: 100 }
    }
    // out: back where it was, quicker
    ParallelAnimation {
        id: shut
        OpacityAnimator { target: blurred; to: 0; duration: 220; easing.type: Easing.OutQuad }
        YAnimator { id: dropY; target: lifted; duration: 260; easing.type: Easing.OutCubic }
        ScaleAnimator { target: box; to: 0.6; duration: 180; easing.type: Easing.InQuad }
        OpacityAnimator { target: box; to: 0; duration: 150 }
        OpacityAnimator { target: strip; to: 0; duration: 150 }
        onFinished: menu.done()
    }
}
