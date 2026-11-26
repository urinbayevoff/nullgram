// Inline bot query results panel (0.9.8): triggered when compose field starts with "@botname ".
// Loaded lazily by ChatPage in the same slot as Autocomplete (above compose bar, respecting barLift).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Item {
    id: panel
    required property var store
    required property var editor
    required property var chatId
    required property real bottomInset
    property bool activeInput: true

    signal resultPicked(string queryId, string resultId)
    signal startBotRequested(var botUserId, string startParameter)
    signal webAppRequested(string url)

    property string botUsername: ""
    property var botUserId: 0
    property bool botIsInline: false
    property string botPlaceholder: ""
    property string query: ""
    property bool dismissed: false
    property bool loading: false
    property bool loadingMore: false
    property bool queried: false
    property string nextOffset: ""
    property var buttonInfo: null       // { text, kind: "start_bot" | "web_app", startParam, url }
    property var items: []
    property var _seenIds: ({})
    property var thumbPaths: ({})       // file_id -> local path
    property int thumbRev: 0
    property var animPaths: ({})        // file_id -> local path
    property int animRev: 0
    property int _resolveSeq: 0
    property int _querySeq: 0
    property bool isGrid: false
    property bool isStickerGrid: false
    property bool animReady: false

    readonly property bool isInlineBot: botIsInline && botUserId > 0
    readonly property string placeholder: activeInput && isInlineBot && query === "" ? botPlaceholder : ""
    readonly property bool open: activeInput && isInlineBot && !dismissed
                                 && (loading || items.length > 0 || buttonInfo !== null || queried)

    readonly property int gridCols: isStickerGrid ? 4 : 3
    readonly property real cardW: Math.max(120, width - 16)
    readonly property real cellW: Math.floor((cardW - 8) / gridCols)
    readonly property real cellH: isStickerGrid ? cellW : Math.round(cellW * 0.86)
    readonly property real maxPanelH: Math.max(110, Math.min(290, height - bottomInset - 72))
    readonly property real btnH: buttonInfo !== null ? 42 : 0
    readonly property real bodyH: items.length === 0 ? 48
                                : isGrid ? Math.max(cellH + 8, Math.ceil(items.length / gridCols) * cellH + 8 + (loadingMore ? 28 : 0))
                                : items.length * 64 + (loadingMore ? 28 : 0)
    readonly property real panelH: Math.min(maxPanelH, btnH + bodyH)

    function close() {
        dismissed = true
        debounce.stop()
        _querySeq++
    }

    function resetAll() {
        debounce.stop()
        _resolveSeq++
        _querySeq++
        botUsername = ""
        botUserId = 0
        botIsInline = false
        botPlaceholder = ""
        query = ""
        dismissed = false
        loading = false
        loadingMore = false
        queried = false
        nextOffset = ""
        buttonInfo = null
        items = []
        _seenIds = {}
        isGrid = false
        isStickerGrid = false
    }

    function evaluate() {
        if (!editor || !activeInput) {
            if (!activeInput)
                resetAll()
            return
        }
        const txt = editor.text || ""
        const m = txt.match(/^@([a-zA-Z][a-zA-Z0-9_]{2,31})\s([\s\S]*)$/)
        if (!m) {
            if (botUsername !== "" || items.length > 0 || loading)
                resetAll()
            return
        }
        const uname = m[1].toLowerCase()
        const q = m[2]
        dismissed = false

        if (uname !== botUsername) {
            debounce.stop()
            _querySeq++
            const rseq = ++_resolveSeq
            botUsername = uname
            botUserId = 0
            botIsInline = false
            botPlaceholder = ""
            query = q
            loading = false
            loadingMore = false
            queried = false
            nextOffset = ""
            buttonInfo = null
            items = []
            _seenIds = {}
            isGrid = false
            isStickerGrid = false

            store.resolveInlineBot(uname, (info) => {
                if (!panel || rseq !== panel._resolveSeq || panel.botUsername !== uname)
                    return
                if (!info || !info.isInline || !info.userId) {
                    panel.botIsInline = false
                    panel.botUserId = 0
                    panel.botPlaceholder = ""
                    return
                }
                panel.botIsInline = true
                panel.botUserId = info.userId
                panel.botPlaceholder = info.placeholder || ""
                debounce.restart()
            })
            return
        }

        if (q === query && (debounce.running || loading || queried))
            return
        query = q
        nextOffset = ""
        loadingMore = false
        _querySeq++
        if (botIsInline && botUserId > 0)
            debounce.restart()
    }

    function _fetchThumb(f) {
        if (!f || !f.id)
            return
        if (f.local && f.local.is_downloading_completed && f.local.path) {
            if (thumbPaths[f.id] !== f.local.path) {
                thumbPaths[f.id] = f.local.path
                thumbRev++
            }
            return
        }
        if (thumbPaths[f.id] !== undefined)
            return
        thumbPaths[f.id] = ""
        const fid = f.id
        store.fetch(f, 4, (path) => {
            if (!panel || !path)
                return
            panel.thumbPaths[fid] = path
            panel.thumbRev++
        })
    }

    function fetchAnim(f) {
        if (!f || !f.id)
            return
        if (f.local && f.local.is_downloading_completed && f.local.path) {
            if (animPaths[f.id] !== f.local.path) {
                animPaths[f.id] = f.local.path
                animRev++
            }
            return
        }
        if (animPaths[f.id] !== undefined)
            return
        animPaths[f.id] = ""
        const fid = f.id
        store.fetch(f, 3, (path) => {
            if (!panel || !path)
                return
            panel.animPaths[fid] = path
            panel.animRev++
        })
    }

    function _runQuery(offset) {
        if (!activeInput || !botIsInline || !botUserId || !chatId || dismissed)
            return
        const isMore = !!offset
        const seq = isMore ? _querySeq : ++_querySeq
        const wantBot = botUserId
        const wantQuery = query
        if (isMore)
            loadingMore = true
        else
            loading = true

        store.queryInlineBot(wantBot, chatId, wantQuery, offset || "", (res, err) => {
            if (!panel || seq !== panel._querySeq || panel.botUserId !== wantBot || panel.query !== wantQuery)
                return
            panel.loading = false
            panel.loadingMore = false
            panel.queried = true
            if (!res) {
                if (!isMore) {
                    panel.items = []
                    panel._seenIds = {}
                    panel.buttonInfo = null
                    panel.nextOffset = ""
                    panel.isGrid = false
                    panel.isStickerGrid = false
                }
                return
            }
            if (!isMore) {
                panel._seenIds = {}
                if (res.button && res.button.type) {
                    const bt = res.button.type["@type"] || ""
                    if (bt === "inlineQueryResultsButtonTypeStartBot") {
                        panel.buttonInfo = {
                            text: res.button.text || Tr.t("Botni ishga tushirish"),
                            kind: "start_bot",
                            startParam: res.button.type.start_parameter || "",
                            url: ""
                        }
                    } else if (bt === "inlineQueryResultsButtonTypeWebApp") {
                        panel.buttonInfo = {
                            text: res.button.text || Tr.t("Ochish"),
                            kind: "web_app",
                            startParam: "",
                            url: res.button.type.url || ""
                        }
                    } else {
                        panel.buttonInfo = null
                    }
                } else {
                    panel.buttonInfo = null
                }
            }
            const qid = String(res.inline_query_id || "0")
            const raw = res.results || []
            const added = []
            for (const r of raw) {
                const info = panel.store.inlineResultInfo(r, qid)
                if (!info || !info.id || panel._seenIds[info.id])
                    continue
                panel._seenIds[info.id] = true
                added.push(info)
                if (info.thumbFile)
                    panel._fetchThumb(info.thumbFile)
            }
            const nextList = isMore ? panel.items.concat(added) : added
            panel.items = nextList
            panel.nextOffset = String(res.next_offset || "")
            panel.isGrid = nextList.length > 0 && nextList.every((x) => x.grid)
            panel.isStickerGrid = panel.isGrid && nextList.every((x) => x.kind === "sticker")
            if (panel.isGrid)
                animDelay.restart()
        })
    }

    function loadMore() {
        if (!nextOffset || loading || loadingMore || !open)
            return
        _runQuery(nextOffset)
    }

    function pickItem(it) {
        if (!it || !it.id)
            return
        const qid = it.queryId
        const rid = it.id
        resetAll()
        resultPicked(qid, rid)
    }

    function tapButton() {
        if (!buttonInfo)
            return
        if (buttonInfo.kind === "start_bot") {
            const uid = botUserId
            const param = buttonInfo.startParam || ""
            close()
            startBotRequested(uid, param)
        } else if (buttonInfo.kind === "web_app") {
            webAppRequested(buttonInfo.url || "")
        }
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: panel._runQuery("")
    }

    Timer {
        id: animDelay
        interval: 200
        onTriggered: panel.animReady = true
    }

    onOpenChanged: if (!open) { animDelay.stop(); animReady = false }

    Connections {
        target: panel.editor
        function onTextChanged() { panel.evaluate() }
    }

    onChatIdChanged: resetAll()
    onActiveInputChanged: if (!activeInput) resetAll(); else evaluate()
    Component.onCompleted: evaluate()

    // Tap anywhere above the compose bar to dismiss the inline panel
    MouseArea {
        visible: panel.open
        x: 0; y: 0
        width: parent.width
        height: Math.max(0, parent.height - panel.bottomInset)
        onPressed: panel.close()
    }

    Rectangle {
        id: card
        visible: panel.open
        x: 8
        width: panel.cardW
        height: panel.panelH
        anchors.bottom: parent.bottom
        anchors.bottomMargin: panel.bottomInset + 6
        radius: 16
        color: Theme.glass
        border.width: 0.5
        border.color: Theme.separator
        clip: true

        // Absorb taps inside card so they do not dismiss
        MouseArea { anchors.fill: parent }

        // Optional top button (inlineQueryResultsButton: start bot / web app)
        Rectangle {
            id: topBtn
            visible: panel.buttonInfo !== null
            width: parent.width
            height: visible ? 42 : 0
            color: topBtnHit.pressed ? Theme.highlight : "transparent"

            Text {
                anchors.centerIn: parent
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: panel.buttonInfo ? panel.buttonInfo.text : ""
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 0.5
                color: Theme.separator
            }
            MouseArea {
                id: topBtnHit
                anchors.fill: parent
                onClicked: panel.tapButton()
            }
        }

        // Loading / empty placeholder when no results yet
        Item {
            visible: panel.items.length === 0
            y: topBtn.height
            width: parent.width
            height: Math.max(0, parent.height - topBtn.height)

            Row {
                anchors.centerIn: parent
                spacing: 8
                Ring {
                    visible: panel.loading
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    value: 0.72
                    cross: false
                    color: Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: panel.loading ? Tr.t("Yuklanmoqda…") : Tr.t("Hech narsa topilmadi")
                    color: Theme.grey
                    font.family: Theme.font
                    font.pixelSize: 14
                }
            }
        }

        // Media grid (photos, GIFs/animations, stickers, videos)
        GridView {
            id: gridView
            visible: panel.items.length > 0 && panel.isGrid
            x: 4
            y: topBtn.height + 4
            width: parent.width - 8
            height: Math.max(0, parent.height - topBtn.height - 8)
            cellWidth: panel.cellW
            cellHeight: panel.cellH
            model: panel.isGrid ? panel.items : []
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: panel.cellH
            onContentYChanged: {
                if (visible && contentHeight > 0 && contentY + height >= contentHeight - 100)
                    panel.loadMore()
            }
            footer: Item {
                width: gridView.width
                height: panel.loadingMore ? 28 : 0
                Ring {
                    visible: panel.loadingMore
                    anchors.centerIn: parent
                    width: 16; height: 16
                    value: 0.72
                    cross: false
                    color: Theme.accent
                }
            }
            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                width: gridView.cellWidth
                height: gridView.cellHeight

                readonly property bool isAnim: modelData.kind === "animation"
                readonly property bool isSticker: modelData.kind === "sticker"
                readonly property string thumbPath: {
                    void panel.thumbRev
                    const f = modelData.thumbFile
                    return f && f.id ? (panel.thumbPaths[f.id] || "") : ""
                }
                readonly property string animPath: {
                    void panel.animRev
                    const f = modelData.animFile
                    return f && f.id ? (panel.animPaths[f.id] || "") : ""
                }
                readonly property bool inView: y + height > gridView.contentY && y < gridView.contentY + gridView.height
                readonly property bool playAnim: isAnim && animPath !== "" && Prefs.autoGif && panel.animReady && panel.open && gridView.visible && !gridView.moving && inView

                Component.onCompleted: {
                    if (isAnim && modelData.animFile && Prefs.autoGif)
                        panel.fetchAnim(modelData.animFile)
                }

                Rectangle {
                    id: frame
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 8
                    color: tile.isSticker ? "transparent" : (Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                    clip: true

                    Image {
                        visible: !tile.isSticker && tile.thumbPath === "" && tile.modelData.mini !== ""
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: tile.modelData.mini !== "" ? ("image://pic/8/" + Math.round(width) + "/mini/" + tile.modelData.mini) : ""
                        sourceSize: Qt.size(Math.max(16, Math.round(width)), Math.max(16, Math.round(height)))
                    }

                    Image {
                        visible: tile.thumbPath !== "" && !tile.modelData.isTgs
                        anchors.fill: parent
                        anchors.margins: tile.isSticker ? 4 : 0
                        fillMode: tile.isSticker ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                        asynchronous: true
                        source: tile.thumbPath !== "" ? ("file://" + tile.thumbPath) : ""
                        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                    }

                    Loader {
                        visible: item !== null && item.showing
                        active: tile.playAnim
                        asynchronous: true
                        anchors.fill: parent
                        sourceComponent: InlineVideo {
                            path: tile.animPath
                            radius: 8
                            sound: false
                            loop: true
                            running: tile.playAnim
                        }
                    }

                    // Video duration / GIF pill badge
                    Rectangle {
                        visible: tile.modelData.badge !== ""
                        anchors.left: parent.left; anchors.leftMargin: 5
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                        width: badgeText.implicitWidth + 10
                        height: 18
                        radius: 9
                        color: Qt.rgba(0, 0, 0, 0.56)
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: tile.modelData.badge
                            textFormat: Text.PlainText
                            color: "white"
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: tileHit.pressed ? Qt.rgba(0, 0, 0, 0.22) : "transparent"
                    }
                }

                MouseArea {
                    id: tileHit
                    anchors.fill: parent
                    onClicked: panel.pickItem(tile.modelData)
                }
            }
        }

        // Article / audio / document / location / venue / contact / voice list
        ListView {
            id: listView
            visible: panel.items.length > 0 && !panel.isGrid
            y: topBtn.height
            width: parent.width
            height: Math.max(0, parent.height - topBtn.height)
            model: !panel.isGrid ? panel.items : []
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: {
                if (visible && contentHeight > 0 && contentY + height >= contentHeight - 100)
                    panel.loadMore()
            }
            footer: Item {
                width: listView.width
                height: panel.loadingMore ? 28 : 0
                Ring {
                    visible: panel.loadingMore
                    anchors.centerIn: parent
                    width: 16; height: 16
                    value: 0.72
                    cross: false
                    color: Theme.accent
                }
            }
            delegate: Rectangle {
                id: rowItem
                required property var modelData
                required property int index
                width: listView.width
                height: 64
                color: rowHit.pressed ? Theme.highlight : "transparent"

                readonly property string thumbPath: {
                    void panel.thumbRev
                    const f = modelData.thumbFile
                    return f && f.id ? (panel.thumbPaths[f.id] || "") : ""
                }
                readonly property string glyph: modelData.badge !== "" ? modelData.badge
                                              : (modelData.title ? modelData.title.slice(0, 1).toUpperCase() : "?")

                Rectangle {
                    visible: rowItem.index > 0
                    x: 68; width: parent.width - 68; height: 0.5
                    color: Theme.separator
                }

                Rectangle {
                    id: thumbBox
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46; height: 46
                    radius: rowItem.modelData.kind === "contact" || rowItem.modelData.kind === "audio" ? 23 : 10
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    clip: true

                    Image {
                        visible: rowItem.thumbPath !== ""
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: rowItem.thumbPath !== "" ? ("file://" + rowItem.thumbPath) : ""
                        sourceSize: Qt.size(Math.ceil(46 * Screen.devicePixelRatio), Math.ceil(46 * Screen.devicePixelRatio))
                    }

                    Text {
                        visible: rowItem.thumbPath === ""
                        anchors.centerIn: parent
                        text: rowItem.glyph
                        textFormat: Text.PlainText
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    x: 68
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 80
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: rowItem.modelData.title || ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: (rowItem.modelData.desc || "") !== ""
                        width: parent.width
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        text: rowItem.modelData.desc || ""
                        color: Theme.grey
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }

                MouseArea {
                    id: rowHit
                    anchors.fill: parent
                    onClicked: panel.pickItem(rowItem.modelData)
                }
            }
        }
    }
}
