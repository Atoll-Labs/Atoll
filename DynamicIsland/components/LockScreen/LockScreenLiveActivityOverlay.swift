//
//  LockScreenLiveActivityOverlay.swift
//  DynamicIsland
//
//  Mirrors the closed-notch live activity layout on the macOS lock screen.
//

import SwiftUI

enum LockLiveActivityState: Equatable {
    case locked
    case unlocking
}

final class LockScreenLiveActivityOverlayViewModel: ObservableObject {
    @Published var expansion: CGFloat = 1
}

struct LockScreenLiveActivityOverlay: View {
    let state: LockLiveActivityState
    let notchSize: CGSize
    @ObservedObject var viewModel: LockScreenLiveActivityOverlayViewModel

    private var indicatorSize: CGFloat {
        max(0, notchSize.height - 12)
    }

    private var horizontalPadding: CGFloat {
        cornerRadiusInsets.closed.bottom
    }

    private var baseWidth: CGFloat {
        notchSize.width + (indicatorSize * 2)
    }

    private var totalWidth: CGFloat {
        baseWidth + (horizontalPadding * 2)
    }

    private var iconName: String {
        state == .locked ? "lock.fill" : "lock.open.fill"
    }

    private var iconColor: Color { .white }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .overlay(alignment: .leading) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: indicatorSize, height: indicatorSize)
                }
                .frame(width: indicatorSize, height: notchSize.height, alignment: .top)

            Color.clear
                .frame(width: notchSize.width, height: notchSize.height, alignment: .top)

            Color.clear
                .frame(width: indicatorSize, height: notchSize.height, alignment: .top)
        }
        .frame(width: baseWidth, height: notchSize.height)
        .padding(.horizontal, horizontalPadding)
        .background(Color.black)
        .clipShape(
            NotchShape(
                topCornerRadius: cornerRadiusInsets.closed.top,
                bottomCornerRadius: cornerRadiusInsets.closed.bottom
            )
        )
        .frame(width: totalWidth, height: notchSize.height)
        .scaleEffect(x: max(0.05, viewModel.expansion), y: 1, anchor: .center)
        .opacity(min(1, max(0.2, viewModel.expansion * 5)))
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.expansion)
        .drawingGroup()
    }
}

#Preview {
    let model = LockScreenLiveActivityOverlayViewModel()
    return VStack(spacing: 24) {
        LockScreenLiveActivityOverlay(state: .locked, notchSize: CGSize(width: 220, height: 32), viewModel: model)
        LockScreenLiveActivityOverlay(state: .unlocking, notchSize: CGSize(width: 220, height: 32), viewModel: model)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
