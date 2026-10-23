//
//  FileLookup.swift
//  SwiftMediaInfo
//
//  Finds a file on this Mac from its name, size and modification date — for
//  the website's "Open in SwiftMediaInfo" button (swiftmediainfo://find?…).
//
//  WHY BY NAME
//
//  A web page is never told where a file lives: the browser hands it the
//  bytes, the name, the size and the modification date, and nothing else. So
//  the page sends those three, and the app looks the file up itself — through
//  Spotlight, then directly in the folders this app has opened files from
//  and the folders downloads usually land in. The direct look covers what
//  Spotlight cannot see: external and network drives it does not index, and
//  places it has been told to skip. Nothing leaves the Mac; the link only
//  ever travels from the browser to this app.
//
//  PRIVACY-PROTECTED FOLDERS
//
//  Spotlight only returns files this app may read. Until macOS has asked
//  permission for Downloads, Desktop or Documents, files there are silently
//  left out of the results — which is why the direct look in those folders
//  follows: touching them is what makes macOS ask, once. After that,
//  Spotlight finds them too.
//
//  The size has to match exactly, so a different file with the same name is
//  never opened by mistake. When two files still match, the modification date
//  decides; if it cannot, or nothing matches, the caller shows the Open
//  dialog rather than guessing.
//

import Foundation

@MainActor
enum FileLookup {

    /// Files called `name` whose size (and, to break ties, modification
    /// date) match. Empty if none could be found within a few seconds.
    static func files(named name: String, size: Int64?, modified: Date?) async -> [URL] {
        // A name, never a path: anything with a slash in it is not a file
        // name a browser would send, and is not looked up.
        guard !name.isEmpty, !name.contains("/") else { return [] }

        // Spotlight's results are checked by size before they count: a
        // same-named file of another size is not a reason to stop looking.
        func matchingSize(_ candidates: [URL]) -> [URL] {
            candidates.filter { url in
                guard let size else { return true }
                return fileSize(url) == size
            }
        }
        var sized = matchingSize(await spotlight(name))
        if sized.isEmpty { sized = matchingSize(knownFolders(name)) }
        guard sized.count > 1, let modified else { return sized }

        // Browsers report the date in whole milliseconds, file systems in
        // finer steps; two seconds absorbs both and still tells copies apart.
        let dated = sized.filter { url in
            guard let date = modificationDate(url) else { return false }
            return abs(date.timeIntervalSince(modified)) < 2
        }
        return dated.isEmpty ? sized : dated
    }

    // MARK: Spotlight

    private static func spotlight(_ name: String) async -> [URL] {
        await withCheckedContinuation { continuation in
            SpotlightSearch(name: name) { continuation.resume(returning: $0) }.start()
        }
    }

    /// One Spotlight query, finished by its first results or by a timeout,
    /// whichever comes first.
    private final class SpotlightSearch: NSObject {
        private let query = NSMetadataQuery()
        private let done: ([URL]) -> Void
        private var finished = false
        private var retainSelf: SpotlightSearch?

        init(name: String, done: @escaping ([URL]) -> Void) {
            self.done = done
            super.init()
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, name)
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
        }

        func start() {
            retainSelf = self
            NotificationCenter.default.addObserver(
                self, selector: #selector(gathered),
                name: .NSMetadataQueryDidFinishGathering, object: query
            )
            if !query.start() { finish() ; return }
            // Spotlight can be slow to answer, or switched off entirely.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.finish() }
        }

        @objc private func gathered() { finish() }

        private func finish() {
            guard !finished else { return }
            finished = true
            query.stop()
            NotificationCenter.default.removeObserver(self)
            let urls = query.results.compactMap { item -> URL? in
                guard let path = (item as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String,
                      FileManager.default.fileExists(atPath: path) else { return nil }
                return URL(fileURLWithPath: path)
            }
            done(urls)
            retainSelf = nil
        }
    }

    // MARK: Fallback

    /// Where a file picked in a browser usually is: the folders of files
    /// opened in this app before (recent files and favorites, which is how a
    /// drive Spotlight does not index gets looked at), favorite folders
    /// themselves, then Downloads and the other folders a browser's file
    /// dialog opens in.
    private static func knownFolders(_ name: String) -> [URL] {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        let remembered = ((defaults.stringArray(forKey: "recentFiles") ?? [])
                          + (defaults.stringArray(forKey: MediaStore.favoritesKey) ?? []))
            .compactMap { URL(string: $0) }
            .filter(\.isFileURL)
            .map { url -> URL in
                // A favorite can be a folder; a file stands for the one it is in.
                var isDirectory: ObjCBool = false
                let exists = fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
                return exists && isDirectory.boolValue ? url : url.deletingLastPathComponent()
            }
        let usual = [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .moviesDirectory, .documentDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }

        var seen = Set<String>()
        return (remembered + usual)
            .filter { seen.insert($0.standardizedFileURL.path(percentEncoded: false)).inserted }
            .map { $0.appendingPathComponent(name) }
            .filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    // MARK: Attributes

    private static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
