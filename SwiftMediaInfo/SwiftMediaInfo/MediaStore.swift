//
//  MediaStore.swift
//  SwiftMediaInfo
//
//  PHASE 1 changes:
//
//    • Results from mediainfo are now matched to the request that created them
//      by file identity, not by URL. Opening the same file twice in quick
//      succession can no longer let the older analysis overwrite the newer one.
//    • Failures are stored as typed errors on MediaFile instead of vanishing.
//    • The analysis timeout is read from user defaults and passed through.
//    • Completed load tasks are pruned instead of accumulating forever.
//    • A retry entry point exists for the error UI.
//
//  PHASE 3 change:
//
//    • cancelLoading(isCompare:) — lets the user stop an analysis in progress.
//      Drives the Cancel button in ContentStateView.
//
//  PHASE 5 change:
//
//    • Share review state (isPreparingShare, pendingShare). The upload itself
//      lives in MediaStore_ShareExtension.swift.
//
//  Everything else — export, sharing, recents, appearance, zoom, search —
//  behaves exactly as before.
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
    
    @Published var currentFile:    MediaFile?      = nil
    @Published var compareFile:    MediaFile?      = nil
    @Published var isCompareMode:  Bool            = false
    // viewMode persists the last-used tab on every switch.
    @Published var viewMode: ViewMode = .easy {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "lastUsedViewMode")
        }
    }
    @Published var showExportMenu: Bool            = false
    
    /// Whether the "Open in Default App" file picker is showing.
    ///
    /// PHASE 8c. This used to be private @State inside the button. A keyboard
    /// shortcut is handled elsewhere in the view tree and cannot reach private
    /// state, so ⌘↩ silently skipped the picker and always opened File A.
    @Published var showOpenInAppPicker: Bool = false
    
    /// PHASE 11 — raised for a moment after a file is handed to another app, so
    /// the toolbar button can say "Opening…".
    ///
    /// It lives on the store rather than in ToolbarView because there are FOUR
    /// ways to launch a file: the toolbar button, the two rows of the Compare
    /// Mode picker popover, and ⌘↩ from ContentView's key monitor. The first
    /// attempt kept this flag as local `@State` in ToolbarView, so three of
    /// those four routes launched the file and left the button sitting there
    /// doing nothing — which is exactly the trap ⌘↩ fell into in Phase 8c, for
    /// exactly the same reason. State that something outside a view has to set
    /// cannot live inside that view.
    @Published var didLaunchInApp: Bool = false
    
    /// Held so a second launch restarts the message rather than being cut short
    /// by the first one's pending reset.
    private var launchFlashTask: Task<Void, Never>? = nil
    
    // ── Share/Upload state ───────────────────────────────────────
    @Published var isUploading:     Bool    = false
    @Published var shareResultURL:  String? = nil
    @Published var shareError:      String? = nil
    @Published var showShareResult: Bool    = false
    
    // Phase 5: sharing is a two-step operation. The payload is assembled and
    // sanitised first, presented for review, and only uploaded once the user
    // confirms. A privacy measure the user can't see is one they can't trust.
    @Published var isPreparingShare: Bool          = false
    @Published var pendingShare:     PendingShare? = nil
    
    // ── Main window geometry ─────────────────────────────────────
    // Reported by ContentView. Auxiliary windows cap their zoom against it, so
    // Settings can never end up larger than the app it belongs to.
    @Published var mainWindowSize: CGSize = .zero
    
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
    
    // ── Option-drag to compare (Phase 8c) ────────────────────────
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
    // Computed once whenever either file changes, rather than recomputed on
    // every render of every pane as it was before.
    @Published private(set) var comparison: MediaComparison = MediaComparison(tracks: [])
    
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
    
    /// Rebuild the comparison. Called whenever either side's tracks change.
    func refreshComparison() {
        comparison = MediaComparison.build(fileA: currentFile, fileB: compareFile)
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
        
        let held = currentFile
        currentFile = compareFile
        compareFile = held
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
        if let name = currentFile?.fileName {
            return "SwiftMediaInfo — \(name)"
        }
        return "SwiftMediaInfo"
    }
    
    @AppStorage("fontSize")               var fontSize:               Double = 12
    @AppStorage("appearanceMode")         var savedAppearance:        String = AppearanceMode.system.rawValue
    // PHASE 12b — the background is now a three-way choice, not a switch.
    // See BackgroundMode in DesignSystem.swift for why the middle option is the
    // one that mattered.
    @AppStorage(BackgroundMode.key) var backgroundModeRaw: String = BackgroundMode.shippedDefault.rawValue
    
    var backgroundMode: BackgroundMode {
        get { BackgroundMode(rawValue: backgroundModeRaw) ?? BackgroundMode.shippedDefault }
        set { backgroundModeRaw = newValue.rawValue }
    }
    
    /// ⌘B. Cycles Static → Animated → Off rather than toggling, since there are
    /// three states now. Static leads because it is the default and the one
    /// most people want back.
    func cycleBackgroundMode() {
        switch backgroundMode {
        case .staticGradient: backgroundMode = .animated
        case .animated:       backgroundMode = .off
        case .off:            backgroundMode = .staticGradient
        }
    }
    
    // MARK: Migration from the old boolean
    //
    // Before Phase 12b this was `showAnimatedBackground`, a Bool. Anyone
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
    
    /// Maximum time a single mediainfo call may take, in seconds.
    ///
    /// Exposed in Settings in Phase 6. Lowered to 60 in Phase 11, from 120: the
    /// slowest real-world file observed took about 40 seconds, so a minute is
    /// still a comfortable margin, and the cost of guessing low is only that a
    /// rare slow file needs the setting raised — whereas the cost of guessing
    /// high is two full minutes of staring at a spinner before being told it
    /// was never going to work. Two minutes is still one click away.
    @AppStorage("analysisTimeoutSeconds") var analysisTimeoutSeconds: Double = 60
    
    /// Clamped so a corrupted preference can't disable the timeout entirely
    /// or push it past the one-hour ceiling.
    var analysisTimeout: TimeInterval {
        min(max(analysisTimeoutSeconds, 5), MediaEngine.maximumTimeout)
    }
    
    /// The current appearance, derived rather than stored separately.
    ///
    /// THE ONE-BEHIND BUG
    ///
    /// This used to be `@Published var appearanceMode`, set alongside
    /// `savedAppearance` every time the theme changed. Two properties holding
    /// one fact, kept in step by hand.
    ///
    /// The Settings picker read one of them and the toolbar button read the
    /// same one — but they were rendered by different windows, and the window
    /// that was not frontmost did not always re-render on the change. So the
    /// toolbar went on displaying whatever it had drawn during the PREVIOUS
    /// change, which looked exactly like the setting being one step behind.
    ///
    /// Deriving it removes the possibility rather than papering over it. There
    /// is now one value, `savedAppearance`, and `@AppStorage` invalidates every
    /// observer when it changes — which is the same arrangement `backgroundMode`
    /// already uses, and that one never had this problem.
    var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: savedAppearance) ?? .system
    }
    
    // MARK: - Cancellation
    
    private var currentLoadTasks:  [Task<Void, Never>] = []
    private var compareLoadTasks:  [Task<Void, Never>] = []
    
    private func cancelCurrentTasks() {
        currentLoadTasks.forEach { $0.cancel() }
        currentLoadTasks = []
        cancelHashing(isCompare: false, markCancelled: false)
    }
    
    private func cancelCompareTasks() {
        compareLoadTasks.forEach { $0.cancel() }
        compareLoadTasks = []
        cancelHashing(isCompare: true, markCancelled: false)
    }
    
    // MARK: - Checksums (Phase 10)
    //
    // Kept separate from the analysis tasks above. A hash can outlive the
    // mediainfo run that started it by minutes, so cancelling one must not
    // cancel the other — closing a file cancels both, but a finished analysis
    // leaves a running hash alone.
    
    private var hashTask: Task<Void, Never>? = nil
    private var compareHashTask: Task<Void, Never>? = nil
    
    /// Decide what to do about a newly opened file's checksum.
    ///
    /// Called once the file is on screen rather than before, so a 50 GB file
    /// shows its metadata immediately and hashes in the background.
    private func beginHashingIfNeeded(for url: URL, sessionID: UUID, isCompare: Bool) {
        guard FileHasher.isEligible(url) else {
            setHashState(.notApplicable, sessionID: sessionID, isCompare: isCompare)
            return
        }
        
        // A remembered digest is applied without touching the disk. This is
        // the whole reason the cache exists: reopening a large file should be
        // instant, not another few minutes of reading.
        if let cached = HashCache.digest(for: url) {
            applyDigest(cached, sessionID: sessionID, isCompare: isCompare)
            return
        }
        
        switch HashPolicy.current {
        case .never:
            setHashState(.notApplicable, sessionID: sessionID, isCompare: isCompare)
            
        case .manual:
            setHashState(.awaitingRequest, sessionID: sessionID, isCompare: isCompare)
            
        case .always:
            startHashing(isCompare: isCompare)
        }
    }
    
    /// Start hashing whichever pane is named. Also the entry point for the
    /// Compute Checksum button and for retrying after a failure.
    func startHashing(isCompare: Bool) {
        guard let file = isCompare ? compareFile : currentFile else { return }
        guard !file.hashState.isRunning else { return }
        
        let url = file.url
        let sessionID = file.id
        
        cancelHashing(isCompare: isCompare, markCancelled: false)
        setHashState(.hashing(progress: 0), sessionID: sessionID, isCompare: isCompare)
        
        let task = Task { [weak self] in
            do {
                let digest = try await FileHasher.sha256(of: url) { progress in
                    self?.setHashState(
                        .hashing(progress: progress),
                        sessionID: sessionID,
                        isCompare: isCompare
                    )
                }
                
                guard !Task.isCancelled else { return }
                
                HashCache.store(digest, for: url)
                AnalysisCache.update(for: url) { $0.digest = digest }
                self?.applyDigest(digest, sessionID: sessionID, isCompare: isCompare)
                
            } catch is CancellationError {
                // The cancelling side already set the state. Setting it again
                // here would overwrite a file that has since been replaced.
                return
                
            } catch {
                self?.setHashState(
                    .failed(reason: error.localizedDescription),
                    sessionID: sessionID,
                    isCompare: isCompare
                )
            }
        }
        
        if isCompare {
            compareHashTask = task
        } else {
            hashTask = task
        }
    }
    
    /// Hide the checksum card without hashing.
    ///
    /// A card offering work you have decided not to do is clutter, and on a
    /// file you are only inspecting it sits between you and the metadata. This
    /// is per-file and not persisted — reopening the file offers again, which
    /// is right, because "not now" is not the same as "never for this file".
    /// "Never at all" is the Off setting.
    func dismissChecksum(isCompare: Bool) {
        cancelHashing(isCompare: isCompare, markCancelled: false)
        
        if isCompare {
            compareFile?.hashState = .notApplicable
        } else {
            currentFile?.hashState = .notApplicable
        }
    }
    
    /// Stop a running hash.
    ///
    /// `markCancelled` separates the user pressing Stop — which should say so
    /// and offer to start again — from the file simply being closed or
    /// replaced, where there is nothing left to report it on.
    func cancelHashing(isCompare: Bool, markCancelled: Bool = true) {
        let task = isCompare ? compareHashTask : hashTask
        guard task != nil else { return }
        
        task?.cancel()
        
        if isCompare {
            compareHashTask = nil
        } else {
            hashTask = nil
        }
        
        guard markCancelled,
              let file = isCompare ? compareFile : currentFile,
              file.hashState.isRunning else { return }
        
        setHashState(.cancelled, sessionID: file.id, isCompare: isCompare)
    }
    
    /// Write a state back, but only if the file it belongs to is still open.
    ///
    /// The session id is checked for the same reason the analysis results
    /// check it: a hash started minutes ago must not write into whatever file
    /// happens to be on screen now.
    private func setHashState(_ state: HashState, sessionID: UUID, isCompare: Bool) {
        if isCompare {
            guard compareFile?.id == sessionID else { return }
            compareFile?.hashState = state
        } else {
            guard currentFile?.id == sessionID else { return }
            currentFile?.hashState = state
        }
    }
    
    /// Record a finished digest and inject it into the track data.
    ///
    /// Injecting into `tracks` rather than into each view is what makes this
    /// feature cheap: Easy View, Compare Mode's diff, the search index, CSV
    /// export and every copy action already read from tracks, so all of them
    /// gain the checksum without a line of their own.
    private func applyDigest(_ digest: String, sessionID: UUID, isCompare: Bool) {
        setHashState(.ready(digest: digest), sessionID: sessionID, isCompare: isCompare)
        refreshComparison()
    }
    
    /// Drop tasks that have already finished. Without this the arrays grew for
    /// the whole lifetime of the app, one entry per file ever opened.
    private func pruneFinishedTasks() {
        currentLoadTasks.removeAll { $0.isCancelled }
        compareLoadTasks.removeAll { $0.isCancelled }
    }
    
    private func track(_ task: Task<Void, Never>, isCompare: Bool) {
        pruneFinishedTasks()
        if isCompare {
            compareLoadTasks.append(task)
        } else {
            currentLoadTasks.append(task)
        }
    }
    
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
        analysisTimeoutSeconds = 60
        
        UserDefaults.standard.set(true, forKey: GlassPreference.key)
        // Reads the shipped default rather than naming a case, so Restore
        // Defaults can never drift away from what a fresh install gets. That
        // drift is exactly what happened when this line said `.always` and the
        // default moved to `.manual`.
        UserDefaults.standard.set(HashPolicy.shippedDefault.rawValue, forKey: HashPolicy.key)
        UserDefaults.standard.set(SharePrivacyMode.always.rawValue, forKey: PrivacyPreference.shareKey)
        UserDefaults.standard.set(LocalPrivacyMode.unmodified.rawValue, forKey: PrivacyPreference.localKey)
        UserDefaults.standard.set(LaunchPreference.restoreLastValue, forKey: LaunchPreference.key)
        
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
    
    // MARK: - Open (unified file + folder picker)
    
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = []    // empty = allow everything
        panel.treatsFilePackagesAsDirectories = false
        
        guard panel.runModal() == .OK,
              let url = panel.urls.first else {
            return
        }
        
        openURL(url)
    }
    
    /// Handles a file dropped while NOT in Compare Mode.
    ///
    /// PHASE 8c — holding Option opens the dropped file as File B and enters
    /// Compare Mode, rather than replacing what is already open. Comparing two
    /// files previously meant opening the first, pressing Compare, and picking
    /// the second through a panel; this makes it one gesture.
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
    
    func openURL(_ url: URL) {
        let normalised = url.standardized
        
        cancelCurrentTasks()
        
        var placeholder = MediaFile(url: normalised)
        placeholder.isLoading = true
        
        // The placeholder's id is this analysis session's identity. Every result
        // arriving later must carry it or it is discarded as stale.
        let sessionID = placeholder.id
        
        currentFile = placeholder
        refreshComparison()
        
        updateWindowTitle()
        addToRecentFiles(normalised)
        
        resolveMediaInfoVersion()
        
        if applyCachedAnalysis(for: normalised, sessionID: sessionID, isCompare: false) {
            updateWindowTitle()
        } else {
            let task = Task {
                await loadInitialFormats(
                    for: normalised,
                    sessionID: sessionID,
                    isCompare: false
                )
            }
            
            track(task, isCompare: false)
        }
        
        beginHashingIfNeeded(for: normalised, sessionID: sessionID, isCompare: false)
    }
    
    /// Fill a file from a cached analysis. Returns false when there is nothing
    /// usable, in which case the caller runs mediainfo as before.
    ///
    /// Tracks are re-parsed from the cached JSON rather than stored separately:
    /// MediaTrack holds tuples, which are not Codable, and one parse of a
    /// string already in memory is far cheaper than the subprocess it replaces.
    private func applyCachedAnalysis(for url: URL, sessionID: UUID, isCompare: Bool) -> Bool {
        guard let entry = AnalysisCache.entry(for: url),
              entry.hasInitialFormats,
              let json = entry.rawJSON else { return false }
        
        let tracks = MediaEngine.parseTracks(from: json)
        
        // A cache that produced no tracks is not worth trusting over a fresh
        // run — it more likely means a truncated write than a file with no
        // streams.
        guard !tracks.isEmpty else { return false }
        
        update(sessionID: sessionID, isCompare: isCompare) { file in
            file.rawText          = entry.rawText
            file.rawTextFull      = entry.rawTextFull
            file.rawJSON          = json
            file.rawHTML          = entry.rawHTML
            file.rawXML           = entry.rawXML
            file.tracks           = tracks
            
            file.isLoadingText    = false
            file.isLoadingRawText = false
            file.isLoadingJSON    = false
            file.isLoading        = false
        }
        
        // Checked after the file is on screen, so the prompt appears over
        // content rather than instead of it.
        if entry.isStale(against: mediaInfoVersion) {
            staleAnalysisURL = url
        }
        
        return true
    }
    
    func closeFile() {
        cancelCurrentTasks()
        cancelCompareTasks()
        
        currentFile   = nil
        compareFile   = nil
        isCompareMode = false
        refreshComparison()
        
        updateWindowTitle()
    }
    
    /// Re-run analysis for a file that failed. Used by the retry affordance.
    func retry(isCompare: Bool) {
        if isCompare {
            guard let url = compareFile?.url else { return }
            openCompareURL(url)
        } else {
            guard let url = currentFile?.url else { return }
            openURL(url)
        }
    }
    
    /// Re-run analysis after the MediaInfo tool has been installed.
    ///
    /// PHASE 9. Both sides are retried, because in Compare Mode both failed for
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
    
    func openCompareURL(_ url: URL) {
        let normalised = url.standardized
        
        resetDropState()
        cancelCompareTasks()
        
        var placeholder = MediaFile(url: normalised)
        placeholder.isLoading = true
        
        let sessionID = placeholder.id
        
        compareFile   = placeholder
        isCompareMode = true
        refreshComparison()
        
        resolveMediaInfoVersion()
        
        if !applyCachedAnalysis(for: normalised, sessionID: sessionID, isCompare: true) {
            let task = Task {
                await loadInitialFormats(
                    for: normalised,
                    sessionID: sessionID,
                    isCompare: true
                )
            }
            
            track(task, isCompare: true)
        }
        
        beginHashingIfNeeded(for: normalised, sessionID: sessionID, isCompare: true)
    }
    
    func exitCompareMode() {
        resetDropState()
        cancelCompareTasks()
        compareFile      = nil
        isCompareMode    = false
        showDiffHighlight = false
        refreshComparison()
    }
    
    // MARK: - Initial loading
    
    private func loadInitialFormats(
        for url: URL,
        sessionID: UUID,
        isCompare: Bool
    ) async {
        guard !Task.isCancelled else { return }
        
        let timeout = analysisTimeout
        
        // Fire all three mediainfo calls simultaneously. Each returns its own
        // Result so one format failing doesn't take the other two with it.
        async let textResult    = MediaEngine.fetchTextResult(url, timeout: timeout)
        async let rawFullResult = MediaEngine.fetchRawTextResult(url, timeout: timeout)
        async let jsonResult    = MediaEngine.fetchJSONResult(url, timeout: timeout)
        
        let (text, rawFull, json) = await (textResult, rawFullResult, jsonResult)
        
        guard !Task.isCancelled else { return }
        
        // Parse tracks off the main thread to keep the UI responsive on large files.
        let jsonString = json.value
        let tracks: [MediaTrack]
        
        if let jsonString {
            tracks = await Task.detached(priority: .userInitiated) {
                MediaEngine.parseTracks(from: jsonString)
            }.value
        } else {
            tracks = []
        }
        
        guard !Task.isCancelled else { return }
        
        update(sessionID: sessionID, isCompare: isCompare) { file in
            file.rawText          = text.value
            file.textError        = text.failure
            file.isLoadingText    = false
            
            file.rawTextFull      = rawFull.value
            file.rawTextError     = rawFull.failure
            file.isLoadingRawText = false
            
            file.rawJSON          = jsonString
            file.jsonError        = json.failure
            file.tracks           = tracks
            file.isLoadingJSON    = false
            
            // The primary error is whichever failure best explains a blank
            // screen. JSON drives Easy View — the default tab — so it wins.
            file.loadError = json.failure ?? text.failure ?? rawFull.failure
            
            file.isLoading = false
        }
        
        // Only a complete, successful analysis is worth remembering. Caching a
        // partial or failed run would serve the failure back on every reopen,
        // with no way to tell it apart from a real one.
        if json.failure == nil, text.failure == nil, rawFull.failure == nil,
           let jsonString, !tracks.isEmpty {
            let version = mediaInfoVersion ?? ""
            AnalysisCache.update(for: url) { entry in
                entry.mediaInfoVersion = version
                entry.rawText          = text.value
                entry.rawTextFull      = rawFull.value
                entry.rawJSON          = jsonString
            }
        }
        
        updateWindowTitle()
    }
    
    // MARK: - On-demand loading
    
    func loadFormatIfNeeded(_ mode: ViewMode, isCompare: Bool = false) {
        let fileRef: MediaFile? = isCompare ? compareFile : currentFile
        
        guard let file = fileRef,
              !file.isLoading else {
            return
        }
        
        let url       = file.url
        let sessionID = file.id
        let timeout   = analysisTimeout
        
        switch mode {
        case .text, .rawText, .easy, .json:
            break
            
        case .html:
            // Already have it, already fetching, or already failed → don't refire.
            guard file.rawHTML == nil,
                  file.isLoadingHTML == false,
                  file.htmlError == nil else {
                return
            }
            
            update(sessionID: sessionID, isCompare: isCompare) {
                $0.isLoadingHTML = true
            }
            
            let task = Task {
                guard !Task.isCancelled else { return }
                
                let result = await MediaEngine.fetchHTMLResult(url, timeout: timeout)
                
                guard !Task.isCancelled else { return }
                
                update(sessionID: sessionID, isCompare: isCompare) {
                    $0.rawHTML       = result.value
                    $0.htmlError     = result.failure
                    $0.isLoadingHTML = false
                }
                
                // Remembered so this tab is instant on every future open.
                if let html = result.value, result.failure == nil {
                    AnalysisCache.update(for: url) { $0.rawHTML = html }
                }
            }
            
            track(task, isCompare: isCompare)
            
        case .xml:
            guard file.rawXML == nil,
                  file.isLoadingXML == false,
                  file.xmlError == nil else {
                return
            }
            
            update(sessionID: sessionID, isCompare: isCompare) {
                $0.isLoadingXML = true
            }
            
            let task = Task {
                guard !Task.isCancelled else { return }
                
                let result = await MediaEngine.fetchXMLResult(url, timeout: timeout)
                
                guard !Task.isCancelled else { return }
                
                update(sessionID: sessionID, isCompare: isCompare) {
                    $0.rawXML       = result.value
                    $0.xmlError     = result.failure
                    $0.isLoadingXML = false
                }
                
                if let xml = result.value, result.failure == nil {
                    AnalysisCache.update(for: url) { $0.rawXML = xml }
                }
            }
            
            track(task, isCompare: isCompare)
        }
    }
    
    /// Clear a format's recorded failure so the retry button can try again.
    func clearError(for mode: ViewMode, isCompare: Bool) {
        let fileRef: MediaFile? = isCompare ? compareFile : currentFile
        guard let sessionID = fileRef?.id else { return }
        
        update(sessionID: sessionID, isCompare: isCompare) { file in
            switch mode {
            case .html:    file.htmlError = nil
            case .xml:     file.xmlError  = nil
            default:       break
            }
        }
    }
    
    // MARK: - Helper
    
    /// Applies a mutation only if the file currently on screen is still the one
    /// the caller was working on.
    ///
    /// This used to compare URLs. That failed in one real case: open file A,
    /// then open file A again before the first analysis finished — both tasks
    /// matched, so the older, slower result could land on top of the newer one.
    /// Comparing identity instead of path closes that.
    private func update(
        sessionID: UUID,
        isCompare: Bool,
        mutation: (inout MediaFile) -> Void
    ) {
        if isCompare {
            guard var file = compareFile,
                  file.id == sessionID else {
                return
            }
            
            mutation(&file)
            compareFile = file
            refreshComparison()
            
        } else {
            guard var file = currentFile,
                  file.id == sessionID else {
                return
            }
            
            mutation(&file)
            currentFile = file
            refreshComparison()
        }
    }
    
    // MARK: - Window title helper
    
    private func updateWindowTitle() {
        // PHASE 12c — was `NSApp.windows.first`, which is a latent bug: the
        // array is not ordered by importance, so with Settings or About open
        // the title could land on the wrong window. The Phase 12c window marker
        // gives an unambiguous answer, and the old behaviour is kept as a
        // fallback for the instant before the stamp is applied at launch.
        let document = NSApp.windows.first {
            $0.identifier?.rawValue == DocumentWindowMarker.identifier
        }
        
        (document ?? NSApp.windows.first)?.title = windowTitle
    }
    
    // MARK: - Recent files
    
    private func addToRecentFiles(_ url: URL) {
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
    private func replaceInRecents(_ old: URL, with new: URL) {
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
    
    // MARK: - File actions (Phase 8b)
    //
    // Five things you can do to the file rather than to the report about it.
    // Three happen immediately; the two that change the disk are staged here
    // and confirmed by UI hosted on ContentView, because a context menu has
    // already closed by the time its action runs and cannot present anything.
    
    // MARK: Analysis cache (Phase 10)
    
    /// The running mediainfo version, resolved once per launch.
    ///
    /// Cached entries are stamped with it. Asking mediainfo every time a file
    /// opens would put an extra subprocess in front of every analysis to
    /// answer a question whose answer cannot change while the app is running.
    @Published private(set) var mediaInfoVersion: String? = nil
    
    /// Set when an open file's cached analysis came from an older mediainfo.
    ///
    /// A prompt rather than a silent discard: the cached output is not wrong,
    /// it is just older, and re-reading is the user's call.
    @Published var staleAnalysisURL: URL? = nil
    
    func resolveMediaInfoVersion() {
        guard mediaInfoVersion == nil else { return }
        
        Task {
            let found = await MediaEngine.fetchVersion()
            await MainActor.run { self.mediaInfoVersion = found }
        }
    }
    
    /// The same lookup, awaitable, and able to ignore what is already known.
    ///
    /// PHASE 13l. Settings needs this in two places — the MediaInfo pane shows
    /// it, and the diagnostics summary includes it — and Re-detect has to be
    /// able to discard a cached answer, which `resolveMediaInfoVersion` above
    /// deliberately cannot.
    ///
    /// Both routes write to the same property. An earlier attempt at this added
    /// a second `mediaInfoVersion` to the store, which would have shadowed the
    /// one the analysis cache stamps its entries with — two properties of the
    /// same name holding what should always be one fact.
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
        
        if compareFile?.url == url, currentFile?.url != url {
            openCompareURL(url)
        } else {
            openURL(url)
        }
    }
    
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
        
        if pending.isCompare {
            openCompareURL(destination)
        } else {
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
        
        if pending.isCompare {
            cancelCompareTasks()
            compareFile = nil
        } else {
            cancelCurrentTasks()
            currentFile = nil
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
    
    /// Copies every field of one track as aligned "key: value" lines.
    func copyTrack(_ track: MediaTrack, from fileURL: URL?) {
        let fields = EasyFields.resolve(for: track)
        guard !fields.isEmpty else { return }
        
        // Padded to a common width so the values line up when pasted into a
        // monospaced context — a ticket, a commit message, a chat window.
        let widest = fields.map { FieldFormat.friendlyLabel($0.key).count }.max() ?? 0
        
        let body = fields.map { field in
            let label = FieldFormat.friendlyLabel(field.key)
            let padding = String(repeating: " ", count: max(0, widest - label.count))
            return "\(label)\(padding)  \(field.value)"
        }.joined(separator: "\n")
        
        copySnippet("\(track.displayTitle)\n\(body)", from: fileURL, actionName: "Copy")
    }
    
    private func writeToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    // MARK: - Open in default app
    //
    // PHASE 11. One funnel, for the same reason the checksum has one: the
    // launch used to be called directly from four separate places, and the
    // confirmation was bolted onto one of them. Anything added here later — a
    // recent-launch list, an error when nothing can open the file — lands on
    // all four routes at once instead of three of them silently missing out.
    
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
    
    /// Copies the current tab's output. Returns whether anything reached the
    /// clipboard.
    ///
    /// PHASE 11 — the return value is new, and it exists because the toolbar
    /// button now animates on success. Both of these calls can decline to copy:
    /// there may be no file open, and the privacy prompt can be cancelled. A
    /// button that flashed "Copied!" in either case would be telling the user
    /// something untrue about the contents of their clipboard, which is a bad
    /// thing for a button to do — the clipboard is invisible, so this button is
    /// the only evidence they have.
    ///
    /// Marked `@discardableResult` so existing callers that don't care still
    /// compile unchanged.
    @discardableResult
    func copyToClipboard() -> Bool {
        guard let content = currentOutputString(),
              let url = currentFile?.url else {
            return false
        }
        
        // Asked once per action, not once per document — a multi-file export
        // shouldn't interrogate the user repeatedly about the same question.
        guard let shouldRemovePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Copy"
        ) else { return false }
        
        let output = shouldRemovePaths
        ? PrivacySanitizer.sanitize(content, fileURL: url).text
        : content
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        
        return true
    }
    
    @discardableResult
    func copyToClipboard(source: CopySource) -> Bool {
        guard let shouldRemovePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Copy"
        ) else { return false }
        
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
            let a = prepared(outputStringForFile(currentFile), currentFile) ?? ""
            let b = prepared(outputStringForFile(compareFile), compareFile) ?? ""
            
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
        NSPasteboard.general.setString(content, forType: .string)
        
        return true
    }
    
    
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
