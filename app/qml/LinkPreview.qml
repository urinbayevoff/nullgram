// Link preview card inside a text message bubble (TDLib 1.8.68 messageText.link_preview).
// Left accent bar, tinted background, site name, title, up to 3 lines of description, and either
// a small right-side square thumbnail or full-width media preserving aspect ratio (with a play
// badge for videos). Tapping opens the link; long-pressing forwards to the bubble's menu.
pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: box
    property var info: null
    property string picPath: ""
    property bool out: false
    property real room: 220

    signal opened(string url)
    signal instantView(string url)
    signal touched(bool down)
    signal held()

    readonly property color ink: out ? Theme.check : Theme.accent
    readonly property string url: info ? (info.url || "") : ""
    readonly property string site: info ? (info.site || "") : ""
    readonly property string title: info ? (info.title || "") : ""
    readonly property string desc: info ? (info.desc || "") : ""
    readonly property bool hasIv: !!(info && info.iv > 0)
    readonly property real ivBarH: hasIv ? 34 : 0
    readonly property bool hasMedia: !!(info && info.hasMedia)
    readonly property bool showLarge: hasMedia && !!(info && info.showLarge)
    readonly property bool mediaAbove: showLarge && !!(info && info.mediaAbove)
    readonly property bool isVideo: !!(info && info.isVideo)
    readonly property string mini: info ? (info.mini || "") : ""
    readonly property int picW: info && info.w > 0 ? info.w : 1
    readonly property int picH: info && info.h > 0 ? info.h : 1
    readonly property bool smallPic: hasMedia && !showLarge

    readonly property real padL: 11
    readonly property real padR: 8
    readonly property real smallSide: 48
    readonly property real textW: Math.max(
        siteTxt.visible ? siteTxt.implicitWidth : 0,
        titleTxt.visible ? titleTxt.implicitWidth : 0,
        descTxt.visible ? descTxt.implicitWidth : 0
    )
    readonly property real wants: showLarge ? Math.max(180, room)
        : Math.min(room, Math.max(smallPic ? 156 : 80, textW + padL + padR + (smallPic ? smallSide + 8 : 0)))

    readonly property real curTextW: Math.max(40, width - padL - padR - (smallPic ? smallSide + 8 : 0))
    readonly property real largeW: Math.max(80, width - padL - padR)
    readonly property real largeH: showLarge ? Math.max(92, Math.min(200, Math.round(largeW * picH / Math.max(1, picW)))) : 0

    readonly property real afterSite: siteTxt.visible ? siteTxt.y + siteTxt.height : 6
    readonly property real mediaTopY: mediaAbove ? afterSite + (siteTxt.visible ? 5 : 0) : 6
    readonly property real titleY: mediaAbove ? mediaTopY + largeH + 5 : afterSite + (siteTxt.visible ? 2 : 0)
    readonly property real descY: titleTxt.visible ? titleY + titleTxt.height + 2
                                : mediaAbove ? mediaTopY + largeH + 5
                                : afterSite + (siteTxt.visible ? 2 : 0)
    readonly property real textBottom: descTxt.visible ? descY + descTxt.height
                                     : titleTxt.visible ? titleY + titleTxt.height
                                     : siteTxt.visible ? siteTxt.y + siteTxt.height : 6
    readonly property real picY: mediaAbove ? mediaTopY
                               : showLarge ? textBottom + (textBottom > 6 ? 6 : 0)
                               : 6
    readonly property real contentBottom: mediaAbove ? Math.max(textBottom, mediaTopY + largeH)
                                        : showLarge ? picY + largeH
                                        : smallPic ? Math.max(textBottom, 6 + smallSide)
                                        : textBottom

    radius: 6
    clip: true
    color: Qt.rgba(ink.r, ink.g, ink.b, out ? (Theme.outLight ? 0.10 : 0.16) : (Theme.dark ? 0.14 : 0.09))
    implicitHeight: Math.max(36, contentBottom + 6) + ivBarH
    height: implicitHeight

    Rectangle {
        width: 3
        height: parent.height
        color: box.ink
    }

    Text {
        id: siteTxt
        visible: box.site !== ""
        x: box.padL
        y: 6
        width: box.curTextW
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        text: box.site
        color: box.ink
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Text {
        id: titleTxt
        visible: box.title !== ""
        x: box.padL
        y: box.titleY
        width: box.curTextW
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 2
        textFormat: Text.PlainText
        text: box.title
        color: box.out ? Theme.outText : Theme.inText
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Text {
        id: descTxt
        visible: box.desc !== ""
        x: box.padL
        y: box.descY
        width: box.curTextW
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 3
        textFormat: Text.PlainText
        text: box.desc
        color: box.out ? Theme.outText : Theme.inText
        opacity: 0.88
        font.family: Theme.font
        font.pixelSize: 13
    }

    Image {
        id: picImg
        visible: box.hasMedia
        x: box.showLarge ? box.padL : box.width - box.padR - box.smallSide
        y: box.picY
        width: box.showLarge ? box.largeW : box.smallSide
        height: box.showLarge ? box.largeH : box.smallSide
        asynchronous: true
        smooth: true
        sourceSize: Qt.size(Math.max(16, Math.round(width)), Math.max(16, Math.round(height)))
        source: !box.hasMedia ? ""
              : box.picPath !== "" ? "image://pic/6/" + Math.round(width) + "/" + box.picPath
              : box.mini !== "" ? "image://pic/6/" + Math.round(width) + "/mini/" + box.mini
              : ""
    }

    Loader {
        id: playBadge
        active: box.hasMedia && box.isVideo
        visible: active
        x: picImg.x + (picImg.width - width) / 2
        y: picImg.y + (picImg.height - height) / 2
        width: box.showLarge ? 42 : 24
        height: width
        sourceComponent: Rectangle {
            radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.54)
            Icon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: box.showLarge ? 1.5 : 1
                width: box.showLarge ? 18 : 11
                height: width
                name: "play"
                color: "white"
            }
        }
    }

    MouseArea {
        id: hit
        anchors.fill: parent
        anchors.bottomMargin: box.ivBarH
        pressAndHoldInterval: 350
        property bool wasHeld: false
        onPressed: {
            wasHeld = false
            box.touched(true)
        }
        onReleased: box.touched(false)
        onCanceled: box.touched(false)
        onPressAndHold: {
            wasHeld = true
            box.held()
        }
        onClicked: {
            if (!wasHeld && box.url !== "")
                box.opened(box.url)
        }
    }

    Loader {
        id: ivBtn
        active: box.hasIv
        visible: active
        z: 2
        x: 3
        y: box.height - box.ivBarH
        width: box.width - 3
        height: box.ivBarH
        sourceComponent: Item {
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(box.ink.r, box.ink.g, box.ink.b, ivHit.pressed ? 0.18 : 0.0)
            }
            Rectangle {
                x: 8; y: 0
                width: parent.width - 16; height: 0.5
                color: Qt.rgba(box.ink.r, box.ink.g, box.ink.b, 0.28)
            }
            Text {
                anchors.centerIn: parent
                text: "⚡ " + Tr.t("Tezkor ko'rish")
                color: box.ink
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            MouseArea {
                id: ivHit
                anchors.fill: parent
                onClicked: if (box.url !== "") box.instantView(box.url)
            }
        }
    }
}
