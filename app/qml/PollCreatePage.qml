// Create Poll / Quiz page (Telegram-iOS CreatePollController):
// question, 2..maxOptions answers (add, remove, drag to reorder), Anonymous (locked on in channels),
// Multiple Answers, Quiz Mode (correct answer + optional explanation), and optional Close Time
// (open_period / close_date). Sends via TDLib 1.8.68 inputMessagePoll.
pragma ComponentBehavior: Bound
import QtQuick

SubPage {
    id: page
    required property var chatId
    property bool isChannel: false
    property int maxOptions: 10
    property int maxOpenPeriod: 600
    property bool anonymous: true
    property bool multiple: false
    property bool quiz: false
    property int correctIndex: -1
    property int openPeriod: 0          // seconds (<= maxOpenPeriod)
    property int closeAfter: 0          // seconds for close_date (> maxOpenPeriod, e.g. 1h / 24h)
    property bool closeSheetOpen: false
    property int _optRev: 0             // bumped whenever an option changes, to refresh computed bindings

    signal submitted(string question, var options, var opts)

    title: Tr.t("Yangi so'rovnoma")
    action: Tr.t("Yuborish")
    actionBold: true
    actionOn: canSend

    // Keep scrolled content clear of both OSK and ztMETRO nav line
    Component.onCompleted: {
        maxOptions = store.pollOptionLimit || 10
        maxOpenPeriod = store.pollOpenPeriodMax || 600
        store.loadPollLimits((lim, maxP) => {
            if (!page)
                return
            if (lim >= 2)
                page.maxOptions = lim
            if (maxP >= 30)
                page.maxOpenPeriod = maxP
        })
        optModel.append({ optId: 1, text: "" })
        optModel.append({ optId: 2, text: "" })
        _optRev++
    }

    property int _nextOptId: 3
    ListModel { id: optModel }

    // Trimmed option texts
    readonly property var optionTexts: {
        const rev = _optRev
        void rev
        const out = []
        for (let i = 0; i < optModel.count; i++)
            out.push((optModel.get(i).text || "").trim())
        return out
    }
    readonly property bool hasEmptyOption: {
        const list = optionTexts
        if (list.length < 2)
            return true
        for (let i = 0; i < list.length; i++)
            if (!list[i].length)
                return true
        return false
    }
    readonly property bool hasDuplicateOption: {
        const list = optionTexts
        const seen = {}
        for (let i = 0; i < list.length; i++) {
            const t = list[i].toLowerCase()
            if (!t)
                continue
            if (seen[t])
                return true
            seen[t] = true
        }
        return false
    }
    readonly property bool quizNeedsAnswer: quiz && (correctIndex < 0 || correctIndex >= optionTexts.length || !optionTexts[correctIndex])
    readonly property bool canSend: questionEdit.text.trim().length > 0
                                    && optionTexts.length >= 2
                                    && optionTexts.length <= maxOptions
                                    && !hasEmptyOption
                                    && !hasDuplicateOption
                                    && !quizNeedsAnswer

    readonly property int remainingOptions: Math.max(0, maxOptions - optModel.count)
    readonly property string optionsNote: {
        if (hasDuplicateOption)
            return Tr.t("Takroriy variantlar bo'lmasligi kerak.")
        if (quizNeedsAnswer && !hasEmptyOption)
            return Tr.t("To'g'ri javobni belgilang.")
        if (remainingOptions <= 0)
            return Tr.t("Eng ko'p variant soniga yetildi.")
        return Tr.f("Yana %1 ta variant qo'shishingiz mumkin.", remainingOptions)
    }

    readonly property var closePresets: [
        { key: "none", label: Tr.t("Yo'q"), secs: 0 },
        { key: "30s", label: Tr.t("30 soniya"), secs: 30 },
        { key: "1m", label: Tr.t("1 daqiqa"), secs: 60 },
        { key: "5m", label: Tr.t("5 daqiqa"), secs: 300 },
        { key: "10m", label: Tr.t("10 daqiqa"), secs: 600 },
        { key: "1h", label: Tr.t("1 soat"), secs: 3600 },
        { key: "24h", label: Tr.t("24 soat"), secs: 86400 }
    ]
    readonly property string closeLabel: {
        const s = openPeriod > 0 ? openPeriod : closeAfter
        for (let i = 0; i < closePresets.length; i++)
            if (closePresets[i].secs === s)
                return closePresets[i].label
        return Tr.t("Yo'q")
    }

    function setCloseSeconds(secs) {
        if (secs <= 0) {
            openPeriod = 0
            closeAfter = 0
        } else if (secs <= maxOpenPeriod) {
            openPeriod = secs
            closeAfter = 0
        } else {
            openPeriod = 0
            closeAfter = secs
        }
        closeSheetOpen = false
    }

    function keyboardDown() {
        questionEdit.focus = false
        explainEdit.focus = false
        if (osk.h > 0)
            osk.hide()
    }

    function dismiss() {
        if (closeSheetOpen) {
            closeSheetOpen = false
            return true
        }
        if (osk.h > 0) {
            keyboardDown()
            return true
        }
        return false
    }

    function addOption(initialText) {
        if (optModel.count >= maxOptions)
            return false
        optModel.append({ optId: _nextOptId++, text: initialText || "" })
        _optRev++
        return true
    }

    function removeOption(idx) {
        if (optModel.count <= 2 || idx < 0 || idx >= optModel.count)
            return false
        optModel.remove(idx)
        if (correctIndex === idx)
            correctIndex = -1
        else if (correctIndex > idx)
            correctIndex--
        _optRev++
        return true
    }

    function moveOption(fromIdx, toIdx) {
        if (fromIdx === toIdx || fromIdx < 0 || toIdx < 0 || fromIdx >= optModel.count || toIdx >= optModel.count)
            return false
        optModel.move(fromIdx, toIdx, 1)
        if (correctIndex === fromIdx) {
            correctIndex = toIdx
        } else if (fromIdx < toIdx && correctIndex > fromIdx && correctIndex <= toIdx) {
            correctIndex--
        } else if (fromIdx > toIdx && correctIndex >= toIdx && correctIndex < fromIdx) {
            correctIndex++
        }
        _optRev++
        return true
    }

    function setOptionText(idx, value) {
        if (idx < 0 || idx >= optModel.count)
            return
        if (optModel.get(idx).text !== value) {
            optModel.setProperty(idx, "text", value)
            _optRev++
        }
    }

    function setQuestionText(value) { questionEdit.text = value || "" }
    function setExplanationText(value) { explainEdit.text = value || "" }

    function setQuizMode(on) {
        quiz = !!on
        if (quiz) {
            multiple = false
            if (correctIndex >= optModel.count)
                correctIndex = -1
        }
    }

    function submit() {
        if (!canSend)
            return false
        keyboardDown()
        const q = questionEdit.text.trim()
        const optsList = optionTexts.slice()
        const closeDate = closeAfter > 0 ? Math.floor(Date.now() / 1000) + closeAfter : 0
        const payload = {
            anonymous: isChannel ? true : anonymous,
            multiple: !quiz && multiple,
            quiz: quiz,
            correctOptionId: quiz ? correctIndex : -1,
            explanation: quiz ? explainEdit.text.trim() : "",
            openPeriod: openPeriod,
            closeDate: closeDate
        }
        submitted(q, optsList, payload)
        return true
    }

    onActed: submit()

    // Ensure bottom clearance above keyboard too
    Binding {
        target: page.flick
        property: "bottomMargin"
        value: Math.max(osk.h, safe.bottom)
    }

    // ---- 1. Question ----
    SettingsGroup {
        title: Tr.t("Savol")
        Item {
            width: parent.width
            height: Math.max(52, questionEdit.implicitHeight + 24)
            TextEdit {
                id: questionEdit
                x: 16; y: 12
                width: parent.width - 32 - (qCount.visible ? qCount.implicitWidth + 8 : 0)
                wrapMode: TextEdit.Wrap
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                onTextChanged: {
                    if (text.length > 255)
                        text = text.slice(0, 255)
                }
                Text {
                    visible: !questionEdit.text
                    text: Tr.t("Savol bering")
                    color: Theme.grey
                    font: questionEdit.font
                }
            }
            Text {
                id: qCount
                visible: questionEdit.text.length >= 220
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                text: String(255 - questionEdit.text.length)
                color: questionEdit.text.length >= 250 ? Theme.danger : Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    // ---- 2. Answer Options ----
    SettingsGroup {
        title: Tr.t("Javob variantlari")
        note: page.optionsNote

        Repeater {
            id: optRepeater
            model: optModel
            delegate: Item {
                id: optRow
                required property int index
                required property int optId
                required property string text
                width: parent ? parent.width : 300
                height: Math.max(48, optEdit.implicitHeight + 22)
                z: dragHandle.dragActive ? 5 : 1

                readonly property bool isCorrect: page.quiz && page.correctIndex === index

                Rectangle {
                    anchors.fill: parent
                    color: dragHandle.dragActive ? Theme.highlight : "transparent"
                }

                // Quiz correct-answer selector circle
                Item {
                    id: quizPick
                    visible: page.quiz
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 22; radius: 11
                        color: optRow.isCorrect ? "#34c759" : "transparent"
                        border.color: optRow.isCorrect ? "#34c759" : Theme.separator
                        border.width: 1.5
                        Icon {
                            visible: optRow.isCorrect
                            anchors.centerIn: parent
                            width: 14; height: 14
                            name: "check"
                            color: "white"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6
                        onClicked: page.correctIndex = optRow.index
                    }
                }

                TextEdit {
                    id: optEdit
                    x: page.quiz ? 48 : 16
                    y: 12
                    width: parent.width - x - (delBtn.visible ? 76 : 44)
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    selectionColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                    text: optRow.text
                    onTextChanged: {
                        if (text.length > 100) {
                            text = text.slice(0, 100)
                            return
                        }
                        if (text !== optRow.text)
                            page.setOptionText(optRow.index, text)
                    }
                    Text {
                        visible: !optEdit.text
                        text: Tr.f("Variant %1", optRow.index + 1)
                        color: Theme.grey
                        font: optEdit.font
                    }
                }

                // Delete button (only when > 2 options)
                Item {
                    id: delBtn
                    visible: optModel.count > 2
                    anchors.right: dragHandle.left; anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32
                    opacity: delHit.pressed ? 0.4 : 0.75
                    Icon {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        name: "cross"
                        color: Theme.grey
                    }
                    MouseArea {
                        id: delHit
                        anchors.fill: parent
                        onClicked: page.removeOption(optRow.index)
                    }
                }

                // Drag handle to reorder options
                Item {
                    id: dragHandle
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 36
                    property bool dragActive: false
                    property real startY: 0
                    Icon {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        name: "drag"
                        color: dragHandle.dragActive ? Theme.accent : Theme.grey
                    }
                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        onPressed: (mouse) => {
                            dragHandle.dragActive = true
                            dragHandle.startY = mouse.y
                            page.flick.interactive = false
                        }
                        onPositionChanged: (mouse) => {
                            if (!dragHandle.dragActive)
                                return
                            const dy = mouse.y - dragHandle.startY
                            if (dy > 32 && optRow.index < optModel.count - 1) {
                                page.moveOption(optRow.index, optRow.index + 1)
                                dragHandle.startY = mouse.y
                            } else if (dy < -32 && optRow.index > 0) {
                                page.moveOption(optRow.index, optRow.index - 1)
                                dragHandle.startY = mouse.y
                            }
                        }
                        onReleased: {
                            dragHandle.dragActive = false
                            page.flick.interactive = true
                        }
                        onCanceled: {
                            dragHandle.dragActive = false
                            page.flick.interactive = true
                        }
                    }
                }

                Rectangle {
                    visible: optRow.index < optModel.count - 1 || addOptRow.visible
                    x: page.quiz ? 48 : 16
                    anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
            }
        }

        // "+ Variant qo'shish"
        Item {
            id: addOptRow
            visible: optModel.count < page.maxOptions
            width: parent.width
            height: visible ? 46 : 0
            Rectangle {
                anchors.fill: parent
                color: Theme.highlight
                visible: addOptHit.pressed
            }
            Icon {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                name: "plus"
                color: Theme.accent
            }
            Text {
                x: 48; anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Variant qo'shish")
                color: Theme.accent
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
            }
            MouseArea {
                id: addOptHit
                anchors.fill: parent
                onClicked: page.addOption("")
            }
        }
    }

    // ---- 3. Settings ----
    SettingsGroup {
        title: Tr.t("Sozlamalar")
        SettingsRow {
            text: Tr.t("Anonim ovoz berish")
            sub: page.isChannel ? Tr.t("Kanallarda so'rovnomalar doimo anonim bo'ladi") : ""
            toggle: true
            chevron: false
            on: page.isChannel ? true : page.anonymous
            dim: page.isChannel
            onClicked: {
                if (!page.isChannel)
                    page.anonymous = !page.anonymous
            }
        }
        SettingsRow {
            text: Tr.t("Bir nechta javob")
            sub: page.quiz ? Tr.t("Viktorinada faqat bitta to'g'ri javob bo'ladi") : ""
            toggle: true
            chevron: false
            on: !page.quiz && page.multiple
            dim: page.quiz
            onClicked: {
                if (!page.quiz)
                    page.multiple = !page.multiple
            }
        }
        SettingsRow {
            text: Tr.t("Viktorina rejimi")
            sub: Tr.t("Faqat bitta to'g'ri javob tanlanadi, ovozni o'zgartirib bo'lmaydi")
            toggle: true
            chevron: false
            on: page.quiz
            onClicked: page.setQuizMode(!page.quiz)
        }
        SettingsRow {
            text: Tr.t("Yopilish vaqti")
            value: page.closeLabel
            chevron: true
            last: true
            onClicked: {
                page.keyboardDown()
                page.closeSheetOpen = true
            }
        }
    }

    // ---- 4. Quiz Explanation ----
    SettingsGroup {
        visible: page.quiz
        title: Tr.t("Izoh")
        note: Tr.t("Foydalanuvchilar noto'g'ri javob berganda yoki lampochkani bosganda ko'rinadi.")
        Item {
            width: parent.width
            height: Math.max(52, explainEdit.implicitHeight + 24)
            TextEdit {
                id: explainEdit
                x: 16; y: 12
                width: parent.width - 32 - (eCount.visible ? eCount.implicitWidth + 8 : 0)
                wrapMode: TextEdit.Wrap
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 16
                onTextChanged: {
                    if (text.length > 200)
                        text = text.slice(0, 200)
                }
                Text {
                    visible: !explainEdit.text
                    text: Tr.t("Izoh qo'shish (ixtiyoriy)")
                    color: Theme.grey
                    font: explainEdit.font
                }
            }
            Text {
                id: eCount
                visible: explainEdit.text.length >= 170
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                text: String(200 - explainEdit.text.length)
                color: explainEdit.text.length >= 195 ? Theme.danger : Theme.grey
                font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    // ---- Close Time Action Sheet (over the page, above safe.bottom) ----
    Item {
        id: closeSheet
        parent: page
        anchors.fill: parent
        z: 30
        visible: closeDim.opacity > 0
        Rectangle {
            id: closeDim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4)
            opacity: page.closeSheetOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; onClicked: page.closeSheetOpen = false }
        }
        Column {
            x: 8; width: parent.width - 16
            y: page.closeSheetOpen ? parent.height - height - 8 - safe.bottom : parent.height + 8
            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            spacing: 8
            Rectangle {
                width: parent.width
                height: closeCol.height
                radius: 14
                color: Theme.menu
                clip: true
                Column {
                    id: closeCol
                    width: parent.width
                    Item {
                        width: parent.width; height: 40
                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Yopilish vaqti")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.separator }
                    }
                    Repeater {
                        model: page.closePresets
                        Rectangle {
                            id: presetRow
                            required property int index
                            required property var modelData
                            readonly property bool chosen: (page.openPeriod > 0 ? page.openPeriod : page.closeAfter) === modelData.secs
                            width: closeCol.width; height: 48
                            color: pHit.pressed ? Theme.highlight : "transparent"
                            Text {
                                x: 18; anchors.verticalCenter: parent.verticalCenter
                                text: presetRow.modelData.label
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 17
                            }
                            Icon {
                                visible: presetRow.chosen
                                anchors.right: parent.right; anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                name: "check"
                                color: Theme.accent
                            }
                            Rectangle {
                                visible: presetRow.index < page.closePresets.length - 1
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 0.5
                                color: Theme.separator
                            }
                            MouseArea {
                                id: pHit
                                anchors.fill: parent
                                onClicked: page.setCloseSeconds(presetRow.modelData.secs)
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 52; radius: 14
                color: cancelCloseHit.pressed ? Theme.highlight : Theme.menu
                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Bekor qilish")
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                MouseArea { id: cancelCloseHit; anchors.fill: parent; onClicked: page.closeSheetOpen = false }
            }
        }
    }
}
