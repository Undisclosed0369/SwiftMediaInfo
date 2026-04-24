//
//  MediaStore.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  MediaStore.swift
//  MediaInfoMac
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

enum AppearanceMode: String {
    case system, light, dark
}

@MainActor
final class MediaStore: ObservableObject {
    
    init() {
        // Apply saved appearance on launch
        applyAppearance(AppearanceMode(rawValue: savedAppearance) ?? .system)
    }
    
    @Published var currentFile:    MediaFile?  = nil
    @Published var viewMode:       ViewMode    = .easy
    @Published var showExportMenu: Bool        = false
    @AppStorage("fontSize")       var fontSize:        Double = 12
    @AppStorage("appearanceMode") var savedAppearance: String = AppearanceMode.system.rawValue
    
    // Published so the toolbar button can reflect current state
    @Published var appearanceMode: AppearanceMode = .system
    
    // MARK: - Appearance
    
    func cycleAppearance() {
        let next: AppearanceMode
        switch appearanceMode {
        case .system: next = .light
        case .light:  next = .dark
        case .dark:   next = .system
        }
        appearanceMode  = next
        savedAppearance = next.rawValue
        applyAppearance(next)
    }
    
    private func applyAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    
    // MARK: - Zoom
    
    func zoomIn()  { fontSize = min(fontSize + 1, 48) }
    func zoomOut() { fontSize = max(fontSize - 1,  8) }
    
    // MARK: - Open
    
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.movie, .audio, .data, .item]
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        openURL(url)
    }
    
    func openURL(_ url: URL) {
        let normalised  = url.standardized
        let placeholder = MediaFile(url: normalised)
        currentFile = placeholder
        Task {
            let analysed = await MediaEngine.analyse(normalised)
            if self.currentFile?.url == normalised {
                self.currentFile = analysed
            }
        }
    }
    
    func closeFile() {
        currentFile = nil
    }
    
    // MARK: - Export / Copy
    
    func copyToClipboard() {
        guard let content = currentOutputString() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    func export(format: ExportFormat) {
        guard let content = outputString(for: format) else { return }
        let panel = NSSavePanel()
        let base  = currentFile?.url.deletingPathExtension().lastPathComponent ?? "export"
        panel.nameFieldStringValue = base + "." + format.fileExtension
        panel.allowedContentTypes  = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    func exportAll() {
        guard let file = currentFile else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export All Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let base = file.url.deletingPathExtension().lastPathComponent
        for format in ExportFormat.allCases {
            guard let content = outputString(for: format) else { continue }
            let dest = dir.appendingPathComponent(base + "." + format.fileExtension)
            try? content.write(to: dest, atomically: true, encoding: .utf8)
        }
    }
    
    func outputString(for format: ExportFormat) -> String? {
        switch format {
        case .text: return currentFile?.rawText
        case .html: return currentFile?.rawHTML
        case .xml:  return currentFile?.rawXML
        case .json: return currentFile?.rawJSON
        case .csv:  return buildCSV()
        }
    }
    
    private func currentOutputString() -> String? {
        switch viewMode {
        case .text: return currentFile?.rawText
        case .html: return currentFile?.rawHTML
        case .xml:  return currentFile?.rawXML
        case .json: return currentFile?.rawJSON
        default:    return currentFile?.rawText
        }
    }
    
    private func buildCSV() -> String {
        guard let file = currentFile else { return "" }
        var lines = ["Track,Field,Value"]
        for track in file.tracks {
            for field in track.fields {
                let escaped = field.value.replacingOccurrences(of: "\"", with: "\"\"")
                lines.append("\"\(track.displayTitle)\",\"\(field.key)\",\"\(escaped)\"")
            }
        }
        return lines.joined(separator: "\n")
    }
}
