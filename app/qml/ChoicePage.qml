// One of a few, ✓ by the chosen one (Telegram-iOS's small choice lists: «Auto-Delete Messages», «If Away For»,
// «Auto-Lock»): `choices` [{ t, v }], `value`; a tap marks it and says chosen(v) (the opener applies it). `ask`: a
// function of the new value that may hold it (true: it asked first and will call page.pick(v, true) itself).
import QtQuick

SubPage {
    id: page
    property string heading: ""
    property var choices: []
    property var value: null
    property string note: ""
    property string groupTitle: ""      // the group's title
    property var ask: null
    signal chosen(var v)
    title: heading

    function pick(v, asked) {
        if (v === value)
            return
        if (!asked && ask && ask(v))
            return
        value = v
        chosen(v)
    }

    SettingsGroup {
        title: page.groupTitle
        note: page.note
        Repeater {
            model: page.choices
            SettingsRow {
                required property var modelData
                required property int index
                text: modelData.t
                chevron: false
                tick: page.value === modelData.v
                last: index === page.choices.length - 1
                onClicked: page.pick(modelData.v)
            }
        }
    }
    Alert { id: alert; parent: page; anchors.fill: parent }
}
