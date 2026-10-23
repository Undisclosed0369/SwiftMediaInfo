//
//  SyntaxHighlighter.swift
//  SwiftMediaInfo
//
//  Syntax highlighting for the JSON and XML views (Settings › Appearance ›
//  Code Views decides which).
//
//  RESTRAINED ON PURPOSE
//
//  Xcode's own default theme, and only a handful of its roles: names (JSON
//  keys, XML elements), string values, numbers, true/false/null, punctuation
//  and comments. A MediaInfo report is almost entirely names and values, so
//  in practice the page is two colours plus quiet punctuation — enough to
//  find your place, never a rainbow.
//
//  LIGHT AND DARK
//
//  Every colour is a dynamic NSColor that resolves against the text view's
//  own appearance each time it draws. Switching between light and dark — by
//  the system, or by the app's Appearance setting — recolours the text
//  instantly, without re-highlighting and without anything having to notice
//  the change. The light and dark values are Xcode's, which are tuned for
//  contrast on their respective backgrounds.
//
//  SPEED
//
//  One pass over the UTF-16 code units, no regular expressions in the JSON
//  path. A Blu-ray remux with 60+ tracks produces a few hundred kilobytes of
//  JSON, and this stays well under a frame for that.
//

import AppKit

enum CodeLanguage {
    case json, xml
}

/// Settings › Appearance › Syntax Highlighting.
enum SyntaxHighlighting: String, CaseIterable, Identifiable {
    case on, off, jsonOnly, xmlOnly
    
    static let key = "syntaxHighlighting"
    static let shippedDefault = SyntaxHighlighting.on
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .on:       return "On"
        case .off:      return "Off"
        case .jsonOnly: return "Only JSON"
        case .xmlOnly:  return "Only XML"
        }
    }
    
    /// The language to highlight a view as, or nil to show it plain.
    func language(_ language: CodeLanguage?) -> CodeLanguage? {
        switch (self, language) {
        case (.on, _), (.jsonOnly, .json), (.xmlOnly, .xml): return language
        default: return nil
        }
    }
}

enum SyntaxHighlighter {

    // MARK: Palette

    enum Palette {
        // One set of hues for both appearances: Xcode's dark theme — cyan
        // names, coral strings, gold numbers, pink keywords, tan attributes.
        // In light mode each is the same hue taken much darker, because the
        // dark-mode values are pastel enough to vanish on the light gradient.
        // The light values clear about 6:1 contrast on the background's usual
        // lavender and blue, and stay near 4.5:1 even over its deepest
        // violet; comments are kept a step quieter on purpose.
        
        /// JSON keys and XML element names — the structure you scan by.
        static let name = dynamic(light: 0x005A73, dark: 0x5DD8FF)
        static let string = dynamic(light: 0x9E2716, dark: 0xFC6A5D)
        static let number = dynamic(light: 0x574700, dark: 0xD0BF69)
        static let keyword = dynamic(light: 0x8C1450, dark: 0xFC5FA3)
        /// XML attribute names.
        static let attribute = dynamic(light: 0x653C17, dark: 0xBF8555)
        static let comment = dynamic(light: 0x4A545E, dark: 0x6C7986)
        /// Braces, brackets, colons, commas, angle brackets: present but quiet.
        static let punctuation = NSColor.secondaryLabelColor
        static let text = NSColor.labelColor

        private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return color(isDark ? dark : light)
            }
        }

        private static func color(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    // MARK: Entry point

    static func attributedString(_ text: String, language: CodeLanguage, font: NSFont) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: Palette.text
        ])
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)

        result.beginEditing()
        switch language {
        case .json: highlightJSON(result, boldFont: bold)
        case .xml:  highlightXML(result)
        }
        result.endEditing()
        return result
    }

    // MARK: JSON

    private static func highlightJSON(_ storage: NSMutableAttributedString, boldFont: NSFont) {
        let units = Array(storage.string.utf16)
        let count = units.count
        var i = 0

        func paint(_ color: NSColor, _ start: Int, _ end: Int) {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: end - start))
        }

        while i < count {
            let c = units[i]
            switch c {
            case 0x22: // "
                let start = i
                i += 1
                while i < count && units[i] != 0x22 {
                    i += units[i] == 0x5C ? 2 : 1   // skip escaped characters
                }
                i = min(i + 1, count)

                // A string followed by a colon is a key.
                var j = i
                while j < count, units[j] == 0x20 || units[j] == 0x09 || units[j] == 0x0A || units[j] == 0x0D { j += 1 }
                paint(j < count && units[j] == 0x3A ? Palette.name : Palette.string, start, i)

            case 0x7B, 0x7D, 0x5B, 0x5D, 0x3A, 0x2C: // { } [ ] : ,
                paint(Palette.punctuation, i, i + 1)
                i += 1

            case 0x2D, 0x30...0x39: // - and digits
                let start = i
                i += 1
                while i < count, isNumberPart(units[i]) { i += 1 }
                paint(Palette.number, start, i)

            case 0x74, 0x66, 0x6E: // t f n — true, false, null
                if let word = ["true", "false", "null"].first(where: { starts(units, at: i, with: $0) }) {
                    let length = word.utf16.count
                    paint(Palette.keyword, i, i + length)
                    storage.addAttribute(.font, value: boldFont, range: NSRange(location: i, length: length))
                    i += length
                } else {
                    i += 1
                }
                
            default:
                i += 1
            }
        }
    }

    private static func starts(_ units: [UInt16], at index: Int, with word: String) -> Bool {
        let target = Array(word.utf16)
        guard index + target.count <= units.count else { return false }
        return Array(units[index..<index + target.count]) == target
    }
    
    private static func isNumberPart(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || unit == 0x2E || unit == 0x65 || unit == 0x45 || unit == 0x2B || unit == 0x2D
    }

    // MARK: XML

    private static let commentPattern = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#)
    private static let declarationPattern = try! NSRegularExpression(pattern: #"<\?[\s\S]*?\?>|<!\[CDATA\[[\s\S]*?\]\]>|<![A-Z][^>]*>"#)
    private static let tagPattern = try! NSRegularExpression(pattern: #"(</?)([A-Za-z_][\w:.\-]*)([^>]*?)(/?>)"#)
    private static let attributePattern = try! NSRegularExpression(pattern: #"([A-Za-z_][\w:.\-]*)(\s*=\s*)("[^"]*"|'[^']*')"#)

    private static func highlightXML(_ storage: NSMutableAttributedString) {
        let text = storage.string
        let whole = NSRange(location: 0, length: (text as NSString).length)

        for match in tagPattern.matches(in: text, range: whole) {
            storage.addAttribute(.foregroundColor, value: Palette.punctuation, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: Palette.name, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: Palette.punctuation, range: match.range(at: 4))

            let attributes = match.range(at: 3)
            guard attributes.length > 0 else { continue }
            for attribute in attributePattern.matches(in: text, range: attributes) {
                storage.addAttribute(.foregroundColor, value: Palette.attribute, range: attribute.range(at: 1))
                storage.addAttribute(.foregroundColor, value: Palette.punctuation, range: attribute.range(at: 2))
                storage.addAttribute(.foregroundColor, value: Palette.string, range: attribute.range(at: 3))
            }
        }

        // Last, so a tag-shaped piece of text inside a comment or declaration
        // ends up the comment's colour, not a tag's.
        for pattern in [declarationPattern, commentPattern] {
            for match in pattern.matches(in: text, range: whole) {
                storage.addAttribute(.foregroundColor, value: Palette.comment, range: match.range)
            }
        }
    }
}
