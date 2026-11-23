// Money as Telegram gives it (minor units of a currency) written for people: «29,99 US$», «269 990 so'm».
.pragma library

const ZERO = ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF", "PYG"]
const WHOLE = ["UZS", "KZT"]
const SIGN = { USD: "US$", EUR: "€", RUB: "₽", GBP: "£", UZS: "so'm", KZT: "₸" }

function group(n, sep) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, sep)
}

function money(amount, currency, en) {
    const zero = ZERO.indexOf(currency) >= 0
    const v = zero ? amount : amount / 100
    const whole = zero || WHOLE.indexOf(currency) >= 0 || v % 1 === 0 || v >= 1000
    const sep = en ? "," : " "
    let s
    if (whole)
        s = group(Math.floor(v), sep)
    else {
        const fixed = v.toFixed(2).split(".")
        s = group(fixed[0], sep) + (en ? "." : ",") + fixed[1]
    }
    return s + " " + (SIGN[currency] || currency)
}
