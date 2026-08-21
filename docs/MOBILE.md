# Building the mobile app (Android)

GymFLOSS ships in two flavors from the same codebase:

| | **Self-hosted** (this repo's default) | **Mobile app** (`VITE_MOBILE=1`) |
|---|---|---|
| Runs | in any browser, against your own server | natively on Android (Capacitor shell) |
| Accounts | passkey sign-in, one profile per person | none — the phone *is* the account |
| Data | synced to your server, readable on desktop | stays on the device (file in the app's private storage) |
| Reminders | Web Push from your server | native local notifications, no server involved |
| Exercise media | served by your server (`img/`, `gif/`) | loaded from the jsDelivr CDN |

The mobile flavor never talks to a backend: no sign-in screen, no sync, no telemetry.
State is mirrored from `localStorage` into `gymfloss-state.json` in the app's private data
directory on every change (the system is allowed to evict WebView storage under pressure —
the file mirror is the durable copy and is restored on launch). Backups go out through the
OS share sheet instead of a browser download.

## Prerequisites

- Node 22.12+ (24 recommended)
- **Android:** Android Studio (bundles the SDK). Java 21 for Gradle.

## Build & run

```sh
cd frontend
npm install
npm run build:mobile:android   # VITE_MOBILE build + `cap sync android`

npx cap open android           # opens Android Studio → run on emulator or device
```

`npm run build:mobile:android` bakes the CDN media base into the bundle and copies the web
build into the native project — re-run it after every web-code change before building natively.

> **Heads-up:** after `build:mobile:android`, `frontend/dist` contains the *mobile* bundle.
> Run a plain `npm run build` again before deploying `dist` to a server.

## App icons & splash screens

`frontend/resources/icon.svg` is the 1024×1024 source (the app's dumbbell glyph on the
app background). Generate all platform assets from it on a machine with the tooling:

```sh
cd frontend
npx @capacitor/assets generate --iconBackgroundColor '#0c0e12' --splashBackgroundColor '#0c0e12'
```

(If the generator won't take the SVG directly, export it to `resources/icon.png` at
1024×1024 first — any image tool can do it.)

## Distribution — deliberately no app stores

GymFLOSS's mobile app is not on the Play Store or App Store, and that's a choice: no store
accounts, no store rules, no yearly fees between you and an open-source app.

### Android — sideload the APK

Each release attaches a signed APK — grab it from the
[latest release](https://github.com/mjryan253/GymFLOSS/releases/latest), or build your own below.
Android asks you to allow installs from outside the Play Store the first time — standard for any
app that isn't in it.

The easy way: run **`./build-apk.sh`** from the repo root. It fetches the Android SDK and
Node if they're missing, builds, and signs with a keystore it generates into `.signing/`
(gitignored — back that directory up). The output lands at the repo root as
`GymFLOSS-<version>.apk`.

What the script does, by hand:

```sh
cd frontend && npm run build:mobile:android
cd android && ./gradlew assembleRelease            # → app/build/outputs/apk/release/app-release-unsigned.apk

# one-time: create a keystore. KEEP IT — updates must be signed with the same key,
# or Android refuses to install the new version over the old one.
keytool -genkeypair -keystore my.keystore -alias gymfloss -keyalg RSA -validity 10950

# align + sign (zipalign/apksigner ship with the Android SDK build-tools)
zipalign -f -p 4 app-release-unsigned.apk aligned.apk
apksigner sign --ks my.keystore --ks-key-alias gymfloss --out GymFLOSS.apk aligned.apk
```

### iPhone — what's actually possible

Apple does not allow installing apps outside the App Store, so there is no `.ipa` download
that would simply install. Self-host and add the app to your home screen instead: open your
instance in Safari → **Share** → *Add to Home Screen*. You get a full-screen app with its own
icon, passkey sign-in and sync, and it never expires.

This repo no longer ships an Xcode project, so free signing and AltStore aren't options here.
The PWA is the supported route on iPhone, and the better one regardless — nothing to re-sign
every seven days, and you keep sync and passkeys.

### Release notes for maintainers

- Bump `versionName`/`versionCode` in `android/app/build.gradle` per release; keep them in
  step with `frontend/package.json`. `versionCode` must strictly increase or updates won't
  install over an existing APK.
- **License:** GymFLOSS is AGPL-3.0, which by itself sits badly with app-store terms of
  service. `NOTICE.md` carries an app-store exception (an additional permission under
  AGPL §7) granted by the copyright holder — relevant only if store distribution ever happens.
- The app requests notification permission only when the workout-day reminder is switched
  on, and (on Android) declares `SCHEDULE_EXACT_ALARM` so the reminder fires to the minute
  where the user allows it.
