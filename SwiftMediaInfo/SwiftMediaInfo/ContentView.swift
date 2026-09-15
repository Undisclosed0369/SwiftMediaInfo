//
//  ContentView.swift
//  SwiftMediaInfo
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: MediaStore
    @Environment(\.openWindow) private var openWindow
    @State private var isTargeted = false
    
    /// The window-wide drop highlight, shown only in single-file mode.
    ///
    /// In Compare Mode each pane owns its own highlight, in its own colour, so
    /// a window-wide violet wash would be both wrong and misleading — it was
    /// what made a compare drop look like it would land anywhere.
    ///
    /// The `isDragSessionActive` gate is what stops the highlight outliving the
    /// drag. Both of the other two inputs can go stale:
    ///
    /// • `isTargeted` is SwiftUI's own flag, and SwiftUI only sends this view an
    ///   "exited" when *this* view's target ends the drag. When a Compare pane
    ///   consumed the drop instead, the flag was left true. Compare Mode being
    ///   on hid it — and the moment Compare Mode exited, the stale true had
    ///   nothing suppressing it and the overlay appeared permanently.
    ///
    /// • `externalDropTarget` is cleared on a delay, so it too can lag.
    ///
    /// The session flag is the one value that is authoritative about whether a
    /// drag is in progress, so it decides.
    private var showDropHighlight: Bool {
        guard !store.isCompareMode else { return false }
        guard store.isDragSessionActive else { return false }
        return isTargeted || store.externalDropTarget == .main
    }
    
    /// Wording for the plain (no modifier) drop overlay.
    ///
    /// When a file is already open, the overlay names the Option gesture. That
    /// is the only place it is advertised — a modifier that is never mentioned
    /// is one only the person who wrote it knows about.
    private var dropHint: String {
        store.isOptionCompareAvailable
        ? "Drop to open  ·  hold ⌥ to compare"
        : "Drop to open here"
    }
    
    var body: some View {
        ZStack {
            // ── Gradient wallpaper (behind everything) ──────────────────────
            //
            // PHASE 12b — no longer guarded here. The view owns all three
            // modes, including Off, in which it draws nothing. One place that
            // knows what the setting means, rather than four.
            GradientBackground()
                .transition(.opacity)
            
            // ── Main layout ────────────────────────────────────────────────
            VStack(spacing: 0) {
                ToolbarView()
                SpectrumDivider()
                MainDetailView()
                SpectrumDivider()
                StatusBar()
            }
            
            // ── Search bar overlay ─────────────────────────────────────────
            SearchBarOverlay()
            
            // ── Drop highlight overlay ─────────────────────────────────────
            //
            // `showDropHighlight` combines SwiftUI's own drag tracking with the
            // signal from HTMLView. The HTML tab hosts a WKWebView, which
            // intercepts drags before SwiftUI ever sees them, so without that
            // second source the overlay would vanish over one tab out of six.
            //
            // PHASE 8c — the overlay changes colour and wording while Option
            // is held, because a modifier nobody can see is a feature nobody
            // finds.
            //
            // Teal, because the other candidates are all spoken for: violet is
            // the ordinary drop, blue and pink are File A and File B, and green
            // already means "open on its own" in Compare Mode's centre zone.
            // A colour that means two things is worse than an unfamiliar one.
            if showDropHighlight {
                GlassDropOverlay(
                    color: store.willCompareOnDrop ? .brandTeal : .brandViolet,
                    message: store.willCompareOnDrop
                    ? "Compare with this file"
                    : dropHint
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        // PHASE 12c — stamps this window so ⌘W can tell it apart from Settings,
        // About and Keyboard Shortcuts. See MediaInfoMacApp.handleCloseCommand.
        .background(DocumentWindowMarker())
        // Report the window size so auxiliary windows can cap their zoom
        // against it rather than growing past the app itself.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { store.mainWindowSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in
                        store.mainWindowSize = newValue
                    }
            }
        )
        .smiAnimation(SMI.Motion.snap, value: showDropHighlight)
        .smiAnimation(SMI.Motion.fade, value: store.willCompareOnDrop)
        // Binding the `isTargeted` parameter is what makes the highlight appear
        // while a file is held over the window. It was previously passed as
        // nil, so the flag was only flipped inside the drop handler — the
        // overlay flashed for a third of a second *after* the drop and was
        // never visible during the drag it was meant to guide.
        // The registered type list is deliberately constant.
        //
        // This previously read `of: store.isCompareMode ? [] : [.fileURL]` to
        // switch the handler off during Compare Mode. Varying the registered
        // types does not reliably re-register the target when it flips back, so
        // once the list had been empty the window-wide drop target stayed dead
        // for the rest of the session. Tabs backed by AppKit views kept working
        // because they handle drops themselves; Easy View, being pure SwiftUI,
        // had nothing to fall back on and stopped accepting files entirely.
        //
        // Compare Mode is now handled inside the closure instead. The panes are
        // descendants of this view, so their own drop targets take precedence
        // and this only ever sees drops they declined — which, in Compare Mode,
        // means the dead zone, where doing nothing is the correct answer.
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers, _ in
            guard !store.isCompareMode else { return false }
            
            isTargeted = false
            store.endDragSession(from: .main)
            
            Task { @MainActor in
                if let provider = providers.first,
                   let item = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                   ),
                   let data = item as? Data,
                   let url  = URL(dataRepresentation: data, relativeTo: nil) {
                    // PHASE 8c — honours the Option key: see openDropped.
                    store.openDropped(url)
                }
            }
            return true
        }
        // This view takes part in the shared drag session like every other drop
        // target, so a drag it handles alone — Easy View, which has no AppKit
        // view beneath it — still registers as a session and the highlight can
        // be gated on one consistent signal.
        .onChange(of: isTargeted) { _, targeted in
            guard !store.isCompareMode else { return }
            if targeted {
                store.beginDragSession()
                store.reportDropTarget(.main, from: .main)
            } else {
                store.reportDropTarget(nil, from: .main)
                store.endDragSession(from: .main)
            }
        }
        // Resynchronise when the session ends.
        //
        // SwiftUI will not clear `isTargeted` for a drag that some other view
        // consumed, so without this a stale true survives into the next drag —
        // where `onChange` would not fire either, since the value never
        // changed. Forcing it false on session end keeps the two in step.
        .onChange(of: store.isDragSessionActive) { _, active in
            if !active && isTargeted {
                isTargeted = false
            }
        }
        .sheet(isPresented: $store.showShareResult) {
            ShareResultView()
                .environmentObject(store)
        }
        .alert("Unsupported Mode",
               isPresented: $store.showDiffUnsupportedPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Difference highlighting is only available in Easy View, Text View, and Raw Text View. Please switch to one of these modes to use this feature.")
        }
        // ── Phase 8b: file actions ─────────────────────────────────────
        //
        // Both confirmations live here rather than beside the menus that
        // trigger them. A context menu has already closed by the time its
        // action runs, so it has nothing left to present from; this view is
        // always on screen.
        .sheet(item: $store.pendingRename) { pending in
            RenameFileSheet(pending: pending)
                .environmentObject(store)
        }
        // `presenting:` rather than reading the store inside the button.
        // SwiftUI holds the presented value for the lifetime of the alert, so
        // the action still has the file even though dismissing the alert
        // clears the binding first.
        .alert(
            "Move to Trash?",
            isPresented: Binding(
                get: { store.pendingTrash != nil },
                set: { if !$0 { store.pendingTrash = nil } }
            ),
            presenting: store.pendingTrash
        ) { pending in
            // Return confirms. Making a destructive button the default is
            // normally something to avoid, but this one is already behind a
            // deliberate menu choice and its undo is the Trash itself — and
            // an alert where Return does nothing feels broken. Escape still
            // cancels, via the cancel role.
            Button("Move to Trash", role: .destructive) {
                store.commitTrash(pending)
            }
            .keyboardShortcut(.defaultAction)
            
            Button("Cancel", role: .cancel) {
                store.pendingTrash = nil
            }
        } message: { pending in
            Text("“\(pending.url.lastPathComponent)” will be moved to the Trash. You can put it back from there until the Trash is emptied.")
        }
        // PHASE 10 — the open file's cached analysis came from an older
        // MediaInfo. Not an error: the output is not wrong, only older, so it
        // is offered rather than discarded. The checksum is kept either way,
        // since the bytes are unchanged.
        .alert(
            "MediaInfo Has Been Updated",
            isPresented: Binding(
                get: { store.staleAnalysisURL != nil },
                set: { if !$0 { store.staleAnalysisURL = nil } }
            ),
            presenting: store.staleAnalysisURL
        ) { _ in
            Button("Analyse Again") { store.reanalyseAfterUpgrade() }
            Button("Keep Cached Version", role: .cancel) { store.staleAnalysisURL = nil }
        } message: { url in
            Text("The saved analysis for “\(url.lastPathComponent)” was produced by an earlier version of MediaInfo, which may report fewer fields. Analysing again keeps the existing checksum.")
        }
        .alert(
            "Couldn’t Complete That Action",
            isPresented: Binding(
                get: { store.fileActionError != nil },
                set: { if !$0 { store.fileActionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.fileActionError = nil }
        } message: {
            Text(store.fileActionError ?? "")
        }
        .background(
            Color.clear
                .onAppear { installArrowKeyMonitor() }
                .onDisappear { removeArrowKeyMonitor() }
        )
        .background(
            WindowReader { window in
                if hostWindow !== window { hostWindow = window }
            }
        )
        .background(
            Group {
                Button("") { store.showExportMenu = true }
                    .keyboardShortcut("e", modifiers: .command)
                
                Button("") { handleCompareShortcut() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("") { handleOpenInDefaultApp() }
                    .keyboardShortcut(.return, modifiers: .command)
                
                // ⌘B — cycles the background rather than toggling it, since
                // there are three modes as of Phase 12b.
                Button("") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        store.cycleBackgroundMode()
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                
                // Toggle diff highlighting (⌘D)
                Button("") {
                    if store.isCompareMode {
                        if [ViewMode.easy, .text, .rawText].contains(store.viewMode) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.showDiffHighlight.toggle()
                            }
                        } else {
                            store.showDiffUnsupportedPrompt = true
                        }
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                
                // Show keyboard shortcuts (⌘K)
                Button("") { openWindow(id: "shortcuts-window") }
                    .keyboardShortcut("k", modifiers: .command)
                
                // Toggle search bar (⌘F)
                Button("") { store.toggleSearchBar() }
                    .keyboardShortcut("f", modifiers: .command)
                
                Button("") { store.zoomIn()  }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.zoomIn()  }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("") { store.resetZoom() }.keyboardShortcut("0", modifiers: .command)
                
                Button("") { store.cycleAppearance() }
                    .keyboardShortcut("m", modifiers: .command)
                
                Button("") { handleShortcut(1) }.keyboardShortcut("1", modifiers: .command)
                Button("") { handleShortcut(2) }.keyboardShortcut("2", modifiers: .command)
                Button("") { handleShortcut(3) }.keyboardShortcut("3", modifiers: .command)
                Button("") { handleShortcut(4) }.keyboardShortcut("4", modifiers: .command)
                Button("") { handleShortcut(5) }.keyboardShortcut("5", modifiers: .command)
                Button("") { handleShortcut(6) }.keyboardShortcut("6", modifiers: .command)
            }
                .opacity(0)
        )
    }
    
    /// ⌘↩ — open the file in whatever app owns it.
    ///
    /// PHASE 8c. This used to open File A unconditionally, because the A/B
    /// picker's presentation flag was private @State inside the toolbar button
    /// and a shortcut handled here could not reach it. The flag now lives on
    /// the store, so the shortcut opens the same picker the button does.
    ///
    /// With only one file loaded there is nothing to choose between, so it
    /// opens that file directly — a picker offering a single option is a
    /// question with one answer.
    private func handleOpenInDefaultApp() {
        if store.isCompareMode,
           store.currentFile != nil,
           store.compareFile != nil {
            store.showOpenInAppPicker = true
            return
        }
        
        if let url = store.currentFile?.url ?? store.compareFile?.url {
            // Through the store, so ⌘↩ flashes the toolbar button like a
            // click on it does.
            store.openInDefaultApp(url)
        }
    }
    
    private func handleCompareShortcut() {
        if store.isCompareMode {
            store.exitCompareMode()
        } else {
            if store.currentFile == nil { store.openFilePicker() }
            store.openCompareFilePicker()
        }
    }
    
    private func handleShortcut(_ number: Int) {
        if store.isCompareMode {
            switch number {
            case 1: store.openFilePicker()
            case 2: store.openCompareFilePicker()
            default:
                if let mode = ViewMode.allCases.first(where: {
                    $0.shortcut == KeyEquivalent(Character(String(number)))
                }) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        store.viewMode = mode
                    }
                }
            }
        } else {
            if let mode = ViewMode.allCases.first(where: {
                $0.shortcut == KeyEquivalent(Character(String(number)))
            }) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    store.viewMode = mode
                }
            }
        }
    }
    
    // MARK: - Arrow key search navigation
    
    @State private var arrowKeyMonitor: Any? = nil
    
    /// The window this ContentView lives in.
    ///
    /// `addLocalMonitorForEvents` is application-wide, so without this the
    /// monitor below would also swallow Escape in the Settings and Keyboard
    /// Shortcuts windows — where Escape already means "close me".
    @State private var hostWindow: NSWindow? = nil
    
    /// The file the single-file shortcuts act on, or nil when they should not
    /// fire at all.
    ///
    /// Compare Mode is excluded on purpose: with two files open, a key
    /// equivalent cannot ask which one you meant. The File menu offers File A
    /// and File B as separate submenus there instead.
    private var shortcutTargetURL: URL? {
        guard !store.isCompareMode,
              store.pendingRename == nil,
              store.pendingTrash == nil,
              let file = store.currentFile else { return nil }
        
        return file.url
    }
    
    private func installArrowKeyMonitor() {
        guard arrowKeyMonitor == nil else { return }
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key   = event.charactersIgnoringModifiers?.lowercased() ?? ""
            
            // ── 1. Protect text editing from ⌘⌫ ────────────────────────
            //
            // Checked before anything else, and deliberately not scoped to one
            // window — the rename sheet is a window of its own. Inside a text
            // field ⌘⌫ means "clear to the start of the line", and that has to
            // beat the File menu's Move to Trash. A local event monitor is the
            // only thing that runs earlier than a menu's key equivalent.
            if event.keyCode == 51,
               flags == .command,
               let editor = event.window?.firstResponder as? NSTextView,
               editor.isFieldEditor {
                editor.deleteToBeginningOfLine(nil)
                return nil
            }
            
            // Everything below belongs to the main window only. Permissive
            // while the window is still unknown, so nothing breaks at launch.
            if let hostWindow = self.hostWindow, event.window !== hostWindow {
                return event
            }
            
            // ── 2. File-action shortcuts ───────────────────────────────
            //
            // Handled here rather than left to the menu. The menu items still
            // declare the same keys so the menu displays them, but this
            // monitor consumes the event first, so they can never both fire.
            // It also sidesteps ⇧⌘R never reaching the menu item at all.
            if let url = self.shortcutTargetURL {
                if event.keyCode == 51, flags == .command {
                    self.store.perform(.trash, on: url, isCompare: false)
                    return nil
                }
                
                if key == "r", flags == [.command, .shift] {
                    self.store.perform(.reveal, on: url, isCompare: false)
                    return nil
                }
                
                if key == "c", flags == [.command, .option] {
                    self.store.perform(.copyPath, on: url, isCompare: false)
                    return nil
                }
            }
            
            // ── 3. Search bar ──────────────────────────────────────────
            guard self.store.showSearchBar else { return event }
            
            // Escape closes the search bar from anywhere in the window,
            // including from inside the text field. Handled here rather than
            // with `onExitCommand` because the field editor consumes the key
            // before SwiftUI sees it — so the one moment you most want Escape
            // to work was the one moment it did not.
            if event.keyCode == 53 {
                self.store.toggleSearchBar()
                return nil
            }
            
            guard !self.store.searchQuery.isEmpty else { return event }
            
            // Only intercept if the search text field is NOT focused
            if let responder = event.window?.firstResponder as? NSTextView,
               responder.isFieldEditor {
                return event  // let the search bar handle typing
            }
            
            switch event.keyCode {
            case 125, 124:  // Down arrow, Right arrow → next match
                guard self.store.searchMatchCount > 0 else { return event }
                self.store.searchMatchIndex = (self.store.searchMatchIndex + 1) % self.store.searchMatchCount
                return nil
            case 126, 123:  // Up arrow, Left arrow → previous match
                guard self.store.searchMatchCount > 0 else { return event }
                self.store.searchMatchIndex = (self.store.searchMatchIndex - 1 + self.store.searchMatchCount) % self.store.searchMatchCount
                return nil
            default:
                return event
            }
        }
    }
    
    private func removeArrowKeyMonitor() {
        if let monitor = arrowKeyMonitor {
            NSEvent.removeMonitor(monitor)
            arrowKeyMonitor = nil
        }
    }
}

// MARK: - Window reader
//
// Reports the NSWindow this view was placed in. Used to scope the key monitor
// to the main window: local event monitors are application-wide, so without a
// window to compare against, Escape intended for the search bar would also be
// swallowed in Settings and Keyboard Shortcuts.
//
// The lookup is deferred by one turn of the run loop because a view's `window`
// is nil until it has actually been added to a hierarchy.

private struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // The window can change — a view can be moved between windows, and on
        // launch the first resolution can land before the window exists.
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

// MARK: - Document window marker
//
// PHASE 12c.
//
// ⌘W has to behave differently depending on which window is in front: close the
// open file in the document window, close the window itself in Settings, About
// or Keyboard Shortcuts. That means being able to tell them apart, reliably,
// from AppKit.
//
// Guessing was the alternative, and every version of the guess was bad. Window
// titles are user-facing text that changes with the open file. SwiftUI's own
// internal window identifiers are undocumented and free to change between
// macOS releases. Resizability is a coincidence, not a fact about identity.
//
// So the window is stamped explicitly, by the view that only ever lives in it.
// One string, set once, checked once.

struct DocumentWindowMarker: NSViewRepresentable {
    static let identifier = "smi-document-window"
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        
        // The window is not attached yet during `makeNSView`, so the stamp has
        // to wait for the view to be installed in a hierarchy.
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // A window can be recycled — restored on relaunch, or reused when the
        // last one closed — so the stamp is reapplied rather than assumed.
        if nsView.window?.identifier?.rawValue != Self.identifier {
            nsView.window?.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        }
    }
}
