//
//  MediaStore_ExportExtension.swift
//  SwiftMediaInfo
//
//  PHASE 12c — moved out of MediaStore.swift, unchanged.
//
//  WHY THIS FILE EXISTS
//
//  Export was 751 lines sitting in the middle of a 2,437-line file, between the
//  clipboard code and the output-string helpers. Finding it meant scrolling past
//  file loading, comparison state, appearance, zoom, hashing and recent files.
//
//  Splitting it out follows the pattern MediaStore_ShareExtension.swift already
//  set: same type, new file. Nothing moved between types, no property changed
//  owner, and not one call site changed.
//
//  WHAT THIS IS AND IS NOT
//
//  This is a readability change, not an architectural one. `MediaStore` is
//  exactly as large as it was; it is simply no longer all in one place. You can
//  now open a file about exporting when you want to think about exporting.
//
//  A genuinely separate `Exporter` type was considered and rejected. It would
//  need the store's current file, compare file, view mode, cached formats,
//  privacy decisions and checksum state — which is most of the store, so its
//  initialiser would end up being a copy of it. That is not separation, it is
//  paperwork.
//
//  ONE DELIBERATE VISIBILITY CHANGE
//
//  `currentOutputString()` and `outputStringForFile(_:)` were `private` and are
//  now internal. Not a style preference — a requirement. In Swift `private` on
//  an extension member means *file*-scoped, so the moment these moved out of
//  MediaStore.swift the clipboard code left behind could no longer see them.
//  They are the two helpers copy and export genuinely share.
//
//  Everything else in here stays private and stays invisible outside this file,
//  which is most of it.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension MediaStore {
    
    // MARK: - Checksum in exported output (Phase 10)
    //
    // Three separate switches used to map a format to its raw string. Adding
    // the checksum to each of them independently is how they would drift, so
    // they now share one function that appends it in whatever way the format
    // can absorb without becoming invalid.
    
    private func digest(for file: MediaFile) -> String? {
        file.hashState.digest
    }
    
    private func withChecksum(_ content: String?, file: MediaFile, format: ExportFormat) -> String? {
        guard let content, let digest = digest(for: file) else { return content }
        
        switch format {
        case .text, .rawText:
            return FileHasher.appendToText(content, digest: digest)
        case .xml:
            return FileHasher.appendToXML(content, digest: digest)
        case .json:
            return FileHasher.appendToJSON(content, digest: digest)
        case .html:
            return FileHasher.appendToHTML(content, digest: digest)
        case .csv:
            // CSV is built from tracks, and the digest is already a field on
            // the General track, so it is in there already.
            return content
        }
    }
    
    /// The export format that corresponds to the tab on screen.
    private func exportFormat(for mode: ViewMode) -> ExportFormat {
        switch mode {
        case .text:    return .text
        case .rawText: return .rawText
        case .html:    return .html
        case .xml:     return .xml
        case .json:    return .json
        case .easy:    return .text
        }
    }
    
    func outputStringForFile(_ file: MediaFile?) -> String? {
        guard let file = file else { return nil }
        
        return outputStringRaw(file: file, format: exportFormat(for: viewMode))
    }
    
    /// Keep a format that was fetched for export.
    ///
    /// Exporting HTML or XML before that tab has been opened runs mediainfo to
    /// produce it, and the result used to be written to disk and thrown away —
    /// so switching to the tab a moment later ran the whole thing again. The
    /// work is already done; this hands it to whichever pane the file is open
    /// in.
    ///
    /// Only fills an empty slot. Overwriting a format that is already loaded
    /// would be pointless at best, and at worst would replace a fresh result
    /// with a stale one.
    private func adoptFetchedFormat(_ content: String?, mode: ViewMode, url: URL) {
        guard let content, !content.isEmpty else { return }
        
        func apply(to file: inout MediaFile?) {
            guard file?.url == url else { return }
            
            switch mode {
            case .html: if file?.rawHTML == nil { file?.rawHTML = content }
            case .xml:  if file?.rawXML  == nil { file?.rawXML  = content }
            default:    break
            }
        }
        
        apply(to: &currentFile)
        apply(to: &compareFile)
        
        // Remembered too, so a tab visited once is instant on every reopen.
        AnalysisCache.update(for: url) { entry in
            switch mode {
            case .html: entry.rawHTML = content
            case .xml:  entry.rawXML  = content
            default:    break
            }
        }
    }
    
    // MARK: - On-demand fetch for export/share
    //
    // HTML and XML load lazily, so exporting them may require fetching first.
    // A failure here currently results in that one format being skipped, which
    // matches the previous behaviour exactly. Phase 3 surfaces export failures
    // in the UI; until then this stays deliberately quiet rather than silently
    // writing an empty file.
    
    private func fetchHTMLForOutput(_ url: URL) async -> String? {
        let html = await MediaEngine.fetchHTMLResult(url, timeout: analysisTimeout).value
        adoptFetchedFormat(html, mode: .html, url: url)
        return html
    }
    
    private func fetchXMLForOutput(_ url: URL) async -> String? {
        let xml = await MediaEngine.fetchXMLResult(url, timeout: analysisTimeout).value
        adoptFetchedFormat(xml, mode: .xml, url: url)
        return xml
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
        
        guard let shouldRemovePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Export"
        ) else { return }
        
        let snapshot = file
        let dest     = saveURL
        
        Task {
            let content: String?
            
            switch format {
            case .html:
                if let html = snapshot.rawHTML {
                    content = html
                } else {
                    content = withChecksum(
                        await fetchHTMLForOutput(snapshot.url),
                        file: snapshot, format: .html
                    )
                }
                
            case .xml:
                if let xml = snapshot.rawXML {
                    content = xml
                } else {
                    content = withChecksum(
                        await fetchXMLForOutput(snapshot.url),
                        file: snapshot, format: .xml
                    )
                }
                
            default:
                content = outputStringRaw(file: snapshot, format: format)
            }
            
            guard let c = content,
                  !c.isEmpty else {
                return
            }
            
            // No checksum call here: every branch above already went through
            // either outputStringRaw or an explicit wrap, and applying it twice
            // would print the digest twice.
            let output = shouldRemovePaths
            ? PrivacySanitizer.sanitize(c, fileURL: snapshot.url).text
            : c
            
            try? output.write(to: dest, atomically: true, encoding: .utf8)
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
        
        guard let removePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Export"
        ) else { return }
        
        let snapshot = file
        let base     = file.url.deletingPathExtension().lastPathComponent
        
        Task {
            await writeFormatsAsync(
                snapshot: snapshot,
                base: base,
                tag: "",
                dir: dir,
                removePaths: removePaths
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
        
        guard let removePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Export"
        ) else { return }
        
        let snapshot = file
        
        Task {
            await zipFormats(
                snapshot: snapshot,
                base: base,
                tag: "",
                destZip: destZip,
                removePaths: removePaths
            )
        }
    }
    
    // MARK: - Export Compare
    
    func exportCompare(source: CopySource, format: ExportFormat) {
        guard let removePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Export"
        ) else { return }
        
        func prepared(_ text: String, _ file: MediaFile?) -> String {
            guard removePaths, let file else { return text }
            return PrivacySanitizer.sanitize(text, fileURL: file.url).text
        }
        
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
            
            try? prepared(content, currentFile).write(
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
            
            try? prepared(content, compareFile).write(
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
                try? prepared(ca, currentFile).write(
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
                try? prepared(cb, compareFile).write(
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
        
        guard let removePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Export"
        ) else { return }
        
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
                        dir: dir,
                        removePaths: removePaths
                    )
                }
                
            case .fileB:
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "",
                        dir: dir,
                        removePaths: removePaths
                    )
                }
                
            case .both:
                if let f = snapshotA {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileA",
                        dir: dir,
                        removePaths: removePaths
                    )
                }
                
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileB",
                        dir: dir,
                        removePaths: removePaths
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
        
        guard let removePaths = PrivacyPreference.resolveLocalDecision(
            actionName: "Export"
        ) else { return }
        
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
                        dir: tmpDir,
                        removePaths: removePaths
                    )
                }
                
            case .fileB:
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "",
                        dir: tmpDir,
                        removePaths: removePaths
                    )
                }
                
            case .both:
                if let f = snapshotA {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileA",
                        dir: tmpDir,
                        removePaths: removePaths
                    )
                }
                
                if let f = snapshotB {
                    await writeFormatsAsync(
                        snapshot: f,
                        base: f.url.deletingPathExtension().lastPathComponent,
                        tag: "_FileB",
                        dir: tmpDir,
                        removePaths: removePaths
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
        dir: URL,
        removePaths: Bool = false
    ) async {
        let fileURL = snapshot.url
        
        let htmlContent: String
        if let html = snapshot.rawHTML {
            htmlContent = html
        } else {
            htmlContent = await fetchHTMLForOutput(fileURL) ?? ""
        }
        
        let xmlContent: String
        if let xml = snapshot.rawXML {
            xmlContent = xml
        } else {
            xmlContent = await fetchXMLForOutput(fileURL) ?? ""
        }
        
        // Each entry goes through withChecksum for its own format — a digest
        // appended as a plain line would make the XML and JSON files invalid.
        // CSV is already covered, because the digest is a General track field.
        let formats: [(content: String, suffix: String, ext: String)] = [
            (withChecksum(snapshot.rawText,     file: snapshot, format: .text)    ?? "", "",     "txt"),
            (withChecksum(snapshot.rawTextFull, file: snapshot, format: .rawText) ?? "", "_raw", "txt"),
            (withChecksum(htmlContent,          file: snapshot, format: .html)    ?? "", "",     "html"),
            (withChecksum(xmlContent,           file: snapshot, format: .xml)     ?? "", "",     "xml"),
            (withChecksum(snapshot.rawJSON,     file: snapshot, format: .json)    ?? "", "",     "json"),
            (buildCSV(for: snapshot),                                                    "",     "csv"),
        ]
        
        for (content, suffix, ext) in formats {
            guard !content.isEmpty else {
                continue
            }
            
            let dest = dir.appendingPathComponent(
                base + suffix + tag + "." + ext
            )
            
            let output = removePaths
            ? PrivacySanitizer.sanitize(content, fileURL: fileURL).text
            : content
            
            try? output.write(
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
        destZip: URL,
        removePaths: Bool = false
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
            dir: tmpDir,
            removePaths: removePaths
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
    
    /// Raw output for one format, with the checksum already folded in.
    ///
    /// The checksum lives here rather than at each call site. It was added at
    /// two of the eight places output is produced, and the other six — Export
    /// All, Export as ZIP, and their three Compare Mode equivalents — silently
    /// shipped without it. One funnel, one place to be wrong.
    private func outputStringRaw(
        file: MediaFile?,
        format: ExportFormat
    ) -> String? {
        guard let file = file else {
            return nil
        }
        
        return withChecksum(rawFormatString(file: file, format: format), file: file, format: format)
    }
    
    private func rawFormatString(
        file: MediaFile,
        format: ExportFormat
    ) -> String? {
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
    
    func currentOutputString() -> String? {
        outputStringForFile(currentFile)
    }
    
    func buildCSV(for file: MediaFile) -> String {
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
