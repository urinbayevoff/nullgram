// Hikoya joylash (StoryCreatePage): Telegram-iOS style story creation flow.
// Step 1 ("pick"): 3-column gallery of recent photos and videos (AttachSheet pattern).
// Step 2 ("edit"): full-screen photo/video preview + caption input + privacy/duration chip -> Next.
// Step 3 ("privacy"): who can view (Everyone / Contacts / Close Friends / Selected Users),
//                     duration (6 / 12 / 24 / 48 h; non-Premium locked to 24 h), options -> Post Story.
// Step 4 ("contacts"): contact picker for Selected Users (NewGroupPage pattern: chips + search + checks).
pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

Page {
    id: page

    property string step: "pick"            // "pick" | "edit" | "privacy" | "contacts"
    property var gallery: []                // recent photos & videos from td.recent()
    property string mediaPath: ""
    property bool isVideo: false
    property int videoDuration: 0
    property bool muted: false
    property string privacyKind: "everyone" // "everyone" | "contacts" | "closeFriends" | "selected"
    property var selectedIds: []            // user ids for "selected" privacy
    property int periodHours: 24            // 6, 12, 24, 48 (non-Premium: 24 only)
    property bool saveToProfile: true       // is_posted_to_chat_page
    property bool protectContent: false     // protect_content
    property bool posting: false
    property string errorText: ""

    property var allContacts: []
    property bool contactsLoaded: false
    property string contactQuery: ""
    property int now: Date.now() / 1000

    readonly property bool isPremium: !!(store && store.me && store.me.is_premium)
    readonly property int captionLimit: isPremium ? 2048 : 200
    readonly property real toastFloor: step === "edit" ? (editFoot.height + 10)
                                     : step === "privacy" ? (82 + safe.bottom)
                                     : safe.bottom

    color: step === "edit" ? "#000000" : step === "privacy" ? Theme.grouped : Theme.bg

    Component.onCompleted: {
        refreshGallery()
    }

    Component.onDestruction: {
        vidPlayer.stop()
    }

    onStepChanged: {
        if (step !== "edit") {
            vidPlayer.stop()
            keyboardDown()
        } else if (isVideo && mediaPath !== "") {
            vidPlayer.source = "file://" + mediaPath
            vidPlayer.play()
        }
        if (step === "contacts" && !contactsLoaded)
            loadContacts()
    }

    function refreshGallery() {
        const all = td.recent() || []
        gallery = all.filter((f) => (f.kind === "photo" && !f.path.toLowerCase().endsWith(".gif"))
                                    || f.kind === "video")
    }

    function loadContacts() {
        now = Date.now() / 1000
        store.contacts((list) => {
            if (!page)
                return
            page.allContacts = list || []
            page.contactsLoaded = true
            page.rebuildContacts()
            page.rebuildChips()
        })
    }

    function selectMedia(path, video, dur) {
        if (!path)
            return
        mediaPath = path
        isVideo = !!video
        if (isVideo) {
            const p = dur > 0 ? dur : (td.probe(path).duration || 0)
            videoDuration = p > 0 ? p : 1
        } else {
            videoDuration = 0
        }
        errorText = ""
        step = "edit"
    }

    function keyboardDown() {
        captionField.focus = false
        contactSearch.focus = false
        if (osk.h > 0)
            osk.hide()
    }

    function dismiss() {
        if (posting)
            return true
        if (step === "contacts") {
            keyboardDown()
            step = "privacy"
            return true
        }
        if (step === "privacy") {
            step = "edit"
            return true
        }
        if (step === "edit") {
            keyboardDown()
            vidPlayer.stop()
            step = "pick"
            return true
        }
        return false
    }

    function formatDur(sec) {
        const s = Math.max(0, Math.round(sec || 0))
        const m = Math.floor(s / 60), r = s % 60
        return m + ":" + (r < 10 ? "0" + r : r)
    }

    function privacySummary() {
        if (privacyKind === "contacts")
            return Tr.t("Kontaktlar")
        if (privacyKind === "closeFriends")
            return Tr.t("Yaqin do'stlar")
        if (privacyKind === "selected")
            return selectedIds.length > 0 ? Tr.n("%1 kishi", selectedIds.length) : Tr.t("Tanlanganlar")
        return Tr.t("Hamma")
    }

    function pickPeriod(hours) {
        if (!isPremium && hours !== 24) {
            nav.say(Tr.t("Bu muddat faqat Telegram Premium bilan mavjud"))
            return
        }
        periodHours = hours
    }

    function isSelected(uid) {
        return selectedIds.indexOf(uid) >= 0
    }

    function toggleContact(uid) {
        if (isSelected(uid))
            selectedIds = selectedIds.filter((id) => id !== uid)
        else
            selectedIds = selectedIds.concat([uid])
        rebuildChips()
    }

    function userPhotoNow(u) {
        const f = u && u.profile_photo && u.profile_photo.small
        return f && f.local && f.local.is_downloading_completed ? f.local.path : ""
    }

    function rebuildChips() {
        chips.clear()
        for (const uid of selectedIds) {
            const u = store.users[uid]
            const full = u ? (u.first_name + " " + u.last_name).trim() : String(uid)
            const first = u && u.first_name ? u.first_name : full
            chips.append({
                userId: uid, firstName: first, fullName: full,
                photo: userPhotoNow(u), letters: store.letters(full),
                tint: store.tints[Math.abs(uid) % store.tints.length]
            })
        }
    }

    function rebuildContacts() {
        contactRows.clear()
        const f = store.fold(contactQuery)
        for (const u of allContacts) {
            const full = (u.first_name + " " + u.last_name).trim()
            if (f && store.fold(full).indexOf(f) < 0)
                continue
            contactRows.append({
                userId: u.id, name: full,
                photo: userPhotoNow(u), letters: store.letters(full),
                tint: store.tints[Math.abs(u.id) % store.tints.length]
            })
        }
    }

    function publishNow() {
        if (posting || !mediaPath)
            return
        if (privacyKind === "selected" && selectedIds.length === 0) {
            nav.say(Tr.t("Kamida bitta kontakt tanlang"))
            step = "contacts"
            return
        }
        // as Telegram: the page goes at once and the story goes up in the background, the ring round «Hikoyam»
        // in the chat list showing how far (ChatListPage opens the stories row); Main says how it ended (storyPosted)
        posting = true          // (no second tap while it goes)
        keyboardDown()
        const periodSec = (isPremium ? periodHours : 24) * 3600
        store.postStory(
            mediaPath,
            isVideo,
            captionField.text,
            { kind: privacyKind, userIds: selectedIds.slice() },
            periodSec,
            null,
            { saveToProfile: saveToProfile, protectContent: protectContent, duration: videoDuration }
        )
        nav.pop()
    }

    ListModel { id: contactRows }
    ListModel { id: chips }

    // =========================================================================
    // STEP 1: GALLERY PICKER (AttachSheet pattern)
    // =========================================================================
    Item {
        id: pickView
        visible: page.step === "pick"
        anchors.fill: parent

        Rectangle {
            id: pickBar
            width: parent.width; height: 56
            color: Theme.bg
            z: 5

            Text {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: Theme.accent
                opacity: pickBack.pressed ? 0.4 : 1
                font.family: Theme.font; font.pixelSize: 34
            }
            MouseArea {
                id: pickBack
                width: 72; height: parent.height
                onClicked: page.nav.pop()
            }

            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Tr.t("Yangi hikoya")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Tr.t("Rasm yoki video tanlang")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 12
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }

        GridView {
            id: grid
            y: pickBar.height
            width: parent.width; height: parent.height - y
            clip: true
            cellWidth: width / 3
            cellHeight: Math.round(cellWidth * 1.25)
            model: page.gallery
            bottomMargin: safe.bottom + 16

            delegate: Item {
                id: tile
                required property var modelData
                width: grid.cellWidth; height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent; anchors.margins: 1
                    color: Theme.highlight
                }
                Image {
                    anchors.fill: parent; anchors.margins: 1
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(width, height)
                    source: "image://thumb/" + tile.modelData.path
                }
                Rectangle {
                    visible: tile.modelData.kind === "video"
                    x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    width: 28; height: 20; radius: 10
                    color: Qt.rgba(0, 0, 0, 0.58)
                    Icon {
                        anchors.centerIn: parent
                        width: 12; height: 12
                        name: "play"
                        color: "white"
                    }
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 1
                    color: "black"
                    opacity: tileHit.pressed ? 0.22 : 0
                }
                MouseArea {
                    id: tileHit
                    anchors.fill: parent
                    onClicked: page.selectMedia(tile.modelData.path, tile.modelData.kind === "video", 0)
                }
            }
        }

        Text {
            visible: page.gallery.length === 0
            anchors.centerIn: parent
            width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: Tr.t("Rasm yoki video topilmadi.\nFayllar ~/Pictures, ~/Videos, ~/Downloads papkalaridan olinadi.")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }

    // =========================================================================
    // STEP 2: FULL-SCREEN PREVIEW + CAPTION
    // =========================================================================
    Item {
        id: editView
        visible: page.step === "edit"
        anchors.fill: parent

        Image {
            id: previewImg
            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(width * 2, height * 2)
            source: page.mediaPath
                ? (page.isVideo ? "image://thumb/" + page.mediaPath : "file://" + page.mediaPath)
                : ""
        }

        VideoOutput {
            id: vidOut
            anchors.fill: parent
            visible: page.isVideo && page.step === "edit"
            fillMode: VideoOutput.PreserveAspectFit
        }

        MediaPlayer {
            id: vidPlayer
            videoOutput: vidOut
            audioOutput: AudioOutput { muted: page.muted }
            loops: MediaPlayer.Infinite
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (captionField.activeFocus || osk.h > 0) {
                    page.keyboardDown()
                    return
                }
                if (page.isVideo) {
                    if (vidPlayer.playbackState === MediaPlayer.PlayingState)
                        vidPlayer.pause()
                    else
                        vidPlayer.play()
                }
            }
        }

        // Top dark scrim + back / video pills
        Rectangle {
            width: parent.width; height: 84
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                GradientStop { position: 1; color: "transparent" }
            }

            Rectangle {
                x: 12; y: 12
                width: 38; height: 38; radius: 19
                color: Qt.rgba(0, 0, 0, 0.45)
                opacity: editBack.pressed ? 0.5 : 1
                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -2
                    text: "‹"
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 28
                }
                MouseArea {
                    id: editBack
                    anchors.fill: parent; anchors.margins: -6
                    onClicked: {
                        page.keyboardDown()
                        page.step = "pick"
                    }
                }
            }

            // Video duration & mute controls
            Row {
                visible: page.isVideo
                anchors.horizontalCenter: parent.horizontalCenter
                y: 16
                spacing: 8

                Rectangle {
                    height: 30; width: durLabel.implicitWidth + 32; radius: 15
                    color: Qt.rgba(0, 0, 0, 0.48)
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 11; height: 11
                            name: "play"
                            color: "white"
                        }
                        Text {
                            id: durLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.formatDur(page.videoDuration)
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                }

                Rectangle {
                    height: 30; width: muteLabel.implicitWidth + 20; radius: 15
                    color: Qt.rgba(0, 0, 0, 0.48)
                    opacity: muteHit.pressed ? 0.5 : 1
                    Text {
                        id: muteLabel
                        anchors.centerIn: parent
                        text: page.muted ? Tr.t("Ovoz o'chiq") : Tr.t("Ovoz yoqiq")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    MouseArea {
                        id: muteHit
                        anchors.fill: parent
                        onClicked: page.muted = !page.muted
                    }
                }
            }
        }

        // Bottom dark scrim + caption input + audience chip & Next button
        Rectangle {
            id: editFoot
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: captionWrap.height + 72 + Math.max(osk.h, safe.bottom)
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.28; color: Qt.rgba(0, 0, 0, 0.62) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.88) }
            }

            Rectangle {
                id: captionWrap
                x: 14
                anchors.bottom: editActions.top; anchors.bottomMargin: 10
                width: parent.width - 28
                height: Math.max(42, Math.min(84, captionField.contentHeight + 18))
                radius: 21
                color: Qt.rgba(0.12, 0.12, 0.14, 0.78)
                border.color: captionField.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.24)
                border.width: 1

                Flickable {
                    id: captionFlick
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: capCount.visible ? capCount.width + 20 : 16
                    anchors.topMargin: 9; anchors.bottomMargin: 9
                    contentWidth: width
                    contentHeight: captionField.contentHeight
                    clip: true

                    TextEdit {
                        id: captionField
                        width: captionFlick.width
                        wrapMode: TextEdit.Wrap
                        color: "white"
                        selectionColor: Theme.accent
                        font.family: Theme.font; font.pixelSize: 16
                        onTextChanged: {
                            if (text.length > page.captionLimit)
                                text = text.slice(0, page.captionLimit)
                        }
                        Text {
                            visible: !captionField.text
                            text: Tr.t("Izoh qo'shish…")
                            color: Qt.rgba(1, 1, 1, 0.58)
                            font: captionField.font
                        }
                    }
                }

                Text {
                    id: capCount
                    visible: captionField.text.length > page.captionLimit - 40
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 11
                    text: String(page.captionLimit - captionField.text.length)
                    color: captionField.text.length >= page.captionLimit ? Theme.danger : Qt.rgba(1, 1, 1, 0.65)
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
            }

            Item {
                id: editActions
                x: 14
                width: parent.width - 28; height: 44
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12 + Math.max(osk.h, safe.bottom)

                // Audience + duration pill
                Rectangle {
                    id: audPill
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: 38
                    width: Math.min(parent.width - nextBtn.width - 12, audRow.implicitWidth + 24)
                    radius: 19
                    color: Qt.rgba(1, 1, 1, 0.16)
                    opacity: audHit.pressed ? 0.55 : 1

                    Row {
                        id: audRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            name: "eye"
                            color: "white"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.privacySummary() + " · " + Tr.n("%1 soat", page.periodHours)
                            color: "white"
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                        }
                    }
                    MouseArea {
                        id: audHit
                        anchors.fill: parent
                        onClicked: {
                            page.keyboardDown()
                            page.step = "privacy"
                        }
                    }
                }

                // Next button
                Rectangle {
                    id: nextBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 42
                    width: Math.max(108, nextLabel.implicitWidth + 36)
                    radius: 21
                    color: Theme.accent
                    opacity: nextHit.pressed ? 0.7 : 1

                    Text {
                        id: nextLabel
                        anchors.centerIn: parent
                        text: Tr.t("Keyingi")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: nextHit
                        anchors.fill: parent
                        onClicked: {
                            page.keyboardDown()
                            page.step = "privacy"
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // STEP 3: PRIVACY, DURATION & PUBLISH
    // =========================================================================
    Item {
        id: privacyView
        visible: page.step === "privacy"
        anchors.fill: parent

        Rectangle {
            id: privBar
            width: parent.width; height: 56
            color: Theme.grouped
            z: 5

            Text {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: page.posting ? Theme.grey : Theme.accent
                opacity: privBack.pressed ? 0.4 : 1
                font.family: Theme.font; font.pixelSize: 34
            }
            MouseArea {
                id: privBack
                width: 72; height: parent.height
                enabled: !page.posting
                onClicked: page.step = "edit"
            }

            Text {
                anchors.centerIn: parent
                text: Tr.t("Hikoya sozlamalari")
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
        }

        Flickable {
            id: privFlick
            y: privBar.height
            width: parent.width
            height: parent.height - y - postBar.height
            clip: true
            contentHeight: privCol.height + 28

            Column {
                id: privCol
                y: 8
                width: parent.width
                spacing: 20

                // Compact media + caption summary card
                SettingsGroup {
                    Item {
                        width: parent.width; height: 74
                        Rectangle {
                            id: miniThumbWrap
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 56; radius: 8
                            color: Theme.highlight
                            clip: true
                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(88, 112)
                                source: page.mediaPath
                                    ? (page.isVideo ? "image://thumb/" + page.mediaPath : "file://" + page.mediaPath)
                                    : ""
                            }
                            Rectangle {
                                visible: page.isVideo
                                anchors.centerIn: parent
                                width: 22; height: 22; radius: 11
                                color: Qt.rgba(0, 0, 0, 0.55)
                                Icon { anchors.centerIn: parent; width: 10; height: 10; name: "play"; color: "white" }
                            }
                        }
                        Column {
                            x: 70; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 16
                            spacing: 3
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: page.isVideo ? Tr.f("Video · %1", page.formatDur(page.videoDuration)) : Tr.t("Rasm")
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: captionField.text.trim() !== "" ? captionField.text.trim() : Tr.t("Izohsiz")
                                color: Theme.grey
                                font.family: Theme.font; font.pixelSize: 14
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !page.posting
                            onClicked: page.step = "edit"
                        }
                    }
                }

                // Who can view
                SettingsGroup {
                    title: Tr.t("Kimlar ko'radi")
                    SettingsRow {
                        icon: "globe"; tint: "#2a9ef1"
                        text: Tr.t("Hamma")
                        chevron: false
                        tick: page.privacyKind === "everyone"
                        onClicked: if (!page.posting) page.privacyKind = "everyone"
                    }
                    SettingsRow {
                        icon: "person"; tint: "#34c759"
                        text: Tr.t("Kontaktlar")
                        chevron: false
                        tick: page.privacyKind === "contacts"
                        onClicked: if (!page.posting) page.privacyKind = "contacts"
                    }
                    SettingsRow {
                        icon: "star"; tint: "#30d158"
                        text: Tr.t("Yaqin do'stlar")
                        chevron: false
                        tick: page.privacyKind === "closeFriends"
                        onClicked: if (!page.posting) page.privacyKind = "closeFriends"
                    }
                    SettingsRow {
                        icon: "group"; tint: "#ff9500"
                        text: Tr.t("Tanlanganlar")
                        value: page.privacyKind === "selected" && page.selectedIds.length > 0
                            ? Tr.n("%1 kishi", page.selectedIds.length)
                            : ""
                        chevron: true
                        tick: false
                        last: true
                        onClicked: {
                            if (page.posting)
                                return
                            page.privacyKind = "selected"
                            page.step = "contacts"
                        }
                    }
                }

                // Active period: 6 / 12 / 24 / 48 hours
                SettingsGroup {
                    title: Tr.t("Muddat")
                    note: page.isPremium
                        ? Tr.t("Hikoya tanlangan muddatdan keyin arxivga o'tadi.")
                        : Tr.t("6, 12 va 48 soatlik muddat Telegram Premium bilan ochiladi.")

                    Item {
                        width: parent.width; height: 60

                        Row {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 20; height: 40
                            spacing: 8

                            Repeater {
                                model: [6, 12, 24, 48]
                                Rectangle {
                                    id: pChip
                                    required property int modelData
                                    readonly property bool locked: !page.isPremium && modelData !== 24
                                    readonly property bool chosen: page.periodHours === modelData
                                    width: (parent.width - 24) / 4
                                    height: 40; radius: 10
                                    color: chosen ? Theme.accent
                                         : (pHit.pressed ? Theme.separator : Theme.highlight)
                                    opacity: locked ? 0.65 : 1

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Icon {
                                            visible: pChip.locked
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 11; height: 11
                                            name: "lock"
                                            color: Theme.grey
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Tr.n("%1 soat", pChip.modelData)
                                            color: pChip.chosen ? "white" : (pChip.locked ? Theme.grey : Theme.text)
                                            font.family: Theme.font; font.pixelSize: 12
                                            font.weight: pChip.chosen ? Font.DemiBold : Font.Medium
                                        }
                                    }
                                    MouseArea {
                                        id: pHit
                                        anchors.fill: parent
                                        enabled: !page.posting
                                        onClicked: page.pickPeriod(pChip.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Additional toggles
                SettingsGroup {
                    title: Tr.t("Qo'shimcha")
                    SettingsRow {
                        text: Tr.t("Profilga saqlash")
                        sub: Tr.t("Muddat tugagach hikoya profil sahifasida qoladi")
                        toggle: true
                        on: page.saveToProfile
                        onClicked: if (!page.posting) page.saveToProfile = !page.saveToProfile
                    }
                    SettingsRow {
                        text: Tr.t("Saqlashni cheklash")
                        sub: Tr.t("Skrinshot olish va uzatishni taqiqlaydi")
                        toggle: true
                        on: page.protectContent
                        last: true
                        onClicked: if (!page.posting) page.protectContent = !page.protectContent
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
            }
        }

        // Sticky publish bar (extends to screen bottom; button lifted by safe.bottom)
        Rectangle {
            id: postBar
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 76 + safe.bottom
            color: Theme.grouped

            Rectangle {
                width: parent.width; height: 0.5
                color: Theme.separator
            }

            Rectangle {
                id: postBtn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16 + safe.bottom
                width: parent.width - 32; height: 50; radius: 25
                color: Theme.accent
                opacity: postHit.pressed ? 0.72 : 1

                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Ring {
                        visible: page.posting
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        value: Math.max(0.15, page.store ? page.store.storyPosting : 0.2)
                        cross: false
                        color: "white"
                        thickness: 2.2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.posting ? Tr.t("Hikoya yuklanmoqda…") : Tr.t("Hikoyani joylash")
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: postHit
                    anchors.fill: parent
                    enabled: !page.posting
                    onClicked: page.publishNow()
                }
            }
        }
    }

    // =========================================================================
    // STEP 4: SELECTED USERS CONTACT PICKER (NewGroupPage pattern)
    // =========================================================================
    Item {
        id: contactsView
        visible: page.step === "contacts"
        anchors.fill: parent

        Rectangle {
            id: cBar
            width: parent.width; height: 56
            color: Theme.bg
            z: 5

            Text {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: Theme.accent
                opacity: cBack.pressed ? 0.4 : 1
                font.family: Theme.font; font.pixelSize: 34
            }
            MouseArea {
                id: cBack
                width: 72; height: parent.height
                onClicked: {
                    page.keyboardDown()
                    page.step = "privacy"
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Tr.t("Tanlanganlar")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.selectedIds.length > 0 ? Tr.n("%1 kishi", page.selectedIds.length) : Tr.t("Kontaktlarni tanlang")
                    color: Theme.grey
                    font.family: Theme.font; font.pixelSize: 12
                }
            }

            Text {
                id: cDoneText
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Tayyor")
                color: Theme.accent
                opacity: cDoneHit.pressed ? 0.4 : 1
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            MouseArea {
                id: cDoneHit
                anchors.right: parent.right
                width: cDoneText.width + 32; height: parent.height
                onClicked: {
                    page.keyboardDown()
                    page.step = "privacy"
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }

        // Selected chips strip
        Item {
            id: chipStrip
            y: cBar.height
            width: parent.width
            height: chips.count > 0 ? 48 : 0
            clip: true

            ListView {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                orientation: ListView.Horizontal
                spacing: 8
                model: chips
                delegate: Rectangle {
                    id: chip
                    required property var userId
                    required property string firstName
                    required property string photo
                    required property string letters
                    required property string tint
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    height: 32
                    width: chipLbl.x + chipLbl.implicitWidth + 26
                    radius: 16
                    color: chipHit.pressed ? Theme.highlight
                         : (Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.28) : Qt.rgba(0.46, 0.46, 0.5, 0.14))

                    Avatar {
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        source: chip.photo; letters: chip.letters; tint: chip.tint || Theme.accent
                    }
                    Text {
                        id: chipLbl
                        x: 36; anchors.verticalCenter: parent.verticalCenter
                        text: chip.firstName
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Icon {
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12
                        name: "cross"
                        color: Theme.grey
                    }
                    MouseArea {
                        id: chipHit
                        anchors.fill: parent
                        onClicked: page.toggleContact(chip.userId)
                    }
                }
            }
            Rectangle {
                visible: chips.count > 0
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }

        // Contact search input
        Item {
            id: cSearchBox
            y: chipStrip.y + chipStrip.height
            width: parent.width; height: 48

            Rectangle {
                x: 14; y: 6
                width: parent.width - 28; height: 36; radius: 18
                color: Theme.dark ? Qt.rgba(0.46, 0.46, 0.5, 0.24) : Qt.rgba(0.46, 0.46, 0.5, 0.12)

                Icon {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    name: "search"; width: 17; height: 17; color: Theme.grey
                }
                TextInput {
                    id: contactSearch
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 14
                    color: Theme.text; selectionColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onTextChanged: {
                        page.contactQuery = text.trim()
                        page.rebuildContacts()
                    }
                    Text {
                        visible: !contactSearch.text
                        text: Tr.t("Kontaktlarni qidirish")
                        color: Theme.grey
                        font: contactSearch.font
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 0.5
                color: Theme.separator
            }
        }

        ListView {
            id: cList
            y: cSearchBox.y + cSearchBox.height
            width: parent.width; height: parent.height - y
            clip: true
            model: contactRows
            cacheBuffer: 400
            bottomMargin: Math.max(osk.h, safe.bottom) + 16
            onMovementStarted: page.keyboardDown()

            delegate: Rectangle {
                id: crow
                required property var userId
                required property string name
                required property string photo
                required property string letters
                required property string tint
                readonly property bool chosen: page.selectedIds.indexOf(userId) >= 0
                width: cList.width; height: 60
                color: cHit.pressed ? Theme.highlight : Theme.bg
                property string pic: photo

                Component.onCompleted: {
                    if (!pic && userId > 0)
                        page.store.userPhoto(page.store.users[userId], (p) => { if (crow) crow.pic = p })
                }

                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 11
                    color: crow.chosen ? Theme.accent : "transparent"
                    border.width: crow.chosen ? 0 : 1.5
                    border.color: Theme.separator
                    Icon {
                        visible: crow.chosen
                        anchors.centerIn: parent
                        width: 15; height: 15; name: "check"; color: "white"
                    }
                }
                Avatar {
                    x: 52; anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 44
                    source: crow.pic; letters: crow.letters; tint: crow.tint || Theme.accent
                }
                Text {
                    x: 108; y: 10
                    width: parent.width - x - 14
                    elide: Text.ElideRight
                    text: crow.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    x: 108; y: 32
                    width: parent.width - x - 14
                    elide: Text.ElideRight
                    readonly property string st: page.store.seen >= 0 ? page.store.userStatus(page.store.users[crow.userId], page.now) : ""
                    text: st
                    color: st === Tr.t("onlayn") ? Theme.accent : Theme.grey
                    font.family: Theme.font; font.pixelSize: 14
                }
                Rectangle {
                    x: 108; anchors.bottom: parent.bottom
                    width: parent.width - x; height: 0.5
                    color: Theme.separator
                }
                MouseArea {
                    id: cHit
                    anchors.fill: parent
                    onClicked: page.toggleContact(crow.userId)
                }
            }
        }

        Text {
            visible: page.contactsLoaded && contactRows.count === 0
            y: cSearchBox.y + cSearchBox.height + 90
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.contactQuery ? Tr.t("Hech narsa topilmadi") : Tr.t("Kontaktlar yo'q")
            color: Theme.grey
            font.family: Theme.font; font.pixelSize: 15
        }
    }
}
