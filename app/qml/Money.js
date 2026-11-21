// Money as Telegram gives it (minor units of a currency) written for people: «29,99 US$», «12 000 so'm».
.pragma library

const ZERO = ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF", "PYG"]
const SIGN = { USD: "US$", EUR: "€", RUB: "₽", GBP: "£", UZS: "so'm", KZT: "₸" }

function money(amount, currency, en) {
    const zero = ZERO.indexOf(currency) >= 0
    const v = zero ? amount : amount / 100
    const s = v.toLocaleString(Qt.locale(en ? "en_US" : "uz_UZ"), "f", zero || v % 1 === 0 ? 0 : 2)
    return s + " " + (SIGN[currency] || currency)
}
