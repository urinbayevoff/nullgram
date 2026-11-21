// The app's own themes, as Telegram-iOS builds them: four bases (PresentationBuiltinThemeReference: dayClassic,
// nightAccent, day, night — the row's order in ThemePickerController), each with its accent colours
// (PresentationThemeBaseColor, and ThemeColorPresets.swift's presets: an accent, our bubbles' colours, a background),
// and what a base and an accent make of the app's colours (customizeDefaultDayTheme,
// customizeDefaultDarkPresentationTheme, customizeDefaultDarkTintedPresentationTheme).
// look(base, key) is what Store puts into Theme. Colours here are numbers (0xrrggbb), "#rrggbb" in a look.
.pragma library

const BASES = [{ id: "classic", dark: false, name: "Klassik" }, { id: "tinted", dark: true, name: "Qorong'i" },
               { id: "day", dark: false, name: "Kun" }, { id: "night", dark: true, name: "Tun" }]

const COLORS = { blue: 0x0088ff, cyan: 0x00c2ed, green: 0x29b327, pink: 0xeb6ca4, orange: 0xf08200, purple: 0x9472ee,
                 red: 0xd33213, yellow: 0xedb400, gray: 0x6d839e, black: 0x000000, white: 0xffffff }
const ORDER = ["blue", "cyan", "green", "pink", "orange", "purple", "red", "yellow", "gray", "black", "white"]

// Telegram's patterns by their names (BuiltinWallpaperData)
const SLUGS = { d: "fqv01SQemVIBAAAApND8LDRUhRU", v1: "RlZs2PJkSFADAAAAElGaGwgJBgU", v2: "9LW_RcoOSVACAAAAFTk3DTyXN-M",
                v3: "CJNyxPMgSVAEAAAAvW9sMwc51cw", v4: "BQqgrGnjSFABAAAA8mQDBXQcARE", v5: "MIo6r0qGSFAFAAAAtL8TsDzNX60",
                v6: "9iklpvIPQVABAAAAORQXKur_Eyc", v7: "H6rz6geXUFIMAAAAuUs7m6cXbcc", v9: "mP3FG_iwSFAFAAAA2AklJO978pA",
                v10: "Ujx2TFcJSVACAAAARJ4vLa50MkM", v11: "RepJ5uE_SVABAAAAr4d0YhgB850", v12: "9GcNVISdSVADAAAAUcw5BYjELW4",
                v13: "-Xc-np9y2VMCAAAARKr0yNNPYW0", v14: "JrNEYdNhSFABAAAA9WtRdJkPRbY" }
function wp(v, colors, intensity) {
    return { slug: SLUGS[v], colors: colors, intensity: intensity }
}

const PRESETS = {
    classic: [{ key: "p106", accent: 0xf55783, bubbles: [0xd6f5ff, 0xc9fdfe], wall: wp("d", [0x8dc0eb, 0xb9d1ea, 0xc6b1ef, 0xebd7ef], 50) },
              { key: "p102", accent: 0xff5fa9, bubbles: [0xfff4d7], wall: wp("v12", [0xeaa36e, 0xf0e486, 0xf29ebf, 0xe8c06e], 50) },
              { key: "p104", accent: 0x5a9e29, bubbles: [0xfff8df], wall: wp("v13", [0x7fc289, 0xe4d573, 0xafd677, 0xf0c07a], 50) },
              { key: "p101", accent: 0x7e5fe5, bubbles: [0xf5e2ff], wall: wp("v14", [0xe4b2ea, 0x8376c2, 0xeab9d9, 0xb493e6], 50) },
              { key: "p107", accent: 0x2cb9ed, bubbles: [0xadf7b5, 0xfcff8b], wall: wp("v3", [0x1a2e1a, 0x47623c, 0x222e24, 0x314429], 50) },
              { key: "p103", accent: 0x199972, bubbles: [0xfffec7], wall: wp("v3", [0xdceb92, 0x8fe1d6, 0x67a3f2, 0x85d685], 50) },
              { key: "p105", accent: 0xda90d9, bubbles: [0x94fff9, 0xccffc7], wall: wp("v9", [0xffc3b2, 0xe2c0ff, 0xffe7b2], 50) }],
    day: [{ key: "p101", accent: 0x0088ff, bubbles: [0x0088ff, 0xff53f4], wall: null },
          { key: "p102", accent: 0x00b09b, bubbles: [0xaee946, 0x00b09b], wall: null },
          { key: "p103", accent: 0xd33213, bubbles: [0xf9db00, 0xd33213], wall: null },
          { key: "p104", accent: 0xea8ced, bubbles: [0xea8ced, 0x00c2ed], wall: null }],
    night: [{ key: "p102", accent: 0x00b09b, bubbles: [0xaee946, 0x00b09b], wall: wp("v9", [0xe4b2ea, 0x8376c2, 0xeab9d9, 0xb493e6], -35) },
            { key: "p103", accent: 0xd33213, bubbles: [0xf9db00, 0xd33213], wall: wp("v2", [0xfec496, 0xdd6cb9, 0x962fbf, 0x4f5bd5], -40) },
            { key: "p104", accent: 0xea8ced, bubbles: [0xea8ced, 0x00c2ed], wall: wp("v6", [0x8adbf2, 0x888dec, 0xe39fea, 0x679ced], -30) }],
    tinted: []
}
// a colour's own background by night (PresentationThemeBaseColor.colorWallpaper of each dark theme)
const NIGHT_WALLS = { cyan: wp("v5", [0xa4dbff, 0x009fdd, 0x527bdd], -30), green: wp("v3", [0x7fa381, 0xfff5c5, 0x336f55, 0xfbe37d], -20),
                      pink: wp("v9", [0xe4b2ea, 0x8376c2, 0xeab9d9, 0xb493e6], -35), orange: wp("v2", [0xfec496, 0xdd6cb9, 0x962fbf, 0x4f5bd5], -40),
                      purple: wp("v6", [0x8adbf2, 0x888dec, 0xe39fea, 0x679ced], -30), red: wp("v4", [0xe4b2ea, 0x8376c2, 0xeab9d9, 0xb493e6], -35),
                      yellow: wp("v1", [0xeaa36e, 0xf0e486, 0xf29ebf, 0xe8c06e], -30) }
const TINTED_WALLS = { blue: wp("v7", [0x1e3557, 0x182036, 0x1c4352, 0x16263a], 40), cyan: wp("v3", [0x1e3557, 0x151a36, 0x1c4352, 0x2a4541], 40),
                       green: wp("v3", [0x2d4836, 0x172b19, 0x364331, 0x103231], 40), pink: wp("v9", [0x2c0b22, 0x290020, 0x160a22, 0x3b1834], 40),
                       orange: wp("v10", [0x2c211b, 0x442917, 0x22191f, 0x3b2714], 40), purple: wp("v11", [0x3a1c3a, 0x24193c, 0x392e3e, 0x1a1632], 40),
                       red: wp("v4", [0x2c211b, 0x44332a, 0x22191f, 0x3b2d36], 40), yellow: wp("v2", [0x2c2512, 0x45360b, 0x221d08, 0x3b2f13], 40),
                       gray: wp("v6", [0x1c2731, 0x1a1c25, 0x27303b, 0x1b1b21], 40) }

// ---- colours ------------------------------------------------------------------------------------
function rgb(c) { return [((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255] }
function num(r, g, b) {
    return (Math.round(Math.min(1, Math.max(0, r)) * 255) << 16) | (Math.round(Math.min(1, Math.max(0, g)) * 255) << 8)
           | Math.round(Math.min(1, Math.max(0, b)) * 255)
}
function css(c) { return "#" + ("000000" + (c >>> 0).toString(16)).slice(-6) }
function hsb(c) {
    const [r, g, b] = rgb(c)
    const hi = Math.max(r, g, b), lo = Math.min(r, g, b), d = hi - lo
    let h = 0
    if (d > 0) {
        if (hi === r)
            h = ((g - b) / d + 6) % 6
        else if (hi === g)
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        h /= 6
    }
    return [h, hi > 0 ? d / hi : 0, hi]
}
function ofHsb(h, s, v) {
    h = (h % 1) * 6
    const i = Math.floor(h), f = h - i
    const p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    const [r, g, b] = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6]
    return num(r, g, b)
}
// UIColor.withMultiplied(hue:saturation:brightness:), each kept within 0…1
function mul(c, h, s, v) {
    const x = hsb(c)
    return ofHsb(Math.min(1, x[0] * h), Math.min(1, x[1] * s), Math.min(1, x[2] * v))
}
function lightness(c) {
    const [r, g, b] = rgb(c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
function mix(cs) {
    let r = 0, g = 0, b = 0
    for (const c of cs) {
        const x = rgb(c)
        r += x[0]; g += x[1]; b += x[2]
    }
    return num(r / cs.length, g / cs.length, b / cs.length)
}
function alpha(c, a) {
    const [r, g, b] = rgb(c)
    return Qt.rgba(r, g, b, a)
}

// ---- the accents of a base, in iOS's order: [{ key, accent, bubbles (the swatch's middle; [] none) }] ----------------
function classicBubble(accent) {
    const x = hsb(accent)
    return ofHsb(x[0], x[1] > 0 && x[2] > 0 ? 0.14 : 0, 0.79 + x[2] * 0.21)
}
function tintedBubbles(accent) {
    const bottom = mul(accent, 1.019, 0.731, 0.59)
    return [mul(bottom, 0.966, 0.61, 0.98), bottom]
}
function options(base) {
    const out = []
    const colour = (name) => {
        const c = COLORS[name]
        out.push({ key: name, accent: base === "tinted" && name === "blue" ? 0x2ea6ff : base === "night" && name === "blue" ? 0x3e88f7 : c,
                   bubbles: base === "classic" ? [classicBubble(c)] : base === "tinted" ? tintedBubbles(name === "blue" ? 0x2ea6ff : c) : [] })
    }
    let names = ORDER.slice()
    if (base === "classic")
        out.push({ key: "", accent: 0x0088ff, bubbles: [0xe1ffc7] })
    else if (base === "day" || base === "night") {
        colour("blue")
        names = names.filter((n) => n !== "blue")
    }
    for (const p of PRESETS[base] || [])
        out.push({ key: p.key, accent: p.accent, bubbles: p.bubbles })
    if (base !== "day")
        names = names.filter((n) => n !== "black")
    names = names.filter((n) => n !== (base === "night" ? "gray" : "white"))
    names.forEach(colour)
    return out
}
// the accent a base has until one is chosen
function first(base) {
    return base === "classic" ? "" : "blue"
}
// a custom colour's key is "#rrggbb" (the colour picker's); its number, or -1
function isCustom(key) {
    return typeof key === "string" && key.charAt(0) === "#"
}
function customNum(key) {
    return isCustom(key) ? parseInt(key.slice(1), 16) & 0xffffff : -1
}

// the tinted night's surfaces from its accent (customizeDefaultDarkTintedPresentationTheme's main… colours)
function tintOf(a) {
    const main = mul(a, 1.024, 0.585, 0.25), page = mul(a, 1.024, 0.573, 0.18)
    return { card: css(main), page: css(page), highlight: css(mul(a, 1.03, 0.585, 0.12)), separator: css(mul(a, 1.033, 0.426, 0.34)),
             grey: css(mul(a, 1.019, 0.109, 0.59)), field: css(mul(a, 1.029, 0.609, 0.19)), bar: alpha(main, 0.92),
             menu: alpha(main, 0.96), bubbleIn: css(main) }
}

// ---- a base and an accent as the app's colours ----------------------------------------------------------
// { base, dark, accent, out (our bubbles; "" the base's own), outLight (dark words on them), outMeta, check, control
//   ("" the base's own), bubbleIn (""), tint (the tinted night's surfaces; null), badgeText ("" white),
//   wall: { slug, colors, intensity } | { fill: [colours] } | null (the base's own) }
function look(base, key) {
    const b = BASES.find((x) => x.id === base) || BASES[0]
    const preset = (PRESETS[b.id] || []).find((p) => p.key === key) || null
    const custom = customNum(key)
    const named = COLORS[key] !== undefined ? key : ""
    const l = { base: b.id, dark: b.dark, accent: "", out: "", outLight: !b.dark, outMeta: "", check: "", control: "",
                bubbleIn: "", tint: null, badgeText: "", wall: null }
    let accent = preset ? preset.accent : custom >= 0 ? custom : named ? COLORS[named] : -1
    let bubbles = preset ? preset.bubbles.slice() : []
    let outAccent = -1

    if (b.id === "classic" || b.id === "day") {
        const day = b.id === "day"
        if (day && accent < 0)
            accent = COLORS.blue
        if (!bubbles.length) {
            if (day)
                bubbles = [mul(accent, 0.966, 0.61, 0.98), accent]
            else if (accent >= 0) {
                bubbles = [classicBubble(accent)]
                const x = hsb(accent)
                outAccent = lightness(accent) > 0.705 ? ofHsb(x[0], Math.min(1, x[1] * 1.1), Math.min(x[2], 0.6)) : accent
                l.wall = { fill: [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884] }
            }
        }
        if (accent >= 0 && lightness(accent) > 0.705) {
            const x = hsb(accent)
            accent = ofHsb(x[0], Math.min(1, x[1] * 1.1), Math.min(x[2], 0.6))
        }
        if (bubbles.length) {
            const m = mix(bubbles)
            l.out = css(m)
            l.outLight = lightness(m) > 0.705
            if (l.outLight) {
                if (outAccent >= 0) {
                    l.outMeta = alpha(outAccent, 1)
                    l.check = css(outAccent)
                    l.control = css(outAccent)
                } else {
                    l.outMeta = alpha(mul(bubbles[0], 1.344 * 0.75, 4.554 * 1.1, 0.549), 0.8)
                    l.check = alpha(mul(m, 1.344 * 0.75, 4.554 * 1.1, 0.549), 0.8)
                    l.control = css(mul(m, 1.283 * 0.75, 3.176, 0.765))
                }
            }
        }
        if (day) {
            l.bubbleIn = "#f1f1f4"
            l.wall = { fill: [0xffffff] }
        }
        if (preset && preset.wall)
            l.wall = preset.wall
    } else if (b.id === "night") {
        if (accent < 0)
            return l                    // (the night as it is: Telegram-iOS's own blue)
        const white = accent === 0xffffff
        if (!bubbles.length)
            bubbles = white ? [0x313131] : named === "blue" ? [0xa256bf, 0x9047ff, 0x0771ff] : [mul(accent, 0.966, 0.61, 0.98), accent]
        if (named === "blue")
            accent = 0x3e88f7
        if (white)
            l.badgeText = "#000000"
        else if (lightness(accent) > 0.735)
            l.badgeText = "#000000"
        else {
            const x = hsb(accent)
            accent = ofHsb(x[0], x[1], Math.max(x[2], 0.55))
        }
        const m = mix(bubbles)
        l.out = css(m)
        l.outLight = lightness(m) > 0.705
        l.wall = preset ? preset.wall : NIGHT_WALLS[named] || null
    } else {
        if (accent < 0 || named === "blue")
            accent = 0x2ea6ff
        const x = hsb(accent)
        const a = ofHsb(x[0], x[1], Math.max(x[2], 0.18))
        bubbles = tintedBubbles(accent)
        const m = mix(bubbles)
        l.out = css(m)
        l.outLight = lightness(m) > 0.6
        l.tint = tintOf(a)
        if (lightness(a) > 0.7)
            l.badgeText = "#000000"
        l.wall = TINTED_WALLS[custom >= 0 ? "" : named || "blue"] || { fill: [mul(a, 1.024, 0.573, 0.18)] }
        accent = a
    }
    l.accent = accent >= 0 ? css(accent) : ""
    return l
}
