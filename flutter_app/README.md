# Zen (Flutter)

The native Android version of Zen. It works fully offline: all data stays on the phone, sounds are bundled
in the app, and the release build does not even request internet permission.

## Focus mode

The **Focus** tab keeps you off your phone. There is no stop button: a session ends only when its time is up,
and Back is ignored.

**With the app blocker (recommended).** Turn it on once from the Focus tab (Android Settings → Accessibility →
Zen focus blocker). Then:

- **Allowed apps:** pick up to 5 apps that keep working during focus (WhatsApp and Google Pay are suggested).
  Phone and incoming calls are always allowed. Opening any other app sends you back to Zen.
- **Schedules:** repeating blocks such as *Weekdays 9:00–11:00* or overnight *11:00 PM–7:00 AM*. They start by
  themselves, even when Zen is closed.
- Settings can't be changed while a session is running.

The blocker only checks which app is in front (its package name); it never reads screen content, and nothing
leaves the phone. On Android 13+, sideloaded apps need one extra step before Accessibility can be switched on:
Zen's App info → ⋮ → *Allow restricted settings*.

Limits: if an allowed app opens a different app (for example a browser for a payment), that app is blocked
unless it is also allowed. Restarting in Android's safe mode turns all accessibility services off.

**Without the blocker,** Focus falls back to Android app pinning: the phone stays on Zen until the timer ends
(no allowed apps or schedules). Android always lets you unpin by holding Back and Recents; turn on
*Ask for PIN before unpinning* in the App pinning settings to make that harder.

**Silence notifications** turns on Do Not Disturb (priority only) for sessions you start, and restores your
previous setting afterwards. Android asks you to allow this once.

## Get the APK

Every push that touches `flutter_app/` builds an APK with GitHub Actions
([`.github/workflows/android-apk.yml`](../.github/workflows/android-apk.yml)) and publishes it on the
repository's **Releases** page. Open the latest release on your phone, download the `.apk`, and allow
installing from your browser when Android asks.

### Keep your data when updating

Android only installs a new version over an old one if both are signed with the same key. Until you add
your own key, each build is signed with a different throwaway key, so you must uninstall (losing your
journal and stats) before installing a newer build. To fix that once:

```sh
keytool -genkeypair -v -keystore zen.jks -alias zen -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 zen.jks   # copy the output
```

Add these repository secrets (Settings → Secrets and variables → Actions):
`ANDROID_KEYSTORE_BASE64` (the base64 output), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`zen`),
`ANDROID_KEY_PASSWORD`. Keep `zen.jks` and the passwords safe and never commit them.

## Develop locally

Needs the Flutter SDK and Android SDK.

```sh
flutter pub get
flutter test
flutter run            # on a connected phone or emulator
flutter build apk      # build/app/outputs/flutter-apk/app-release.apk
```

## Layout

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App entry, theme and tab navigation |
| `lib/store.dart` | Sessions, journal and settings saved on the device |
| `lib/screens/` | Today, Breathe, Meditate, Focus and Journal screens |
| `lib/focus_lock.dart` | Bridge to the Android side of Focus (`MainActivity.kt`) |
| `lib/focus_config.dart` | Allowed apps and schedules |
| `android/app/src/main/kotlin/` | App blocker service, schedule rules, pinning and Do Not Disturb |
| `lib/sound.dart` | Bell and ambient sound playback |
| `assets/sounds/` | Bundled bell and ambient audio |
| `test/` | Flutter unit and widget tests |
| `android/app/src/test/` | Tests for the schedule rules (`./gradlew :app:testDebugUnitTest`) |
