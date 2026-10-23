//
//  CardDecorationView.swift
//  SwiftMediaInfo
//
//  What a glass card's Core Animation decorations share:
//  the shadow beneath it (CardShadow) and the gradient edge around it
//  (GlassBorder). Each is a layer-hosting view that takes no clicks and is
//  redrawn only when the card's size, the screen's resolution or the
//  appearance changes — never because of what is inside the card.
//

import AppKit

class CardDecorationView: NSView {
    private var laidOutSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-hosting, so AppKit leaves the layers alone.
        let host = CALayer()
        host.isGeometryFlipped = true
        layer = host
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    // Decoration only: clicks and hovers belong to the card itself.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        // Layout passes come often while scrolling; only a new size matters.
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        redraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redraw()
    }

    /// Draws the decoration for the current size, scale and appearance.
    func redraw() {}
}
