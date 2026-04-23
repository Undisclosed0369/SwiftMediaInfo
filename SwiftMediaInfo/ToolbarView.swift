//
//  ToolbarView.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  ToolbarView.swift
//  MediaInfoMac
//

import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject var store: MediaStore

    var body: some View {
        HStack(spacing: 10) {

            // ── LEFT: Open File / Open Folder ────────────────────────────
            Button(action: { store.openFilePicker() }) {
                VStack(spacing: 3) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                    Text("Open File")
                        .font(.system(size: 10.5))
                }
                .frame(minWidth: 56)
            }
            .buttonStyle(.plain)
            .help("Open file (⌘O)")

            Button(action: { store.openFolderPicker() }) {
                VStack(spacing: 3) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                    Text("Open Folder")
                        .font(.system(size: 10.5))
                }
                .frame(minWidth: 64)
            }
            .buttonStyle(.plain)
            .help("Open folder (⌘⇧O)")

            toolbarDivider

            // ── CENTRE: View mode picker ──────────────────────────────────
            Picker("View", selection: $store.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon)
                        .tag(mode)
                        .help("\(mode.label) view (⌘\(mode.shortcut.displayString))")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 500)

            Spacer()

            // ── RIGHT: Zoom → Copy → Export ───────────────────────────────

            // Zoom controls
            HStack(spacing: 6) {
                Button(action: { store.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Zoom out (⌘-)")

                Text("\(Int((store.fontSize / 12.0) * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 38)

                Button(action: { store.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Zoom in (⌘+)")
            }

            toolbarDivider

            // Copy
            Button(action: { store.copyToClipboard() }) {
                VStack(spacing: 3) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 17, weight: .medium))
                    Text("Copy")
                        .font(.system(size: 10.5))
                }
                .frame(minWidth: 44)
            }
            .buttonStyle(.plain)
            .disabled(store.selectedFile == nil)
            .help("Copy to clipboard (⌘⇧C)")

            // Export menu — also triggered programmatically by CMD+E
            ExportMenuButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 24)
            .padding(.horizontal, 2)
    }
}

// MARK: - Export menu as its own view so onChange compiles cleanly

struct ExportMenuButton: View {
    @EnvironmentObject var store: MediaStore

    var body: some View {
        Menu {
            // One button per format, iterating by index to avoid ForEach+Identifiable issues
            Button("Export as Text…")     { store.export(format: .text) }
            Button("Export as HTML…")     { store.export(format: .html) }
            Button("Export as XML…")      { store.export(format: .xml)  }
            Button("Export as JSON…")     { store.export(format: .json) }
            Button("Export as CSV…")      { store.export(format: .csv)  }
            Divider()
            Button("Export All Formats…") { store.exportAll() }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                Text("Export")
                    .font(.system(size: 10.5))
            }
            .frame(minWidth: 50)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.selectedFile == nil)
        .help("Export report (⌘E)")
        .onChange(of: store.showExportMenu) { oldValue, newValue in
            // Reset the flag; the Menu opens via its own interaction
            if newValue { store.showExportMenu = false }
        }
    }
}

// MARK: - KeyEquivalent display helper

extension KeyEquivalent {
    /// Returns a plain String so it can be interpolated in Text/help strings.
    var displayString: String {
        switch self {
        case "1": return "1"
        case "2": return "2"
        case "3": return "3"
        case "4": return "4"
        case "5": return "5"
        case "6": return "6"
        case "7": return "7"
        default:  return ""
        }
    }
}
