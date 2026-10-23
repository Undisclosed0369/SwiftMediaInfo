//
//  MarkdownBuilder.swift
//  SwiftMediaInfo
//
//  One place that turns label/value rows into plain text or GitHub-ready
//  Markdown: Copy Track, Copy Track as Markdown, the Overview's copy actions,
//  the Media Health report and the Markdown export (ReportDocument) all go
//  through here, so everything out of the app is escaped and laid out the
//  same way.
//

import Foundation

enum MarkdownBuilder {

    typealias Row = (label: String, value: String)

    // MARK: Markdown

    /// A heading followed by a two-column table.
    ///
    ///     ### Video
    ///
    ///     | Field | Value |
    ///     | --- | --- |
    ///     | Format | HEVC |
    static func section(_ title: String, rows: [Row], level: Int = 3) -> String {
        heading(title, level: level) + "\n\n" + table(rows: rows)
    }

    static func heading(_ text: String, level: Int = 3) -> String {
        String(repeating: "#", count: min(max(level, 1), 6)) + " " + inline(text)
    }

    /// A GitHub-flavoured table. Values are wrapped in nothing — a code span
    /// would stop GitHub wrapping long encoder settings and push the table off
    /// the right-hand edge.
    static func table(rows: [Row], headers: (String, String) = ("Field", "Value")) -> String {
        var lines = [
            "| \(cell(headers.0)) | \(cell(headers.1)) |",
            "| --- | --- |"
        ]
        for row in rows {
            lines.append("| \(cell(row.label)) | \(cell(row.value)) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Makes text safe inside a table cell: pipes would end the cell, and a
    /// line break would end the whole table.
    static func cell(_ text: String) -> String {
        let escaped = inline(text).replacingOccurrences(of: "|", with: "\\|")
        let lines = escaped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? " " : lines.joined(separator: "<br>")
    }

    /// Escapes only what would really change how metadata renders: a
    /// backtick or asterisk starting formatting, or angle brackets read as
    /// HTML. Underscores and brackets are left alone — GitHub doesn't treat
    /// "movie_hdr.mkv" as italics, and a backslash in every file name would
    /// make the raw text ugly for anyone reading it unrendered.
    static func inline(_ text: String) -> String {
        var result = ""
        for char in text {
            if "\\`*<>".contains(char) { result.append("\\") }
            result.append(char)
        }
        return result
    }

    // MARK: Plain text

    /// The title on its own line, then labels padded to a common width so the
    /// values line up when pasted into a monospaced context — a ticket, a
    /// commit message, a chat window.
    static func plainSection(_ title: String, rows: [Row]) -> String {
        let widest = rows.map(\.label.count).max() ?? 0
        let body = rows.map { row in
            let padding = String(repeating: " ", count: max(0, widest - row.label.count))
            return "\(row.label)\(padding)  \(row.value)"
        }
        return ([title] + body).joined(separator: "\n")
    }
}
