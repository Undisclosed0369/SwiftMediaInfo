//
//  ProjectLinks.swift
//  SwiftMediaInfo
//
//  PHASE 13n — one place for every address the app can send someone to.
//
//  WHAT WAS HERE BEFORE
//
//  Nothing. The URLs lived as string literals inside whichever view happened
//  to need them: the GitHub address appeared in three separate files, the
//  issues address in two. That was survivable while there were three of them
//  and they all pointed at the same repository.
//
//  WHY THIS EXISTS NOW
//
//  Phase 13n adds the website and the donate page, which takes the count to
//  six across three files. Six literals in three files is a maintenance trap:
//  the day the domain changes, or a page is renamed, the failure is silent —
//  one menu item quietly opens a dead link and nothing tells you.
//
//  So the addresses live here, once, and the views read from them. Changing
//  the domain is now a one-line edit in one file.
//
//  Everything here is a `static let` on an enum with no cases, which is the
//  usual Swift way of saying "namespace, not a type you can instantiate".
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
    
    // MARK: - Opening
    
    /// Opens a link in the user's browser.
    ///
    /// Every caller used to write the same three lines: build a `URL`, unwrap
    /// it, hand it to `NSWorkspace`. The unwrap can never fail for the
    /// constants above — they are valid at compile time — but Swift cannot
    /// know that, so the dance was repeated at every call site.
    ///
    /// Doing it here means a malformed address fails quietly in one place
    /// instead of needing a `guard` in eight.
    @MainActor
    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
