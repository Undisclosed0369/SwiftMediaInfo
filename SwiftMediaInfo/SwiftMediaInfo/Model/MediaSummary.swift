//
//  MediaSummary.swift
//  SwiftMediaInfo
//
//  One readable summary of a file, built from its tracks: the Overview card
//  at the top of Easy View (OverviewCard) and its copy actions, the
//  Markdown and PDF reports (ReportDocument), Media Health, Siri AI's
//  "overview" answers, and the preview's file details and main audio track.
//
//  Keeping the decisions in one place — which audio track counts as the main
//  one, how formats are named, what makes a file "HDR" — means every surface
//  gives the same answer about the same file.
//

import Foundation

struct MediaSummary {

    enum Kind {
        case video, audio, image, other

        var symbol: String {
            switch self {
            case .video: return "film"
            case .audio: return "waveform"
            case .image: return "photo"
            case .other: return "doc.text.magnifyingglass"
            }
        }
    }

    /// One line of the summary. `glossaryKey` is the MediaInfo field the value
    /// came from, used only to find a tooltip — it is never shown or copied.
    struct Row: Identifiable {
        let label: String
        let value: String
        var glossaryKey: String? = nil
        /// For a list value, its entries — so a long list can be shown
        /// shortened while copies still carry all of it.
        var items: [String]? = nil
        var id: String { label }
    }

    struct Section: Identifiable {
        let title: String
        let symbol: String
        /// The track type whose colour the section borrows.
        let trackType: String
        let rows: [Row]
        var id: String { title }
    }

    /// A group of header chips sharing one track colour.
    struct ChipGroup: Identifiable {
        let trackType: String
        let chips: [String]
        var id: String { trackType }
    }

    struct Video {
        var format: String?
        var profile: String?
        var level: String?
        var tier: String?
        var width: Int?
        var height: Int?
        var frameRate: String?
        var frameRateMode: String?
        var bitRate: String?
        var bitDepth: Int?
        var colorSpace: String?
        var chroma: String?
        var primaries: String?
        var hdr: String?
        var hdrShort: String?
    }

    struct Audio {
        var language: String?
        var title: String?
        var format: String?
        var commercial: String?
        var channelCount: Int?
        var hasLFE = false
        var samplingRate: String?
        var bitDepth: Int?
        var bitRate: String?
        var compression: String?
        var isDefault = false
    }

    struct Subtitle {
        var language: String?
        var title: String?
        var format: String?
        var isDefault = false
        var isForced = false
    }

    struct Picture {
        var format: String?
        var width: Int?
        var height: Int?
        var colorSpace: String?
        var chroma: String?
        var bitDepth: Int?
    }

    // MARK: Contents

    let kind: Kind
    let fileName: String
    let fileSize: String?
    let container: String?
    let duration: String?
    let tags: [Row]
    let video: Video?
    let audio: [Audio]
    let subtitles: [Subtitle]
    let picture: Picture?

    /// The track a player starts with: the one flagged Default, otherwise the
    /// first.
    var mainAudio: Audio? {
        audio.first(where: \.isDefault) ?? audio.first
    }

    /// Default first, then a forced track — that is the one shown without the
    /// viewer choosing anything — then simply the first.
    var mainSubtitle: Subtitle? {
        subtitles.first(where: \.isDefault)
        ?? subtitles.first(where: \.isForced)
        ?? subtitles.first
    }

    // MARK: Building

    init(tracks: [MediaTrack], fileURL: URL) {
        let general = tracks.first { $0.type == "General" }

        fileName = fileURL.lastPathComponent
        fileSize = general?.text("FileSize_String")
        container = general?.text("Format_String", fallback: "Format")
        duration = general?.text("Duration_String")

        tags = [("Title", "Title"), ("Performer", "Artist"), ("Album", "Album"),
                ("Recorded_Date", "Year"), ("Genre", "Genre")]
            .compactMap { key, label in
                guard let value = general?.text(key) else { return nil }
                return Row(label: label, value: value, glossaryKey: key)
            }

        video = tracks.first { $0.type == "Video" }.map { Self.makeVideo($0) }
        audio = tracks.filter { $0.type == "Audio" }.map { Self.makeAudio($0) }
        subtitles = tracks.filter { $0.type == "Text" }.map { Self.makeSubtitle($0) }
        picture = tracks.first { $0.type == "Image" }.map { Self.makePicture($0) }

        if video != nil { kind = .video }
        else if !audio.isEmpty { kind = .audio }
        else if picture != nil { kind = .image }
        else { kind = .other }
    }

    private static func makeVideo(_ track: MediaTrack) -> Video {
        var video = Video()
        video.format = track.text("Format")
        video.profile = track.text("Format_Profile")
        video.level = track.text("Format_Level")
        video.tier = track.text("Format_Tier")
        video.width = track.int("Width")
        video.height = track.int("Height")
        if let rate = track.text("FrameRate").flatMap(Double.init) {
            video.frameRate = trimmedNumber(rate, decimals: 3) + " fps"
        }
        video.frameRateMode = track.text("FrameRate_Mode_String")?.lowercased()
        video.bitRate = track.text("BitRate_String") ?? track.text("BitRate_Nominal_String")
        video.bitDepth = track.int("BitDepth")
        video.colorSpace = track.text("ColorSpace")
        video.chroma = track.text("ChromaSubsampling")
        video.primaries = track.text("colour_primaries")
        video.hdr = HDRDescription.full(for: track)
        video.hdrShort = HDRDescription.short(for: track)
        if video.hdr == nil, let short = video.hdrShort {
            // PQ or HLG with no HDR metadata is still HDR — named by its curve.
            video.hdr = short == "PQ" ? "PQ, no HDR metadata" : short
        }
        return video
    }

    private static func makeAudio(_ track: MediaTrack) -> Audio {
        var audio = Audio()
        audio.language = language(of: track)
        audio.title = track.text("Title")
        audio.format = track.text("Format_String", fallback: "Format")
        audio.commercial = track.text("Format_Commercial_IfAny")
        audio.channelCount = track.int("Channels") ?? track.int("Channel_s_")
        let positions = (track.text("ChannelLayout") ?? "") + (track.text("ChannelPositions") ?? "")
        audio.hasLFE = positions.contains("LFE")
        if let rate = track.text("SamplingRate_String") ?? track.text("SamplingRate") {
            audio.samplingRate = FieldFormat.kilohertz(rate)
        }
        audio.bitDepth = track.int("BitDepth")
        audio.bitRate = track.text("BitRate_String") ?? track.text("BitRate_Maximum_String")
        audio.compression = track.text("Compression_Mode_String", fallback: "Compression_Mode")
        audio.isDefault = track.text("Default") == "Yes"
        return audio
    }

    private static func makeSubtitle(_ track: MediaTrack) -> Subtitle {
        var subtitle = Subtitle()
        subtitle.language = language(of: track)
        subtitle.title = track.text("Title")
        subtitle.format = subtitleFormat(track)
        subtitle.isDefault = track.text("Default") == "Yes"
        subtitle.isForced = track.text("Forced") == "Yes"
        return subtitle
    }

    private static func makePicture(_ track: MediaTrack) -> Picture {
        var picture = Picture()
        picture.format = track.text("Format_String", fallback: "Format")
        picture.width = track.int("Width")
        picture.height = track.int("Height")
        picture.colorSpace = track.text("ColorSpace")
        picture.chroma = track.text("ChromaSubsampling")
        picture.bitDepth = track.int("BitDepth")
        return picture
    }

    /// The spelled-out language, ignoring MediaInfo's "zxx" — "No linguistic
    /// content or not applicable" says nothing useful in a summary.
    private static func language(of track: MediaTrack) -> String? {
        guard let code = track.text("Language"), code != "zxx", code != "und" else { return nil }
        return track.text("Language_String") ?? code
    }

    /// The name people use for a subtitle format. MediaInfo calls a Matroska
    /// SubRip track "UTF-8", which is its character set, not its format.
    private static func subtitleFormat(_ track: MediaTrack) -> String? {
        let format = track.text("Format")
        let codec = track.text("CodecID") ?? ""
        if codec == "S_TEXT/UTF8" || format == "UTF-8" { return "SRT" }
        if codec == "S_TEXT/ASS" || format == "ASS" { return "ASS" }
        if codec == "S_TEXT/SSA" || format == "SSA" { return "SSA" }
        if codec == "S_TEXT/WEBVTT" || format == "WebVTT" { return "WebVTT" }
        if codec == "tx3g" || format == "Timed Text" { return "Timed Text" }
        if format == "RLE" || codec.contains("VOBSUB") { return "VobSub" }
        return format
    }

    fileprivate static func trimmedNumber(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: Lines
    //
    // Each line combines what belongs together, so the overview reads like a
    // spec sheet rather than a form: "HEVC, Main 10@L6.1@Main", not three rows.

    var videoCodecLine: String? {
        guard let video, let format = video.format else { return nil }
        guard let profile = video.profile else { return format }
        // MediaInfo's own notation, the one people recognise from its Text
        // output and from release notes.
        var spec = profile
        if let level = video.level { spec += "@L\(level)" }
        if let tier = video.tier { spec += "@\(tier)" }
        return "\(format), \(spec)"
    }

    var resolution: String? {
        guard let width = video?.width ?? picture?.width,
              let height = video?.height ?? picture?.height else { return nil }
        return "\(width) × \(height)"
    }

    var frameRateLine: String? {
        guard let rate = video?.frameRate else { return nil }
        return [rate, video?.frameRateMode].compactMap { $0 }.joined(separator: ", ")
    }

    var videoBitRateLine: String? {
        let depth = video?.bitDepth.map { "\($0)-bit" }
        let parts = [video?.bitRate, depth].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var colorLine: String? {
        guard let video else { return nil }
        let space = [video.colorSpace, video.chroma].compactMap { $0 }.joined(separator: " ")
        let parts = [video.hdr, video.primaries, space.isEmpty ? nil : space].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "Dolby Digital Plus (E-AC-3)" — the commercial name first, since it is
    /// the one on the box, with the technical one for anyone matching specs.
    static func audioFormat(_ audio: Audio) -> String? {
        guard let format = audio.format else { return audio.commercial }
        guard let commercial = audio.commercial,
              !format.localizedCaseInsensitiveContains(commercial),
              !commercial.localizedCaseInsensitiveContains(format) else { return format }
        return "\(commercial) (\(format))"
    }

    /// "Dolby TrueHD Atmos", "DTS-HD MA", "AAC LC" — short enough for a chip.
    static func audioChip(_ audio: Audio) -> String? {
        guard var name = audio.commercial ?? audio.format else { return nil }
        name = name.replacingOccurrences(of: " with Dolby Atmos", with: " Atmos")
        name = name.replacingOccurrences(of: "DTS-HD Master Audio", with: "DTS-HD MA")
        name = name.replacingOccurrences(of: "DTS-HD High Resolution Audio", with: "DTS-HD HRA")
        return name
    }

    /// "2.0 (Stereo)", "1.0 (Mono)", "5.1", "7.1".
    static func channelLine(_ audio: Audio) -> String? {
        guard let count = audio.channelCount else { return nil }
        switch (count, audio.hasLFE) {
        case (1, _): return "1.0 (Mono)"
        case (2, false): return "2.0 (Stereo)"
        case (_, true): return "\(count - 1).1"
        default: return "\(count).0"
        }
    }

    static func channelChip(_ audio: Audio) -> String? {
        switch audio.channelCount {
        case 1: return "Mono"
        case 2 where !audio.hasLFE: return "Stereo"
        default: return channelLine(audio)
        }
    }

    /// "24-bit / 48 kHz", or just the rate for lossy codecs that have no real
    /// bit depth.
    static func sampleLine(_ audio: Audio) -> String? {
        let depth = audio.bitDepth.map { "\($0)-bit" }
        let parts = [depth, audio.samplingRate].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    /// Every subtitle track by name, with its format: "English (PGS)",
    /// "English (SDH) (PGS)", "Chinese (Simplified) (SRT)".
    ///
    /// The title names a track best — it is where "SDH", "Forced" and
    /// "Commentary" live — so it is used when there is one, and the language
    /// otherwise. A track with neither is counted at the end rather than
    /// listed as "Unknown". Nil when no track has either, since the track
    /// count already says everything there is to say.
    var subtitleList: [String]? {
        var items: [String] = []
        var unnamed = 0
        for subtitle in subtitles {
            guard let name = subtitle.title ?? subtitle.language else {
                unnamed += 1
                continue
            }
            items.append(subtitle.format.map { "\(name) (\($0))" } ?? name)
        }
        guard !items.isEmpty else { return nil }
        if unnamed > 0 { items.append("\(unnamed) untagged") }
        return items
    }
    
    /// "1 SRT, 1 PGS" in the order the tracks appear.
    var subtitleFormatsLine: String? {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for subtitle in subtitles {
            let format = subtitle.format ?? "Unknown"
            if counts[format] == nil { order.append(format) }
            counts[format, default: 0] += 1
        }
        guard !order.isEmpty else { return nil }
        return order.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
    }

    var megapixels: String? {
        guard let width = picture?.width, let height = picture?.height else { return nil }
        return Self.trimmedNumber(Double(width * height) / 1_000_000, decimals: 1) + " MP"
    }

    /// "4K", "1080p" — judged on width as well as height, so a 3840 × 1608
    /// scope film still counts as 4K.
    var resolutionClass: String? {
        guard let width = video?.width, let height = video?.height else { return nil }
        switch (width, height) {
        case let (w, h) where w >= 7680 || h >= 4320: return "8K"
        case let (w, h) where w >= 3840 || h >= 2160: return "4K"
        case let (w, h) where w >= 2560 || h >= 1440: return "1440p"
        case let (w, h) where w >= 1920 || h >= 1080: return "1080p"
        case let (w, h) where w >= 1280 || h >= 720:  return "720p"
        default: return "SD"
        }
    }

    // MARK: Header

    /// Size, duration and container, under the file name.
    var fileDetails: [String] {
        [fileSize, kind == .image ? nil : duration, container].compactMap { $0 }
    }

    /// The header chips, one colour per track kind — the facts people check
    /// first, readable even while the card is folded.
    var chipGroups: [ChipGroup] {
        var groups: [ChipGroup] = []

        if let video {
            let chips = [resolutionClass, video.format, video.hdrShort].compactMap { $0 }
            if !chips.isEmpty { groups.append(ChipGroup(trackType: "Video", chips: chips)) }
        }

        if let main = mainAudio {
            var chips = [Self.audioChip(main), Self.channelChip(main)].compactMap { $0 }
            if kind == .audio {
                if let rate = main.samplingRate {
                    chips.append([main.bitDepth.map { "\($0)-bit" }, rate].compactMap { $0 }.joined(separator: " / "))
                }
                if main.compression == "Lossless" { chips.append("Lossless") }
            } else if let language = main.language {
                chips.append(language)
            }
            groups.append(ChipGroup(trackType: "Audio", chips: chips))
        }

        if let main = mainSubtitle {
            let chips = [main.language, main.format].compactMap { $0 }
            if !chips.isEmpty { groups.append(ChipGroup(trackType: "Text", chips: chips)) }
        }

        if kind == .image, let picture {
            let chips = [picture.format, megapixels].compactMap { $0 }
            groups.append(ChipGroup(trackType: "Image", chips: chips))
        }

        return groups
    }

    // MARK: Sections

    /// Everything the overview shows. The File section comes first; the card
    /// shows it as its header rather than as a block, and the copy actions
    /// include it as a section of its own.
    var sections: [Section] {
        var result: [Section] = []

        var file: [Row] = [Row(label: "Name", value: fileName, glossaryKey: "FileName")]
        file.append(optional: "Size", fileSize, key: "FileSize")
        file.append(optional: "Duration", kind == .image ? nil : duration, key: "Duration")
        file.append(optional: "Format", container, key: "Format")
        result.append(Section(title: "File", symbol: "doc", trackType: "General", rows: file))

        if video != nil {
            var rows: [Row] = []
            rows.append(optional: "Codec", videoCodecLine, key: "Format_Profile")
            rows.append(optional: "Resolution", resolution, key: "Width")
            rows.append(optional: "Frame Rate", frameRateLine, key: "FrameRate_Mode")
            rows.append(optional: "Bit Rate", videoBitRateLine, key: "BitRate")
            rows.append(optional: "Color", colorLine, key: "HDR_Format")
            result.append(Section(title: "Video", symbol: "film", trackType: "Video", rows: rows))
        }

        if let main = mainAudio {
            var rows: [Row] = []
            if kind == .video || main.language != nil {
                rows.append(Row(label: "Language", value: main.language ?? "Not specified", glossaryKey: "Language"))
            }
            rows.append(optional: "Codec", Self.audioFormat(main), key: "Format")
            rows.append(optional: "Channels", Self.channelLine(main), key: "Channels")
            rows.append(optional: "Sampling", Self.sampleLine(main), key: "SamplingRate")
            rows.append(optional: "Bit Rate", main.bitRate, key: "BitRate")
            if kind == .audio {
                rows.append(optional: "Compression", main.compression, key: "Compression_Mode")
            }
            if kind == .video || audio.count > 1 {
                rows.append(Row(label: "Tracks", value: "\(audio.count)"))
            }
            result.append(Section(title: audio.count > 1 ? "Main Audio" : "Audio", symbol: "waveform", trackType: "Audio", rows: rows))
        }

        if kind == .video || !subtitles.isEmpty {
            var rows: [Row] = []
            if let main = mainSubtitle {
                rows.append(Row(label: "Tracks", value: "\(subtitles.count)"))
                rows.append(Row(label: "Main Language", value: main.language ?? "Not specified", glossaryKey: "Language"))
                if let list = subtitleList {
                    rows.append(Row(label: list.count == 1 ? "Language" : "Languages",
                                    value: list.joined(separator: ", "),
                                    glossaryKey: "Language", items: list))
                }
                rows.append(optional: "Formats", subtitleFormatsLine, key: "Format")
            } else {
                rows.append(Row(label: "Tracks", value: "None"))
            }
            result.append(Section(title: "Subtitles", symbol: "captions.bubble", trackType: "Text", rows: rows))
        }

        if let picture, kind == .image {
            var rows: [Row] = []
            rows.append(optional: "Format", picture.format, key: "Format")
            rows.append(optional: "Resolution", [resolution, megapixels].compactMap { $0 }.joined(separator: ", "), key: "Width")
            rows.append(optional: "Color", [picture.colorSpace, picture.chroma].compactMap { $0 }.joined(separator: " "), key: "ColorSpace")
            rows.append(optional: "Bit Depth", picture.bitDepth.map { "\($0)-bit" }, key: "BitDepth")
            result.append(Section(title: "Image", symbol: "photo", trackType: "Image", rows: rows))
        }

        if kind == .audio, !tags.isEmpty {
            result.append(Section(title: "Tags", symbol: "tag", trackType: "Menu", rows: tags))
        }

        return result
    }

    // MARK: Export

    var markdown: String {
        var parts = [MarkdownBuilder.heading(fileName, level: 2)]
        for section in sections {
            parts.append(MarkdownBuilder.section(section.title, rows: section.rows.map { ($0.label, $0.value) }))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    var plainText: String {
        sections
            .map { MarkdownBuilder.plainSection($0.title, rows: $0.rows.map { ($0.label, $0.value) }) }
            .joined(separator: "\n\n")
    }
}

// MARK: - Helpers

private extension MediaTrack {
    /// A non-empty value for `key`, or for `fallback` when it is missing.
    func text(_ key: String, fallback: String? = nil) -> String? {
        if let value = value(for: key)?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
            return value
        }
        guard let fallback,
              let raw = value(for: fallback)?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        return FieldFormat.formatRaw(key: fallback, value: raw)
    }

    func int(_ key: String) -> Int? {
        text(key).flatMap { Int($0) }
    }
}

private extension Array where Element == MediaSummary.Row {
    mutating func append(optional label: String, _ value: String?, key: String? = nil) {
        guard let value, !value.isEmpty else { return }
        append(MediaSummary.Row(label: label, value: value, glossaryKey: key))
    }
}
