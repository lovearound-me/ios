# Love Around for iPhone and Apple Watch

Tap a circle on your phone or your wrist, and someone you're thinking of gets
a bare "someone is thinking of you": no name, no message. When someone thinks
of you, the screen edges glow in your color and hearts, cats and flowers
float up. You never learn who it was.

Status: version 1.0, on its way to the App Store. The iPhone app gets
signals while it is open (the server's WebSocket, as the Mac app) and by
Apple push in the background. watchOS doesn't let ordinary apps keep a
WebSocket open ([TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)),
so the watch app gets hearts only as its own push notifications, sent to it
straight from the server: it works without the iPhone app, and with the
iPhone's receiving off.

## The iPhone app

- **Sign in**, all of it in the app: Apple's button; Google's own sign-in
  library (GoogleSignIn: Google's account chooser over the app, its ID token
  traded for a Firebase session; the client is the iPhone app's in Firebase,
  `GIDClientID` in Info.plist); or an email and a password in a form that
  signs in or makes the account, with «Забыли пароль?», as on the site. One
  account per email: an email whose account was made another way is told to
  sign in that way. The app keeps the Firebase refresh token in the Keychain.
- **Notifications** are asked for once after signing in, after a screen of
  ours that says what they are for; «Не сейчас» leaves it to Settings.
- **«Сердечки»** (variant Б of the mockups): a big heart for «Кому-нибудь на
  свете» (once an hour), the close people in circles three to a row, then
  «Вся книга». A tap sends.
- **«Книга»**: «Рядом» in its order (drag to change it), the others; a
  person's card: name, color, «Рядом», their Love ID, removing. «+» adds by
  a Love ID link, also from `lovearound://add/<code>`.
- **«Игрушки»**: the account's devices; connect one by the six digits on its
  screen (a watch, a lamp), or make a token for a board of one's own. The
  tab reads "Devices" in every language but Russian.
- **«Настройки»**: my color, hearts from anyone, pause, my Love ID, how the
  account signs in, sign out, delete the account (an account that signs in
  with Apple confirms with Apple once more, and Apple forgets the app too:
  `AppleSignIn.revoke`), help and privacy pages. The site's pages open over
  the app (`SFSafariViewController`), not in Safari.

## The watch app

## What it does

- **Sign in** with «Войти через Apple», or «Войти по коду»: the watch shows a QR
  code and six digits; the iPhone camera opens
  `lovearound.me/login/devices#<code>`, or the digits go in by hand on a
  computer. Whoever confirms the code there gets the watch on their account.
  The code lives 10 minutes and works once (API: `POST /v1/pairing`).
- Apple with an email that already has an account (made with Google or a
  password) can't sign in on the watch: it offers the code instead.
- Either way the watch ends up with a **device token**, kept in the Keychain.
  It shows among the account's devices, and removing it there signs the
  watch out; «Выйти» on the watch removes it from there too
  (`DELETE /v1/devices/self`). The watch never holds the account's own
  sign-in.
- **The main screen**, as Settings → «Вид» says: «Соты» (the default,
  bubbles packed like the watch's own app screen, smaller towards the
  edges), «Кружочки» (like the Mac menu), «Кружочки с именами», «Список».
  «Кому-нибудь на свете» first, then the close people, then everyone else.
  A tap sends; a held finger shows the whole name, letting go sends, sliding
  away cancels.
- **«Вибрация»**: taps per heart, 0–5, three by default (on the watch and in
  the iPhone's «Уведомление»). With the app in front it plays them all; on a
  sleeping watch watchOS taps once and the long look plays the rest. None:
  the watch registers with `silent` and the server sends it passive
  notifications without sound; the iPhone's extension drops the sound.
- **A heart for me** comes as the watch's own notification
  (`PUT /v1/devices/self/push`), on the watch's terms: its «Получать
  сердечки» (the same switch as «Принимает» in its card on the phone), its
  quiet hours and «кто-нибудь на свете» from that card. The phone's switch,
  pause and quiet hours don't touch it. The notification's long look glows in
  my color (`WKNotificationScene`, category `signal`); with the app in front,
  the whole screen glows and emoji float up. Where the iPhone takes the heart
  too, the wrist shows it once: both carry the same `apns-collapse-id`.
- **Settings**: «Получать сердечки», «Как светится» (my color, and «Показать»
  to try it), the account, sign out, delete the account (App Store rule;
  confirmed with a fresh Apple sign-in, which also lets Apple forget the app).

API docs: [lovearound.me/docs](https://lovearound.me/docs).

## Layout

| Folder | What |
|---|---|
| `Shared/` | For both apps: contacts, Keychain, Apple sign-in through Firebase's REST API (no Firebase SDK), palette, strings, the app mark |
| `Phone/` | The iPhone app (SwiftUI, iOS 17+): Firebase sign-in (Apple, Google, email), the API and WebSocket clients ported from the Mac app, `Demo.swift` for screenshots |
| `Watch/` | The watch app (SwiftUI, watchOS 10+), its device-token API client, `Demo.swift` |
| `PhoneUITests/`, `WatchUITests/` | UI tests: on made-up data (CI) and against the server (on a Mac) |
| `i18n/` | One dictionary per language, keyed by the Russian text, for both apps |
| `*/Assets.xcassets` | The icon, drawn by `scripts/make-icon.py` (the Mac and Linux icon's gradient and heart, full-bleed: watchOS cuts it to a circle, iOS rounds it) |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec: the `.xcodeproj` is generated, not kept |

Bundle ids: the iPhone app `me.lovearound.ios`, the watch app
`me.lovearound.ios.watchkitapp`, which travels inside it (one App Store
record) and also runs without an iPhone app installed. The QR
code comes from [swift-qrcode-generator](https://github.com/fwcd/swift-qrcode-generator)
(watchOS has no Core Image QR filter).

## Build

On a Mac with Xcode 16+:

    brew install xcodegen
    xcodegen generate
    open LoveAround.xcodeproj

GitHub Actions (`.github/workflows/build.yml`) builds both apps for the
simulator on every push, runs the UI tests on made-up data and takes a
screenshot of every screen in Russian and English (artifact `screenshots`).
Locally, the iPhone app (the scheme `LoveAround` builds the watch app inside
it; `LoveAroundWatch` builds the watch app alone):

    xcodebuild -project LoveAround.xcodeproj -scheme LoveAround \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    scripts/screenshots.sh build/Build/Products/Debug-iphonesimulator/LoveAround.app shots/phone
    scripts/screenshots.sh build/Build/Products/Debug-watchsimulator/LoveAround.app shots/watch

UI tests tap through the apps in a simulator. `PhoneDemoUITests` and
`DemoUITests` (made-up data) run in CI. On a Mac only, against the real
server (see the files for how): `PhoneLiveUITests` opens the test account
with a one-hour ID token, sends one heart and signs out; `LiveUITests` signs
the watch in by code, sends one heart and signs out.

    xcodebuild test -project LoveAround.xcodeproj -scheme LoveAround \
      -destination 'platform=iOS Simulator,name=<an iPhone>' \
      -only-testing:LoveAroundUITests/PhoneDemoUITests
    xcodebuild test -project LoveAround.xcodeproj -scheme LoveAroundWatch \
      -destination 'platform=watchOS Simulator,name=<a watch>' \
      -only-testing:LoveAroundWatchUITests/DemoUITests

`--demo <name>` draws one screen from made-up data, without signing in. On
the iPhone: `signin notifyIntro home sent anyone empty signal paused book
contact add toys board pair settings`; on the watch: `signin exists code
expired computer connected hive circles named list peek sent anyone empty signal notification
settings layout vibration glow delete`.
Made-up people have Russian names in Russian and English ones elsewhere.

## Translations

The site's 13 languages. The key is the Russian text in the code,
`tr("Книга")`, so there is no `ru.json`; `{site}`-style placeholders are
kept as is. Texts shared with the Mac and web apps are taken from their
dictionaries, so the same thing reads the same everywhere: «Кому-нибудь на
свете» = "Someone out there", informal "you".

    python3 scripts/check-i18n.py   # missing, unused and broken entries

## Privacy

A signal carries no sender. The apps send only what the API needs. The
iPhone keeps the account's Firebase refresh token in its Keychain, and my
color, the pause and when it last sent to whom in `UserDefaults`; the watch
keeps its device token and the account's email, and my color. The server
keeps Apple's push token of each (hashed as the key, the token itself to
send). Nothing else. Each bundle
says so in its `PrivacyInfo.xcprivacy`. See [lovearound.me/privacy](https://lovearound.me/privacy).

## License

MIT
