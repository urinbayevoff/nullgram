// The words Nullgram shows, in Uzbek or English (Modified for OmonullOS, 2026-11: English added).
// The Uzbek words stay in the code where they were and are the keys (lang-en.js has their English),
// as ztlang does it for ztMETRO. The language is the Til page's choice (Prefs.lang), else omonullOS
// Settings' own (td.systemLang). A binding that calls t() reads `lang`, so it changes as it does;
// words already put into a model (a chat's last message, a service line) change as they come anew.
pragma Singleton
import QtQuick
import "lang-en.js" as EN

QtObject {
    id: tr
    readonly property string system: typeof td !== "undefined" && td && td.systemLang === "en" ? "en" : "uz"
    readonly property string lang: Prefs.lang === "en" || Prefs.lang === "uz" ? Prefs.lang : system
    readonly property bool en: lang === "en"
    property var _missed: ({})

    function _en(s) {
        const e = EN.words[s]
        if (e === undefined && !_missed[s]) {
            _missed[s] = true
            console.warn("nullgram: no English for", JSON.stringify(s))
        }
        return e
    }
    // the words in the language
    function t(s) {
        if (!en || !s)
            return s
        const e = _en(s)
        return e === undefined ? s : Array.isArray(e) ? e[1] : e
    }
    // with %1, %2 ... put in (the English may have them in another order)
    function f(s) {
        let r = t(s)
        for (let i = 1; i < arguments.length; i++)
            r = r.split("%" + i).join(String(arguments[i]))
        return r
    }
    // a count's words, %1 the count as shown: the English has [one, more] ("%1 member", "%1 members")
    function n(s, k, shown) {
        let r = s
        if (en) {
            const e = _en(s)
            r = e === undefined ? s : Array.isArray(e) ? e[k === 1 ? 0 : 1] : e
        }
        return r.split("%1").join(shown === undefined ? String(k) : String(shown))
    }

    // a date as each says it: "4-noyabr 2026" / "November 4, 2026" (month 1..12; year 0: none)
    readonly property var monthsUz: ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust",
                                     "sentabr", "oktabr", "noyabr", "dekabr"]
    readonly property var monthsEn: ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]
    function date(day, month, year) {
        return en ? monthsEn[month - 1] + " " + day + (year ? ", " + year : "")
                  : day + "-" + monthsUz[month - 1] + (year ? " " + year : "")
    }
    // the short weekday names, Sunday first
    function weekday(i) {
        return (en ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["Yak", "Dush", "Sesh", "Chor", "Pay", "Jum", "Shan"])[i]
    }
}
