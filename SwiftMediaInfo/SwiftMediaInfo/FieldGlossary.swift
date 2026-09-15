//
//  FieldGlossary.swift
//  SwiftMediaInfo
//
//  PHASE 8a — plain-language explanations for MediaInfo's field names.
//
//  DELIBERATELY INCOMPLETE
//
//  MediaInfo emits several hundred distinct fields depending on the container
//  and codec. This covers the ones people actually read — roughly the fields
//  Easy View surfaces, plus common neighbours.
//
//  Anything not listed here gets **no tooltip at all**, rather than a generated
//  guess. A wrong explanation of a technical field is worse than no explanation:
//  someone reading metadata is usually trying to settle a question, and a
//  plausible-sounding invention is the one thing that could send them the wrong
//  way with confidence. Silence is honest; a guess is not.
//
//  Explanations answer "what does this number mean for me", not "what does the
//  spec call this". Anyone who wants the spec already knows where to find it.
//

import Foundation

enum FieldGlossary {

    /// Plain-language explanation for a raw MediaInfo key, or nil if this field
    /// isn't one we can describe accurately.
    static func explanation(for key: String) -> String? {
        // MediaInfo appends variants like Duration_String3 or BitRate_String.
        // They describe the same quantity, so the base key's entry applies.
        if let direct = entries[key] { return direct }

        for suffix in ["_String4", "_String3", "_String2", "_String1", "_String"] {
            if key.hasSuffix(suffix) {
                let base = String(key.dropLast(suffix.count))
                if let match = entries[base] { return match }
            }
        }

        return nil
    }

    // MARK: - Entries

    private static let entries: [String: String] = [

        // ── Identity ────────────────────────────────────────────────
        "FileName":
            "The file’s name, without its folder path.",
        "FileExtension":
            "The part after the last dot. It suggests the container but doesn’t guarantee it — MediaInfo reads the actual contents.",
        "Format":
            "The container or codec. A container (MKV, MP4) holds streams; a codec (HEVC, AAC) is how a stream is encoded.",
        "Format_Profile":
            "A named subset of the format's features. Decoders support specific profiles, so this often decides whether a device can play the file.",
        "Format_Level":
            "How demanding the stream is within its profile — roughly resolution and bitrate combined. Higher levels need more capable hardware.",
        "Format_Version":
            "Which revision of the format specification the file follows.",
        "Format_Commercial_IfAny":
            "The marketing name for this format, such as Dolby Vision or DTS-HD Master Audio.",
        "CodecID":
            "The container's own four-character identifier for the stream's codec.",
        "InternetMediaType":
            "The MIME type, as used by web servers and browsers.",
        "UniqueID":
            "A random identifier written when the file was created. Useful for telling apart two files with identical contents.",

        // ── Size and duration ───────────────────────────────────────
        "FileSize":
            "Total size on disk, including every stream and all metadata.",
        "StreamSize":
            "How much of the file this particular stream accounts for.",
        "Duration":
            "How long the file plays.",
        "Delay":
            "How far this stream is offset from the start. A non-zero audio delay is how lip sync is corrected.",
        "Delay_Source":
            "Where the delay value came from — the container or the stream itself.",

        // ── Bitrate ─────────────────────────────────────────────────
        "BitRate":
            "Data used per second. Higher generally means better quality for the same codec, but the codec matters more than the number.",
        "OverallBitRate":
            "Data per second for the whole file — every stream added together.",
        "BitRate_Mode":
            "Constant spends the same data every second. Variable spends more on complex scenes and less on simple ones, which is usually the better trade.",
        "BitRate_Maximum":
            "The highest rate the stream reaches. Playback devices must sustain at least this much.",
        "BitRate_Nominal":
            "The rate the encoder targeted, which may differ from what it achieved.",

        // ── Picture ─────────────────────────────────────────────────
        "Width":
            "Picture width in pixels.",
        "Height":
            "Picture height in pixels.",
        "DisplayAspectRatio":
            "The shape the picture should be shown at. It can differ from width ÷ height when the pixels themselves aren't square.",
        "PixelAspectRatio":
            "Whether the pixels are square. Anything other than 1.000 means the picture is stretched on display.",
        "FrameRate":
            "Frames shown per second. 23.976 is film, 25 is PAL broadcast, 29.97 is NTSC.",
        "FrameRate_Mode":
            "Constant keeps a fixed interval between frames. Variable doesn't, which some editors handle poorly.",
        "FrameCount":
            "Total number of frames in the stream.",
        "ScanType":
            "Progressive draws whole frames. Interlaced draws alternating half-frames, a legacy of broadcast television, and usually needs deinterlacing.",
        "ScanOrder":
            "For interlaced video, which half-frame comes first.",
        "Rotation":
            "How far the picture should be turned on playback. Phone video often carries a rotation instead of being re-encoded.",

        // ── Colour ──────────────────────────────────────────────────
        "ColorSpace":
            "How colour is represented. YUV separates brightness from colour, which is why chroma can be stored at lower resolution.",
        "ChromaSubsampling":
            "How much colour detail is kept relative to brightness. 4:2:0 keeps a quarter, which the eye barely notices; 4:4:4 keeps all of it.",
        "BitDepth":
            "Bits per colour sample. 8-bit gives 256 levels per channel, 10-bit gives 1024 — the difference shows most in gradients like skies.",
        "colour_primaries":
            "Which set of physical colours the values refer to. BT.709 is standard HD; BT.2020 is the wider range used for HDR.",
        "transfer_characteristics":
            "The curve mapping stored values to brightness. PQ and HLG are the HDR curves.",
        "matrix_coefficients":
            "The formula converting between RGB and YUV. A mismatch here is a classic cause of washed-out or oversaturated playback.",
        "colour_range":
            "Limited uses 16–235 for historical broadcast reasons; Full uses 0–255. Getting this wrong crushes blacks or blows out whites.",
        "HDR_Format":
            "Which HDR system the video uses — HDR10, HDR10+, or Dolby Vision.",
        "HDR_Format_Compatibility":
            "What a display without full HDR support will fall back to.",
        "MasteringDisplay_Luminance":
            "The brightness range of the reference monitor the content was graded on.",
        "MaxCLL":
            "The brightest single pixel anywhere in the content.",
        "MaxFALL":
            "The brightest frame average. Displays use it to manage sustained brightness.",

        // ── Audio ───────────────────────────────────────────────────
        "Channels":
            "How many audio channels. 2 is stereo, 6 is 5.1 surround, 8 is 7.1.",
        "ChannelPositions":
            "Where each channel is meant to sit in the room.",
        "ChannelLayout":
            "The channels in their standard order, by short name.",
        "SamplingRate":
            "Audio samples per second. 48 kHz is standard for video; 44.1 kHz comes from CD.",
        "Compression_Mode":
            "Lossy discards detail permanently to save space. Lossless can be restored exactly.",
        "Format_Settings_Endianness":
            "Byte order for uncompressed audio. Rarely matters unless something plays back as noise.",
        "SamplesPerFrame":
            "How many audio samples each compressed frame carries.",

        // ── Text and menus ──────────────────────────────────────────
        "Language":
            "The language of this stream, as declared in the file. It's a label, not a guarantee.",
        "Title":
            "A human-readable name for this stream, shown by players in track menus.",
        "Default":
            "Whether players should select this stream automatically.",
        "Forced":
            "Marks subtitles meant to appear even with subtitles off — usually for foreign dialogue in an otherwise untranslated film.",
        "ElementCount":
            "How many entries this stream contains, such as chapter markers.",

        // ── Provenance ──────────────────────────────────────────────
        "Encoded_Date":
            "When the file was encoded, as recorded inside it. Independent of the filesystem's date, which changes when a file is copied.",
        "Tagged_Date":
            "When the metadata was last written.",
        "File_Modified_Date":
            "When the filesystem last saw the file change. Resets on copy, so it says little about the content.",
        "Encoded_Application":
            "The program that produced the file.",
        "Encoded_Library":
            "The encoder library and version. Often the most telling field about how a file was made.",
        "Encoded_Library_Settings":
            "The exact parameters the encoder was given. Verbose, and the closest thing to a recipe for the encode.",
        "Writing_Application":
            "The program that assembled the container, which is frequently not the program that did the encoding.",
        "Writing_Library":
            "The library used to write the container.",

        // ── Streaming and structure ─────────────────────────────────
        "IsStreamable":
            "Whether playback can begin before the whole file has downloaded. This depends on where the index sits in the file.",
        "Interleaved":
            "Whether audio and video are woven together through the file rather than stored in separate blocks.",
        "MuxingMode":
            "How the streams were combined into the container.",
        "ID":
            "The stream's identifier within the container. Players and tools use it to select tracks.",
        "StreamOrder":
            "The stream's position in the file, which can differ from its ID.",
        "Alternate_Group":
            "Streams in the same group are alternatives to one another — typically the same audio in different languages.",
        "Attachments":
            "Extra files carried inside the container, such as subtitle fonts or cover art.",
        "Cover":
            "Whether embedded artwork is present.",
    ]
}
