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
        HStack(spacing: 14) {
            
            // ── LEFT: Open File ───────────────────────────────────────────
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
            
            toolbarDivider
            
            // ── CENTRE: Custom view mode picker ──────────────────────────
            ViewModePicker()
            
            Spacer()
            
            // ── RIGHT: Appearance → Zoom → Copy → Export ──────────────────
            
            // Appearance toggle
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
            
            // Zoom controls
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
            
            Button(action: { store.copyToClipboard() }) {
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
            .help("Copy to clipboard (⌘⇧C)")
            
            ExportMenuButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
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
    
    private var toolbarDivider: some View {
        Divider()
            .frame(height: 30)
            .padding(.horizontal, 2)
    }
}

// MARK: - Custom view mode picker

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
                    .background(
                        store.viewMode == mode
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                    )
                    .foregroundColor(
                        store.viewMode == mode
                        ? .accentColor
                        : .primary
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("\(mode.label) view (⌘\(mode.shortcut.displayString))")
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

// MARK: - Export menu

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
            ExportPopoverContent()
                .environmentObject(store)
        }
    }
}

// MARK: - Export popover content

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
            
            Group {
                exportButton("Export as Text…", format: .text, icon: "doc.text")
                exportButton("Export as HTML…", format: .html, icon: "globe")
                exportButton("Export as XML…",  format: .xml,  icon: "chevron.left.forwardslash.chevron.right")
                exportButton("Export as JSON…", format: .json, icon: "curlybraces")
                exportButton("Export as CSV…",  format: .csv,  icon: "tablecells")
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
            .padding(.bottom, 4)
        }
        .frame(minWidth: 220)
    }
    
    private func exportButton(_ title: String, format: ExportFormat, icon: String) -> some View {
        Button {
            store.showExportMenu = false
            store.export(format: format)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
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
        default:  return ""
        }
    }
}
