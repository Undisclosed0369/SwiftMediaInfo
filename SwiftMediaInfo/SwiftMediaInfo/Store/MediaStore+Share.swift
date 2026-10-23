//
//  MediaStore+Share.swift
//  SwiftMediaInfo
//
//  Sharing a report online, in two steps.
//
//  1. Prepare: build the format's contents (through `exportData`, as Export
//     does), make a sanitised copy without local paths (PrivacySanitizer),
//     and show the review screen (ShareResultView) listing every redaction
//     and whether the checksum is included. Nothing is uploaded yet.
//  2. Upload, once confirmed: HTML and PDF to ship.page (a PDF wrapped in a
//     full-window viewer page), Markdown to markdown.page, Text, CSV, JSON
//     and XML to pb.plz.ac, a ZIP of everything to up.sb.
//
//  Temporary files live in owner-only, uniquely named folders removed on
//  every exit path (SecureTemporaryDirectory). curl is invoked with an
//  explicit end-of-options marker and a URL never assembled from user input.
//  If a service changes its API, its request and response parsing are in
//  the upload functions below.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Payload

/// What is about to be uploaded, after sanitisation.
struct PendingShare: Equatable {
    enum Payload: Equatable {
        /// A single file — text, or the PDF's bytes.
        case document(name: String, data: Data)
        /// Several documents to be zipped together.
        case archive(baseName: String, documents: [Document])
        
        struct Document: Equatable {
            let name: String
            let data: Data
        }
    }
    
    let format: ShareFormat
    let source: CopySource
    let fileName: String
    /// Sanitised version of the payload.
    let payload: Payload
    /// The original, with paths intact. Kept so the "Ask" preference can offer
    /// both without re-running MediaInfo when the choice changes.
    let originalPayload: Payload
    let report: SanitizationReport
    /// Whether the sanitised version is the one that will be uploaded.
    var removePaths: Bool
    /// Whether the SHA-256 checksum is in the upload, shown on the
    /// review screen. Nil when the file has no checksum to include.
    var includesChecksum: Bool?
    /// HTML keeps or loses its paths by Settings › Privacy › Include
    /// paths in HTML; the review screen says so rather than offering a choice.
    var pathsKeptBySetting = false
    var pathsRemovedBySetting = false
    /// Whether the review screen offers Remove / Include.
    var offersPathChoice = false
    
    static func == (lhs: PendingShare, rhs: PendingShare) -> Bool {
        lhs.format == rhs.format &&
        lhs.source == rhs.source &&
        lhs.fileName == rhs.fileName &&
        lhs.removePaths == rhs.removePaths &&
        lhs.includesChecksum == rhs.includesChecksum &&
        lhs.payload == rhs.payload
    }
}

extension MediaStore {
    
    // MARK: - Step 1 — prepare and review
    
    /// Gathers the content, sanitises it, and presents the review screen.
    /// This does not upload anything.
    func shareOnline(format: ShareFormat, source: CopySource) {
        let file: MediaFile?
        switch source {
        case .fileA: file = currentFile
        case .fileB: file = compareFile
        case .both:  file = currentFile   // "both" isn't offered for sharing
        }
        
        guard let file else { return }
        
        // Asked before anything is prepared, so the review screen can say
        // plainly whether the checksum is going out.
        guard let includeChecksum = PrivacyPreference.resolveChecksumDecision(
            actionName: "Share", files: [file]
        ) else { return }
        
        isPreparingShare = true
        pendingShare     = nil
        shareResultURL   = nil
        shareError       = nil
        isUploading      = false
        showShareResult  = true
        
        let needed: [MediaFormat] = format.exportFormat.map { [$0.sourceFormat] } ?? MediaFormat.allCases

        Task {
            do {
                // Formats arrive one at a time; wait for what this share
                // uses rather than running a second mediainfo for it.
                let snapshot = await completedSnapshot(file, needing: needed)

                let prepared = try await buildPendingShare(
                    format: format,
                    source: source,
                    snapshot: snapshot,
                    includeChecksum: includeChecksum
                )
                
                await MainActor.run {
                    self.pendingShare     = prepared
                    self.isPreparingShare = false
                }
            } catch {
                await MainActor.run {
                    self.shareError       = error.localizedDescription
                    self.isPreparingShare = false
                }
            }
        }
    }
    
    // MARK: - Step 2 — confirmed upload
    
    /// Uploads the reviewed payload. Called only from the review screen.
    func confirmShareUpload() {
        guard let pending = pendingShare else { return }
        
        // Whichever version the user settled on. The unsanitised one is only
        // ever reachable when the preference explicitly allows it.
        let payload = pending.removePaths ? pending.payload : pending.originalPayload
        
        isUploading    = true
        shareError     = nil
        shareResultURL = nil
        
        Task {
            do {
                let url: String
                
                switch payload {
                case .document(let name, let data):
                    url = try await uploadDocument(data, filename: name, format: pending.format)
                    
                case .archive(let baseName, let documents):
                    url = try await uploadArchive(baseName: baseName, documents: documents)
                }
                
                await MainActor.run {
                    self.shareResultURL = url
                    self.isUploading    = false
                    self.pendingShare   = nil
                }
            } catch {
                await MainActor.run {
                    self.shareError  = error.localizedDescription
                    self.isUploading = false
                }
            }
        }
    }
    
    /// Flip the sanitisation choice on the review screen. Only reachable when
    /// the Share privacy preference is set to Ask.
    func setPendingShareRemovesPaths(_ removePaths: Bool) {
        guard var pending = pendingShare else { return }
        pending.removePaths = removePaths
        pendingShare = pending
    }
    
    func cancelPendingShare() {
        pendingShare     = nil
        isPreparingShare = false
        showShareResult  = false
    }
    
    func dismissShareResult() {
        showShareResult  = false
        shareResultURL   = nil
        shareError       = nil
        isUploading      = false
        isPreparingShare = false
        pendingShare     = nil
    }
    
    // MARK: - Payload assembly
    
    /// Builds both versions of the upload — paths removed and paths kept —
    /// from exactly what Export would write, so a shared HTML or PDF is the
    /// same document, in the same light or dark appearance, as the exported
    /// one.
    private func buildPendingShare(
        format: ShareFormat,
        source: CopySource,
        snapshot: MediaFile,
        includeChecksum: Bool
    ) async throws -> PendingShare {
        let base = snapshot.url.deletingPathExtension().lastPathComponent
        let formats = format.exportFormat.map { [$0] } ?? ExportFormat.allCases
        
        var sanitizedDocs: [PendingShare.Payload.Document] = []
        var originalDocs: [PendingShare.Payload.Document] = []
        var reports: [SanitizationReport] = []
        
        // HTML's own setting: Always and Never fix both versions; Ask lets
        // the review screen's choice decide, like every other format.
        let htmlMode = PrivacyPreference.htmlPaths
        
        for exportFormat in formats {
            guard let original = await exportData(
                for: snapshot, format: exportFormat, removePaths: false,
                htmlRemovePaths: htmlMode == .never, includeChecksum: includeChecksum
            ), let sanitized = await exportData(
                for: snapshot, format: exportFormat, removePaths: true,
                htmlRemovePaths: htmlMode != .always, includeChecksum: includeChecksum
            ) else { continue }
            
            let name = base + exportFormat.fileSuffix + "." + exportFormat.fileExtension
            originalDocs.append(.init(name: name, data: original))
            sanitizedDocs.append(.init(name: name, data: sanitized))
            
            // What the review screen lists as removed. The PDF is checked
            // through the text it was made from, since its bytes are binary.
            let text = exportFormat == .pdf
            ? ReportDocument(file: includeChecksum ? snapshot : snapshot.withoutChecksum()).markdown
            : String(decoding: original, as: UTF8.self)
            let keepsPaths = exportFormat == .html && htmlMode == .always
            if !keepsPaths {
                reports.append(Self.sanitized(text, fileURL: snapshot.url).report)
            }
        }
        
        guard !sanitizedDocs.isEmpty else {
            throw ShareError.uploadFailed("There was nothing to upload.")
        }
        
        let payload: PendingShare.Payload
        let originalPayload: PendingShare.Payload
        if format == .zip {
            payload = .archive(baseName: base, documents: sanitizedDocs)
            originalPayload = .archive(baseName: base, documents: originalDocs)
        } else {
            payload = .document(name: sanitizedDocs[0].name, data: sanitizedDocs[0].data)
            originalPayload = .document(name: originalDocs[0].name, data: originalDocs[0].data)
        }
        
        let hasDigest = file(withSessionID: snapshot.id)?.hashState.digest != nil
        let isHTML = format == .html
        let pathsKept = isHTML && htmlMode == .always
        let pathsRemoved = isHTML && htmlMode == .never
        let removePaths: Bool = pathsKept ? false
        : pathsRemoved ? true
        : isHTML ? true                      // Ask: start from the safe choice
        : PrivacyPreference.share != .never
        
        return PendingShare(
            format: format,
            source: source,
            fileName: snapshot.fileName,
            payload: payload,
            originalPayload: originalPayload,
            report: SanitizationReport.combining(reports),
            removePaths: removePaths,
            includesChecksum: hasDigest ? includeChecksum : nil,
            pathsKeptBySetting: pathsKept,
            pathsRemovedBySetting: pathsRemoved,
            offersPathChoice: isHTML ? htmlMode == .ask : PrivacyPreference.share == .ask
        )
    }
    
    // MARK: - Upload: single document
    
    private func uploadDocument(_ data: Data, filename: String, format: ShareFormat) async throws -> String {
        let workspace = try SecureTemporaryDirectory()
        defer { workspace.cleanUp() }
        
        switch format.host {
        case .webPage:
            // HTML goes up as the page itself. A PDF is wrapped in a page
            // that shows it full-window, so the link opens straight into the
            // document in any browser.
            let page = format == .pdf ? Self.pdfViewerPage(data, title: filename) : data
            let file = workspace.file(named: "page.html")
            try page.write(to: file, options: .atomic)
            let response = await runCurl(arguments: [
                "--silent", "--show-error", "--fail",
                "--max-time", "300",
                "--request", "POST",
                "--header", "Content-Type: text/html",
                "--data-binary", "@" + file.path(percentEncoded: false),
                "--",
                "https://ship.page/deploy"
            ])
            return try parseUploadResponse(response)
            
        case .markdownPage:
            let file = workspace.file(named: filename)
            try data.write(to: file, options: .atomic)
            let response = await runCurl(arguments: [
                "--silent", "--show-error", "--fail",
                "--max-time", "120",
                "--data-binary", "@" + file.path(percentEncoded: false),
                "--",
                "https://markdown.page/api/publish"
            ])
            return try parseUploadResponse(response)
            
        case .paste, .fileDrop:
            let file = workspace.file(named: filename)
            try data.write(to: file, options: .atomic)
            let response = await runCurl(arguments: [
                "--silent", "--show-error", "--fail",
                "--max-time", "120",
                "--request", "POST",
                "--data-binary", "@" + file.path(percentEncoded: false),
                "--",
                "https://pb.plz.ac/"
            ])
            return try parseUploadResponse(response)
        }
    }
    
    /// A page that is nothing but the PDF, filling the window.
    private static func pdfViewerPage(_ pdf: Data, title: String) -> Data {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let page = """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(escapedTitle)</title>
        <style>html,body,iframe{margin:0;width:100%;height:100%;border:0}</style>
        </head><body><iframe src="data:application/pdf;base64,\(pdf.base64EncodedString())"></iframe></body></html>
        """
        return Data(page.utf8)
    }
    
    // MARK: - Upload: archive
    
    private func uploadArchive(
        baseName: String,
        documents: [PendingShare.Payload.Document]
    ) async throws -> String {
        let workspace = try SecureTemporaryDirectory()
        defer { workspace.cleanUp() }
        
        // Documents and the archive live in separate subdirectories so the zip
        // can't accidentally include itself.
        let contentsDir = workspace.url.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contentsDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        
        var paths: [String] = []
        for document in documents {
            let destination = contentsDir.appendingPathComponent(document.name)
            try document.data.write(to: destination, options: .atomic)
            paths.append(destination.path(percentEncoded: false))
        }
        
        let archive = workspace.file(named: baseName + "_mediainfo.zip")
        let archivePath = archive.path(percentEncoded: false)
        
        let zipSucceeded = await Task.detached(priority: .userInitiated) { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            // "-j" flattens paths so the archive has no directory structure.
            //
            // No "--" marker here: Info-ZIP's zip does not implement one and
            // treats it as the archive name, which is what broke archive
            // creation. It isn't needed anyway — every path passed in is
            // absolute and therefore starts with "/", so none of them can be
            // mistaken for an option.
            process.arguments = ["-j", archivePath] + paths
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            process.standardInput  = FileHandle.nullDevice
            
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
        
        guard zipSucceeded,
              FileManager.default.fileExists(atPath: archivePath) else {
            throw ShareError.uploadFailed("Couldn’t create the archive.")
        }
        
        let response = await runCurl(arguments: [
            "--silent",
            "--show-error",
            "--fail",
            "--max-time", "300",
            "--upload-file", archivePath,
            "--",
            "https://up.sb"
        ])
        
        return try parseUploadResponse(response)
    }
    
    // MARK: - Response parsing
    
    private func parseUploadResponse(_ response: String) throws -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            throw ShareError.uploadFailed("The server didn’t respond.")
        }
        
        // ship.page answers in JSON with the link under "url"; markdown.page
        // may too. Anything else is read as plain text below.
        if let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] {
            for key in ["url", "link", "href"] {
                if let link = json[key] as? String, link.hasPrefix("http") { return link }
            }
        }
        
        // Some endpoints return the URL alone, others wrap it in a line of text.
        if trimmed.hasPrefix("http") && !trimmed.contains("\n") {
            return trimmed
        }
        
        for line in trimmed.components(separatedBy: .newlines) {
            for token in line.components(separatedBy: .whitespaces)
            where token.hasPrefix("http") {
                return token
            }
        }
        
        throw ShareError.uploadFailed("Unexpected response from the server.")
    }
    
    // MARK: - curl
    
    /// Runs curl with no shell involved and no string interpolation into the
    /// command. Both pipes are drained before waiting, for the same
    /// deadlock reason documented in MediaEngine.
    private func runCurl(arguments: [String]) async -> String {
        await Task.detached(priority: .userInitiated) {
            let process   = Process()
            let outPipe   = Pipe()
            let errPipe   = Pipe()
            
            process.executableURL  = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments      = arguments
            process.standardOutput = outPipe
            process.standardError  = errPipe
            process.standardInput  = FileHandle.nullDevice
            
            var environment = ProcessInfo.processInfo.environment
            environment["LANG"]   = "en_US.UTF-8"
            environment["LC_ALL"] = "en_US.UTF-8"
            process.environment = environment
            
            guard (try? process.run()) != nil else { return "" }
            
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            _ = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            return String(data: outData, encoding: .utf8) ?? ""
        }.value
    }
}

// MARK: - Share Error

enum ShareError: LocalizedError {
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .uploadFailed(let reason): return reason
        }
    }
}
