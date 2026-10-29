# Pen Me In (project `penmein`)

One Flutter app for Android and iPhone, from the house of Arwee (sister app: Save This Spot,
`C:\dev\pinnocate`, same Midnight Gold look and Arwee logo rules). Both platforms must stay identical
for the user. Repo: https://github.com/arwee444/penmein (private, branch `main`) once created.

## User's standing rule
Every change the user asks for (UI, app icon, features, fixes) applies to **both Android and iOS**, unless the
user clearly says it is for one platform only. Never ship a change to one platform alone; if something can't
be done the same way on the other, say so and do the closest equivalent.

## Every session
1. `git pull` before changing anything.
2. When done: `flutter analyze` clean, `flutter test` passing, then commit and `git push` to `main`.
3. Tell the user the other computer must pull (PC = Windows, app changes + Android builds;
   Mac = iPhone builds + iOS-only native code).

## Keeping Android and iOS the same
- `lib/` and `assets/` are shared: change once, both platforms get it.
- Per-platform files — when one changes, change the other in the same commit:

  | What | Android | iOS |
  |---|---|---|
  | App name | `android/app/src/main/AndroidManifest.xml` `android:label` | `ios/Runner/Info.plist` `CFBundleDisplayName` |
  | Permissions | `AndroidManifest.xml` `<uses-permission>` | `Info.plist` `NS…UsageDescription` (honest wording) |
  | App icon | `android/app/src/main/res/mipmap-*` | `ios/Runner/Assets.xcassets/AppIcon.appiconset` (both from `NibPainter`, `test/render_icons_test.dart`) |
  | Native launch screen | `res/drawable*/launch_background.xml` | `ios/Runner/Base.lproj/LaunchScreen.storyboard` |

- Platform-only features are guarded with `ListenController.isSupported` (Android only): background listening
  (foreground service + offline Vosk wake phrase), speech models, beeps, battery. The iOS counterpart is the
  Siri App Intent `ios/Runner/PenNoteIntent.swift` writing the same `inbox.jsonl` format
  (`{"id","text","t"}`, read by `NoteInbox` in `lib/data/notes.dart`); in-app dictation on iOS is
  `lib/services/ios_dictation.dart`. A change to the inbox format must be made on both sides.
- New plugin: check it supports both android and ios; add any Info.plist keys it needs.
- Bump `version:` in `pubspec.yaml` for each release; it sets both platforms' version numbers.
- Never change `com.arwee.penmein` (Android applicationId / iOS bundle id) or the Android signing.

## Builds
- Android (PC, PowerShell): `$env:JAVA_HOME='C:\dev\jdk17'; $env:ANDROID_HOME='C:\dev\android-sdk';
  $env:PATH="C:\dev\jdk17\bin;C:\dev\flutter\bin;C:\dev\mingit\cmd;$env:PATH"` then
  `flutter build apk --release --split-per-abi --target-platform android-arm64` (code shrinking stays off:
  R8 breaks Vosk/JNA). Git push on the PC needs `$env:GIT_TERMINAL_PROMPT='1'`.
- iOS (Mac): `flutter pub get && cd ios && pod install`, then `flutter run --release` on the iPhone.
  Details: `docs/IOS_HANDOFF.md`.
- Screenshots without a phone: `SHOTS=<dir> flutter test test/render_screens_test.dart`.
