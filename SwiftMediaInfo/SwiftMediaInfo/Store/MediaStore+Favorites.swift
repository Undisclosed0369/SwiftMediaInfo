//
//  MediaStore+Favorites.swift
//  SwiftMediaInfo
//
//  Favorites: files (and folders) you come back to, starred from their tab.
//  The list is kept in user defaults as absolute file URLs, newest first.
//  Paths rather than security bookmarks because the app is not sandboxed: a
//  path is all it needs to open a file, and a path is what the user can read
//  in a menu. Shown in File › Favorites, the tab menu, the empty screen,
//  the New Tab button's menu and every Compare With list.
//
//  A favorite whose file has since moved or been deleted stays in the list,
//  marked missing, rather than vanishing — the same rule Recent Files follows,
//  because a file on an unmounted drive is not gone, only away.
//

import SwiftUI
import AppKit

extension MediaStore {

    static let favoritesKey = "favoriteFiles"

    static func loadFavorites() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
            .compactMap { URL(string: $0) }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favoriteURLs.map(\.absoluteString), forKey: Self.favoritesKey)
    }

    // MARK: Queries

    func isFavorite(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        return favoriteURLs.contains { $0.standardizedFileURL == target }
    }

    /// Whether a favorite can be compared with the file on screen: there is
    /// a file on screen, the favorite is a file (not a folder) that still
    /// exists, and it is not the same file.
    func canCompareWithCurrentFile(_ url: URL) -> Bool {
        guard hasOpenReport, let current = currentFile?.url else { return false }
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return url.standardizedFileURL != current.standardizedFileURL
    }

    func favoriteExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: Changes

    /// Star or unstar. New favorites go to the top of the list.
    func toggleFavorite(_ url: URL) {
        let target = url.standardizedFileURL

        if isFavorite(target) {
            favoriteURLs.removeAll { $0.standardizedFileURL == target }
            SMI.A11y.announce("Removed \(target.lastPathComponent) from Favorites")
        } else {
            favoriteURLs.insert(target, at: 0)
            SMI.A11y.announce("Added \(target.lastPathComponent) to Favorites")
        }

        saveFavorites()
    }

    func removeFavorite(_ url: URL) {
        let target = url.standardizedFileURL
        favoriteURLs.removeAll { $0.standardizedFileURL == target }
        saveFavorites()
    }

    func clearFavorites() {
        favoriteURLs = []
        saveFavorites()
    }

    /// A renamed file keeps its star.
    func replaceFavorite(_ old: URL, with new: URL) {
        let target = old.standardizedFileURL
        guard let index = favoriteURLs.firstIndex(where: { $0.standardizedFileURL == target }) else { return }
        favoriteURLs[index] = new.standardizedFileURL
        saveFavorites()
    }
}
