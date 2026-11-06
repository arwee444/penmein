import ActivityKit
import AVFoundation
import AppIntents
import AudioToolbox
import Foundation
import Speech

/// "Hey Siri, Pen Me In" / Action Button, also on the locked phone.
///
/// Records in the background without opening the app (an audio-recording
/// intent; iOS requires the Live Activity it starts). The note ends only on
/// a stop phrase ("done"), a cancel phrase, the Live Activity's Done/Cancel
/// buttons or the safety limit, never on a pause, like in-app dictation on
/// iPhone. The note goes to the same inbox.jsonl the app imports on open.
@available(iOS 18.0, *)
struct RecordNoteIntent: AudioRecordingIntent {
  static let title: LocalizedStringResource = "Record a long note"
  static let description = IntentDescription("Record a note, even on the lock screen. Say \"done\" to save it.")
  static let openAppWhenRun = false
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  // No spoken reply: the microphone is already on, Siri's voice would end up
  // in the note. The start beep and the Live Activity confirm instead.
  func perform() async throws -> some IntentResult {
    switch await LockDictation.shared.start() {
    case .started, .alreadyRecording: return .result()
    case .needsPermission: throw LockNoteError.needsPermission
    case .failed: throw LockNoteError.failed
    }
  }
}

@available(iOS 16.0, *)
enum LockNoteError: Error, CustomLocalizedStringResourceConvertible {
  case needsPermission, failed

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .needsPermission: "Open Pen Me In once and allow the microphone and speech recognition."
    case .failed: "I couldn't start recording. Try again in a moment."
    }
  }
}

/// Stop / cancel phrases, copied from the app's settings (lib/services/settings.dart)
/// over the penmein/launch channel.
enum LockPhrases {
  static let stopKey = "pm_stop_phrases"
  static let cancelKey = "pm_cancel_phrases"

  static var stop: [String] {
    let l = UserDefaults.standard.stringArray(forKey: stopKey) ?? []
    return l.isEmpty ? ["done", "end note"] : l
  }

  static var cancel: [String] {
    UserDefaults.standard.stringArray(forKey: cancelKey) ?? ["cancel note"]
  }

  static func save(stop: [String], cancel: [String]) {
    UserDefaults.standard.set(stop, forKey: stopKey)
    UserDefaults.standard.set(cancel, forKey: cancelKey)
  }

  /// Lower-case words only, as `normalizeSpeech` in lib/core/phrases.dart.
  static func normalize(_ s: String) -> String {
    let lowered = s.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
    let words = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
    return String(words).split(separator: " ").joined(separator: " ")
  }

  /// [text] without a trailing phrase from [phrases] (punctuation ignored),
  /// or nil when it doesn't end with one.
  static func stripTrailing(_ text: String, _ phrases: [String]) -> String? {
    let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
    for phrase in phrases {
      let words = normalize(phrase).split(separator: " ").map(String.init)
      if words.isEmpty { continue }
      var rest = tokens
      var i = words.count - 1
      var matched = true
      while i >= 0 {
        guard let last = rest.last else { matched = false; break }
        let n = normalize(last)
        if n.isEmpty { rest.removeLast(); continue }  // Lone punctuation.
        if n == words[i] {
          rest.removeLast()
          i -= 1
        } else {
          matched = false
          break
        }
      }
      if matched { return rest.joined(separator: " ") }
    }
    return nil
  }

  /// Trims, drops trailing commas etc. and capitalises the first letter.
  static func tidy(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = t.last, ",;:-".contains(last) { t.removeLast() }
    t = t.trimmingCharacters(in: .whitespaces)
    guard let first = t.first else { return "" }
    return first.uppercased() + t.dropFirst()
  }
}

/// The audio tap runs on Apple's audio thread; it feeds whichever recognition
/// request is current.
private final class RequestBox: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?

  func set(_ r: SFSpeechAudioBufferRecognitionRequest?) {
    lock.lock()
    request = r
    lock.unlock()
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let r = request
    lock.unlock()
    r?.append(buffer)
  }
}

@available(iOS 18.0, *)
@MainActor
final class LockDictation {
  static let shared = LockDictation()

  enum StartResult { case started, alreadyRecording, needsPermission, failed }

  /// Safety net in case the stop phrase is never heard (as in-app on iPhone).
  private static let maxLength: TimeInterval = 30 * 60
  /// Started by mistake and nothing said: stop without saving.
  private static let noSpeechTimeout: TimeInterval = 20

  private let engine = AVAudioEngine()
  private let box = RequestBox()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var activity: Activity<PenNoteAttributes>?
  private var timer: Timer?

  private var running = false
  private var startedAt = Date()
  /// Text of recognition stretches Apple already finished (it ends one after a
  /// long pause; recording carries on in a new one).
  private var finished: [String] = []
  private var current = ""
  private var shownText = ""
  private var restarts: [Date] = []

  private var allText: String { (finished + [current]).filter { !$0.isEmpty }.joined(separator: " ") }

  func start() async -> StartResult {
    if running { return .alreadyRecording }
    guard SFSpeechRecognizer.authorizationStatus() == .authorized,
      AVAudioApplication.shared.recordPermission == .granted
    else { return .needsPermission }

    let r = Self.makeRecognizer()
    guard let r, r.isAvailable else { return .failed }
    recognizer = r

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { [box] buffer, _ in box.append(buffer) }
      engine.prepare()
      try engine.start()
    } catch {
      cleanUpAudio()
      return .failed
    }

    running = true
    startedAt = Date()
    finished = []
    current = ""
    shownText = ""
    restarts = []
    startTask()
    startActivity()
    AudioServicesPlaySystemSound(1113)  // begin_record, as in-app (AppDelegate Beep)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
      Task { @MainActor in LockDictation.shared.tick() }
    }
    return .started
  }

  /// Ends the note: saves it (minus a trailing stop phrase) or throws it away.
  func finish(save: Bool) async {
    guard running else { return }
    running = false
    timer?.invalidate()
    timer = nil
    let heard = allText
    let body = LockPhrases.stripTrailing(heard, LockPhrases.stop) ?? heard
    let text = save ? LockPhrases.tidy(body) : ""
    cleanUpAudio()
    if !text.isEmpty { try? NoteInbox.append(text) }

    let phase: PenNoteAttributes.ContentState.Phase = !save ? .cancelled : (text.isEmpty ? .nothing : .saved)
    AudioServicesPlaySystemSound(phase == .saved ? 1114 : 1053)  // end_record / negative
    let state = PenNoteAttributes.ContentState(phase: phase, text: text, stopPhrase: Self.stopLabel)
    await activity?.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
    activity = nil
    try? await Task.sleep(nanoseconds: 600_000_000)  // Let the beep play.
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Recognition

  private static func makeRecognizer() -> SFSpeechRecognizer? {
    if let r = SFSpeechRecognizer(locale: Locale.current), r.supportsOnDeviceRecognition { return r }
    if let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), r.supportsOnDeviceRecognition { return r }
    return SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  }

  private func startTask() {
    guard running, let recognizer else { return }
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    req.taskHint = .dictation
    req.addsPunctuation = true
    // On-device: works while locked and has no one-minute server limit.
    if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
    request = req
    box.set(req)
    task = recognizer.recognitionTask(with: req) { result, error in
      let text = result?.bestTranscription.formattedString
      let isFinal = result?.isFinal ?? false
      let failed = error != nil
      Task { @MainActor in LockDictation.shared.onResult(req, text: text, isFinal: isFinal, failed: failed) }
    }
  }

  private func onResult(_ req: SFSpeechAudioBufferRecognitionRequest, text: String?, isFinal: Bool, failed: Bool) {
    guard running, req === request else { return }  // A finished stretch.
    if let text { current = text }

    let heard = allText
    if LockPhrases.stripTrailing(heard, LockPhrases.cancel) != nil {
      Task { await finish(save: false) }
      return
    }
    if LockPhrases.stripTrailing(heard, LockPhrases.stop) != nil {
      Task { await finish(save: true) }
      return
    }

    if isFinal || failed {
      // Apple ended this stretch (a long pause, or an error): keep the words and
      // listen on. Repeated quick failures mean the recogniser isn't working.
      if !current.isEmpty { finished.append(current) }
      current = ""
      task?.cancel()
      let now = Date()
      restarts = restarts.filter { now.timeIntervalSince($0) < 10 } + [now]
      if restarts.count > 5 {
        Task { await finish(save: true) }
        return
      }
      startTask()
    }
    updateActivity()
  }

  private func tick() {
    guard running else { return }
    let elapsed = Date().timeIntervalSince(startedAt)
    if elapsed >= Self.maxLength {
      Task { await finish(save: true) }
    } else if allText.isEmpty && elapsed >= Self.noSpeechTimeout {
      Task { await finish(save: false) }
    } else {
      updateActivity()
    }
  }

  private func cleanUpAudio() {
    engine.inputNode.removeTap(onBus: 0)
    if engine.isRunning { engine.stop() }
    box.set(nil)
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
  }

  // MARK: - Live Activity

  private static var stopLabel: String { LockPhrases.stop.first ?? "done" }

  private func startActivity() {
    let state = PenNoteAttributes.ContentState(phase: .recording, text: "", stopPhrase: Self.stopLabel)
    activity = try? Activity.request(
      attributes: PenNoteAttributes(),
      content: ActivityContent(state: state, staleDate: nil),
      pushType: nil
    )
  }

  private func updateActivity() {
    let text = allText
    guard text != shownText, let activity else { return }
    shownText = text
    let state = PenNoteAttributes.ContentState(phase: .recording, text: text, stopPhrase: Self.stopLabel)
    Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
  }
}
