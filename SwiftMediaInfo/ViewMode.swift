//
//  ViewMode.swift
//  SwiftMediaInfo
//
//  Created by Undisclosed on 23/4/26.
//


//
//  Models.swift
//  MediaInfoMac
//

import Foundation
import SwiftUI

// MARK: - View Modes

enum ViewMode: String, CaseIterable, Identifiable {
    case easy, text, html, xml, json
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .easy:  return "Easy"
        case .text:  return "Text"
        case .html:  return "HTML"
        case .xml:   return "XML"
        case .json:  return "JSON"
        }
    }
    
    var icon: String {
        switch self {
        case .easy:  return "list.bullet.rectangle"
        case .text:  return "doc.text"
        case .html:  return "globe"
        case .xml:   return "chevron.left.forwardslash.chevron.right"
        case .json:  return "curlybraces"
        }
    }
    
    var shortcut: KeyEquivalent {
        switch self {
        case .easy:  return "1"
        case .text:  return "2"
        case .html:  return "3"
        case .xml:   return "4"
        case .json:  return "5"
        }
    }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case text, html, xml, json, csv
    var id: String { rawValue }
    
    var fileExtension: String { rawValue }
    
    var label: String {
        switch self {
        case .text: return "Text (.txt)"
        case .html: return "HTML (.html)"
        case .xml:  return "XML (.xml)"
        case .json: return "JSON (.json)"
        case .csv:  return "CSV (.csv)"
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

struct MediaFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var tracks:    [MediaTrack] = []
    var rawText:   String = ""
    var rawHTML:   String = ""
    var rawXML:    String = ""
    var rawJSON:   String = ""
    var isLoading: Bool   = true
    var error:     String? = nil
    
    static func == (lhs: MediaFile, rhs: MediaFile) -> Bool { lhs.id == rhs.id }
    
    var fileName: String { url.lastPathComponent }
    
    var fileSizeString: String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    var generalTrack: MediaTrack? { tracks.first(where: { $0.type == "General" }) }
    var videoTracks:  [MediaTrack] { tracks.filter { $0.type == "Video" } }
    var audioTracks:  [MediaTrack] { tracks.filter { $0.type == "Audio" } }
    var textTracks:   [MediaTrack] { tracks.filter { $0.type == "Text"  } }
    var menuTracks:   [MediaTrack] { tracks.filter { $0.type == "Menu"  } }
}
