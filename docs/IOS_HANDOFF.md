# Pen Me In on iPhone — handoff for the Mac session

Prepared on Windows (2026-10-29). Nothing here has been compiled for iOS yet; the Mac session does that.
Target: iPhone 17 (iOS 26), built on a MacBook Air M3 with Xcode. Same approach as Save This Spot
(`arwee444/pinnocate`, see its `docs/IOS_HANDOFF.md` for what worked there).

## What is already done (on Windows)

- `ios/` created with `flutter create --platforms ios` (bundle id `com.arwee.penmein`, tests
  `com.arwee.penmein.RunnerTests`, deployment target iOS 15.0 in `Runner.xcodeproj` and `ios/Podfile`).
- `ios/Runner/Info.plist`: display name "Pen Me In"; `NSMicrophoneUsageDescription` and
  `NSSpeechRecognitionUsageDescription` (in-app dictation). No other permissions are used on iOS.
- Native launch screen background = app navy `#0B1426` (`Base.lproj/LaunchScreen.storyboard`).
- App icon: all sizes in `Assets.xcassets/AppIcon.appiconset`, rendered from the same `NibPainter` as the
  Android icon (`test/render_icons_test.dart` → `build/ios_icon_1024.png`), 24-bit PNG without alpha.
- **Siri / Action Button: `ios/Runner/PenNoteIntent.swift`** (written on Windows, *not compiled yet*), already
  added to the Runner target in `project.pbxproj`. Mirrors Save This Spot's `SaveSpotIntent`:
  - "Hey Siri, Pen Me In" (also "Take a note in / New note in / Write down in Pen Me In") → Siri asks
    "What should I write down?" → the dictated text is appended to `Application Support/inbox.jsonl` as
    `{"id": "<uuid>", "text": "...", "t": "<ISO-8601>"}` — the exact format Android's listening service writes
    and `NoteInbox.take()` (lib/data/notes.dart) reads. The app imports it on launch/resume (lib/main.dart).
  - `openAppWhenRun = false`, no App Group (free-account variant, as in Save This Spot).
- Android-only features hidden on iOS (`ListenController.isSupported` = Android only):
  - Background listening (foreground service + Vosk): the Home switch card is replaced by a "Hands-free with
    Siri" card; Settings hides wake phrases, speech models, beep/vibrate and battery, and shows a Siri section;
    first run asks only for mic + speech and explains Siri.
  - `packages/vosk_listener` declares only `android`, so it is not registered on iOS and `pod install` ignores it.
  - `flutter_foreground_task`: only `initCommunicationPort()` / `getData` / `saveData` run on iOS (Dart +
    shared_preferences); the service is never started.
- In-app mic button on iOS: `lib/services/ios_dictation.dart` uses `speech_to_text` (Apple's recogniser) with
  the same note rules (pause, "done"/"cancel note", length limit via `NoteSession`).
- `flutter analyze` clean, `flutter test` passing, Android arm64 release APK still builds.

## Mac setup (one time — skip what Save This Spot already set up)

1. Xcode from the App Store, opened once, iOS platform installed; `sudo xcode-select -s
   /Applications/Xcode.app/Contents/Developer`.
2. `brew install cocoapods`.
3. Flutter **3.47.7 stable** on PATH; `flutter doctor` green for Xcode + CocoaPods.
4. `git clone https://github.com/arwee444/penmein.git` (private). Always `git pull` first; commit + push
   iPhone changes so Windows can pull them.

## Build and run

```
cd penmein
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

Xcode: Runner → Signing & Capabilities → Automatically manage signing → your Team. Free Apple ID: installs
expire after 7 days. If Save This Spot needed `Pods-Runner` includes in `ios/Flutter/{Debug,Release}.xcconfig`,
add the same lines here. Then on the iPhone (Developer Mode on, certificate trusted):

```
flutter run --release
```

## Acceptance checks on the iPhone

1. Splash (robot + Arwee credit, gold nib), Notes, Settings, first run look like Android v1.2.0.
2. Typed note: add, edit, search, copy, share, delete.
3. Mic button: mic + speech prompts appear with the wording above; dictation saves after a pause or "done".
4. "Hey Siri, Pen Me In" (unlocked, then locked) → Siri asks for the note → "Saved to Pen Me In" → open the
   app: the note is there with the mic icon. Also from Shortcuts / Action Button.
5. No listening switch, speech models, beep/vibrate or battery settings on iPhone.
6. Android APK rebuilt and unchanged in behaviour.

## Known risks / not verified

- `PenNoteIntent.swift` was written blind: fix any compile errors on the Mac (App Intents, iOS 16+).
- Siri may say Apple Notes for "take a note" phrases; "Hey Siri, Pen Me In" is the main phrase.
- Siri on a locked phone may ask to unlock depending on settings; note in the check results.
- Lock Screen / Control Center control (widget extension + App Group) needs the paid Developer Program;
  not done, same as Save This Spot.

## Mac session results (2026-10-29, MacBook Air M3)

Toolchain: Xcode 27.1, Flutter 3.47.7 stable, CocoaPods 1.17.0, iPhone 17 on iOS 26.6.2 (USB).

**Build: done.**
- `flutter pub get` OK. `pod install` OK. It installs only the `Flutter` pod, because every iOS plugin
  comes in as a Swift Package (Flutter prints a "migrate to Swift Package Manager" note; it's harmless and
  left for later).
- Signing: automatic, team `24U49H3267` (same as Save This Spot), set on the three Runner build configs in
  `project.pbxproj`. Added the `Pods-Runner` `#include?` lines to `ios/Flutter/{Debug,Release}.xcconfig`, as in
  Save This Spot.
- `PenNoteIntent.swift` compiled first time, with **no changes needed**. The intent is in the app's
  `Metadata.appintents`, so Siri and Shortcuts can see it.
- `flutter build ios --release` OK (18.3 MB). `flutter run --release` installed and launched "Pen Me In"
  1.2.0 (5) on the iPhone.
- `flutter analyze` clean, `flutter test` all passing.

**Acceptance checks**

| # | Check | Result |
|---|---|---|
| 1 | Splash, Notes, Settings, first run look like Android v1.2.0 | **Not checked yet**: needs someone looking at the phone |
| 2 | Typed note: add, edit, search, copy, share, delete | **Not checked yet**: on the phone |
| 3 | Mic + speech prompts, dictation saves after pause / "done" | Partly. The built Info.plist has the expected wording for both prompts. Prompts and dictation still need trying on the phone |
| 4 | "Hey Siri, Pen Me In" unlocked/locked, Shortcuts, Action Button | Partly. The intent compiles and is registered in the app metadata. Tested off the phone: notes written by the intent's inbox code (including quotes, `/`, emoji and Devanagari) are read back by the Dart `NoteInbox.take()` with id, text, time and the 🎙 voice source intact. Siri itself still needs trying on the phone (unlocked, then locked) |
| 5 | No listening switch, speech models, beep/vibrate, battery on iPhone | Code check only. Home, Settings, onboarding and dictation are all gated on `ListenController.isSupported` (Android only). Still needs a look on the phone |
| 6 | Android APK rebuilt, behaviour unchanged | **Not done on the Mac**: no Dart/Android code changed in this session; rebuild on the PC |

Mac notes for next time:
- `flutter` isn't on the shell PATH: it lives at `~/development/flutter/bin`.
- `pod` lives at `~/.gem/ruby/2.6.0/bin`, and it crashes with `Unicode Normalization not appropriate for
  ASCII-8BIT` unless you set `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` first.

### Phone test feedback, round 1 (2026-10-29)

- **In-app mic:** there was no beep after "done", and notes saved after a short gap.
  - Fixed: iOS now beeps like Android (start / saved / nothing saved), using iPhone system sounds through the
    `penmein/beep` channel in `AppDelegate.swift`. The Beep switch now shows in Settings on iPhone too.
    System sounds follow the ringer switch, so there's no beep when the phone is on silent.
  - Fixed: the note now ends only by the same rules as Android: the "Pause that ends a note" setting
    (default 2.5 s), a stop phrase ("done"), the Done button, or the length limit. Before, the plugin's pause
    timer or any result Apple marked as final saved the note straight away. If Apple's recogniser stops by
    itself, the app keeps what it heard and starts listening again.
  - Still the same on both platforms: a pause longer than the setting saves the note. To wait longer before
    saying "done", raise "Pause that ends a note" (up to 6 s).
- **Siri:** Siri stopped listening before the user said "stop". That's Siri's own end-of-speech
  detection when it asks "What should I write down?". Apps can't change how long Siri waits, and Siri plays
  no app beep. Workaround: say the whole note in one go, or use the in-app mic for longer notes.
