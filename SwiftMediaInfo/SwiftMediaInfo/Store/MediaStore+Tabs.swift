//
//  MediaStore+Tabs.swift
//  SwiftMediaInfo
//
//  Tabs: the tab model (DocumentTab, and the empty New Tab placeholder),
//  opening several items at once with the drop rules, selecting, closing and
//  reordering, folder tabs and stepping through their files, and dragging a
//  tab. The tab bar itself is FileTabBar.
//
//  Every open file lives in a tab, and exactly one tab is on screen. The tab
//  list in MediaStore is the source of truth; `currentFile` reads and writes
//  the selected tab's file, which is why most of the app did not have to learn
//  that tabs exist.
//
//  WHAT A TAB OWNS
//
//  Its file, and through the file's session id, that file's loader and hash.
//  Closing a tab stops both. Switching tabs does not stop anything — a tab in
//  the background keeps whatever it has loaded and, when the files on screen
//  are done, finishes loading the rest (see `scheduleLoaders`).
//
//  COMPARE MODE
//
//  File A is the selected tab and File B is another tab (`compareTabID`).
//  Either can be closed on its own: its pane empties and the comparison waits
//  for a replacement, ending only when both sides are gone.
//

import SwiftUI
import AppKit

// MARK: - Tab

/// The empty tab ⌘T opens: a place in the tab bar, not a file.
struct NewTabPlaceholder: Equatable {
    let id = UUID()
    /// Where it sits among `tabs` — before the tab at this index.
    var index: Int
}

struct DocumentTab: Identifiable {
    /// The tab's own identity. Distinct from the file's id, because reloading
    /// a file — retry, rename, re-analysis — gives it a new session id while
    /// it stays in the same tab.
    let id = UUID()
    var file: MediaFile
    
    /// Set for a folder tab: the folder and its media files. `file` is then
    /// whichever of those files is selected — the one on screen.
    var folder: FolderContents? = nil
    
    /// What the tab bar shows: the folder's name for a folder tab.
    var title: String { folder?.name ?? file.fileName }
    
    /// The URL that identifies the tab — the folder for a folder tab — used
    /// to notice that something being opened is already open.
    var identityURL: URL { folder?.url ?? file.url }
}

extension MediaStore {

    // MARK: - Selection

    /// Everything that depends on which file is on screen.
    ///
    /// Called from `selectedTabID`'s observer, so it runs however the
    /// selection changed — a click, a keyboard shortcut, a file opening, or
    /// the selected tab closing.
    func selectedTabDidChange() {
        refreshComparison()
        updateWindowTitle()

        // The newly visible file gets the machine; whatever was on screen
        // before drops back to the background slot.
        scheduleLoaders()
        startDeferredHashesForVisibleFiles()
        loadFormatIfNeeded(viewMode)

        // Matches belong to the report they were counted in.
        searchMatchIndex = 0
        
        // An open Quick Look panel follows the tab on screen.
        PreviewRouter.screenChanged(to: isCompareMode ? nil : currentFile?.url)
    }

    /// Show a tab. In Compare Mode the clicked tab becomes File A — and
    /// clicking File B's own tab swaps the two sides, since a file cannot be
    /// compared with itself.
    func selectTab(_ id: UUID) {
        if id == newTab?.id {
            if isCompareMode { exitCompareMode() }
            selectedTabID = id
            return
        }
        guard tabs.contains(where: { $0.id == id }) else { return }
        
        if isCompareMode, id == compareTabID {
            if selectedTabID == nil {
                // File A's pane is empty: File B moves across to fill it.
                compareTabID = nil
                selectedTabID = id
            } else {
                swapCompareFiles()
            }
            return
        }
        
        selectedTabID = id
    }
    
    /// ⌘-click: make this tab File B, entering Compare Mode if needed.
    func toggleCompare(withTab id: UUID) {
        if isCompareMode, id == compareTabID {
            exitCompareMode()
        } else if selectedTabID == nil {
            selectedTabID = id
        } else {
            compare(withTab: id)
        }
    }
    
    /// ⌃⇥ and ⌃⇧⇥. Wraps at both ends, as tabs do everywhere else on macOS.
    /// In Compare Mode File B's tab is stepped over: it is already showing.
    func selectAdjacentTab(_ offset: Int) {
        let candidates = tabStripIDs.filter { !isCompareMode || $0 != compareTabID }
        guard !candidates.isEmpty else { return }
        
        let current = candidates.firstIndex { $0 == selectedTabID } ?? 0
        let next = (current + offset % candidates.count + candidates.count) % candidates.count
        selectTab(candidates[next])
    }
    
    // MARK: - New Tab (⌘T)
    //
    // An empty tab showing the start screen — recent files, favorites — as in
    // Safari. It is not a DocumentTab: every DocumentTab holds a file, and
    // hundreds of lines rely on that. It is a marker for a place in the bar,
    // kept in step as tabs open and close around it. Opening a file from it
    // puts the file in its place; ⌘W closes it like any other tab.
    
    /// Every tab in the bar's order, the New Tab included.
    var tabStripIDs: [UUID] {
        var ids = tabs.map(\.id)
        if let newTab { ids.insert(newTab.id, at: min(newTab.index, ids.count)) }
        return ids
    }
    
    var isNewTabSelected: Bool {
        newTab != nil && selectedTabID == newTab?.id
    }
    
    func openNewTab() {
        if isCompareMode { exitCompareMode() }
        
        // One is enough: a second ⌘T goes back to it.
        if let newTab {
            selectedTabID = newTab.id
            return
        }
        
        let placeholder = NewTabPlaceholder(index: selectedTabIndex.map { $0 + 1 } ?? tabs.endIndex)
        newTab = placeholder
        selectedTabID = placeholder.id
    }
    
    private func closeNewTab() {
        guard let placeholder = newTab else { return }
        let index = min(placeholder.index, tabs.count)
        newTab = nil
        
        if selectedTabID == placeholder.id {
            // The tab to the right takes its place, as with any other tab.
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id
            : (index > 0 ? tabs[index - 1].id : nil)
        }
        updateWindowTitle()
    }
    
    // MARK: - Closing

    func closeTab(_ id: UUID) {
        if id == newTab?.id {
            closeNewTab()
            return
        }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        // Keep the New Tab where it was relative to its neighbours.
        if let placeholder = newTab, index < placeholder.index {
            newTab?.index = placeholder.index - 1
        }
        
        cancelWork(for: tabs[index].file.id)
        
        if isCompareMode && (id == selectedTabID || id == compareTabID) {
            // A side of the comparison is closing. Its pane empties rather
            // than being filled by a neighbour — a neighbour you never chose
            // appearing as File A would be a comparison you did not ask for.
            if id == compareTabID { compareTabID = nil }
            if id == selectedTabID { selectedTabID = nil }
            tabs.remove(at: index)
            
            // Nothing left on either side: there is no comparison to keep.
            if selectedTabID == nil, compareTabID == nil {
                exitCompareMode()
                selectedTabID = tabs.indices.contains(index)
                ? tabs[index].id
                : tabs.last?.id
            }
            
        } else if id == selectedTabID {
            // The tab to the right takes its place, as in Safari and Finder —
            // falling back to the left when it was the last one.
            let neighbour = tabs.indices.contains(index + 1)
            ? tabs[index + 1].id
            : (index > 0 ? tabs[index - 1].id : nil)
            
            tabs.remove(at: index)
            selectedTabID = neighbour
        } else {
            tabs.remove(at: index)
        }
        
        refreshComparison()
        updateWindowTitle()
    }
    
    func closeTabs(toTheRightOf id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTabs(tabs[(index + 1)...].map(\.id), keeping: id)
    }

    func closeTabs(toTheLeftOf id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTabs(tabs[..<index].map(\.id), keeping: id)
    }

    func closeOtherTabs(than id: UUID) {
        closeTabs(tabs.filter { $0.id != id }.map(\.id), keeping: id)
    }

    func closeAllTabs() {
        if isCompareMode { exitCompareMode() }
        closeNewTab()
        for tab in tabs { closeTab(tab.id) }
    }

    /// Close several tabs at once, leaving `anchor` selected if the selection
    /// was among them. Without this, closing tabs one by one would walk the
    /// selection across each neighbour in turn.
    private func closeTabs(_ ids: [UUID], keeping anchor: UUID) {
        guard !ids.isEmpty else { return }

        if let selectedTabID, ids.contains(selectedTabID) {
            self.selectedTabID = anchor
        }

        for id in ids { closeTab(id) }
    }

    // MARK: - Opening

    /// "New Tab to the Right": an empty New Tab, placed immediately to the
    /// right of the tab that was right-clicked. If a New Tab is already open
    /// it moves there rather than a second one appearing — there is only ever
    /// one, as with ⌘T.
    func openNewTab(toTheRightOf id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if isCompareMode { exitCompareMode() }

        if newTab != nil {
            newTab?.index = index + 1
        } else {
            newTab = NewTabPlaceholder(index: index + 1)
        }
        selectedTabID = newTab?.id
        updateWindowTitle()
    }

    /// Middle-click on a recent file: open it in a tab without switching to
    /// it, so several can be queued up from the list in one go.
    ///
    /// Recent Files is left in its order — moving the file to the front would
    /// shuffle the list under the pointer between clicks. If nothing is on
    /// screen and nothing is selected, there is nothing to stay on, but the
    /// tab still opens in the background: the empty screen, and the rest of
    /// its list, stay where they are.
    func openInBackgroundTab(_ url: URL) {
        let normalised = url.standardized
        guard !tabs.contains(where: { $0.identityURL == normalised }) else { return }
        
        insertTab(for: normalised, at: selectedTabIndex.map { $0 + 1 } ?? tabs.endIndex)
    }
    
    // MARK: - Opening several items
    
    /// An explicit "open these": the Open dialog, Finder's Open, the Dock.
    /// Every item gets a tab of its own — a folder becomes one folder tab —
    /// in the order given, next to the selected tab. The first one is shown.
    /// Items already open are switched to rather than opened twice.
    func openTabs(_ urls: [URL]) {
        let unique = Self.unique(urls)
        guard !unique.isEmpty else { return }
        
        var position = selectedTabIndex.map { $0 + 1 } ?? tabs.endIndex
        var firstID: UUID?
        
        for url in unique {
            if let existing = tabs.first(where: { $0.identityURL == url }) {
                firstID = firstID ?? existing.id
                continue
            }
            
            // The first file takes the New Tab's place, if it is showing.
            let replacing = firstID == nil && isNewTabSelected
            if replacing, let placeholder = newTab { position = placeholder.index }
            let id = insertTab(for: url, at: position, replacingNewTab: replacing)
            position += 1
            firstID = firstID ?? id
        }
        
        for url in unique.reversed() { addToRecentFiles(url) }
        
        if let firstID { selectTab(firstID) }
    }
    
    /// Files dropped on the window, a pane or the Dock:
    ///
    ///   • one file   → opens in a tab (Option still means "compare with this")
    ///   • two files  → both open, side by side in Compare Mode
    ///   • three+     → a tab each
    ///   • a folder   → one folder tab, wherever it appears in the drop
    func openDropped(_ urls: [URL]) {
        let unique = Self.unique(urls)
        
        switch unique.count {
        case 0:
            return
        case 1:
            openDropped(unique[0])
        case 2 where !unique.contains(where: FolderScanner.isDirectory):
            openURL(unique[0])
            openCompareURL(unique[1])
        default:
            openTabs(unique)
        }
    }
    
    /// Standardised, existing, and each only once, in the order given.
    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .filter { seen.insert($0).inserted }
    }
    
    /// Make a tab for a file or folder at a position, without selecting it.
    @discardableResult
    /// `replacingNewTab`: when the New Tab is showing, the file opens in its
    /// place and the New Tab goes. Only for opens that then show the file —
    /// a background open from the start screen leaves the New Tab in place.
    func insertTab(for url: URL, at position: Int, replacingNewTab: Bool = false) -> UUID {
        var position = min(max(position, 0), tabs.endIndex)
        
        if let placeholder = newTab {
            if replacingNewTab && selectedTabID == placeholder.id {
                position = min(placeholder.index, tabs.endIndex)
                newTab = nil
            } else if position <= placeholder.index {
                newTab?.index = placeholder.index + 1
            }
        }
        
        if FolderScanner.isDirectory(url) {
            return insertFolderTab(url, at: position)
        }
        
        let tab = DocumentTab(file: Self.placeholder(for: url))
        tabs.insert(tab, at: position)
        beginAnalysis(of: tab.file, isCompare: false)
        return tab.id
    }
    
    // MARK: - Folder tabs
    
    /// A folder opens as one tab. Its files are listed in the background;
    /// the first one is analysed as soon as the list is known.
    private func insertFolderTab(_ url: URL, at position: Int) -> UUID {
        // The folder itself is never analysed — see FolderContents.swift — so
        // its placeholder only carries the "loading" look while it is read.
        var tab = DocumentTab(file: Self.placeholder(for: url))
        tab.folder = FolderContents(url: url)
        tabs.insert(tab, at: position)
        
        let tabID = tab.id
        
        Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) {
                FolderScanner.mediaFiles(in: url)
            }.value
            
            self?.finishScanning(tabID: tabID, items: items)
        }
        
        return tabID
    }
    
    private func finishScanning(tabID: UUID, items: [URL]) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        
        tabs[index].folder?.items = items
        tabs[index].folder?.isScanning = false
        
        if let first = items.first {
            reload(tabID: tabID, with: first)
        } else {
            // Nothing to show. The folder view says so; the tab stops spinning.
            tabs[index].file.isLoading = false
        }
    }
    
    /// Whether there is a report on screen to copy, share, export or act on.
    /// False for an empty folder tab, whose "file" is the folder itself.
    var hasOpenReport: Bool {
        guard currentFile != nil else { return isCompareMode && compareFile != nil }
        return currentFolder?.items.isEmpty != true
    }
    
    /// The folder of the selected tab, when it is a folder tab.
    var currentFolder: FolderContents? {
        guard let index = selectedTabIndex else { return nil }
        return tabs[index].folder
    }
    
    /// Show another file from a folder tab's list, in the same tab.
    func selectFolderItem(_ url: URL, inTab tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              tab.folder != nil,
              tab.file.url != url else { return }
        reload(tabID: tabID, with: url)
    }
    
    /// The next or previous file in the selected folder tab's list.
    func selectAdjacentFolderItem(_ offset: Int) {
        guard let index = selectedTabIndex,
              let folder = tabs[index].folder,
              !folder.items.isEmpty else { return }
        
        let current = folder.items.firstIndex(of: tabs[index].file.url) ?? 0
        let next = min(max(current + offset, 0), folder.items.count - 1)
        selectFolderItem(folder.items[next], inTab: tabs[index].id)
    }
    
    /// A file inside a folder tab was renamed or trashed: keep the list true.
    /// Returns the tabs whose shown file was affected.
    func folderTabsContaining(_ url: URL) -> [UUID] {
        tabs.filter { $0.folder?.items.contains(url.standardizedFileURL) == true }.map(\.id)
    }
    
    func replaceFolderItem(_ old: URL, with new: URL?) {
        let old = old.standardizedFileURL
        
        for index in tabs.indices {
            guard var folder = tabs[index].folder,
                  let position = folder.items.firstIndex(of: old) else { continue }
            
            let wasShown = tabs[index].file.url == old
            
            if let new {
                folder.items[position] = new.standardizedFileURL
            } else {
                folder.items.remove(at: position)
            }
            tabs[index].folder = folder
            
            guard wasShown else { continue }
            
            if let new {
                reload(tabID: tabs[index].id, with: new)
            } else if !folder.items.isEmpty {
                let next = folder.items[min(position, folder.items.count - 1)]
                reload(tabID: tabs[index].id, with: next)
            } else {
                cancelWork(for: tabs[index].file.id)
                tabs[index].file = MediaFile(url: folder.url)
                tabs[index].file.isLoading = false
            }
        }
    }
    
    // MARK: - Dragging a tab
    
    /// Start of a tab drag. The drag carries the tab's file, so dropping it on
    /// the Dock or another app opens the original; within the tab bar the same
    /// drag reorders.
    ///
    /// SwiftUI says when a drag starts but never when it ends — a drop on
    /// another app or on nothing at all reports nothing back. So the end is
    /// detected the one reliable way available: the mouse button is up again.
    func beginTabDrag(_ id: UUID) {
        draggingTabID = id
        FileDropSupport.isTabDragActive = true
        
        tabDragWatcher?.cancel()
        tabDragWatcher = Task { [weak self] in
            // A short grace period: the button is still down when this runs.
            try? await Task.sleep(nanoseconds: 300_000_000)
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.endTabDrag()
        }
    }
    
    func endTabDrag() {
        tabDragWatcher?.cancel()
        tabDragWatcher = nil
        draggingTabID = nil
        FileDropSupport.isTabDragActive = false
    }
    
    // MARK: - Reordering

    /// Move a tab to sit where `target` is now. Used while a tab is dragged
    /// across the bar, so it is called repeatedly and must be cheap when
    /// nothing changes.
    func moveTab(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }

        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    // MARK: - Starting a comparison
    
    /// The Compare button and its shortcut.
    ///
    /// With other tabs open or recent files to hand, the obvious File B is one
    /// of them, so the choice is offered as a list — with "Choose a File…"
    /// still at the bottom. With neither, it goes straight to the file picker.
    func beginCompare() {
        if isCompareMode {
            exitCompareMode()
            return
        }
        
        if currentFile == nil {
            openFilePicker()
            guard currentFile != nil else { return }
        }
        
        if tabs.count > 1 || !favoriteCompareCandidates.isEmpty || !recentCompareCandidates.isEmpty {
            showComparePicker = true
        } else {
            openCompareFilePicker()
        }
    }
    
    /// Tabs that could be File B for the selected tab.
    var compareCandidates: [DocumentTab] {
        tabs.filter { $0.id != selectedTabID }
    }
    
    /// Recent files worth offering for a comparison: ones that still exist
    /// and are not already open in a tab — those are offered as tabs.
    var recentCompareCandidates: [URL] {
        let open = Set(tabs.map { $0.identityURL.standardized })
        return recentFileURLs
            .map(\.standardized)
            .filter { !open.contains($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }
    
    /// Favorites worth offering for a comparison: files that still exist and
    /// are not already open in a tab. Folders are left out, as in File ›
    /// Favorites — there is nothing to compare in one.
    var favoriteCompareCandidates: [URL] {
        let open = Set(tabs.map { $0.identityURL.standardized })
        return favoriteURLs
            .map(\.standardized)
            .filter { !open.contains($0) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }
    }
    
    /// Compare a tab (as File A) with a file from disk (as File B), which
    /// opens in a tab of its own.
    func compare(tab id: UUID, withFileAt url: URL) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        makeFileA(id)
        openCompareURL(url)
    }
    
    /// Compare a tab (as File A) with a file chosen in a panel.
    func compareWithPickedFile(tab id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        makeFileA(id)
        openCompareFilePicker()
    }
    
    /// Put a tab on File A's side directly — without `selectTab`'s rule that
    /// clicking File B swaps the sides, which is right for a click and wrong
    /// for "compare this tab with…".
    private func makeFileA(_ id: UUID) {
        if compareTabID == id { compareTabID = nil }
        selectedTabID = id
    }
    
    // MARK: - Queries for the tab menu

    func hasTabs(toTheRightOf id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        return index < tabs.count - 1
    }

    func hasTabs(toTheLeftOf id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0
    }
}
