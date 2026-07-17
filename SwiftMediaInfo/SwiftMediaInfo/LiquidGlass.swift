//
//  LiquidGlass.swift
//  SwiftMediaInfo
//
//  Shared design tokens, colours, and reusable view modifiers for the
//  Liquid Glass visual language used throughout SwiftMediaInfo.
//

import SwiftUI
import AppKit

// MARK: - Brand Palette

extension Color {
    /// Violet  #8d42f5
    static let brandViolet = Color(red: 0.553, green: 0.259, blue: 0.961)
    /// Pink    #e042f5
    static let brandPink   = Color(red: 0.878, green: 0.259, blue: 0.961)
    /// Blue    #42a1f5
    static let brandBlue   = Color(red: 0.259, green: 0.631, blue: 0.961)
    /// Green   #42f566
    static let brandGreen  = Color(red: 0.259, green: 0.961, blue: 0.400)
}

// MARK: - Gradient presets

extension LinearGradient {
    /// Blue → Violet diagonal
    static let brandBlueViolet = LinearGradient(
        colors: [.brandBlue, .brandViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Full spectrum (for decorative use)
    static let brandSpectrum = LinearGradient(
        colors: [.brandBlue, .brandViolet, .brandPink],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Glass surface modifier
//
// Reproduces the "Liquid Glass" pill style from Apple Music's tab bar:
//   • ultra-thin material blur background (picks up colour from what's behind it)
//   • a very subtle inner border in a brand colour at low opacity
//   • a thin specular highlight along the top edge

struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tintColor: Color = .brandViolet
    var borderOpacity: Double = 0.25
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base: frosted blur
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // Tint wash
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tintColor.opacity(0.07))
                    // Specular top shimmer
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                tintColor.opacity(borderOpacity),
                                tintColor.opacity(borderOpacity * 0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: tintColor.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        tintColor: Color = .brandViolet,
        borderOpacity: Double = 0.25
    ) -> some View {
        modifier(LiquidGlassSurface(
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            borderOpacity: borderOpacity
        ))
    }
}

// MARK: - Animated gradient background
//
// A slow-shifting mesh of brand colours — sits behind the window so the
// glass panels pick up colour. Uses a looping phase animation.
// Throttled to pause rendering when the app is inactive.

struct AnimatedGradientBackground: View {
    @State private var isAppActive = true
    @State private var pauseDate = Date()
    
    var body: some View {
        Group {
            if isAppActive {
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { context in
                    GradientCanvas(date: context.date)
                }
            } else {
                GradientCanvas(date: pauseDate)
            }
        }
        .blur(radius: 80)
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            pauseDate = Date()
            isAppActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAppActive = true
        }
        .onAppear {
            isAppActive = NSApplication.shared.isActive
        }
    }
}

private struct GradientCanvas: View {
    var date: Date
    
    var body: some View {
        Canvas { ctx, size in
            // Three overlapping radial blobs, slow lissajous motion
            let t = date.timeIntervalSinceReferenceDate * 0.45
            let w = size.width, h = size.height
            let blobs: [(x: Double, y: Double, r: Double, color: Color)] = [
                (
                    w * (0.3 + 0.25 * sin(t)),
                    h * (0.3 + 0.2  * cos(t * 0.7)),
                    min(w, h) * 0.55,
                    .brandViolet
                ),
                (
                    w * (0.7 + 0.2  * cos(t * 0.9)),
                    h * (0.6 + 0.25 * sin(t * 1.1)),
                    min(w, h) * 0.5,
                    .brandPink
                ),
                (
                    w * (0.5 + 0.3  * sin(t * 0.6 + 1)),
                    h * (0.2 + 0.3  * cos(t * 0.8 + 0.5)),
                    min(w, h) * 0.45,
                    .brandBlue
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

// MARK: - ViewMode tab bar pill (Apple Music style)
//
// A single pill that contains all tab icons + labels.
// The selected item gets a brand-colour capsule highlight.

struct LiquidGlassTabBar: View {
    @EnvironmentObject var store: MediaStore
    @Namespace private var ns
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases) { mode in
                TabPill(mode: mode, selected: store.viewMode == mode, namespace: ns) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        store.viewMode = mode
                    }
                }
            }
        }
        .padding(4)
        .liquidGlass(cornerRadius: 18, tintColor: .brandViolet, borderOpacity: 0.3)
    }
}

private struct TabPill: View {
    let mode: ViewMode
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    private var accentColor: Color {
        switch mode {
        case .easy:    return .brandBlue
        case .text:    return .brandViolet
        case .rawText: return .brandPink
        case .html:    return .brandGreen
        case .xml:     return .brandBlue
        case .json:    return .brandViolet
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: mode.icon)
                    .font(.system(size: 21, weight: selected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)
                Text(mode.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(selected ? accentColor : .secondary)
            .frame(minWidth: 62, minHeight: 47)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(accentColor.opacity(0.18))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(accentColor.opacity(0.35), lineWidth: 0.7)
                        )
                        .matchedGeometryEffect(id: "tab_highlight", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Spectrum divider

struct SpectrumDivider: View {
    var body: some View {
        LinearGradient.brandSpectrum
            .frame(height: 1)
            .opacity(0.35)
    }
}

// MARK: - Drop highlight overlay

struct GlassDropOverlay: View {
    var color: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(color, lineWidth: 2.5)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.08))
            )
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(color)
                        .symbolEffect(.pulse)
                    Text("Drop to open here")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
            )
            .padding(10)
            .allowsHitTesting(false)
    }
}
