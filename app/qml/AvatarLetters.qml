// An Avatar's initials, loaded by its Loader only when there is no picture (a file of its own: an inline
// Component was made with every Avatar, shown or not -- 0.1 ms each, ~600 in a flick through a group).
import QtQuick

Text {
    // qmllint disable missing-property
    text: parent ? parent.letters : ""
    font.pixelSize: parent ? Math.round(parent.side * 0.38) : 12
    // kept inside the circle: a letter from a wide, tall script's font (𒐫, a nickname's cuneiform) ran out of
    // it over the row; Latin, Cyrillic, emoji come well under this and stay as they were
    scale: parent ? Math.min(1, parent.side * 0.74 / Math.max(implicitWidth, 1), parent.side * 0.74 / Math.max(implicitHeight, 1)) : 1
    // qmllint enable missing-property
    color: "white"
    font.family: Theme.font
    font.weight: Font.DemiBold
}
