// Secret chat encryption key visualization (Telegram's 4-color identicon grid + 4 key emojis).
// Rendered from TDLib secretChat.key_hash (16 bytes -> 8x8, 36 bytes -> 12x12, 2 bits per cell).
pragma ComponentBehavior: Bound
import QtQuick

SubPage {
    id: page
    title: Tr.t("Shifrlash kaliti")

    property var chatId: 0
    property int secretChatId: 0
    property string partnerName: ""

    readonly property var chat: (store.seen, store.chats[chatId])
    readonly property int scId: secretChatId || (chat && chat.type && chat.type["@type"] === "chatTypeSecret" ? chat.type.secret_chat_id : 0)
    readonly property var sc: (store.secretSeen, scId ? (store.secretChats[scId] || null) : null)
    readonly property string keyHash: sc && sc.key_hash ? String(sc.key_hash) : ""
    readonly property var keyBytes: store.decodeBase64Bytes(keyHash)
    readonly property var keyEmojis: store.secretKeyEmojis(keyHash)
    readonly property string keyHex: store.secretKeyHex(keyHash)
    readonly property string who: partnerName || (chat ? store.secretPartnerName(chat) : "") || Tr.t("Suhbatdosh")

    Component.onCompleted: {
        if (scId && !sc)
            store.getSecretChat(scId, null)
    }

    onKeyHashChanged: {
        if (identicon.available)
            identicon.requestPaint()
    }

    // ---- identicon + 4 emojis card ----
    Item {
        width: parent.width
        height: contentCol.height + 16

        Column {
            id: contentCol
            x: 16
            width: parent.width - 32
            spacing: 18

            // Identicon square card (or pending placeholder)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 244; height: 244
                radius: 20
                color: Theme.card
                border.color: Theme.separator
                border.width: 0.5

                Canvas {
                    id: identicon
                    visible: page.keyBytes.length > 0
                    anchors.centerIn: parent
                    width: 216; height: 216
                    readonly property var keyColors: ["#ffffff", "#d5e6f3", "#2d5775", "#2f99c9"]
                    onAvailableChanged: if (available) requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const bytes = page.keyBytes
                        if (!bytes || !bytes.length)
                            return
                        const side = bytes.length === 16 ? 8 : 12
                        const cell = width / side
                        let bit = 0
                        for (let iy = 0; iy < side; iy++) {
                            for (let ix = 0; ix < side; ix++) {
                                const idx = Math.floor(bit / 8) % bytes.length
                                const shift = bit % 8
                                const val = (bytes[idx] >> shift) & 3
                                bit += 2
                                ctx.fillStyle = keyColors[val]
                                ctx.fillRect(Math.floor(ix * cell), Math.floor(iy * cell),
                                             Math.ceil((ix + 1) * cell) - Math.floor(ix * cell),
                                             Math.ceil((iy + 1) * cell) - Math.floor(iy * cell))
                            }
                        }
                    }
                }

                Column {
                    visible: page.keyBytes.length === 0
                    anchors.centerIn: parent
                    width: parent.width - 36
                    spacing: 12
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 44; height: 44
                        name: "lock"
                        color: Theme.grey
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: Tr.t("Shifrlash kaliti suhbatdosh ulangandan keyin yaratiladi.")
                        color: Theme.grey
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }
            }

            // 4 key fingerprint emojis
            Row {
                visible: page.keyEmojis.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Repeater {
                    model: page.keyEmojis
                    Text {
                        required property string modelData
                        text: modelData
                        font.pixelSize: 38
                    }
                }
            }

            // Monospace hex fingerprint
            Rectangle {
                visible: page.keyHex !== ""
                width: parent.width
                height: hexText.implicitHeight + 20
                radius: 12
                color: Theme.card
                Text {
                    id: hexText
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: page.keyHex
                    color: Theme.grey
                    font.family: "monospace"
                    font.pixelSize: 12
                    lineHeight: 1.35
                }
            }

            // Explanation text (Telegram-iOS / Android style)
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.f("Bu rasm va emojilar %1 bilan maxfiy chatingizning shifrlash kalitidan yaratildi.", page.who)
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 15
                lineHeight: 1.25
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Tr.f("Agar %1ning qurilmasida ham xuddi shu rasm va emojilar ko'rinsa, uchdan-uchga shifrlash kafolatlanadi.", page.who)
                color: Theme.grey
                font.family: Theme.font; font.pixelSize: 14
                lineHeight: 1.25
            }
        }
    }

    Item { width: 1; height: safe.bottom + 16 }
}
