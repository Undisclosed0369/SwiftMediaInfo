//
//  PressableIcon.swift
//  SwiftMediaInfo
//
//  The app icon in About and Settings, made to feel physical: it shrinks
//  while the mouse button is held and springs back to full size when it is
//  let go, which is when its action runs — as long as the pointer is still
//  over it. Dragging off before letting go cancels, as with any button.
//  With Reduce Motion on, the icon stays still and the action still runs.
//

import SwiftUI

struct PressableIcon: ViewModifier {
    let action: () -> Void

    @State private var isPressed = false
    @State private var size: CGSize = .zero

    /// How small the icon gets while held.
    private static let pressedScale: CGFloat = 0.88

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? Self.pressedScale : 1)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let inside = contains(value.location)
                        guard inside != isPressed else { return }
                        // Sinking in is quick and soft…
                        animate(.spring(duration: 0.22, bounce: 0)) { isPressed = inside }
                    }
                    .onEnded { value in
                        // …coming back has a little bounce.
                        animate(.spring(duration: 0.45, bounce: 0.45)) { isPressed = false }
                        if contains(value.location) { action() }
                    }
            )
            .accessibilityAction { action() }
    }

    private func contains(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: size).contains(point)
    }

    private func animate(_ animation: Animation, _ change: () -> Void) {
        if SMI.Access.reduceMotion {
            change()
        } else {
            withAnimation(animation, change)
        }
    }
}

extension View {
    /// Shrinks while pressed, springs back on release, then runs `action`.
    func pressableIcon(action: @escaping () -> Void) -> some View {
        modifier(PressableIcon(action: action))
    }
}
