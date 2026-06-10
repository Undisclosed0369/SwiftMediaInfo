//
//  MediaStore.swift
//  SwiftMediaInfo
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
internal import Combine

enum AppearanceMode: String {
    case system, light, dark
}

@MainActor
final class MediaStore: ObservableObject {
    
    init() {
        applyAppearance(AppearanceMode(rawValue: savedAppearance) ?? .system)
        
        // Restore the last-used tab. "lastUsedViewMode" is written every time
        // the user switches tabs (see the didSet observer on viewMode below).
        // Fall back to the Preferences default, then Easy.
        let lastUsed    = UserDefaults.standard.string(forKey: "lastUsedViewMode")
        let prefDefault = UserDefaults.standard.string(forKey: "defaultViewMode")
        let rawMode     = lastUsed ?? prefDefault ?? ViewMode.easy.rawValue
        _viewMode = Published(initialValue: ViewMode(rawValue: rawMode) ?? .easy)
    }
    
    @Published var currentFile:    MediaFile?      = nil
    @Published var compareFile:    MediaFile?      = nil
    @Published var isCompareMode:  Bool            = false
    // viewMode persists the last-used tab on every switch.
    @Published var viewMode: ViewMode = .easy {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "lastUsedViewMode")
        }
    }
    @Published var showExportMenu: Bool            = false
    
    // ── Recent files list ──────────────────────────────────────────
    @Published var recentFileURLs: [URL] = {
        let stored = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
        return stored.compactMap { URL(string: $0) }
    }()
    
    // ── Dynamic window title ───────────────────────────────────────
    var windowTitle: String {
        if let name = currentFile?.fileName {
            return "SwiftMediaInfo — \(name)"
        }
        return "SwiftMediaInfo"
    }
    
    @AppStorage("fontSize")        var fontSize:        Double = 12
    @AppStorage("appearanceMode")  var savedAppearance: String = AppearanceMode.system.rawValue
    
    @Published var appearanceMode: AppearanceMode = .system
    
    // MARK: - Cancellation
    
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
        case .system:
            next = .light
            
        case .light:
            next = .dark
            
        case .dark:
            next = .system
        }
        
        appearanceMode  = next
        savedAppearance = next.rawValue
        applyAppearance(next)
    }
    
    private func applyAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode
        
        switch mode {
        case .system:
            NSApp.appearance = nil
            
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
            
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    
    // MARK: - Zoom
    
    func zoomIn() {
        fontSize = min(fontSize + 1, 48)
    }
    
    func zoomOut() {
        fontSize = max(fontSize - 1, 8)
    }
    
    // MARK: - Open (primary file)
    
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.movie, .audio, .data, .item]
        
        guard panel.runModal() == .OK,
              let url = panel.urls.first else {
            return
        }
        
        openURL(url)
    }
    
    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowedContentTypes     = []
        
        guard panel.runModal() == .OK,
              let url = panel.urls.first else {
            return
        }
        
        openURL(url)
    }
    
    func openURL(_ url: URL) {
        let normalised = url.standardized
        
        cancelCurrentTasks()
        
        var placeholder = MediaFile(url: normalised)
        placeholder.isLoading = true
        
        currentFile = placeholder
        
        updateWindowTitle()
        addToRecentFiles(normalised)
        
        let task = Task {
            await loadInitialFormats(for: normalised, isCompare: false)
        }
        
        currentLoadTasks.append(task)
    }
    
    func closeFile() {
        cancelCurrentTasks()
        cancelCompareTasks()
        
        currentFile   = nil
        compareFile   = nil
        isCompareMode = false
        
        updateWindowTitle()
    }
    
    // MARK: - Open (compare file)
    
    func openCompareFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.canChooseFiles          = true
        panel.allowedContentTypes     = [.movie, .audio, .data, .item]
        panel.message                 = "Choose a second file to compare"
        
        guard panel.runModal() == .OK,
              let url = panel.urls.first else {
            return
        }
        
        openCompareURL(url)
    }
    
    func openCompareURL(_ url: URL) {
        let normalised = url.standardized
        
        cancelCompareTasks()
        
        var placeholder = MediaFile(url: normalised)
        placeholder.isLoading = true
        
        compareFile   = placeholder
        isCompareMode = true
        
        let task = Task {
            await loadInitialFormats(for: normalised, isCompare: true)
        }
        
        compareLoadTasks.append(task)
    }
    
    func exitCompareMode() {
        cancelCompareTasks()
        compareFile   = nil
        isCompareMode = false
    }
    
    // MARK: - Initial loading
    //
    // For files > 10 GB we pass a progress-update closure into MediaEngine so
    // that stderr "% complete" output can drive a real progress bar.
    // For normal files the plain fetchJSON is used instead.
    
    private func loadInitialFormats(for url: URL, isCompare: Bool) async {
        guard !Task.isCancelled else { return }
        
        // Check file size to decide whether to show progress
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        let isLargeFile = fileSize > 10_000_000_000  // 10 GB
        
        // Fire all three mediainfo calls simultaneously
        async let textResult    = MediaEngine.fetchText(url)
        async let rawFullResult = MediaEngine.fetchRawText(url)
        async let jsonResult: String = {
            if isLargeFile {
                return await MediaEngine.fetchJSONWithProgress(url) { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        self.update(url: url, isCompare: isCompare) {
                            $0.analysisProgress = progress
                        }
                    }
                }
            } else {
                return await MediaEngine.fetchJSON(url)
            }
        }()
        
        // Wait for all three to come back
        let (text, rawFull, json) = await (textResult, rawFullResult, jsonResult)
        
        guard !Task.isCancelled else { return }
        
        let tracks = MediaEngine.parseTracks(from: json)
        
        update(url: url, isCompare: isCompare) {
            $0.rawText           = text
            $0.isLoadingText     = false
            $0.rawTextFull       = rawFull
            $0.isLoadingRawText  = false
            $0.rawJSON           = json
            $0.tracks            = tracks
            $0.isLoadingJSON     = false
            $0.isLoading         = false
            $0.analysisProgress  = nil   // clear progress when done
        }
        
        updateWindowTitle()
    }
    
    // MARK: - On-demand loading
    
    func loadFormatIfNeeded(_ mode: ViewMode, isCompare: Bool = false) {
        let fileRef: MediaFile? = isCompare ? compareFile : currentFile
        
        guard let file = fileRef,
              !file.isLoading else {
            return
        }
        
        let url = file.url
        
        switch mode {
        case .text, .rawText, .easy, .json:
            break
            
        case .html:
            let alreadyHave = isCompare
            ? (compareFile?.rawHTML != nil)
            : (currentFile?.rawHTML != nil)
            
            let alreadyFetching = isCompare
            ? (compareFile?.isLoadingHTML == true)
            : (currentFile?.isLoadingHTML == true)
            
            guard !alreadyHave && !alreadyFetching else {
                return
            }
            
            update(url: url, isCompare: isCompare) {
                $0.isLoadingHTML = true
            }
            
            let task = Task {
                guard !Task.isCancelled else { return }
                
                let html = await MediaEngine.fetchHTML(url)
                
                guard !Task.isCancelled else { return }
                
                update(url: url, isCompare: isCompare) {
                    $0.rawHTML = html
                    $0.isLoadingHTML = false
                }
            }
            
            if isCompare {
                compareLoadTasks.append(task)
            } else {
                currentLoadTasks.append(task)
            }
            
        case .xml:
            let alreadyHave = isCompare
            ? (compareFile?.rawXML != nil)
            : (currentFile?.rawXML != nil)
            
            let alreadyFetching = isCompare
            ? (compareFile?.isLoadingXML == true)
            : (currentFile?.isLoadingXML == true)
            
            guard !alreadyHave && !alreadyFetching else {
                return
            }
            
            update(url: url, isCompare: isCompare) {
                $0.isLoadingXML = true
            }
            
            let task = Task {
                guard !Task.isCancelled else { return }
                
                let xml = await MediaEngine.fetchXML(url)
                
                guard !Task.isCancelled else { return }
                
                update(url: url, isCompare: isCompare) {
                    $0.rawXML = xml
                    $0.isLoadingXML = false
                }
            }
            
            if isCompare {
                compareLoadTasks.append(task)
            } else {
                currentLoadTasks.append(task)
            }
        }
    }
    
    // MARK: - Helper
    
    private func update(
        url: URL,
        isCompare: Bool,
        mutation: (inout MediaFile) -> Void
    ) {
        if isCompare {
            guard var file = compareFile,
                  file.url == url else {
                return
            }
            
            mutation(&file)
            compareFile = file
            
        } else {
            guard var file = currentFile,
                  file.url == url else {
                return
            }
            
            mutation(&file)
            currentFile = file
        }
    }
    
    // MARK: - Window title helper
    
    private func updateWindowTitle() {
        NSApp.windows.first?.title = windowTitle
    }
    
    // MARK: - Recent files
    
    private func addToRecentFiles(_ url: URL) {
        var recents = recentFileURLs.filter { $0 != url }
        recents.insert(url, at: 0)
        if recents.count > 10 { recents = Array(recents.prefix(10)) }
        recentFileURLs = recents
        UserDefaults.standard.set(recents.map { $0.absoluteString }, forKey: "recentFiles")
    }
    
    func clearRecentFiles() {
        recentFileURLs = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }
    
    // MARK: - Copy to clipboard
    
    func copyToClipboard() {
        guard let content = currentOutputString() else {
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    func copyToClipboard(source: CopySource) {
        let content: String
        
        switch source {
        case .fileA:
            guard let s = outputStringForFile(currentFile) else {
                return
            }
            
            content = s
            
        case .fileB:
            guard let s = outputStringForFile(compareFile) else {
                return
            }
            
            content = s
            
        case .both:
            let a = outputStringForFile(currentFile) ?? ""
            let b = outputStringForFile(compareFile) ?? ""
            
            let separator =
            "\n\n" +
            String(repeating: "─", count: 60) +
            "\n\n"
            
            content = [a, b]
                .filter { !$0.isEmpty }
                .joined(separator: separator)
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    private func outputStringForFile(_ file: MediaFile?) -> String? {
        guard let file = file else {
            return nil
        }
        
        switch viewMode {
        case .text:
            return file.rawText
            
        case .rawText:
            return file.rawTextFull
            
        case .html:
            return file.rawHTML
            
        case .xml:
            return file.rawXML
            
        case .json:
            return file.rawJSON
            
        default:
            return file.rawText
        }
    }
    
    // MARK: - Export
    
    func export(format: ExportFormat) {
        guard let file = currentFile else {
            return
        }
        
        let panel  = NSSavePanel()
        let base   = file.url.deletingPathExtension().lastPathComponent
        let suffix = format == .rawText ? "_raw" : ""
        
        panel.nameFieldStringValue = base + suffix + "." + format.fileExtension
        panel.allowedContentTypes  = [
            UTType(filenameExtension: format.fileExtension) ?? .plainText
        ]
        
        guard panel.runModal() == .OK,
              let saveURL = panel.url else {
            return
        }
        
        let snapshot = file
        let dest     = saveURL
        
        Task {
            let content: String?
            
            switch format {
            case .html:
                if let html = snapshot.rawHTML {
                    content = html
                } else {
                    content = await MediaEngine.fetchHTML(snapshot.url)
                }
                
            case .xml:
                if let xml = snapshot.rawXML {
                    content = xml
                } else {
                    content = await MediaEngine.fetchXML(snapshot.url)
                }
                
            default:
                content = outputStringRaw(file: snapshot, format: format)
            }
            
            guard let c = content,
                  !c.isEmpty else {
                return
            }
            
            try? c.write(to: dest, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Export All
    
    func exportAll() {
        guard let file = currentFile else {
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export All Here"
        
        guard panel.runModal() == .OK,
              let dir = panel.url else {
            return
        }
        
        let snapshot = file
        let base     = file.url.deletingPathExtension().lastPathComponent
        
        Task {
            await writeFormatsAsync(
                snapshot: snapshot,
                base: base,
                tag: "",
                dir: dir
            )
        }
    }
    
    // MARK: - Export All as ZIP
    
    func exportAllAsZip() {
        guard let file = currentFile else {
            return
        }
        
        let panel = NSSavePanel()
        let base  = file.url.deletingPathExtension().lastPathComponent
        
        panel.nameFieldStringValue = base + "_mediainfo.zip"
        panel.allowedContentTypes  = [
            UTType(filenameExtension: "zip") ?? .data
        ]
        
        guard panel.runModal() == .OK,
              let destZip = panel.url else {
            return
        }
        
        let snapshot = file
        
        Task {
            await zipFormats(
                snapshot: snapshot,
                base: base,
                tag: "",
                destZip: destZip
            )
        }
    }
    
    // MARK: - Export Compare
    
    func exportCompare(source: CopySource, format: ExportFormat) {
        let panel = NSSavePanel()
        
        panel.allowedContentTypes = [
            UTType(filenameExtension: format.fileExtension) ?? .plainText
        ]
        
        switch source {
        case .fileA:
            guard let content = outputStringRaw(
                file: currentFile,
                format: format
            ) else {
                return
            }
            
            let base =
            currentFile?
                .url
                .deletingPathExtension()
                .lastPathComponent ?? "FileA"
            
            panel.nameFieldStringValue =
            base +
            (format == .rawText ? "_raw" : "") +
            "." +
            format.fileExtension
            
            guard panel.runModal() == .OK,
                  let url = panel.url else {
                return
            }
            
            try? content.write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
            
        case .fileB:
            guard let content = outputStringRaw(
                file: compareFile,
                format: format
            ) else {
                return
            }
            
            let base =
            compareFile?
                .url
                .deletingPathExtension()
                .lastPathComponent ?? "FileB"
            
            panel.nameFieldStringValue =
            base +
            (format == .rawText ? "_raw" : "") +
            "." +
            format.fileExtension
            
            guard panel.runModal() == .OK,
                  let url = panel.url else {
                return
            }
            
            try? content.write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
            
        case .both:
            let folderPanel = NSOpenPanel()
            
            folderPanel.canChooseDirectories    = true
            folderPanel.canChooseFiles          = false
            folderPanel.allowsMultipleSelection = false
            folderPanel.prompt = "Save Both Files Here"
            
            guard folderPanel.runModal() == .OK,
                  let dir = folderPanel.url else {
                return
            }
            
            let baseA =
            currentFile?
                .url
                .deletingPathExtension()
                .lastPathComponent ?? "FileA"
            
            let baseB =
            compareFile?
                .url
                .deletingPathExtension()
                .lastPathComponent ?? "FileB"
            
            let suffix = format == .rawText ? "_raw" : ""
            let ext    = format.fileExtension
            
            if let ca = outputStringRaw(
                file: currentFile,
                format: format
            ) {
                try? ca.write(
                    to: dir.appendingPathComponent(
                        baseA + suffix + "_FileA." + ext
                    ),
                    atomically: true,
                    encoding: .utf8
                )
            }
            
            if let cb = outputStringRaw(
                file: compareFile,
                format: format
            ) {
                try? cb.write(
                    to: dir.appendingPathComponent(
                        baseB + suffix + "_FileB." + ext
                    ),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
    }
    
    // MARK: - Export Compare All
    
    func exportCompareAll(source: CopySource) {
        let folderPanel = NSOpenPanel()
        
        folderPanel.canChooseDirectories    = true
        folderPanel.canChooseFiles          = false
        folderPanel.allowsMultipleSelection = false
        folderPanel.prompt = "Export All Here"
        
        guard folderPanel.runModal() == .OK,
              let dir = folderPanel.url else {
            return
        }
        
        let snapshotA = currentFile
        let snapshotB = compareFile
        
        Task {
            switch source {
            case .fileA:
                if let f = snapshotA {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "",
                        dir: dir
                    )
                }
                
            case .fileB:
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "",
                        dir: dir
                    )
                }
                
            case .both:
                if let f = snapshotA {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileA",
                        dir: dir
                    )
                }
                
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileB",
                        dir: dir
                    )
                }
            }
        }
    }
    
    // MARK: - Export Compare All as ZIP
    
    func exportCompareAllAsZip(source: CopySource) {
        let panel = NSSavePanel()
        
        panel.allowedContentTypes = [
            UTType(filenameExtension: "zip") ?? .data
        ]
        
        switch source {
        case .fileA:
            let base =
            currentFile?
                .url
                .deletingPathExtension()
                .lastPathComponent ?? "FileA"
            
            panel.nameFieldStringValue = base + "_mediainfo.zip"
            
        case .fileB:
            let base =
            compareFile?
                .url
                .deletingPathExtension()
                .lastPathComponent ?? "FileB"
            
            panel.nameFieldStringValue = base + "_mediainfo.zip"
            
        case .both:
            panel.nameFieldStringValue = "mediainfo_compare.zip"
        }
        
        guard panel.runModal() == .OK,
              let destZip = panel.url else {
            return
        }
        
        let snapshotA = currentFile
        let snapshotB = compareFile
        
        Task {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "SwiftMediaInfo_\(UUID().uuidString)",
                    isDirectory: true
                )
            
            try? FileManager.default.createDirectory(
                at: tmpDir,
                withIntermediateDirectories: true
            )
            
            switch source {
            case .fileA:
                if let f = snapshotA {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "",
                        dir: tmpDir
                    )
                }
                
            case .fileB:
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "",
                        dir: tmpDir
                    )
                }
                
            case .both:
                if let f = snapshotA {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileA",
                        dir: tmpDir
                    )
                }
                
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileB",
                        dir: tmpDir
                    )
                }
            }
            
            await createZip(from: tmpDir, to: destZip)
        }
    }
    
    // MARK: - Shared async writer
    
    private func writeFormatsAsync(
        snapshot: MediaFile,
        base: String,
        tag: String,
        dir: URL
    ) async {
        let fileURL = snapshot.url
        
        let htmlContent: String
        if let html = snapshot.rawHTML {
            htmlContent = html
        } else {
            htmlContent = await MediaEngine.fetchHTML(fileURL)
        }
        
        let xmlContent: String
        if let xml = snapshot.rawXML {
            xmlContent = xml
        } else {
            xmlContent = await MediaEngine.fetchXML(fileURL)
        }
        
        let formats: [(content: String, suffix: String, ext: String)] = [
            (snapshot.rawText     ?? "", "",     "txt"),
            (snapshot.rawTextFull ?? "", "_raw", "txt"),
            (htmlContent,               "",     "html"),
            (xmlContent,                "",     "xml"),
            (snapshot.rawJSON     ?? "", "",     "json"),
            (buildCSV(for: snapshot),   "",     "csv"),
        ]
        
        for (content, suffix, ext) in formats {
            guard !content.isEmpty else {
                continue
            }
            
            let dest = dir.appendingPathComponent(
                base + suffix + tag + "." + ext
            )
            
            try? content.write(
                to: dest,
                atomically: true,
                encoding: .utf8
            )
        }
    }
    
    // MARK: - ZIP helper
    
    private func zipFormats(
        snapshot: MediaFile,
        base: String,
        tag: String,
        destZip: URL
    ) async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SwiftMediaInfo_\(UUID().uuidString)",
                isDirectory: true
            )
        
        try? FileManager.default.createDirectory(
            at: tmpDir,
            withIntermediateDirectories: true
        )
        
        await writeFormatsAsync(
            snapshot: snapshot,
            base: base,
            tag: tag,
            dir: tmpDir
        )
        
        await createZip(from: tmpDir, to: destZip)
    }
    
    // MARK: - createZip
    
    nonisolated
    private func createZip(from sourceDir: URL, to destZip: URL) async {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: nil
        ),
              !files.isEmpty else {
            try? FileManager.default.removeItem(at: sourceDir)
            return
        }
        
        let destPath = destZip.path
        let filePaths = files.map { $0.path }
        
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            
            process.executableURL = URL(
                fileURLWithPath: "/usr/bin/zip"
            )
            
            process.arguments = ["-j", destPath] + filePaths
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            
            try? process.run()
            process.waitUntilExit()
        }.value
        
        try? FileManager.default.removeItem(at: sourceDir)
    }
    
    // MARK: - outputString helpers
    
    func outputString(for format: ExportFormat) -> String? {
        outputStringRaw(file: currentFile, format: format)
    }
    
    private func outputStringRaw(
        file: MediaFile?,
        format: ExportFormat
    ) -> String? {
        guard let file = file else {
            return nil
        }
        
        switch format {
        case .text:
            return file.rawText
            
        case .rawText:
            return file.rawTextFull
            
        case .html:
            return file.rawHTML
            
        case .xml:
            return file.rawXML
            
        case .json:
            return file.rawJSON
            
        case .csv:
            return buildCSV(for: file)
        }
    }
    
    private func currentOutputString() -> String? {
        switch viewMode {
        case .text:
            return currentFile?.rawText
            
        case .rawText:
            return currentFile?.rawTextFull
            
        case .html:
            return currentFile?.rawHTML
            
        case .xml:
            return currentFile?.rawXML
            
        case .json:
            return currentFile?.rawJSON
            
        default:
            return currentFile?.rawText
        }
    }
    
    private func buildCSV(for file: MediaFile) -> String {
        var lines = ["Track,Field,Value"]
        
        for track in file.tracks {
            for field in track.fields {
                let escaped = field.value
                    .replacingOccurrences(of: "\"", with: "\"\"")
                
                lines.append(
                    "\"\(track.displayTitle)\"," +
                    "\"\(field.key)\"," +
                    "\"\(escaped)\""
                )
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
