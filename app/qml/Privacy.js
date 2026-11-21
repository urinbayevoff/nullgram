// TDLib's userPrivacySettingRules read and made as Telegram-iOS's SelectivePrivacySettings: a base (0 everybody,
// 1 my contacts, 2 nobody) and its exceptions — users and groups always let in, users and groups never.
.pragma library

const ALL = "userPrivacySettingRuleAllowAll", CONTACTS = "userPrivacySettingRuleAllowContacts",
      NONE = "userPrivacySettingRuleRestrictAll"

function read(rules) {
    const r = { base: 2, allowUsers: [], allowChats: [], denyUsers: [], denyChats: [] }
    let based = false
    for (const x of (rules && rules.rules) || []) {
        const t = x["@type"]
        if (!based && (t === ALL || t === CONTACTS || t === NONE)) {
            r.base = t === ALL ? 0 : t === CONTACTS ? 1 : 2
            based = true                // (TDLib goes in order: the first base decides)
        } else if (t === "userPrivacySettingRuleAllowUsers")
            r.allowUsers = r.allowUsers.concat(x.user_ids)
        else if (t === "userPrivacySettingRuleAllowChatMembers")
            r.allowChats = r.allowChats.concat(x.chat_ids)
        else if (t === "userPrivacySettingRuleRestrictUsers")
            r.denyUsers = r.denyUsers.concat(x.user_ids)
        else if (t === "userPrivacySettingRuleRestrictChatMembers")
            r.denyChats = r.denyChats.concat(x.chat_ids)
    }
    return r
}

// back to rules: the exceptions first, then the base (an «always» list means nothing under «everybody», and
// a «never» one nothing under «nobody» — left out, as iOS does)
function make(r) {
    const l = []
    if (r.base !== 0) {
        if (r.allowUsers.length)
            l.push({ "@type": "userPrivacySettingRuleAllowUsers", user_ids: r.allowUsers })
        if (r.allowChats.length)
            l.push({ "@type": "userPrivacySettingRuleAllowChatMembers", chat_ids: r.allowChats })
    }
    if (r.base !== 2) {
        if (r.denyUsers.length)
            l.push({ "@type": "userPrivacySettingRuleRestrictUsers", user_ids: r.denyUsers })
        if (r.denyChats.length)
            l.push({ "@type": "userPrivacySettingRuleRestrictChatMembers", chat_ids: r.denyChats })
    }
    l.push({ "@type": r.base === 0 ? ALL : r.base === 1 ? CONTACTS : NONE })
    return { "@type": "userPrivacySettingRules", rules: l }
}

// how many let in and kept out beyond the base (iOS's «Everybody (-2)», «My Contacts (-1, +3)», «Nobody (+4)»)
function counts(r) {
    return { plus: r.base === 0 ? 0 : r.allowUsers.length + r.allowChats.length,
             minus: r.base === 2 ? 0 : r.denyUsers.length + r.denyChats.length }
}
