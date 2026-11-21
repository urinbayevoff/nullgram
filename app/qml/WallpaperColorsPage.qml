// «Rang o'rnatish», as Telegram-iOS's ThemeColorsGridController: its gradients (four colours, the freeform one), then its
// colours, by day or by night, in three columns of squares (corners 16, 6 between). One tapped opens before it is set
// (WallpaperPreview, a backgroundTypeFill). iOS's «Set Custom Color» (its colour picker) waits.
import QtQuick

SubPage {
    id: page
    title: Tr.t("Rang o'rnatish")
    readonly property var gradients: Theme.dark
        ? ["1e3557,151a36,1c4352,2a4541", "1d223f,1d1832,1b2943,141631", "203439,102028,1d3c3a,172635", "1c2731,1a1c25,27303b,1b1b21", "3a1c3a,24193c,392e3e,1a1632", "2c211b,44332a,22191f,3b2d36", "1e3557,182036,1c4352,16263a", "111236,14424f,0b2334,3b315d", "2d4836,172b19,364331,103231"]
        : ["dbddbb,6ba587,d5d88d,88b884", "8dc0eb,b9d1ea,c6b1ef,ebd7ef", "97beeb,b1e9ea,c6b1ef,efb7dc", "8adbf2,888dec,e39fea,679ced", "b0cdeb,9fb0ea,bbead5,b2e3dd", "daeac8,a2b4ff,eccbff,b9e2ff", "dceb92,8fe1d6,67a3f2,85d685", "eaa36e,f0e486,f29ebf,e8c06e", "ffc3b2,e2c0ff,ffe7b2,f8cece"]
    readonly property var colours: Theme.dark
        ? ["1d2d3c", "111b26", "0b141e", "1f361f", "131f15", "0e1710", "2f2e27", "2a261f", "191817", "432e30", "2e1c1e", "1f1314", "432e3c", "2e1c28", "1f131b", "3c2e43", "291c2e", "1d1221", "312e43", "1e1c2e", "141221", "2f3f3f", "212d30", "141e20", "272524", "191716", "000000"]
        : ["d3dfea", "a5c5db", "6f99c8", "d2e3a9", "a4d48e", "7dbb6e", "e6ddae", "d5be91", "cba479", "ebc0b9", "e0a79d", "c97870", "ebb9c8", "e09db7", "d27593", "dac2ed", "d3a5e7", "b587d2", "c2c2ed", "a5a5e7", "7f7fd0", "c2e2ed", "a5d6e7", "7fbad0", "d6c2b9", "9c8882", "000000"]
    property var maker: null
    property var chatId: 0              // one chat's (WallpaperPage's): handed on to the preview
    property Item home: null
    function preview(fill) {
        const cs = fill.split(",").map((c) => parseInt(c, 16))
        const type = { "@type": "backgroundTypeFill",
                       fill: cs.length === 1 ? { "@type": "backgroundFillSolid", color: cs[0] }
                                             : { "@type": "backgroundFillFreeformGradient", colors: cs } }
        if (!maker)
            maker = Qt.createComponent("WallpaperPreview.qml")
        nav.push(maker, { type: type, chatId: chatId, home: home })
    }

    Rectangle {
        x: 16; width: parent.width - 32
        height: grid.height + 24
        radius: 12
        color: Theme.card
        Grid {
            id: grid
            x: 12; y: 12
            columns: 3
            spacing: 6
            readonly property real cell: Math.floor((parent.width - 24 - 12) / 3)
            Repeater {
                model: page.gradients.concat(page.colours)
                Item {
                    id: tile
                    required property string modelData
                    width: grid.cell; height: grid.cell
                    Wallpaper { anchors.fill: parent; radius: 16; spec: tile.modelData + ";0;;" }
                    Rectangle {         // (a colour near the card's is lost without an edge)
                        anchors.fill: parent; radius: 16
                        color: "transparent"
                        border.width: 0.5; border.color: Theme.separator
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.preview(tile.modelData) }
                }
            }
        }
    }
    Item { width: 1; height: 20 }
}
