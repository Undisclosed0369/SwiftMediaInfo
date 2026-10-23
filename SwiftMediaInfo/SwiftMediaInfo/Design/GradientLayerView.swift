//
//  GradientLayerView.swift
//  SwiftMediaInfo
//
//  The window background's drawing: drawn once, moved in steps. The modes
//  and when it holds still are GradientBackground's (LiquidGlass.swift);
//  where the discs sit in Static is StaticBlobLayout's (DesignSystem.swift).
//
//  WHY
//
//  The animated background was a SwiftUI Canvas inside a TimelineView: twelve
//  times a second SwiftUI re-ran the canvas, re-blurred it and re-diffed the
//  window's view tree on the main thread — about 12 % of a core on an M4 while
//  the app was in front, more on an M1. The picture itself never changes, only
//  where three blurred discs sit.
//
//  So each disc is drawn and blurred once, into an image, and the three
//  images are moved along the same lissajous paths as before, twelve times a
//  second, by a timer that sets three layer positions. The app no longer
//  redraws or re-blurs anything per frame.
//
//  WHY TWELVE, AND WHY A TIMER
//
//  Twelve frames a second is what the Canvas drew, and it matters for more
//  than the background itself: every frame the background moves, each glass
//  panel in the window re-blurs what's behind it. A Core Animation animation
//  would run at the display's own rate — 120 Hz on a ProMotion screen — and
//  measured at nearly twice the GPU time of the twelve-frame Canvas; Core
//  Animation doesn't honour a lower preferred rate here. A timer stepping the
//  positions keeps the original twelve.
//

import SwiftUI
import AppKit
import CoreImage

struct GradientLayerView: NSViewRepresentable {
    var colors: [NSColor]
    /// Moving, or held still.
    var isAnimating: Bool
    /// When non-nil, the discs sit here and never move (Static): one point
    /// per disc, as fractions of the view's width and height.
    var staticPositions: [CGPoint]?

    func makeNSView(context: Context) -> GradientLayerHost { GradientLayerHost() }

    func updateNSView(_ view: GradientLayerHost, context: Context) {
        view.update(colors: colors, isAnimating: isAnimating, staticPositions: staticPositions)
    }
}

final class GradientLayerHost: NSView {
    /// Same constants as the Canvas this replaces.
    private static let speed = 0.45
    private static let opacity: CGFloat = 0.28
    private static let blur: CGFloat = 80
    /// Images are drawn at a quarter of their size — they are blurred by
    /// 80 points, so there is no detail for the lower resolution to lose.
    private static let imageScale: CGFloat = 0.25
    /// Frames per second while moving — the Canvas's twelve.
    private static let frameRate: Double = 12
    /// Reused: creating a Core Image context is the slow part of a redraw.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private let blobs = [CALayer(), CALayer(), CALayer()]
    private var colors: [NSColor] = []
    private var isAnimating = false
    private var staticPositions: [CGPoint]?
    private var imageSize: CGSize = .zero
    private var imageColors: [NSColor] = []
    private var redraw: DispatchWorkItem?
    private var ticker: Timer?

    /// Drift time is wall-clock time minus every second spent paused, so the
    /// discs carry on from exactly where they stopped.
    private var pausedTotal: Double = 0
    private var pausedAt: Double?
    private var driftNow: Double {
        (pausedAt ?? Date().timeIntervalSinceReferenceDate) - pausedTotal
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        for blob in blobs {
            blob.contentsGravity = .resize
            blob.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
            layer?.addSublayer(blob)
        }
        pausedAt = Date().timeIntervalSinceReferenceDate
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        ticker?.invalidate()
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // No window, nothing to draw for: stop the timer with it.
        if window == nil { ticker?.invalidate(); ticker = nil } else { setAnimating(isAnimating, force: true) }
    }

    func update(colors: [NSColor], isAnimating: Bool, staticPositions: [CGPoint]?) {
        let colorsChanged = colors != self.colors
        let positionsChanged = staticPositions != self.staticPositions
        self.colors = colors
        self.staticPositions = staticPositions
        if colorsChanged { drawImages() }
        if positionsChanged { place() }
        setAnimating(isAnimating && staticPositions == nil)
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Positions follow every step of a live resize, as the Canvas did;
        // the images stretch meanwhile (they are blurred, so it doesn't show)
        // and are redrawn at the right size once the resize settles.
        place()
        guard bounds.size != imageSize else { return }
        redraw?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.drawImages() }
        redraw = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (imageSize == .zero ? 0 : 0.15), execute: item)
    }

    // MARK: Building

    /// Where disc `index` sits at path time `t`, as fractions of the view's
    /// width and height (0 at the top left).
    static func unitCentre(_ index: Int, t: Double) -> CGPoint {
        switch index {
        case 0:  return CGPoint(x: 0.3 + 0.25 * sin(t),          y: 0.3 + 0.2 * cos(t * 0.7))
        case 1:  return CGPoint(x: 0.7 + 0.2 * cos(t * 0.9),     y: 0.6 + 0.25 * sin(t * 1.1))
        default: return CGPoint(x: 0.5 + 0.3 * sin(t * 0.6 + 1), y: 0.2 + 0.3 * cos(t * 0.8 + 0.5))
        }
    }

    /// The speed the drift runs at — path time is seconds times this.
    static var driftSpeed: Double { speed }

    /// Radius of disc `index` as a fraction of the view's shorter side.
    static let radiusFractions: [CGFloat] = [0.55, 0.5, 0.45]
    static var blurRadius: CGFloat { blur }
    static var discOpacity: CGFloat { opacity }

    private static func radius(_ index: Int, size: CGSize) -> CGFloat {
        min(size.width, size.height) * radiusFractions[index]
    }

    private static func side(_ index: Int, size: CGSize) -> CGFloat {
        (radius(index, size: size) + blur * 3) * 2
    }

    /// The three disc images, for the current size and colours.
    private func drawImages() {
        let size = bounds.size
        guard size.width > 0, size.height > 0, !colors.isEmpty else { return }
        guard size != imageSize || colors != imageColors else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, blob) in blobs.enumerated() {
            blob.contents = Self.discImage(
                radius: Self.radius(index, size: size),
                side: Self.side(index, size: size),
                colour: colors[index % colors.count]
            )
        }
        CATransaction.commit()
        imageSize = size
        imageColors = colors
    }

    /// Sizes and positions the discs for the current moment.
    private func place() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let t = driftNow * Self.speed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, blob) in blobs.enumerated() {
            let side = Self.side(index, size: size)
            let unit = staticPositions.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                ?? Self.unitCentre(index, t: t)
            blob.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            blob.position = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
        }
        CATransaction.commit()
    }

    /// One disc, filled at the canvas's opacity and blurred as the Canvas
    /// version was, drawn small.
    private static func discImage(radius: CGFloat, side: CGFloat, colour: NSColor) -> CGImage? {
        let s = imageScale
        let px = Int(ceil(side * s))
        guard px > 0,
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        ctx.setFillColor(rgb.withAlphaComponent(opacity).cgColor)
        let r = radius * s, c = CGFloat(px) / 2
        ctx.fillEllipse(in: CGRect(x: c - r, y: c - r, width: r * 2, height: r * 2))
        guard let disc = ctx.makeImage() else { return nil }

        let input = CIImage(cgImage: disc)
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(blur * s))
            .cropped(to: input.extent)
        return ciContext.createCGImage(blurred, from: input.extent)
    }

    // MARK: Pausing

    /// Held still where it is (app inactive, scrolling, Low Power Mode,
    /// Reduce Motion), and carried on from there.
    private func setAnimating(_ animating: Bool, force: Bool = false) {
        guard animating != isAnimating || force else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if animating != isAnimating {
            if animating {
                if let pausedAt { pausedTotal += now - pausedAt }
                pausedAt = nil
            } else {
                pausedAt = now
            }
            isAnimating = animating
        }
        ticker?.invalidate()
        ticker = nil
        guard animating, window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / Self.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
