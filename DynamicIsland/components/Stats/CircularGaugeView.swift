import SwiftUI

struct CircularGaugeView: View {
    let title: String
    let value: Double
    let tint: Color
    let centerPrimaryText: String
    var centerSecondaryText: String? = nil
    var subtitle: String? = nil
    var size: CGFloat = 72
    var lineWidth: CGFloat = 8
    var backgroundTint: Color = Color.primary.opacity(0.08)

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(backgroundTint, lineWidth: lineWidth)
                    .frame(width: size, height: size)
                if value > 0 {
                    RingArc(start: 0, end: min(max(value, 0), 1), color: tint, lineWidth: lineWidth)
                        .frame(width: size, height: size)
                }
                VStack(spacing: 2) {
                    Text(centerPrimaryText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(tint)
                    if let centerSecondaryText, !centerSecondaryText.isEmpty {
                        Text(centerSecondaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
