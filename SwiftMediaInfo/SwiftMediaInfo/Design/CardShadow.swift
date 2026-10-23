//
//  CardShadow.swift
//  SwiftMediaInfo
//
//  The glass cards' drop shadow, drawn by Core Animation (used by
//  SMIGlassSurface in DesignSystem; the shared view plumbing is
//  CardDecorationView).
//
//  SwiftUI's `.shadow` on a card works out the shadow from everything in the
//  card — every row of text, through the card's rounded clip — and does it
//  again on every frame the card moves. Scrolling a long Easy View kept the
//  GPU about 80 % busy, most of it on these shadows and clips.
//
//  This draws the same shadow once, into an image, from the card's outline,
//  and lets Core Animation move the image with the card. Cards bigger than a
//  small template share one image stretched along its straight edges (a
//  nine-slice); smaller ones get an image of their own size. Colour, blur,
//  offset and how much shows through the glass were all fitted on screen
//  against SwiftUI's shadow, in light and dark mode.
//

import SwiftUI
import AppKit

struct CardShadow: NSViewRepresentable {
    var cornerRadius: CGFloat
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    func makeNSView(context: Context) -> CardShadowView { CardShadowView() }

    func updateNSView(_ view: CardShadowView, context: Context) {
        view.configure(cornerRadius: cornerRadius, color: NSColor(color), radius: radius, y: y)
    }
}

final class CardShadowView: CardDecorationView {
    /// The shadow, pre-drawn with the card's interior cut out.
    private let slab = CALayer()
    private var color = NSColor.clear
    private var cornerRadius: CGFloat = 0
    private var radius: CGFloat = 0
    private var y: CGFloat = 0
    private var drawnKey: ImageKey?

    override init(frame: NSRect) {
        super.init(frame: frame)
        slab.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "contentsCenter": NSNull()]
        layer?.addSublayer(slab)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(cornerRadius: CGFloat, color: NSColor, radius: CGFloat, y: CGFloat) {
        guard color != self.color || cornerRadius != self.cornerRadius
                || radius != self.radius || y != self.y else { return }
        self.color = color
        self.cornerRadius = cornerRadius
        self.radius = radius
        self.y = y
        redraw()
    }

    // MARK: Drawing

    /// Core Graphics' blur for the same softness as SwiftUI's shadow radius.
    /// Both of these were fitted on screen against the SwiftUI shadow, in
    /// light and dark, to within one or two levels.
    private static let blurPerRadius: CGFloat = 2

    /// How much of the shadow shows through the glass. SwiftUI cast the
    /// shadow from the glass's own opacity — more in dark mode, where the
    /// glass carries a dark scrim — and the glass sat on top of it.
    private static func showThrough(isDark: Bool) -> CGFloat { isDark ? 0.75 : 0.25 }

    override func redraw() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = (color.usingColorSpace(.sRGB) ?? color).cgColor
        }
        let blur = radius * Self.blurPerRadius
        let margin = ceil(blur * 1.5 + abs(y) + 2)
        // Along any direction where the card is longer than this, its edges
        // have a straight stretch whose shadow is the same all along it, so a
        // small image stretched in the middle draws it exactly — in both
        // directions for most cards (a nine-slice), or just across for a
        // wide, short one such as a closed card.
        let template = ceil((cornerRadius * 1.6 + margin) * 2 + 2)
        let stretchesX = bounds.width >= template
        let stretchesY = bounds.height >= template
        let card = CGSize(width: stretchesX ? template : bounds.width,
                          height: stretchesY ? template : bounds.height)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let inside = Self.showThrough(isDark: isDark)
        let key = ImageKey(card: card, margin: margin, cornerRadius: cornerRadius,
                           color: resolved.components ?? [], blur: blur, y: y, scale: scale, inside: inside)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slab.frame = bounds.insetBy(dx: -margin, dy: -margin)
        if key != drawnKey {
            slab.contents = Self.image(key, color: resolved)
            slab.contentsScale = scale
            drawnKey = key
        }
        let w = card.width + margin * 2, h = card.height + margin * 2
        slab.contentsCenter = CGRect(
            x: stretchesX ? (w / 2 - 1) / w : 0,
            y: stretchesY ? (h / 2 - 1) / h : 0,
            width: stretchesX ? 2 / w : 1,
            height: stretchesY ? 2 / h : 1
        )
        CATransaction.commit()
    }

    /// Everything an image depends on. Cards of the same kind share images.
    private struct ImageKey: Hashable {
        var card: CGSize
        var margin: CGFloat
        var cornerRadius: CGFloat
        var color: [CGFloat]
        var blur: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var inside: CGFloat
    }

    private static var cache: [ImageKey: CGImage] = [:]

    /// The shadow of a card of size `card`, `margin` points of room around
    /// it, with only `inside` of it left under the card.
    private static func image(_ key: ImageKey, color: CGColor) -> CGImage? {
        if let hit = cache[key] { return hit }
        let (card, margin, cornerRadius, blur, y, scale, inside) =
            (key.card, key.margin, key.cornerRadius, key.blur, key.y, key.scale, key.inside)

        let size = CGSize(width: card.width + margin * 2, height: card.height + margin * 2)
        let pw = Int(ceil(size.width * scale)), ph = Int(ceil(size.height * scale))
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Points, top-left origin, like the card.
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        let outline = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: CGRect(x: margin, y: margin, width: card.width, height: card.height)).cgPath

        // The shadow alone: the shape is drawn off to the right, beyond the
        // canvas, and its shadow is offset back by the same distance. Shadow
        // offsets and blur are in device pixels, with y pointing up.
        let away = size.width + blur * 4 + 10
        ctx.setShadow(offset: CGSize(width: -away * scale, height: -y * scale), blur: blur * scale, color: color)
        ctx.translateBy(x: away, y: 0)
        ctx.addPath(outline)
        ctx.setFillColor(.black)
        ctx.fillPath()
        ctx.translateBy(x: -away, y: 0)

        // Under the card, only as much as showed through the glass.
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setBlendMode(.destinationIn)
        ctx.addPath(outline)
        ctx.setFillColor(CGColor(gray: 0, alpha: inside))
        ctx.fillPath()

        let image = ctx.makeImage()
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
