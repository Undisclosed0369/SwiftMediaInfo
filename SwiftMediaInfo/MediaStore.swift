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

@MainActor
final class MediaStore: ObservableObject {
    

    // Explicit init so Swift doesn't complain about @AppStorage inside actor
    init() {}

    @Published var files:          [MediaFile] = []
    @Published var selectedID:     UUID?       = nil
    @Published var viewMode:       ViewMode    = .easy
    @Published var showExportMenu: Bool        = false
    @AppStorage("fontSize") var fontSize: Double = 12

    var selectedFile: MediaFile? {
        guard let id = selectedID else { return files.first }
        return files.first(where: { $0.id == id }) ?? files.first
    }

    // MARK: - Zoom

    func zoomIn()  { fontSize = min(fontSize + 1, 22) }
    func zoomOut() { fontSize = max(fontSize - 1,  8) }

    // MARK: - Open

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.movie, .audio, .data, .item]
        guard panel.runModal() == .OK else { return }
        addURLs(panel.urls)
    }

    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let urls = enumerator
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        addURLs(urls)
    }

    func addURLs(_ urls: [URL]) {
        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }
            let placeholder = MediaFile(url: url)
            files.append(placeholder)
            let id = placeholder.id
            if selectedID == nil { selectedID = id }
            Task {
                let analysed = await MediaEngine.analyse(url)
                if let idx = self.files.firstIndex(where: { $0.id == id }) {
                    self.files[idx] = analysed
                }
            }
        }
    }

    func close(_ file: MediaFile) {
        files.removeAll { $0.id == file.id }
        if selectedID == file.id { selectedID = files.first?.id }
    }

    func closeAll() {
        files.removeAll()
        selectedID = nil
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
        let base  = selectedFile?.url.deletingPathExtension().lastPathComponent ?? "export"
        panel.nameFieldStringValue = base + "." + format.fileExtension
        panel.allowedContentTypes  = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAll() {
        guard let file = selectedFile else { return }
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
        case .text: return selectedFile?.rawText
        case .html: return selectedFile?.rawHTML
        case .xml:  return selectedFile?.rawXML
        case .json: return selectedFile?.rawJSON
        case .csv:  return buildCSV()
        }
    }

    private func currentOutputString() -> String? {
        switch viewMode {
        case .text: return selectedFile?.rawText
        case .html: return selectedFile?.rawHTML
        case .xml:  return selectedFile?.rawXML
        case .json: return selectedFile?.rawJSON
        default:    return selectedFile?.rawText
        }
    }

    private func buildCSV() -> String {
        guard let file = selectedFile else { return "" }
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

