import AppIntents
import Foundation

/// "Hey Siri, Pen Me In" / Action Button.
///
/// Opens the app straight into its own dictation, which ends only on "done"
/// or the Done button (lib/services/ios_dictation.dart). Siri's own dictation
/// ends at the first pause and apps can't change that, so Siri doesn't take
/// the note itself. The app picks the request up through `DictateRequest`
/// (method channel `penmein/launch` in AppDelegate.swift, lib/ui/home_screen.dart).
@available(iOS 16.0, *)
struct DictateNoteIntent: AppIntent {
  static let title: LocalizedStringResource = "Pen me in"
  static let description = IntentDescription("Open Pen Me In and start dictating. Say \"done\" to save.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    DictateRequest.mark()
    return .result()
  }
}

/// "Start dictating", handed from the intent to the Flutter side.
enum DictateRequest {
  private static let key = "pm_dictate_request"

  static func mark() {
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
  }

  /// True once per request, if it is recent (opening can take a moment, e.g.
  /// unlocking with Face ID first).
  static func take() -> Bool {
    let at = UserDefaults.standard.double(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
    return at > 0 && Date().timeIntervalSince1970 - at < 120
  }
}

/// Shortcuts action "Add a note": saves the given text without opening the
/// app, e.g. in a user-built Shortcut Dictate Text (Stop Listening: On Tap) →
/// Add a note. Appends to the same inbox Android's listening service uses
/// (`NoteInbox` in lib/data/notes.dart); the app imports it on launch/resume.
@available(iOS 16.0, *)
struct PenNoteIntent: AppIntent {
  static let title: LocalizedStringResource = "Add a note"
  static let description = IntentDescription("Save text as a note in Pen Me In.")
  static let openAppWhenRun = false

  @Parameter(title: "Note", requestValueDialog: IntentDialog("What should I write down?"))
  var note: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return .result(dialog: "I didn't catch anything, so nothing was saved.")
    }
    try NoteInbox.append(text)
    return .result(dialog: "Saved to Pen Me In.")
  }
}

@available(iOS 16.0, *)
struct PenNoteShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: DictateNoteIntent(),
      phrases: [
        "\(.applicationName)",
        "Take a note in \(.applicationName)",
        "New note in \(.applicationName)",
        "Write down in \(.applicationName)",
      ],
      shortTitle: "Pen me in",
      systemImageName: "pencil.and.scribble"
    )
  }
}

/// Appends one JSON line per note, in the format `NoteInbox.take` reads:
/// {"id": "...", "text": "...", "t": "<ISO-8601>"}
enum NoteInbox {
  static func append(_ text: String) throws {
    let fm = FileManager.default
    // Same directory as path_provider's getApplicationSupportDirectory() on iOS.
    let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let file = dir.appendingPathComponent("inbox.jsonl")

    let time = ISO8601DateFormatter()
    time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let entry: [String: Any] = [
      "id": UUID().uuidString.lowercased(),
      "text": text,
      "t": time.string(from: Date()),
    ]
    var line = try JSONSerialization.data(withJSONObject: entry)
    line.append(0x0A)

    if !fm.fileExists(atPath: file.path) {
      fm.createFile(atPath: file.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.synchronize()
  }
}
