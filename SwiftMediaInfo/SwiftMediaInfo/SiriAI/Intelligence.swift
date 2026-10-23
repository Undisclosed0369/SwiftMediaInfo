//
//  Intelligence.swift
//  SwiftMediaInfo
//
//  Siri AI: ask about a file, or compare two, in plain language. This file
//  holds availability, the report shortening, and the conversation
//  (ExplainModel); the window is ExplainView. Types named "Explain…" are
//  Siri AI's — the feature's working name before it was named.
//
//  REQUIREMENT
//
//  Only on Macs that support Apple Intelligence, running macOS 27 or later,
//  with Apple Intelligence turned on in System Settings. Everywhere else the
//  feature says exactly why it isn't there — in Settings › Siri AI and in the
//  window itself — and the rest of the app is unaffected. FoundationModels
//  exists on macOS 26 too, but this feature is deliberately macOS 27 only.
//
//  ON-DEVICE ONLY
//
//  Siri AI uses Apple's on-device model and nothing else; nothing leaves the
//  Mac. Apple's Private Cloud Compute was considered and dropped: Apple only
//  lets individually approved apps use it (a managed entitlement this app
//  doesn't have — without it the first request stops the app), and it would
//  send the report — file names, titles, languages — to Apple's servers.
//
//  WHAT THE MODEL READS
//
//  MediaInfo's Text report, never the file, with file paths taken out. Asked
//  about health or for an overview, it also gets the app's own Media Health
//  results or Overview, so the answer comes from the same checks the app
//  shows. The on-device context holds about 8K tokens; long reports are
//  shortened — least useful fields first, then extra subtitle and audio
//  tracks folded into one line — and the window says so.
//
//  HOW A CONVERSATION RUNS
//
//  `start` opens a session whose first prompt carries the report; follow-up
//  questions go to the same session. `stop` (the Stop button, Esc) keeps what
//  was written and marks the exchange stopped; ⌘R (`redo`) asks it again in
//  its place. A stopped prompt doesn't stay in the session, so until an
//  answer that carried the report has finished (`reportDelivered`), the next
//  question starts a fresh session that carries it — otherwise Siri AI would
//  answer without the file.
//

import Foundation
import AppKit
import SwiftUI
import FoundationModels
internal import Combine

// MARK: - Preferences

enum IntelligencePreference {
    /// The master switch. Off hides every Siri AI entry point.
    static let enabledKey = "intelligenceEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static let requirement = "Siri AI requires a Mac that supports Apple Intelligence, running macOS 27 or later."

    /// Apple Intelligence & Siri in System Settings.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Availability

/// Whether the feature can run here, and if not, why — in words a person can
/// act on.
enum IntelligenceStatus: Equatable {
    case available
    /// macOS 26: the feature is macOS 27 only.
    case needsNewerMacOS
    /// This Mac can't run Apple Intelligence at all.
    case deviceNotEligible
    /// Supported, but switched off in System Settings.
    case systemSettingOff
    /// Supported and on, but the model is still downloading or preparing.
    case modelNotReady
    /// Any other reason the system reported.
    case unavailable

    static var current: IntelligenceStatus {
        guard #available(macOS 27, *) else { return .needsNewerMacOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .systemSettingOff
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unavailable
        }
    }

    /// The toolbar button, menu item and File Actions row appear only where
    /// the feature could work: the setting is on, and this Mac and macOS can
    /// run it. Turning Apple Intelligence off in System Settings, or a model
    /// still downloading, still shows them — the window then explains what to
    /// do, since that is something the person can fix.
    static var showsEntryPoints: Bool {
        guard IntelligencePreference.isEnabled else { return false }
        switch current {
        case .needsNewerMacOS, .deviceNotEligible: return false
        default: return true
        }
    }

    var title: String {
        switch self {
        case .available:         return "Available on this Mac"
        case .needsNewerMacOS:   return "Requires macOS 27 or later"
        case .deviceNotEligible: return "Not supported on this Mac"
        case .systemSettingOff:  return "Apple Intelligence is turned off"
        case .modelNotReady:     return "Getting ready"
        case .unavailable:       return "Not available right now"
        }
    }

    var detail: String {
        switch self {
        case .available:
            return "Siri AI runs on this Mac with Apple’s on-device model, so nothing leaves your Mac."
        case .needsNewerMacOS:
            return "Siri AI only works on Macs that support Apple Intelligence, running macOS 27 or later. Everything else in SwiftMediaInfo works as usual."
        case .deviceNotEligible:
            return "This Mac doesn’t support Apple Intelligence, which Siri AI is built on, so Siri AI isn’t available here. It needs a Mac that supports Apple Intelligence, running macOS 27 or later. Everything else in SwiftMediaInfo works as usual."
        case .systemSettingOff:
            return "Siri AI is built on Apple Intelligence, which is turned off. Turn it on in System Settings › Apple Intelligence & Siri, then try again."
        case .modelNotReady:
            return "Apple Intelligence’s on-device model is still downloading or preparing. This usually finishes on its own — try again in a few minutes."
        case .unavailable:
            return "macOS reports that Apple Intelligence, which Siri AI is built on, can’t be used at the moment. Try again later."
        }
    }

    var canOpenSystemSettings: Bool {
        self == .systemSettingOff
    }
}

// MARK: - What to ask

/// Which file(s) the window is about. Its own identity, so the window can be
/// reopened straight after closing it.
struct ExplainTarget: Identifiable, Equatable {
    let id = UUID()
    var subject: ExplainSubject
}

enum ExplainSubject: Hashable {
    case fileA, fileB, both
}

// MARK: - Shortening long reports

/// MediaInfo's Text report, made to fit a token budget.
///
/// Each level keeps everything the one before kept that matters most and
/// gives up something less useful. Level 0 is the report as MediaInfo wrote
/// it, minus the file's path.
nonisolated enum ReportCondenser {

    static let maxLevel = 4

    /// Fields that describe how the file was made rather than what is in it.
    private static let noiseKeys: Set<String> = [
        "unique id", "codec id/info", "codec id/hint", "encoding settings",
        "writing library", "writing application", "count of elements",
        "default", "forced", "stream size", "source stream size",
        "delay relative to video", "delay", "statistics tags issue", "statistics tags",
        "bps", "number_of_frames", "number_of_bytes",
        "_statistics_writing_app", "_statistics_writing_date_utc", "_statistics_tags",
        "format settings", "format settings, cabac", "format settings, reference frames",
        "format settings, gop", "overall bit rate mode", "encoded date",
        "folder name", "file name extension", "file name", "complete name",
        "codec configuration box", "frame count", "matrix coefficients", "compression mode",
        "service kind", "alternate group", "elementary stream", "muxing mode",
    ]

    /// Fields worth keeping even from tracks whose details are folded away.
    private struct Section {
        var title: String
        var lines: [String]
        var kind: String { title.split(separator: " ").first.map(String.init) ?? title }
    }

    static func condense(_ report: String, fileName: String, level: Int) -> String {
        var sections = parse(report)

        // Always: the path goes, the name stays.
        for i in sections.indices where sections[i].kind == "General" {
            sections[i].lines = sections[i].lines.map { line in
                key(of: line) == "complete name" ? "Complete name : \(fileName)" : line
            }
            .filter { key(of: $0) != "folder name" }
        }

        // A subtitle track's "frame rate" is how often captions change, and
        // the model read 0.4 FPS as "extremely slow subtitles".
        for i in sections.indices where sections[i].kind == "Text" {
            sections[i].lines = sections[i].lines.filter { !key(of: $0).hasPrefix("frame rate") }
        }

        if level >= 1 {
            for i in sections.indices {
                let keepName = sections[i].kind == "General"
                sections[i].lines = sections[i].lines.filter { line in
                    let k = key(of: line)
                    if keepName && k == "complete name" { return true }
                    if k.hasPrefix("_statistics") { return false }
                    return !noiseKeys.contains(k)
                }
            }
        }

        if level >= 2 {
            sections = fold(sections, kind: "Text", keep: level >= 3 ? 2 : 4, noun: "subtitle")
            sections = fold(sections, kind: "Audio", keep: level >= 3 ? 3 : 6, noun: "audio")
            if level >= 3 {
                sections = sections.map { section in
                    guard section.kind == "Menu" else { return section }
                    return Section(title: "Menu", lines: ["Chapters : \(section.lines.count)"])
                }
            }
        }

        var text = sections.map { ([$0.title] + $0.lines).joined(separator: "\n") }
            .joined(separator: "\n\n")

        if level >= 4, text.count > 6_000 {
            text = String(text.prefix(6_000)) + "\n\n[Report shortened to fit]"
        }
        return text
    }

    private static func parse(_ report: String) -> [Section] {
        report
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { block in
                let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                guard let title = lines.first else { return nil }
                return Section(title: title, lines: Array(lines.dropFirst()))
            }
    }

    private static func key(of line: String) -> String {
        guard let colon = line.range(of: " : ") ?? line.range(of: ":") else { return "" }
        return line[..<colon.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func value(of line: String) -> String {
        guard let colon = line.range(of: " : ") ?? line.range(of: ":") else { return "" }
        return line[colon.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    /// Keeps the first `keep` tracks of a kind in full and folds the rest
    /// into one line naming each by language and format.
    private static func fold(_ sections: [Section], kind: String, keep: Int, noun: String) -> [Section] {
        let indices = sections.indices.filter { sections[$0].kind == kind }
        guard indices.count > keep else { return sections }
        let folded = indices.dropFirst(keep)
        let names = folded.map { i -> String in
            let lines = sections[i].lines
            let lang = lines.first { key(of: $0) == "language" }.map(value) ?? "Unknown language"
            let format = lines.first { key(of: $0) == "format" }.map(value)
            let title = lines.first { key(of: $0) == "title" }.map(value)
                .flatMap { $0.caseInsensitiveCompare(lang) == .orderedSame ? nil : $0 }
            return [lang, format.map { "(\($0))" }, title.map { "“\($0)”" }]
                .compactMap { $0 }.joined(separator: " ")
        }
        var result = sections.enumerated().filter { !folded.contains($0.offset) }.map(\.element)
        let summary = Section(
            title: "Other \(noun) tracks",
            lines: ["Count : \(folded.count)", "Tracks : \(names.joined(separator: "; "))"]
        )
        if let last = result.lastIndex(where: { $0.kind == kind }) {
            result.insert(summary, at: last + 1)
        } else {
            result.append(summary)
        }
        return result
    }
}

// MARK: - The conversation

/// One question and its answer, as shown in the window.
struct ExplainExchange: Identifiable, Equatable {
    let id = UUID()
    var question: String
    var answer: String = ""
    var isFinished = false
    /// Stopped by the user before it was finished; `answer` is what had been
    /// written by then.
    var wasStopped = false
}

/// What Siri AI may read about one file. Media Health and the Overview are
/// the app's own analyses — handed over when a question asks for them, so
/// "check its health" uses the same checks as ⇧⌘H rather than the model's
/// guess.
struct ExplainContext {
    var name: String
    var report: String
    var health: String?
    var overview: String?
}

/// Drives the window: prepares the report, streams answers from the
/// on-device model and keeps the session for follow-up questions.
@MainActor
final class ExplainModel: ObservableObject {

    @Published private(set) var exchanges: [ExplainExchange] = []
    @Published private(set) var isResponding = false
    @Published private(set) var isPreparing = false
    @Published private(set) var hasSession = false
    @Published private(set) var wasShortened = false
    @Published private(set) var failure: String?

    /// LanguageModelSession, held untyped so this class needn't be
    /// macOS 27 only.
    private var session: AnyObject?
    private var task: Task<Void, Never>?
    /// A stopped answer, still winding down. The session takes one request at
    /// a time, so the next question waits for it.
    private var winding: Task<Void, Never>?
    /// Counts answers, so a stopped one finishing late can't touch the next.
    private var generation = 0
    /// The opening question while the report is prepared, for showing it if
    /// it is stopped before the answer starts.
    private var preparingQuestion: String?
    /// The exchange already showing a question whose report is being
    /// prepared (a fresh start from `ask`).
    private var preparingIndex: Int?
    /// Whether a finished answer carried the report into the session. Until
    /// one has, the session knows nothing about the file.
    private var reportDelivered = false
    /// The Media Health and Overview data added to the request in progress.
    private var pendingData: (health: Bool, overview: Bool) = (false, false)
    private var contexts: [ExplainContext] = []
    @Published private(set) var sentHealth = false
    @Published private(set) var sentOverview = false

    static let singleQuestion = "Can you tell me what this is?"
    static let compareQuestion = "Compare these two files technically — picture, HDR, audio, subtitles, size and bit rate. What are the important differences, and which is the better copy?"
    /// What the window shows for the comparison question; the model gets the
    /// fuller version above.
    static let compareQuestionShown = "Compare these two files technically"

    private static let common = """
    You are Siri AI inside SwiftMediaInfo, a Mac app that analyses video and \
    audio files. You are given the output of MediaInfo, which lists the \
    technical details of media files. Answer only from facts you are given. \
    Be accurate and specific, using the real values (resolution, codec, HDR \
    format, bit rates, channels, languages), and briefly explain technical \
    terms. Keep answers under 250 words, in short paragraphs or bullet \
    points. Never invent details. If asked to explain in simple terms, avoid \
    jargon. If a question includes SwiftMediaInfo's Media Health results or \
    Overview, base the answer on them and say they come from SwiftMediaInfo.
    """

    static func instructions(comparing: Bool) -> String {
        comparing
        ? common + " You are given two files, File A and File B. Compare them, naming each as File A or File B."
        : common + " You are given one file. Talk about it directly; never mention other files."
    }

    /// Starts over with one file, or File A and File B.
    func start(contexts: [ExplainContext], question: String, shownAs shown: String? = nil) {
        cancel()
        exchanges = []
        failure = nil
        hasSession = false
        wasShortened = false
        session = nil
        reportDelivered = false
        sentHealth = false
        sentOverview = false
        self.contexts = contexts
        opening = (question, shown)
        guard #available(macOS 27, *) else {
            failure = IntelligenceStatus.needsNewerMacOS.detail
            return
        }
        isPreparing = true
        preparingQuestion = shown ?? question
        task = Task { [weak self] in
            await self?.run(question: question, shownAs: shown ?? question, into: nil)
        }
    }

    /// Whether there is anything to ask about yet.
    var canAsk: Bool { !contexts.isEmpty }

    /// The opening question as the model gets it and as the window shows it,
    /// for redoing it if it is stopped.
    private var opening: (question: String, shown: String?)?

    /// Whether the last answer was stopped and can be asked again (⌘R).
    var canRedo: Bool {
        exchanges.last?.wasStopped == true && !isResponding && !isPreparing && canAsk
    }

    /// ⌘R: asks the stopped question again, in its place.
    func redo() {
        guard canRedo, let stopped = exchanges.popLast() else { return }
        if exchanges.isEmpty, let opening {
            // The opening question: a fresh start, exactly as the window
            // began — with the full comparison question when comparing.
            start(contexts: contexts, question: opening.question, shownAs: opening.shown)
        } else {
            ask(stopped.question)
        }
    }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding, !isPreparing, canAsk else { return }
        guard #available(macOS 27, *) else { return }
        let previous = winding
        winding = nil

        guard reportDelivered else {
            // The report never reached Siri AI — the answer that carried it
            // was stopped (or failed) before it finished — so this question
            // starts a fresh conversation that carries it, rather than being
            // answered from nothing.
            sentHealth = false
            sentOverview = false
            failure = nil
            exchanges.append(ExplainExchange(question: question))
            let index = exchanges.count - 1
            isPreparing = true
            preparingIndex = index
            task = Task { [weak self] in
                await previous?.value
                await self?.run(question: question, shownAs: question, into: index)
            }
            return
        }

        let prompt = withRequestedData(question)
        task = Task { [weak self] in
            await previous?.value
            await self?.respond(to: prompt, shownAs: question, carriesReport: false, into: nil)
        }
    }

    /// Stops the answer being written — or the report being prepared — and
    /// keeps whatever had been written.
    func stop() {
        guard isResponding || isPreparing else { return }
        if isPreparing {
            if let index = preparingIndex, exchanges.indices.contains(index) {
                exchanges[index].isFinished = true
                exchanges[index].wasStopped = true
            } else if let question = preparingQuestion {
                exchanges.append(ExplainExchange(question: question, isFinished: true, wasStopped: true))
            }
        } else if let last = exchanges.indices.last, !exchanges[last].isFinished {
            exchanges[last].isFinished = true
            exchanges[last].wasStopped = true
        }
        // Media Health or Overview data added to the stopped question can't be
        // relied on to have reached Siri AI; it goes again next time it's asked
        // for.
        if pendingData.health { sentHealth = false }
        if pendingData.overview { sentOverview = false }
        cancel()
    }

    func cancel() {
        task?.cancel()
        winding = task
        task = nil
        preparingQuestion = nil
        preparingIndex = nil
        pendingData = (false, false)
        isResponding = false
        isPreparing = false
    }

    var transcriptText: String {
        exchanges.map { exchange in
            let answer = exchange.wasStopped
            ? (exchange.answer.isEmpty ? "(Stopped)" : exchange.answer + "\n\n(Stopped)")
            : exchange.answer
            return "Q: \(exchange.question)\n\n\(answer)"
        }
        .joined(separator: "\n\n")
    }

    // MARK: Media Health and Overview

    private static let healthWords = [
        "health", "healthy", "problem", "issue", "wrong", "error", "corrupt",
        "broken", "damaged", "warning", "fix", "check", "defect", "glitch",
    ]
    private static let overviewWords = [
        "overview", "summary", "summarise", "summarize", "sum up", "sum it up",
        "at a glance", "tl;dr", "tldr", "in short", "key facts", "highlights",
    ]

    private static func mentions(_ question: String, _ words: [String]) -> Bool {
        let q = question.lowercased()
        return words.contains { q.contains($0) }
    }

    /// The question, with the app's Media Health results or Overview added
    /// the first time a question asks for them.
    private func withRequestedData(_ question: String) -> String {
        var parts = [question]
        let label = { (c: ExplainContext) in self.contexts.count > 1 ? " — \(c.name)" : "" }
        pendingData = (false, false)

        if !sentHealth, Self.mentions(question, Self.healthWords) {
            let blocks = contexts.compactMap { c in c.health.map { "Media Health results\(label(c)):\n\($0)" } }
            if !blocks.isEmpty {
                parts.append(blocks.joined(separator: "\n\n"))
                sentHealth = true
                pendingData.health = true
            }
        }
        if !sentOverview, Self.mentions(question, Self.overviewWords) {
            let blocks = contexts.compactMap { c in c.overview.map { "SwiftMediaInfo Overview\(label(c)):\n\($0)" } }
            if !blocks.isEmpty {
                parts.append(blocks.joined(separator: "\n\n"))
                sentOverview = true
                pendingData.overview = true
            }
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: Running

    /// A fresh session whose first prompt carries the report. `index` is the
    /// exchange already showing the question, if there is one.
    @available(macOS 27, *)
    private func run(question: String, shownAs shown: String, into index: Int?) async {
        let extra = withRequestedData(question)
        let plan = await Self.plan(contexts: contexts, question: extra)
        guard !Task.isCancelled else { return }
        isPreparing = false
        preparingQuestion = nil
        preparingIndex = nil
        wasShortened = plan.shortened
        session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Self.instructions(comparing: contexts.count > 1)
        )
        hasSession = true
        await respond(to: plan.prompt, shownAs: shown, carriesReport: true, into: index)
    }

    @available(macOS 27, *)
    private func respond(to prompt: String, shownAs question: String, carriesReport: Bool, into existing: Int?) async {
        guard let session = session as? LanguageModelSession else { return }
        failure = nil
        let index: Int
        if let existing, exchanges.indices.contains(existing) {
            index = existing
        } else {
            exchanges.append(ExplainExchange(question: question))
            index = exchanges.count - 1
        }
        generation += 1
        let mine = generation
        isResponding = true
        defer { if generation == mine { isResponding = false } }

        // A request stopped a moment ago may still be closing in the session.
        var waited = 0
        while session.isResponding, waited < 100, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000)
            waited += 1
        }

        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                guard !Task.isCancelled else { return }
                exchanges[index].answer = snapshot.content
            }
            guard !Task.isCancelled else { return }
            exchanges[index].isFinished = true
            pendingData = (false, false)
            if carriesReport { reportDelivered = true }
        } catch {
            // Stopped: `stop` has already marked the exchange.
            guard !Task.isCancelled else { return }
            if exchanges[index].answer.isEmpty { exchanges.remove(at: index) }
            if pendingData.health { sentHealth = false }
            if pendingData.overview { sentOverview = false }
            pendingData = (false, false)
            failure = Self.describe(error)
        }
    }

    /// How much of the report fits the on-device model.
    @available(macOS 27, *)
    private static func plan(contexts: [ExplainContext], question: String)
    async -> (prompt: String, shortened: Bool) {
        let model = SystemLanguageModel.default
        // Room for the instructions, the answer and a few follow-ups.
        let budget = model.contextSize - 2_200

        func prompt(level: Int) -> String {
            let body = contexts.map { context -> String in
                let text = ReportCondenser.condense(context.report, fileName: context.name, level: level)
                let clean = MediaStore.sanitized(text, fileURL: URL(fileURLWithPath: context.name)).text
                return contexts.count > 1 ? "\(context.name):\n\(clean)" : clean
            }
            .joined(separator: "\n\n---\n\n")
            let files = contexts.count > 1 ? "MediaInfo reports (File A, then File B)" : "MediaInfo report"
            return "\(question)\n\n\(files):\n\n\(body)"
        }

        func tokens(_ text: String) async -> Int {
            (try? await model.tokenCount(for: text)) ?? text.count / 3
        }

        let full = prompt(level: 0)
        if await tokens(full) <= budget { return (full, false) }

        for level in 1...ReportCondenser.maxLevel {
            let text = prompt(level: level)
            if await tokens(text) <= budget { return (text, true) }
        }
        return (prompt(level: ReportCondenser.maxLevel), true)
    }

    @available(macOS 27, *)
    private static func describe(_ error: Error) -> String {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded:
                return "This conversation has grown too long for the on-device model. Press Ask Again to start fresh."
            case .guardrailViolation, .refusal:
                return "Siri AI declined to answer that. Try asking in a different way."
            case .rateLimited:
                return "Siri AI is busy right now. Wait a moment and try again."
            case .unsupportedLanguageOrLocale:
                return "Siri AI doesn’t support your Mac’s current language for this yet."
            case .timeout:
                return "Siri AI took too long to answer. Try again."
            default:
                break
            }
        }
        let status = IntelligenceStatus.current
        if status != .available { return status.detail }
        return "Siri AI couldn’t answer: \(error.localizedDescription)"
    }
}

// MARK: - Opening the window

extension MediaStore {

    var canExplain: Bool {
        currentFile != nil || compareFile != nil
    }

    /// File A (or the only file), File B, or — in Compare Mode with both
    /// files open — the two together.
    func showExplain(_ subject: ExplainSubject? = nil) {
        guard IntelligenceStatus.showsEntryPoints, canExplain else { return }
        let resolved: ExplainSubject
        if let subject {
            resolved = subject
        } else if isCompareMode, currentFile != nil, compareFile != nil {
            resolved = .both
        } else {
            resolved = currentFile != nil ? .fileA : .fileB
        }
        explainTarget = ExplainTarget(subject: resolved)
    }
}

// MARK: - File menu

/// File › Ask Siri AI… (⇧⌘I). Its own view so the
/// Settings switch adds and removes it at once.
struct ExplainMenuItem: View {
    @ObservedObject var store: MediaStore
    @AppStorage(IntelligencePreference.enabledKey) private var enabled = true

    var body: some View {
        if enabled, IntelligenceStatus.showsEntryPoints {
            Button("Ask Siri AI…") {
                store.showExplain()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!store.canExplain)
        }
    }
}
