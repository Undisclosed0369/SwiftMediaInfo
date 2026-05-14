//
//  MediaStore.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

//
//  MediaStore.swift
//  SwiftMediaInfo
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
        applyAppearance(AppearanceMode(rawValue: savedAppearance) ?? .system)
    }
    
    @Published var currentFile:    MediaFile?      = nil
    @Published var compareFile:    MediaFile?      = nil
    @Published var isCompareMode:  Bool            = false
    @Published var viewMode:       ViewMode        = .easy
    @Published var showExportMenu: Bool            = false
    
    @AppStorage("fontSize")        var fontSize:        Double = 12
    @AppStorage("appearanceMode")  var savedAppearance: String = AppearanceMode.system.rawValue
    
    @Published var appearanceMode: AppearanceMode = .system
    
    // MARK: - Cancellation
    //
    // We keep a reference to every background loading Task so we can cancel
    // it the moment the user opens a different file.  Without this, opening
    // file B while file A is still loading would leave A's tasks running in
    // the background, wasting CPU/IO and potentially overwriting file B's data.
    
    private var currentLoadTasks:  [Task<Void, Never>] = []
    private var compareLoadTasks:  [Task<Void, Never>] = []
    
    private func cancelCurrentTasks() {
        currentLoadTasks.forEach { $0.cancel() }
        currentLoadTasks = []
    }
    
    private func cancelCompareTasks() {
        compareLoadTasks.forEach { $0.cancel() }
        compareLoadTasks = []
    }
    
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
    
    // MARK: - Open (primary file)
    
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
        let normalised = url.standardized
        
        // Cancel any in-flight tasks for the previous file immediately
        cancelCurrentTasks()
        
        var placeholder = MediaFile(url: normalised)
        placeholder.isLoading = true
        currentFile = placeholder
        
        let task = Task { await loadInitialFormats(for: normalised, isCompare: false) }
        currentLoadTasks.append(task)
    }
    
    func closeFile() {
        cancelCurrentTasks()
        cancelCompareTasks()
        currentFile   = nil
        compareFile   = nil
        isCompareMode = false
    }
    
    // MARK: - Open (compare file)
    
    func openCompareFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.movie, .audio, .data, .item]
        panel.message                 = "Choose a second file to compare"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        openCompareURL(url)
    }
    
    func openCompareURL(_ url: URL) {
        let normalised = url.standardized
        
        cancelCompareTasks()
        
        var placeholder = MediaFile(url: normalised)
        placeholder.isLoading = true
        compareFile   = placeholder
        isCompareMode = true
        
        let task = Task { await loadInitialFormats(for: normalised, isCompare: true) }
        compareLoadTasks.append(task)
    }
    
    func exitCompareMode() {
        cancelCompareTasks()
        compareFile   = nil
        isCompareMode = false
    }
    
    // MARK: - Initial loading  (Text → Raw Text → JSON, then done)
    //
    // Loading order as requested:
    //   1. Text      — fast, plain summary, user sees something almost immediately
    //   2. Raw Text  — nearly the same speed
    //   3. JSON      — powers Easy view cards + status bar; marks end of initial load
    //
    // HTML and XML are intentionally skipped here — they are loaded on demand
    // when the user clicks those tabs.
    
    private func loadInitialFormats(for url: URL, isCompare: Bool) async {
        // 1️⃣ Text
        guard !Task.isCancelled else { return }
        let text = await MediaEngine.fetchText(url)
        guard !Task.isCancelled else { return }
        update(url: url, isCompare: isCompare) { $0.rawText = text; $0.isLoadingText = false }
        
        // 2️⃣ Raw Text
        guard !Task.isCancelled else { return }
        let rawFull = await MediaEngine.fetchRawText(url)
        guard !Task.isCancelled else { return }
        update(url: url, isCompare: isCompare) { $0.rawTextFull = rawFull; $0.isLoadingRawText = false }
        
        // 3️⃣ JSON (also drives Easy view)
        guard !Task.isCancelled else { return }
        let json   = await MediaEngine.fetchJSON(url)
        let tracks = MediaEngine.parseTracks(from: json)
        guard !Task.isCancelled else { return }
        update(url: url, isCompare: isCompare) {
            $0.rawJSON       = json
            $0.tracks        = tracks
            $0.isLoadingJSON = false
            $0.isLoading     = false   // ← spinner disappears here
        }
        
        // HTML and XML are left as nil; loaded on demand via loadFormatIfNeeded().
    }
    
    // MARK: - On-demand loading
    //
    // Called when the user clicks a tab whose content hasn't loaded yet.
    
    func loadFormatIfNeeded(_ mode: ViewMode, isCompare: Bool = false) {
        let fileRef: MediaFile?
        if isCompare { fileRef = compareFile } else { fileRef = currentFile }
        guard let file = fileRef, !file.isLoading else { return }
        let url = file.url
        
        switch mode {
            
        case .text:
            // Loaded in initial pass — nothing to do
            break
            
        case .rawText:
            // Loaded in initial pass — nothing to do
            break
            
        case .easy, .json:
            // Loaded in initial pass — nothing to do
            break
            
        case .html:
            let alreadyHave    = isCompare ? (compareFile?.rawHTML != nil) : (currentFile?.rawHTML != nil)
            let alreadyFetching = isCompare ? (compareFile?.isLoadingHTML == true) : (currentFile?.isLoadingHTML == true)
            guard !alreadyHave && !alreadyFetching else { return }
            update(url: url, isCompare: isCompare) { $0.isLoadingHTML = true }
            let t = Task {
                guard !Task.isCancelled else { return }
                let html = await MediaEngine.fetchHTML(url)
                guard !Task.isCancelled else { return }
                update(url: url, isCompare: isCompare) { $0.rawHTML = html; $0.isLoadingHTML = false }
            }
            if isCompare { compareLoadTasks.append(t) } else { currentLoadTasks.append(t) }
            
        case .xml:
            let alreadyHave    = isCompare ? (compareFile?.rawXML != nil) : (currentFile?.rawXML != nil)
            let alreadyFetching = isCompare ? (compareFile?.isLoadingXML == true) : (currentFile?.isLoadingXML == true)
            guard !alreadyHave && !alreadyFetching else { return }
            update(url: url, isCompare: isCompare) { $0.isLoadingXML = true }
            let t = Task {
                guard !Task.isCancelled else { return }
                let xml = await MediaEngine.fetchXML(url)
                guard !Task.isCancelled else { return }
                update(url: url, isCompare: isCompare) { $0.rawXML = xml; $0.isLoadingXML = false }
            }
            if isCompare { compareLoadTasks.append(t) } else { currentLoadTasks.append(t) }
        }
    }
    
    // MARK: - Helper: mutate the right file in place
    
    private func update(url: URL, isCompare: Bool, mutation: (inout MediaFile) -> Void) {
        if isCompare {
            guard var f = compareFile, f.url == url else { return }
            mutation(&f)
            compareFile = f
        } else {
            guard var f = currentFile, f.url == url else { return }
            mutation(&f)
            currentFile = f
        }
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
        let suffix = format == .rawText ? "_raw" : ""
        panel.nameFieldStringValue = base + suffix + "." + format.fileExtension
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
            let suffix = format == .rawText ? "_raw" : ""
            let dest = dir.appendingPathComponent(base + suffix + "." + format.fileExtension)
            try? content.write(to: dest, atomically: true, encoding: .utf8)
        }
    }
    
    func outputString(for format: ExportFormat) -> String? {
        switch format {
        case .text:    return currentFile?.rawText
        case .rawText: return currentFile?.rawTextFull
        case .html:    return currentFile?.rawHTML
        case .xml:     return currentFile?.rawXML
        case .json:    return currentFile?.rawJSON
        case .csv:     return buildCSV()
        }
    }
    
    private func currentOutputString() -> String? {
        switch viewMode {
        case .text:    return currentFile?.rawText
        case .rawText: return currentFile?.rawTextFull
        case .html:    return currentFile?.rawHTML
        case .xml:     return currentFile?.rawXML
        case .json:    return currentFile?.rawJSON
        default:       return currentFile?.rawText
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
