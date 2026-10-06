# Zen (Flutter)

The native Android version of Zen. It works fully offline: all data stays on the phone, sounds are bundled
in the app, and the release build does not even request internet permission.

## Focus mode

The **Focus** tab keeps you off your phone for a set time (15 minutes to 2 hours):

- **Lock phone to Zen:** uses Android's app pinning. After you confirm Android's prompt, Home, Recents and
  notifications are blocked until the timer ends.
- **Silence notifications:** turns on Do Not Disturb (priority only) and restores your previous setting after.
  Android asks you to allow this once.
- **No stop button.** A session ends only when its timer runs out. Back is ignored.

Android always lets the person holding the phone unpin an app (hold Back and Recents), and no ordinary app
can remove that. Turn on *Ask for PIN before unpinning* in the phone's App pinning settings to make it harder.

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
| `lib/focus_lock.dart` | Bridge to Android app pinning and Do Not Disturb (`MainActivity.kt`) |
| `lib/sound.dart` | Bell and ambient sound playback |
| `assets/sounds/` | Bundled bell and ambient audio |
| `test/` | Unit and widget tests |
