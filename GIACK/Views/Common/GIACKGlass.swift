//
//  GIACKGlass.swift
//  GIACK
//
//  This file is part of GIACK.
//
//  GIACK is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  GIACK is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with GIACK.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI

enum GIACKBrandPalette {
    static let amber = Color(red: 0.95, green: 0.63, blue: 0.24)
    static let copper = Color(red: 0.79, green: 0.30, blue: 0.15)
    static let gold = Color(red: 0.98, green: 0.81, blue: 0.49)
    static let smoke = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let slate = Color(red: 0.15, green: 0.17, blue: 0.21)
    static let mist = Color(red: 0.94, green: 0.97, blue: 1.00)
}

struct GIACKBrandIcon: View {
    var size: CGFloat = 64

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.26), radius: size * 0.18, x: 0, y: size * 0.09)
    }
}

extension View {
    func giackWindowBackground() -> some View {
        modifier(GIACKWindowBackground())
    }

    func giackPanelCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(GIACKPanelCard(cornerRadius: cornerRadius, padding: padding))
    }

    func giackGlassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(GIACKGlassCard(cornerRadius: cornerRadius))
    }

    @available(*, deprecated, renamed: "giackWindowBackground")
    func whiskyWindowBackground() -> some View { giackWindowBackground() }

    @available(*, deprecated, renamed: "giackPanelCard")
    func whiskyPanelCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        giackPanelCard(cornerRadius: cornerRadius, padding: padding)
    }

    @available(*, deprecated, renamed: "giackGlassCard")
    func whiskyGlassCard(cornerRadius: CGFloat = 22) -> some View { giackGlassCard(cornerRadius: cornerRadius) }
}

struct GIACKGlassBadge: View {
    @AppStorage("useGlassUI") private var useGlassUI = false
    let icon: String
    let title: String
    var tint: Color = .accentColor

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } icon: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if useGlassUI {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    }
            } else {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            }
        }
    }
}

private struct GIACKWindowBackground: ViewModifier {
    @AppStorage("useGlassUI") private var useGlassUI = false

    func body(content: Content) -> some View {
        if useGlassUI {
            content
                .background {
                    ZStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.13, green: 0.14, blue: 0.17),
                                        Color(red: 0.11, green: 0.12, blue: 0.15),
                                        Color(red: 0.12, green: 0.10, blue: 0.09)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .ignoresSafeArea()

                        LinearGradient(
                            colors: [
                                GIACKBrandPalette.gold.opacity(0.08),
                                Color.clear,
                                GIACKBrandPalette.copper.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        Circle()
                            .fill(GIACKBrandPalette.gold.opacity(0.08))
                            .frame(width: 420, height: 420)
                            .blur(radius: 80)
                            .offset(x: -220, y: -180)

                        Circle()
                            .fill(GIACKBrandPalette.copper.opacity(0.10))
                            .frame(width: 360, height: 360)
                            .blur(radius: 80)
                            .offset(x: 220, y: 170)
                    }
                }
        } else {
            content
        }
    }
}

private struct GIACKGlassCard: ViewModifier {
    @AppStorage("useGlassUI") private var useGlassUI = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if useGlassUI {
            content
                .padding(16)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 10)
        } else {
            content
        }
    }
}

private struct GIACKPanelCard: ViewModifier {
    @AppStorage("useGlassUI") private var useGlassUI = false
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if useGlassUI {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        }
                }
            }
            .shadow(
                color: .black.opacity(useGlassUI ? 0.12 : 0.04),
                radius: useGlassUI ? 16 : 8,
                x: 0,
                y: useGlassUI ? 10 : 4
            )
    }
}
