//
//  LiquidGlass.swift
//  SwiftMediaInfo
//
//  The reusable component library, built from DesignSystem's tokens:
//
//  • Buttons: GlassPressStyle (the shared press), RowButtonStyle (cheap
//    buttons for list rows), GlassButton and ToolbarActionButton (the
//    toolbar), the view-mode bar (LiquidGlassTabBar).
//  • Cards: GlassCard and its corner-following backgrounds, CardStack,
//    CardDisclosureChevron, GlassBadge, GlassSectionHeader.
//  • The window: GradientBackground, SpectrumDivider, GlassDropOverlay.
//
//  Small menus' rows and titles are in PopoverChrome; sheet and panel window
//  pieces in WindowChrome.
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

// MARK: - Row buttons
//
// For the small buttons repeated in every row of a long list (the copy and
// info buttons in Easy View and Compare Mode).
//
// On macOS a Button with an ordinary style is backed by AppKit views for its
// press tracking and keyboard focus. Two of those per row came to a few
// hundred in a long file, each built as its row scrolled into view, and they
// were the most expensive part of a row.
//
// This style tracks the press itself, so the button is plain SwiftUI. Under
// the pointer it behaves as before: shown pressed while the button is held
// down with the pointer inside it, fired on release inside it, and abandoned
// if the pointer is let go outside. The defaults reproduce `.plain`, which
// dims the label to three-quarters while held (measured on screen); the copy
// button passes GlassPressStyle's values.

struct RowButtonStyle: PrimitiveButtonStyle {
    /// Scale while held. 1 for none, as `.plain`.
    var pressedScale: CGFloat = 1
    /// Opacity while held.
    var pressedOpacity: Double = 0.75
    /// GlassPressStyle eases the press in and out; `.plain` doesn't.
    var animatesPress = false

    func makeBody(configuration: Configuration) -> some View {
        RowButton(configuration: configuration, style: self)
    }
}

private struct RowButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let style: RowButtonStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false
    @State private var size: CGSize = .zero

    var body: some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? style.pressedScale : 1.0))
            .opacity(isPressed ? style.pressedOpacity : 1.0)
            .animation(
                style.animatesPress ? (reduceMotion ? SMI.Motion.reduced : SMI.Motion.snap) : nil,
                value: isPressed
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { drag, isPressed, _ in
                        isPressed = contains(drag.location)
                    }
                    .onEnded { drag in
                        if contains(drag.location) { configuration.trigger() }
                    }
            )
    }

    private func contains(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: size).contains(point)
    }
}

extension View {
    /// `.plain` for a button repeated in every row that must stay reachable
    /// from the keyboard: RowButtonStyle normally, and an ordinary `.plain`
    /// button when Keyboard Navigation is on — the only time macOS lets Tab
    /// reach a button, and the one thing RowButtonStyle doesn't do.
    func plainRowButtonStyle() -> some View {
        modifier(PlainRowButtonStyle())
    }
}

private struct PlainRowButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if NSApplication.shared.isFullKeyboardAccessEnabled {
            content.buttonStyle(.plain)
        } else {
            content.buttonStyle(RowButtonStyle())
        }
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
    
    /// What VoiceOver should say, when the visible label is not
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
                // Some GlassButtons change their glyph rather than
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

// MARK: - Toolbar action button
//
// Copy, Share and Export. They sit in the same glass cluster as GlassButton
// and share its geometry exactly — the same reserved icon height, the same
// 62×47 minimum, the same press style — and add a success state, because the
// clipboard is invisible: pressing Copy must look different from not
// pressing it.
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
    /// Lit so a popover floating under the toolbar has a visible parent —
    /// the way the tab bar marks selection.
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

// MARK: - Card disclosure chevron

/// The chevron at the trailing end of a card header that folds: pointing down
/// when the card is open, turning to point right as it closes. Track cards in
/// Easy View and Compare, and the Overview, sized to the report's text.
struct CardDisclosureChevron: View {
    let isExpanded: Bool
    let fontSize: Double

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: CGFloat(fontSize) - 2, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .smiAnimation(SMI.Motion.disclosure, value: isExpanded)
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
    
    /// A badge is shorthand: "12" next to a card header means twelve
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
    /// For cards that come by the dozen and scroll (Easy View and
    /// Compare Mode tracks). See "Rounding its own corners" below.
    var roundsOwnCorners: Bool = false
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// True while the card is opening or closing (see below).
    @State private var isDisclosing = false
    @State private var disclosureEnd: DispatchWorkItem?
    
    // ROUNDING ITS OWN CORNERS
    //
    // The card used to clip everything inside it to its rounded outline and
    // cast its shadow from the result. SwiftUI redoes both on every frame the
    // card moves, from every row of text in it, and with fifty track cards
    // scrolling they kept the GPU about 80 % busy.
    //
    // Only a handful of things in a track card ever reach its corners: the
    // header's tint band and hover wash, and the backgrounds of the last row.
    // A card that rounds its own corners hands its outline down to those
    // backgrounds (`cardBackground`), which shape themselves to it — the same
    // pixels the clip produced. (The shadow, like every glass surface's, is
    // pre-drawn by CardShadow.)
    //
    // While the card opens or closes, the rows slide past the corners, so
    // for that half-second the real clip comes back. At rest the clip is a
    // plain rectangle, which costs nothing.
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header()
                .cardBackground(tint.opacity(reduceTransparency ? 0.16 : 0.10), at: .top)
                // Above the content, so rows sliding up while the card closes
                // pass underneath the header instead of over it.
                .zIndex(1)
            
            // The content stays in place and the card's height is what moves.
            //
            // The old version inserted and removed the content with a
            // move-and-fade transition. The card's outline jumped to its new
            // size while the rows were still sliding, so for a moment the text
            // hung outside the card, and the cards below snapped rather than
            // glided. Animating the height instead means the outline, the
            // rows inside it and everything below it all travel on one curve.
            content()
                // Rows drift a few points as they fade, like a sheet being
                // drawn down rather than a block being revealed. The drift
                // happens inside the clip below, so nothing ever shows above
                // the content's own top edge.
                .offset(y: isExpanded || reduceMotion ? 0 : -6)
                .opacity(isExpanded ? 1 : 0)
                // The text fades a little behind the height on the way in,
                // and well ahead of it on the way out, so it is never clipped
                // mid-fade by an edge that is still moving.
                .animation(contentFade, value: isExpanded)
                .frame(height: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        // So a background inside the card can find the card's corners.
        .coordinateSpace(GlassCardSpace.name)
        .environment(\.roundsCardCorners, roundsOwnCorners)
        // While the card opens or closes the real clip shapes the header;
        // only at rest does a closed card's header round its bottom corners.
        .environment(\.cardIsClosed, !isExpanded && !isDisclosing)
        .clipShape(RoundedRectangle(
            cornerRadius: roundsOwnCorners && !isDisclosing ? 0 : SMI.Radius.card,
            style: .continuous
        ))
        .liquidGlass(
            cornerRadius: SMI.Radius.card,
            tint: tint,
            borderOpacity: 0.22,
            elevation: SMI.Elevation.resting(tint),
            edgeInLayer: true
        )
        .smiAnimation(SMI.Motion.disclosure, value: isExpanded)
        .onChange(of: isExpanded) { _, _ in
            guard roundsOwnCorners else { return }
            // Switched without animation: the corner radius must not tween.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { isDisclosing = true }
            disclosureEnd?.cancel()
            let end = DispatchWorkItem {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { isDisclosing = false }
            }
            disclosureEnd = end
            // The height spring settles well inside this.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: end)
        }
    }
    
    private var contentFade: Animation {
        if reduceMotion { return SMI.Motion.reduced }
        // Timed against the height, which is a critically damped spring: it
        // covers about half its distance in the first 0.08 s and 80% by
        // 0.15 s, then spends the rest settling.
        //
        // Opening: the text starts once the card is about a third open and is
        // fully in by the time the card is ~95% open — following the edge
        // down rather than arriving after the card has finished, which made
        // the motion feel like two separate steps.
        //
        // Closing: ease-out, so the fade is quickest at the very start. The
        // previous ease-in held the text near full strength for the first
        // frames, exactly while the edge was already closing over it.
        return isExpanded
        ? .easeOut(duration: 0.18).delay(0.05)
        : .easeOut(duration: 0.12)
    }
}

// MARK: - Backgrounds that follow a card's corners
//
// Used inside GlassCard content for anything drawn edge to edge — header
// bands, hover washes, row backgrounds. In an ordinary card it is a plain
// background. In a card that rounds its own corners, a background at the
// card's top or bottom draws the card's own rounded outline, cut to its own
// rectangle — exactly the pixels the card's clip used to leave.
//
// A rectangular cut costs nothing, unlike the rounded clip it replaces, and
// nothing here is recomputed while the card scrolls.

/// Where a background sits in its card.
enum CardEdge {
    /// The header: the card's top corners, or all four when it is closed.
    case top
    /// One of the last rows: may reach the bottom corners.
    case bottom
}

private struct RoundsCardCornersKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CardIsClosedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var roundsCardCorners: Bool {
        get { self[RoundsCardCornersKey.self] }
        set { self[RoundsCardCornersKey.self] = newValue }
    }
    
    /// Closed and at rest, so the header is the whole card.
    fileprivate var cardIsClosed: Bool {
        get { self[CardIsClosedKey.self] }
        set { self[CardIsClosedKey.self] = newValue }
    }
}

/// GlassCard is generic, so its coordinate space name lives here.
enum GlassCardSpace {
    static let name: NamedCoordinateSpace = .named("SMIGlassCard")
}

extension View {
    /// A fill behind the view that follows the card's corners. Layered
    /// backgrounds (a row's stripe, then its hover wash) are written as
    /// successive calls, the one nearest the content first.
    func cardBackground<S: ShapeStyle>(_ style: S, at edge: CardEdge) -> some View {
        modifier(CardBackground(style: style, edge: edge))
    }
}

private struct CardBackground<S: ShapeStyle>: ViewModifier {
    let style: S
    let edge: CardEdge
    @Environment(\.roundsCardCorners) private var roundsCardCorners
    
    func body(content: Content) -> some View {
        // Anywhere a plain background would do, it is exactly the plain
        // background it always was.
        if !roundsCardCorners {
            content.background(style)
        } else if edge == .top {
            content.background { CardTopFill(style: style) }
        } else {
            content.background { CardBottomFill(style: style) }
        }
    }
}

/// Only used in a card that rounds its own corners (see CardBackground).
private struct CardTopFill<S: ShapeStyle>: View {
    let style: S
    @Environment(\.cardIsClosed) private var cardIsClosed
    
    var body: some View {
        CardTopOutline(isWholeCard: cardIsClosed).fill(style).clipped()
    }
}

/// Only used in a card that rounds its own corners (see CardBackground).
private struct CardBottomFill<S: ShapeStyle>: View {
    let style: S
    /// The card's rectangle in this view's coordinates. Measured once, and
    /// again only if the view moves within its card — never while scrolling.
    @State private var card: CGRect?
    
    var body: some View {
        Group {
            if let card {
                CardOutline(card: card).fill(style).clipped()
            } else {
                Rectangle().fill(style)
            }
        }
        .onGeometryChange(for: CGRect?.self) { $0.bounds(of: GlassCardSpace.name) } action: { card = $0 }
    }
}

/// The card's rounded outline, given in the shape's own coordinates.
private struct CardOutline: Shape {
    var card: CGRect
    
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: SMI.Radius.card, style: .continuous).path(in: card)
    }
}

/// The card's outline as seen from its header: the header is the card's top,
/// so the card's top corners are the header's — and when the card is closed,
/// the header is the whole card.
private struct CardTopOutline: Shape {
    var isWholeCard: Bool
    
    func path(in rect: CGRect) -> Path {
        let card = isWholeCard
        ? rect
        : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + 10_000)
        return RoundedRectangle(cornerRadius: SMI.Radius.card, style: .continuous).path(in: card)
    }
}


// MARK: - Card stack
//
// The column the track cards sit in.
//
// A LazyVStack builds cards only as they scroll into view. That is also what
// made opening and closing a card look uneven: when a card closes, the cards
// below slide up, and any card that comes into view part-way through is
// created already at its final position — it pops in while its neighbours are
// still gliding. An ordinary VStack builds every card up front, so they all
// travel together. Files with a great many tracks (a Blu-ray remux with 50+
// subtitle streams) keep the lazy stack, where building everything at once
// would cost more than the smoother motion is worth.

struct CardStack<Content: View>: View {
    let itemCount: Int
    var spacing: CGFloat = SMI.Spacing.large
    @ViewBuilder var content: () -> Content
    
    static var eagerLimit: Int { 30 }
    
    var body: some View {
        if itemCount <= Self.eagerLimit {
            VStack(alignment: .leading, spacing: spacing, content: content)
        } else {
            LazyVStack(alignment: .leading, spacing: spacing, content: content)
        }
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

// MARK: - Gradient background
//
// Three blurred discs of colour behind the window (the user's palette), so
// the glass panels have something to pick colour up from — without it the
// glass reads as grey. Settings › Appearance › Background, or ⌘B:
//
//   • Off — nothing is drawn.
//   • Static — the default: the discs sit at one fixed moment and the
//     picture is drawn once.
//   • Animated — the discs drift slowly along lissajous paths.
//
// The drawing is GradientLayerView's: each disc is drawn and blurred once,
// at a quarter of its size (an 80-point blur leaves no detail to lose), and
// moved by a timer twelve times a second, so the drift costs the app nothing
// per frame.
//
// WHEN IT HOLDS STILL
//
// The animated mode freezes, keeping its colour, while the app is inactive
// or the window is hidden, while a list is scrolling, under Reduce Motion,
// and in Low Power Mode.
//
// WHY STATIC IS THE ONE THAT MATTERS
//
// The cost was never the background alone. It was that sixteen to twenty
// frosted glass panels each have to re-sample their backdrop every time it
// moves — including the glass above a row as the pointer hovers it. Freezing
// the backdrop ends that recomputation everywhere at once.

struct GradientBackground: View {
    @State private var isAppActive = true
    @State private var isScrolling = false
    @State private var scrollDebounce: DispatchWorkItem? = nil
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    
    @AppStorage(BackgroundMode.key) private var modeRaw: String = BackgroundMode.shippedDefault.rawValue
    @AppStorage(BackgroundPalette.keys[0]) private var hex1: String = Color.brandViolet.smiHex
    @AppStorage(BackgroundPalette.keys[1]) private var hex2: String = Color.brandPink.smiHex
    @AppStorage(BackgroundPalette.keys[2]) private var hex3: String = Color.brandBlue.smiHex
    /// Where the discs sit in Static, chosen in Settings › Appearance.
    @AppStorage(StaticBlobLayout.key) private var blobPositions: String = ""
    
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
            isAppActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAppActive = true
        }
        // Pause animation during scrolling
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
            scrollDebounce?.cancel()
            if !isScrolling {
                isScrolling = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
            // Resume after a short delay so rapid scroll gestures don't flicker
            let item = DispatchWorkItem { isScrolling = false }
            scrollDebounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
        // The system posts this when Low Power Mode is switched on
        // or off, so the change takes effect immediately rather than at next
        // launch.
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            let low = ProcessInfo.processInfo.isLowPowerModeEnabled
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
                isAppActive = false
            }
        }
    }
    
    /// Drawn and moved by Core Animation (GradientLayerView), so the drift
    /// costs the app nothing per frame. Static mode places the discs where
    /// StaticBlobLayout says; the other reasons for holding still freeze them
    /// wherever they are.
    private var scaledCanvas: some View {
        GradientLayerView(
            colors: colors.map { NSColor($0) },
            isAnimating: shouldAnimate,
            staticPositions: mode == .staticGradient
                ? StaticBlobLayout.decode(blobPositions) ?? StaticBlobLayout.defaults
                : nil
        )
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
            // Slimmer than the other toolbar buttons (56 + 2×4 rather
            // than 62 + 2×10): six of them side by side made room for Siri AI
            // without widening the window.
            .frame(minWidth: 56, minHeight: 47)
            .padding(.horizontal, 4)
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
        .help("\(mode.label) View (⌃⌘\(String(mode.shortcut.character)))")
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
