//
//  FolderContents.swift
//  SwiftMediaInfo
//
//  Folder tabs: the folder's media files (FolderContents) and the scanner
//  that lists them (FolderScanner). The sidebar is FolderSidebar; the tab
//  model and file switching are in MediaStore+Tabs.
//
//  A folder opens as ONE tab, named after the folder, with its media files
//  listed beside the report. Exactly one file is analysed and shown at a time,
//  so every view — Easy View included — still describes a single file, which
//  is the only thing a media report can honestly do.
//
//  WHY NOT HAND THE FOLDER TO MEDIAINFO
//
//  mediainfo will happily describe a whole folder, recursively, in one go —
//  one enormous report whose JSON Easy View can't read (it is a list of
//  reports, not one), which takes as long as analysing every file in the tree
//  before anything appears. Listing the files and analysing the one you are
//  looking at is faster to first result and keeps every view meaningful.
//

import Foundation
import UniformTypeIdentifiers

struct FolderContents {
    let url: URL
    /// Media files inside, in Finder's order, including subfolders.
    var items: [URL] = []
    /// True until the folder has been read.
    var isScanning = true

    var name: String { url.lastPathComponent }

    /// The path of an item below the folder, without the file name — empty for
    /// files directly inside. Shown under names so files of the same name in
    /// different subfolders can be told apart.
    func subfolderPath(of item: URL) -> String {
        let base = url.standardizedFileURL.pathComponents
        let parts = item.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { return "" }
        return parts.dropFirst(base.count).joined(separator: "/")
    }
}

enum FolderScanner {

    /// More than any real media folder; enough to stop a mistaken drop of a
    /// home folder from walking the whole disk.
    nonisolated static let limit = 5_000

    /// Extensions that are media even where the system does not declare a
    /// type for them (Matroska, WebM, and other formats macOS has no importer
    /// for are the usual cases).
    nonisolated private static let knownMediaExtensions: Set<String> = [
        "mkv", "mka", "mks", "webm", "mp4", "m4v", "m4a", "mov", "avi", "wmv",
        "flv", "ts", "m2ts", "mts", "mpg", "mpeg", "vob", "ogv", "ogg", "oga",
        "opus", "flac", "wav", "aiff", "aif", "mp3", "aac", "ac3", "eac3", "dts",
        "thd", "alac", "ape", "wma", "wv", "3gp", "3g2", "mxf", "rm", "rmvb",
        "heic", "heif", "avif", "jpg", "jpeg", "png", "tif", "tiff", "dng"
    ]

    /// Every media file under `folder`, sorted the way Finder sorts names.
    /// Hidden files and package contents are skipped.
    nonisolated static func mediaFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []

        for case let url as URL in enumerator {
            guard found.count < limit else { break }

            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }

            if isMedia(url, type: values?.contentType) {
                found.append(url.standardizedFileURL)
            }
        }

        return found.sorted {
            $0.path(percentEncoded: false).localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending
        }
    }

    nonisolated private static func isMedia(_ url: URL, type: UTType?) -> Bool {
        if knownMediaExtensions.contains(url.pathExtension.lowercased()) { return true }
        guard let type else { return false }
        return type.conforms(to: .audiovisualContent) || type.conforms(to: .image)
    }

    nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
