//
//  MediaStore_ShareExtension.swift
//  SwiftMediaInfo
//
//  PHASE 5 — sharing is now a two-step, sanitised operation.
//
//  WHAT CHANGED
//
//  1. Nothing is uploaded until the user has seen what is being removed.
//     Share now prepares the payload, sanitises it, and presents a review
//     screen listing every redaction. Uploading happens only after the user
//     confirms. A privacy measure the user can't see is one they can't trust.
//
//  2. Local paths are stripped before upload — see PrivacySanitizer.
//     Copy and Export are untouched; those stay on the user's own machine.
//
//  3. Temporary files live in owner-only, uniquely named directories that are
//     removed on every exit path, including failures.
//
//  4. curl is invoked with an explicit end-of-options marker and a URL that is
//     never assembled from user input.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Payload

/// What is about to be uploaded, after sanitisation.
struct PendingShare: Equatable {
    enum Payload: Equatable {
        /// A single document.
        case document(name: String, content: String)
        /// Several documents to be zipped together.
        case archive(baseName: String, documents: [Document])
        
        struct Document: Equatable {
            let name: String
            let content: String
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
    
    static func == (lhs: PendingShare, rhs: PendingShare) -> Bool {
        lhs.format == rhs.format &&
        lhs.source == rhs.source &&
        lhs.fileName == rhs.fileName &&
        lhs.removePaths == rhs.removePaths &&
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
        
        isPreparingShare = true
        pendingShare     = nil
        shareResultURL   = nil
        shareError       = nil
        isUploading      = false
        showShareResult  = true
        
        let snapshot = file
        let timeout  = analysisTimeout
        
        Task {
            do {
                let prepared = try await buildPendingShare(
                    format: format,
                    source: source,
                    snapshot: snapshot,
                    timeout: timeout
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
                case .document(let name, let content):
                    url = try await uploadDocument(content: content, filename: name)
                    
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
    
    private func buildPendingShare(
        format: ShareFormat,
        source: CopySource,
        snapshot: MediaFile,
        timeout: TimeInterval
    ) async throws -> PendingShare {
        
        let base = snapshot.url.deletingPathExtension().lastPathComponent
        let fileURL = snapshot.url
        
        switch format {
        case .txt:
            let raw = try await resolve(snapshot.rawText) {
                try await MediaEngine.fetchText(fileURL, timeout: timeout)
            }
            return finalize(raw, name: base + ".txt", format: format,
                            source: source, snapshot: snapshot)
            
        case .rawText:
            let raw = try await resolve(snapshot.rawTextFull) {
                try await MediaEngine.fetchRawText(fileURL, timeout: timeout)
            }
            return finalize(raw, name: base + "_raw.txt", format: format,
                            source: source, snapshot: snapshot)
            
        case .csv:
            let raw = buildCSVForShare(for: snapshot)
            return finalize(raw, name: base + ".csv", format: format,
                            source: source, snapshot: snapshot)
            
        case .json:
            let raw = try await resolve(snapshot.rawJSON) {
                try await MediaEngine.fetchJSON(fileURL, timeout: timeout)
            }
            return finalize(raw, name: base + ".json", format: format,
                            source: source, snapshot: snapshot)
            
        case .html:
            let raw = try await resolve(snapshot.rawHTML) {
                try await MediaEngine.fetchHTML(fileURL, timeout: timeout)
            }
            return finalize(raw, name: base + ".html", format: format,
                            source: source, snapshot: snapshot)
            
        case .zip:
            var documents: [PendingShare.Payload.Document] = []
            var originals: [PendingShare.Payload.Document] = []
            var reports: [SanitizationReport] = []
            
            func add(_ content: String, _ name: String) {
                guard !content.isEmpty else { return }
                let result = PrivacySanitizer.sanitize(content, fileURL: fileURL)
                documents.append(.init(name: name, content: result.text))
                originals.append(.init(name: name, content: content))
                reports.append(result.report)
            }
            
            add(snapshot.rawText     ?? "", base + ".txt")
            add(snapshot.rawTextFull ?? "", base + "_raw.txt")
            add(snapshot.rawJSON     ?? "", base + ".json")
            add(buildCSVForShare(for: snapshot), base + ".csv")
            
            // `??` takes an autoclosure on the right, which cannot contain an
            // await — so these are written out explicitly. A format that fails
            // to fetch is simply left out of the archive rather than failing
            // the whole upload.
            let html: String
            if let cached = snapshot.rawHTML, !cached.isEmpty {
                html = cached
            } else {
                html = await MediaEngine.fetchHTMLResult(fileURL, timeout: timeout).value ?? ""
            }
            add(html, base + ".html")
            
            let xml: String
            if let cached = snapshot.rawXML, !cached.isEmpty {
                xml = cached
            } else {
                xml = await MediaEngine.fetchXMLResult(fileURL, timeout: timeout).value ?? ""
            }
            add(xml, base + ".xml")
            
            guard !documents.isEmpty else {
                throw ShareError.uploadFailed("There was nothing to upload.")
            }
            
            return PendingShare(
                format: format,
                source: source,
                fileName: snapshot.fileName,
                payload: .archive(baseName: base, documents: documents),
                originalPayload: .archive(baseName: base, documents: originals),
                report: SanitizationReport.combining(reports),
                removePaths: PrivacyPreference.share != .never
            )
        }
    }
    
    private func resolve(
        _ cached: String?,
        fetch: () async throws -> String
    ) async throws -> String {
        if let cached, !cached.isEmpty { return cached }
        return try await fetch()
    }
    
    private func finalize(
        _ raw: String,
        name: String,
        format: ShareFormat,
        source: CopySource,
        snapshot: MediaFile
    ) -> PendingShare {
        let result = PrivacySanitizer.sanitize(raw, fileURL: snapshot.url)
        
        return PendingShare(
            format: format,
            source: source,
            fileName: snapshot.fileName,
            payload: .document(name: name, content: result.text),
            originalPayload: .document(name: name, content: raw),
            report: result.report,
            removePaths: PrivacyPreference.share != .never
        )
    }
    
    // MARK: - Upload: single document
    
    private func uploadDocument(content: String, filename: String) async throws -> String {
        let workspace = try SecureTemporaryDirectory()
        defer { workspace.cleanUp() }
        
        let tempFile = workspace.file(named: filename)
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        
        let response = await runCurl(arguments: [
            "--silent",
            "--show-error",
            "--fail",
            "--max-time", "120",
            "--request", "POST",
            "--data-binary", "@" + tempFile.path(percentEncoded: false),
            "--",
            "https://pb.plz.ac/"
        ])
        
        return try parseUploadResponse(response)
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
            try document.content.write(to: destination, atomically: true, encoding: .utf8)
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
    
    // MARK: - CSV
    
    private func buildCSVForShare(for file: MediaFile) -> String {
        buildCSV(for: file)
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
