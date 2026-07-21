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
                HStack(spacing: 4) {
                    // Unified Open button (picks files OR folders)
                    GlassButton(
                        icon: "doc.badge.plus",
                        label: "Open",
                        accentColor: .brandBlue
                    ) { store.openFilePicker() }
                        .help("Open file or folder (⌘O)")
                    
                    // Animated background toggle
                    GlassButton(
                        icon: store.showAnimatedBackground ? "wand.and.stars" : "wand.and.stars.inverse",
                        label: store.showAnimatedBackground ? "BG On" : "BG Off",
                        accentColor: .brandPink,
                        isActive: store.showAnimatedBackground
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            store.showAnimatedBackground.toggle()
                        }
                    }
                    .help("Toggle animated background")
                    
                    // Open in Default App (no folder button next to it)
                    GlassButton(
                        icon: "play.rectangle",
                        label: "Open in App",
                        accentColor: .brandGreen,
                        isDisabled: store.currentFile == nil
                    ) {
                        if store.isCompareMode {
                            // fall through to popover below
                        } else if let url = store.currentFile?.url {
                            OpenInDefaultAppButton.openInDefaultApp(url)
                        }
                    }
                    .overlay(
                        // Preserve compare-mode popover behaviour
                        store.isCompareMode ? AnyView(OpenInDefaultAppButton()) : AnyView(EmptyView())
                    )
                    .help("Open in default app (⌘↩)")
                }
                .liquidGlass(cornerRadius: 14, tintColor: .brandBlue, borderOpacity: 0.2)
                
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
                    GlassButton(
                        icon: "minus.magnifyingglass",
                        label: "",
                        accentColor: .brandBlue
                    ) {
                        store.zoomOut()
                        
                    }
                    .help("Zoom out (⌘-)")
                    
                    // Zoom % label
                    Text("\(Int((store.fontSize / 12.0) * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
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
                    
                    // Zoom in
                    GlassButton(
                        icon: "plus.magnifyingglass",
                        label: "",
                        accentColor: .brandBlue
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

// MARK: - Reusable glass button

struct GlassButton: View {
    let icon: String
    let label: String
    var accentColor: Color = .brandViolet
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isActive ? accentColor : (isDisabled ? Color.secondary.opacity(0.4) : Color.primary))
            .frame(minWidth: label.isEmpty ? 36 : 62, minHeight: 47)
            .padding(.horizontal, label.isEmpty ? 8 : 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Open in Default App Button

struct OpenInDefaultAppButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    var body: some View {
        // In compare mode this overlays a transparent tap target
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { showPopover = true }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                OpenInAppPopover(isPresented: $showPopover)
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
    @Binding var isPresented: Bool
    
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
                    isPresented = false
                    OpenInDefaultAppButton.openInDefaultApp(fileA.url)
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
                    isPresented = false
                    OpenInDefaultAppButton.openInDefaultApp(fileB.url)
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

struct CopyButton: View {
    @EnvironmentObject var store: MediaStore
    @State private var showPopover = false
    
    var body: some View {
        Button(action: {
            if store.isCompareMode {
                showPopover = true
            } else {
                store.copyToClipboard()
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 21))
                Text("Copy")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(minWidth: 62, minHeight: 47)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .disabled(store.currentFile == nil)
        .help("Copy to clipboard")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            CopyPopover(isPresented: $showPopover)
                .environmentObject(store)
        }
    }
}

// MARK: - Copy Popover (compare mode)

struct CopyPopover: View {
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
            
            ForEach([CopySource.fileA, .fileB, .both], id: \.self) { source in
                Button {
                    isPresented = false
                    store.copyToClipboard(source: source)
                } label: {
                    Label(source.label, systemImage: source.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
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
        Button(action: { store.showExportMenu = true }) {
            VStack(spacing: 3) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 21))
                Text("Export")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(minWidth: 62, minHeight: 47)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
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
