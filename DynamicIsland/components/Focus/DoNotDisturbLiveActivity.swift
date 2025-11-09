//
//  DoNotDisturbLiveActivity.swift
//  DynamicIsland
//
//  Renders the closed-notch Focus indicator with a purple moon badge.
//

import SwiftUI

struct DoNotDisturbLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = DoNotDisturbManager.shared
    @State private var isExpanded = false

    private let focusColor = Color.purple

    var body: some View {
        HStack(spacing: 0) {
            leadingWing
                .frame(width: leadingWingWidth, height: wingHeight)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            trailingWing
                .frame(width: trailingWingWidth, height: wingHeight)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = true
            }
        }
        .onChange(of: manager.isDoNotDisturbActive) { _, isActive in
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = isActive
            }
        }
    }

    private var wingHeight: CGFloat {
        max(vm.effectiveClosedNotchHeight - 10, 20)
    }

    private var leadingWingWidth: CGFloat {
        isExpanded ? max(vm.effectiveClosedNotchHeight - 10, 20) : 0
    }

    private var trailingWingWidth: CGFloat {
        guard isExpanded else { return 0 }
        return max(vm.closedNotchSize.width * 0.65, 120)
    }

    private var focusSymbol: String {
        if let symbol = FocusModeType(rawValue: manager.currentFocusModeIdentifier)?.sfSymbol {
            return symbol
        }
        return FocusModeType.doNotDisturb.sfSymbol
    }

    private var focusLabel: String {
        if !manager.currentFocusModeName.isEmpty {
            return manager.currentFocusModeName
        }
        return FocusModeType(rawValue: manager.currentFocusModeIdentifier)?.displayName ?? "Do Not Disturb"
    }

    private var accessibilityDescription: String {
        "Focus mode active: \(focusLabel)"
    }

    private var leadingWing: some View {
        Color.clear
            .background {
                if isExpanded {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(focusColor.opacity(0.18))

                        Image(systemName: focusSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(focusColor)
                    }
                    .frame(width: leadingWingWidth, height: wingHeight)
                }
            }
    }

    private var trailingWing: some View {
        Color.clear
            .background {
                if isExpanded {
                    HStack {
                        Text(focusLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(focusColor)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(
                        Capsule(style: .continuous)
                            .fill(focusColor.opacity(0.18))
                    )
                }
            }
    }
}

#Preview {
    DoNotDisturbLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 320, height: 54)
        .background(Color.black)
}
