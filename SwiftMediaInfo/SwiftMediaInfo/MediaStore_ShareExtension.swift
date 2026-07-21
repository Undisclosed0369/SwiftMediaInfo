//
//  MediaStore_ShareExtension.swift
//  SwiftMediaInfo
//
//  Add this entire file to your project. It extends MediaStore with
//  the share/upload functionality via a Swift extension.
//

import SwiftUI
import UniformTypeIdentifiers

extension MediaStore {
    
    // ──────────────────────────────────────────────────────────────────
    //  IMPORTANT — Add these four @Published properties to MediaStore
    //  (inside the class body, near the other @Published vars):
    //
    //      @Published var isUploading:     Bool    = false
    //      @Published var shareResultURL:  String? = nil
    //      @Published var shareError:      String? = nil
    //      @Published var showShareResult: Bool    = false
    // ──────────────────────────────────────────────────────────────────
    
    // MARK: - Share Online (public entry point)
    
    func shareOnline(format: ShareFormat, source: CopySource) {
        let file: MediaFile?
        switch source {
        case .fileA: file = currentFile
        case .fileB: file = compareFile
        case .both:  file = currentFile  // shouldn't happen for share
        }
        
        guard let file = file else { return }
        
        isUploading     = true
        shareResultURL  = nil
        shareError      = nil
        showShareResult = true
        
        let snapshot = file
        
        Task {
            do {
                let url: String
                
                switch format {
                case .txt:
                    let content: String
                    if let cached = snapshot.rawText { content = cached }
                    else { content = await MediaEngine.fetchText(snapshot.url) }
                    url = try await uploadToPb(content: content, filename: baseName(snapshot) + ".txt")
                    
                case .rawText:
                    let content: String
                    if let cached = snapshot.rawTextFull { content = cached }
                    else { content = await MediaEngine.fetchRawText(snapshot.url) }
                    url = try await uploadToPb(content: content, filename: baseName(snapshot) + "_raw.txt")
                    
                case .csv:
                    let content = buildCSVForShare(for: snapshot)
                    url = try await uploadToPb(content: content, filename: baseName(snapshot) + ".csv")
                    
                case .json:
                    let content: String
                    if let cached = snapshot.rawJSON { content = cached }
                    else { content = await MediaEngine.fetchJSON(snapshot.url) }
                    url = try await uploadToPb(content: content, filename: baseName(snapshot) + ".json")
                    
                case .html:
                    let content: String
                    if let html = snapshot.rawHTML {
                        content = html
                    } else {
                        content = await MediaEngine.fetchHTML(snapshot.url)
                    }
                    url = try await uploadToPb(content: content, filename: baseName(snapshot) + ".html")
                    
                case .zip:
                    url = try await uploadZipToUpSb(snapshot: snapshot)
                }
                
                await MainActor.run {
                    self.shareResultURL = url
                    self.isUploading = false
                }
            } catch {
                await MainActor.run {
                    self.shareError = error.localizedDescription
                    self.isUploading = false
                }
            }
        }
    }
    
    func dismissShareResult() {
        showShareResult = false
        shareResultURL  = nil
        shareError      = nil
        isUploading     = false
    }
    
    // MARK: - Upload text to pb.plz.ac
    
    private func uploadToPb(content: String, filename: String) async throws -> String {
        // Write to temp file, curl it, remove temp file
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMediaInfo_share_\(UUID().uuidString)_\(filename)")
        
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        
        let result = await runCurl(arguments: [
            "-s", "-X", "POST",
            "--data-binary", "@\(tmpFile.path(percentEncoded: false))",
            "https://pb.plz.ac/"
        ])
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty, trimmed.hasPrefix("http") else {
            throw ShareError.uploadFailed("Server returned: \(trimmed.isEmpty ? "(empty response)" : trimmed)")
        }
        
        return trimmed
    }
    
    // MARK: - Upload ZIP to up.sb
    
    private func uploadZipToUpSb(snapshot: MediaFile) async throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMediaInfo_\(UUID().uuidString)", isDirectory: true)
        
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        
        let base = baseName(snapshot)
        
        // Write all formats to tmpDir
        await writeFormatsForShare(snapshot: snapshot, base: base, dir: tmpDir)
        
        // Create ZIP
        let zipPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)_mediainfo.zip")
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ), !files.isEmpty else {
            try? FileManager.default.removeItem(at: tmpDir)
            throw ShareError.uploadFailed("No files to upload")
        }
        
        let filePaths = files.map { $0.path(percentEncoded: false) }
        
        // Create zip using /usr/bin/zip
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", zipPath.path(percentEncoded: false)] + filePaths
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            try? process.run()
            process.waitUntilExit()
        }.value
        
        // Clean up tmp dir
        try? FileManager.default.removeItem(at: tmpDir)
        
        defer { try? FileManager.default.removeItem(at: zipPath) }
        
        // Upload to up.sb
        let zipFilePath = zipPath.path(percentEncoded: false)
        _  = "\(base)_mediainfo.zip"
        
        let result = await runCurl(arguments: [
            "-s",
            "https://up.sb",
            "-T", zipFilePath
        ])
        
        // up.sb returns the download URL in the response
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse out the URL from the response
        // up.sb typically returns text with the URL in it
        if let urlLine = trimmed.components(separatedBy: .newlines)
            .first(where: { $0.contains("http") }) {
            // Extract just the URL
            let parts = urlLine.components(separatedBy: .whitespaces)
            if let url = parts.first(where: { $0.hasPrefix("http") }) {
                return url
            }
            return urlLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !trimmed.isEmpty else {
            throw ShareError.uploadFailed("Server returned empty response")
        }
        
        return trimmed
    }
    
    // MARK: - Write all formats for sharing
    
    private func writeFormatsForShare(
        snapshot: MediaFile,
        base: String,
        dir: URL
    ) async {
        let fileURL = snapshot.url
        
        let htmlContent: String
        if let cached = snapshot.rawHTML { htmlContent = cached }
        else { htmlContent = await MediaEngine.fetchHTML(fileURL) }
        
        let xmlContent: String
        if let cached = snapshot.rawXML { xmlContent = cached }
        else { xmlContent = await MediaEngine.fetchXML(fileURL) }
        
        let formats: [(content: String, suffix: String, ext: String)] = [
            (snapshot.rawText     ?? "", "",     "txt"),
            (snapshot.rawTextFull ?? "", "_raw", "txt"),
            (htmlContent,               "",     "html"),
            (xmlContent,                "",     "xml"),
            (snapshot.rawJSON     ?? "", "",     "json"),
            (buildCSVForShare(for: snapshot), "", "csv"),
        ]
        
        for (content, suffix, ext) in formats {
            guard !content.isEmpty else { continue }
            let dest = dir.appendingPathComponent(base + suffix + "." + ext)
            try? content.write(to: dest, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - CSV builder (duplicate of private method for extension access)
    
    private func buildCSVForShare(for file: MediaFile) -> String {
        var lines = ["Track,Field,Value"]
        for track in file.tracks {
            for field in track.fields {
                let escaped = field.value.replacingOccurrences(of: "\"", with: "\"\"")
                lines.append("\"\(track.displayTitle)\",\"\(field.key)\",\"\(escaped)\"")
            }
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private func baseName(_ file: MediaFile) -> String {
        file.url.deletingPathExtension().lastPathComponent
    }
    
    private func runCurl(arguments: [String]) async -> String {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe    = Pipe()
            
            process.executableURL  = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments      = arguments
            process.standardOutput = pipe
            process.standardError  = Pipe()
            
            var env = ProcessInfo.processInfo.environment
            env["LANG"]   = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            process.environment = env
            
            guard (try? process.run()) != nil else { return "" }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            return String(data: data, encoding: .utf8) ?? ""
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
