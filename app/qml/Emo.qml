// Apple emoji as images, Telegram's way (Modified for OmonullOS, 2026-11). One source for both the
// message text (Store.rich) and the picker (StickerPanel): the code-point->file map lives in
// app/emoji/emoji-map.json and the PNGs in app/emoji/apple (both local, gitignored). If the set is
// absent the map does not load (ready stays false) and callers keep the system font. They are used when
// chosen: Ko'rinish › Emoji (Prefs.emojiSet "apple"), or left to omonullOS Settings > theme > Emoji (td.appleEmoji);
// else the font (Noto) draws. The set is the user's own download (emoji_get.py); when it comes, goes or the
// choice changes, the map is read again (ready flips, so the bindings that ask fileUrl follow).
pragma Singleton
import QtQuick

QtObject {
    id: emo
    // the set's folder: nullgram_app.py's emoji_dir() (a checkout's app/emoji, or ~/.cache/nullgram-emoji)
    readonly property string dir: typeof td !== "undefined" && td && td.emojiDir ? td.emojiDir : Qt.resolvedUrl("../emoji/")
    readonly property string base: dir + "apple/"
    property int px: 20                  // inline size in message text
    property var map: null
    property bool ready: false
    readonly property bool use: Prefs.emojiSet === "apple" || (Prefs.emojiSet === "" && typeof td !== "undefined" && !!td && td.appleEmoji)
    onDirChanged: reload()
    onUseChanged: reload()
    function reload() {
        if (map === null)
            return              // (not read yet: the first load() will)
        map = null
        ready = false
        cache = ({}); cacheN = 0
        load()
    }
    // a cheap pre-test: does the text hold a char that could begin an emoji (so plain text skips the walk)
    readonly property var hint: /[©®‼⁉™ℹ←-⯿⤴⤵〰〽㊗㊙⃣️\ud83c-\udbff]/

    function load() {
        if (map !== null)
            return
        map = ({})
        if (!use) {
            console.log("nullgram: emoji pictures off (the system's chosen)")
            return
        }
        try {
            const x = new XMLHttpRequest()
            x.open("GET", dir + "emoji-map.json", false)
            x.send(null)
            if (x.status === 200 || x.status === 0) {
                map = JSON.parse(x.responseText)
                ready = !!map && Object.keys(map).length > 0
            }
        } catch (e) { ready = false }
        console.log("nullgram: emoji pictures", ready ? Object.keys(map).length : "off")
    }

    // the whole string's code points as a key (surrogate pairs by hand: Qt's Array.from splits them),
    // and its Apple file's url, or "" if the set has no such emoji
    function fileUrl(s) {
        load()
        if (!ready || !s)
            return ""
        let key = ""
        for (let k = 0; k < s.length;) {
            let cp = s.charCodeAt(k)
            if (cp >= 0xD800 && cp <= 0xDBFF && k + 1 < s.length) {
                const d = s.charCodeAt(k + 1)
                if (d >= 0xDC00 && d <= 0xDFFF) { cp = 0x10000 + ((cp - 0xD800) << 10) + (d - 0xDC00); k += 2 }
                else k++
            } else k++
            key += (key ? "-" : "") + cp.toString(16)
        }
        const f = map[key]
        return f ? base + f : ""
    }

    // an escaped HTML run with its emoji turned to <img> (StyledText draws them); &amp; &lt; <br> and
    // ordinary text pass through. The longest code-point run that the map knows wins at each step.
    function emojify(s, size) {         // size: the pictures' side (default px, the message text's)
        load()
        if (!ready)
            return s
        // a row made again while scrolling back asks for the same text: answer from memory
        const ck = (size || px) + "|" + s
        const hit = cache[ck]
        if (hit !== undefined)
            return hit
        const res = walk(s, size)
        if (cacheN >= 3000) { cache = ({}); cacheN = 0 }     // a crude cap: start over rather than grow for ever
        cache[ck] = res
        cacheN++
        return res
    }
    property var cache: ({})
    property int cacheN: 0
    function walk(s, size) {
        const cp = [], src = []
        for (let k = 0; k < s.length;) {
            const c = s.charCodeAt(k)
            if (c >= 0xD800 && c <= 0xDBFF && k + 1 < s.length) {
                const d = s.charCodeAt(k + 1)
                if (d >= 0xDC00 && d <= 0xDFFF) {
                    cp.push(0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)); src.push(s.substr(k, 2)); k += 2; continue
                }
            }
            cp.push(c); src.push(s[k]); k++
        }
        let out = ""
        const n = cp.length
        for (let i = 0; i < n;) {
            const c0 = cp[i]
            // most chars cannot begin an emoji: letters (Latin, Cyrillic), digits' runs, spaces, punctuation.
            // Every char used to build up to 12 keys of up to 12 code points (2026-11-23: a flick through a
            // group spent about half of its rows' make time here with Apple emoji on)
            if (c0 < 0x2000 && c0 !== 0x23 && c0 !== 0x2a && (c0 < 0x30 || c0 > 0x39) && c0 !== 0xa9 && c0 !== 0xae) {
                out += src[i]; i++
                continue
            }
            let file = "", len = 0
            const hi = Math.min(12, n - i)
            let key = ""
            for (let L = 1; L <= hi; L++) {         // the keys grow one code point at a time; the longest known wins
                key += (L > 1 ? "-" : "") + cp[i + L - 1].toString(16)
                const f = map[key]
                if (f) { file = f; len = L }
            }
            if (file) {
                out += "<img src=\"" + base + file + "\" width=\"" + (size || px) + "\" height=\"" + (size || px) + "\">"
                i += len
            } else {
                out += src[i]; i++
            }
        }
        return out
    }

    Component.onCompleted: load()
}
