//
//  LiquidGlass.swift
//  SwiftMediaInfo
//
//  PHASE 2 — the reusable component library.
//
//  Tokens (colour, type, spacing, motion, the glass surface itself) now live in
//  DesignSystem.swift. This file holds the things that actually draw.
//
//  IMPORTANT — before building, delete the `GlassButton` struct from
//  ToolbarView.swift. It has moved here, upgraded with hover and press states.
//  Leaving both in place will fail to compile with a duplicate-symbol error.
//
//  What changed from v1.5:
//    • GlassButton gained hover, press, and disabled states. It previously had
//      no feedback at all, which was the most prototype-like thing in the app.
//    • The animated background freezes under Reduce Motion.
//    • New shared components: GlassCard, GlassBadge, GlassIconButton,
//      GlassSectionHeader, and a shimmer for loading states.
//    • Everything reads from tokens instead of inline numbers.
//

import SwiftUI
import AppKit

// MARK: - Press feedback
//
// A shared button style so every pressable surface in the app compresses by the
// same amount, at the same speed. Small, but it's the kind of consistency people
// register as "solid" without knowing why.

struct GlassPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? scale : 1.0))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(
                reduceMotion ? SMI.Motion.reduced : SMI.Motion.snap,
                value: configuration.isPressed
            )
    }
}

// MARK: - Glass Button
//
// The primary toolbar control. Moved here from ToolbarView.swift.
//
// Three visual states now exist where there was previously only one:
//   • resting  — icon and label, no chrome
//   • hovered  — a faint wash appears, so the target reads as clickable
//   • pressed  — compresses slightly (via GlassPressStyle)
//
// Active (toggled-on) buttons additionally carry an accent tint and a soft
// capsule behind them, matching how the tab bar marks selection.

struct GlassButton: View {
    let icon: String
    let label: String
    var accentColor: Color = .brandViolet
    var isActive: Bool = false
    var isDisabled: Bool = false
    
    /// PHASE 11. What VoiceOver should say, when the visible label is not
    /// enough — or not there at all.
    ///
    /// The two zoom buttons are the case that forced this. They pass an empty
    /// label because the magnifier glyphs are self-explanatory to look at, and
    /// an unlabelled button is announced as "button", which is useless. The
    /// tooltip already carried the right words; this makes the same words
    /// available to someone who cannot see the tooltip either.
    var voiceOverLabel: String? = nil
    
    /// Spoken description of what pressing this does, when the label alone
    /// leaves it ambiguous. Optional, and usually unnecessary — a hint that
    /// merely restates the label is a hint worth deleting.
    var voiceOverHint: String? = nil
    
    let action: () -> Void
    
    @State private var isHovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var spokenLabel: String {
        if let voiceOverLabel, !voiceOverLabel.isEmpty { return voiceOverLabel }
        return label
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: SMI.Spacing.hair + 1) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                // PHASE 11. Some GlassButtons change their glyph rather than
                // their state: the appearance toggle cycles sun → moon → half-
                // circle, and Compare swaps a hollow icon for a filled one.
                // Those swaps were instantaneous, so the button appeared to
                // teleport between two different buttons.
                //
                // `.replace` morphs one glyph into the other. Putting it here
                // rather than at the call site means every icon-changing
                // GlassButton gets it, now and later, without anyone having to
                // remember. Under Reduce Motion it degrades to a cross-fade —
                // the change of shape is information, the morph is movement.
                    .contentTransition(
                        reduceMotion ? .opacity : .symbolEffect(.replace)
                    )
                    .symbolEffect(.bounce, value: isActive)
                // One reserved height for every icon, so the labels
                // underneath share a baseline. See SMI.Metrics.toolbarIcon.
                    .frame(height: SMI.Metrics.toolbarIcon)
                
                if !label.isEmpty {
                    Text(label)
                        .font(SMI.Typo.callout)
                        .lineLimit(1)
                    // Without this the label is treated as compressible and
                    // SwiftUI shortens it — "Open in App" became
                    // "Open in…" while there was still empty space further
                    // along the toolbar. `minWidth` sets a floor, not a
                    // ceiling, so the text has to insist on its own width
                    // for the button to grow to fit it.
                        .fixedSize(horizontal: true, vertical: false)
                    // "System" → "Light" → "Dark" cross-fades instead of
                    // snapping. Opacity rather than anything spatial, because
                    // the three words are different widths and sliding them
                    // would shove the whole toolbar group sideways.
                        .contentTransition(.opacity)
                }
            }
            .foregroundStyle(foreground)
            .frame(minWidth: label.isEmpty ? 36 : 62, minHeight: 47)
            .padding(.horizontal, label.isEmpty ? SMI.Spacing.small : SMI.Spacing.medium - 2)
            .padding(.vertical, SMI.Spacing.snug + 1)
            .background(backdrop)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isDisabled)
        .onHover { hovering in
            guard !isDisabled else { return }
            isHovering = hovering
        }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .smiAnimation(SMI.Motion.snap, value: isActive)
        // The content transitions above need an animation attached to the
        // value that actually changes. `isActive` does not move when the
        // appearance toggle cycles, so without these two the glyph and the
        // word would still snap.
        .smiAnimation(SMI.Motion.snap, value: icon)
        .smiAnimation(SMI.Motion.fade, value: label)
        // One element, one sentence. Without `.ignore` the icon and the label
        // are two stops, and the first one is announced as "image".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(voiceOverHint ?? "")
        // A toggled-on button — Compare, while comparing — reads as selected
        // rather than looking different and sounding identical.
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
    
    private var foreground: Color {
        if isDisabled { return .secondary.opacity(0.4) }
        if isActive   { return accentColor }
        return isHovering ? .primary : .primary.opacity(0.85)
    }
    
    @ViewBuilder
    private var backdrop: some View {
        let shape = RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
        
        if isActive {
            shape
                .fill(accentColor.opacity(reduceTransparency ? 0.28 : 0.18))
                .overlay(
                    shape.strokeBorder(accentColor.opacity(0.35), lineWidth: 0.7)
                )
        } else if isHovering && !isDisabled {
            shape.fill(SMI.Palette.hoverWash)
        }
    }
}

// MARK: - Glass Icon Button
//
// A compact, label-less control for dense contexts — search bar navigation,
// card-level actions, popover dismissal.

struct GlassIconButton: View {
    let icon: String
    var accentColor: Color = .brandViolet
    var size: CGFloat = 28
    var isDisabled: Bool = false
    var help: String? = nil
    
    /// PHASE 11. Defaults to the tooltip, which is almost always already the
    /// right sentence — these buttons are icon-only, so the tooltip is the only
    /// place their name is written down at all.
    var voiceOverLabel: String? = nil
    
    let action: () -> Void
    
    @State private var isHovering = false
    
    private var spokenLabel: String {
        voiceOverLabel ?? help ?? ""
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(
                    isDisabled
                    ? AnyShapeStyle(Color.secondary.opacity(0.35))
                    : AnyShapeStyle(isHovering ? accentColor : Color.primary.opacity(0.75))
                )
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        isHovering && !isDisabled
                        ? accentColor.opacity(0.14)
                        : Color.clear
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.90))
        .disabled(isDisabled)
        .onHover { hovering in
            guard !isDisabled else { return }
            isHovering = hovering
        }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .help(help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Toolbar action button
//
// PHASE 11.
//
// Copy, Share and Export were each hand-built with `.buttonStyle(.plain)` and
// no feedback of any kind: no hover wash, no press compression, and — for
// Copy — nothing at all to say the copy had happened. Pressing Copy looked
// exactly like not pressing Copy, which is the one thing a clipboard button
// must never do, because the clipboard is invisible.
//
// The three of them sit in the same glass cluster as GlassButton, so they now
// share its geometry exactly: the same reserved icon height, the same 62×47
// minimum, the same press style. What this adds on top is a success state.
//
// HOW THE SUCCESS STATE IS DRAWN
//
// Four things change at once, deliberately, because each covers a different
// way of noticing:
//
//   • the glyph becomes a filled check       — shape
//   • the words become "Copied!"             — language
//   • the tint becomes the success gradient  — colour
//   • the whole button swells very slightly  — motion
//
// Colour alone would fail anyone who cannot distinguish it, and motion alone
// disappears under Reduce Motion. Because the shape and the wording carry the
// message on their own, the button still reports success when both the colour
// and the movement are stripped away.
//
// UNDER REDUCE MOTION
//
// The swell and the symbol bounce are dropped; the glyph swap becomes a short
// cross-fade rather than a replace effect. The information survives, the
// movement does not — which is the rule the whole motion vocabulary follows.

struct ToolbarActionButton: View {
    let icon: String
    let label: String
    var accentColor: Color = .brandViolet
    
    /// Lit while this button owns something that is open — a popover, usually.
    ///
    /// PHASE 11. Share and Export both spawn popovers, and both used to go
    /// completely inert the moment the popover appeared, so the panel floating
    /// under the toolbar had no visible parent. Lighting the button is how the
    /// tab bar already marks selection, and it costs nothing.
    var isActive: Bool = false
    
    /// Drives the success state. The caller owns it, and should only raise it
    /// when the action genuinely completed — a button that celebrates a copy
    /// the user cancelled is a button that lies.
    var isSuccessful: Bool = false
    var successIcon: String = "checkmark.circle.fill"
    var successLabel: String? = nil
    
    var isDisabled: Bool = false
    var help: String? = nil
    var voiceOverLabel: String? = nil
    var voiceOverHint: String? = nil
    
    let action: () -> Void
    
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    private var shownIcon: String { isSuccessful ? successIcon : icon }
    private var shownLabel: String { isSuccessful ? (successLabel ?? label) : label }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: SMI.Spacing.hair + 1) {
                Image(systemName: shownIcon)
                    .font(.system(size: 21, weight: isSuccessful ? .semibold : .regular))
                    .frame(height: SMI.Metrics.toolbarIcon)
                // `.replace` is the glyph-morph transition. Under Reduce
                // Motion it is swapped for a plain opacity cross-fade, since
                // the morph is movement and the change of shape is not.
                    .contentTransition(
                        reduceMotion
                        ? .opacity
                        : .symbolEffect(.replace)
                    )
                    .symbolEffect(.bounce, value: reduceMotion ? false : isSuccessful)
                
                Text(shownLabel)
                    .font(SMI.Typo.callout)
                    .lineLimit(1)
                // Same reason as GlassButton: "Copied!" is wider than
                // "Copy", and without this SwiftUI would rather truncate the
                // word than let the button grow.
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(foreground)
            .frame(minWidth: 62, minHeight: 47)
            .padding(.horizontal, SMI.Spacing.medium - 2)
            .padding(.vertical, SMI.Spacing.snug + 1)
            .background(backdrop)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .disabled(isDisabled)
        .onHover { hovering in
            guard !isDisabled else { return }
            isHovering = hovering
        }
        // A small swell, then back. Enough to catch the eye at the edge of
        // vision without pulling the toolbar around.
        .scaleEffect(isSuccessful && !reduceMotion ? 1.06 : 1.0)
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .smiAnimation(SMI.Motion.snap, value: isSuccessful)
        .smiAnimation(SMI.Motion.snap, value: isActive)
        .help(help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel ?? label)
        .accessibilityValue(isSuccessful ? (successLabel ?? "Done") : "")
        .accessibilityHint(voiceOverHint ?? "")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
    
    private var foreground: AnyShapeStyle {
        if isDisabled {
            return AnyShapeStyle(Color.secondary.opacity(0.4))
        }
        if isSuccessful {
            return AnyShapeStyle(LinearGradient.brandSuccess)
        }
        if isActive {
            return AnyShapeStyle(accentColor)
        }
        return AnyShapeStyle(isHovering ? Color.primary : Color.primary.opacity(0.85))
    }
    
    @ViewBuilder
    private var backdrop: some View {
        let shape = RoundedRectangle(cornerRadius: SMI.Radius.control, style: .continuous)
        
        // Success wins over active: if a copy just landed, that is the more
        // urgent thing for the button to be saying.
        if isSuccessful {
            shape
                .fill(SMI.Palette.success.opacity(reduceTransparency ? 0.30 : 0.18))
                .overlay(
                    shape.strokeBorder(SMI.Palette.success.opacity(0.40), lineWidth: 0.7)
                )
        } else if isActive {
            shape
                .fill(accentColor.opacity(reduceTransparency ? 0.28 : 0.18))
                .overlay(
                    shape.strokeBorder(accentColor.opacity(0.35), lineWidth: 0.7)
                )
        } else if isHovering && !isDisabled {
            shape.fill(SMI.Palette.hoverWash)
        }
    }
}

// MARK: - Glass Badge
//
// Small count/status pill. Used for field counts on track cards, diff totals,
// and search match counts.
//
// The unfilled variant was previously tinted text on a 15%-tint background,
// which on a coloured card header was close to invisible. It now carries a
// neutral dark backing plus a stronger border, so the figure reads at a glance
// against any tint, in either colour scheme, without shouting.

struct GlassBadge: View {
    let text: String
    var tint: Color = .brandViolet
    var filled: Bool = true
    /// Base font size to scale against — pass store.fontSize where the
    /// surrounding text scales with zoom. Defaults to the fixed micro size.
    var scale: Double? = nil
    
    /// PHASE 11. A badge is shorthand: "12" next to a card header means twelve
    /// fields, and only the layout says so. Spoken on its own it is just a
    /// number. Pass the long form — "12 fields" — and the shorthand keeps
    /// working for the eye while the sentence works for the ear.
    var voiceOverLabel: String? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var font: Font {
        if let scale {
            return .system(size: max(9, CGFloat(scale) - 2), weight: .bold, design: .rounded)
        }
        return SMI.Typo.micro
    }
    
    private var foreground: Color {
        if filled { return .white }
        // Full-strength tint rather than the tint at partial opacity — the
        // background behind it already carries the tint.
        return colorScheme == .dark ? tint : tint.opacity(0.95)
    }
    
    private var background: some ShapeStyle {
        if filled { return AnyShapeStyle(tint.opacity(0.92)) }
        return AnyShapeStyle(
            colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.white.opacity(0.65)
        )
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, SMI.Spacing.snug)
            .padding(.vertical, SMI.Spacing.hair)
            .background(
                Capsule(style: .continuous).fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(filled ? 0 : 0.65), lineWidth: 1)
            )
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOverLabel ?? text)
    }
}

// MARK: - Glass Card
//
// The container for grouped content — track cards in Easy View, sections in
// Settings, the comparison summary.
//
// This replaces the opaque `Color(NSColor.controlBackgroundColor)` chrome that
// Easy View used, which was the main reason the content area stopped looking
// like the rest of the app the moment you scrolled.

struct GlassCard<Header: View, Content: View>: View {
    var tint: Color = .brandViolet
    var isExpanded: Bool = true
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .background(tint.opacity(reduceTransparency ? 0.16 : 0.10))
            
            if isExpanded {
                content()
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SMI.Radius.card, style: .continuous))
        .liquidGlass(
            cornerRadius: SMI.Radius.card,
            tint: tint,
            borderOpacity: 0.22,
            elevation: SMI.Elevation.resting(tint)
        )
        .smiAnimation(SMI.Motion.smooth, value: isExpanded)
    }
}

// MARK: - Section header
//
// Used inside cards and Settings panes. Deliberately quiet — an uppercase,
// tracked-out caption rather than a bold title, so it organises without
// competing with the content it labels.

struct GlassSectionHeader: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .secondary
    
    var body: some View {
        HStack(spacing: SMI.Spacing.snug) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title.uppercased())
                .font(SMI.Typo.caption)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SMI.Spacing.tight)
        .padding(.bottom, SMI.Spacing.snug)
    }
}

// MARK: - Shimmer
//
// A travelling highlight for loading placeholders. Preferable to a spinner for
// content that has a known shape — it suggests the layout that's arriving
// rather than just signalling "wait".
//
// Disabled entirely under Reduce Motion, falling back to a static wash.

struct ShimmerEffect: ViewModifier {
    var tint: Color = .brandViolet
    
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.5)
        } else {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .clear,
                                tint.opacity(0.25),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                    }
                        .allowsHitTesting(false)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

extension View {
    func shimmer(tint: Color = .brandViolet) -> some View {
        modifier(ShimmerEffect(tint: tint))
    }
}

// MARK: - Animated gradient background
//
// A slow-shifting mesh of brand colours behind the window, so the glass panels
// have something to pick colour up from. Without it the glass reads as grey.
//
// Rendering is suspended whenever it can't be seen or shouldn't be running:
// app inactive, window occluded, mid-scroll, or Reduce Motion enabled. Under
// Reduce Motion a single static frame is drawn — the colour depth is retained,
// the movement is not.

// MARK: - Gradient background
//
// PHASE 12b — rewritten. Was `AnimatedGradientBackground`, renamed because it
// is no longer necessarily animated.
//
// FOUR CHANGES, AND WHY EACH ONE IS INVISIBLE
//
// 1. THREE MODES INSTEAD OF A BOOLEAN. Static is the new default and draws the
//    gradient exactly once. Nothing about the picture changes; only the number
//    of times it is computed.
//
// 2. QUARTER RESOLUTION. The canvas is drawn a quarter of the width and a
//    quarter of the height, blurred by a quarter of the radius, then scaled up
//    to fill. That is one sixteenth of the pixels.
//
//    This is safe for one specific reason: the picture is viewed through an
//    80-point blur, and a blur exists to destroy fine detail. There is nothing
//    left in the image for the smaller size to lose. Blurring then magnifying
//    produces the same result as magnifying then blurring, and the first is
//    sixteen times cheaper.
//
// 3. SIX FRAMES PER SECOND, DOWN FROM TEN. The blobs travel on lissajous paths
//    at a 0.45 speed multiplier — they cross the window over tens of seconds.
//    There is no edge, no text, nothing with a hard boundary for the eye to
//    catch stepping.
//
// 4. LOW POWER MODE FREEZES IT. macOS reports when the user has asked to
//    conserve battery, and this app previously ignored that entirely. Treated
//    the same way Reduce Motion already is: the colour is kept in full, only
//    the movement goes. Someone who asked their laptop to try harder should not
//    have to also find a setting in here.
//
// WHY STATIC IS THE ONE THAT MATTERS
//
// The measurements in Phase 12a showed the cost was never the background
// alone. It was that sixteen to twenty frosted glass panels each had to
// re-sample their backdrop every time that backdrop moved. Freezing the
// backdrop ends that recomputation everywhere at once — including the cost of
// hovering a row, which forces the glass above it to repaint.

struct GradientBackground: View {
    /// How much smaller the canvas is drawn before being scaled back up.
    /// Four is a judgement, not a law: at eight the blur starts to show faint
    /// banding on a large display, and at two the saving is only fourfold.
    private static let downscale: CGFloat = 4
    
    private static let blurRadius: CGFloat = 80
    
    /// Frames per second while animating.
    ///
    /// Settled at 12 after testing. Six read as choppy; fifteen was smooth but
    /// bought more than the motion needed.
    ///
    /// The reason twelve is affordable at all is the quarter-resolution
    /// rendering below, which made each frame roughly sixteen times cheaper. It
    /// is a little smoother than the ten this originally shipped with, while
    /// costing around a thirteenth of what that original cost — the saving came
    /// from the resolution, not from rationing frames.
    ///
    /// One number, safe to tune if it ever reads as stepped on a larger
    /// display.
    private static let frameRate: Double = 12
    
    /// The frozen moment used by the static mode.
    ///
    /// Not zero. At t = 0 two of the three blobs sit almost on top of each
    /// other against the right edge, which is a poor composition to be stuck
    /// looking at forever. This value places them at roughly (0.29, 0.49),
    /// (0.59, 0.80) and (0.80, 0.43) — well separated, none of them crowding a
    /// corner. It is a constant so that the static background is identical on
    /// every launch and on every machine.
    private static let frozenMoment: Double = 116.28
    
    @State private var isAppActive = true
    @State private var pauseDate = Date()
    @State private var isScrolling = false
    @State private var scrollDebounce: DispatchWorkItem? = nil
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    
    @AppStorage(BackgroundMode.key) private var modeRaw: String = BackgroundMode.shippedDefault.rawValue
    @AppStorage(BackgroundPalette.keys[0]) private var hex1: String = Color.brandViolet.smiHex
    @AppStorage(BackgroundPalette.keys[1]) private var hex2: String = Color.brandPink.smiHex
    @AppStorage(BackgroundPalette.keys[2]) private var hex3: String = Color.brandBlue.smiHex
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var mode: BackgroundMode {
        BackgroundMode(rawValue: modeRaw) ?? BackgroundMode.shippedDefault
    }
    
    /// Malformed hex falls back to the brand colour rather than to black, so a
    /// corrupted preference degrades to the default look instead of a void.
    private var colors: [Color] {
        [
            Color(smiHex: hex1) ?? .brandViolet,
            Color(smiHex: hex2) ?? .brandPink,
            Color(smiHex: hex3) ?? .brandBlue
        ]
    }
    
    private var shouldAnimate: Bool {
        mode == .animated
        && isAppActive
        && !isScrolling
        && !reduceMotion
        && !isLowPower
    }
    
    var body: some View {
        Group {
            if mode == .off {
                Color.clear
            } else {
                scaledCanvas
            }
        }
        .ignoresSafeArea()
        // Wallpaper. It exists so the glass has something to pick colour up
        // from, and it says nothing — so it should say nothing out loud either.
        .smiDecorativeChrome()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            pauseDate = Date()
            isAppActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAppActive = true
        }
        // Pause animation during scrolling
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            scrollDebounce?.cancel()
            if !isScrolling {
                pauseDate = Date()
                isScrolling = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            // Resume after a short delay so rapid scroll gestures don't flicker
            let item = DispatchWorkItem { isScrolling = false }
            scrollDebounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
        // PHASE 12b — the system posts this when Low Power Mode is switched on
        // or off, so the change takes effect immediately rather than at next
        // launch.
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            let low = ProcessInfo.processInfo.isLowPowerModeEnabled
            if low { pauseDate = Date() }
            isLowPower = low
        }
        .onAppear {
            isAppActive = NSApplication.shared.isActive
            isLowPower  = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        // Pause when the window is occluded (minimised or fully behind others)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notif in
            guard let window = notif.object as? NSWindow else { return }
            if window.occlusionState.contains(.visible) {
                isAppActive = NSApplication.shared.isActive
            } else {
                pauseDate = Date()
                isAppActive = false
            }
        }
    }
    
    /// Draws small, blurs small, scales up.
    ///
    /// `GeometryReader` places its child at the top-leading corner, which is
    /// why the scale is anchored there — anchoring at the centre would leave
    /// the magnified canvas straddling the window's middle instead of covering
    /// it from the corner out.
    private var scaledCanvas: some View {
        GeometryReader { geo in
            let f = Self.downscale
            let w = max(geo.size.width  / f, 1)
            let h = max(geo.size.height / f, 1)
            
            Group {
                if shouldAnimate {
                    TimelineView(.animation(minimumInterval: 1.0 / Self.frameRate)) { context in
                        GradientCanvas(date: context.date, colors: colors)
                    }
                } else {
                    GradientCanvas(date: frozenOrPausedDate, colors: colors)
                }
            }
            .frame(width: w, height: h)
            .blur(radius: Self.blurRadius / f)
            .scaleEffect(f, anchor: .topLeading)
        }
    }
    
    /// Static mode always uses the fixed moment, so it looks the same every
    /// launch. The other reasons for holding still — losing focus, scrolling,
    /// Low Power Mode — freeze wherever the drift happened to be, because
    /// snapping back to a canonical frame would be a visible jump.
    private var frozenOrPausedDate: Date {
        mode == .staticGradient
        ? Date(timeIntervalSinceReferenceDate: Self.frozenMoment)
        : pauseDate
    }
}

private struct GradientCanvas: View {
    var date: Date
    var colors: [Color]
    
    var body: some View {
        Canvas { ctx, size in
            // Three overlapping radial blobs on slow lissajous paths
            let t = date.timeIntervalSinceReferenceDate * 0.45
            let w = size.width, h = size.height
            
            // Defensive: the palette should always be three, but a short array
            // wrapping rather than crashing costs one modulo.
            func color(_ i: Int) -> Color {
                colors.isEmpty ? .brandViolet : colors[i % colors.count]
            }
            
            let blobs: [(x: Double, y: Double, r: Double, color: Color)] = [
                (
                    w * (0.3 + 0.25 * sin(t)),
                    h * (0.3 + 0.2  * cos(t * 0.7)),
                    min(w, h) * 0.55,
                    color(0)
                ),
                (
                    w * (0.7 + 0.2  * cos(t * 0.9)),
                    h * (0.6 + 0.25 * sin(t * 1.1)),
                    min(w, h) * 0.5,
                    color(1)
                ),
                (
                    w * (0.5 + 0.3  * sin(t * 0.6 + 1)),
                    h * (0.2 + 0.3  * cos(t * 0.8 + 0.5)),
                    min(w, h) * 0.45,
                    color(2)
                ),
            ]
            
            for blob in blobs {
                ctx.drawLayer { inner in
                    let rect = CGRect(
                        x: blob.x - blob.r,
                        y: blob.y - blob.r,
                        width:  blob.r * 2,
                        height: blob.r * 2
                    )
                    inner.opacity = 0.28
                    inner.fill(
                        Path(ellipseIn: rect),
                        with: .color(blob.color)
                    )
                }
            }
        }
    }
}

// MARK: - ViewMode tab bar
//
// A single glass pill containing every tab. The selected item's capsule slides
// between positions via matchedGeometryEffect rather than cross-fading, which
// is what makes the selection feel like one object moving instead of two
// objects swapping.

struct LiquidGlassTabBar: View {
    @EnvironmentObject var store: MediaStore
    @Namespace private var ns
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases) { mode in
                TabPill(mode: mode, selected: store.viewMode == mode, namespace: ns) {
                    smiWithAnimation(SMI.Motion.smooth) {
                        store.viewMode = mode
                    }
                }
            }
        }
        .padding(SMI.Spacing.tight)
        .liquidGlass(
            cornerRadius: SMI.Radius.card,
            tint: .brandViolet,
            borderOpacity: 0.3
        )
        // `.contain` rather than `.ignore`: the six pills stay individually
        // reachable, but they are announced as belonging to a named group, so
        // stepping into them says "View mode" first instead of dropping the
        // user straight onto "Easy" with no idea what it is one of.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View mode")
    }
}

private struct TabPill: View {
    let mode: ViewMode
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    private var accentColor: Color { SMI.Palette.viewMode(mode) }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: SMI.Spacing.hair + 1) {
                Image(systemName: mode.icon)
                    .font(.system(size: 21, weight: selected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)
                    .frame(height: SMI.Metrics.toolbarIcon)
                Text(mode.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(foreground)
            .frame(minWidth: 62, minHeight: 47)
            .padding(.horizontal, SMI.Spacing.medium - 2)
            .padding(.vertical, SMI.Spacing.snug + 1)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(accentColor.opacity(reduceTransparency ? 0.3 : 0.18))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(accentColor.opacity(0.35), lineWidth: 0.7)
                        )
                        .matchedGeometryEffect(id: "tab_highlight", in: namespace)
                } else if isHovering {
                    Capsule(style: .continuous)
                        .fill(SMI.Palette.hoverWash)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.97))
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.fade, value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.label)
        // Selection is currently shown by a tinted capsule and a heavier
        // weight — both invisible to a screen reader. The trait is what makes
        // "Easy, selected" possible.
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Show the \(mode.label) view of this file")
    }
    
    private var foreground: Color {
        if selected   { return accentColor }
        if isHovering { return .primary }
        return .secondary
    }
}

// MARK: - Spectrum divider

struct SpectrumDivider: View {
    var body: some View {
        LinearGradient.brandSpectrum
            .frame(height: 1)
            .opacity(0.35)
            .smiDecorativeChrome()
    }
}

// MARK: - Drop highlight overlay

struct GlassDropOverlay: View {
    var color: Color
    var message: String = "Drop to open here"
    var symbol: String = "plus.circle.fill"
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
            .strokeBorder(color, lineWidth: 2.5)
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.button, style: .continuous)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                VStack(spacing: SMI.Spacing.medium - 2) {
                    Group {
                        if reduceMotion {
                            Image(systemName: symbol)
                                .font(.system(size: 38))
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 38))
                                .symbolEffect(.pulse)
                        }
                    }
                    .foregroundStyle(color)
                    
                    Text(message)
                        .font(SMI.Typo.bodyStrong)
                        .foregroundStyle(color)
                }
            )
            .padding(SMI.Spacing.medium - 2)
            .allowsHitTesting(false)
        // The overlay appears mid-drag and carries real instruction, so it is
        // read as one sentence rather than hidden. `.ignore` collapses the
        // pulsing glyph and the text into that one sentence.
            .smiReadAsOne(message)
    }
}
