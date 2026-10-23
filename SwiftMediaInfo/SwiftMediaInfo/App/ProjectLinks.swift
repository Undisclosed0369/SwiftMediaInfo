//
//  ProjectLinks.swift
//  SwiftMediaInfo
//
//  One place for every address the app can send someone to: the website and
//  its pages, the GitHub repository, and third-party pages (MediaArea,
//  Homebrew). Add new links here rather than as literals in a view — a
//  renamed page or a new domain is then a one-line edit, instead of a menu
//  item somewhere quietly opening a dead link.
//
//  Upload services used by Share (ship.page, markdown.page, pb.plz.ac, up.sb)
//  are not here; they live with the upload code in MediaStore+Share.
//

import Foundation
import AppKit

enum ProjectLinks {
    
    // MARK: - Website
    
    /// The studio root. Used where the author is being credited rather than
    /// the app being linked.
    static let website = "https://undisclosed0369.app"
    
    /// The app's own page. This is the one to use for anything about
    /// SwiftMediaInfo specifically — it is where a visitor should land, not
    /// the studio index that lists everything.
    static let appPage = "https://undisclosed0369.app/swiftmediainfo/"
    
    /// The FAQ. Genuinely the app's documentation: why macOS warns on first
    /// launch, why MediaInfo is needed, what happens to your files.
    static let faq = "https://undisclosed0369.app/swiftmediainfo/faq.html"
    
    /// The donate page. Named `donate` rather than `support` because support
    /// means something else in software and the ambiguity would cost more
    /// than the word saves.
    static let donate = "https://undisclosed0369.app/swiftmediainfo/donate.html"
    
    // MARK: - Repository
    
    static let github = "https://github.com/Undisclosed0369/SwiftMediaInfo"
    static let issues = "https://github.com/Undisclosed0369/SwiftMediaInfo/issues"
    static let license = "https://github.com/Undisclosed0369/SwiftMediaInfo/blob/main/LICENSE"
    
    // MARK: - Third party
    
    /// MediaArea's download page. SwiftMediaInfo is a front-end for their
    /// work; when the dependency is missing, this is where someone is sent.
    static let mediaAreaDownload = "https://mediaarea.net/en/MediaInfo/Download/Mac_OS"
    
    /// Homebrew, the usual way to install MediaInfo and ffmpeg. Where it
    /// isn't installed, "Get Homebrew" sends someone here.
    static let homebrew = "https://brew.sh"
    
    // MARK: - Opening
    
    /// Opens a link in the user's browser. A malformed address fails quietly
    /// here, in one place, instead of needing a `guard` at every call site.
    @MainActor
    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
