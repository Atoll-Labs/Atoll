import SwiftUI
import AtollExtensionKit

struct ExtensionLiveActivityStandaloneView: View {
    let payload: ExtensionLiveActivityPayload
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let isHovering: Bool

    private var descriptor: AtollLiveActivityDescriptor { payload.descriptor }
    private var contentHeight: CGFloat {
        max(0, notchHeight - (isHovering ? 0 : 12))
    }
    private var accentColor: Color { descriptor.accentColor.swiftUIColor }

    var body: some View {
        let baseWingWidth = max(contentHeight, 44)
        let trailingWidth = ExtensionLayoutMetrics.trailingWidth(
            for: payload,
            baseWidth: baseWingWidth,
            maxWidth: notchWidth * 0.42
        )
        let centerWidth = max(96, notchWidth - baseWingWidth - trailingWidth)

        return HStack(spacing: 0) {
            ExtensionCompositeIconView(
                leading: descriptor.leadingIcon,
                badge: descriptor.badgeIcon,
                accent: accentColor,
                size: contentHeight
            )
            .frame(width: baseWingWidth, height: contentHeight)

            Rectangle()
                .fill(Color.black)
                .frame(width: centerWidth, height: contentHeight)
                .overlay(centerContent)

            ExtensionMusicWingView(payload: payload, notchHeight: contentHeight)
                .frame(width: trailingWidth, height: contentHeight)
        }
        .frame(width: notchWidth, height: notchHeight + (isHovering ? 8 : 0))
        .animation(.smooth(duration: 0.25), value: payload.id)
    }

    private var centerContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(descriptor.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let subtitle = descriptor.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExtensionMusicWingView: View {
    let payload: ExtensionLiveActivityPayload
    let notchHeight: CGFloat

    private var descriptor: AtollLiveActivityDescriptor { payload.descriptor }
    private var accentColor: Color { descriptor.accentColor.swiftUIColor }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if case .none = descriptor.trailingContent {
                EmptyView()
            } else {
                ExtensionTrailingContentView(content: descriptor.trailingContent, accent: accentColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let indicator = descriptor.progressIndicator, indicator != .none {
                ExtensionProgressIndicatorView(
                    indicator: indicator,
                    progress: descriptor.progress,
                    accent: accentColor,
                    estimatedDuration: descriptor.estimatedDuration
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
    }
}
