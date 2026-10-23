//
//  MediaStore+Export.swift
//  SwiftMediaInfo
//
//  Exporting: one format, Export All Formats (into a folder), Export All as
//  ZIP, and the same three for Compare Mode's File A / File B / Both.
//
//  HOW IT FITS TOGETHER
//
//  • `exportData(for:format:…)` is the one place a format's file contents are
//    built — checksum, privacy pass and trailing-whitespace trim included —
//    so a format comes out the same from every export path (and Share).
//  • `outputStringRaw` is the raw text for one format, checksum folded in;
//    `outputStringForFile` (the current view's text) is shared with Copy.
//  • Formats that haven't loaded yet are waited for (`completedSnapshot`),
//    or fetched for HTML and XML, and kept for the view afterwards.
//  • Privacy questions (paths, checksum, paths in HTML) are asked once per
//    export, after the save panel, via PrivacyPreference.
//  • Menus start an export through `afterPopoverCloses`, so the save panel
//    runs after the popover has closed (see its note).
//
//  CSV, Markdown and PDF are built from the parsed tracks: CSV here,
//  Markdown and PDF by ReportDocument and PDFRenderer.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension MediaStore {
    
    // MARK: - Checksum in exported output
    //
    // One function adds the checksum to any format, in whatever way that
    // format can absorb without becoming invalid (see FileHasher's append
    // functions). CSV, Markdown and PDF get it from the General track.
    
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
        case .csv, .markdown, .pdf:
            // Built from the tracks, and the digest is already a field on the
            // General track, so it is in there already.
            return content
        }
    }
    
    /// The export format that corresponds to the view on screen.
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
    /// Exporting HTML or XML before that view has been opened runs mediainfo
    /// to produce it; this hands the result to whichever pane the file is open
    /// in, so switching to the view afterwards doesn't run it again.
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
        
        // Remembered too, so the view is instant on every reopen.
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
    // HTML and XML may not have loaded yet, so exporting them can mean
    // fetching first. A failure skips that one format quietly rather than
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
        
        panel.nameFieldStringValue = base + format.fileSuffix + "." + format.fileExtension
        panel.allowedContentTypes  = [
            UTType(filenameExtension: format.fileExtension) ?? .plainText
        ]
        
        guard panel.runModal() == .OK,
              let saveURL = panel.url else {
            return
        }
        
        // HTML has its own setting, so it never asks the general question.
        guard let shouldRemovePaths = format == .html
                ? PrivacyPreference.resolveHTMLPathsDecision(actionName: "Export")
                : PrivacyPreference.resolveLocalDecision(actionName: "Export"),
              let includeChecksum = PrivacyPreference.resolveChecksumDecision(
                actionName: "Export", files: [file]
              ) else { return }
        
        Task {
            // The format may still be loading in the background.
            let snapshot = await completedSnapshot(file, needing: [format.sourceFormat])
            guard let data = await exportData(
                for: snapshot, format: format,
                removePaths: shouldRemovePaths,
                htmlRemovePaths: format == .html ? shouldRemovePaths : nil,
                includeChecksum: includeChecksum
            ) else { return }
            try? data.write(to: saveURL, options: .atomic)
        }
    }
    
    // MARK: - One format's file contents
    //
    // Every export path — one format, Export All, ZIP and the three Compare
    // Mode variants — asks here, so a format behaves identically wherever it
    // is exported from. The checksum, the privacy pass and the trailing-
    // whitespace trim all happen in this one place.
    
    func exportData(
        for snapshot: MediaFile,
        format: ExportFormat,
        removePaths: Bool,
        htmlRemovePaths: Bool? = nil,
        includeChecksum: Bool = true
    ) async -> Data? {
        var snapshot = includeChecksum ? snapshot : snapshot.withoutChecksum()
        
        // HTML follows Settings › Privacy › "Include paths in HTML", not the
        // general path settings. `htmlRemovePaths` carries an answer already
        // given to its Ask; without one, Always and Never decide.
        let generalRemovePaths = removePaths
        let removePaths: Bool
        if format == .html {
            switch PrivacyPreference.htmlPaths {
            case .always: removePaths = htmlRemovePaths ?? false
            case .never:  removePaths = htmlRemovePaths ?? true
            case .ask:    removePaths = htmlRemovePaths ?? generalRemovePaths
            }
        } else {
            removePaths = generalRemovePaths
        }
        
        // A format nobody has looked at yet may never have been queued, so
        // waiting for the loader finds nothing. Fetch it here rather than
        // write nothing. (HTML and XML have their own fetch below, which
        // also keeps the result for their tabs.)
        let source = format.sourceFormat
        if snapshot.content(for: source) == nil, source != .html, source != .xml {
            let result: Result<String, MediaInfoError>
            switch source {
            case .text:    result = await MediaEngine.fetchTextResult(snapshot.url, timeout: analysisTimeout)
            case .rawText: result = await MediaEngine.fetchRawTextResult(snapshot.url, timeout: analysisTimeout)
            default:       result = await MediaEngine.fetchJSONResult(snapshot.url, timeout: analysisTimeout)
            }
            let tracks = source == .json ? (result.value.map { MediaEngine.parseTracks(from: $0) } ?? []) : []
            snapshot.apply(result, tracks: tracks, for: source)
        }
        
        func prepared(_ text: String) -> String {
            guard removePaths else { return text.trimmingTrailingWhitespace }
            return Self.sanitized(text, fileURL: snapshot.url).text.trimmingTrailingWhitespace
        }
        
        switch format {
        case .html:
            // Styled exactly like the in-app HTML tab — see ReportHTML.
            let raw: String?
            if let html = snapshot.rawHTML {
                raw = html
            } else {
                raw = await fetchHTMLForOutput(snapshot.url)
            }
            guard let raw = withChecksum(raw, file: snapshot, format: .html), !raw.isEmpty else { return nil }
            return prepared(ReportHTML.styledDocument(raw, appearance: .export(isDark: Self.exportsDark))).data(using: .utf8)
            
        case .xml:
            let raw: String?
            if let xml = snapshot.rawXML {
                raw = xml
            } else {
                raw = await fetchXMLForOutput(snapshot.url)
            }
            guard let content = withChecksum(raw, file: snapshot, format: .xml), !content.isEmpty else { return nil }
            return prepared(content).data(using: .utf8)
            
        case .pdf:
            guard !snapshot.tracks.isEmpty else { return nil }
            let isDark = Self.exportsDark
            let html = ReportDocument(file: snapshot).pdfHTML(iconPNG: Self.appIconPNG, isDark: isDark)
            return await PDFRenderer.render(html: prepared(html), paper: ReportDocument.pdfPaper(isDark: isDark))
            
        default:
            guard let content = outputStringRaw(file: snapshot, format: format), !content.isEmpty else { return nil }
            return prepared(content).data(using: .utf8)
        }
    }
    
    /// The privacy pass, with the app's own links shielded from it. It
    /// removes the account name wherever it appears, and an account that
    /// shares a word with the website's domain would otherwise turn the PDF
    /// and Markdown footer links into "[user]0369.app".
    static func sanitized(_ text: String, fileURL: URL) -> (text: String, report: SanitizationReport) {
        let shielded = projectLinks.enumerated().reduce(text) { result, item in
            result.replacingOccurrences(of: item.element, with: "\u{E000}LINK\(item.offset)\u{E000}")
        }
        let result = PrivacySanitizer.sanitize(shielded, fileURL: fileURL)
        let restored = projectLinks.enumerated().reduce(result.text) { text, item in
            text.replacingOccurrences(of: "\u{E000}LINK\(item.offset)\u{E000}", with: item.element)
        }
        return (restored, result.report)
    }
    
    /// Whether exports come out dark: they follow the app's own appearance
    /// at the moment of exporting (Settings › Appearance, or the system when
    /// that is set to System).
    private static var exportsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    /// Longest first, so a link is never shielded only partly.
    private static let projectLinks = [
        ProjectLinks.appPage, ProjectLinks.github,
        ReportDocument.githubText, ReportDocument.websiteText
    ].sorted { $0.count > $1.count }
    
    /// The app icon for the PDF's masthead, at a size that stays sharp in
    /// print without bloating the file.
    private static var appIconPNG: Data? {
        let icon = NSApp.applicationIconImage ?? NSImage()
        let size = NSSize(width: 128, height: 128)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
    
    // MARK: - Leaving a popover for a dialog
    
    /// Runs `work` — which opens a save panel, folder picker or privacy
    /// alert — once the popover that asked for it has closed.
    ///
    /// Those dialogs run modally: they spin the run loop until the user
    /// answers. Started straight from a popover button's action, that loop
    /// runs inside SwiftUI's handling of the click, so every change the app
    /// published while the dialog was open — the popover closing, progress,
    /// the analysis of another tab — was reported as "Publishing changes
    /// from within view updates", one line each. On the next turn of the run
    /// loop the click has been fully handled and the dialog runs on its own.
    func afterPopoverCloses(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { work() }
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
        
        guard let privacy = PrivacyPreference.resolveExportDecisions(
            actionName: "Export", files: [file]
        ) else { return }
        let removePaths = privacy.removePaths
        let includeChecksum = privacy.includeChecksum
        let htmlRemovePaths = privacy.htmlRemovePaths
        
        let snapshot = includeChecksum ? file : file.withoutChecksum()
        let base     = file.url.deletingPathExtension().lastPathComponent
        
        Task {
            await writeFormatsAsync(
                snapshot: snapshot,
                base: base,
                tag: "",
                dir: dir,
                removePaths: removePaths,
                htmlRemovePaths: htmlRemovePaths
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
        
        guard let privacy = PrivacyPreference.resolveExportDecisions(
            actionName: "Export", files: [file]
        ) else { return }
        let removePaths = privacy.removePaths
        let includeChecksum = privacy.includeChecksum
        let htmlRemovePaths = privacy.htmlRemovePaths
        
        let snapshot = includeChecksum ? file : file.withoutChecksum()
        
        Task {
            await zipFormats(
                snapshot: snapshot,
                base: base,
                tag: "",
                destZip: destZip,
                removePaths: removePaths,
                htmlRemovePaths: htmlRemovePaths
            )
        }
    }
    
    // MARK: - Export Compare
    
    func exportCompare(source: CopySource, format: ExportFormat) {
        let ext = format.fileExtension
        let files: [(file: MediaFile, tag: String)]
        let destination: URL
        
        switch source {
        case .fileA, .fileB:
            guard let file = source == .fileA ? currentFile : compareFile else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .plainText]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent
            + format.fileSuffix + "." + ext
            guard panel.runModal() == .OK, let url = panel.url else { return }
            files = [(file, "")]
            destination = url
            
        case .both:
            let folderPanel = NSOpenPanel()
            folderPanel.canChooseDirectories    = true
            folderPanel.canChooseFiles          = false
            folderPanel.allowsMultipleSelection = false
            folderPanel.prompt = "Save Both Files Here"
            guard folderPanel.runModal() == .OK, let dir = folderPanel.url else { return }
            files = [(currentFile, "_FileA"), (compareFile, "_FileB")].compactMap { pair in
                pair.0.map { ($0, pair.1) }
            }
            destination = dir
        }
        
        guard let removePaths = format == .html
                ? PrivacyPreference.resolveHTMLPathsDecision(actionName: "Export")
                : PrivacyPreference.resolveLocalDecision(actionName: "Export"),
              let includeChecksum = PrivacyPreference.resolveChecksumDecision(
                actionName: "Export", files: files.map(\.file)
              ) else { return }
        
        Task {
            for (file, tag) in files {
                let snapshot = await completedSnapshot(file, needing: [format.sourceFormat])
                guard let data = await exportData(
                    for: snapshot, format: format,
                    removePaths: removePaths,
                    htmlRemovePaths: format == .html ? removePaths : nil,
                    includeChecksum: includeChecksum
                ) else { continue }
                let url = source == .both
                ? destination.appendingPathComponent(
                    file.url.deletingPathExtension().lastPathComponent + format.fileSuffix + tag + "." + ext)
                : destination
                try? data.write(to: url, options: .atomic)
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
        
        guard let privacy = PrivacyPreference.resolveExportDecisions(
            actionName: "Export", files: compareExportFiles(source)
        ) else { return }
        let removePaths = privacy.removePaths
        let htmlRemovePaths = privacy.htmlRemovePaths
        let targets = compareExportTargets(source, includeChecksum: privacy.includeChecksum)
        
        Task {
            for target in targets {
                await writeFormatsAsync(
                    snapshot: target.file,
                    base: target.file.url.deletingPathExtension().lastPathComponent,
                    tag: target.tag,
                    dir: dir,
                    removePaths: removePaths,
                    htmlRemovePaths: htmlRemovePaths
                )
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
        
        guard let privacy = PrivacyPreference.resolveExportDecisions(
            actionName: "Export", files: compareExportFiles(source)
        ) else { return }
        let removePaths = privacy.removePaths
        let htmlRemovePaths = privacy.htmlRemovePaths
        let targets = compareExportTargets(source, includeChecksum: privacy.includeChecksum)
        
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
            
            for target in targets {
                await writeFormatsAsync(
                    snapshot: target.file,
                    base: target.file.url.deletingPathExtension().lastPathComponent,
                    tag: target.tag,
                    dir: tmpDir,
                    removePaths: removePaths,
                    htmlRemovePaths: htmlRemovePaths
                )
            }
            
            await createZip(from: tmpDir, to: destZip)
        }
    }
    
    // MARK: - Compare export files
    
    /// The files a Compare export covers, for the privacy questions.
    private func compareExportFiles(_ source: CopySource) -> [MediaFile?] {
        switch source {
        case .fileA: return [currentFile]
        case .fileB: return [compareFile]
        case .both:  return [currentFile, compareFile]
        }
    }
    
    /// What a Compare export writes: one side, its names untagged, or both,
    /// tagged _FileA and _FileB — File A first. Without their checksums
    /// unless the user chose to include them.
    private func compareExportTargets(_ source: CopySource, includeChecksum: Bool) -> [(file: MediaFile, tag: String)] {
        let a = includeChecksum ? currentFile : currentFile?.withoutChecksum()
        let b = includeChecksum ? compareFile : compareFile?.withoutChecksum()
        let sides: [(MediaFile?, String)]
        switch source {
        case .fileA: sides = [(a, "")]
        case .fileB: sides = [(b, "")]
        case .both:  sides = [(a, "_FileA"), (b, "_FileB")]
        }
        return sides.compactMap { side in side.0.map { (file: $0, tag: side.1) } }
    }
    
    // MARK: - Shared async writer
    
    private func writeFormatsAsync(
        snapshot: MediaFile,
        base: String,
        tag: String,
        dir: URL,
        removePaths: Bool = false,
        htmlRemovePaths: Bool? = nil
    ) async {
        // A snapshot whose checksum was left out arrives without one, but
        // the live file still has it — so tell the two apart before
        // refreshing, or the checksum would come back.
        let liveHasDigest = file(withSessionID: snapshot.id)?.hashState.digest != nil
        let includeChecksum = snapshot.hashState.digest != nil || !liveHasDigest
        
        // Every format is written, so wait for any still loading in the
        // background rather than leaving them out of the folder.
        let snapshot = await completedSnapshot(snapshot)
        
        // Every format the Export menu offers, Markdown and PDF included.
        for format in ExportFormat.allCases {
            guard let data = await exportData(
                for: snapshot, format: format,
                removePaths: removePaths, htmlRemovePaths: htmlRemovePaths,
                includeChecksum: includeChecksum
            ),
                  !data.isEmpty else { continue }
            
            let dest = dir.appendingPathComponent(
                base + format.fileSuffix + tag + "." + format.fileExtension
            )
            try? data.write(to: dest, options: .atomic)
        }
    }
    
    // MARK: - ZIP helper
    
    private func zipFormats(
        snapshot: MediaFile,
        base: String,
        tag: String,
        destZip: URL,
        removePaths: Bool = false,
        htmlRemovePaths: Bool? = nil
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
    /// The checksum lives here rather than at each of the eight places output
    /// is produced, so none of them can ship without it.
    private func outputStringRaw(
        file: MediaFile?,
        format: ExportFormat
    ) -> String? {
        guard let file = file else {
            return nil
        }
        
        return withChecksum(rawFormatString(file: file, format: format), file: file, format: format)?
            .trimmingTrailingWhitespace
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
            
        case .markdown:
            return ReportDocument(file: file).markdown
            
        case .pdf:
            // Binary; produced by exportData, never as a string.
            return nil
        }
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
