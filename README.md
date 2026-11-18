# Love Around for Apple Watch (and, later, iPhone)

Tap a circle on your wrist, and someone you're thinking of gets a bare
"someone is thinking of you": no name, no message. When someone thinks of you,
the watch taps your wrist, the screen edges glow in your color and hearts,
cats and flowers float up. You never learn who it was.

Status: being built, not in the App Store yet. Receiving signals still needs
Apple push on the server: watchOS doesn't let ordinary apps keep a WebSocket
open ([TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)).

## What it does

- **Sign in** with «Войти через Apple», or «Войти по коду»: the watch shows a QR
  code and six digits; the iPhone camera opens
  `lovearound.me/login/devices#<code>`, or the digits go in by hand on a
  computer. Whoever confirms the code there gets the watch on their account.
  The code lives 10 minutes and works once (API: `POST /v1/pairing`).
- Apple with an email that already has an account (made with Google or a
  password) can't sign in on the watch: it offers the code instead.
- Either way the watch ends up with a **device token**, kept in the Keychain.
  It shows in «Устройства» on app.lovearound.me, and removing it there signs
  the watch out. The watch never holds the account's own sign-in.
- **The main screen** is circles, like the Mac menu: «Кому-нибудь на свете»
  first, then the close people, then everyone else. A tap sends.
- **Settings**: my color (stays on this watch), the account, sign out,
  delete the account (App Store rule; confirmed with a fresh Apple sign-in).

API docs: [lovearound.me/docs](https://lovearound.me/docs).

## Layout

| Folder | What |
|---|---|
| `Shared/` | API client, Keychain, Apple sign-in through Firebase's REST API (no Firebase SDK), palette, strings. For the iPhone app too. |
| `Watch/` | The watch app (SwiftUI, watchOS 10+), `Demo.swift` for screenshots |
| `i18n/` | One dictionary per language, keyed by the Russian text |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec: the `.xcodeproj` is generated, not kept |

Bundle id `me.lovearound.ios.watchkitapp`, a watch-only app for now; the
iPhone app will be `me.lovearound.ios`, with the watch app under it. The QR
code comes from [swift-qrcode-generator](https://github.com/fwcd/swift-qrcode-generator)
(watchOS has no Core Image QR filter).

## Build

On a Mac with Xcode 16+:

    brew install xcodegen
    xcodegen generate
    open LoveAround.xcodeproj

GitHub Actions (`.github/workflows/build.yml`) builds for the simulator on
every push and takes a screenshot of every screen in Russian and English
(artifact `screenshots`). Locally:

    xcodebuild -project LoveAround.xcodeproj -scheme LoveAroundWatch \
      -destination 'generic/platform=watchOS Simulator' \
      -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    scripts/screenshots.sh build/Build/Products/Debug-watchsimulator/LoveAround.app shots

`--demo <name>` draws one screen from made-up data, without signing in:
`signin exists code expired computer connected circles sent anyone empty
signal settings colors delete`.

## Translations

The site's 13 languages. The key is the Russian text in the code,
`tr("Мой цвет")`, so there is no `ru.json`; `{site}`-style placeholders are
kept as is. Texts shared with the Mac and web apps are taken from their
dictionaries, so the same thing reads the same everywhere: «Кому-нибудь на
свете» = "Someone out there", informal "you".

    python3 scripts/check-i18n.py   # missing, unused and broken entries

## Privacy

A signal carries no sender. The app sends only what the API needs; it keeps
the device token and the account's email on the watch, my color in
`UserDefaults`, and nothing else. See [lovearound.me/privacy](https://lovearound.me/privacy).

## License

MIT
