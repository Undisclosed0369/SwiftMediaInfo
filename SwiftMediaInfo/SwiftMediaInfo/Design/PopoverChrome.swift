//
//  PopoverChrome.swift
//  SwiftMediaInfo
//
//  The pieces the toolbar's small menus are built from — Copy, Export,
//  Share and Open in Default App — so each draws its title, rows and back
//  button the same way.
//
//  Every row lights up under the pointer, as the Compare With list's rows
//  always have, and the two-step menus (a file, then a format) slide between
//  their steps like a navigation stack.
//

import SwiftUI

/// A menu's title, in the headline style.
struct PopoverTitle: View {
    let text: String
    /// None under a back button, which already gives the menu its top margin.
    var topPadding: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, topPadding)
            .padding(.bottom, 4)
    }
}

/// The soft wash behind a row under the pointer, inset from the menu's
/// edges, fading in and out.
struct PopoverRowHighlight: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.chip, style: .continuous)
                    .fill(SMI.Palette.hoverWash)
                    .padding(.horizontal, 4)
                    .opacity(isHovering ? 1 : 0)
            )
            .onHover { isHovering = $0 }
            .smiAnimation(SMI.Motion.fade, value: isHovering)
    }
}

extension View {
    func popoverRowHighlight() -> some View { modifier(PopoverRowHighlight()) }
}

/// One action in a menu.
struct PopoverMenuItem: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .popoverRowHighlight()
        }
        .buttonStyle(.plain)
    }
}

/// A choice that leads on to a second step — a file, then what to do with
/// it — marked with a chevron that leans forward under the pointer.
struct PopoverChoiceRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(isHovering ? .primary : .secondary)
                    .font(.caption)
                    .offset(x: isHovering ? 2 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: SMI.Radius.chip, style: .continuous)
                    .fill(SMI.Palette.hoverWash)
                    .padding(.horizontal, 4)
                    .opacity(isHovering ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .smiAnimation(SMI.Motion.snap, value: isHovering)
    }
}

/// Back to the first step, named after the choice made there.
///
/// In the primary text colour on a light capsule. It used to be drawn in the
/// accent colour, which macOS greys out in a popover — the window it sits in
/// is never the key window — so it all but disappeared.
struct PopoverBackButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .offset(x: isHovering ? -2 : 0)
                    Text(title)
                        .font(.callout.weight(.medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.14 : 0.08))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(GlassPressStyle())
            .onHover { isHovering = $0 }
            .smiAnimation(SMI.Motion.snap, value: isHovering)
            .help("Back")
            .accessibilityLabel("Back to \(title)")
            .padding(.leading, 8)
            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

/// A two-step menu's steps: the second slides in from the trailing edge and
/// the first comes back from the leading edge, as in a navigation stack.
/// With Reduce Motion on, they simply cross-fade.
struct PopoverSteps<First: View, Second: View>: View {
    let showsSecond: Bool
    /// Whether the change was a step back, which slides the other way.
    let isGoingBack: Bool
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsSecond {
                second().transition(transition)
            } else {
                first().transition(transition)
            }
        }
        .clipped()
    }

    private var transition: AnyTransition {
        guard !SMI.Access.reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing).combined(with: .opacity),
            removal: .move(edge: isGoingBack ? .trailing : .leading).combined(with: .opacity)
        )
    }
}

extension SMI.Motion {
    /// A two-step menu moving between its steps.
    static let popoverStep = Animation.spring(duration: 0.32, bounce: 0)
}
