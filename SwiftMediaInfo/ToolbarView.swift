//
//  ToolbarView.swift
//  SwiftMediaInfo
//

import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        HStack(spacing: 14) {
            
            // ── LEFT: Open File ────
            Button(action: { store.openFilePicker() }) {
                VStack(spacing: 4) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 25.5, weight: .medium))
                    Text("Open File")
                        .font(.system(size: 11.5))
                }
                .frame(minWidth: 68)
            }
            .buttonStyle(.plain)
            .help("Open file (⌘O)")
            
            // ── FIX 3: Open Folder button ────
            Button(action: { store.openFolderPicker() }) {
                VStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 25.5, weight: .medium))
                    Text("Open Folder")
                        .font(.system(size: 11.5))
                }
                .frame(minWidth: 80)
            }
            .buttonStyle(.plain)
            .help("Open folder (⇧⌘O)")
            
            // ── FIX 4 & 5: Open in Default App button ────
            // In normal mode: opens current file directly.
            // In compare mode: shows a popover asking which file (File A or File B).
            OpenInDefaultAppButton()
            
            // ── Compare button ────
            Button(action: { handleCompareButton() }) {
                VStack(spacing: 4) {
                    Image(systemName: store.isCompareMode
                          ? "rectangle.split.2x1.fill"
                          : "rectangle.split.2x1")
                    .font(.system(size: 25.5, weight: .medium))
                    .foregroundColor(store.isCompareMode ? .accentColor : .primary)
                    Text(store.isCompareMode ? "Exit Compare" : "Compare")
                        .font(.system(size: 11.5))
                        .foregroundColor(store.isCompareMode ? .accentColor : .primary)
                }
                .frame(minWidth: 78)
            }
            .buttonStyle(.plain)
            .help(store.isCompareMode ? "Exit compare mode" : "Compare two files side by side")
            
            toolbarDivider
            
            // ── CENTRE: View mode picker ────
            ViewModePicker()
            
            Spacer()
            
            // ── RIGHT: Appearance → Zoom → Copy → Export ────
            
            Button(action: { store.cycleAppearance() }) {
                VStack(spacing: 4) {
                    Image(systemName: appearanceIcon)
                        .font(.system(size: 25.5, weight: .medium))
                    Text(appearanceLabel)
                        .font(.system(size: 11.5))
                }
                .frame(minWidth: 58)
            }
            .buttonStyle(.plain)
            .help("Toggle appearance (currently \(appearanceLabel))")
            
            toolbarDivider
            
            HStack(spacing: 8) {
                Button(action: { store.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 25.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Zoom out (⌘-)")
                
                Text("\(Int((store.fontSize / 12.0) * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 42)
                
                Button(action: { store.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 25.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Zoom in (⌘+)")
            }
            
            toolbarDivider
            
            CopyButton()
            ExportMenuButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Compare button action
    
    private func handleCompareButton() {
        if store.isCompareMode {
            store.exitCompareMode()
        } else {
            if store.currentFile == nil { store.openFilePicker() }
            store.openCompareFilePicker()
        }
    }
    
    // MARK: - Helpers
    
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
    
    private var toolbarDivider: some View {
        Divider().frame(height: 30).padding(.horizontal, 2)
    }
}

// MARK: - Open in Default App Button
//
// FIX 4: In normal mode, clicking this immediately opens the current file
//         in whatever app macOS considers the default for that file type
//         (e.g. VLC for .mkv, Preview for images, Music for .mp3).
//
// FIX 5: In compare mode, clicking shows a small popover asking the user
//         to pick File A or File B — then opens the chosen one.
//
// INFUSE FIX: We use /usr/bin/open (the shell command) instead of
// NSWorkspace.shared.open(). Both do the same thing conceptually,
// but NSWorkspace can fail with sandboxed Mac App Store apps like Infuse
// because macOS blocks the inter-app file handoff between two sandboxed apps.
// /usr/bin/open goes through the system's Launch Services daemon directly,
// exactly like double-clicking a file in Finder — no sandbox restriction.

struct OpenInDefaultAppButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    var body: some View {
        Button(action: {
            if store.isCompareMode {
                // Show picker popover (Fix 5)
                showPopover = true
            } else {
                // Open directly (Fix 4 + Infuse fix)
                if let url = store.currentFile?.url {
                    OpenInDefaultAppButton.openInDefaultApp(url)
                }
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 25.5, weight: .medium))
                Text("Open in App")
                    .font(.system(size: 11.5))
            }
            .frame(minWidth: 74)
        }
        .buttonStyle(.plain)
        .disabled(store.currentFile == nil)
        .help("Open file in its default application")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            OpenInAppPopover(isPresented: $showPopover)
                .environmentObject(store)
        }
    }
    
    /// Opens a file using /usr/bin/open — identical to double-clicking in Finder.
    /// This works with Infuse, VLC, and ALL other apps including sandboxed ones,
    /// because it routes through Launch Services rather than NSWorkspace's
    /// inter-app communication channel.
    static func openInDefaultApp(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Pass the raw file path. We use path(percentEncoded:false) on macOS 13+
        // so special characters (ü, é, etc.) in filenames are handled correctly.
        if #available(macOS 13.0, *) {
            process.arguments = [url.path(percentEncoded: false)]
        } else {
            process.arguments = [url.path]
        }
        process.standardOutput = Pipe()  // discard output
        process.standardError  = Pipe()  // discard errors
        try? process.run()
        // No waitUntilExit — we don't want to block the UI thread
    }
}

// MARK: - Open in Default App — Compare Popover
//
// Shown only in compare mode. Lets the user pick which file to open.

struct OpenInAppPopover: View {
    @EnvironmentObject var store: MediaStore
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open in Default App")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            // File A row — only shown if File A is loaded
            if let fileA = store.currentFile {
                fileRow(
                    label:    "File A",
                    subtitle: fileA.fileName,
                    color:    .blue,
                    icon:     "doc"
                ) {
                    isPresented = false
                    OpenInDefaultAppButton.openInDefaultApp(fileA.url)
                }
            }
            
            // File B row — only shown if File B is loaded
            if let fileB = store.compareFile {
                fileRow(
                    label:    "File B",
                    subtitle: fileB.fileName,
                    color:    .purple,
                    icon:     "doc.fill"
                ) {
                    isPresented = false
                    OpenInDefaultAppButton.openInDefaultApp(fileB.url)
                }
            }
            
            // Safety: if somehow neither file is loaded, show a message
            if store.currentFile == nil && store.compareFile == nil {
                Text("No files loaded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 240)
    }
    
    private func fileRow(
        label: String,
        subtitle: String,
        color: Color,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Coloured badge matching the compare pane colours
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color)
                    .cornerRadius(5)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Copy button

struct CopyButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    var body: some View {
        Button(action: {
            if store.isCompareMode { showPopover = true }
            else                   { store.copyToClipboard() }
        }) {
            VStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 25.5, weight: .medium))
                Text("Copy")
                    .font(.system(size: 11.5))
            }
            .frame(minWidth: 52)
        }
        .buttonStyle(.plain)
        .disabled(store.currentFile == nil)
        .help(store.isCompareMode ? "Copy to clipboard…" : "Copy current view to clipboard")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            CopyPopoverContent(isPresented: $showPopover)
                .environmentObject(store)
        }
    }
}

// MARK: - Copy popover (compare mode)

struct CopyPopoverContent: View {
    @EnvironmentObject var store: MediaStore
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Copy to Clipboard")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            Divider()
            
            copyRow(label: "File A", icon: "doc.on.clipboard") { store.copyToClipboard(source: .fileA) }
            copyRow(label: "File B", icon: "doc.on.clipboard") { store.copyToClipboard(source: .fileB) }
            
            Divider()
            
            copyRow(label: "Both Files", icon: "doc.on.doc") { store.copyToClipboard(source: .both) }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 200)
    }
    
    private func copyRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            isPresented = false
            action()
        } label: {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View mode picker

struct ViewModePicker: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                Button(action: { store.viewMode = mode }) {
                    VStack(spacing: 3) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 15, weight: .medium))
                        Text(mode.label)
                            .font(.system(size: 11))
                    }
                    .frame(minWidth: 52)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(store.viewMode == mode
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear)
                    .foregroundColor(store.viewMode == mode ? .accentColor : .primary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("\(mode.label) view")
            }
        }
        .padding(3)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Export menu button

struct ExportMenuButton: View {
    @EnvironmentObject var store: MediaStore
    
    var body: some View {
        Button(action: { store.showExportMenu = true }) {
            VStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 25.5, weight: .medium))
                Text("Export")
                    .font(.system(size: 11.5))
            }
            .frame(minWidth: 58)
        }
        .buttonStyle(.plain)
        .disabled(store.currentFile == nil)
        .help("Export report (⌘E)")
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
            // ── Step 2: choose format ────
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button {
                        selectedSource = nil
                    } label: {
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
            // ── Step 1: choose which file ────
            VStack(alignment: .leading, spacing: 4) {
                Text("Export — Choose File")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                
                Divider()
                
                ForEach([CopySource.fileA, .fileB, .both], id: \.self) { source in
                    Button {
                        selectedSource = source
                    } label: {
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

// MARK: - Original single-file export popover

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

// MARK: - KeyEquivalent display helper

extension KeyEquivalent {
    var displayString: String {
        switch self {
        case "1": return "1"
        case "2": return "2"
        case "3": return "3"
        case "4": return "4"
        case "5": return "5"
        case "6": return "6"
        default:  return ""
        }
    }
}
