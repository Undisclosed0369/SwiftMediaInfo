//
//  MediaStore+Open.swift
//  SwiftMediaInfo
//
//  Opening one file: the Open panel, a single dropped file (Option-drop
//  compares), opening a URL into the current tab — from the analysis cache
//  when the file is unchanged — and starting its analysis; closing, reloading,
//  retrying and cancelling; File B and leaving Compare Mode. Opening several
//  items at once, and the multi-item drop rules, are in MediaStore+Tabs.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
internal import Combine

extension MediaStore {
    
    // MARK: - Open (unified file + folder picker)
    
    /// - Parameter directory: where the dialog starts — the website's Open in
    ///   SwiftMediaInfo button passes the folder of a likely match.
    func openFilePicker(startingIn directory: URL? = nil) {
        let panel = NSOpenPanel()
        if let directory { panel.directoryURL = directory }
        // Several at once: each opens in its own tab, a folder as a folder
        // tab.
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = []    // empty = allow everything
        panel.treatsFilePackagesAsDirectories = false
        
        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }
        
        openTabs(panel.urls)
    }
    
    /// Handles a file dropped while NOT in Compare Mode.
    ///
    /// Holding Option opens the dropped file as File B and enters Compare
    /// Mode, rather than replacing what is already open — comparing in one
    /// gesture.
    ///
    /// The modifier is read here, at the moment of the drop, rather than
    /// trusting the flag the highlight uses. That flag is updated by an event
    /// monitor and could in principle lag by a frame — and a drop that does
    /// the opposite of what the overlay just promised is far worse than a
    /// highlight that is briefly stale.
    func openDropped(_ url: URL) {
        let wantsCompare = NSEvent.modifierFlags.contains(.option)
        
        if wantsCompare, isOptionCompareAvailable {
            openCompareURL(url)
        } else {
            openURL(url)
        }
    }
    
    /// Open a file in a tab of its own, next to the one selected.
    ///
    /// A file already open is switched to rather than opened twice. Two tabs
    /// showing the same report would be two copies to keep in step for no
    /// gain, and "which one did I just open?" has no good answer.
    func openURL(_ url: URL) {
        let normalised = url.standardizedFileURL
        
        addToRecentFiles(normalised)
        
        // A folder already open as a folder tab counts too.
        if let existing = tabs.first(where: { $0.identityURL == normalised }) {
            selectTab(existing.id)
            return
        }
        
        // Files and folders alike — a folder becomes a folder tab.
        let id = insertTab(for: normalised, at: selectedTabIndex.map { $0 + 1 } ?? tabs.endIndex, replacingNewTab: true)
        selectedTabID = id
    }
    
    /// Analyse a tab's file again from scratch, in the same tab.
    ///
    /// Used by retry, by re-analysis after a mediainfo upgrade, and by rename,
    /// which passes the file's new location. Reopening through `openURL`
    /// would either switch to the tab and do nothing, or — for a rename —
    /// leave the old tab behind pointing at a file that no longer exists.
    func reload(tabID: UUID, with url: URL? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        
        cancelWork(for: tabs[index].file.id)
        
        let target = (url ?? tabs[index].file.url).standardized
        let placeholder = Self.placeholder(for: target)
        
        tabs[index].file = placeholder
        refreshComparison()
        updateWindowTitle()
        
        beginAnalysis(of: placeholder, isCompare: false)
    }
    
    /// A file that has not been read yet. Its id is the analysis session's
    /// identity: every result arriving later must carry it or it is
    /// discarded as stale.
    static func placeholder(for url: URL) -> MediaFile {
        var file = MediaFile(url: url)
        file.isLoading = true
        return file
    }
    
    /// Cache first, then mediainfo for whatever the cache did not have, then
    /// the checksum.
    func beginAnalysis(of file: MediaFile, isCompare: Bool) {
        resolveMediaInfoVersion()
        
        let missing = applyCachedAnalysis(for: file.url, sessionID: file.id, isCompare: isCompare)
        startLoader(for: file.url, sessionID: file.id, isCompare: isCompare, formats: missing)
        
        // A checksum reads the whole file. Opening ten files in background
        // tabs must not start ten of those at once, so a file that is not on
        // screen waits until it is.
        if isVisible(file.id) {
            beginHashingIfNeeded(for: file.url, sessionID: file.id, isCompare: isCompare)
        } else {
            deferredHashes[file.id] = file.url
        }
    }
    
    private func isVisible(_ sessionID: UUID) -> Bool {
        currentFile?.id == sessionID || (isCompareMode && compareFile?.id == sessionID)
    }
    
    /// Called whenever what is on screen changes.
    func startDeferredHashesForVisibleFiles() {
        for (sessionID, url) in deferredHashes where isVisible(sessionID) {
            deferredHashes[sessionID] = nil
            beginHashingIfNeeded(for: url, sessionID: sessionID, isCompare: compareFile?.id == sessionID)
        }
    }
    
    /// Fill a file from whatever the cache holds for it, and return the
    /// formats still to be fetched — all five when nothing is cached.
    ///
    /// Partial entries count. Formats are cached one by one as they arrive, so
    /// a file closed halfway through its background pass reopens with what it
    /// had and fetches only the rest.
    ///
    /// Tracks are re-parsed from the cached JSON rather than stored separately:
    /// MediaTrack holds tuples, which are not Codable, and one parse of a
    /// string already in memory is far cheaper than the subprocess it replaces.
    private func applyCachedAnalysis(for url: URL, sessionID: UUID, isCompare: Bool) -> [MediaFormat] {
        guard let entry = AnalysisCache.entry(for: url) else { return MediaFormat.allCases }

        // A cached JSON that produced no tracks is not worth trusting over a
        // fresh run — it more likely means a truncated write than a file with
        // no streams.
        var tracks: [MediaTrack] = []
        var json = entry.rawJSON
        if let cachedJSON = json {
            tracks = MediaEngine.parseTracks(from: cachedJSON)
            if tracks.isEmpty { json = nil }
        }

        let cached: [MediaFormat: String] = [
            .json:    json,
            .text:    entry.rawText,
            .rawText: entry.rawTextFull,
            .html:    entry.rawHTML,
            .xml:     entry.rawXML
        ].compactMapValues { $0 }

        guard !cached.isEmpty else { return MediaFormat.allCases }

        // Still "analysing" when the cache has other tabs but not this one —
        // the first fetch to land will clear it, and that fetch is this tab's.
        let coversCurrentTab = cached[viewMode.format] != nil

        update(sessionID: sessionID, isCompare: isCompare) { file in
            for (format, content) in cached {
                file.apply(.success(content), tracks: tracks, for: format)
            }
            if coversCurrentTab { file.isLoading = false }
        }

        // Checked after the file is on screen, so the prompt appears over
        // content rather than instead of it.
        if entry.isStale(against: mediaInfoVersion) {
            staleAnalysisURL = url
        }

        updateWindowTitle()

        return MediaFormat.allCases.filter { cached[$0] == nil }
    }
    
    /// ⌘W: close the selected tab.
    ///
    /// In Compare Mode that is File A. Its pane empties and the comparison
    /// waits for a new File A, rather than ending — closing one side should
    /// not throw away the other. With File A already gone, ⌘W closes File B.
    func closeFile() {
        if let selectedTabID {
            closeTab(selectedTabID)
        } else if isCompareMode, let compareTabID {
            closeTab(compareTabID)
        } else if isCompareMode {
            exitCompareMode()
        } else if let last = tabs.last {
            // Tabs opened in the background from the empty screen, none of
            // them showing: ⌘W closes them from the right, and only then the
            // window.
            closeTab(last.id)
        }
    }
    
    /// Re-run analysis for a file that failed. Used by the retry affordance.
    func retry(isCompare: Bool) {
        if isCompare {
            if let compareTabID { reload(tabID: compareTabID) }
        } else if let selectedTabID {
            reload(tabID: selectedTabID)
        }
    }
    
    /// Re-run analysis after the MediaInfo tool has been installed.
    ///
    /// Both sides are retried, because in Compare Mode both failed for
    /// the same reason and fixing one while leaving the other showing "MediaInfo
    /// isn't installed" would be worse than fixing neither. Does nothing when no
    /// file is open, so it is safe to call unconditionally after any install.
    func retryAfterDependencyInstall() {
        if currentFile != nil {
            retry(isCompare: false)
        }
        
        if isCompareMode, compareFile != nil {
            retry(isCompare: true)
        }
    }
    
    /// Stop an in-progress analysis at the user's request.
    ///
    /// The file stays open so it can be retried without re-picking it. The
    /// mediainfo process itself is terminated by MediaEngine's cancellation
    /// handling — cancelling the Swift task is what triggers that.
    func cancelLoading(isCompare: Bool = false) {
        if isCompare {
            cancelCompareTasks()
        } else {
            cancelCurrentTasks()
        }
        
        let reference: MediaFile? = isCompare ? compareFile : currentFile
        guard let sessionID = reference?.id else { return }
        
        update(sessionID: sessionID, isCompare: isCompare) { file in
            file.isLoading        = false
            file.isLoadingText    = false
            file.isLoadingRawText = false
            file.isLoadingJSON    = false
            file.isLoadingHTML    = false
            file.isLoadingXML     = false
            file.loadError        = .cancelled
        }
    }
    
    // MARK: - Open (compare file)
    
    func openCompareFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.movie, .audio, .data, .item]
        panel.message                 = "Choose a second file to compare"
        
        guard panel.runModal() == .OK,
              let url = panel.urls.first else {
            return
        }
        
        openCompareURL(url)
    }
    
    /// Make `url` File B, in a tab of its own.
    ///
    /// A file that is already open is used where it is. Otherwise it opens in
    /// a new tab just after File A — without taking the selection, because
    /// the selected tab is File A.
    func openCompareURL(_ url: URL) {
        let normalised = url.standardized
        
        resetDropState()
        
        // File B is as much a file the user opened as File A — a Finder
        // "Compare in SwiftMediaInfo" should leave both in Recent Files.
        addToRecentFiles(normalised)
        
        if let existing = tabs.first(where: { $0.identityURL == normalised }) {
            compare(withTab: existing.id)
            return
        }
        
        let id = insertTab(for: normalised, at: selectedTabIndex.map { $0 + 1 } ?? tabs.endIndex)
        compare(withTab: id)
    }
    
    /// Enter (or stay in) Compare Mode with this tab as File B.
    ///
    /// The file on the other side is the selected tab. Comparing a tab with
    /// itself means nothing, so picking the selected tab as File B is ignored.
    func compare(withTab id: UUID) {
        guard id != selectedTabID, tabs.contains(where: { $0.id == id }) else { return }
        
        compareTabID  = id
        isCompareMode = true
        refreshComparison()
        scheduleLoaders()
        startDeferredHashesForVisibleFiles()
        loadFormatIfNeeded(viewMode, isCompare: true)
    }
    
    /// Compare two tabs: `first` as File A, `second` as File B.
    func compare(tab first: UUID, with second: UUID) {
        guard first != second else { return }
        if compareTabID == first { compareTabID = nil }
        selectedTabID = first
        compare(withTab: second)
    }
    
    /// Leave Compare Mode. File B's tab stays open — it is a tab like any
    /// other, and closing it is a separate decision.
    func exitCompareMode() {
        resetDropState()
        
        // With File A's pane empty, the file left on screen is File B.
        if selectedTabID == nil, let compareTabID {
            selectedTabID = compareTabID
        }
        
        compareTabID     = nil
        isCompareMode    = false
        showDiffHighlight = false
        refreshComparison()
    }
}
