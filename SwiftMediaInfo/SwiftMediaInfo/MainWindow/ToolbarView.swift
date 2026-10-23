//
//  ToolbarView.swift
//  SwiftMediaInfo
//
//  The main window's toolbar, left to right: Open, File Actions, Open in App;
//  Compare and Ask Siri; the view-mode bar (Easy … JSON); appearance and
//  zoom; Copy, Share and Export.
//
//  Also the menus those buttons open: the Compare picker, Open in App's
//  File A / File B choice, and the Copy and Export menus (single-file and
//  Compare Mode), with the shared format list (ExportFormatList) that Share
//  reuses. Their rows and titles come from PopoverChrome; Share's menus are
//  in ShareUploadView; File Actions' in FileActions.
//
//  Flags that a keyboard shortcut also has to set (the Compare picker, Open
//  in App's picker, the Export menu) live on the store, not in @State here.
//

import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var store: MediaStore
    
    /// Siri AI's switch in Settings, so turning it off removes the button at
    /// once.
    @AppStorage(IntelligencePreference.enabledKey) private var siriEnabled = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                
                // ── LEFT: File actions ────────────────────────────────────
                //
                // Three buttons, in the order you use them: choose a file,
                // act on the file, hand the file to another app.
                //
                // The background setting is deliberately not here — it's a
                // display preference, not a file action. ⌘B cycles it, and
                // Settings › Appearance has it.
                HStack(spacing: 4) {
                    // Unified Open button (picks files OR folders)
                    GlassButton(
                        icon: "doc.badge.plus",
                        label: "Open",
                        accentColor: .brandBlue
                    ) { store.openFilePicker() }
                        .help("Open file or folder (⌘O)")
                    
                    // Actions on the file itself, as opposed to the report
                    // about it. Copy, Share and Export on the right are all
                    // about its metadata.
                    FileActionsButton()
                    
                    // Open in Default App (no folder button next to it)
                    //
                    // This one hands the file to another application, which can
                    // take a second or two to appear, so it says "Opening…" for
                    // a moment rather than looking broken.
                    ToolbarActionButton(
                        icon: "play.rectangle",
                        label: "Open in App",
                        accentColor: .brandGreen,
                        isActive: store.showOpenInAppPicker,
                        isSuccessful: store.didLaunchInApp,
                        successIcon: "arrow.up.forward.app.fill",
                        successLabel: "Opening…",
                        isDisabled: !store.hasOpenReport,
                        help: "Open in default app (⌘↩)",
                        voiceOverLabel: "Open in default app",
                        voiceOverHint: store.isCompareMode
                        ? "Opens a menu to choose File A or File B"
                        : "Hands this file to whichever app normally opens it"
                    ) {
                        if store.isCompareMode {
                            // fall through to popover below
                        } else if let url = store.currentFile?.url {
                            store.openInDefaultApp(url)
                        }
                    }
                    .overlay(
                        // Preserve compare-mode popover behaviour
                        store.isCompareMode ? AnyView(OpenInDefaultAppButton()) : AnyView(EmptyView())
                    )
                }
                .liquidGlass(cornerRadius: 14, tintColor: .brandBlue, borderOpacity: 0.2)
                // These three name themselves in full. If the window ever gets
                // narrow enough that something has to give, the tab bar gives
                // first — its labels sit under icons that already identify it.
                .layoutPriority(1)
                
                // ── Compare ───────────────────────────────────────────────
                GlassButton(
                    icon: store.isCompareMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                    label: store.isCompareMode ? "Exit Compare" : "Compare",
                    accentColor: store.isCompareMode ? .brandPink : .brandViolet,
                    isActive: store.isCompareMode
                ) { handleCompareButton() }
                    .liquidGlass(
                        cornerRadius: 14,
                        tintColor: store.isCompareMode ? .brandPink : .brandViolet,
                        borderOpacity: store.isCompareMode ? 0.35 : 0.2
                    )
                    .help(store.isCompareMode ? "Exit Compare Mode (⇧⌘C)" : "Compare two files side by side (⇧⌘C)")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.isCompareMode)
                    .popover(isPresented: $store.showComparePicker, arrowEdge: .bottom) {
                        ComparePickerPopover()
                            .environmentObject(store)
                    }
                
                // ── Siri AI ───────────────────────────────────────────────
                //
                // Beside Compare: both are ways of understanding the file
                // rather than doing something to it, and in Compare Mode this
                // one compares the two files. Only on Macs that support Apple
                // Intelligence, on macOS 27 or later, with the setting on.
                if siriEnabled, IntelligenceStatus.showsEntryPoints {
                    GlassButton(
                        icon: "siri",
                        label: "Ask Siri",
                        accentColor: .brandPink,
                        isActive: store.explainTarget != nil,
                        isDisabled: !store.canExplain,
                        voiceOverLabel: "Ask Siri AI",
                        voiceOverHint: store.isCompareMode
                        ? "Compares File A and File B, on this Mac"
                        : "Asks about this file, on this Mac"
                    ) { store.showExplain() }
                        .liquidGlass(cornerRadius: 14, tintColor: .brandPink, borderOpacity: 0.2)
                        .help(store.isCompareMode
                              ? "Ask Siri AI to compare these files (⇧⌘I)"
                              : "Ask Siri AI about this file (⇧⌘I)")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                // ── CENTRE: View modes ────────────────────────────────────
                LiquidGlassTabBar()
                
                Spacer(minLength: 0)
                
                // ── RIGHT: Controls ───────────────────────────────────────
                HStack(spacing: 4) {
                    // Appearance
                    GlassButton(
                        icon: appearanceIcon,
                        label: appearanceLabel,
                        accentColor: .brandViolet
                    ) { store.cycleAppearance() }
                        .help("Cycle appearance: Light, Dark, System (⌘M)")
                    
                    // Zoom out
                    //
                    // An empty `label` is right for the eye (the
                    // magnifier glyphs need no caption) and wrong for the ear:
                    // an unlabelled button is announced as "button", full stop.
                    // The tooltip already had the words; this hands the same
                    // words to VoiceOver.
                    GlassButton(
                        icon: "minus.magnifyingglass",
                        label: "",
                        accentColor: .brandBlue,
                        voiceOverLabel: "Zoom out"
                    ) {
                        store.zoomOut()
                        
                    }
                    .help("Zoom out (⌘-)")
                    
                    // Zoom % label
                    Text("\(Int((store.fontSize / 12.0) * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    // Short enough that wrapping it is never the right
                    // answer — it wrapped to "125 / %" once the file
                    // buttons started insisting on their full width.
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(
                            store.showZoomFlash
                            ? AnyShapeStyle(LinearGradient(
                                colors: [.brandBlue, .brandViolet],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            : AnyShapeStyle(Color.primary.opacity(0.7))
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.showZoomFlash
                                      ? Color.brandViolet.opacity(0.12)
                                      : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(store.showZoomFlash
                                              ? Color.brandViolet.opacity(0.25)
                                              : Color.primary.opacity(0.08),
                                              lineWidth: 0.6)
                        )
                        .animation(.easeInOut(duration: 0.25), value: store.showZoomFlash)
                        .animation(.easeInOut(duration: 0.15), value: store.fontSize)
                    // "125 %" read out as a bare number sitting between two
                    // buttons means nothing. Named and given a value, it reads
                    // as "Zoom level, 125 percent" — and `.updatesFrequently`
                    // tells VoiceOver to re-read it when it changes rather than
                    // holding the figure it saw when focus arrived.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Zoom level")
                        .accessibilityValue("\(Int((store.fontSize / 12.0) * 100)) percent")
                        .accessibilityAddTraits(.updatesFrequently)
                    
                    // Zoom in
                    GlassButton(
                        icon: "plus.magnifyingglass",
                        label: "",
                        accentColor: .brandBlue,
                        voiceOverLabel: "Zoom in"
                    ) {
                        store.zoomIn()
                        
                    }
                    .help("Zoom in (⌘+)")
                }
                .liquidGlass(cornerRadius: 14, tintColor: .brandViolet, borderOpacity: 0.2)
                
                // Copy + Share + Export
                HStack(spacing: 4) {
                    CopyButton()
                    ShareButton()
                    ExportMenuButton()
                }
                .liquidGlass(cornerRadius: 14, tintColor: .brandGreen, borderOpacity: 0.2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Helpers
    
    private func handleCompareButton() {
        store.beginCompare()
    }
    
    private var appearanceIcon: String {
        switch store.appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
    
    private var appearanceLabel: String {
        switch store.appearanceMode {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

// MARK: - Open in Default App Button

struct OpenInDefaultAppButton: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        // In compare mode this overlays a transparent tap target.
        //
        // The presentation flag lives on the store rather than in this view's
        // @State, so ⌘↩ (handled in ContentView) can raise the same picker.
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { store.showOpenInAppPicker = true }
            .popover(isPresented: $store.showOpenInAppPicker, arrowEdge: .bottom) {
                OpenInAppPopover()
                    .environmentObject(store)
            }
    }
    
    static func openInDefaultApp(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path(percentEncoded: false)]
        process.standardOutput = Pipe()
        process.standardError  = Pipe()
        try? process.run()
    }
}

// MARK: - Compare picker

/// "Compare “A” with…" — the other open tabs, favorites and recent files,
/// then a file picker.
struct ComparePickerPopover: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compare With")
                    .font(.headline)
                if let fileA = store.currentFile {
                    Text(fileA.fileName)
                        .font(SMI.Typo.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !store.compareCandidates.isEmpty {
                        sectionTitle("Open Tabs")
                        ForEach(store.compareCandidates) { tab in
                            row(icon: FileTabBar.symbol(for: tab.file.url), title: tab.file.fileName) {
                                store.showComparePicker = false
                                store.compare(withTab: tab.id)
                            }
                        }
                    }
                    
                    let favorites = store.favoriteCompareCandidates
                    if !favorites.isEmpty {
                        sectionTitle("Favorites")
                        FoldingPickerRows(urls: favorites, icon: { _ in "star.fill" }) { url in
                            store.showComparePicker = false
                            store.openCompareURL(url)
                        }
                    }
                    
                    let recents = store.recentCompareCandidates
                    if !recents.isEmpty {
                        sectionTitle("Recent Files")
                        FoldingPickerRows(urls: recents, icon: { FileTabBar.symbol(for: $0) }) { url in
                            store.showComparePicker = false
                            store.openCompareURL(url)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            
            Divider()
            
            row(icon: "folder", title: "Choose a File…") {
                store.showComparePicker = false
                // After the popover has gone, so the panel is not parented to it.
                DispatchQueue.main.async { store.openCompareFilePicker() }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 300)
    }
    
    private func row(icon: String, title: String, action: @escaping () -> Void) -> some View {
        ComparePickerRow(icon: icon, title: title, action: action)
    }
    
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(SMI.Typo.micro)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

/// A list's first few files, then "N More", which shows the rest as soon
/// as the pointer reaches it (or on a click).
private struct FoldingPickerRows: View {
    let urls: [URL]
    let icon: (URL) -> String
    let action: (URL) -> Void
    @State private var isExpanded = false

    var body: some View {
        let shown = isExpanded ? urls : Array(urls.prefix(ListFolding.shownCount))
        ForEach(shown, id: \.self) { url in
            ComparePickerRow(icon: icon(url), title: url.lastPathComponent) { action(url) }
        }
        if !isExpanded, urls.count > ListFolding.shownCount {
            ComparePickerRow(
                icon: "chevron.down",
                title: "\(urls.count - ListFolding.shownCount) More",
                action: expand,
                onHoverStart: expand
            )
        }
    }

    private func expand() {
        smiWithAnimation(SMI.Motion.smooth) { isExpanded = true }
    }
}

private struct ComparePickerRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    /// For a row that acts as soon as the pointer reaches it.
    var onHoverStart: (() -> Void)? = nil
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: SMI.Spacing.small) {
                Image(systemName: icon)
                    .foregroundStyle(Color.brandPink)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.chip, style: .continuous)
                    .fill(isHovering ? SMI.Palette.hoverWash : .clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { onHoverStart?() }
        }
    }
}

// MARK: - Open in Default App — Compare Popover

struct OpenInAppPopover: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverTitle(text: "Open in Default App")
            
            Divider()
            
            if let fileA = store.currentFile {
                PopoverMenuItem(title: "File A — \(fileA.fileName)", icon: "doc") {
                    store.showOpenInAppPicker = false
                    store.openInDefaultApp(fileA.url)
                }
            }
            
            if let fileB = store.compareFile {
                PopoverMenuItem(title: "File B — \(fileB.fileName)", icon: "doc.fill") {
                    store.showOpenInAppPicker = false
                    store.openInDefaultApp(fileB.url)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 260)
    }
}

// MARK: - Copy Button
//
// The clipboard is invisible, so Copy has to say when it worked. It uses
// ToolbarActionButton's state vocabulary: hover, press, and
// a success state that swaps the glyph for a filled check, the word for
// "Copied!", the tint for the success gradient, and swells very slightly. It
// holds that for 1.4 seconds and settles back.
//
// 1.4 s is the same figure the Easy View field-copy affordance uses (1.1 s plus
// its fade). Long enough to register if you looked away at the moment you
// clicked; short enough that a second copy doesn't feel like it's queueing
// behind the first.
//
// IT ONLY CELEBRATES A COPY THAT HAPPENED
//
// `copyToClipboard` returns whether it copied. With no file open, or with
// the privacy prompt cancelled, nothing reaches the clipboard — and the button
// stays exactly as it was rather than claiming otherwise.
//
// IN COMPARE MODE
//
// The button opens the file picker popover instead of copying, so the flash
// belongs to the popover's choice. The popover reports back through `onCopied`
// and the button flashes once it has closed, which puts the confirmation where
// the user is already looking.

struct CopyButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    @State private var didCopy = false
    
    /// Held so a second copy restarts the timer rather than being cut short by
    /// the first one's pending reset. Without this, two copies 1.3 s apart
    /// leave the check visible for 0.1 s.
    @State private var resetTask: Task<Void, Never>? = nil
    
    var body: some View {
        ToolbarActionButton(
            icon: "doc.on.doc",
            label: "Copy",
            accentColor: .brandGreen,
            isSuccessful: didCopy,
            successLabel: "Copied!",
            isDisabled: !store.hasOpenReport,
            help: store.isCompareMode
            ? "Choose a file to copy to the clipboard"
            : "Copy this report to the clipboard",
            voiceOverLabel: "Copy report",
            voiceOverHint: store.isCompareMode
            ? "Opens a menu to choose File A, File B or both"
            : "Copies the current view to the clipboard"
        ) {
            if store.isCompareMode {
                showPopover = true
            } else if store.copyToClipboard() {
                flashSuccess()
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            CopyPopover(isPresented: $showPopover) {
                flashSuccess()
            }
            .environmentObject(store)
        }
    }
    
    private func flashSuccess() {
        resetTask?.cancel()
        
        smiWithAnimation(SMI.Motion.snap) { didCopy = true }
        
        // The visual flash is worth nothing to someone using VoiceOver: focus
        // never moved, so there is no reason for it to say anything. This is
        // the audible half of the same confirmation.
        SMI.A11y.announce("Copied to clipboard")
        
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            smiWithAnimation(SMI.Motion.fade) { didCopy = false }
        }
    }
}

// MARK: - Copy Popover (compare mode)

struct CopyPopover: View {
    @EnvironmentObject var store: MediaStore
    @Binding var isPresented: Bool
    
    /// Called only when something actually reached the clipboard, so the
    /// toolbar button behind the popover can flash.
    var onCopied: () -> Void = {}
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverTitle(text: "Copy to Clipboard")
                .accessibilityAddTraits(.isHeader)
            
            Divider()
            
            ForEach([CopySource.fileA, .fileB, .both], id: \.self) { source in
                PopoverMenuItem(title: source.label, icon: source.icon) {
                    isPresented = false
                    if store.copyToClipboard(source: source) {
                        onCopied()
                    }
                }
                .accessibilityLabel("Copy \(source.label)")
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 200)
    }
}

// MARK: - Export Menu Button

struct ExportMenuButton: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        // Same component as Copy and Share. No success state: Export opens a
        // save panel, and the panel is its own confirmation.
        ToolbarActionButton(
            icon: "square.and.arrow.up",
            label: "Export",
            accentColor: .brandGreen,
            isActive: store.showExportMenu,
            isDisabled: !store.hasOpenReport,
            help: "Export report (⌘E)",
            voiceOverLabel: "Export report",
            voiceOverHint: "Opens a menu of export formats"
        ) {
            store.showExportMenu = true
        }
        .popover(isPresented: $store.showExportMenu, arrowEdge: .bottom) {
            if store.isCompareMode {
                CompareExportPopover()
                    .environmentObject(store)
            } else {
                ExportPopoverContent()
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - Compare export popover (two-step)

struct CompareExportPopover: View {
    @EnvironmentObject var store: MediaStore
    /// The file chosen in the first step. Kept after stepping back, so the
    /// formats step can slide out still showing it.
    @State private var source: CopySource = .fileA
    @State private var showsFormats = false
    @State private var isGoingBack = false
    
    var body: some View {
        PopoverSteps(showsSecond: showsFormats, isGoingBack: isGoingBack) {
            fileStep
        } second: {
            formatStep
        }
        .frame(width: 260)
    }
    
    private func step(to formats: Bool) {
        isGoingBack = !formats
        smiWithAnimation(SMI.Motion.popoverStep) { showsFormats = formats }
    }
    
    private var formatStep: some View {
        let source = self.source
        return VStack(alignment: .leading, spacing: 4) {
            PopoverBackButton(title: source.label) { step(to: false) }
            
            PopoverTitle(text: "Choose Format", topPadding: 0)
            
            Divider()
            
            ExportFormatList { format in
                store.showExportMenu = false
                store.afterPopoverCloses { store.exportCompare(source: source, format: format) }
            }
            
            Divider()
            
            PopoverMenuItem(title: "Export All Formats…", icon: "square.and.arrow.up.on.square") {
                store.showExportMenu = false
                store.afterPopoverCloses { store.exportCompareAll(source: source) }
            }
            
            PopoverMenuItem(title: "Export All as ZIP…", icon: "archivebox") {
                store.showExportMenu = false
                store.afterPopoverCloses { store.exportCompareAllAsZip(source: source) }
            }
            .padding(.bottom, 4)
        }
    }
    
    private var fileStep: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverTitle(text: "Export — Choose File")
            
            Divider()
            
            ForEach([CopySource.fileA, .fileB, .both], id: \.self) { choice in
                PopoverChoiceRow(title: choice.label, icon: choice.icon) {
                    source = choice
                    step(to: true)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Single-file export popover

struct ExportPopoverContent: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopoverTitle(text: "Export")
            
            Divider()
            
            ExportFormatList { format in
                store.showExportMenu = false
                store.afterPopoverCloses { store.export(format: format) }
            }
            
            Divider()
            
            PopoverMenuItem(title: "Export All Formats…", icon: "square.and.arrow.up.on.square") {
                store.showExportMenu = false
                store.afterPopoverCloses { store.exportAll() }
            }
            
            PopoverMenuItem(title: "Export All as ZIP…", icon: "archivebox") {
                store.showExportMenu = false
                store.afterPopoverCloses { store.exportAllAsZip() }
            }
            .padding(.bottom, 4)
        }
        .frame(minWidth: 240)
    }
    
}

// MARK: - Format list

/// The formats in two groups — Human-readable (Text, Raw Text, HTML, PDF,
/// Markdown) and Machine-readable (CSV, JSON, XML) — shared by the single-file
/// and Compare Mode popovers so the two never list formats differently.
struct ExportFormatList: View {
    /// "Export" or "Share" — the list is shared by both menus.
    var verb: String = "Export"
    let action: (ExportFormat) -> Void
    
    var body: some View {
        ForEach(ExportFormat.Category.allCases, id: \.self) { category in
            Text(category.title.uppercased())
                .font(SMI.Typo.caption)
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, category == .humanReadable ? 6 : 10)
                .padding(.bottom, 2)
            
            ForEach(category.formats) { format in
                Button {
                    action(format)
                } label: {
                    Label("\(verb) as \(format.label)…", systemImage: format.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .popoverRowHighlight()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - CopySource enum

enum CopySource: String, CaseIterable, Hashable {
    case fileA, fileB, both
    
    var label: String {
        switch self {
        case .fileA: return "File A"
        case .fileB: return "File B"
        case .both:  return "Both Files"
        }
    }
    
    var icon: String {
        switch self {
        case .fileA: return "doc"
        case .fileB: return "doc.fill"
        case .both:  return "doc.on.doc"
        }
    }
}
