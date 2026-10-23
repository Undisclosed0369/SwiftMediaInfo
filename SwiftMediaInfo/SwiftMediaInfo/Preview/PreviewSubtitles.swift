//
//  PreviewSubtitles.swift
//  SwiftMediaInfo
//
//  The file's own subtitles in the preview.
//
//  Text subtitles (SRT, ASS, WebVTT…) are copied into each clip as the text
//  tracks macOS's player shows, in its own subtitles menu as well as in the
//  window's Subtitles menu.
//
//  Picture subtitles — PGS from Blu-ray, VobSub from DVD, DVB — are images,
//  which macOS's player can't show at all. For the track chosen, ffmpeg turns
//  the clip's stretch of it into a picture for each change of subtitle, and
//  the preview draws those over the video at the right moments, exactly as
//  they look on the disc, in full screen too.
//
//  When a file has subtitles, its default track is shown — or its first, if
//  none is marked default — until a different choice is made, which is then
//  kept for that file. A file without subtitles keeps the behaviour it had:
//  macOS's transcription, on or off as last chosen.
//

import AppKit
import AVKit
import ImageIO

// MARK: - Tracks

/// One subtitle stream in the file, as ffmpeg numbers it.
nonisolated struct PreviewSubtitleTrack: Identifiable, Hashable, Sendable {
    /// ffmpeg's index among the file's subtitle streams (`0:s:N`).
    let index: Int
    let codec: String
    let language: String?
    let title: String?
    let isDefault: Bool
    let isForced: Bool

    var id: Int { index }

    enum Kind { case text, picture }

    var kind: Kind? {
        if Self.textCodecs.contains(codec) { return .text }
        if Self.pictureCodecs.contains(codec) { return .picture }
        return nil
    }

    private static let textCodecs: Set<String> = [
        "subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text", "microdvd",
        "subviewer", "subviewer1", "sami", "realtext", "mpl2", "pjs", "vplayer", "jacosub", "stl",
    ]
    private static let pictureCodecs: Set<String> = [
        "hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub",
    ]

    /// "SRT", "PGS"… — added to a name only where two tracks would otherwise
    /// read the same.
    var formatName: String {
        switch codec {
        case "subrip", "srt":       return "SRT"
        case "ass", "ssa":          return "ASS"
        case "webvtt":              return "WebVTT"
        case "mov_text":            return "Timed Text"
        case "hdmv_pgs_subtitle":   return "PGS"
        case "dvd_subtitle":        return "VobSub"
        case "dvb_subtitle":        return "DVB"
        default:                    return codec.uppercased()
        }
    }

    /// "English", "English (SDH)", "Spanish — Latin American", "French (Forced)".
    var name: String {
        let languageName = language
            .flatMap { ["und", "zxx", "mis", "mul"].contains($0) ? nil : $0 }
            .flatMap { Locale.current.localizedString(forLanguageCode: $0) }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespaces) ?? ""
        var name: String
        switch (languageName, trimmedTitle.isEmpty) {
        case (nil, true):
            name = "Track \(index + 1)"
        case (nil, false):
            name = trimmedTitle
        case (let language?, true):
            name = language
        case (let language?, false):
            name = trimmedTitle.localizedCaseInsensitiveContains(language) ? trimmedTitle : "\(language) — \(trimmedTitle)"
        }
        if isForced, !name.localizedCaseInsensitiveContains("forced") { name += " (Forced)" }
        return name
    }

    /// The file's subtitle streams that can be shown, in ffmpeg's order.
    static func probe(_ url: URL) async -> [PreviewSubtitleTrack] {
        guard let data = await FFmpeg.probe([
            "-select_streams", "s",
            "-show_entries", "stream=codec_name:stream_disposition=default,forced:stream_tags=language,title",
            "-of", "json", url.path(percentEncoded: false),
        ]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]]
        else { return [] }

        return streams.enumerated().compactMap { index, stream in
            let disposition = stream["disposition"] as? [String: Any] ?? [:]
            let tags = stream["tags"] as? [String: Any] ?? [:]
            let track = PreviewSubtitleTrack(
                index: index,
                codec: stream["codec_name"] as? String ?? "",
                language: (tags["language"] as? String)?.lowercased(),
                title: tags["title"] as? String,
                isDefault: (disposition["default"] as? Int) == 1,
                isForced: (disposition["forced"] as? Int) == 1
            )
            return track.kind == nil ? nil : track
        }
    }
}

// MARK: - Choice

/// What the preview shows for subtitles.
nonisolated enum PreviewSubtitleChoice: Hashable, Sendable {
    case off
    /// One of the file's own tracks, by its ffmpeg subtitle index.
    case track(Int)
    /// macOS's transcription of the clip's speech.
    case transcribed

    fileprivate var stored: String {
        switch self {
        case .off:              return "off"
        case .track(let index): return "s:\(index)"
        case .transcribed:      return "transcribed"
        }
    }

    fileprivate init?(stored: String) {
        switch stored {
        case "off":         self = .off
        case "transcribed": self = .transcribed
        default:
            guard stored.hasPrefix("s:"), let index = Int(stored.dropFirst(2)) else { return nil }
            self = .track(index)
        }
    }
}

/// The subtitles chosen for each file, kept from one preview to the next and
/// across launches — the most recent hundred files.
@MainActor
enum PreviewSubtitleMemory {
    private static let key = "previewSubtitleChoices"
    private static let limit = 100

    /// [[path, choice]], most recent first.
    private static var entries: [[String]] {
        UserDefaults.standard.array(forKey: key) as? [[String]] ?? []
    }

    static func choice(for url: URL) -> PreviewSubtitleChoice? {
        let path = url.path(percentEncoded: false)
        return entries.first { $0.count == 2 && $0[0] == path }.flatMap { PreviewSubtitleChoice(stored: $0[1]) }
    }

    static func remember(_ choice: PreviewSubtitleChoice, for url: URL) {
        let path = url.path(percentEncoded: false)
        var list = entries.filter { $0.count == 2 && $0[0] != path }
        list.insert([path, choice.stored], at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    /// Restore Defaults: every file goes back to its default track.
    static func forgetAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// The choice a preview of `url` opens with: the one last made for this
    /// file, if its track is still there; otherwise the default track, or the
    /// first if none is marked default.
    static func initialChoice(for url: URL, tracks: [PreviewSubtitleTrack]) -> PreviewSubtitleChoice {
        if let saved = choice(for: url) {
            switch saved {
            case .off, .transcribed: return saved
            case .track(let index) where tracks.contains(where: { $0.index == index }): return saved
            case .track: break
            }
        }
        guard let track = tracks.first(where: \.isDefault) ?? tracks.first else { return .off }
        return .track(track.index)
    }
}

// MARK: - Picture subtitles

/// A clip's stretch of one picture-subtitle track: what shows when.
nonisolated struct PictureSubtitles: @unchecked Sendable {
    struct Frame {
        /// Seconds from the start of the clip.
        let time: Double
        /// Nil where the screen is clear.
        let image: CGImage?
        /// Where the image sits on the canvas, top-left origin.
        let rect: CGRect
    }

    /// The clip it belongs to, so a late result can't land on the next one.
    let clipID: Int
    let track: PreviewSubtitleTrack
    /// The frame the subtitles were drawn for.
    let canvas: CGSize
    let frames: [Frame]

    /// The frame showing at `time`, or nil if nothing is.
    func frame(at time: Double) -> Frame? {
        guard let index = frames.lastIndex(where: { $0.time <= time + 0.001 }) else { return nil }
        return frames[index].image == nil ? nil : frames[index]
    }

    /// Every change of subtitle in `track` from `start` for `length` seconds,
    /// drawn by ffmpeg into `folder`, read, and the folder deleted again.
    static func extract(clipID: Int, from url: URL, track: PreviewSubtitleTrack,
                        start: Double, length: Double, folder: URL) async -> PictureSubtitles? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }

        var arguments: [String] = []
        // Blu-ray subtitles are drawn for a 1920 × 1080 or 3840 × 2160
        // frame; 1080 is plenty for a preview and a quarter of the work.
        if track.codec == "hdmv_pgs_subtitle" { arguments += ["-canvas_size", "1920x1080"] }
        arguments += [
            "-ss", String(format: "%.3f", max(0, start)), "-i", url.path(percentEncoded: false),
            "-t", String(format: "%.3f", length),
            // One picture per change: identical frames in a row are dropped.
            "-filter_complex", "[0:s:\(track.index)]format=rgba,mpdecimate=hi=1:lo=1:frac=0:max=0",
            "-fps_mode", "passthrough", "-enc_time_base", "1/1000", "-frame_pts", "1",
            folder.appendingPathComponent("%d.png").path(percentEncoded: false),
        ]
        guard await FFmpeg.run(arguments) == 0, !Task.isCancelled else { return nil }

        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let timed = files.compactMap { file -> (Int, URL)? in
            guard file.pathExtension == "png", let ms = Int(file.deletingPathExtension().lastPathComponent) else { return nil }
            return (ms, file)
        }
        .sorted { $0.0 < $1.0 }

        var canvas = CGSize.zero
        var frames: [Frame] = []
        for (ms, file) in timed {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            canvas = CGSize(width: image.width, height: image.height)
            let (cropped, rect) = Self.trimmed(image)
            frames.append(Frame(time: Double(ms) / 1000, image: cropped, rect: rect))
        }
        guard !frames.isEmpty else { return nil }
        return PictureSubtitles(clipID: clipID, track: track, canvas: canvas, frames: frames)
    }

    /// The image cut down to its visible part, held in its own small buffer
    /// rather than the whole transparent canvas. Nil for a clear frame.
    private static func trimmed(_ image: CGImage) -> (CGImage?, CGRect) {
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return (nil, .zero) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // The first row of the buffer is the top of the image.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = pixels + y * width * 4
            var x = 0
            while x < width {
                if row[x * 4 + 3] != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    maxY = y
                }
                x += 1
            }
        }
        guard maxX >= minX, maxY >= minY else { return (nil, .zero) }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let full = context.makeImage(), let part = full.cropping(to: rect),
              let small = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
                                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (nil, .zero) }
        small.draw(part, in: CGRect(origin: .zero, size: rect.size))
        return (small.makeImage(), rect)
    }

    /// Where the canvas lies over the video. Blu-ray subtitles are placed on
    /// the disc's full 16:9 frame, so on a video cropped to another shape
    /// they keep their place on that frame; DVD and DVB subtitles are drawn
    /// for the video frame itself.
    func canvasRect(over video: CGRect) -> CGRect {
        guard track.codec == "hdmv_pgs_subtitle", video.width > 0, video.height > 0 else { return video }
        let frameAspect = canvas.width / max(canvas.height, 1)
        var size = video.size
        if video.width / video.height >= frameAspect {
            size.height = video.width / frameAspect
        } else {
            size.width = video.height * frameAspect
        }
        return CGRect(x: video.midX - size.width / 2, y: video.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

// MARK: - Drawing

/// Draws picture subtitles over the video. Lives in AVPlayerView's content
/// overlay, between the picture and the controls, which also goes with the
/// video into full screen.
final class PictureSubtitleView: NSView {
    weak var playerView: AVPlayerView?

    private let imageLayer = CALayer()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var subtitles: PictureSubtitles?
    private var shownTime: Double = -1
    private var shownFrame: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let host = CALayer()
        host.isGeometryFlipped = true
        layer = host
        wantsLayer = true
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        host.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    // The controls underneath keep every click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ subtitles: PictureSubtitles?, playing player: AVPlayer?) {
        if player !== self.player {
            if let timeObserver, let old = self.player { old.removeTimeObserver(timeObserver) }
            timeObserver = nil
            self.player = player
            if let player {
                timeObserver = player.addPeriodicTimeObserver(
                    forInterval: CMTime(value: 1, timescale: 25), queue: .main
                ) { [weak self] time in
                    MainActor.assumeIsolated { self?.update(at: time.seconds) }
                }
            }
        }
        self.subtitles = subtitles
        shownFrame = nil
        update(at: player?.currentTime().seconds ?? 0)
    }

    override func layout() {
        super.layout()
        shownFrame = nil
        update(at: shownTime)
    }

    private func update(at time: Double) {
        guard time.isFinite else { return }
        shownTime = time
        guard let subtitles, let frame = subtitles.frame(at: time), let image = frame.image,
              let playerView
        else {
            imageLayer.isHidden = true
            shownFrame = nil
            return
        }
        guard image !== shownFrame else { return }
        shownFrame = image
        let video = convert(playerView.videoBounds, from: playerView)
        let canvas = subtitles.canvasRect(over: video)
        let scale = canvas.width / max(subtitles.canvas.width, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        imageLayer.contents = image
        imageLayer.frame = CGRect(x: canvas.minX + frame.rect.minX * scale,
                                  y: canvas.minY + frame.rect.minY * scale,
                                  width: frame.rect.width * scale,
                                  height: frame.rect.height * scale)
        imageLayer.isHidden = false
        CATransaction.commit()
    }

    func stop() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        subtitles = nil
        imageLayer.contents = nil
    }
}

// MARK: - Leftovers

/// Preview folders left behind by a copy of the app that quit without
/// cleaning up — crashed or was force-quit — are deleted at the next launch.
/// A folder belonging to a copy still running is left alone.
nonisolated enum PreviewLeftovers {
    static func sweep() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftMediaInfo", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let name = folder.lastPathComponent
            if name.hasPrefix("Preview-") {
                let parts = name.split(separator: "-")
                if parts.count > 1, let pid = Int32(parts[1]), pid == getpid() || isRunning(pid) { continue }
                try? FileManager.default.removeItem(at: folder)
            } else if UUID(uuidString: name) != nil, holdsOnlyPreviewFiles(folder) {
                // From before preview folders were named: clips and frames.
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func holdsOnlyPreviewFiles(_ folder: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)),
              !files.isEmpty else { return false }
        return files.allSatisfy { $0.wholeMatch(of: /(clip|frame)-\d+\.(mp4|m4a|hevc|jpg)/) != nil }
    }
}
