import SwiftUI

final class LockScreenLiveActivityOverlayModel: ObservableObject {
	@Published var iconName: String = "lock.fill"
	@Published var scale: CGFloat = 0.6
	@Published var opacity: Double = 0
}

struct LockScreenLiveActivityOverlay: View {
	@ObservedObject var model: LockScreenLiveActivityOverlayModel
	let notchSize: CGSize

	private var indicatorSize: CGFloat {
		max(0, notchSize.height - 12)
	}

	private var horizontalPadding: CGFloat {
		cornerRadiusInsets.closed.bottom
	}

	private var totalWidth: CGFloat {
		notchSize.width + (indicatorSize * 2) + (horizontalPadding * 2)
	}

	var body: some View {
		HStack(spacing: 0) {
			Color.clear
				.overlay(alignment: .leading) {
					Image(systemName: model.iconName)
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white)
						.frame(width: indicatorSize, height: indicatorSize)
				}
				.frame(width: indicatorSize, height: notchSize.height)

			Rectangle()
				.fill(.black)
				.frame(width: notchSize.width, height: notchSize.height)

			Color.clear
				.frame(width: indicatorSize, height: notchSize.height)
		}
		.frame(width: notchSize.width + (indicatorSize * 2), height: notchSize.height)
		.padding(.horizontal, horizontalPadding)
		.background(Color.black)
		.clipShape(
			NotchShape(
				topCornerRadius: cornerRadiusInsets.closed.top,
				bottomCornerRadius: cornerRadiusInsets.closed.bottom
			)
		)
		.frame(width: totalWidth, height: notchSize.height)
		.scaleEffect(x: model.scale, y: 1, anchor: .center)
		.opacity(model.opacity)
		.drawingGroup()
	}
}
