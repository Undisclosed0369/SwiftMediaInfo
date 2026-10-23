//
//  GlassBorder.swift
//  SwiftMediaInfo
//
//  A glass card's gradient edge, drawn by Core Animation (used by
//  SMIGlassSurface when `edgeInLayer` is set; the shared view plumbing is
//  CardDecorationView).
//
//  SwiftUI draws a gradient stroke on the CPU into a bitmap the size of the
//  whole card — the gradient is worked out for every pixel of the card, not
//  only along the hairline — and it throws that bitmap away and draws it
//  again whenever the card's contents change: each row the pointer crosses,
//  each frame of a card opening or closing, each card a long list brings
//  into view. In Easy View that was the largest single cost of hovering and
//  of scrolling with the pointer over the rows.
//
//  The same edge is drawn here as up to eight small pieces — the corners and
//  the straight runs between them — from the outline SwiftUI strokes, with
//  the gradient laid across the whole card exactly as before. The pieces are
//  drawn when the card changes size or colour, never because of what is
//  inside it.
//

import SwiftUI
import AppKit

struct GlassBorder: NSViewRepresentable {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    /// The gradient's colours at the top-leading and bottom-trailing corners.
    var start: Color
    var end: Color

    func makeNSView(context: Context) -> GlassBorderView { GlassBorderView() }

    func updateNSView(_ view: GlassBorderView, context: Context) {
        view.configure(cornerRadius: cornerRadius, lineWidth: lineWidth,
                       start: NSColor(start), end: NSColor(end))
    }
}

final class GlassBorderView: CardDecorationView {
    private var pieces: [CALayer] = []
    private var cornerRadius: CGFloat = 0
    private var lineWidth: CGFloat = 0
    private var start = NSColor.clear
    private var end = NSColor.clear

    func configure(cornerRadius: CGFloat, lineWidth: CGFloat, start: NSColor, end: NSColor) {
        guard cornerRadius != self.cornerRadius || lineWidth != self.lineWidth
                || start != self.start || end != self.end else { return }
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.start = start
        self.end = end
        redraw()
    }

    // MARK: Drawing

    override func redraw() {
        let size = bounds.size
        guard size.width > 0, size.height > 0, lineWidth > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        var colors: [CGColor] = []
        effectiveAppearance.performAsCurrentDrawingAppearance {
            colors = [start, end].map { ($0.usingColorSpace(.sRGB) ?? $0).cgColor }
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors as CFArray, locations: [0, 1])
        else { return }
        // Exactly what `strokeBorder` strokes: the outline inset by half the
        // line width.
        let outline = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: lineWidth / 2)
            .path(in: CGRect(origin: .zero, size: size))
            .cgPath

        let rects = Self.pieces(size: size, scale: scale, cornerRadius: cornerRadius, lineWidth: lineWidth)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while pieces.count < rects.count {
            let piece = CALayer()
            piece.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(piece)
            pieces.append(piece)
        }
        for (index, piece) in pieces.enumerated() {
            guard index < rects.count else {
                piece.contents = nil
                piece.isHidden = true
                continue
            }
            let rect = rects[index]
            piece.isHidden = false
            piece.frame = CGRect(x: rect.minX / scale, y: rect.minY / scale,
                                 width: rect.width / scale, height: rect.height / scale)
            piece.contentsScale = scale
            piece.contents = Self.image(of: rect, outline: outline, lineWidth: lineWidth,
                                        gradient: gradient, card: size, scale: scale)
        }
        CATransaction.commit()
    }

    /// The parts of the card the edge passes through, in device pixels from
    /// the card's top-left corner: its corners, where the outline curves, and
    /// thin runs along the straight sides between them. Seams fall on whole
    /// pixels, so the pieces meet without a gap or an overlap.
    private static func pieces(size: CGSize, scale: CGFloat, cornerRadius: CGFloat, lineWidth: CGFloat) -> [CGRect] {
        let right = ceil(size.width * scale), bottom = ceil(size.height * scale)
        // A continuous corner curves over about 1.53 times its radius.
        let corner = (ceil(cornerRadius * 1.6) + 2) * scale
        // The stroke and its anti-aliasing, along a straight side.
        let edge = (ceil(lineWidth) + 1) * scale

        enum Part { case whole, low, middle, high }
        func spans(_ length: CGFloat) -> [(Part, CGFloat, CGFloat)] {
            length >= corner * 2 + 1
            ? [(.low, 0, corner), (.middle, corner, length - corner), (.high, length - corner, length)]
            : [(.whole, 0, length)]
        }
        /// The strips of a span that hold the edge: one at the low end, one
        /// at the high end, or the whole span if they would meet.
        func runs(_ part: Part, _ length: CGFloat) -> [(CGFloat, CGFloat)] {
            switch part {
            case .low:    return [(0, edge)]
            case .high:   return [(length - edge, length)]
            case .whole:  return length > edge * 2 ? [(0, edge), (length - edge, length)] : [(0, length)]
            case .middle: return []
            }
        }

        var rects: [CGRect] = []
        for (xPart, x0, x1) in spans(right) {
            for (yPart, y0, y1) in spans(bottom) {
                switch (xPart, yPart) {
                case (.middle, .middle):
                    continue
                case (.middle, _):
                    for (a, b) in runs(yPart, bottom) where a >= y0 && b <= y1 {
                        rects.append(CGRect(x: x0, y: a, width: x1 - x0, height: b - a))
                    }
                case (_, .middle):
                    for (a, b) in runs(xPart, right) where a >= x0 && b <= x1 {
                        rects.append(CGRect(x: a, y: y0, width: b - a, height: y1 - y0))
                    }
                default:
                    rects.append(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
                }
            }
        }
        return rects
    }

    /// One piece of the stroked outline, `rect` in device pixels.
    private static func image(of rect: CGRect, outline: CGPath, lineWidth: CGFloat,
                              gradient: CGGradient, card: CGSize, scale: CGFloat) -> CGImage? {
        let pw = Int(rect.width), ph = Int(rect.height)
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The card's own coordinates: points, top-left origin.
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.scaleBy(x: scale, y: scale)

        ctx.addPath(outline)
        ctx.setLineWidth(lineWidth)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        // Top-leading to bottom-trailing of the whole card, as the SwiftUI
        // gradient ran.
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: card.width, y: card.height),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return ctx.makeImage()
    }
}
