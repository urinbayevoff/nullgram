pragma ComponentBehavior: Bound
// Instant View article reader (TDLib 1.8.68 getWebPageInstantView -> webPageInstantView):
// renders pageBlockTitle, Subtitle, AuthorDate, Header/Subheader/SectionHeading/Kicker,
// Paragraph, Footer, List, BlockQuote/PullQuote, Photo (lazy-loaded only when instantiated
// in the viewport), Preformatted, Divider, Cover, Details, and plain-text fallback for any
// other block. External links always require Alert confirmation before Qt.openUrlExternally.
import QtQuick

Page {
    id: page
    property string url: ""
    property string siteTitle: ""

    property bool loading: true
    property string errorText: ""
    property bool isRtl: false
    property int viewCount: 0
    property var blocks: []
    property var photoPaths: ({})       // fileId -> local path
    property int photoTick: 0
    property string lastOpenedUrl: ""

    function dismiss() {
        if (alert.open) {
            alert.open = false
            return true
        }
        return false
    }

    function askOpenUrl(target) {
        const u = String(target || "").trim()
        if (!u)
            return
        alert.show(Tr.t("Havolani ochish"), Tr.f("Havolani ochish: %1?", u), [
            { t: Tr.t("Bekor qilish") },
            { t: Tr.t("Ochish"), bold: true, run: () => {
                page.lastOpenedUrl = u
                Qt.openUrlExternally(u)
            } }
        ])
    }

    function requestPhoto(file) {
        if (!file || !file.id || !store)
            return
        const fid = file.id
        if (photoPaths[fid] !== undefined)
            return
        if (file.local && file.local.is_downloading_completed && file.local.path) {
            const m = Object.assign({}, photoPaths)
            m[fid] = file.local.path
            photoPaths = m
            photoTick++
            return
        }
        const m0 = Object.assign({}, photoPaths)
        m0[fid] = ""
        photoPaths = m0
        store.fetch(file, 4, (path) => {
            if (!page)
                return
            const m1 = Object.assign({}, page.photoPaths)
            m1[fid] = path || ""
            page.photoPaths = m1
            page.photoTick++
        })
    }

    function photoPathOf(file, _tick) {
        if (!file || !file.id)
            return ""
        if (photoPaths[file.id])
            return photoPaths[file.id]
        if (file.local && file.local.is_downloading_completed && file.local.path)
            return file.local.path
        return ""
    }

    function formatDate(ts) {
        if (!ts || ts <= 0)
            return ""
        return Qt.formatDate(new Date(ts * 1000), "dd.MM.yyyy")
    }

    Component.onCompleted: {
        if (!store || !url) {
            loading = false
            errorText = Tr.t("Tezkor ko'rish yuklanmadi")
            return
        }
        store.getWebPageInstantView(url, (iv, err) => {
            if (!page)
                return
            page.loading = false
            if (!iv) {
                page.errorText = err || Tr.t("Tezkor ko'rish yuklanmadi")
                return
            }
            page.isRtl = !!(iv.is_rtl || (iv.page && iv.page.is_rtl))
            page.viewCount = iv.view_count || 0
            const parsed = store.instantViewBlocks(iv)
            if (!parsed.length) {
                page.errorText = Tr.t("Tezkor ko'rish yuklanmadi")
                return
            }
            page.blocks = parsed
        })
    }

    ListView {
        id: lv
        anchors.fill: parent
        topMargin: bar.height + 10
        bottomMargin: 28 + safe.bottom
        spacing: 10
        cacheBuffer: 180
        boundsBehavior: Flickable.DragOverBounds
        visible: !page.loading && page.errorText === "" && page.blocks.length > 0
        model: page.blocks

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind || "paragraph"
            readonly property int align: page.isRtl ? Text.AlignRight : Text.AlignLeft
            width: lv.width
            implicitHeight: blockLoad.item ? blockLoad.item.implicitHeight : 0
            height: implicitHeight

            Loader {
                id: blockLoad
                x: 16
                width: row.width - 32
                readonly property var blk: row.modelData
                readonly property int align: row.align
                sourceComponent: row.kind === "title" ? titleComp
                               : row.kind === "subtitle" ? subtitleComp
                               : row.kind === "kicker" ? kickerComp
                               : row.kind === "author" ? authorComp
                               : row.kind === "heading" ? headingComp
                               : row.kind === "listItem" ? listItemComp
                               : row.kind === "quote" ? quoteComp
                               : row.kind === "photo" ? photoComp
                               : row.kind === "pre" ? preComp
                               : row.kind === "divider" ? dividerComp
                               : row.kind === "footer" ? footerComp
                               : paraComp
            }
        }

        footer: Item {
            width: lv.width
            height: 76
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                spacing: 10
                Text {
                    visible: page.viewCount > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.store ? Tr.n("%1 marta ko'rildi", page.viewCount, page.store.count(page.viewCount)) : ""
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 13
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: openFootTxt.implicitWidth + 28; height: 34; radius: 17
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, openFootHit.pressed ? 0.24 : 0.13)
                    Text {
                        id: openFootTxt
                        anchors.centerIn: parent
                        text: Tr.t("Brauzerda ochish")
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    MouseArea {
                        id: openFootHit
                        anchors.fill: parent
                        onClicked: page.askOpenUrl(page.url)
                    }
                }
            }
        }
    }

    // ---- block delegates ----
    Component {
        id: titleComp
        Text {
            readonly property var b: parent.blk
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.StyledText
            text: b.html || ""
            color: Theme.text
            linkColor: Theme.accent
            font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold
            lineHeight: 1.22
            onLinkActivated: (u) => page.askOpenUrl(u)
        }
    }

    Component {
        id: subtitleComp
        Text {
            readonly property var b: parent.blk
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.StyledText
            text: b.html || ""
            color: Theme.grey
            linkColor: Theme.accent
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Medium
            lineHeight: 1.3
            onLinkActivated: (u) => page.askOpenUrl(u)
        }
    }

    Component {
        id: kickerComp
        Text {
            readonly property var b: parent.blk
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.PlainText
            text: (b.plain || "").toUpperCase()
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }

    Component {
        id: authorComp
        Text {
            readonly property var b: parent.blk
            readonly property string dateStr: page.formatDate(b.date)
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.PlainText
            text: b.author && dateStr ? (b.author + " · " + dateStr) : (b.author || dateStr)
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 13
        }
    }

    Component {
        id: headingComp
        Text {
            readonly property var b: parent.blk
            readonly property int lvl: b.level || 1
            width: parent.width
            topPadding: lvl === 1 ? 8 : 4
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.StyledText
            text: b.html || ""
            color: Theme.text
            linkColor: Theme.accent
            font.family: Theme.font
            font.pixelSize: lvl === 1 ? 20 : lvl === 2 ? 18 : 16
            font.weight: Font.DemiBold
            lineHeight: 1.28
            onLinkActivated: (u) => page.askOpenUrl(u)
        }
    }

    Component {
        id: paraComp
        Text {
            readonly property var b: parent.blk
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.StyledText
            text: b.html || ""
            color: Theme.text
            linkColor: Theme.accent
            font.family: Theme.font; font.pixelSize: Prefs.chatSize
            lineHeight: 1.42
            onLinkActivated: (u) => page.askOpenUrl(u)
        }
    }

    Component {
        id: footerComp
        Text {
            readonly property var b: parent.blk
            width: parent.width
            wrapMode: Text.Wrap
            horizontalAlignment: parent.align
            textFormat: Text.StyledText
            text: b.html || ""
            color: Theme.grey
            linkColor: Theme.accent
            font.family: Theme.font; font.pixelSize: 13
            lineHeight: 1.35
            onLinkActivated: (u) => page.askOpenUrl(u)
        }
    }

    Component {
        id: listItemComp
        Item {
            readonly property var b: parent.blk
            readonly property int al: parent.align
            width: parent.width
            implicitHeight: liTxt.implicitHeight
            Text {
                id: liLabel
                x: 4; y: 0
                width: 24
                textFormat: Text.PlainText
                text: b.label || "•"
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: Prefs.chatSize; font.weight: Font.DemiBold
            }
            Text {
                id: liTxt
                x: 28; y: 0
                width: parent.width - 28
                wrapMode: Text.Wrap
                horizontalAlignment: al
                textFormat: Text.StyledText
                text: b.html || ""
                color: Theme.text
                linkColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Prefs.chatSize
                lineHeight: 1.38
                onLinkActivated: (u) => page.askOpenUrl(u)
            }
        }
    }

    Component {
        id: quoteComp
        Rectangle {
            readonly property var b: parent.blk
            readonly property int al: parent.align
            width: parent.width
            implicitHeight: qCol.implicitHeight + 18
            height: implicitHeight
            radius: 8
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.14 : 0.08)
            clip: true
            Rectangle {
                width: 3; height: parent.height
                color: Theme.accent
            }
            Column {
                id: qCol
                x: 13; y: 9
                width: parent.width - 22
                spacing: 5
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: al
                    textFormat: Text.StyledText
                    text: b.html || ""
                    color: Theme.text
                    linkColor: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: b.pull ? Prefs.chatSize + 1 : Prefs.chatSize - 1
                    font.italic: true
                    lineHeight: 1.36
                    onLinkActivated: (u) => page.askOpenUrl(u)
                }
                Text {
                    visible: !!b.credit
                    width: parent.width
                    wrapMode: Text.Wrap
                    horizontalAlignment: al
                    textFormat: Text.StyledText
                    text: b.credit || ""
                    color: Theme.grey
                    linkColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 13
                    onLinkActivated: (u) => page.askOpenUrl(u)
                }
            }
        }
    }

    Component {
        id: preComp
        Rectangle {
            readonly property var b: parent.blk
            width: parent.width
            implicitHeight: preCol.implicitHeight + 18
            height: implicitHeight
            radius: 8
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
            border.width: 0.5
            border.color: Theme.separator
            Column {
                id: preCol
                x: 12; y: 9
                width: parent.width - 24
                spacing: 4
                Text {
                    visible: !!b.lang
                    text: b.lang || ""
                    color: Theme.accent
                    font.family: "monospace"; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                    text: b.plain || ""
                    color: Theme.text
                    font.family: "monospace"; font.pixelSize: Math.max(12, Prefs.chatSize - 2)
                    lineHeight: 1.32
                }
            }
        }
    }

    Component {
        id: dividerComp
        Item {
            width: parent.width
            implicitHeight: 16
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.45, 140)
                height: 1
                color: Theme.separator
            }
        }
    }

    Component {
        id: photoComp
        Column {
            id: pCol
            readonly property var b: parent.blk
            readonly property real aspect: (b.w > 0 && b.h > 0) ? (b.h / b.w) : 0.62
            readonly property real picH: Math.max(100, Math.min(340, Math.round(width * aspect)))
            readonly property string picPath: page.photoPathOf(b.file, page.photoTick)
            width: parent.width
            spacing: 6
            // Lazy image loading: request file ONLY once this ListView delegate is instantiated on screen
            Component.onCompleted: {
                if (b.file)
                    page.requestPhoto(b.file)
            }
            Rectangle {
                width: pCol.width
                height: pCol.picH
                radius: 10
                clip: true
                color: Theme.dark ? "#1e1e22" : "#e8e8ed"
                Image {
                    anchors.fill: parent
                    asynchronous: true
                    smooth: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(Math.max(32, Math.round(width)), Math.max(32, Math.round(height)))
                    source: pCol.picPath !== "" ? "image://pic/10/" + Math.round(width) + "/" + pCol.picPath
                          : pCol.b.mini ? "image://pic/10/" + Math.round(width) + "/mini/" + pCol.b.mini
                          : ""
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !!pCol.b.url
                    onClicked: page.askOpenUrl(pCol.b.url)
                }
            }
            Text {
                visible: !!pCol.b.captionHtml
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: pCol.b.captionHtml || ""
                color: Theme.grey
                linkColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 13
                onLinkActivated: (u) => page.askOpenUrl(u)
            }
            Text {
                visible: !!pCol.b.creditHtml
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: pCol.b.creditHtml || ""
                color: Theme.grey
                opacity: 0.8
                linkColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 12
                onLinkActivated: (u) => page.askOpenUrl(u)
            }
        }
    }

    // ---- loading & error states ----
    Column {
        visible: page.loading
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Yuklanmoqda…")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    Column {
        visible: !page.loading && page.errorText !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 300)
        spacing: 12
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: page.errorText
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: errBtnTxt.implicitWidth + 32; height: 40; radius: 20
            color: Theme.accent
            opacity: errBtnHit.pressed ? 0.72 : 1
            Text {
                id: errBtnTxt
                anchors.centerIn: parent
                text: Tr.t("Brauzerda ochish")
                color: "white"
                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
            }
            MouseArea {
                id: errBtnHit
                anchors.fill: parent
                onClicked: page.askOpenUrl(page.url)
            }
        }
    }

    // ---- floating glass header (matches ChatPage / SubPage) ----
    Item {
        id: bar
        z: 5
        width: parent.width
        height: 60
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.94) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.0) }
            }
        }
        Glass {
            x: 10; y: 8
            width: 44; height: 44
            opacity: backHit.pressed ? 0.6 : 1
            Icon {
                anchors.centerIn: parent
                width: 22; height: 22
                name: "back"
                color: Theme.text
            }
            MouseArea {
                id: backHit
                anchors.fill: parent; anchors.margins: -6
                onClicked: if (page.nav) page.nav.pop()
            }
        }
        Glass {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: Math.min(parent.width - 132, Math.max(120, hdrTitle.implicitWidth + 32))
            height: 44
            Text {
                id: hdrTitle
                anchors.centerIn: parent
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: page.siteTitle || Tr.t("Tezkor ko'rish")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
        }
        Glass {
            anchors.right: parent.right; anchors.rightMargin: 10
            y: 8
            width: 44; height: 44
            opacity: extHit.pressed ? 0.6 : 1
            Icon {
                anchors.centerIn: parent
                width: 21; height: 21
                name: "globe"
                color: Theme.text
            }
            MouseArea {
                id: extHit
                anchors.fill: parent; anchors.margins: -6
                onClicked: page.askOpenUrl(page.url)
            }
        }
    }

    Alert {
        id: alert
        z: 30
        anchors.fill: parent
    }
}
