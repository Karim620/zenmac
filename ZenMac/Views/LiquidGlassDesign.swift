//
//  LiquidGlassDesign.swift
//  ZenMac
//
//  Native macOS Liquid Glass geometry, specular refractive rim lighting,
//  and fluid mesh ambient canvas.
//

import SwiftUI

// MARK: - 1. Liquid Glass Shape Modifier

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color
    public var isInteractive: Bool

    @State private var isHovered: Bool = false

    public init(cornerRadius: CGFloat = 24, tint: Color = .cyan, isInteractive: Bool = true) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    // 1. Base ultra-thin material blur
                    shape
                        .fill(.ultraThinMaterial)

                    // 2. Subtle chromatic tint wash
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(isHovered ? 0.14 : 0.08),
                                    .white.opacity(isHovered ? 0.07 : 0.03),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 3. Top-edge inner liquid gloss reflection
                    shape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(isHovered ? 0.22 : 0.14), location: 0.0),
                                    .init(color: .white.opacity(0.02), location: 0.35),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(color: .black.opacity(0.24), radius: isHovered ? 20 : 14, x: 0, y: isHovered ? 10 : 6)
                .shadow(color: tint.opacity(isHovered ? 0.16 : 0.06), radius: 18, x: 0, y: 4)
            }
            .overlay {
                // 4. Dual Specular Rim Border (bright top-left catchlight + refractive bottom-right edge)
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isHovered ? 0.65 : 0.45), location: 0.0),
                                .init(color: tint.opacity(isHovered ? 0.40 : 0.22), location: 0.35),
                                .init(color: .white.opacity(0.06), location: 0.70),
                                .init(color: .white.opacity(isHovered ? 0.30 : 0.18), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 1.35 : 1.0
                    )
            }
            .scaleEffect(isInteractive && isHovered ? 1.006 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isHovered)
            .onHover { hovering in
                guard isInteractive else { return }
                isHovered = hovering
            }
    }
}

// MARK: - 2. Liquid Glass Capsule Pill Modifier

public struct LiquidGlassPillModifier: ViewModifier {
    public var tint: Color
    public var isProminent: Bool

    @State private var isHovered: Bool = false

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isProminent
                                    ? [tint.opacity(isHovered ? 0.55 : 0.40), tint.opacity(isHovered ? 0.30 : 0.18)]
                                    : [.white.opacity(isHovered ? 0.14 : 0.07), tint.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: isProminent ? tint.opacity(0.28) : .black.opacity(0.15), radius: 10, x: 0, y: 4)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isHovered ? 0.70 : 0.45),
                                tint.opacity(0.30),
                                .white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - 3. Ambient Fluid Backdrop (Refracts through Liquid Glass)

public struct LiquidAmbientBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.55)

            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.mint.opacity(0.22), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: geo.size.width * 0.48
                            )
                        )
                        .frame(width: geo.size.width * 0.75, height: geo.size.width * 0.75)
                        .offset(x: -geo.size.width * 0.22, y: -geo.size.height * 0.25)
                        .blur(radius: 45)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.cyan.opacity(0.20), .clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: geo.size.width * 0.45
                            )
                        )
                        .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
                        .offset(x: geo.size.width * 0.28, y: geo.size.height * 0.20)
                        .blur(radius: 50)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.indigo.opacity(0.16), .clear],
                                center: .center,
                                startRadius: 5,
                                endRadius: geo.size.width * 0.35
                            )
                        )
                        .frame(width: geo.size.width * 0.55, height: geo.size.width * 0.55)
                        .offset(x: geo.size.width * 0.05, y: -geo.size.height * 0.1)
                        .blur(radius: 40)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a squircle Liquid Glass container with specular rim highlights and inner chromatic refraction.
    public func liquidGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color = .cyan,
        isInteractive: Bool = true
    ) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isInteractive: isInteractive))
    }

    /// Applies a capsule-shaped Liquid Glass pill style for buttons, badges, and status controls.
    public func liquidGlassPill(tint: Color = .mint, isProminent: Bool = false) -> some View {
        modifier(LiquidGlassPillModifier(tint: tint, isProminent: isProminent))
    }
}
