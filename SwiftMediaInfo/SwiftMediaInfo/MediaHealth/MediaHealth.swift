//
//  MediaHealth.swift
//  SwiftMediaInfo
//
//  Media Health's checks: a short list that answers "is anything wrong with
//  this file?" from what MediaInfo already reported — container, conformance
//  (including a mismatched extension), streams, track IDs, frame rate, HDR
//  metadata, language tags, durations, SHA-256 availability — and the report
//  as text and Markdown. The window is MediaHealthView; Siri AI is handed
//  the same results when asked about a file's health.
//
//  Nothing here reads the file again. Every check works from the parsed tracks
//  (and the checksum state the store already keeps), so a report is instant
//  and can be rebuilt on every redraw as late-arriving data comes in.
//
//  Three outcomes, deliberately:
//    • passed  — checked, and fine.
//    • warning — checked, and worth your attention. Each one explains what it
//                means and what you can do, in the Warnings section.
//    • info    — not a problem and not a pass: the check doesn't apply
//                (no video in a song) or can't be answered yet.
//  Folding "doesn't apply" into "passed" would make a song's report claim its
//  video stream was healthy; folding it into "warning" would cry wolf.
//

import Foundation

// MARK: - Preference

enum HealthPreference {
    /// Settings › Analysis › Include SHA-256 availability.
    static let includeChecksumKey = "healthIncludesChecksum"
    static let includeChecksumDefault = true

    static var includesChecksum: Bool {
        UserDefaults.standard.object(forKey: includeChecksumKey) as? Bool ?? includeChecksumDefault
    }
}

// MARK: - Report

struct HealthCheck: Identifiable {
    enum Status { case passed, warning, info }

    let id: String
    let title: String
    let status: Status
    /// One line, shown beside the check.
    let result: String
    /// For warnings: what it means, and what to do about it.
    var explanation: String? = nil
    var suggestion: String? = nil
}

struct HealthReport {
    let fileName: String
    let checks: [HealthCheck]

    var warnings: [HealthCheck] { checks.filter { $0.status == .warning } }
    var passedCount: Int { checks.filter { $0.status == .passed }.count }

    // MARK: Building

    init(file: MediaFile, includeChecksum: Bool = HealthPreference.includesChecksum) {
        fileName = file.url.lastPathComponent

        let tracks = file.tracks
        let summary = MediaSummary(tracks: tracks, fileURL: file.url)
        let general = tracks.first { $0.type == "General" }
        let videos = tracks.filter { $0.type == "Video" }
        let audios = tracks.filter { $0.type == "Audio" }
        let texts = tracks.filter { $0.type == "Text" }

        var checks: [HealthCheck] = []
        checks.append(Self.container(general))
        checks.append(Self.conformance(general))
        checks.append(Self.videoStream(videos, kind: summary.kind, summary: summary))
        checks.append(Self.audioStream(audios, videos: videos, kind: summary.kind, summary: summary))
        checks.append(Self.trackIDs(tracks))
        checks.append(Self.frameRate(videos.first))
        checks.append(Self.hdr(videos.first, summary: summary))
        checks.append(Self.languages(audios: audios, texts: texts, kind: summary.kind))
        checks.append(Self.durations(general: general, videos: videos, audios: audios))

        // Only where a checksum exists to be had at all: files over 10 GB,
        // the same line FileHasher draws. Below it there is never a digest,
        // so "not available" would be a permanent, meaningless warning.
        if includeChecksum, let size = Self.fileSize(file, general: general), size > FileHasher.sizeThreshold {
            checks.append(Self.checksum(file.hashState))
        }

        self.checks = checks
    }

    // MARK: Checks

    private static func container(_ general: MediaTrack?) -> HealthCheck {
        let title = "Container readable"
        guard let general, let format = general.text("Format_String") ?? general.text("Format") else {
            return HealthCheck(
                id: "container", title: title, status: .warning,
                result: "Format not recognised",
                explanation: "MediaInfo couldn't identify what kind of file this is. It may be damaged, still downloading, or not a media file at all.",
                suggestion: "Try opening it in a player. If it won't play either, get a fresh copy of the file."
            )
        }
        if general.text("IsTruncated") == "Yes" {
            return HealthCheck(
                id: "container", title: title, status: .warning,
                result: "\(format), but cut short",
                explanation: "The file ends before its own header says it should. This usually means an interrupted download or copy, and the end of the file — often the last minutes — is missing.",
                suggestion: "Copy or download the file again and compare the sizes."
            )
        }
        return HealthCheck(id: "container", title: title, status: .passed, result: "\(format), read without errors")
    }

    /// MediaInfo's own conformance notes, plus its check that the extension
    /// matches the contents.
    private static func conformance(_ general: MediaTrack?) -> HealthCheck {
        let title = "Format conformance"
        guard let general else {
            return HealthCheck(id: "conformance", title: title, status: .info, result: "Nothing to check")
        }

        if let expected = general.text("FileExtension_Invalid") {
            let actual = general.text("FileExtension") ?? "this"
            let suggested = expected.split(separator: " ").first.map(String.init) ?? expected
            return HealthCheck(
                id: "conformance", title: title, status: .warning,
                result: "Extension .\(actual) doesn't match the contents",
                explanation: "The file is \(general.text("Format") ?? "a different format") inside, but its name ends in .\(actual). Some apps and devices go by the extension and will refuse to open it, or open it with the wrong player.",
                suggestion: "Rename it to end in .\(suggested). Nothing inside the file needs to change."
            )
        }

        let notes = [general.text("ConformanceErrors"), general.text("ConformanceWarnings")].compactMap { $0 }
        if !notes.isEmpty {
            return HealthCheck(
                id: "conformance", title: title, status: .warning,
                result: "MediaInfo reported problems",
                explanation: "MediaInfo found parts of the file that don't follow its format's specification: \(notes.joined(separator: "; ")).",
                suggestion: "Most players cope with minor issues. If this file misbehaves, remuxing it (for example with MKVToolNix or ffmpeg) usually rewrites it cleanly."
            )
        }
        return HealthCheck(id: "conformance", title: title, status: .passed, result: "No problems reported")
    }

    private static func videoStream(_ videos: [MediaTrack], kind: MediaSummary.Kind, summary: MediaSummary) -> HealthCheck {
        let title = "Video stream"
        if !videos.isEmpty {
            let detail = [summary.video?.format, summary.resolution].compactMap { $0 }.joined(separator: ", ")
            let count = videos.count == 1 ? "1 stream" : "\(videos.count) streams"
            return HealthCheck(id: "video", title: title, status: .passed,
                               result: detail.isEmpty ? count : "\(count) — \(detail)")
        }
        switch kind {
        case .audio:
            return HealthCheck(id: "video", title: title, status: .info, result: "None — an audio file doesn't need one")
        case .image:
            return HealthCheck(id: "video", title: title, status: .info, result: "Not applicable to images")
        default:
            return HealthCheck(
                id: "video", title: title, status: .warning, result: "No video or audio found",
                explanation: "MediaInfo found no video, audio or image stream in this file, so there is nothing in it to play.",
                suggestion: "Check that this is the file you meant to open. If it should contain video, it may be damaged or incomplete."
            )
        }
    }

    private static func audioStream(_ audios: [MediaTrack], videos: [MediaTrack], kind: MediaSummary.Kind, summary: MediaSummary) -> HealthCheck {
        let title = "Audio stream"
        if !audios.isEmpty {
            let main = summary.mainAudio.flatMap { MediaSummary.audioChip($0) }
            let count = audios.count == 1 ? "1 stream" : "\(audios.count) streams"
            return HealthCheck(id: "audio", title: title, status: .passed,
                               result: main.map { "\(count) — main is \($0)" } ?? count)
        }
        if kind == .image {
            return HealthCheck(id: "audio", title: title, status: .info, result: "Not applicable to images")
        }
        if !videos.isEmpty {
            return HealthCheck(
                id: "audio", title: title, status: .warning, result: "Video with no sound",
                explanation: "This file has a video stream but no audio at all. That's expected for screen recordings, B-roll or GIF-style clips — otherwise the sound was lost when the file was made.",
                suggestion: "If it should have sound, export or download it again with audio included."
            )
        }
        return HealthCheck(id: "audio", title: title, status: .info, result: "None found")
    }

    private static func trackIDs(_ tracks: [MediaTrack]) -> HealthCheck {
        let title = "Unique track IDs"
        let streams = tracks.filter { $0.type != "General" && $0.type != "Menu" }
        let ids = streams.compactMap { track in track.text("ID").map { (id: $0, name: track.displayName) } }

        guard !ids.isEmpty else {
            return HealthCheck(id: "ids", title: title, status: .info, result: "This format doesn't number its tracks")
        }

        let grouped = Dictionary(grouping: ids, by: \.id).filter { $0.value.count > 1 }
        guard grouped.isEmpty else {
            let clashes = grouped.keys.sorted().map { id in
                "ID \(id): " + (grouped[id] ?? []).map(\.name).joined(separator: ", ")
            }
            return HealthCheck(
                id: "ids", title: title, status: .warning,
                result: grouped.count == 1 ? "1 ID is used twice" : "\(grouped.count) IDs are used more than once",
                explanation: "Two or more tracks share an ID (\(clashes.joined(separator: "; "))). Players and editing tools pick tracks by ID, so they may play the wrong track or skip one.",
                suggestion: "Remuxing the file (MKVToolNix, ffmpeg) renumbers the tracks."
            )
        }
        return HealthCheck(id: "ids", title: title, status: .passed,
                           result: ids.count == 1 ? "Only one track" : "\(Self.all(ids.count, "tracks")) have their own ID")
    }

    private static func frameRate(_ video: MediaTrack?) -> HealthCheck {
        let title = "Frame rate"
        guard let video else {
            return HealthCheck(id: "vfr", title: title, status: .info, result: "No video")
        }
        let rate = video.text("FrameRate").flatMap(Double.init).map { String(format: "%g fps", $0) }
        switch video.text("FrameRate_Mode") {
        case "VFR":
            return HealthCheck(
                id: "vfr", title: title, status: .warning,
                result: ["Variable", rate.map { "around \($0)" }].compactMap { $0 }.joined(separator: ", "),
                explanation: "Frames aren't evenly spaced in time — typical of phone and screen recordings. Players handle it fine, but editors such as Premiere Pro, Final Cut and DaVinci Resolve can drift out of sync with the audio over a long clip.",
                suggestion: "Before editing, convert it to a constant frame rate (HandBrake's \"Constant Framerate\" option does this)."
            )
        case "CFR":
            return HealthCheck(id: "vfr", title: title, status: .passed,
                               result: ["Constant", rate].compactMap { $0 }.joined(separator: ", "))
        default:
            return HealthCheck(id: "vfr", title: title, status: .info,
                               result: rate.map { "\($0), mode not reported" } ?? "Not reported")
        }
    }

    private static func hdr(_ video: MediaTrack?, summary: MediaSummary) -> HealthCheck {
        let title = "HDR metadata"
        guard let video else {
            return HealthCheck(id: "hdr", title: title, status: .info, result: "No video")
        }

        let transfer = video.text("transfer_characteristics") ?? ""
        let hdrFormat = video.text("HDR_Format")
        let isPQ = transfer.contains("PQ")
        let isHLG = transfer.contains("HLG")

        if let description = summary.video?.hdr, hdrFormat != nil {
            // HDR10 relies on its static metadata; Dolby Vision and HDR10+
            // carry their own dynamic metadata, so only plain HDR10 is held
            // to having the mastering display described.
            let isPlainHDR10 = hdrFormat?.contains("2086") == true && hdrFormat?.contains("/") == false
            if isPlainHDR10 && video.text("MasteringDisplay_Luminance") == nil {
                return HealthCheck(
                    id: "hdr", title: title, status: .warning, result: "HDR10 without mastering details",
                    explanation: "The stream is flagged HDR10 but doesn't say how bright the mastering display was. TVs use that to map the picture to their own brightness, so highlights may clip or look dim.",
                    suggestion: "Usually only fixable by re-encoding with the mastering display values set."
                )
            }
            return HealthCheck(id: "hdr", title: title, status: .passed, result: description)
        }
        if isPQ {
            return HealthCheck(
                id: "hdr", title: title, status: .warning, result: "HDR (PQ) without HDR metadata",
                explanation: "The video uses the PQ curve that HDR10 is built on, but carries none of the metadata that tells a display how to show it. Many TVs will fall back to a guess, often too dark or washed out.",
                suggestion: "If you encoded this yourself, re-encode with HDR10 metadata (mastering display and MaxCLL/MaxFALL)."
            )
        }
        if isHLG {
            return HealthCheck(id: "hdr", title: title, status: .passed, result: "HLG — needs no extra metadata")
        }
        return HealthCheck(id: "hdr", title: title, status: .passed, result: "SDR — none needed")
    }

    private static func languages(audios: [MediaTrack], texts: [MediaTrack], kind: MediaSummary.Kind) -> HealthCheck {
        let title = "Language tags"
        let tracks = audios + texts
        guard !tracks.isEmpty else {
            return HealthCheck(id: "lang", title: title, status: .info, result: "No audio or subtitle tracks")
        }
        let missing = tracks.filter { track in
            guard let code = track.text("Language") else { return true }
            return code == "und"
        }
        guard !missing.isEmpty else {
            return HealthCheck(id: "lang", title: title, status: .passed,
                               result: tracks.count == 1 ? "Tagged" : "\(Self.all(tracks.count, "tracks")) tagged")
        }
        // A song or podcast with one untagged track is the norm, not a fault.
        if kind == .audio && texts.isEmpty {
            return HealthCheck(id: "lang", title: title, status: .info, result: "Not tagged — usual for music and podcasts")
        }
        let names = missing.prefix(6).map(\.displayName).joined(separator: ", ")
            + (missing.count > 6 ? ", and \(missing.count - 6) more" : "")
        return HealthCheck(
            id: "lang", title: title, status: .warning,
            result: "\(missing.count) of \(tracks.count) tracks untagged",
            explanation: "\(names) \(missing.count == 1 ? "has" : "have") no language set. Players use the language to pick audio and subtitles automatically, and show it in their track menus — untagged tracks appear as \"Unknown\".",
            suggestion: "Set the language in MKVToolNix's header editor (no re-encode needed), or with ffmpeg's -metadata:s option."
        )
    }

    /// Video and audio should run the same length. Subtitles are left out:
    /// they end with their last line, which is normally well before the film.
    private static func durations(general: MediaTrack?, videos: [MediaTrack], audios: [MediaTrack]) -> HealthCheck {
        let title = "Duration consistency"
        let streams = (videos + audios).compactMap { track in track.seconds.map { (track: track, seconds: $0) } }
        guard let reference = streams.first(where: { $0.track.type == "Video" }) ?? streams.first ?? general?.seconds.map({ (track: general!, seconds: $0) }),
              streams.count > 1 else {
            return HealthCheck(id: "duration", title: title, status: .info,
                               result: streams.isEmpty ? "No durations reported" : "Only one stream — nothing to compare")
        }

        // A second, or a thousandth of the running time on long files. Small
        // differences are normal: an audio frame ends a few milliseconds
        // after the last video frame.
        let tolerance = max(1.0, reference.seconds * 0.001)
        let off = streams.filter { $0.track.id != reference.track.id && abs($0.seconds - reference.seconds) > tolerance }

        guard !off.isEmpty else {
            let spread = (streams.map(\.seconds).max() ?? 0) - (streams.map(\.seconds).min() ?? 0)
            return HealthCheck(id: "duration", title: title, status: .passed,
                               result: "\(Self.all(streams.count, "streams")) within \(Self.seconds(spread)) of each other")
        }

        let details = off.prefix(4).map { item -> String in
            let delta = item.seconds - reference.seconds
            return "\(item.track.displayName) is \(Self.seconds(abs(delta))) \(delta < 0 ? "shorter" : "longer")"
        }.joined(separator: "; ")

        return HealthCheck(
            id: "duration", title: title, status: .warning,
            result: off.count == 1 ? "1 stream differs" : "\(off.count) streams differ",
            explanation: "Compared with \(reference.track.displayName) (\(Self.clock(reference.seconds))): \(details). A short audio track can mean a cut-off ending; a long one can mean the two were joined from different sources and may drift out of sync.",
            suggestion: "Play the end of the file to check. If it is out of sync, a fresh copy or re-mux usually fixes it."
        )
    }

    private static func checksum(_ state: HashState) -> HealthCheck {
        let title = "SHA-256 checksum"
        switch state {
        case .ready(let digest):
            return HealthCheck(id: "sha", title: title, status: .passed, result: "Available — \(digest.prefix(12))…")
        case .hashing(let progress):
            return HealthCheck(id: "sha", title: title, status: .info, result: "Calculating… \(Int(progress * 100))%")
        case .awaitingRequest, .cancelled:
            return HealthCheck(id: "sha", title: title, status: .info, result: "Not calculated yet — available on request")
        case .failed(let reason):
            return HealthCheck(
                id: "sha", title: title, status: .warning, result: "Couldn't be calculated",
                explanation: "Reading the whole file to compute its checksum failed: \(reason). A read error part-way through a file can be an early sign of a failing drive or a damaged copy.",
                suggestion: "Try again from Easy View. If it fails at the same point, copy the file to another drive and check it there."
            )
        case .notApplicable:
            return HealthCheck(id: "sha", title: title, status: .info, result: "Checksums are off in Settings › Analysis")
        }
    }

    // MARK: Helpers

    private static func fileSize(_ file: MediaFile, general: MediaTrack?) -> Int64? {
        if let size = general?.text("FileSize").flatMap({ Int64($0) }) { return size }
        let values = try? file.url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    /// "Both tracks", "All 5 tracks".
    private static func all(_ count: Int, _ noun: String) -> String {
        count == 2 ? "Both \(noun)" : "All \(count) \(noun)"
    }
    
    private static func seconds(_ value: Double) -> String {
        value < 1 ? String(format: "%.2f s", value) : String(format: "%.1f s", value)
    }

    private static func clock(_ value: Double) -> String {
        let total = Int(value.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: Export

    private func symbol(_ status: HealthCheck.Status) -> String {
        switch status {
        case .passed:  return "✓"
        case .warning: return "⚠"
        case .info:    return "–"
        }
    }

    var verdict: String {
        switch warnings.count {
        case 0:  return "No problems found"
        case 1:  return "1 warning"
        default: return "\(warnings.count) warnings"
        }
    }

    var plainText: String {
        var lines = ["Media Health — \(fileName)", verdict, ""]
        let widest = checks.map(\.title.count).max() ?? 0
        for check in checks {
            let pad = String(repeating: " ", count: max(0, widest - check.title.count))
            lines.append("\(symbol(check.status)) \(check.title)\(pad)  \(check.result)")
        }
        for warning in warnings {
            lines.append("")
            lines.append("⚠ \(warning.title): \(warning.result)")
            if let explanation = warning.explanation { lines.append(explanation) }
            if let suggestion = warning.suggestion { lines.append("What to do: \(suggestion)") }
        }
        return lines.joined(separator: "\n")
    }

    var markdown: String {
        var parts = [
            MarkdownBuilder.heading("Media Health — \(fileName)", level: 2),
            "**\(verdict)**",
            MarkdownBuilder.table(
                rows: checks.map { ("\(symbol($0.status)) \($0.title)", $0.result) },
                headers: ("Check", "Result")
            )
        ]
        if !warnings.isEmpty {
            parts.append(MarkdownBuilder.heading("Warnings", level: 3))
            for warning in warnings {
                var item = "- **\(MarkdownBuilder.inline(warning.title))** — \(MarkdownBuilder.inline(warning.result))"
                if let explanation = warning.explanation { item += "\n  \(MarkdownBuilder.inline(explanation))" }
                if let suggestion = warning.suggestion { item += "\n  *What to do:* \(MarkdownBuilder.inline(suggestion))" }
                parts.append(item)
            }
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Track helpers

private extension MediaTrack {
    func text(_ key: String) -> String? {
        guard let value = value(for: key)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    /// "Audio #2", "Subtitle #3" — the way the checks name a track.
    var displayName: String {
        let kind = type == "Text" ? "Subtitle" : type
        return "\(kind) #\(streamIndex + 1)"
    }
}
