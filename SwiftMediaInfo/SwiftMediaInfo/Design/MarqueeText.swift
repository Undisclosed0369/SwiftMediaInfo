//
//  MarqueeText.swift
//  SwiftMediaInfo
//
//  A single line of text that scrolls when it does not fit.
//
//  Used by tabs and Compare Mode's pane headers. Two styles:
//
//    • bounce — scrolls to the end, rests, and comes back. The original
//      behaviour, still used by Compare Mode's File A / File B headers.
//    • loop   — always travels the same way: rests, scrolls left until a
//      second copy of the name has taken the first one's place, and starts
//      again. The jump back is invisible because the two copies are
//      identical. Used by tabs, where several names may be moving at once and
//      everything travelling in one direction at one speed is what makes the
//      bar read as calm rather than busy.
//
//  Both move at a fixed speed in points per second, not over a fixed
//  duration, so a long name and a short one move at exactly the same pace.
//
//  History, kept because each of these was a real bug:
//
//  1. Short names scrolled, because the container width was cached in
//     `onAppear` — which fires before the split view has settled its widths.
//  2. The speed was uneven, because `.repeatForever` re-applies `.delay` on
//     every repetition and interacts badly with autoreversal.
//  3. Then nothing scrolled at all. Measuring with a hidden copy in a
//     `.background` broke once that background sat inside the width-limited
//     frame: the copy was constrained to the container, so it never looked as
//     though it overflowed.
//
//  4. It cost a third of a CPU core while idle. The scroll
//     was a repeating SwiftUI keyframe animation, which SwiftUI advances on
//     the main thread every display frame — re-rendering the whole window's
//     view tree 60–120 times a second for as long as a long name was on
//     screen, even with the app in the background. The scrolling copy is now
//     a Core Animation layer: the movement runs in the system compositor and
//     costs the app nothing, and it pauses while the app is inactive.
//
//  Measurement no longer depends on layout. The text is measured directly
//  against the NSFont AppKit will render it with, which is deterministic and
//  available before the first layout pass.
//

import SwiftUI
import AppKit

struct MarqueeText: View {

    enum Style {
        case bounce
        case loop
    }

    let text: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    var style: Style = .bounce
    /// Where the text sits when it fits and does not need to move.
    var restingAlignment: Alignment = .leading
    /// When false, an overflowing name is shortened in the middle instead of
    /// scrolling. Tabs use this so only the one you are looking at moves.
    var isAnimated: Bool = true
    /// Secondary text colour while scrolling. The resting label takes its
    /// colour from SwiftUI as usual; the scrolling layer can't, so it is
    /// told.
    var isSecondary: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slack before scrolling kicks in, so a name that only just fits stays put.
    private let tolerance: CGFloat = 6
    /// Extra travel past the end so the tail clears the edge cleanly (bounce).
    private let tail: CGFloat = 24
    /// Space between the two copies (loop).
    private let gap: CGFloat = 36
    /// Points per second — slow enough to read while it moves.
    private let speed: CGFloat = 26
    /// How long the text rests before moving again.
    private let pause: Double = 1.6
    /// Width of the soft fade at each edge while scrolling.
    private let fade: CGFloat = 10

    /// Natural width of the text, measured against the font AppKit will use.
    private var textWidth: CGFloat {
        let nsFont = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        let bounds = (text as NSString).size(withAttributes: [.font: nsFont])
        return ceil(bounds.width)
    }

    var body: some View {
        GeometryReader { geo in
            let container = geo.size.width
            let overflows = container > 0 && textWidth > container + tolerance

            Group {
                if overflows && isAnimated && !reduceMotion {
                    scrolling(container: container)
                } else {
                    // Truncate in the middle so the extension stays visible —
                    // on long release names that's usually the useful part.
                    label
                        .truncationMode(.middle)
                        .frame(width: max(container, 0), alignment: restingAlignment)
                }
            }
            .clipped()
        }
        .frame(height: ceil(size * 1.35))
        .clipped()
        .help(text)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
    }

    private func scrolling(container: CGFloat) -> some View {
        MarqueeLayer(
            text: text,
            font: NSFont.systemFont(ofSize: size, weight: weight.nsWeight),
            isSecondary: isSecondary,
            style: style,
            textWidth: textWidth,
            container: container,
            tail: tail, gap: gap, speed: speed, pause: pause, fade: fade
        )
        .frame(width: container, height: ceil(size * 1.35))
        // Read once, by name.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - The scrolling layer

/// The moving copy of the text, animated by Core Animation.
private struct MarqueeLayer: NSViewRepresentable {
    let text: String
    let font: NSFont
    let isSecondary: Bool
    let style: MarqueeText.Style
    let textWidth: CGFloat
    let container: CGFloat
    let tail: CGFloat, gap: CGFloat, speed: CGFloat, pause: Double, fade: CGFloat

    func makeNSView(context: Context) -> MarqueeLayerView { MarqueeLayerView() }

    func updateNSView(_ view: MarqueeLayerView, context: Context) {
        view.configure(self)
    }
}

fileprivate final class MarqueeLayerView: NSView {
    private let strip = CALayer()
    private var copies: [CATextLayer] = []
    private var fadeMask = CAGradientLayer()
    private var signature = ""
    private var fadeWidth: CGFloat = 10
    private var isSecondary = false
    private var observers: [NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(strip)
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = fadeMask

        // Still while the app is in the background: nobody is reading it.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(true) }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPaused(false) }
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override var isFlipped: Bool { true }

    func configure(_ spec: MarqueeLayer) {
        fadeWidth = spec.fade
        isSecondary = spec.isSecondary
        applyColour()

        let key = "\(spec.text)|\(spec.font.pointSize)|\(spec.font.fontName)|\(Int(spec.container))|\(spec.style)"
        guard key != signature else { return }
        signature = key

        copies.forEach { $0.removeFromSuperlayer() }
        copies = []
        strip.removeAllAnimations()

        let count = spec.style == .loop ? 2 : 1
        let lineHeight = ceil(spec.font.ascender - spec.font.descender + spec.font.leading)
        for index in 0..<count {
            let layer = CATextLayer()
            layer.string = spec.text
            layer.font = spec.font
            layer.fontSize = spec.font.pointSize
            layer.truncationMode = .none
            layer.isWrapped = false
            layer.contentsScale = window?.backingScaleFactor ?? 2
            layer.frame = CGRect(x: CGFloat(index) * (spec.textWidth + spec.gap), y: 0,
                                 width: spec.textWidth + 2, height: lineHeight)
            strip.addSublayer(layer)
            copies.append(layer)
        }
        applyColour()
        needsLayout = true

        // Same movement as before: rest, travel at a fixed speed, then either
        // come back (bounce) or snap invisibly to the second copy (loop).
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        switch spec.style {
        case .bounce:
            let distance = max(spec.textWidth - spec.container + spec.tail, 0)
            let travel = max(Double(distance / spec.speed), 1.0)
            let total = spec.pause * 2 + travel * 2
            animation.values = [0, 0, -distance, -distance, 0]
            animation.keyTimes = [0, spec.pause / total, (spec.pause + travel) / total,
                                  (spec.pause * 2 + travel) / total, 1].map { NSNumber(value: $0) }
            animation.duration = total
        case .loop:
            let distance = spec.textWidth + spec.gap
            let travel = Double(distance / spec.speed)
            let total = spec.pause + travel
            animation.values = [0, 0, -distance]
            animation.keyTimes = [0, spec.pause / total, 1].map { NSNumber(value: $0) }
            animation.duration = total
        }
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        strip.add(animation, forKey: "marquee")
        setPaused(!NSApp.isActive)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height = copies.first?.frame.height ?? bounds.height
        strip.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        fadeMask.frame = bounds
        let edge = bounds.width > 0 ? Double(fadeWidth / bounds.width) : 0
        fadeMask.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        copies.forEach { $0.contentsScale = scale }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColour()
    }

    /// Label colours are dynamic; a CGColor isn't, so it is resolved again
    /// whenever the appearance changes.
    private func applyColour() {
        var colour: CGColor = NSColor.labelColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            colour = (isSecondary ? NSColor.secondaryLabelColor : NSColor.labelColor).cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        copies.forEach { $0.foregroundColor = colour }
        CATransaction.commit()
    }

    private func setPaused(_ paused: Bool) {
        guard let layer = Optional(strip) else { return }
        if paused, layer.speed != 0 {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
        } else if !paused, layer.speed == 0 {
            let offset = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - offset
        }
    }
}

// MARK: - Font weight bridging

private extension Font.Weight {
    /// SwiftUI and AppKit weights don't bridge automatically, and measurement
    /// has to use the same weight that will actually be drawn.
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}
