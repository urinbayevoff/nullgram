// Compose-field autocomplete panel (0.9.6/4): @ group member mentions, # per-chat recent hashtags,
// and : emoji keyword suggestions. Loaded lazily by ChatPage when the field contains @, #, or :.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window

Item {
    id: ac
    required property var store
    required property var editor
    required property var chatId
    required property bool isGroup
    property var thread: 0
    property var directTopic: 0
    property int forumTopic: 0
    required property real bottomInset
    property bool activeInput: true
    property bool inlineMode: false

    signal mentionNamePicked(int offset, int length, var userId)

    property string mode: ""            // "", "@", "#", ":"
    property string query: ""
    property int tokenStart: -1
    property bool dismissed: false
    property string dismissedKey: ""
    property bool _updating: false
    property int reqSeq: 0

    property var members: []
    property var hashtags: []
    property var emojis: []

    readonly property int itemCount: mode === "@" ? members.length
                                   : mode === "#" ? hashtags.length
                                   : mode === ":" ? emojis.length : 0
    readonly property bool open: activeInput && mode !== "" && !dismissed && itemCount > 0
    readonly property real maxPanelH: Math.max(54, height - bottomInset - 72)
    readonly property real panelH: mode === ":" ? 54
                                 : mode === "@" ? Math.min(Math.min(members.length, 5) * 48, maxPanelH)
                                 : mode === "#" ? Math.min(Math.min(hashtags.length, 5) * 44, maxPanelH) : 0

    function close() {
        dismissed = true
        dismissedKey = mode && tokenStart >= 0 ? (mode + ":" + tokenStart) : ""
        debounce.stop()
        reqSeq++
    }

    function _clear(resetDismiss) {
        debounce.stop()
        reqSeq++
        mode = ""
        query = ""
        tokenStart = -1
        members = []
        hashtags = []
        emojis = []
        if (resetDismiss) {
            dismissed = false
            dismissedKey = ""
        }
    }

    function evaluate() {
        if (_updating || !editor || !activeInput)
            return
        if (inlineMode) {
            _clear(true)
            return
        }
        const txt = editor.text || ""
        const pos = Math.max(0, Math.min(txt.length, editor.cursorPosition))
        const before = txt.slice(0, pos)

        let nextMode = ""
        let nextQuery = ""
        let nextStart = -1

        let m = isGroup ? before.match(/(?:^|[\s(\["'«])@([^\s@#:]*)$/) : null
        if (m) {
            nextMode = "@"
            nextQuery = m[1]
            nextStart = before.length - 1 - nextQuery.length
        } else {
            m = before.match(/(?:^|[\s(\["'«])#([^\s@#:]*)$/)
            if (m) {
                nextMode = "#"
                nextQuery = m[1]
                nextStart = before.length - 1 - nextQuery.length
            } else {
                m = before.match(/(?:^|[\s(\["'«]):([^\s@#:]{2,})$/)
                if (m) {
                    nextMode = ":"
                    nextQuery = m[1]
                    nextStart = before.length - 1 - nextQuery.length
                }
            }
        }

        if (!nextMode) {
            _clear(true)
            return
        }

        const key = nextMode + ":" + nextStart
        if (dismissed && dismissedKey === key)
            return
        if (dismissedKey !== key) {
            dismissed = false
            dismissedKey = ""
        }

        const sameQuery = (mode === nextMode && query === nextQuery && tokenStart === nextStart)
        if (mode !== nextMode) {
            members = []
            hashtags = []
            emojis = []
        }
        mode = nextMode
        query = nextQuery
        tokenStart = nextStart

        if (nextMode === "#") {
            debounce.stop()
            reqSeq++
            hashtags = store.filterHashtags(chatId, nextQuery)
            return
        }

        if (sameQuery && (debounce.running || itemCount > 0))
            return

        debounce.restart()
    }

    function _runSearch() {
        if (dismissed || !mode || mode === "#")
            return
        const seq = ++reqSeq
        const wantMode = mode
        const wantStart = tokenStart
        const q = query
        if (wantMode === "@") {
            if (!isGroup || !chatId)
                return
            store.searchChatMembers(chatId, q, store.topic(thread, directTopic, forumTopic), 20, (list) => {
                if (!ac || seq !== ac.reqSeq || ac.mode !== wantMode || ac.tokenStart !== wantStart || ac.dismissed)
                    return
                ac.members = list || []
            })
        } else if (wantMode === ":") {
            store.searchEmojis(q, (list) => {
                if (!ac || seq !== ac.reqSeq || ac.mode !== wantMode || ac.tokenStart !== wantStart || ac.dismissed)
                    return
                ac.emojis = list || []
            })
        }
    }

    function _replaceToken(inserted, addSpace) {
        if (!editor || tokenStart < 0)
            return -1
        const txt = editor.text || ""
        const start = Math.max(0, Math.min(txt.length, tokenStart))
        const end = Math.max(start, Math.min(txt.length, editor.cursorPosition))
        const before = txt.slice(0, start)
        const after = txt.slice(end)
        const sp = addSpace && (after.length === 0 || !/^\s/.test(after)) ? " " : ""
        editor.text = before + inserted + sp + after
        editor.cursorPosition = before.length + inserted.length + sp.length
        return before.length
    }

    function pickMember(u) {
        if (!u)
            return
        _updating = true
        const uname = u.usernames && u.usernames.active_usernames && u.usernames.active_usernames.length
                    ? u.usernames.active_usernames[0] : ""
        if (uname) {
            _replaceToken("@" + uname, true)
        } else {
            const disp = (u.first_name || "").trim() || (u.last_name || "").trim() || Tr.t("Foydalanuvchi")
            const at = _replaceToken(disp, true)
            if (at >= 0)
                mentionNamePicked(at, disp.length, u.id)
        }
        _clear(true)
        _updating = false
        editor.forceActiveFocus()
    }

    function pickHashtag(tag) {
        if (!tag)
            return
        _updating = true
        _replaceToken("#" + tag, true)
        _clear(true)
        _updating = false
        editor.forceActiveFocus()
    }

    function pickEmoji(emoji) {
        if (!emoji)
            return
        _updating = true
        _replaceToken(emoji, false)
        _clear(true)
        _updating = false
        editor.forceActiveFocus()
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: ac._runSearch()
    }

    Connections {
        target: ac.editor
        function onTextChanged() { ac.evaluate() }
        function onCursorPositionChanged() { ac.evaluate() }
    }

    onChatIdChanged: evaluate()
    onIsGroupChanged: evaluate()
    onActiveInputChanged: if (!activeInput) _clear(true); else evaluate()
    onInlineModeChanged: if (inlineMode) _clear(true); else evaluate()
    Component.onCompleted: evaluate()

    // Tap anywhere above the compose bar to dismiss the panel without blocking field/send taps below
    MouseArea {
        visible: ac.open
        x: 0; y: 0
        width: parent.width
        height: Math.max(0, parent.height - ac.bottomInset)
        onPressed: ac.close()
    }

    Rectangle {
        id: card
        visible: ac.open
        x: 8
        width: parent.width - 16
        height: ac.panelH
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ac.bottomInset + 6
        radius: 16
        color: Theme.glass
        border.width: 0.5
        border.color: Theme.separator
        clip: true

        // Absorb taps inside the panel background so they do not fall through to the dismiss area
        MouseArea { anchors.fill: parent }

        // @ mentions list
        ListView {
            id: memberList
            anchors.fill: parent
            visible: ac.mode === "@"
            model: ac.members
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: mRow
                required property var modelData
                required property int index
                readonly property string fullName: ((modelData.first_name || "") + " " + (modelData.last_name || "")).trim()
                                                   || Tr.t("Foydalanuvchi")
                readonly property string uname: modelData.usernames && modelData.usernames.active_usernames
                                                && modelData.usernames.active_usernames.length
                                                ? modelData.usernames.active_usernames[0] : ""
                property string pic: ""

                function loadPic() {
                    pic = ""
                    const u = modelData
                    if (!u || !u.profile_photo || !u.profile_photo.small)
                        return
                    if (u.profile_photo.small.local && u.profile_photo.small.local.is_downloading_completed)
                        pic = u.profile_photo.small.local.path
                    else
                        ac.store.userPhoto(u, (p) => { if (mRow && mRow.modelData === u) mRow.pic = p })
                }

                onModelDataChanged: loadPic()
                Component.onCompleted: loadPic()

                width: memberList.width
                height: 48
                color: mHit.pressed ? Theme.highlight : "transparent"

                Rectangle {
                    visible: mRow.index > 0
                    x: 56; width: parent.width - 56; height: 0.5
                    color: Theme.separator
                }
                Avatar {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34
                    source: mRow.pic
                    letters: ac.store.letters(mRow.fullName)
                    tint: ac.store.tints[Math.abs(mRow.modelData.id || 0) % ac.store.tints.length]
                }
                Column {
                    x: 56
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 68
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: mRow.fullName
                        textFormat: Text.PlainText
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        visible: mRow.uname !== ""
                        width: parent.width
                        elide: Text.ElideRight
                        text: mRow.uname ? "@" + mRow.uname : ""
                        textFormat: Text.PlainText
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: mHit
                    anchors.fill: parent
                    onClicked: ac.pickMember(mRow.modelData)
                }
            }
        }

        // # hashtags list
        ListView {
            id: tagList
            anchors.fill: parent
            visible: ac.mode === "#"
            model: ac.hashtags
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: tRow
                required property string modelData
                required property int index
                width: tagList.width
                height: 44
                color: tHit.pressed ? Theme.highlight : "transparent"

                Rectangle {
                    visible: tRow.index > 0
                    x: 46; width: parent.width - 46; height: 0.5
                    color: Theme.separator
                }
                Rectangle {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; radius: 13
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                    Text {
                        anchors.centerIn: parent
                        text: "#"
                        color: Theme.accent
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                }
                Text {
                    x: 46; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 58
                    elide: Text.ElideRight
                    text: "#" + tRow.modelData
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15
                }
                MouseArea {
                    id: tHit
                    anchors.fill: parent
                    onClicked: ac.pickHashtag(tRow.modelData)
                }
            }
        }

        // : emoji horizontal strip
        ListView {
            id: emojiList
            anchors.fill: parent
            visible: ac.mode === ":"
            orientation: ListView.Horizontal
            model: ac.emojis
            spacing: 4
            leftMargin: 6
            rightMargin: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: eItem
                required property string modelData
                required property int index
                readonly property string emoSrc: Emo.fileUrl(modelData)
                width: 44
                height: emojiList.height
                Rectangle {
                    anchors.centerIn: parent
                    width: 40; height: 40; radius: 10
                    color: eHit.pressed ? Theme.highlight : "transparent"
                }
                Image {
                    id: emoImg
                    visible: eItem.emoSrc !== ""
                    anchors.centerIn: parent
                    width: 28; height: 28
                    sourceSize: Qt.size(Math.ceil(28 * Screen.devicePixelRatio), Math.ceil(28 * Screen.devicePixelRatio))
                    asynchronous: true
                    source: eItem.emoSrc
                }
                Text {
                    visible: !emoImg.visible
                    anchors.centerIn: parent
                    text: eItem.modelData
                    font.pixelSize: 26
                }
                MouseArea {
                    id: eHit
                    anchors.fill: parent
                    onClicked: ac.pickEmoji(eItem.modelData)
                }
            }
        }
    }
}
