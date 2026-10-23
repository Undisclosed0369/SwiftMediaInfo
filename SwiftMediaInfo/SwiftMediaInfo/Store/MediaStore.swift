//
//  MediaStore.swift
//  SwiftMediaInfo
//
//  The app's one store: open tabs and their files, Compare Mode, the view
//  on screen, and every preference the main window reads. One instance,
//  created by MediaInfoMacApp and handed to every window as an environment
//  object.
//
//  It is spread over files by job, each an extension:
//    MediaStore+Open        opening files and folders, File B
//    MediaStore+Tabs        tabs, folder tabs, New Tab
//    MediaStore+Favorites   starred files and folders
//    MediaStore+Checksums   SHA-256 hashing
//    MediaStore+FileActions rename, trash, reveal…, the analysis cache's
//                           MediaInfo version check
//    MediaStore+Copy        copying values, reports and overviews
//    MediaStore+Export      every export format, Export All, ZIP
//    MediaStore+Share       review, sanitising and uploading
//    MediaStore+Health      opening Media Health
//  Stored properties must live here (Swift doesn't allow them in
//  extensions), which is why some state is declared here beside a note
//  pointing to the file that uses it. This file also holds loading (one
//  FormatLoader per file), the comparison, appearance, zoom, search and
//  recent files.
//
//  RULES THE REST OF THE APP RELIES ON
//
//  • Results are matched to files by session id (`MediaFile.id`), never by
//    URL, through `update(sessionID:)` — a late result can't land on a file
//    opened since, even the same file opened twice.
//  • `currentFile` is the selected tab's file (File A in Compare Mode) and
//    `compareFile` is File B's tab; both read and write through `tabs`.
//  • The comparison rebuilds itself when either side's content changes.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
internal import Combine

enum AppearanceMode: String {
    case system, light, dark
}

/// Which tab the app opens on.
///
/// Stored as either the sentinel "last" — restore whatever was in use — or a
/// ViewMode raw value to open on every time. A sentinel rather than a separate
/// boolean, so there is exactly one value to read and no way for two settings
/// to disagree about what should happen.
enum LaunchPreference {
    static let key = "launchViewMode"
    static let restoreLastValue = "last"
    
    @MainActor
    static var stored: String {
        UserDefaults.standard.string(forKey: key) ?? restoreLastValue
    }
}

@MainActor
final class MediaStore: ObservableObject {
    
    init() {
        // Runs before any @AppStorage default can win. See the note on the
        // function for why the order matters.
        Self.migrateBackgroundPreferenceIfNeeded()
        
        applyAppearance(AppearanceMode(rawValue: savedAppearance) ?? .system)
        
        // Which tab to open on.
        //
        // "launchViewMode" holds either "last" (restore whatever was in use) or
        // a specific ViewMode raw value to open on every time. "lastUsedViewMode"
        // is written on every tab switch by the didSet below.
        let launchPreference = UserDefaults.standard.string(forKey: LaunchPreference.key)
        ?? LaunchPreference.restoreLastValue
        
        let resolved: ViewMode
        if launchPreference == LaunchPreference.restoreLastValue {
            let lastUsed = UserDefaults.standard.string(forKey: "lastUsedViewMode")
            resolved = ViewMode(rawValue: lastUsed ?? ViewMode.easy.rawValue) ?? .easy
        } else {
            resolved = ViewMode(rawValue: launchPreference) ?? .easy
        }
        
        _viewMode = Published(initialValue: resolved)
    }
    
    // ── Tabs ─────────────────────────────────────────────────────
    //
    // Every open file lives in a tab. The tab list is the source of truth;
    // `currentFile` is simply the selected tab's file, read and written
    // through. Keeping that name meant the hundreds of places that already
    // ask "what is the open file?" did not have to change. Tab operations live
    // in MediaStore+Tabs.swift.

    @Published var tabs: [DocumentTab] = [] {
        didSet { refreshComparisonIfInputsChanged() }
    }

    /// The empty tab ⌘T opens. See `openNewTab` in MediaStore+Tabs.
    @Published var newTab: NewTabPlaceholder?

    @Published var selectedTabID: UUID? = nil {
        didSet {
            guard oldValue != selectedTabID else { return }
            selectedTabDidChange()
        }
    }

    /// The file in the selected tab — File A in Compare Mode.
    ///
    /// Setting it replaces that tab's file. Setting nil does nothing: closing
    /// a file means closing its tab, which `closeTab` does explicitly.
    var currentFile: MediaFile? {
        get {
            guard let index = selectedTabIndex else { return nil }
            return tabs[index].file
        }
        set {
            guard let newValue, let index = selectedTabIndex else { return }
            tabs[index].file = newValue
        }
    }

    var selectedTabIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    /// Total time spent in the app. See UsageTracker.swift.
    let usage = UsageTracker()
    
    /// Starred files and folders, newest first. See MediaStore+Favorites.swift.
    @Published var favoriteURLs: [URL] = MediaStore.loadFavorites()
    
    /// The tab being dragged, for reordering and so the window's own file drop
    /// targets ignore a tab dragged over them. See `beginTabDrag`.
    @Published var draggingTabID: UUID? = nil
    var tabDragWatcher: Task<Void, Never>?
    
    // ── Compare Mode ─────────────────────────────────────────────
    //
    // File A is the selected tab. File B is another tab, referenced here, so
    // comparing never runs mediainfo on something already open, and either
    // side can be a tab you already had.
    @Published var compareTabID: UUID? = nil {
        didSet { refreshComparisonIfInputsChanged() }
    }
    
    /// The Compare button's list of open tabs. On the store, like the Open in
    /// App picker, so the keyboard shortcut can raise it too.
    @Published var showComparePicker: Bool = false
    /// The Media Health window, when open: which pane it reports on.
    @Published var healthTarget: HealthTarget?
    
    /// The Siri AI window, when open.
    @Published var explainTarget: ExplainTarget?
    
    /// File B: the file in the tab `compareTabID` names.
    ///
    /// Setting a file writes it back into that tab; setting nil simply stops
    /// referencing it — the tab stays open.
    var compareFile: MediaFile? {
        get {
            guard let compareTabID,
                  let tab = tabs.first(where: { $0.id == compareTabID }) else { return nil }
            return tab.file
        }
        set {
            guard let newValue else {
                compareTabID = nil
                return
            }
            guard let compareTabID,
                  let index = tabs.firstIndex(where: { $0.id == compareTabID }) else { return }
            tabs[index].file = newValue
        }
    }
    
    @Published var isCompareMode:  Bool            = false {
        didSet {
            guard oldValue != isCompareMode else { return }
            scheduleLoaders()
            // Quick Look shows one file; with two on screen it closes.
            if isCompareMode { PreviewRouter.screenChanged(to: nil) }
        }
    }
    // viewMode persists the last-used view on every switch.
    @Published var viewMode: ViewMode = .easy {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "lastUsedViewMode")

            // Tabs in the background fetch this view's format first too, so
            // it is ready whichever of them you switch to next.
            for loader in loaders.values {
                loader.setPreferred(viewMode.format)
            }
        }
    }
    @Published var showExportMenu: Bool            = false
    
    /// Whether the "Open in Default App" file picker is showing. On the store
    /// rather than in the button, so ⌘↩ (handled in ContentView) can raise it
    /// too.
    @Published var showOpenInAppPicker: Bool = false
    
    /// Raised for a moment after a file is handed to another app, so the
    /// toolbar button can say "Opening…".
    ///
    /// On the store rather than in ToolbarView because there are four ways to
    /// launch a file — the toolbar button, the two rows of the Compare Mode
    /// picker, and ⌘↩ — and state that something outside a view has to set
    /// can't live inside that view.
    @Published var didLaunchInApp: Bool = false
    
    /// Held so a second launch restarts the message rather than being cut short
    /// by the first one's pending reset.
    var launchFlashTask: Task<Void, Never>? = nil
    
    // ── Share/Upload state ───────────────────────────────────────
    @Published var isUploading:     Bool    = false
    @Published var shareResultURL:  String? = nil
    @Published var shareError:      String? = nil
    @Published var showShareResult: Bool    = false
    
    // Sharing is a two-step operation. The payload is assembled and
    // sanitised first, presented for review, and only uploaded once the user
    // confirms. A privacy measure the user can't see is one they can't trust.
    @Published var isPreparingShare: Bool          = false
    @Published var pendingShare:     PendingShare? = nil
    
    // ── Drag and drop ────────────────────────────────────────────
    // Set by the AppKit-backed panes (NSTextView, WKWebView), which intercept
    // drags before SwiftUI ever sees them. Storing *which* pane is targeted
    // rather than a plain bool is what lets Compare Mode highlight one side in
    // its own colour instead of flooding the whole window.
    @Published private(set) var externalDropTarget: FileDropTarget? = nil
    
    /// Which pane last claimed the drag.
    ///
    /// Several views write to `externalDropTarget` — the left pane, the right
    /// pane, and the AppKit views inside each. Without recording an owner, a
    /// late "drag left" from the pane the cursor has *already* moved out of
    /// wipes the highlight the new pane just set, which is what made the
    /// highlight appear on a random side after switching modes.
    private var dropOwner: FileDropTarget? = nil
    
    /// Reports drag state from a pane. Only the pane that set the current
    /// highlight is allowed to clear it.
    func reportDropTarget(_ target: FileDropTarget?, from owner: FileDropTarget) {
        if let target {
            externalDropTarget = target
            dropOwner = owner
        } else if dropOwner == owner || dropOwner == nil {
            externalDropTarget = nil
            dropOwner = nil
        }
    }
    
    /// Clears all drag state. Called on mode transitions so nothing survives
    /// into a layout where it no longer means anything.
    func resetDropState() {
        dragSessionEndTask?.cancel()
        dragSessionEndTask = nil
        externalDropTarget = nil
        dropOwner = nil
        isDragSessionActive = false
        stopModifierTracking()
    }
    
    /// True for the whole duration of a drag over the window.
    ///
    /// The centre "open on its own" card is shown for as long as this is true,
    /// rather than only when the cursor is near the middle — a new interaction
    /// nobody can see is one nobody will use.
    @Published private(set) var isDragSessionActive: Bool = false
    
    private var dragSessionEndTask: Task<Void, Never>? = nil
    
    // ── Option-drag to compare ───────────────────────────────────
    //
    // Holding Option while dropping a file onto a single-file window opens it
    // as File B and enters Compare Mode, instead of replacing what is open.
    //
    // The flag is published because the drop overlay changes colour and
    // wording while Option is down — an invisible modifier is a feature nobody
    // discovers. Tracking it needs a `flagsChanged` monitor, because pressing
    // Option mid-drag generates no drag event at all, so nothing else would
    // tell us. The monitor only exists for the length of a drag.
    
    @Published private(set) var isOptionHeldDuringDrag: Bool = false
    
    private var modifierMonitor: Any? = nil
    
    /// Whether an Option-drop would actually do something different right now.
    ///
    /// Only in single-file mode with a file already open. With nothing open
    /// there is nothing to compare against, and Compare Mode already has its
    /// own three-zone drop.
    var isOptionCompareAvailable: Bool {
        !isCompareMode && currentFile != nil
    }
    
    /// True when the current drag would enter Compare Mode on release.
    var willCompareOnDrop: Bool {
        isOptionHeldDuringDrag && isOptionCompareAvailable
    }
    
    private func startModifierTracking() {
        guard modifierMonitor == nil else { return }
        
        isOptionHeldDuringDrag = NSEvent.modifierFlags.contains(.option)
        
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.contains(.option)
            Task { @MainActor in
                guard let self else { return }
                if self.isOptionHeldDuringDrag != held {
                    self.isOptionHeldDuringDrag = held
                }
            }
            return event
        }
    }
    
    private func stopModifierTracking() {
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
        }
        modifierMonitor = nil
        isOptionHeldDuringDrag = false
    }
    
    /// Whether the three-zone drop applies right now: Compare Mode, with both
    /// sides already filled. With one pane empty, dropping into that pane is
    /// the obvious action and a third choice is just noise.
    var isCentreDropAvailable: Bool {
        isCompareMode && currentFile != nil && compareFile != nil
    }
    
    func beginDragSession() {
        dragSessionEndTask?.cancel()
        dragSessionEndTask = nil
        if !isDragSessionActive {
            isDragSessionActive = true
        }
        startModifierTracking()
    }
    
    /// Ends the session after a short grace period.
    ///
    /// Moving the cursor from one pane to another fires an exit immediately
    /// before the next enter, so ending instantly would make the centre card
    /// flicker out and back every time the divider was crossed.
    ///
    /// The caller passes its own pane, and the delayed clear only applies if
    /// that pane still owns the highlight. Without that check this was the
    /// bug: crossing the left pane on the way to the right one scheduled a
    /// clear, the right pane then set its own highlight, and 220ms later the
    /// stale clear wiped it. The enter often arrives *before* the exit, so the
    /// pending task was never cancelled. Holding the cursor still meant nothing
    /// re-set the highlight and the feedback simply vanished — while the drop
    /// itself, on a separate path, kept working.
    func endDragSession(from owner: FileDropTarget? = nil) {
        dragSessionEndTask?.cancel()
        dragSessionEndTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, let self else { return }
            
            // Someone else has claimed the drag in the meantime — leave it be.
            if let owner, let current = self.dropOwner, current != owner {
                return
            }
            
            self.isDragSessionActive = false
            self.externalDropTarget = nil
            self.dropOwner = nil
            self.stopModifierTracking()
        }
    }
    
    // ── Comparison ───────────────────────────────────────────────
    // Computed once whenever either file changes, not on every render of
    // every pane.
    @Published private(set) var comparison: MediaComparison = MediaComparison(tracks: [])
    
    /// The fingerprint `comparison` was last built from. See
    /// `refreshComparisonIfInputsChanged`.
    private var lastComparisonInputs: ComparisonInputs?
    
    /// Set when the user picks a track in the comparison summary. Both panes
    /// scroll to it and flash it briefly, then it is cleared.
    @Published var focusedComparisonTrackID: String? = nil
    
    /// Whether the summary panel is expanded. Persisted, because it is a
    /// standing preference about how much detail to see, not a per-session
    /// accident.
    @AppStorage("compareSummaryExpanded") var isSummaryExpanded: Bool = false
    
    /// Reveal a track in both panes.
    ///
    /// Turns difference highlighting on first: the user has just clicked
    /// something in a list of differences, so showing them the track without
    /// marking what differs would answer half the question.
    func focusComparisonTrack(_ id: String) {
        if !showDiffHighlight {
            smiWithAnimation(SMI.Motion.smooth) { showDiffHighlight = true }
        }
        
        focusedComparisonTrackID = id
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if focusedComparisonTrackID == id {
                focusedComparisonTrackID = nil
            }
        }
    }
    
    /// Rebuild the comparison now.
    func refreshComparison() {
        lastComparisonInputs = comparisonInputs()
        comparison = MediaComparison.build(fileA: currentFile, fileB: compareFile)
    }
    
    // ── Keeping the comparison current ───────────────────────────
    //
    // The comparison maintains itself. Every change to the tab list or to
    // which tab is File B compares a cheap fingerprint of both sides' content
    // with the one the comparison was built from, and rebuilds when it
    // differs. No code path can forget to refresh it — the bug this replaced:
    // a File B still loading when Compare began left every field "only in A"
    // until something unrelated refreshed it.
    
    /// What the comparison depends on: which files, their parsed metadata
    /// (by the JSON it came from) and their checksums, which are injected
    /// into the General track.
    private struct ComparisonInputs: Equatable {
        let fileA: UUID?
        let jsonA: Int?
        let digestA: String?
        let fileB: UUID?
        let jsonB: Int?
        let digestB: String?
    }
    
    private func comparisonInputs() -> ComparisonInputs {
        let a = currentFile
        let b = compareFile
        return ComparisonInputs(
            fileA: a?.id, jsonA: a?.rawJSON?.utf8.count, digestA: a?.hashState.digest,
            fileB: b?.id, jsonB: b?.rawJSON?.utf8.count, digestB: b?.hashState.digest
        )
    }
    
    private func refreshComparisonIfInputsChanged() {
        guard comparisonInputs() != lastComparisonInputs else { return }
        refreshComparison()
    }
    
    /// Increments on every swap.
    ///
    /// The panes animate from this rather than from the file values changing.
    /// Left to its own devices SwiftUI animated whichever pane happened to keep
    /// its view identity through the swap and rebuilt the other outright, so
    /// exactly one side animated — and which side alternated with every press.
    /// A token both panes watch makes the motion symmetrical by construction.
    @Published private(set) var swapToken: Int = 0
    
    /// Exchange File A and File B.
    ///
    /// Swaps the loaded files wholesale — tracks, every cached format, and all
    /// error state — so nothing is re-read from disk and no format has to be
    /// fetched again. The comparison is rebuilt because "only in A" and "only
    /// in B" have traded places.
    ///
    /// Deliberately not wrapped in `withAnimation`: the implicit animation is
    /// what produced the lopsided result. CompareView owns the motion.
    func swapCompareFiles() {
        guard isCompareMode, currentFile != nil, compareFile != nil else { return }
        
        // Sides are tabs now, so swapping exchanges which tab is which —
        // nothing is copied, nothing re-read.
        let held = selectedTabID
        selectedTabID = compareTabID
        compareTabID = held
        // Loaders and hashes are keyed by file, not by pane, so work still
        // running follows its file to the other side without being touched.
        refreshComparison()
        
        swapToken &+= 1
        
        updateWindowTitle()
    }
    
    // ── Diff highlighting ────────────────────────────────────────
    @Published var showDiffHighlight: Bool  = false
    @Published var showDiffUnsupportedPrompt: Bool = false
    @Published var showZoomFlash: Bool = false
    
    // ── Search/filter ────────────────────────────────────────────
    @Published var showSearchBar:    Bool   = false
    @Published var searchQuery:      String = ""
    @Published var searchMatchCount: Int    = 0
    @Published var searchMatchIndex: Int    = 0
    
    // ── Recent files list ──────────────────────────────────────────
    @Published var recentFileURLs: [URL] = {
        let stored = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
        return stored.compactMap { URL(string: $0) }
    }()
    
    // ── Dynamic window title ───────────────────────────────────────
    var windowTitle: String {
        // A folder tab names the folder and the file showing from it.
        if let folder = currentFolder {
            if folder.items.isEmpty { return "SwiftMediaInfo — \(folder.name)" }
            return "SwiftMediaInfo — \(folder.name) › \(currentFile?.fileName ?? "")"
        }
        if let name = currentFile?.fileName {
            return "SwiftMediaInfo — \(name)"
        }
        return "SwiftMediaInfo"
    }
    
    @AppStorage("fontSize")               var fontSize:               Double = 12
    @AppStorage("appearanceMode")         var savedAppearance:        String = AppearanceMode.system.rawValue
    // The background: Static, Animated or Off. See BackgroundMode in
    // DesignSystem.swift.
    @AppStorage(BackgroundMode.key) var backgroundModeRaw: String = BackgroundMode.shippedDefault.rawValue
    
    var backgroundMode: BackgroundMode {
        get { BackgroundMode(rawValue: backgroundModeRaw) ?? BackgroundMode.shippedDefault }
        set { backgroundModeRaw = newValue.rawValue }
    }
    
    /// ⌘B. Cycles Static → Animated → Off. Static leads because it is the
    /// default and the one most people want back.
    func cycleBackgroundMode() {
        switch backgroundMode {
        case .staticGradient: backgroundMode = .animated
        case .animated:       backgroundMode = .off
        case .off:            backgroundMode = .staticGradient
        }
    }
    
    // MARK: Migration from the old boolean
    //
    // Older versions stored this as `showAnimatedBackground`, a Bool. Anyone
    // upgrading has that key set and the new one absent, and simply letting the
    // new default win would silently overrule a choice they made — someone who
    // deliberately turned the background off would find it back on.
    //
    // So: run once, only when the new key is genuinely missing. `true` meant
    // animated, `false` meant nothing at all. The old key is left in place
    // rather than deleted; it costs a few bytes and it means a downgrade to an
    // older build still finds what it expects.
    static func migrateBackgroundPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        
        guard defaults.object(forKey: BackgroundMode.key) == nil else { return }
        guard defaults.object(forKey: "showAnimatedBackground") != nil else { return }
        
        let wasOn = defaults.bool(forKey: "showAnimatedBackground")
        let migrated: BackgroundMode = wasOn ? .animated : .off
        
        defaults.set(migrated.rawValue, forKey: BackgroundMode.key)
    }
    
    /// Maximum time a single mediainfo call may take, in seconds (Settings ›
    /// Analysis). The default, 60, is well over the slowest real-world file
    /// seen (about 40 seconds): guessing low only means a rare slow file needs
    /// the setting raised, while guessing high means minutes of spinner before
    /// learning it was never going to work.
    @AppStorage("analysisTimeoutSeconds") var analysisTimeoutSeconds: Double = 60
    
    /// Clamped so a corrupted preference can't disable the timeout entirely
    /// or push it past the one-hour ceiling.
    var analysisTimeout: TimeInterval {
        min(max(analysisTimeoutSeconds, 5), MediaEngine.maximumTimeout)
    }
    
    /// The current appearance, derived from `savedAppearance` rather than
    /// stored separately. One value, which `@AppStorage` invalidates for every
    /// observer in every window when it changes. (A separate published copy
    /// kept in step by hand left the window that wasn't frontmost showing the
    /// previous choice — the setting looked one step behind.)
    var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: savedAppearance) ?? .system
    }
    
    // MARK: - Cancellation
    
    /// One loader per open file, keyed by the file's session id. Each runs a
    /// single mediainfo process at a time — see FormatLoader.swift — and
    /// `scheduleLoaders()` decides which of them may run at all.
    private var loaders: [UUID: FormatLoader] = [:]
    
    /// Stop everything running for one file: its analysis and its hash.
    func cancelWork(for sessionID: UUID?) {
        guard let sessionID else { return }
        
        loaders.removeValue(forKey: sessionID)?.cancel()
        cancelHashing(sessionID: sessionID)
        deferredHashes[sessionID] = nil
        scheduleLoaders()
    }
    
    func cancelCurrentTasks() {
        cancelWork(for: currentFile?.id)
    }
    
    func cancelCompareTasks() {
        cancelWork(for: compareFile?.id)
    }
    
    // MARK: - Checksums
    //
    // Kept separate from the analysis tasks above. A hash can outlive the
    // mediainfo run that started it by minutes, so cancelling one must not
    // cancel the other — closing a file cancels both, but a finished analysis
    // leaves a running hash alone.
    //
    // Keyed by file rather than by pane, because with tabs a file whose hash
    // is running may not be on screen at all.
    
    var hashTasks: [UUID: Task<Void, Never>] = [:]
    
    // The checksum methods are in MediaStore+Checksums.swift.
    
    // MARK: - Appearance
    
    /// Set the appearance directly. Used by Settings, where the user picks a
    /// mode rather than cycling through them.
    func setAppearance(_ mode: AppearanceMode) {
        smiWithAnimation(SMI.Motion.fade) {
            savedAppearance = mode.rawValue
            applyAppearance(mode)
        }
    }
    
    /// Return every preference to its shipped default.
    ///
    /// Recent files and the open document are deliberately untouched — this is
    /// a settings reset, not a "forget everything I've done" button, and
    /// conflating the two would make it dangerous to use.
    func resetSettingsToDefaults() {
        fontSize               = 12
        backgroundMode = BackgroundMode.shippedDefault
        BackgroundPalette.reset()
        StaticBlobLayout.reset()
        analysisTimeoutSeconds = 60
        
        UserDefaults.standard.set(true, forKey: GlassPreference.key)
        // Reads the shipped default rather than naming a case, so Restore
        // Defaults can never drift away from what a fresh install gets.
        UserDefaults.standard.set(HashPolicy.shippedDefault.rawValue, forKey: HashPolicy.key)
        UserDefaults.standard.set(SharePrivacyMode.always.rawValue, forKey: PrivacyPreference.shareKey)
        UserDefaults.standard.set(LocalPrivacyMode.unmodified.rawValue, forKey: PrivacyPreference.localKey)
        UserDefaults.standard.set(HTMLPathsMode.never.rawValue, forKey: PrivacyPreference.htmlPathsKey)
        UserDefaults.standard.set(ChecksumPrivacyMode.never.rawValue, forKey: PrivacyPreference.checksumKey)
        UserDefaults.standard.set(LaunchPreference.restoreLastValue, forKey: LaunchPreference.key)
        UserDefaults.standard.set(true, forKey: EmptyScreenPreference.showsFavoritesKey)
        UserDefaults.standard.set(true, forKey: EmptyScreenPreference.showsRecentsKey)
        UserDefaults.standard.set(true, forKey: EmptyScreenPreference.showsTimeSpentKey)
        UserDefaults.standard.set(OverviewExpansion.shippedDefault.rawValue, forKey: OverviewExpansion.key)
        UserDefaults.standard.set(HealthPreference.includeChecksumDefault, forKey: HealthPreference.includeChecksumKey)
        UserDefaults.standard.set(SyntaxHighlighting.shippedDefault.rawValue, forKey: SyntaxHighlighting.key)
        UserDefaults.standard.removeObject(forKey: OverviewExpansion.rememberedKey)
        UserDefaults.standard.removeObject(forKey: StatusBar.ffmpegPromptDismissedKey)
        UserDefaults.standard.removeObject(forKey: IntelligencePreference.enabledKey)
        // The preview's volume, mute, speed, zoom and subtitle choices.
        PreviewPlayback.restoreDefaults()
        // On is the default — switched back on even if it was turned off.
        Task { await FinderExtension.set(true) }
        // Deliberately not reset: the total time spent (UsageTracker.totalKey)
        // and Favorites. They are records of what you have done, not settings.
        
        setAppearance(.system)
    }
    
    func cycleAppearance() {
        let next: AppearanceMode
        
        switch appearanceMode {
        case .system:
            next = .light
            
        case .light:
            next = .dark
            
        case .dark:
            next = .system
        }
        
        savedAppearance = next.rawValue
        applyAppearance(next)
    }
    
    /// Applies an appearance to AppKit. It no longer records the choice —
    /// `savedAppearance` is the only place that lives, and this reads from it.
    private func applyAppearance(_ mode: AppearanceMode) {
        let appearance: NSAppearance?
        switch mode {
        case .system: appearance = nil
        case .light:  appearance = NSAppearance(named: .aqua)
        case .dark:   appearance = NSAppearance(named: .darkAqua)
        }
        
        NSApp.appearance = appearance
        
        // EVERY WINDOW, NOT JUST THE APPLICATION
        //
        // Setting `NSApp.appearance` is supposed to cascade to every window,
        // and it does — to windows that have not been given an appearance of
        // their own. A window that has one keeps it, and AppKit hands windows
        // their own appearance in more situations than is obvious.
        //
        // The symptom was specific and confusing: changing the theme in
        // Settings restyled the Settings window immediately while the main
        // window kept the old one, and changing it a second time made the main
        // window adopt the FIRST choice. It looked like the setting was one
        // step behind. It was not — the main window was simply being restyled
        // by something else, one beat later.
        //
        // Assigning to each window directly removes the ambiguity. `nil` is
        // meaningful here rather than a no-op: it clears any per-window
        // appearance so the window follows the application again, which is
        // exactly what System has to mean.
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
    
    // MARK: - Zoom
    
    func zoomIn() {
        fontSize = min(fontSize + 1, 48)
        flashZoom()
    }
    
    func zoomOut() {
        fontSize = max(fontSize - 1, 8)
        flashZoom()
    }
    
    func resetZoom() {
        fontSize = 12
        flashZoom()
    }
    
    func flashZoom() {
        showZoomFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.showZoomFlash = false
        }
    }
    
    // MARK: - Search
    
    func toggleSearchBar() {
        withAnimation(.easeOut(duration: 0.15)) {
            showSearchBar.toggle()
            if !showSearchBar {
                searchQuery = ""
                searchMatchCount = 0
                searchMatchIndex = 0
            }
        }
    }
    
    // Opening files and folders is in MediaStore+Open.swift.
    
    /// Files whose checksum decision waits until they are first shown.
    var deferredHashes: [UUID: URL] = [:]
    
    // MARK: - Loading
    //
    // One FormatLoader per open file, one mediainfo process per loader. The
    // view on screen is fetched first; the rest follow in the background. See
    // FormatLoader.swift for the scheduling rules.
    
    func startLoader(
        for url: URL,
        sessionID: UUID,
        isCompare: Bool,
        formats: [MediaFormat]
    ) {
        guard !formats.isEmpty else { return }
        
        // Every queued format reads as loading from the start, so a view whose
        // turn has not come yet shows a spinner rather than a Load button.
        update(sessionID: sessionID, isCompare: isCompare) { file in
            for format in formats { file.setLoading(true, for: format) }
        }
        
        let loader = FormatLoader(
            url: url,
            sessionID: sessionID,
            timeout: analysisTimeout,
            formats: formats,
            preferred: viewMode.format
        ) { [weak self] format, result, tracks in
            self?.receive(format, result: result, tracks: tracks, url: url, sessionID: sessionID)
        }
        
        // Finished loaders are dropped, which is what hands the background
        // slot to the next tab that still has work.
        loader.onIdle = { [weak self, weak loader] in
            guard let self, let loader, self.loaders[sessionID] === loader else { return }
            self.loaders[sessionID] = nil
            self.scheduleLoaders()
        }
        
        loaders[sessionID]?.cancel()
        loaders[sessionID] = loader
        
        scheduleLoaders()
        loader.start()
    }
    
    /// Decide which loaders may run.
    ///
    /// Whatever is on screen — the selected tab, and File B in Compare Mode —
    /// always runs. Tabs in the background get a single slot between them,
    /// and only once everything visible has finished, so opening ten files
    /// never means ten mediainfo processes fighting the one you are looking
    /// at. Background tabs take the slot in tab-bar order.
    func scheduleLoaders() {
        let visible = Set([currentFile?.id, isCompareMode ? compareFile?.id : nil].compactMap { $0 })
        
        var backgroundSlotFree = !visible.contains { loaders[$0]?.hasWork == true }
        
        let order = tabs.map(\.file.id)
        
        for sessionID in order {
            guard let loader = loaders[sessionID] else { continue }
            
            if visible.contains(sessionID) {
                loader.isPaused = false
            } else if backgroundSlotFree, loader.hasWork {
                loader.isPaused = false
                backgroundSlotFree = false
            } else {
                loader.isPaused = true
            }
        }
    }
    
    /// Apply one finished fetch to whichever pane its file is in now.
    private func receive(
        _ format: MediaFormat,
        result: Result<String, MediaInfoError>,
        tracks: [MediaTrack],
        url: URL,
        sessionID: UUID
    ) {
        update(sessionID: sessionID) { file in
            file.apply(result, tracks: tracks, for: format)
            
            // The first result to land is the current view's — it was fetched
            // first — so it is what ends the "Analysing…" state. A failure
            // here is the one that best explains a blank screen.
            if file.isLoading {
                file.isLoading = false
                file.loadError = result.failure
            }
        }
        
        // Each format is remembered as soon as it arrives, so a file closed
        // halfway through its background pass still reopens faster. Failures
        // are never cached — they would be served back on every reopen with no
        // way to tell them apart from a real answer — and neither is JSON that
        // produced no tracks.
        if let content = result.value, result.failure == nil,
           format != .json || !tracks.isEmpty {
            let version = mediaInfoVersion ?? ""
            
            AnalysisCache.update(for: url) { entry in
                // An entry from an older mediainfo keeps its old stamp, so it
                // is still offered for re-analysis rather than passing as
                // current because one fresh format was added to it.
                if entry.mediaInfoVersion.isEmpty { entry.mediaInfoVersion = version }
                
                switch format {
                case .json:    entry.rawJSON     = content
                case .text:    entry.rawText     = content
                case .rawText: entry.rawTextFull = content
                case .html:    entry.rawHTML     = content
                case .xml:     entry.rawXML      = content
                }
            }
        }
        
        updateWindowTitle()
    }
    
    private func loader(isCompare: Bool, for file: MediaFile) -> FormatLoader? {
        loaders[file.id]
    }
    
    // MARK: - Tab requests
    
    /// The user is looking at `mode`: make sure its format is loaded or next
    /// in line.
    ///
    /// Called on every view change and whenever a file changes, and by the
    /// Load and Try Again buttons. Cheap when there is nothing to do.
    func loadFormatIfNeeded(_ mode: ViewMode, isCompare: Bool = false) {
        guard let file = isCompare ? compareFile : currentFile else { return }
        
        let format = mode.format
        let loader = loader(isCompare: isCompare, for: file)
        
        // Queued or running already — just move it to the front.
        if let loader, loader.isScheduled(format) {
            loader.prefer(format)
            return
        }
        
        // Loaded, or failed with an error the user has not cleared. Still
        // record the preference, so the background pass knows where you are.
        guard file.content(for: format) == nil,
              file.error(for: format) == nil else {
            loader?.prefer(format)
            return
        }
        
        // Not loaded and not scheduled: a retry, or a format abandoned when
        // the analysis was cancelled.
        update(sessionID: file.id, isCompare: isCompare) { $0.setLoading(true, for: format) }
        
        if let loader {
            loader.enqueue(format)
        } else {
            startLoader(for: file.url, sessionID: file.id, isCompare: isCompare, formats: [format])
        }
    }
    
    /// Clear a format's recorded failure so the retry button can try again.
    func clearError(for mode: ViewMode, isCompare: Bool) {
        let fileRef: MediaFile? = isCompare ? compareFile : currentFile
        guard let sessionID = fileRef?.id else { return }
        
        update(sessionID: sessionID, isCompare: isCompare) { file in
            let format = mode.format
            if file.loadError == file.error(for: format) { file.loadError = nil }
            file.setError(nil, for: format)
        }
    }
    
    /// Wait for formats that are still on their way, then return the file as
    /// it stands.
    ///
    /// Export and share snapshot a file and write it out. With formats now
    /// arriving one at a time, a snapshot taken in the first few seconds can be
    /// missing some of them; this lets those paths wait for the background pass
    /// instead of silently writing less than was asked for. Returns the
    /// original snapshot when the file has been closed in the meantime.
    func completedSnapshot(
        _ snapshot: MediaFile,
        needing formats: [MediaFormat] = MediaFormat.allCases
    ) async -> MediaFile {
        if let loader = loaders[snapshot.id] {
            for format in formats {
                await loader.wait(for: format)
            }
        }
        
        return file(withSessionID: snapshot.id) ?? snapshot
    }
    
    // MARK: - Helper
    
    /// The open file with this session id, wherever it is: any tab, or File B.
    func file(withSessionID sessionID: UUID) -> MediaFile? {
        if let tab = tabs.first(where: { $0.file.id == sessionID }) { return tab.file }
        if compareFile?.id == sessionID { return compareFile }
        return nil
    }
    
    /// Applies a mutation only if the file the caller was working on is still
    /// open.
    ///
    /// Matched by identity, not URL: open file A, then open file A again
    /// before the first analysis finished, and URL matching would let the
    /// older, slower result land on top of the newer one.
    ///
    /// Matched wherever the file is — any tab, or File B — because with tabs
    /// a result can arrive for a file that is not on screen, and Swap can move
    /// a file between panes while it is still loading.
    func update(sessionID: UUID, mutation: (inout MediaFile) -> Void) {
        if let index = tabs.firstIndex(where: { $0.file.id == sessionID }) {
            // `tabs` rebuilds the comparison itself if this touched either
            // side — including File B, which is not the selected tab.
            mutation(&tabs[index].file)
            
        } else if var file = compareFile, file.id == sessionID {
            mutation(&file)
            compareFile = file
            refreshComparison()
        }
    }
    
    /// Kept so call sites that know their pane read naturally. The pane is
    /// no longer needed to find the file.
    func update(
        sessionID: UUID,
        isCompare: Bool,
        mutation: (inout MediaFile) -> Void
    ) {
        update(sessionID: sessionID, mutation: mutation)
    }
    
    // MARK: - Window title helper
    
    func updateWindowTitle() {
        // The main window, found by its DocumentWindowMarker stamp —
        // `NSApp.windows` isn't ordered by importance, so with Settings or
        // About open the first window could be the wrong one. The fallback
        // covers the instant before the stamp is applied at launch.
        let document = NSApp.windows.first {
            $0.identifier?.rawValue == DocumentWindowMarker.identifier
        }
        
        (document ?? NSApp.windows.first)?.title = windowTitle
    }
    
    // MARK: - Recent files
    
    func addToRecentFiles(_ url: URL) {
        var recents = recentFileURLs.filter { $0 != url }
        recents.insert(url, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        recentFileURLs = recents
        UserDefaults.standard.set(recents.map { $0.absoluteString }, forKey: "recentFiles")
    }
    
    func clearRecentFiles() {
        recentFileURLs = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }
    
    /// Drop one entry. Used when a file is trashed, and offered directly on a
    /// recent-file chip — a list of recents with no way to prune it turns into
    /// a list of things you would rather not be reminded of.
    func removeFromRecents(_ url: URL) {
        let target = url.standardized
        let filtered = recentFileURLs.filter { $0.standardized != target }
        
        guard filtered.count != recentFileURLs.count else { return }
        
        recentFileURLs = filtered
        UserDefaults.standard.set(
            filtered.map { $0.absoluteString },
            forKey: "recentFiles"
        )
    }
    
    /// Swap one entry for another, keeping its position.
    ///
    /// A rename should not reshuffle history. The de-duplication guards the
    /// case where the new name is already somewhere further down the list,
    /// which would otherwise leave the same file in the list twice.
    func replaceInRecents(_ old: URL, with new: URL) {
        let target = old.standardized
        var seen = Set<URL>()
        
        let updated = recentFileURLs
            .map { $0.standardized == target ? new : $0 }
            .filter { seen.insert($0.standardized).inserted }
        
        recentFileURLs = updated
        UserDefaults.standard.set(
            updated.map { $0.absoluteString },
            forKey: "recentFiles"
        )
    }
    
    // File actions and the analysis cache are in MediaStore+FileActions.swift.
    
    /// The running mediainfo version, resolved once per launch.
    ///
    /// Cached entries are stamped with it. Asking mediainfo every time a file
    /// opens would put an extra subprocess in front of every analysis to
    /// answer a question whose answer cannot change while the app is running.
    @Published var mediaInfoVersion: String? = nil

    /// Set when an open file's cached analysis came from an older mediainfo.
    ///
    /// A prompt rather than a silent discard: the cached output is not wrong,
    /// it is just older, and re-reading is the user's call.
    @Published var staleAnalysisURL: URL? = nil

    var isResolvingVersion = false

    /// Set while the rename sheet is open.
    @Published var pendingRename: PendingFileAction? = nil

    /// Set while the "move to Trash" confirmation is open.
    @Published var pendingTrash: PendingFileAction? = nil

    /// The last file-action failure, shown in an alert and then cleared.
    ///
    /// These failures are worth surfacing — unlike a format that fails to
    /// export, a rename that silently does nothing looks like the app ignored
    /// you.
    @Published var fileActionError: String? = nil
    
    // Copying, and opening in the default app, are in MediaStore+Copy.swift.
}

// MARK: - Result convenience

extension Result where Success == String, Failure == MediaInfoError {
    /// The value on success, nil on failure.
    var value: String? {
        if case .success(let string) = self { return string }
        return nil
    }
    
    /// The error on failure, nil on success. Cancellation is reported as nil
    /// because a cancelled analysis is not a failure the user should be told about.
    var failure: MediaInfoError? {
        guard case .failure(let error) = self else { return nil }
        return error.isCancellation ? nil : error
    }
}
