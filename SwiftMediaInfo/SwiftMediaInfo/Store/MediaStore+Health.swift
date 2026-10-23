//
//  MediaStore+Health.swift
//  SwiftMediaInfo
//
//  Opening Media Health, from File Actions, the File menu or ⌘⇧H. The checks
//  are in MediaHealth.swift; the window is MediaHealthView, shown by
//  ContentView when `healthTarget` is set.
//

import Foundation

/// Which pane Media Health reports on. Its own identity, so the window can be
/// reopened for the same file straight after closing it.
struct HealthTarget: Identifiable, Equatable {
    let id = UUID()
    var isCompare: Bool
}

extension MediaStore {
    
    /// Whether there is a file to check.
    var canCheckHealth: Bool {
        currentFile != nil || compareFile != nil
    }
    
    /// Opens Media Health for File A (or the only file), or File B. In
    /// Compare Mode the window has its own File A / File B switch, so ⌘⇧H
    /// doesn't have to guess which file you meant.
    func showMediaHealth(isCompare: Bool = false) {
        let isCompare = isCompare && compareFile != nil || currentFile == nil
        guard (isCompare ? compareFile : currentFile) != nil else { return }
        
        // The checks read the parsed tracks, which come from the JSON report.
        // Usually already loaded; if not, this puts it at the front of the
        // queue and the window shows a spinner until it arrives.
        loadFormatIfNeeded(.easy, isCompare: isCompare)
        healthTarget = HealthTarget(isCompare: isCompare)
    }
    
    func copyHealthReport(_ report: HealthReport, from fileURL: URL?, asMarkdown: Bool) {
        copySnippet(asMarkdown ? report.markdown : report.plainText, from: fileURL)
    }
}
