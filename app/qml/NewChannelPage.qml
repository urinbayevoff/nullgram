// New Channel (Telegram-iOS's CreateChannelController): photo (AttachSheet), channel name,
// optional description → createNewSupergroupChat (is_channel: true) → ChannelTypePage.qml.
// When ChannelTypePage closes, opens the newly created channel chat and trims creation pages.
// Double-tap protected: Create locks with a spinner until TDLib answers.
pragma ComponentBehavior: Bound
import QtQuick

SubPage {
    id: page
    property string photo: ""
    property bool creating: false
    property string errorText: ""
    property var createdId: 0
    property bool openedChat: false
    property var sheet: null

    title: Tr.t("Yangi kanal")
    action: creating ? "" : Tr.t("Keyingi")
    actionBold: true
    actionOn: name.text.trim() !== "" && !creating
    onActed: createNow()

    function keyboardDown() {
        name.focus = false
        about.focus = false
        if (osk.h > 0)
            osk.hide()
    }

    function dismiss() {
        if (sheet && sheet.open) {
            sheet.close()
            return true
        }
        if (alert.open) {
            alert.open = false
            return true
        }
        return false
    }

    function openPicker() {
        keyboardDown()
        if (!sheet)
            sheet = sheetMaker.createObject(page)
        sheet.show()
    }

    function pickPhoto() {
        if (creating)
            return
        if (!photo)
            return openPicker()
        alert.title = Tr.t("Kanal rasmi")
        alert.text = ""
        alert.answers = [
            { t: Tr.t("Rasm tanlash"), run: () => page.openPicker() },
            { t: Tr.t("Rasmni o'chirish"), red: true, run: () => page.photo = "" },
            { t: Tr.t("Bekor qilish") }
        ]
        alert.open = true
    }

    function createNow() {
        const t = name.text.trim()
        if (creating || !t)
            return
        creating = true
        errorText = ""
        keyboardDown()
        store.createChannel(t, about.text.trim(), photo, (chatId, err) => {
            if (!page)
                return
            page.creating = false
            if (!chatId) {
                page.errorText = err || Tr.t("Bo'lmadi")
                page.nav.say(Tr.f("Bo'lmadi: %1", page.errorText))
                return
            }
            page.createdId = chatId
            const c = Qt.createComponent("ChannelTypePage.qml")
            if (c.status === Component.Error) {
                console.warn("nullgram:", c.errorString())
                page.openedChat = true
                page.nav.openCreatedChat(chatId)
                return
            }
            page.nav.push(c, { chatId: chatId })
        })
    }

    function maybeOpenCreated() {
        if (createdId && !openedChat && nav && nav.topPage === page && !nav.moving) {
            openedChat = true
            nav.openCreatedChat(createdId)
        }
    }

    Connections {
        target: page.nav
        function onTopPageChanged() { Qt.callLater(page.maybeOpenCreated) }
        function onMovingChanged() { Qt.callLater(page.maybeOpenCreated) }
    }

    // spinner in top-right bar while creating
    Ring {
        parent: page
        z: 10
        visible: page.creating
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 17
        width: 22; height: 22
        value: 0.72
        cross: false
        color: Theme.accent
        thickness: 2.2
    }

    // ---- channel photo ----
    Item { width: 1; height: 8 }
    Column {
        width: parent.width
        spacing: 10
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 100; height: 100
            Rectangle {
                anchors.fill: parent
                radius: 50
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                visible: page.photo === ""
                Icon {
                    anchors.centerIn: parent
                    width: 38; height: 38
                    name: "camera"
                    color: Theme.accent
                }
            }
            Avatar {
                anchors.fill: parent
                visible: page.photo !== ""
                source: page.photo
                letters: page.store.letters(name.text)
                tint: Theme.accent
            }
            MouseArea {
                anchors.fill: parent
                enabled: !page.creating
                onClicked: page.pickPhoto()
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t(page.photo ? "Rasmni o'zgartirish" : "Rasm qo'shish")
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 17
            MouseArea {
                anchors.fill: parent; anchors.margins: -8
                enabled: !page.creating
                onClicked: page.pickPhoto()
            }
        }
        Item { width: 1; height: 4 }
    }

    // ---- channel name and description ----
    SettingsGroup {
        note: Tr.t("Kanalingiz uchun ixtiyoriy tavsif yozishingiz mumkin.")
        Item {
            width: parent.width; height: 48
            TextInput {
                id: name
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                enabled: !page.creating
                maximumLength: 128
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                clip: true
                onAccepted: about.forceActiveFocus()
            }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                visible: !name.text
                text: Tr.t("Kanal nomi")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
            Rectangle {
                x: 16; anchors.bottom: parent.bottom
                width: parent.width - x; height: 0.5
                color: Theme.separator
            }
        }
        Item {
            width: parent.width; height: Math.max(48, about.contentHeight + 26)
            TextEdit {
                id: about
                x: 16; y: 13; width: parent.width - 32
                enabled: !page.creating
                wrapMode: TextEdit.Wrap
                color: Theme.text; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: 17
                onTextChanged: if (length > 255) remove(255, length)
            }
            Text {
                x: 16; y: 13
                visible: !about.text
                text: Tr.t("Tavsif")
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 17
            }
        }
    }

    Text {
        visible: page.errorText !== ""
        x: 32; width: parent.width - 64
        wrapMode: Text.Wrap
        text: page.errorText
        color: Theme.danger
        font.family: Theme.font; font.pixelSize: 14
    }

    Item { width: 1; height: Math.max(osk.h, safe.bottom) + 24 }

    Alert { id: alert; parent: page; anchors.fill: parent }
    Component {
        id: sheetMaker
        AttachSheet {
            rights: ({ photos: true, videos: false, files: false, music: false, other: false, voice: false, round: false })
            onRefused: (text) => page.nav.say(Tr.t("Faqat rasm tanlang"))
            onSend: (picked) => {
                const p = picked.find((f) => f.kind === "photo")
                if (p)
                    page.photo = p.path
            }
        }
    }
}
