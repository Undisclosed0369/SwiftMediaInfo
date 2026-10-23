//
//  MediaStore+Copy.swift
//  SwiftMediaInfo
//
//  Copying: single values (Easy View's copy buttons, the Overview, Media
//  Health), the whole report in the current view, and Compare Mode's File A
//  / File B / Both — each through the Copy privacy settings — plus opening a
//  file in its default app.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
internal import Combine

extension MediaStore {
    
    // MARK: - Targeted copy
    
    /// Copies a single value, prompting about paths only when there is a path
    /// to prompt about.
    ///
    /// Running the full Copy privacy flow on every field copy would mean an
    /// alert each time someone copied a bit rate, which contains nothing
    /// sensitive. The text is sanitised speculatively first; if that changed
    /// nothing, the value is copied straight out with no interruption. Only a
    /// value that genuinely carries a local path asks the question.
    func copySnippet(_ text: String, from fileURL: URL?, actionName: String = "Copy") {
        guard !text.isEmpty else { return }
        
        guard let fileURL else {
            writeToPasteboard(text)
            return
        }
        
        let sanitized = PrivacySanitizer.sanitize(text, fileURL: fileURL)
        
        guard !sanitized.report.isEmpty else {
            writeToPasteboard(text)
            return
        }
        
        guard let removePaths = PrivacyPreference.resolveLocalDecision(
            actionName: actionName
        ) else { return }
        
        writeToPasteboard(removePaths ? sanitized.text : text)
    }
    
    /// Copies every field of one track — as aligned "key  value" lines, or
    /// as a Markdown table ready for GitHub and documentation.
    func copyTrack(_ track: MediaTrack, from fileURL: URL?, asMarkdown: Bool = false) {
        var fields = EasyFields.resolve(for: track)
        guard !fields.isEmpty else { return }
        
        // MediaInfo reports FileName without its extension; Easy View shows
        // the full name, and so should the copy.
        if let fileURL, let index = fields.firstIndex(where: { $0.key == "FileName" }) {
            fields[index].value = fileURL.lastPathComponent
        }
        
        let rows = fields.map { (label: FieldFormat.friendlyLabel($0.key), value: $0.value) }
        let text = asMarkdown
        ? MarkdownBuilder.section(track.displayTitle, rows: rows)
        : MarkdownBuilder.plainSection(track.displayTitle, rows: rows)
        
        copySnippet(text, from: fileURL, actionName: "Copy")
    }
    
    /// Copies the Easy View overview, plain or as Markdown.
    func copySummary(_ summary: MediaSummary, from fileURL: URL?, asMarkdown: Bool) {
        let text = asMarkdown ? summary.markdown : summary.plainText
        copySnippet(text, from: fileURL, actionName: "Copy")
    }
    
    func writeToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.trimmingTrailingWhitespace, forType: .string)
    }
    
    // MARK: - Open in default app
    //
    // One funnel for all four ways to launch a file (toolbar button, the two
    // rows of the Compare Mode picker, ⌘↩), so the "Opening…" confirmation —
    // and anything added later — reaches every route.
    
    func openInDefaultApp(_ url: URL) {
        OpenInDefaultAppButton.openInDefaultApp(url)
        flashLaunch()
    }
    
    /// Held longer than the copy flash on purpose. The copy flash confirms
    /// something that already finished; this one covers the gap while a second
    /// application launches and comes to the front.
    private func flashLaunch() {
        launchFlashTask?.cancel()
        
        smiWithAnimation(SMI.Motion.snap) { didLaunchInApp = true }
        SMI.A11y.announce("Opening in the default app")
        
        launchFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, let self else { return }
            smiWithAnimation(SMI.Motion.fade) { self.didLaunchInApp = false }
        }
    }
    
    // MARK: - Copy to clipboard
    
    /// Copies the current view's output. Returns whether anything reached the
    /// clipboard, so the toolbar button flashes "Copied" only when it's true —
    /// there may be no file open, or the privacy prompt may be cancelled, and
    /// the clipboard is invisible, so the button is the only evidence.
    @discardableResult
    func copyToClipboard() -> Bool {
        guard let file = currentFile else { return false }
        let url = file.url
        
        // Asked once per action, not once per document — a multi-file export
        // shouldn't interrogate the user repeatedly about the same question.
        guard let shouldRemovePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Copy"
        ), let includeChecksum = PrivacyPreference.resolveChecksumDecision(
            actionName: "Copy", files: [file]
        ) else { return false }
        
        guard let content = outputStringForFile(includeChecksum ? file : file.withoutChecksum()) else {
            return false
        }
        
        let output = shouldRemovePaths
        ? PrivacySanitizer.sanitize(content, fileURL: url).text
        : content
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output.trimmingTrailingWhitespace, forType: .string)
        
        return true
    }
    
    @discardableResult
    func copyToClipboard(source: CopySource) -> Bool {
        let involved: [MediaFile?] = switch source {
        case .fileA: [currentFile]
        case .fileB: [compareFile]
        case .both:  [currentFile, compareFile]
        }
        
        guard let shouldRemovePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Copy"
        ), let includeChecksum = PrivacyPreference.resolveChecksumDecision(
            actionName: "Copy", files: involved
        ) else { return false }
        
        let currentFile = includeChecksum ? self.currentFile : self.currentFile?.withoutChecksum()
        let compareFile = includeChecksum ? self.compareFile : self.compareFile?.withoutChecksum()
        
        func prepared(_ text: String?, _ file: MediaFile?) -> String? {
            guard let text, let file else { return nil }
            return shouldRemovePaths
            ? PrivacySanitizer.sanitize(text, fileURL: file.url).text
            : text
        }
        
        let content: String
        
        switch source {
        case .fileA:
            guard let s = prepared(outputStringForFile(currentFile), currentFile) else {
                return false
            }
            
            content = s
            
        case .fileB:
            guard let s = prepared(outputStringForFile(compareFile), compareFile) else {
                return false
            }
            
            content = s
            
        case .both:
            let a = prepared(outputStringForFile(currentFile), currentFile)?.trimmingTrailingWhitespace ?? ""
            let b = prepared(outputStringForFile(compareFile), compareFile)?.trimmingTrailingWhitespace ?? ""
            
            let separator =
            "\n\n" +
            String(repeating: "─", count: 60) +
            "\n\n"
            
            content = [a, b]
                .filter { !$0.isEmpty }
                .joined(separator: separator)
        }
        
        // "Both files" can legitimately end up with nothing in it — neither
        // file analysed yet, for instance. Writing an empty string to the
        // pasteboard would silently wipe whatever was already there, and then
        // report success for having done it.
        guard !content.isEmpty else { return false }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content.trimmingTrailingWhitespace, forType: .string)
        
        return true
    }
}
