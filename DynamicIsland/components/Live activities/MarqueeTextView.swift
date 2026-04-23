/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    
    @State private var animate = false
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    
    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }
    
    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                HStack(spacing: 20) {
                    Text(text)
                    Text(text)
                        .opacity(needsScrolling ? 1 : 0)
                }
                .id(text)
                .font(font)
                .foregroundColor(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: self.animate ? offset : 0)
                .animation(
                    self.animate ?
                        .linear(duration: Double(textSize.width / 30))
                        .delay(minDuration)
                        .repeatForever(autoreverses: false) : .none,
                    value: self.animate
                )
                .background(backgroundColor)
                .modifier(MeasureSizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    self.textSize = CGSize(width: size.width / 2, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                    self.animate = false
                    self.offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02){
                        if needsScrolling {
                            self.animate = true
                            self.offset = -(textSize.width + 20)
                        }
                    }
                }
                .onChange(of: text) { _, _ in
                    // Reset animation when text changes
                    self.animate = false
                    self.offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02){
                        if needsScrolling {
                            self.animate = true
                            self.offset = -(textSize.width + 20)
                        }
                    }
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: textSize.height * 1.3)
        
    }
}

struct MusicExplicitBadge: View {
    var label: String = "E"
    var fontSize: CGFloat = 9
    var height: CGFloat = 14
    var horizontalPadding: CGFloat = 4
    var minWidth: CGFloat? = nil
    var foregroundColor: Color = .white.opacity(0.92)
    var backgroundColor: Color = .white.opacity(0.18)
    var cornerRadius: CGFloat? = nil
    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, max(horizontalPadding, height * 0.2))
            .frame(minWidth: minWidth, minHeight: height)
            .background(
                RoundedRectangle(
                    cornerRadius: cornerRadius ?? max(4, height * 0.28),
                    style: .continuous
                )
                .fill(backgroundColor)
            )
            .fixedSize()
    }
}

struct MusicTitleMarqueeView: View {
    let text: String
    let isExplicit: Bool
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    let alignment: Alignment
    let badgeSpacing: CGFloat
    let badgeLabel: String
    let badgeFontSize: CGFloat?
    let badgeHeight: CGFloat?
    let badgeForegroundColor: Color
    let badgeBackgroundColor: Color
    let badgeHorizontalPadding: CGFloat
    let badgeMinWidth: CGFloat?
    let badgeCornerRadius: CGFloat?

    init(
        text: String,
        isExplicit: Bool,
        font: Font = .body,
        nsFont: NSFont.TextStyle = .body,
        textColor: Color = .primary,
        backgroundColor: Color = .clear,
        minDuration: Double = 3.0,
        frameWidth: CGFloat = 200,
        alignment: Alignment = .leading,
        badgeSpacing: CGFloat = 6,
        badgeLabel: String = "E",
        badgeFontSize: CGFloat? = nil,
        badgeHeight: CGFloat? = nil,
        badgeForegroundColor: Color = .white.opacity(0.92),
        badgeBackgroundColor: Color = .white.opacity(0.18),
        badgeHorizontalPadding: CGFloat = 4,
        badgeMinWidth: CGFloat? = nil,
        badgeCornerRadius: CGFloat? = nil
    ) {
        self.text = text
        self.isExplicit = isExplicit
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
        self.alignment = alignment
        self.badgeSpacing = badgeSpacing
        self.badgeLabel = badgeLabel
        self.badgeFontSize = badgeFontSize
        self.badgeHeight = badgeHeight
        self.badgeForegroundColor = badgeForegroundColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeHorizontalPadding = badgeHorizontalPadding
        self.badgeMinWidth = badgeMinWidth
        self.badgeCornerRadius = badgeCornerRadius
    }

    private var resolvedBadgeHeight: CGFloat {
        badgeHeight ?? max(12, NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.12)
    }

    private var resolvedBadgeFontSize: CGFloat {
        badgeFontSize ?? max(8, resolvedBadgeHeight * 0.6)
    }

    private var reservedBadgeWidth: CGFloat {
        guard isExplicit else { return 0 }
        return resolvedBadgeHeight + (resolvedBadgeHeight * 0.7) + badgeSpacing
    }

    private var titleFrameWidth: CGFloat {
        max(0, frameWidth - reservedBadgeWidth)
    }

    private var measurementFont: NSFont {
        NSFont.preferredFont(forTextStyle: nsFont)
    }

    private var measuredTextWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: measurementFont]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private var needsScrolling: Bool {
        measuredTextWidth > titleFrameWidth
    }

    var body: some View {
        HStack(spacing: badgeSpacing) {
            if needsScrolling {
                MarqueeText(
                    .constant(text),
                    font: font,
                    nsFont: nsFont,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    minDuration: minDuration,
                    frameWidth: titleFrameWidth
                )
            } else {
                Text(text)
                    .font(font)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if isExplicit {
                MusicExplicitBadge(
                    label: badgeLabel,
                    fontSize: resolvedBadgeFontSize,
                    height: resolvedBadgeHeight,
                    horizontalPadding: badgeHorizontalPadding,
                    minWidth: badgeMinWidth,
                    foregroundColor: badgeForegroundColor,
                    backgroundColor: badgeBackgroundColor,
                    cornerRadius: badgeCornerRadius
                )
            }
        }
        .frame(width: frameWidth, alignment: alignment)
    }
}
