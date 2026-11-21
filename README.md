# Nullgram

An **unofficial** Telegram client for [ztOS](https://ztos.online) phones (Arch Linux ARM + the ztMETRO
shell), made with Qt Quick and [TDLib](https://github.com/tdlib/td). It is not made by Telegram.

*O'zbekcha pastda.*

> ⚠ **Apple emoji are not included.** If you want Apple emoji, download them separately (see
> [Apple emoji](#apple-emoji)). Without them Nullgram uses the system's emoji font.
>
> ⚠ **Apple emojisi paket ichida emas.** Apple emojisini ishlatmoqchi bo'lsangiz, uni alohida yuklab
> olasiz ([Apple emoji](#apple-emoji)). Busiz Nullgram tizimdagi emoji shriftini ishlatadi.

## Install

On a ztOS phone (aarch64), add Nullgram's package repository once, to `/etc/pacman.conf`:

```ini
[nullgram]
SigLevel = Optional TrustAll
Server = https://github.com/urinbayevoff/nullgram/releases/download/repo
```

then:

```sh
sudo pacman -Sy nullgram
```

Updates come with `sudo pacman -Syu`. Nullgram appears in the app list; its data stays in
`~/.local/share/ztos/data/uz.omonullos.nullgram`.

Two packages are installed: `nullgram` (the app, Python + QML) and `nullgram-tdlib` (TDLib 1.8.68 in
`/usr/lib/nullgram`, with OpenSSL linked in, so it works on phones with OpenSSL 3 and with 4).

## Telegram API key

Every Telegram client needs an API key (`api_id`, `api_hash`). Nullgram's packages come with one. If Telegram
ever blocks it, or a build comes without one, enter your own from [my.telegram.org](https://my.telegram.org)
→ *API development tools*: Settings → Ma'lumotlar va xotira (Data and storage) → API kaliti (API key).

## Apple emoji

Apple's emoji pictures are Apple's, so they are not in the package. If you want them, download them
yourself, at your own wish: in the app, **Settings → Ko'rinish (Appearance) → Emoji → Apple emojisini yuklab
olish**. It shows how far it is (share, megabytes, speed, time left) and goes on in the background even when
Nullgram is closed; stopped, it goes on where it was. Or from a terminal:

```sh
python3 /usr/share/nullgram/emoji_get.py            # download (or go on)
python3 /usr/share/nullgram/emoji_get.py --remove   # delete the set
```

The set (~85 MB, 3,783 pictures) is [iamcal/emoji-data](https://github.com/iamcal/emoji-data)'s
`img-apple-160` (tag v16.0.0, through the jsDelivr CDN) with an `emoji-map.json`, in `~/.cache/nullgram-emoji/`.
Without it Nullgram uses the system's emoji font. **Apple emojisi:** Sozlamalar → Ko'rinish → Emoji →
«Apple emojisini yuklab olish» (o'z xohishingiz bilan; fonda yuklanadi, qancha qolgani ko'rinib turadi).

## Build

```sh
cd packaging/arch/nullgram-tdlib && makepkg -si     # heavy: TDLib wants ~4 GB of memory
cd ../nullgram && NULLGRAM_SRC=$PWD/../../.. makepkg -si
```

Set `NULLGRAM_API_ID` and `NULLGRAM_API_HASH` while building `nullgram` to put a key in the package.
GitHub Actions builds both for aarch64 (`.github/workflows/build.yml`) and publishes the pacman repository
on the `repo` release.

## O'zbekcha

**Nullgram** — ztOS telefonlari uchun **norasmiy** Telegram ilovasi (Qt Quick + TDLib). Telegram tomonidan
qilinmagan.

**O'rnatish:** `/etc/pacman.conf` faylining oxiriga yuqoridagi `[nullgram]` bo'limini bir marta qo'shing,
keyin `sudo pacman -Sy nullgram`. Yangilanishlar `sudo pacman -Syu` bilan keladi.

**API kaliti:** ilova o'z kaliti bilan keladi. Telegram uni bloklasa, my.telegram.org'dan o'z kalitingizni
oling va Sozlamalar → Ma'lumotlar va xotira → API kaliti sahifasiga yozing.

## Licence

GNU GPL version 2 or (at your option) any later version: [LICENSE](LICENSE). Third-party parts (Telegram-iOS's
animations and icons, TDLib, OpenSSL) are listed in [NOTICE](NOTICE).
