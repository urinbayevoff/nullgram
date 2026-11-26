pragma ComponentBehavior: Bound
// Bottom sheet showing a single message's translation (Telegram-iOS TranslateAlert style):
// original text, translated text via TDLib translateMessageText, language chips (uz/en/ru/tr/ar/de/fr/zh),
// Copy button, clear Premium / server error handling, and safe.bottom clearance for ztMETRO's nav line.
import QtQuick

Item {
    id: sheet
    anchors.fill: parent
    visible: false
    z: 32

    property var store: null
    property bool open: false
    property var chatId: 0
    property var messageId: 0
    property string originalText: ""
    property string targetLang: "uz"
    property string translatedText: ""
    property bool sameLang: false
    property bool loading: false
    property string errorText: ""
    property int _reqId: 0

    signal copied(string text)
    signal closed()

    readonly property var languages: [
        { code: "uz", label: Tr.t("O'zbekcha") },
        { code: "en", label: Tr.t("Inglizcha") },
        { code: "ru", label: Tr.t("Ruscha") },
        { code: "tr", label: Tr.t("Turkcha") },
        { code: "ar", label: Tr.t("Arabcha") },
        { code: "de", label: Tr.t("Nemischa") },
        { code: "fr", label: Tr.t("Fransuzcha") },
        { code: "zh", label: Tr.t("Xitoycha") }
    ]

    function langLabel(code) {
        for (let i = 0; i < languages.length; i++)
            if (languages[i].code === code)
                return languages[i].label
        return code ? code.toUpperCase() : ""
    }

    function show(cid, mid, text, initialLang) {
        chatId = cid || 0
        messageId = mid || 0
        originalText = text || ""
        targetLang = initialLang || Tr.lang || "uz"
        translatedText = ""
        sameLang = false
        errorText = ""
        open = true
        visible = true
        bodyFlick.contentY = 0
        fall.stop()
        panelSlide.y = panel.height
        rise.restart()
        shade.restart()
        requestTranslation()
    }

    function close() {
        if (!open)
            return
        open = false
        _reqId += 1
        loading = false
        rise.stop()
        fallY.to = panel.height
        fall.restart()
        closed()
    }

    function selectLang(code) {
        if (!code || (code === targetLang && !errorText))
            return
        targetLang = code
        requestTranslation()
    }

    function requestTranslation() {
        if (!store || !chatId || !messageId)
            return
        _reqId += 1
        const req = _reqId
        loading = true
        errorText = ""
        sameLang = false
        translatedText = ""
        store.translateMessage(chatId, messageId, targetLang, (ok, text, _ft, err) => {
            if (!sheet || req !== sheet._reqId || !sheet.open)
                return
            sheet.loading = false
            if (!ok) {
                sheet.errorText = err || Tr.t("Tarjima qilib bo'lmadi")
                return
            }
            if (!text || !text.trim()) {
                sheet.sameLang = true
                sheet.translatedText = ""
                return
            }
            sheet.translatedText = text
        })
    }

    function copyTranslation() {
        const txt = translatedText || (sameLang ? originalText : "")
        if (!txt)
            return
        copied(txt)
        close()
    }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        opacity: 0
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    OpacityAnimator { id: shade; target: dim; from: 0; to: 0.4; duration: 240 }

    Rectangle {
        id: panel
        width: parent.width
        anchors.bottom: parent.bottom
        transform: Translate { id: panelSlide; y: 0 }
        readonly property real maxH: Math.max(320, sheet.height - 72)
        readonly property real naturalH: 108 + Math.min(bodyCol.implicitHeight, maxH - 190 - safe.bottom) + 86 + safe.bottom
        height: Math.min(maxH, Math.max(300 + safe.bottom, naturalH))
        radius: 16
        color: Theme.dark ? "#111113" : Theme.grouped
        MouseArea { anchors.fill: parent }

        // Flat bottom extension so the rounded sheet meets the bottom edge cleanly under safe.bottom
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 20
            color: panel.color
        }

        // Top drag handle
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 7; width: 36; height: 4; radius: 2
            color: Theme.separator
        }

        // Close button
        Icon {
            x: 16; y: 20
            width: 22; height: 22
            name: "cross"
            color: Theme.grey
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: sheet.close() }
        }

        // Title
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 19
            spacing: 7
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                name: "translate"
                color: Theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Tarjima")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
        }

        // Target language selector strip
        Flickable {
            id: langStrip
            x: 16; y: 54
            width: parent.width - 32
            height: 36
            contentWidth: langRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Row {
                id: langRow
                spacing: 8
                Repeater {
                    model: sheet.languages
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool chosen: sheet.targetLang === modelData.code
                        width: chipText.implicitWidth + 24
                        height: 32; radius: 16
                        color: chosen ? Theme.accent : (chipHit.pressed ? Theme.highlight : Theme.card)
                        border.width: chosen ? 0 : 0.5
                        border.color: Theme.separator
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            color: chip.chosen ? "white" : Theme.text
                            font.family: Theme.font; font.pixelSize: 14
                            font.weight: chip.chosen ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: chipHit
                            anchors.fill: parent
                            onClicked: sheet.selectLang(chip.modelData.code)
                        }
                    }
                }
            }
        }

        Rectangle {
            x: 16; y: 98
            width: parent.width - 32; height: 0.5
            color: Theme.separator
        }

        // Scrollable original + translated text cards
        Flickable {
            id: bodyFlick
            x: 16; y: 108
            width: parent.width - 32
            height: Math.max(80, copyBtn.y - y - 14)
            contentWidth: width
            contentHeight: bodyCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: bodyCol
                width: bodyFlick.width
                spacing: 12

                // Original message card
                Rectangle {
                    width: parent.width
                    height: origCol.implicitHeight + 22
                    radius: 12
                    color: Theme.card
                    Column {
                        id: origCol
                        x: 14; y: 11
                        width: parent.width - 28
                        spacing: 4
                        Text {
                            text: Tr.t("Asl matn")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: sheet.originalText
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 15
                        }
                    }
                }

                // Translation result card
                Rectangle {
                    width: parent.width
                    height: transCol.implicitHeight + 22
                    radius: 12
                    color: Theme.card
                    border.width: 1
                    border.color: sheet.errorText ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)
                                                  : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                    Column {
                        id: transCol
                        x: 14; y: 11
                        width: parent.width - 28
                        spacing: 6
                        Text {
                            text: Tr.f("Tarjima (%1)", sheet.langLabel(sheet.targetLang))
                            color: sheet.errorText ? Theme.danger : Theme.accent
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        }

                        Row {
                            visible: sheet.loading
                            spacing: 10
                            height: 26
                            Ring {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                value: 0.72
                                thickness: 2
                                cross: false
                                color: Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Tr.t("Tarjima qilinmoqda…")
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 15
                            }
                        }

                        Text {
                            visible: !sheet.loading && sheet.translatedText !== ""
                            width: parent.width
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: sheet.translatedText
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 16
                        }

                        Text {
                            visible: !sheet.loading && sheet.sameLang
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: Tr.t("Xabar allaqachon tanlangan tilda")
                            color: Theme.grey
                            font.family: Theme.font; font.pixelSize: 15
                        }

                        Text {
                            visible: !sheet.loading && sheet.errorText !== ""
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: sheet.errorText
                            color: Theme.danger
                            font.family: Theme.font; font.pixelSize: 15
                        }

                        Rectangle {
                            visible: !sheet.loading && sheet.errorText !== ""
                            width: retryText.implicitWidth + 28
                            height: 32; radius: 16
                            color: retryHit.pressed ? Theme.highlight : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            Text {
                                id: retryText
                                anchors.centerIn: parent
                                text: Tr.t("Qayta urinish")
                                color: Theme.accent
                                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: retryHit
                                anchors.fill: parent
                                onClicked: sheet.requestTranslation()
                            }
                        }
                    }
                }
            }
        }

        // Bottom Copy button (clear of ztMETRO's nav line)
        Rectangle {
            id: copyBtn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + safe.bottom
            width: parent.width - 32; height: 48; radius: 24
            readonly property bool ready: !sheet.loading && (sheet.translatedText !== "" || sheet.sameLang)
            color: Theme.accent
            opacity: !ready ? 0.4 : copyHit.pressed ? 0.8 : 1
            Text {
                anchors.centerIn: parent
                text: Tr.t("Nusxalash")
                color: "white"
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            MouseArea {
                id: copyHit
                anchors.fill: parent
                enabled: copyBtn.ready
                onClicked: sheet.copyTranslation()
            }
        }
    }

    NumberAnimation { id: rise; target: panelSlide; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
    ParallelAnimation {
        id: fall
        NumberAnimation { id: fallY; target: panelSlide; property: "y"; to: panel.height; duration: 220; easing.type: Easing.InCubic }
        OpacityAnimator { target: dim; to: 0; duration: 220 }
        onFinished: sheet.visible = false
    }
}
