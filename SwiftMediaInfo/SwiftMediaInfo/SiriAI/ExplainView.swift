//
//  ExplainView.swift
//  SwiftMediaInfo
//
//  The Siri AI window (a sheet on the main window): ask about a file, or —
//  in Compare Mode — File A, File B or both. The conversation, suggestion
//  bubbles, the question box (typing anywhere goes into it), Stop / Esc,
//  ⌘R to redo a stopped answer, Copy and Ask Again. The model side is
//  ExplainModel in Intelligence.swift.
//
//  Only on Macs that support Apple Intelligence, running macOS 27 or later,
//  and only with Apple's on-device model. When it can't run, the window says
//  exactly why instead of failing.
//

import SwiftUI

struct ExplainView: View {
    @EnvironmentObject var store: MediaStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = ExplainModel()
    @State var subject: ExplainSubject
    @State private var followUp = ""
    @State private var didCopy = false

    private let status = IntelligenceStatus.current

    // MARK: Reports

    private var files: [MediaFile?] {
        switch subject {
        case .fileA: return [store.currentFile]
        case .fileB: return [store.compareFile]
        case .both:  return [store.currentFile, store.compareFile]
        }
    }

    /// Whether every report needed has loaded: the Text report, and the
    /// parsed tracks that Media Health and the Overview are built from.
    /// Cheap — checked on every redraw, including each streamed word.
    private var isReady: Bool {
        files.allSatisfy { file in
            guard let file, let text = file.rawText else { return false }
            return !text.isEmpty && !file.tracks.isEmpty
        }
    }

    /// Everything Siri AI may read. Built once per conversation, not per
    /// redraw: the health report and the privacy filter are real work.
    private var contexts: [ExplainContext]? {
        guard isReady else { return nil }
        return files.compactMap { file in
            guard let file, let text = file.rawText else { return nil }
            return ExplainContext(
                name: file.fileName,
                report: text,
                health: MediaStore.sanitized(HealthReport(file: file).plainText, fileURL: file.url).text,
                overview: MediaSummary(tracks: file.tracks, fileURL: file.url).plainText
            )
        }
    }

    private var readError: Bool {
        files.contains { $0?.textError != nil || $0?.jsonError != nil || $0?.loadError != nil }
    }

    private var question: String {
        subject == .both ? ExplainModel.compareQuestion : ExplainModel.singleQuestion
    }

    private var subtitle: String {
        switch subject {
        case .fileA: return store.currentFile?.fileName ?? ""
        case .fileB: return store.compareFile?.fileName ?? ""
        case .both:  return "Comparing File A and File B"
        }
    }

    private var canCompare: Bool {
        store.isCompareMode && store.currentFile != nil && store.compareFile != nil
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, SMI.Spacing.xxLarge)
                .padding(.top, SMI.Spacing.xLarge)
                .padding(.bottom, SMI.Spacing.large)

            Divider().opacity(0.4)

            Group {
                if status != .available {
                    unavailable
                } else if readError {
                    message(icon: "exclamationmark.triangle.fill", tint: SMI.Palette.warning,
                            title: "This file couldn’t be read",
                            detail: "MediaInfo couldn’t analyse it, so there is no report for Siri AI to read.")
                } else if !isReady {
                    progress("Reading the file…")
                } else {
                    conversation
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.4)
            footer
        }
        .frame(width: 640, height: 680)
        .background(.ultraThinMaterial)
        .background(SheetKeyGuard())
        // Typing goes to the question box; Esc stops an answer that is still
        // being written, and otherwise closes the window as it always did.
        .background(TypeToAsk(onEscape: escape))
        .onAppear(perform: requestReports)
        .onChange(of: subject) { _, _ in requestReports() }
        .task(id: "\(subject)-\(isReady)") { startIfReady() }
        .onDisappear { model.cancel() }
    }

    private func requestReports() {
        let sides: [Bool] = subject == .both ? [false, true] : [subject == .fileB]
        for isCompare in sides {
            store.loadFormatIfNeeded(.easy, isCompare: isCompare)
            store.loadFormatIfNeeded(.text, isCompare: isCompare)
        }
    }

    private var isWorking: Bool { model.isResponding || model.isPreparing }

    private func escape() {
        if isWorking {
            model.stop()
        } else {
            dismiss()
        }
    }

    private func startIfReady() {
        guard status == .available, let contexts else { return }
        model.start(contexts: contexts, question: question,
                    shownAs: subject == .both ? ExplainModel.compareQuestionShown : nil)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: SMI.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.brandBlue, Color.brandViolet, Color.brandPink],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Image(systemName: "siri")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Siri AI")
                    .font(SMI.Typo.title)
                Text(subtitle)
                    .font(SMI.Typo.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(subtitle)
            }

            Spacer(minLength: SMI.Spacing.medium)

            if canCompare, status == .available {
                Picker("Ask about", selection: $subject) {
                    Text("File A").tag(ExplainSubject.fileA)
                    Text("Both").tag(ExplainSubject.both)
                    Text("File B").tag(ExplainSubject.fileB)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(model.isResponding || model.isPreparing)
            }

            SheetCloseButton { dismiss() }
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SMI.Spacing.large) {
                    if model.hasSession {
                        onDeviceBadge
                    }

                    if model.isPreparing && model.exchanges.isEmpty {
                        progress("Preparing the report…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }

                    ForEach(model.exchanges) { exchange in
                        exchangeView(exchange)
                            .id(exchange.id)
                    }

                    if let failure = model.failure {
                        HStack(alignment: .top, spacing: SMI.Spacing.small) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SMI.Palette.warning)
                            Text(failure)
                                .font(SMI.Typo.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(SMI.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                            .fill(SMI.Palette.warning.opacity(0.10)))
                    }

                    if showsSuggestions {
                        suggestions
                            .id("suggestions")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                // Full width from the start, so the opening question sits at
                // the left edge while it waits for its answer, rather than in
                // the middle until the answer widens the column.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SMI.Spacing.xxLarge)
                .animation(.smooth(duration: 0.25), value: showsSuggestions)
            }
            // A new question scrolls to its start; the answer then streams
            // in below it, read from the top rather than chased to the end.
            .onChange(of: model.exchanges.last?.id) { _, id in
                guard let id, model.exchanges.count > 1 else { return }
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    private var onDeviceBadge: some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.small) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("On-device")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(SMI.Palette.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(SMI.Palette.success.opacity(0.12)))
            .help("Answered on this Mac by Apple’s on-device model. Nothing left your Mac.")

            if model.wasShortened {
                Label("This report is longer than the on-device model can read at once, so less important details and extra subtitle and audio tracks were shortened.",
                      systemImage: "scissors")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func exchangeView(_ exchange: ExplainExchange) -> some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.small) {
            Text(exchange.question)
                .font(SMI.Typo.bodyStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.brandViolet.opacity(0.12)))

            if exchange.answer.isEmpty && !exchange.wasStopped {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…")
                        .font(SMI.Typo.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else if !exchange.answer.isEmpty {
                Text(Self.render(exchange.answer))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if exchange.wasStopped {
                HStack(spacing: SMI.Spacing.small) {
                    Label("Stopped", systemImage: "stop.circle")
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                    if exchange.id == model.exchanges.last?.id, model.canRedo {
                        redoHint
                            .transition(.opacity)
                    }
                }
                .padding(.top, exchange.answer.isEmpty ? 4 : 0)
            }
        }
    }

    /// Under the last answer when it was stopped: how to have it written
    /// again. Clicking it does the same as ⌘R.
    private var redoHint: some View {
        Button { model.redo() } label: {
            HStack(spacing: 5) {
                Text("Press")
                Text("⌘R")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                Text("to redo")
            }
            .font(SMI.Typo.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.brandViolet.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.brandViolet.opacity(0.30), lineWidth: 0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .help("Ask this question again (⌘R)")
    }

    // MARK: Suggestions

    private var suggestionList: [String] {
        let list = subject == .both
        ? ["Explain in simple terms", "Which one should I keep?", "Check both files’ media health", "Give me an overview of each"]
        : ["Explain in simple terms", "Check its media health", "Give me the overview", "Is this high quality?"]
        let asked = Set(model.exchanges.map { $0.question.lowercased() })
        return list.filter { suggestion in
            let s = suggestion.lowercased()
            if asked.contains(s) { return false }
            // Already answered from the app's own data, however it was asked.
            if model.sentHealth, s.contains("health") { return false }
            if model.sentOverview, s.contains("overview") { return false }
            return true
        }
    }

    private var showsSuggestions: Bool {
        !model.exchanges.isEmpty && !model.isResponding && !model.isPreparing
        && model.exchanges.last?.isFinished == true && !suggestionList.isEmpty
    }

    /// One tap asks a likely next question — the plain-language version
    /// above all, since the first answer is the technical one.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: SMI.Spacing.small) {
            Text("Suggestions")
                .font(SMI.Typo.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(suggestionList, id: \.self) { suggestion in
                    Button {
                        model.ask(suggestion)
                    } label: {
                        Label(suggestion, systemImage: Self.icon(for: suggestion))
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.brandViolet.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(Color.brandViolet.opacity(0.30), lineWidth: 0.8))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, SMI.Spacing.small)
    }

    private static func icon(for suggestion: String) -> String {
        let s = suggestion.lowercased()
        if s.contains("simple") { return "text.bubble" }
        if s.contains("health") { return "stethoscope" }
        if s.contains("overview") { return "list.bullet.rectangle" }
        if s.contains("keep") { return "checkmark.seal" }
        return "sparkles"
    }

    /// The model writes light Markdown: bold, italics, bullets, sometimes a
    /// heading. Headings become bold lines; the rest renders inline.
    static func render(_ markdown: String) -> AttributedString {
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.firstMatch(of: /^#{1,6}\s+(.+)$/) {
                return "**\(match.1)**"
            }
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                return "•  " + trimmed.dropFirst(2)
            }
            return line
        }
        let text = lines.joined(separator: "\n")
        return (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    // MARK: Unavailable

    private var unavailable: some View {
        VStack(spacing: SMI.Spacing.medium) {
            Image(systemName: "siri")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(status.title)
                .font(SMI.Typo.headline)
            Text(status.detail)
                .font(SMI.Typo.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text(IntelligencePreference.requirement)
                .font(SMI.Typo.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if status.canOpenSystemSettings {
                Button("Open System Settings") { IntelligencePreference.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandViolet)
                    .padding(.top, SMI.Spacing.small)
            }
        }
        .padding(SMI.Spacing.xxLarge)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: SMI.Spacing.medium) {
            if status == .available, !readError {
                HStack(spacing: SMI.Spacing.small) {
                    // Always open for typing — from the moment the window
                    // appears, while the report is read and while an answer is
                    // written. Asking waits until Siri AI is ready (canSend).
                    TextField(subject == .both ? "Ask about these two files…" : "Ask Siri AI about this file…", text: $followUp)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .onSubmit(sendFollowUp)
                    if isWorking {
                        Button { model.stop() } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandViolet)
                        .help("Stop (Esc)")
                        .accessibilityLabel("Stop")
                    } else {
                        Button(action: sendFollowUp) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canSend ? Color.brandViolet : .secondary)
                        .disabled(!canSend)
                        .help("Ask")
                        .accessibilityLabel("Ask")
                    }
                }
            }

            HStack(spacing: SMI.Spacing.small) {
                Text("Siri AI can make mistakes. Check important details in the report.")
                    .font(SMI.Typo.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                Spacer(minLength: SMI.Spacing.small)
                if status == .available {
                    Button(didCopy ? "Copied" : "Copy") {
                        store.copySnippet(model.transcriptText, from: nil)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                    }
                    .disabled(model.exchanges.isEmpty || model.isResponding)
                    Button("Ask Again") { startIfReady() }
                        .disabled(!isReady || isWorking)
                        .help("Start over with a fresh answer")
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandViolet)
            }
        }
        .padding(.horizontal, SMI.Spacing.xxLarge)
        .padding(.vertical, SMI.Spacing.large)
    }

    private var canSend: Bool {
        !followUp.trimmingCharacters(in: .whitespaces).isEmpty
        && !model.isResponding && !model.isPreparing && model.canAsk
    }

    private func sendFollowUp() {
        guard canSend else { return }
        model.ask(followUp)
        followUp = ""
    }

    // MARK: Shared

    private func progress(_ text: String) -> some View {
        VStack(spacing: SMI.Spacing.medium) {
            ProgressView().controlSize(.large)
            Text(text)
                .font(SMI.Typo.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func message(icon: String, tint: Color, title: String, detail: String) -> some View {
        VStack(spacing: SMI.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(tint)
            Text(title).font(SMI.Typo.headline)
            Text(detail)
                .font(SMI.Typo.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(SMI.Spacing.xxLarge)
    }
}

// MARK: - Keyboard

/// The Siri AI window's keyboard.
///
/// Typing anywhere goes to the question box. The first letter typed moves the
/// focus there — so the box lights up as typing starts — and is typed into it,
/// carrying on after anything already written. Keys with ⌘ or ⌃, and Space,
/// Return, Tab and the arrows, keep their usual jobs.
///
/// Esc goes to `onEscape`. It is caught here, ahead of the sheet, because the
/// sheet closes itself on Esc before any SwiftUI shortcut in it is asked.
private struct TypeToAsk: NSViewRepresentable {
    let onEscape: () -> Void
    
    func makeNSView(context: Context) -> TypeToAskView {
        let view = TypeToAskView()
        view.onEscape = onEscape
        return view
    }
    
    func updateNSView(_ view: TypeToAskView, context: Context) {
        view.onEscape = onEscape
    }
}

final class TypeToAskView: NSView {
    var onEscape: (() -> Void)?
    private var monitor: Any?
    
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if self.handlesEscape(event) { return true }
                self.focusQuestion(for: event)
                return false
            }
            return swallow ? nil : event
        }
    }
    
    private func handlesEscape(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, event.keyCode == 53,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        else { return false }
        // Esc while composing with an input method cancels the composition.
        if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        onEscape?()
        return true
    }
    
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
    
    /// Moves the focus to the question box ahead of a typed letter, which
    /// then goes on to be delivered there.
    private func focusQuestion(for event: NSEvent) {
        guard let window, event.window === window, Self.isTyping(event) else { return }
        // Already typing into a text box.
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return }
        guard let field = Self.questionField(in: window.contentView),
              field.isEnabled,
              window.makeFirstResponder(field),
              let editor = window.firstResponder as? NSTextView
        else { return }
        // Taking the focus selects everything in the box; carry on from the
        // end instead of typing over it.
        editor.moveToEndOfDocument(nil)
    }
    
    private static func isTyping(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control]).isEmpty,
              let scalar = event.characters?.unicodeScalars.first
        else { return false }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
        if CharacterSet.controlCharacters.contains(scalar) { return false }
        // Arrow and function keys arrive as private-use characters.
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        return true
    }
    
    private static func questionField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, !(field is NSSecureTextField) {
            return field
        }
        for subview in view.subviews {
            if let found = questionField(in: subview) { return found }
        }
        return nil
    }
}

// MARK: - Flow layout

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
