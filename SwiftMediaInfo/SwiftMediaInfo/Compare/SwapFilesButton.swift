//
//  SwapFilesButton.swift
//  SwiftMediaInfo
//
//  Swapping File A and File B: the button, and the motion of the two panes
//  crossing over (driven by the store's `swapToken`, so both panes move
//  symmetrically).
//

import SwiftUI

// MARK: - Swap motion
//
// The visual half of a swap: both panes fade back and slide toward each other,
// then settle. Mirrored by `isLeftPane`, so the two genuinely cross rather than
// drifting the same way.
//
// Applied as a modifier driven by a shared progress value rather than left to
// SwiftUI's implicit animation. Implicitly, only the pane that kept its view
// identity through the swap animated at all — and which pane that was
// alternated with every press.

struct SwapMotion: ViewModifier {
    let progress: CGFloat
    let isLeftPane: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var travel: CGFloat {
        // No spatial movement under Reduce Motion — the fade alone still
        // signals that something changed.
        guard !reduceMotion else { return 0 }
        return isLeftPane ? 22 : -22
    }
    
    func body(content: Content) -> some View {
        content
            .offset(x: progress * travel)
            .opacity(1 - progress * 0.55)
            .blur(radius: reduceMotion ? 0 : progress * 1.5)
    }
}

// MARK: - Swap control
//
// Exchanges File A and File B without re-reading either from disk: the loaded
// files trade places wholesale, cached formats and all.
//
// Placed on the divider rather than in the toolbar because that is where the
// thing it acts on lives. A toolbar button would be more discoverable and less
// connected to its effect; the ⌘⇧S shortcut and the tooltip cover discovery.

struct SwapFilesButton: View {
    @EnvironmentObject var store: MediaStore
    
    @State private var isHovering = false
    @State private var rotation: Double = 0
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var size: CGFloat { CGFloat(store.fontSize) * 2.9 }
    
    var body: some View {
        Button(action: swap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.brandBlue.opacity(isHovering ? 0.30 : 0.16),
                                Color.brandPink.opacity(isHovering ? 0.30 : 0.16)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.brandBlue.opacity(isHovering ? 0.9 : 0.45),
                                Color.brandPink.opacity(isHovering ? 0.9 : 0.45)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: isHovering ? 1.6 : 1
                    )
                
                // Left-and-right arrows: the gesture the button performs,
                // stated as plainly as a glyph can.
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: size, height: size)
            .smiShadow(
                isHovering
                ? SMI.Elevation.floating(.brandViolet)
                : SMI.Elevation.raised(.brandViolet)
            )
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(scale: 0.90))
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.snap, value: isHovering)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .help("Swap File A and File B (⌘⇧S)")
        .accessibilityLabel("Swap File A and File B")
    }
    
    private func swap() {
        store.swapCompareFiles()
        
        // A half turn per press, accumulating rather than resetting, so a
        // second swap continues the rotation instead of snapping back — the
        // motion reads as the panes changing places rather than as an icon
        // twitching.
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
            rotation += 180
        }
    }
}
