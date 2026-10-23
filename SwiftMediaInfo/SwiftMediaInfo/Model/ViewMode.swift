//
//  ViewMode.swift
//  SwiftMediaInfo
//
//  The report's views (Easy, Text, Raw Text, HTML, XML, JSON) and the
//  formats it can be exported or shared in. Adding a view or an export
//  format starts here: each case maps to the mediainfo output it is drawn
//  from (MediaFormat, in FormatLoader).
//

import Foundation
import SwiftUI

// MARK: - View Modes

/// The toolbar's view buttons, in order. The raw value is persisted (the
/// last-used view), so don't rename cases.
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
    
    /// The digit of its shortcut, ⌃⌘1–⌃⌘6 (⌘1–⌘9 select tabs).
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

    /// The mediainfo output this view is drawn from. Easy and JSON share one:
    /// Easy View is the JSON, parsed into tracks.
    var format: MediaFormat {
        switch self {
        case .easy, .json: return .json
        case .text:        return .text
        case .rawText:     return .rawText
        case .html:        return .html
        case .xml:         return .xml
        }
    }
}

// MARK: - Export Format

/// What Export (and Share) can produce. Raw values must stay in step with
/// ShareFormat's: the Share menu reuses this list and maps each choice to a
/// ShareFormat by raw value.
enum ExportFormat: String, CaseIterable, Identifiable {
    // Declaration order is menu order: human-readable first, then
    // machine-readable.
    case text, rawText, html, pdf, markdown, csv, json, xml
    var id: String { rawValue }
    
    /// The Export and Share menus' two groups.
    enum Category: CaseIterable {
        case humanReadable, machineReadable
        
        var title: String {
            switch self {
            case .humanReadable:   return "Human-readable"
            case .machineReadable: return "Machine-readable"
            }
        }
        
        var formats: [ExportFormat] {
            ExportFormat.allCases.filter { $0.category == self }
        }
    }
    
    var category: Category {
        switch self {
        case .text, .rawText, .html, .pdf, .markdown: return .humanReadable
        case .csv, .json, .xml:                       return .machineReadable
        }
    }
    
    var fileExtension: String {
        switch self {
        case .text, .rawText: return "txt"   // raw text is still a .txt file
        case .markdown: return "md"
        default:        return rawValue
        }
    }
    
    /// Added to the file name so formats sharing an extension don't collide.
    var fileSuffix: String {
        self == .rawText ? "_raw" : ""
    }

    /// The mediainfo output this export is made from. CSV, Markdown and PDF
    /// are built from the parsed tracks, which come from JSON.
    var sourceFormat: MediaFormat {
        switch self {
        case .text:                       return .text
        case .rawText:                    return .rawText
        case .html:                       return .html
        case .xml:                        return .xml
        case .json, .csv, .markdown, .pdf: return .json
        }
    }
    
    var label: String {
        switch self {
        case .text:     return "Text (.txt)"
        case .rawText:  return "Raw Text (.txt)"
        case .html:     return "HTML (.html)"
        case .pdf:      return "PDF (.pdf)"
        case .markdown: return "Markdown (.md)"
        case .csv:      return "CSV (.csv)"
        case .json:     return "JSON (.json)"
        case .xml:      return "XML (.xml)"
        }
    }
    
    /// The SF Symbol in the Export and Share menus.
    var icon: String {
        switch self {
        case .text:     return "doc.text"
        case .rawText:  return "text.alignleft"
        case .html:     return "globe"
        case .pdf:      return "doc.richtext"
        case .markdown: return "m.square"
        case .csv:      return "tablecells"
        case .json:     return "curlybraces"
        case .xml:      return "chevron.left.forwardslash.chevron.right"
        }
    }
}
