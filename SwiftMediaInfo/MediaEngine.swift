//
//  MediaEngine.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  MediaEngine.swift
//  MediaInfoMac
//

import Foundation

final class MediaEngine {

    // MARK: - Binary path

    static var binaryPath: String {
        for candidate in [
            "/opt/homebrew/bin/mediainfo",
            "/usr/local/bin/mediainfo",
            "/usr/bin/mediainfo"
        ] {
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return "mediainfo"
    }

    // MARK: - Public API

    static func analyse(_ url: URL) async -> MediaFile {
        var file = MediaFile(url: url)

        async let jsonStr = run(path: url.path, args: ["--Output=JSON", "--Full"])
        async let textStr = run(path: url.path, args: ["--Output=TEXT", "--Full"])
        async let htmlStr = run(path: url.path, args: ["--Output=HTML"])
        async let xmlStr  = run(path: url.path, args: ["--Output=XML",  "--Full"])

        let (json, text, html, xml) = await (jsonStr, textStr, htmlStr, xmlStr)

        file.rawJSON = json
        file.rawText = text
        file.rawHTML = html
        file.rawXML  = xml
        file.tracks  = parseTracks(from: json)
        file.isLoading = false
        return file
    }

    // MARK: - Parser

    static func parseTracks(from jsonString: String) -> [MediaTrack] {
        guard
            let data       = jsonString.data(using: .utf8),
            let root       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let media      = root["media"] as? [String: Any],
            let trackArray = media["track"] as? [[String: Any]]
        else { return [] }

        var typeCounters: [String: Int] = [:]
        var result: [MediaTrack] = []

        for trackDict in trackArray {
            let type  = (trackDict["@type"] as? String) ?? "Unknown"
            let index = typeCounters[type] ?? 0
            typeCounters[type] = index + 1

            let sortedKeys = trackDict.keys
                .filter { !$0.hasPrefix("@") }
                .sorted { priorityOrder($0) < priorityOrder($1) }

            var fields: [(key: String, value: String)] = []
            for key in sortedKeys {
                if let val = trackDict[key] {
                    let strVal: String
                    if let s = val as? String        { strVal = s }
                    else if let n = val as? NSNumber { strVal = n.stringValue }
                    else                             { strVal = "\(val)" }
                    if !strVal.isEmpty { fields.append((key: key, value: strVal)) }
                }
            }
            result.append(MediaTrack(type: type, streamIndex: index, fields: fields))
        }
        return result
    }

    // MARK: - Process runner

    static func run(path: String, args: [String]) async -> String {
        await Task.detached(priority: .userInitiated) {
            let p    = Process()
            let pipe = Pipe()
            p.executableURL  = await URL(fileURLWithPath: binaryPath)
            p.arguments      = args + [path]
            p.standardOutput = pipe
            p.standardError  = Pipe()
            guard (try? p.run()) != nil else { return "" }
            p.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8) ?? ""
        }.value
    }

    // MARK: - Field ordering

    private static let knownPriority: [String] = [
        "Format", "Format_Profile", "Format_Version", "Format_Commercial_IfAny",
        "Duration", "Duration/String", "FileSize", "OverallBitRate",
        "Width", "Height", "DisplayAspectRatio", "FrameRate",
        "BitRate", "BitRate_Mode", "Channels", "SamplingRate",
        "ColorSpace", "ChromaSubsampling", "BitDepth", "ScanType",
        "Encoded_Date", "Tagged_Date", "Writing_Application", "Writing_Library"
    ]

    private static func priorityOrder(_ key: String) -> Int {
        knownPriority.firstIndex(of: key) ?? (knownPriority.count + key.hashValue)
    }
}
