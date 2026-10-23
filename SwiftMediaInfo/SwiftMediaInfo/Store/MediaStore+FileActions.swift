//
//  MediaStore+FileActions.swift
//  SwiftMediaInfo
//
//  File actions — reveal in Finder, copy path, copy file name, rename, move
//  to Trash — performed on the file itself rather than the report. The menus
//  and the rename sheet are in FileActions.swift; the confirmations are
//  hosted by ContentView.
//
//  Also the analysis cache's MediaInfo version check: cached analyses are
//  stamped with the mediainfo version, and one from an older version is
//  offered for re-analysis.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
internal import Combine

extension MediaStore {
    
    // MARK: - File actions
    //
    // Five things you can do to the file rather than to the report about it.
    // Three happen immediately; the two that change the disk are staged here
    // and confirmed by UI hosted on ContentView, because a context menu has
    // already closed by the time its action runs and cannot present anything.
    
    // MARK: Analysis cache version
    
    func resolveMediaInfoVersion() {
        // With tabs, several files can open in the same instant. One lookup
        // answers all of them; without this guard each started its own.
        guard mediaInfoVersion == nil, !isResolvingVersion else { return }

        isResolvingVersion = true

        Task {
            let found = await MediaEngine.fetchVersion()
            await MainActor.run {
                self.mediaInfoVersion = found
                self.isResolvingVersion = false
            }
        }
    }

    /// The same lookup, awaitable, and able to ignore what is already known.
    ///
    /// For Settings: the Tools page shows the version, the Advanced page's
    /// environment summary includes it, and Re-detect has to discard a cached
    /// answer, which `resolveMediaInfoVersion` above deliberately cannot.
    /// Both write the one `mediaInfoVersion` the analysis cache stamps its
    /// entries with.
    @discardableResult
    func loadMediaInfoVersion(force: Bool = false) async -> String? {
        if let mediaInfoVersion, !force { return mediaInfoVersion }
        
        let found = await MediaEngine.fetchVersion()
        mediaInfoVersion = found
        return found
    }
    
    /// Throw away the cached formats and analyse again, keeping the checksum.
    ///
    /// The bytes have not changed, so the digest is still correct — re-reading
    /// 50 GB to confirm what we already know would be the wrong kind of
    /// thorough.
    func reanalyseAfterUpgrade() {
        guard let url = staleAnalysisURL else { return }
        
        staleAnalysisURL = nil
        
        let digest = (currentFile?.url == url ? currentFile : compareFile)?.hashState.digest
        AnalysisCache.invalidateFormats(for: url, keepingDigest: digest)
        
        for tab in tabs where tab.file.url == url {
            reload(tabID: tab.id)
        }
    }
    
    /// Single dispatch point for every file action, from every surface.
    func perform(_ action: FileAction, on url: URL, isCompare: Bool) {
        // A second confirmation while one is already open would replace the
        // first mid-flight — you would be looking at a rename sheet for one
        // file and confirming a trash for another. The menu items are switched
        // off while a confirmation is up; this is the backstop for any path
        // that is not a menu.
        if pendingRename != nil || pendingTrash != nil {
            guard !action.modifiesFile else { return }
        }
        
        switch action {
        case .reveal:
            revealInFinder(url)
            
        case .copyPath:
            copyFilePath(url)
            
        case .copyFilename:
            copyFileName(url)
            
        case .rename:
            pendingRename = PendingFileAction(url: url, isCompare: isCompare)
            
        case .trash:
            pendingTrash = PendingFileAction(url: url, isCompare: isCompare)
        }
    }
    
    func revealInFinder(_ url: URL) {
        guard fileStillExists(url) else {
            reportMissing(url)
            return
        }
        
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    /// Copies the full path verbatim, ignoring the Copy privacy setting.
    ///
    /// That setting exists to keep paths out of *reports*. This action is a
    /// request for the path by name, and sanitising it would reduce it to the
    /// bare file name — which is what Copy Filename already does. Two menu
    /// items that produce the same string under one preference is a bug, not
    /// a privacy feature.
    func copyFilePath(_ url: URL) {
        writeToPasteboard(url.path(percentEncoded: false))
    }
    
    func copyFileName(_ url: URL) {
        writeToPasteboard(url.lastPathComponent)
    }
    
    // MARK: Rename
    
    /// Rename on disk, then re-read the file.
    ///
    /// Re-reading rather than patching the URL in place is deliberate.
    /// MediaInfo reports `CompleteName`, `FileName` and `FolderName` inside
    /// every output format, so keeping the cached Text, XML, HTML and JSON
    /// after a rename would leave five panes quoting a name that no longer
    /// exists. Renaming is rare; a second analysis is the honest cost.
    func commitRename(_ pending: PendingFileAction, to proposedName: String) {
        pendingRename = nil
        
        let source  = pending.url
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            presentError("A file needs a name.")
            return
        }
        
        // Not an error — the sheet disables Rename in this case, and arriving
        // here means something raced. Doing nothing is the right answer.
        guard trimmed != source.lastPathComponent else { return }
        
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            presentError("A file name can’t contain “/” or “:”.")
            return
        }
        
        guard fileStillExists(source) else {
            reportMissing(source)
            return
        }
        
        let destination = source
            .deletingLastPathComponent()
            .appendingPathComponent(trimmed)
        
        guard !fileStillExists(destination) else {
            presentError("There’s already an item named “\(trimmed)” in that folder. Choose a different name.")
            return
        }
        
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            presentError("“\(source.lastPathComponent)” couldn’t be renamed. \(error.localizedDescription)")
            return
        }
        
        replaceInRecents(source, with: destination)
        replaceFavorite(source, with: destination)
        
        // Inside a folder tab, the list entry is renamed and, if it was the
        // file on screen, re-read under its new name.
        let inFolders = !folderTabsContaining(source).isEmpty
        if inFolders { replaceFolderItem(source, with: destination) }
        
        // Re-read in place, so the renamed file keeps its tab and position.
        if let tab = tabs.first(where: { $0.folder == nil && $0.file.url == source.standardized }) {
            reload(tabID: tab.id, with: destination)
        } else if !inFolders {
            openURL(destination)
        }
    }
    
    // MARK: Trash
    
    /// Move to the Trash and clear the pane that held it.
    ///
    /// `trashItem` rather than `removeItem`: this is a metadata viewer, and
    /// nothing in it should be able to destroy a file outright. The Trash is
    /// the undo.
    func commitTrash(_ pending: PendingFileAction) {
        pendingTrash = nil
        
        let url = pending.url
        
        guard fileStillExists(url) else {
            reportMissing(url)
            return
        }
        
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            // Common on volumes without a Trash — a network share, or some
            // external drives. The system's own message says more than a
            // generic failure would.
            presentError("“\(url.lastPathComponent)” couldn’t be moved to the Trash. \(error.localizedDescription)")
            return
        }
        
        removeFromRecents(url)
        
        // A folder tab keeps going without it: the entry leaves the list and
        // the next file is shown.
        replaceFolderItem(url, with: nil)
        
        // Every other tab holding it goes, whichever side of a comparison it
        // was on.
        for tab in tabs where tab.folder == nil && tab.file.url == url.standardized {
            closeTab(tab.id)
        }
        
        // Compare Mode with nothing on either side is an empty split view with
        // no way to explain itself. Fall back to the single-file empty state,
        // which at least says what to do next.
        if isCompareMode, currentFile == nil, compareFile == nil {
            isCompareMode     = false
            showDiffHighlight = false
        }
        
        resetDropState()
        refreshComparison()
        updateWindowTitle()
    }
    
    // MARK: File-action helpers
    
    private func fileStillExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
    
    /// Show an error one turn of the run loop later.
    ///
    /// Every failure path here runs while a sheet or alert is being dismissed —
    /// the rename sheet closes before the rename is attempted, and the trash
    /// confirmation closes before the trash is attempted. Raising a second
    /// alert in that same frame is how an error message ends up never
    /// appearing at all. The hop lets the first presentation finish first.
    private func presentError(_ message: String) {
        Task { @MainActor in
            fileActionError = message
        }
    }
    
    private func reportMissing(_ url: URL) {
        presentError("“\(url.lastPathComponent)” is no longer where it was. It may have been moved, renamed, or deleted from another app.")
    }
}
