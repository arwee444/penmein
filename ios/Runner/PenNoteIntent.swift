import AppIntents
import Foundation

/// "Hey Siri, Pen Me In" / Action Button / Shortcuts.
///
/// Siri asks "What should I write down?", takes the dictation and the intent
/// appends it to the same inbox Android's listening service uses (`NoteInbox`
/// in lib/data/notes.dart). The app imports the inbox on launch/resume.
/// Runs without opening the app. Mirrors Save This Spot's SaveSpotIntent.
@available(iOS 16.0, *)
struct PenNoteIntent: AppIntent {
  static let title: LocalizedStringResource = "Pen me in"
  static let description = IntentDescription("Dictate a note into Pen Me In.")
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
      intent: PenNoteIntent(),
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
