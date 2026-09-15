//
//  DesignSystem.swift
//  SwiftMediaInfo
//
//  PHASE 2 — the single source of truth for how SwiftMediaInfo looks and moves.
//
//  Nothing in this file draws anything. It defines the vocabulary: colour,
//  type, spacing, corner radii, elevation, and motion. Every view built from
//  Phase 2 onward reads from here rather than hard-coding values, which is what
//  keeps the app feeling like one deliberate piece of design instead of a set
//  of screens that happen to share a window.
//
//  Two rules for using it:
//
//    1. No raw numbers in view code. If you need a size, a gap, or a radius,
//       it belongs here first. If a value only ever gets used once, that's fine
//       — naming it is still worth more than inlining it.
//
//    2. No raw `.animation()` calls. Use `.smiAnimation(_:value:)` so Reduce
//       Motion is honoured automatically. Same for glass surfaces and Reduce
//       Transparency.
//
//  Accessibility is built in here rather than retrofitted in Phase 11, because
//  retrofitting it means auditing every view twice.
//

import SwiftUI
import AppKit

// MARK: - Namespace

/// Design tokens. Namespaced so autocomplete stays useful and nothing collides
/// with SwiftUI's own vocabulary.
enum SMI {}

// MARK: - Spacing
//
// A 2pt-based scale. Using a fixed set of steps rather than arbitrary numbers
// is what makes unrelated parts of the UI feel aligned without anyone measuring.

extension SMI {
    enum Spacing {
        /// 2pt — hairline separation, badge internals
        static let hair: CGFloat = 2
        /// 4pt — tightly related elements
        static let tight: CGFloat = 4
        /// 6pt — icon to label
        static let snug: CGFloat = 6
        /// 8pt — default gap between siblings
        static let small: CGFloat = 8
        /// 12pt — grouped content
        static let medium: CGFloat = 12
        /// 16pt — standard container padding
        static let large: CGFloat = 16
        /// 20pt — section padding
        static let xLarge: CGFloat = 20
        /// 24pt — separation between sections
        static let xxLarge: CGFloat = 24
        /// 32pt — major structural breaks
        static let huge: CGFloat = 32
    }
}

// MARK: - Corner radii
//
// Every rounded rectangle uses `.continuous` style. macOS uses continuous
// (squircle) corners system-wide; circular corners read as subtly wrong next
// to native chrome, and that wrongness is one of those things people feel
// without being able to name.

extension SMI {
    enum Radius {
        /// 6pt — chips, inline highlights
        static let chip: CGFloat = 6
        /// 10pt — field rows, small controls
        static let control: CGFloat = 10
        /// 14pt — buttons, grouped toolbar clusters
        static let button: CGFloat = 14
        /// 18pt — cards, tab bar
        static let card: CGFloat = 18
        /// 24pt — sheets, large panels
        static let panel: CGFloat = 24
    }
}

// MARK: - Fixed metrics
//
// Sizes that exist to make separate controls agree with each other, rather
// than to express a scale.

extension SMI {
    enum Metrics {
        /// Height reserved for a toolbar button's icon.
        ///
        /// SF Symbols do not share a common height — `play.rectangle` is
        /// shorter than `doc.badge.plus`, and `doc.badge.ellipsis` shorter
        /// again. In a centred icon-over-label stack that difference moves the
        /// *label*, so three buttons sitting side by side ended up with their
        /// text on three different baselines. Reserving one height for every
        /// icon puts every label back on the same line.
        static let toolbarIcon: CGFloat = 26
    }
}

// MARK: - Typography
//
// A closed scale. SF Pro for everything structural, SF Mono for metadata
// values, SF Rounded for numerics that read as data rather than prose
// (zoom percentage, match counts, diff totals).
//
// Values that the user might want to compare vertically — bit rates, sizes,
// durations — use mono so digits align in a column. That single choice does
// more for the "professional tool" feeling than any amount of glass.

extension SMI {
    enum Typo {
        /// 26 semibold — empty-state headline, About
        static let display = Font.system(size: 26, weight: .semibold)
        /// 20 semibold — window/section titles
        static let title = Font.system(size: 20, weight: .semibold)
        /// 15 semibold — card headers
        static let headline = Font.system(size: 15, weight: .semibold)
        /// 13 semibold — emphasised body
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        /// 13 medium — labels
        static let label = Font.system(size: 13, weight: .medium)
        /// 13 regular — body copy
        static let body = Font.system(size: 13)
        /// 12 medium — button labels, secondary rows
        static let callout = Font.system(size: 12, weight: .medium)
        /// 11 medium — captions, helper text
        static let caption = Font.system(size: 11, weight: .medium)
        /// 10 bold — badges, pills
        static let micro = Font.system(size: 10, weight: .bold)
        
        /// Monospaced metadata value at the user's current zoom size.
        static func value(_ size: Double) -> Font {
            .system(size: CGFloat(size), design: .monospaced)
        }
        
        /// Field label at the user's current zoom size.
        static func fieldLabel(_ size: Double) -> Font {
            .system(size: CGFloat(size), weight: .medium)
        }
        
        /// Rounded numeric display — counters, percentages.
        static func numeric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }
}

// MARK: - Palette
//
// The brand colours stay exactly as they were. What's new is a semantic layer
// on top, so views ask for "the colour of an audio track" rather than
// "purple". When the meaning of a colour changes, it changes in one place.

extension Color {
    /// Violet  #8d42f5
    static let brandViolet = Color(red: 0.553, green: 0.259, blue: 0.961)
    /// Pink    #e042f5
    static let brandPink   = Color(red: 0.878, green: 0.259, blue: 0.961)
    /// Blue    #42a1f5
    static let brandBlue   = Color(red: 0.259, green: 0.631, blue: 0.961)
    /// Green   #42f566
    static let brandGreen  = Color(red: 0.259, green: 0.961, blue: 0.400)
    /// Teal    #42e0f5 — derived, fills the gap between blue and green
    static let brandTeal   = Color(red: 0.259, green: 0.878, blue: 0.961)
    /// Amber   #f5a142 — derived, reserved for "changed" and warnings
    static let brandAmber  = Color(red: 0.961, green: 0.631, blue: 0.259)
}

// MARK: - Hex colour
//
// PHASE 12b. Needed because the background colours are now user-chosen, and a
// preference has to survive a relaunch as text. A colour picker hands back a
// `Color`; user defaults store strings.
//
// sRGB is pinned explicitly on the way out. Without that, a colour picked from
// a wide-gamut display would round-trip through a different colour space and
// come back subtly wrong — a preference that quietly shifts every time it is
// saved and reloaded.

extension Color {
    /// Parses "#8d42f5" or "8d42f5". Returns nil on anything malformed, so a
    /// corrupted preference falls back to a default rather than crashing.
    init?(smiHex: String) {
        var s = smiHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        
        self.init(
            .sRGB,
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8)  & 0xFF) / 255.0,
            blue:  Double(v         & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
    
    var smiHex: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        
        return String(
            format: "#%02X%02X%02X",
            Int((ns.redComponent   * 255).rounded()),
            Int((ns.greenComponent * 255).rounded()),
            Int((ns.blueComponent  * 255).rounded())
        )
    }
}

// MARK: - Background mode
//
// PHASE 12b. Replaces the old `showAnimatedBackground` boolean, which could
// only say "moving" or "nothing at all".
//
// The middle option turned out to be the one worth having. A static gradient
// keeps every visual property that matters — the glass still picks up colour,
// the window still has depth — while setting the frame count to one. That
// matters more than any other optimisation in this phase, because the reason
// the app was expensive was never the background on its own: it was that every
// frosted panel had to re-sample a backdrop that would not sit still.
//
// Freeze the backdrop and that recomputation stops, everywhere, permanently.
//
// It ships as the default for a second reason that has nothing to do with
// speed. A thing you switch on feels like a feature; the same thing on by
// default feels like something you have to switch off.

enum BackgroundMode: String, CaseIterable, Identifiable {
    /// No gradient. Glass panels have nothing to tint against and read grey.
    case off
    /// Drawn once, never redrawn.
    case staticGradient
    /// The slow drift.
    case animated
    
    var id: String { rawValue }
    
    static let key = "backgroundMode"
    
    static let shippedDefault: BackgroundMode = .staticGradient
    
    var title: String {
        switch self {
        case .off:            return "Off"
        case .staticGradient: return "Static"
        case .animated:       return "Animated"
        }
    }
    
    var explanation: String {
        switch self {
        case .off:
            return "No gradient at all. Glass panels have nothing to pick up colour from, so they read as grey."
        case .staticGradient:
            return "The colour wash is drawn once and held still. Identical to Animated at a glance, and costs nothing to keep on screen."
        case .animated:
            return "The wash drifts slowly. The most expensive option, because every glass panel has to keep up with it."
        }
    }
    
    static var current: BackgroundMode {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let mode = BackgroundMode(rawValue: raw) else { return shippedDefault }
        return mode
    }
}

// MARK: - Background palette
//
// PHASE 12b. The three blob colours, user-chosen, defaulting to the brand set.
//
// Three rather than two: two blobs across a wide window leaves an obvious gap
// in the middle, and the composition stops reading as a wash and starts reading
// as two lumps. Three is the smallest number that fills a landscape window.
//
// Stored as hex strings under one key each, so a single corrupted value costs
// one colour rather than the whole palette.

// MARK: - Gradient presets
//
// PHASE 13l. Four ready-made palettes, so choosing a background does not have
// to begin with three colour pickers and a blank stare.
//
// WHY PRESETS AT ALL
//
// The custom pickers arrived first and they are the more powerful feature, but
// power is not the same as usefulness. Picking three colours that look good
// together is a real skill, and the failure mode is not "slightly worse than
// the default" — it is a muddy wash that makes the glass look broken and the
// app look cheap. A preset is a way to get a considered answer in one click
// and still keep the pickers for anyone who wants them.
//
// WHY THESE FOUR
//
// They are not arbitrary. Each is built from the app's own brand colours, and
// each covers a different temperature so the set spans the range rather than
// offering four variations of violet:
//
//   Signature — violet, pink, blue. The shipped default.
//   Tide      — blue, teal, violet. Cool.
//   Meadow    — green, teal, blue. Cooler still, and the only one without pink.
//   Ember     — pink, amber, violet. Warm, and the only use of amber here.
//
// These are the same four the website shows. That is deliberate: someone who
// saw them on the site should find them named the same way in the app, and
// deriving both from one list is how that stays true.

enum GradientPreset: String, CaseIterable, Identifiable {
    case signature
    case tide
    case meadow
    case ember
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .signature: return "Signature"
        case .tide:      return "Tide"
        case .meadow:    return "Meadow"
        case .ember:     return "Ember"
        }
    }
    
    var colors: [Color] {
        switch self {
        case .signature: return [.brandViolet, .brandPink, .brandBlue]
        case .tide:      return [.brandBlue, .brandTeal, .brandViolet]
        case .meadow:    return [.brandGreen, .brandTeal, .brandBlue]
        case .ember:     return [.brandPink, .brandAmber, .brandViolet]
        }
    }
    
    var hexes: [String] { colors.map(\.smiHex) }
    
    /// Which preset, if any, the current palette matches.
    ///
    /// Compared case-insensitively because a hex written by the colour picker
    /// and one written by this file should count as the same colour even if
    /// one says `#8D42F5` and the other `#8d42f5`.
    static func matching(_ hexes: [String]) -> GradientPreset? {
        let normalised = hexes.map { $0.uppercased() }
        return allCases.first { $0.hexes.map { $0.uppercased() } == normalised }
    }
}

enum BackgroundPalette {
    static let keys = ["backgroundColor1", "backgroundColor2", "backgroundColor3"]
    
    /// Derived from the Signature preset rather than listed again. Two lists of
    /// the same three colours is two places to change and one to forget.
    static let defaults: [Color] = GradientPreset.signature.colors
    
    /// Reads all three, substituting the brand colour for anything missing or
    /// malformed. Always returns exactly three.
    static var current: [Color] {
        keys.enumerated().map { index, key in
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let color = Color(smiHex: raw) else { return defaults[index] }
            return color
        }
    }
    
    static func reset() {
        for (index, key) in keys.enumerated() {
            UserDefaults.standard.set(defaults[index].smiHex, forKey: key)
        }
    }
}

extension SMI {
    enum Palette {
        
        // MARK: Track kinds
        //
        // Previously these were stock SwiftUI colours (.blue, .purple, .teal…)
        // while the rest of the app used the brand palette, so Easy View looked
        // like it belonged to a different application. These map each track
        // type onto the brand spectrum instead.
        
        static func track(_ type: String) -> Color {
            switch type {
            case "General": return .secondary
            case "Video":   return .brandBlue
            case "Audio":   return .brandViolet
            case "Text":    return .brandGreen
            case "Image":   return .brandTeal
            case "Menu":    return .brandPink
            default:        return .secondary
            }
        }
        
        // MARK: View modes
        
        static func viewMode(_ mode: ViewMode) -> Color {
            switch mode {
            case .easy:    return .brandBlue
            case .text:    return .brandViolet
            case .rawText: return .brandPink
            case .html:    return .brandGreen
            case .xml:     return .brandTeal
            case .json:    return .brandViolet
            }
        }
        
        // MARK: Comparison
        //
        // Kept deliberately close to the existing diff colours so muscle memory
        // built in v1.5 still works. Amber replaces raw orange for consistency.
        
        /// A field whose value differs between the two files
        static let diffModified = Color.brandAmber
        /// A field present only in File A
        static let diffOnlyInA  = Color.brandBlue
        /// A field present only in File B
        static let diffOnlyInB  = Color.brandPink
        
        // MARK: Status
        
        static let success = Color.brandGreen
        static let warning = Color.brandAmber
        static let danger  = Color(red: 0.961, green: 0.31, blue: 0.38)
        static let info    = Color.brandBlue
        
        // MARK: Surfaces
        
        /// Solid fallback used when Reduce Transparency is on.
        static var solidSurface: Color { Color(nsColor: .controlBackgroundColor) }
        /// Hairline separator.
        static var separator: Color { Color(nsColor: .separatorColor) }
        
        /// Zebra striping for alternating field rows. Deliberately very low
        /// contrast — it should guide the eye without being noticed.
        static let rowAlternate = Color.primary.opacity(0.035)
        
        /// Hover wash for interactive rows and buttons.
        static let hoverWash = Color.primary.opacity(0.07)
    }
}

// MARK: - Gradients

extension LinearGradient {
    /// Blue → Violet diagonal
    static let brandBlueViolet = LinearGradient(
        colors: [.brandBlue, .brandViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Full spectrum (decorative)
    static let brandSpectrum = LinearGradient(
        colors: [.brandBlue, .brandViolet, .brandPink],
        startPoint: .leading,
        endPoint: .trailing
    )
    /// Success sweep — used for copy confirmation
    static let brandSuccess = LinearGradient(
        colors: [.brandTeal, .brandGreen],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    /// A sweep tinted to an arbitrary accent, for per-context flourishes.
    static func brandSweep(_ accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [accent, accent.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Elevation

extension SMI {
    /// Shadow presets. Kept shallow and tinted rather than grey — a neutral
    /// drop shadow under a coloured glass panel reads as muddy.
    enum Elevation {
        struct Shadow {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }
        
        /// Resting state — barely there.
        static func resting(_ tint: Color) -> Shadow {
            Shadow(color: tint.opacity(0.10), radius: 8, y: 2)
        }
        /// Raised — cards, toolbars.
        static func raised(_ tint: Color) -> Shadow {
            Shadow(color: tint.opacity(0.14), radius: 14, y: 5)
        }
        /// Floating — popovers, sheets, search bar.
        static func floating(_ tint: Color) -> Shadow {
            Shadow(color: tint.opacity(0.20), radius: 26, y: 10)
        }
    }
}

extension View {
    func smiShadow(_ shadow: SMI.Elevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}

// MARK: - Motion
//
// A small closed set of animations, each with a stated purpose. The point of
// limiting them is that consistent timing is most of what "polished" means —
// when every transition in an app shares a rhythm, it feels authored.

extension SMI {
    enum Motion {
        /// Immediate tactile feedback — button presses, toggles.
        static let snap = Animation.spring(response: 0.26, dampingFraction: 0.86)
        
        /// Layout changes — panes resizing, content swapping.
        static let smooth = Animation.spring(response: 0.38, dampingFraction: 0.82)
        
        /// Elements arriving or leaving — sheets, popovers, overlays.
        static let flourish = Animation.spring(response: 0.48, dampingFraction: 0.74)
        
        /// Pure opacity or colour changes where springiness would look wrong.
        static let fade = Animation.easeInOut(duration: 0.22)
        
        /// Slow ambient motion — background gradient, shimmer.
        static let ambient = Animation.easeInOut(duration: 1.6)
        
        /// What every animation collapses to when Reduce Motion is enabled.
        /// Not zero — an instant jump reads as a glitch. A very short fade
        /// preserves cause-and-effect without any spatial movement.
        static let reduced = Animation.easeOut(duration: 0.12)
    }
}

// MARK: - Accessibility
//
// PHASE 11 adds a small vocabulary on top of the Phase 2 hooks.
//
// The Phase 2 work made the app *respect* accessibility settings — Reduce
// Motion and Reduce Transparency are honoured at the token level. What it did
// not do is make the app *describe itself*, which is a different job: a
// VoiceOver user needs every control to say what it is, decorative chrome to
// stay silent, and anything that changes on its own to announce itself.
//
// Three tools cover almost all of that, and they live here so the wording and
// the behaviour are decided once rather than at each call site.

extension SMI {
    /// Spoken feedback for things that happen without the user moving focus.
    ///
    /// A copy button that turns green says "it worked" to someone watching it.
    /// To someone listening, nothing happened at all — focus never moved, so
    /// VoiceOver has no reason to say anything. An announcement is the audible
    /// equivalent of the green flash.
    ///
    /// This uses AppKit's notification directly rather than SwiftUI's
    /// `AccessibilityNotification`, because the AppKit call has been stable on
    /// macOS for a decade and takes an explicit priority, which matters: a
    /// low-priority announcement is silently dropped if VoiceOver is mid-
    /// sentence, and "Copied" arriving late is worse than not arriving.
    enum A11y {
        @MainActor
        static func announce(
            _ message: String,
            priority: NSAccessibilityPriorityLevel = .high
        ) {
            guard !message.isEmpty else { return }
            
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: priority.rawValue
                ]
            )
        }
    }
    
    /// System accessibility state, readable from outside a View body — needed
    /// wherever `withAnimation` is called from a model rather than a view.
    enum Access {
        @MainActor
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        
        @MainActor
        static var reduceTransparency: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }
}

/// `withAnimation`, but Reduce Motion aware. Use this instead of the bare
/// SwiftUI function anywhere outside a view body.
@MainActor
func smiWithAnimation<Result>(
    _ animation: Animation,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(SMI.Access.reduceMotion ? SMI.Motion.reduced : animation, body)
}

private struct SMIAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? SMI.Motion.reduced : animation, value: value)
    }
}

extension View {
    /// Animate a value change, collapsing to a brief fade under Reduce Motion.
    func smiAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(SMIAnimationModifier(animation: animation, value: value))
    }
    
    // MARK: Accessibility spellings
    //
    // Thin wrappers, on purpose. They cost nothing at runtime and they make the
    // intent legible in the view code: `.smiDecorativeChrome()` says "this is
    // scenery" in a way that a bare `.accessibilityHidden(true)` does not, and
    // if the right answer ever changes it changes in one place.
    
    /// Marks purely decorative chrome — gradients, glows, dividers, spacers
    /// with a shape — as invisible to assistive technology.
    ///
    /// Anything that carries no information should be hidden rather than
    /// labelled. An unlabelled image is read out as "image", which is noise;
    /// a labelled decorative image is worse, because it is noise that sounds
    /// like it matters.
    func smiDecorativeChrome() -> some View {
        accessibilityHidden(true)
    }
    
    /// Collapses a cluster of text and icons into a single spoken element.
    ///
    /// A status chip is one idea drawn as two views. Left alone, VoiceOver
    /// stops on the icon, says "image", then stops again on the text. Combined,
    /// it is one stop that says the whole thing.
    func smiReadAsOne(_ label: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

// MARK: - Glass surface
//
// The core surface treatment. Three things make it environment-aware:
//
//   1. Colour scheme. In dark mode the frosted material sits over a bright
//      animated gradient and comes out far too light — panels read as pale
//      lavender rather than dark glass. A black scrim restores depth, and the
//      specular highlight is pulled back because a bright top edge on a dark
//      surface looks like a rendering artefact rather than a reflection.
//
//   2. Reduce Transparency. Blur is replaced with a solid fill and the border
//      is strengthened, because once translucency is gone the edge is the only
//      thing defining the panel's shape.
//
//   3. The Liquid Glass preference. Real-time blur is genuinely expensive —
//      measured at roughly 28% → 40% CPU on an M4 mini. Users who want the
//      cheaper rendering take the same path as Reduce Transparency.

/// Master switch for the glass treatment. Read directly by the surface modifier
/// so nothing needs to thread it through the view hierarchy.
/// Exposed as a control in Settings (Phase 6).
enum GlassPreference {
    static let key = "liquidGlassEnabled"
    
    static var isEnabled: Bool {
        // Defaults to true when never set, matching existing behaviour.
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

struct SMIGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var borderOpacity: Double
    var shadow: SMI.Elevation.Shadow?
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(GlassPreference.key) private var glassEnabled: Bool = true
    
    private var isFlat: Bool { reduceTransparency || !glassEnabled }
    private var isDark: Bool { colorScheme == .dark }
    
    func body(content: Content) -> some View {
        content
            .background(surface)
            .overlay(border)
            .modifier(OptionalShadow(shadow: shadow))
    }
    
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
    
    @ViewBuilder
    private var surface: some View {
        if isFlat {
            shape.fill(SMI.Palette.solidSurface)
        } else {
            ZStack {
                // Frosted base — picks up colour from the animated background
                shape.fill(.ultraThinMaterial)
                
                // Dark mode needs a scrim. Without it the material blends the
                // bright gradient behind it into a washed-out pale panel.
                if isDark {
                    shape.fill(Color.black.opacity(0.34))
                }
                
                // Brand tint wash — slightly stronger in dark mode so the
                // accent survives the scrim.
                shape.fill(tint.opacity(isDark ? 0.10 : 0.07))
                
                // Specular highlight along the top edge. Much subtler in dark
                // mode; a bright edge on a dark pane reads as a mistake.
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.07 : 0.18),
                            Color.white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        }
    }
    
    private var border: some View {
        let opacity = isFlat ? 0.55 : (isDark ? borderOpacity * 1.35 : borderOpacity)
        
        return shape.strokeBorder(
            LinearGradient(
                colors: [
                    tint.opacity(opacity),
                    tint.opacity(opacity * 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: isFlat ? 1.2 : 0.8
        )
    }
}

private struct OptionalShadow: ViewModifier {
    let shadow: SMI.Elevation.Shadow?
    
    func body(content: Content) -> some View {
        if let shadow {
            content.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
        } else {
            content
        }
    }
}

extension View {
    /// Apply the Liquid Glass surface treatment.
    ///
    /// `elevation` defaults to the resting shadow. Pass `nil` for a flat
    /// surface. This is the preferred spelling; see the `tintColor:` variant
    /// below for why the other one still exists.
    func liquidGlass(
        cornerRadius: CGFloat = SMI.Radius.card,
        tint: Color = .brandViolet,
        borderOpacity: Double = 0.25,
        elevation: SMI.Elevation.Shadow? = nil
    ) -> some View {
        modifier(SMIGlassSurface(
            cornerRadius: cornerRadius,
            tint: tint,
            borderOpacity: borderOpacity,
            shadow: elevation ?? SMI.Elevation.resting(tint)
        ))
    }
    
    /// Legacy spelling, retained because ToolbarView still uses it.
    ///
    /// I removed this once and it broke ToolbarView, because I had checked
    /// call sites only across the files I happened to be editing rather than
    /// the whole project. It costs four lines to keep, and keeping it is now
    /// harmless: the trap it created earlier — "missing argument for parameter
    /// 'elevation'" — came from `elevation` being required on the other
    /// overload, and that now has a default.
    ///
    /// New code should use `tint:`.
    func liquidGlass(
        cornerRadius: CGFloat = SMI.Radius.card,
        tintColor: Color,
        borderOpacity: Double = 0.25
    ) -> some View {
        liquidGlass(
            cornerRadius: cornerRadius,
            tint: tintColor,
            borderOpacity: borderOpacity
        )
    }
}

// MARK: - Window zoom
//
// Auxiliary windows — Settings, Keyboard Shortcuts — scale with the app's zoom
// level, so ⌘+ affects the whole app rather than only the metadata pane.
//
// WHY THIS ISN'T scaleEffect
//
// The first implementation scaled the composed view. That works geometrically
// and looks wrong: SwiftUI rasterises the view at its layout size and then
// stretches the bitmap, so every glyph in the window goes soft the moment you
// zoom. No amount of tuning fixes it, because the text was never drawn at the
// size you're seeing.
//
// Instead the scale is published through the environment and each window
// multiplies its own type sizes, spacing and frames by it. The layout happens
// at the real size, so the font engine renders glyphs at that size and they
// stay sharp at every zoom level. It is more plumbing, and it is the only way
// to get a genuinely crisp result.

/// Multiplies design values for a window that scales with the app zoom.
struct SMIScale: Equatable {
    var factor: CGFloat = 1
    
    /// Scale a dimension — spacing, frame width, icon size.
    /// Rounded so edges land on whole points and hairlines stay crisp.
    func s(_ value: CGFloat) -> CGFloat {
        (value * factor).rounded()
    }
    
    /// Scale a font. Sizes are not rounded: type looks better at fractional
    /// sizes than snapped, and glyph rendering handles it natively.
    func font(
        _ size: CGFloat,
        _ weight: Font.Weight = .regular,
        _ design: Font.Design = .default
    ) -> Font {
        .system(size: size * factor, weight: weight, design: design)
    }
}

private struct SMIScaleKey: EnvironmentKey {
    static let defaultValue = SMIScale()
}

extension EnvironmentValues {
    var smiScale: SMIScale {
        get { self[SMIScaleKey.self] }
        set { self[SMIScaleKey.self] = newValue }
    }
}

/// Publishes the zoom scale to an auxiliary window's contents.
struct WindowZoomScale: ViewModifier {
    @EnvironmentObject private var store: MediaStore
    
    /// The window's design size at 1.0, used to work out how far it may grow.
    let baseWidth: CGFloat
    let baseHeight: CGFloat
    
    /// 12pt is the app's default text size, so that is 1.0.
    private var requestedScale: CGFloat {
        max(CGFloat(store.fontSize) / 12.0, 0.85)
    }
    
    /// The largest scale this window may use — the lower of two ceilings.
    ///
    /// 1. The screen. A fixed limit isn't enough: at 1.75 the shortcuts window
    ///    would be 1120pt tall, taller than most Mac displays, and a window
    ///    whose bottom you can't reach is worse than one that doesn't scale.
    ///
    /// 2. The main window. A Settings panel larger than the application it
    ///    configures reads as a bug even when it fits the display, so these
    ///    windows never outgrow the app itself.
    ///
    /// Neither ceiling goes below 1.0: a small main window reduces the headroom
    /// but must not shrink a panel below its design size.
    private var maximumScale: CGFloat {
        var limit: CGFloat = 1.75
        
        if let visible = NSScreen.main?.visibleFrame {
            // Margin leaves room for the menu bar and the window's title bar.
            limit = min(
                limit,
                (visible.width  - 80) / baseWidth,
                (visible.height - 80) / baseHeight
            )
        }
        
        let main = store.mainWindowSize
        if main.width > 0, main.height > 0 {
            limit = min(limit, main.width / baseWidth, main.height / baseHeight)
        }
        
        return max(limit, 1.0)
    }
    
    private var scale: SMIScale {
        SMIScale(factor: min(requestedScale, maximumScale))
    }
    
    func body(content: Content) -> some View {
        content
            .environment(\.smiScale, scale)
            .smiAnimation(SMI.Motion.smooth, value: scale)
    }
}

extension View {
    /// Publishes the app's zoom scale to a fixed-size auxiliary window.
    /// The window sizes itself from that scale; this only supplies the value.
    func windowZoomScaled(baseWidth: CGFloat, baseHeight: CGFloat) -> some View {
        modifier(WindowZoomScale(baseWidth: baseWidth, baseHeight: baseHeight))
    }
}
