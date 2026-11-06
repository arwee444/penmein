import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock screen / Dynamic Island view while "Hey Siri, Pen Me In" records
/// (ios/Runner/LockDictation.swift). Midnight Gold colours from lib/theme.dart.
@main
struct PenLiveActivityBundle: WidgetBundle {
  var body: some Widget { PenNoteLiveActivity() }
}

private let gold = Color(red: 0xD4 / 255, green: 0xAF / 255, blue: 0x5F / 255)
private let surface = Color(red: 0x13 / 255, green: 0x20 / 255, blue: 0x3A / 255)
private let fog = Color(red: 0x9A / 255, green: 0xA7 / 255, blue: 0xBF / 255)

struct PenNoteLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: PenNoteAttributes.self) { context in
      NoteView(state: context.state)
        .padding(16)
        .activityBackgroundTint(surface)
        .activitySystemActionForegroundColor(gold)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) { NoteView(state: context.state) }
      } compactLeading: {
        Image(systemName: context.state.icon).foregroundStyle(context.state.tint)
      } compactTrailing: {
        Text(context.state.phase == .recording ? "Pen" : "✓").foregroundStyle(gold)
      } minimal: {
        Image(systemName: context.state.icon).foregroundStyle(context.state.tint)
      }
    }
  }
}

private struct NoteView: View {
  let state: PenNoteAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: state.icon).foregroundStyle(state.tint)
        Text(state.title).font(.headline).foregroundStyle(.white)
        Spacer()
      }
      Text(state.preview)
        .font(.subheadline)
        .foregroundStyle(state.text.isEmpty ? fog : .white)
        .lineLimit(3)
      if state.phase == .recording {
        HStack(spacing: 10) {
          Button(intent: CancelNoteIntent()) { Label("Cancel", systemImage: "xmark") }
            .tint(fog)
          Button(intent: FinishNoteIntent()) { Label("Done", systemImage: "checkmark") }
            .tint(gold)
        }
        .buttonStyle(.borderedProminent)
        .font(.subheadline.weight(.semibold))
      }
    }
  }
}

extension PenNoteAttributes.ContentState {
  var icon: String {
    switch phase {
    case .recording: "mic.fill"
    case .saved: "checkmark.circle.fill"
    case .cancelled, .nothing: "xmark.circle"
    }
  }

  var tint: Color { phase == .recording ? .red : gold }

  var title: String {
    switch phase {
    case .recording: "Pen Me In · Recording"
    case .saved: "Saved to Pen Me In"
    case .cancelled: "Note cancelled"
    case .nothing: "Nothing heard, nothing saved"
    }
  }

  var preview: String {
    if text.isEmpty {
      return phase == .recording ? "Speak now. Say \"\(stopPhrase)\" when you're finished." : ""
    }
    return text.count <= 160 ? text : "…" + text.suffix(160)
  }
}
