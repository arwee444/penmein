import ActivityKit
import AppIntents
import Foundation

// Shared by the Runner app and the PenLiveActivity widget extension (target
// membership in both). The extension builds with WIDGET_EXTENSION defined.

/// The lock-screen Live Activity shown while "Hey Siri, Pen Me In" records.
@available(iOS 16.2, *)
struct PenNoteAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    enum Phase: String, Codable { case recording, saved, cancelled, nothing }

    var phase: Phase
    /// The note so far (recording) or the saved note.
    var text: String
    /// The stop phrase to show, e.g. "done".
    var stopPhrase: String
  }
}

/// Live Activity "Done" button: save the note now.
@available(iOS 17.0, *)
struct FinishNoteIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Save note"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
      if #available(iOS 18.0, *) { await LockDictation.shared.finish(save: true) }
    #endif
    return .result()
  }
}

/// Live Activity "Cancel" button: throw the note away.
@available(iOS 17.0, *)
struct CancelNoteIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Cancel note"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
      if #available(iOS 18.0, *) { await LockDictation.shared.finish(save: false) }
    #endif
    return .result()
  }
}
