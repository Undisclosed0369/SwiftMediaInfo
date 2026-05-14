//
//  ViewMode.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//

//
//  ViewMode.swift
//  SwiftMediaInfo
//

import Foundation
import SwiftUI

// MARK: - View Modes

enum ViewMode: String, CaseIterable, Identifiable {
    case easy, text, rawText, html, xml, json
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .easy:    return "Easy"
        case .text:    return "Text"
        case .rawText: return "Raw Text"
        case .html:    return "HTML"
        case .xml:     return "XML"
        case .json:    return "JSON"
        }
    }
    
    var icon: String {
        switch self {
        case .easy:    return "list.bullet.rectangle"
        case .text:    return "doc.text"
        case .rawText: return "text.alignleft"
        case .html:    return "globe"
        case .xml:     return "chevron.left.forwardslash.chevron.right"
        case .json:    return "curlybraces"
        }
    }
    
    var shortcut: KeyEquivalent {
        switch self {
        case .easy:    return "1"
        case .text:    return "2"
        case .rawText: return "3"
        case .html:    return "4"
        case .xml:     return "5"
        case .json:    return "6"
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case text, rawText, html, xml, json, csv
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .rawText: return "txt"   // raw text is still a .txt file
        default:       return rawValue
        }
    }
    
    var label: String {
        switch self {
        case .text:    return "Text (.txt)"
        case .rawText: return "Raw Text (.txt)"
        case .html:    return "HTML (.html)"
        case .xml:     return "XML (.xml)"
        case .json:    return "JSON (.json)"
        case .csv:     return "CSV (.csv)"
        }
    }
    
    /// System image name for the export popover icon
    var icon: String {
        switch self {
        case .text:    return "doc.text"
        case .rawText: return "text.alignleft"
        case .html:    return "globe"
        case .xml:     return "chevron.left.forwardslash.chevron.right"
        case .json:    return "curlybraces"
        case .csv:     return "tablecells"
        }
    }
}

// MARK: - Track

struct MediaTrack: Identifiable {
    let id = UUID()
    let type: String
    let streamIndex: Int
    var fields: [(key: String, value: String)]
    
    var typeIcon: String {
        switch type {
        case "Video":  return "film"
        case "Audio":  return "waveform"
        case "Text":   return "captions.bubble"
        case "Menu":   return "list.number"
        case "Image":  return "photo"
        default:       return "info.circle"
        }
    }
    
    var displayTitle: String {
        if type == "General" { return "General" }
        let lang  = fields.first(where: { $0.key == "Language/String" })?.value
        ?? fields.first(where: { $0.key == "Language" })?.value ?? ""
        let title = fields.first(where: { $0.key == "Title" })?.value ?? ""
        var parts: [String] = [streamIndex > 0 ? "\(type) #\(streamIndex + 1)" : type]
        if !lang.isEmpty  { parts.append(lang) }
        if !title.isEmpty { parts.append("") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - MediaFile
//
// Each format string starts as nil (not yet loaded).
// nil  = not fetched yet  →  show "Load" button
// ""   = fetched but empty (unlikely)
// text = ready to display

struct MediaFile: Identifiable, Equatable {
    let id   = UUID()
    let url  : URL
    
    // Parsed track data (from JSON). Populated automatically with Easy view.
    var tracks: [MediaTrack] = []
    
    // Per-format raw strings. nil means "not loaded yet".
    var rawText:     String? = nil   // normal mediainfo output
    var rawTextFull: String? = nil   // --Full output  (Raw Text view)
    var rawHTML:     String? = nil
    var rawXML:      String? = nil
    var rawJSON:     String? = nil   // also drives the Easy view
    
    // Per-format loading flags (true while the background task is running)
    var isLoadingText:     Bool = false
    var isLoadingRawText:  Bool = false
    var isLoadingHTML:     Bool = false
    var isLoadingXML:      Bool = false
    var isLoadingJSON:     Bool = false
    
    // Overall "first load in progress" flag shown in MainDetailView
    var isLoading: Bool = true
    var error: String? = nil
    
    static func == (lhs: MediaFile, rhs: MediaFile) -> Bool { lhs.id == rhs.id }
    
    var fileName:       String { url.lastPathComponent }
    
    var fileSizeString: String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    var generalTrack: MediaTrack?  { tracks.first(where: { $0.type == "General" }) }
    var videoTracks:  [MediaTrack] { tracks.filter { $0.type == "Video" } }
    var audioTracks:  [MediaTrack] { tracks.filter { $0.type == "Audio" } }
    var textTracks:   [MediaTrack] { tracks.filter { $0.type == "Text"  } }
    var menuTracks:   [MediaTrack] { tracks.filter { $0.type == "Menu"  } }
}
