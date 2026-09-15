//
//  ToolbarView.swift
//  SwiftMediaInfo
//

import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                
                // ── LEFT: File actions ────────────────────────────────────
                //
                // Three buttons, in the order you use them: choose a file,
                // act on the file, hand the file to another app.
                //
                // The animated-background toggle used to sit in the middle of
                // this group. It was removed in Phase 8b — it is a display
                // preference, not a file action, and it was the one control
                // here that had nothing to do with the open document. The
                // behaviour is untouched: ⌘B still toggles it, and Settings ›
                // Appearance still has the switch.
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
                    // PHASE 11 — this one hands the file to another
                    // application, which can take a second or two to appear.
                    // Nothing happened on screen in the meantime, so the button
                    // read as broken and people pressed it twice. It now says
                    // "Opening…" for a moment, which is the whole fix.
                    ToolbarActionButton(
                        icon: "play.rectangle",
                        label: "Open in App",
                        accentColor: .brandGreen,
                        isActive: store.showOpenInAppPicker,
                        isSuccessful: store.didLaunchInApp,
                        successIcon: "arrow.up.forward.app.fill",
                        successLabel: "Opening…",
                        isDisabled: store.currentFile == nil && store.compareFile == nil,
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
                    .help(store.isCompareMode ? "Exit compare mode" : "Compare two files side by side")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.isCompareMode)
                
                // ── CENTRE: Tab picker ────────────────────────────────────
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
                        .help("Toggle appearance")
                    
                    // Zoom out
                    //
                    // PHASE 11 — an empty `label` is right for the eye (the
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
        if store.isCompareMode {
            store.exitCompareMode()
        } else {
            if store.currentFile == nil { store.openFilePicker() }
            store.openCompareFilePicker()
        }
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
        // PHASE 8c — the presentation flag lives on the store rather than in
        // this view's @State. A keyboard shortcut is handled somewhere else
        // entirely and has no way to reach a private @State, which is why ⌘↩
        // used to skip the picker and always open File A. State that a
        // shortcut has to set cannot be local to the view that shows it.
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

// MARK: - Open in Default App — Compare Popover

struct OpenInAppPopover: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open in Default App")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            if let fileA = store.currentFile {
                Button {
                    store.showOpenInAppPicker = false
                    store.openInDefaultApp(fileA.url)
                } label: {
                    Label("File A — \(fileA.fileName)", systemImage: "doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            
            if let fileB = store.compareFile {
                Button {
                    store.showOpenInAppPicker = false
                    store.openInDefaultApp(fileB.url)
                } label: {
                    Label("File B — \(fileB.fileName)", systemImage: "doc.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 260)
    }
}

// MARK: - Copy Button
//
// PHASE 11 — this button now answers back.
//
// THE PROBLEM IT HAD
//
// Pressing Copy looked identical to not pressing Copy. No hover wash, no press
// compression, no confirmation. For most buttons that would be sloppy; for this
// one it was a real usability hole, because the clipboard is invisible. The
// only way to find out whether the copy had worked was to go and paste
// somewhere, and if it hadn't worked, you found out in the wrong document.
//
// WHAT IT DOES NOW
//
// It borrows the state vocabulary from ToolbarActionButton: hover, press, and
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
// `copyToClipboard` returns a Bool as of this phase. With no file open, or with
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
            isDisabled: store.currentFile == nil,
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
            Text("Copy to Clipboard")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            
            Divider()
            
            ForEach([CopySource.fileA, .fileB, .both], id: \.self) { source in
                Button {
                    isPresented = false
                    if store.copyToClipboard(source: source) {
                        onCopied()
                    }
                } label: {
                    Label(source.label, systemImage: source.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
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
        // PHASE 11 — same component as Copy and Share, so all three now hover
        // and compress the way the buttons on the left of the toolbar always
        // have. No success state: Export opens a save panel, and the panel is
        // its own confirmation.
        ToolbarActionButton(
            icon: "square.and.arrow.up",
            label: "Export",
            accentColor: .brandGreen,
            isActive: store.showExportMenu,
            isDisabled: store.currentFile == nil,
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
    @State private var selectedSource: CopySource? = nil
    
    var body: some View {
        if let source = selectedSource {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button { selectedSource = nil } label: {
                        Image(systemName: "chevron.left")
                        Text(source.label)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.leading, 12)
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
                
                Text("Choose Format")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                
                Divider()
                
                ForEach(ExportFormat.allCases) { format in
                    Button {
                        store.showExportMenu = false
                        store.exportCompare(source: source, format: format)
                    } label: {
                        Label("Export as \(format.label)…", systemImage: format.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                
                Button {
                    store.showExportMenu = false
                    store.exportCompareAll(source: source)
                } label: {
                    Label("Export All Formats…", systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                
                Button {
                    store.showExportMenu = false
                    store.exportCompareAllAsZip(source: source)
                } label: {
                    Label("Export All as ZIP…", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }
            .frame(minWidth: 260)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export — Choose File")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                
                Divider()
                
                ForEach([CopySource.fileA, .fileB, .both], id: \.self) { source in
                    Button { selectedSource = source } label: {
                        HStack {
                            Label(source.label, systemImage: source.icon)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
            .frame(minWidth: 230)
        }
    }
}

// MARK: - Single-file export popover

struct ExportPopoverContent: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            ForEach(ExportFormat.allCases) { format in
                exportButton(format)
            }
            
            Divider()
            
            Button {
                store.showExportMenu = false
                store.exportAll()
            } label: {
                Label("Export All Formats…", systemImage: "square.and.arrow.up.on.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            
            Button {
                store.showExportMenu = false
                store.exportAllAsZip()
            } label: {
                Label("Export All as ZIP…", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
        .frame(minWidth: 240)
    }
    
    private func exportButton(_ format: ExportFormat) -> some View {
        Button {
            store.showExportMenu = false
            store.export(format: format)
        } label: {
            Label("Export as \(format.label)…", systemImage: format.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
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
