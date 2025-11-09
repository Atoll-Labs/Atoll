//
//  DoNotDisturbLiveActivity.swift
//  DynamicIsland
//
//  Renders the closed-notch Focus indicator with per-mode colours and
//  an icon-first layout that collapses gracefully when Focus ends.
//

import Defaults
import SwiftUI

struct DoNotDisturbLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = DoNotDisturbManager.shared
    @Default(.showDoNotDisturbLabel) private var showLabelSetting

    @State private var isExpanded = false
    @State private var showInactiveIcon = false
    @State private var iconScale: CGFloat = 1.0
    @State private var scaleResetTask: Task<Void, Never>?
    @State private var collapseTask: Task<Void, Never>?
    @State private var cleanupTask: Task<Void, Never>?
    @State private var labelIntrinsicWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            iconWing
                .frame(width: iconWingWidth, height: wingHeight)

            Rectangle()
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width)

            labelWing
                .frame(width: labelWingWidth, height: wingHeight)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onAppear(perform: handleInitialState)
        .onChange(of: manager.isDoNotDisturbActive, handleFocusStateChange)
        .onDisappear(perform: cancelPendingTasks)
    }

    // MARK: - Layout helpers

    private var wingHeight: CGFloat {
        max(vm.effectiveClosedNotchHeight - 10, 20)
    }

    private var iconWingWidth: CGFloat {
        (isExpanded || showInactiveIcon) ? minimalWingWidth : 0
    }

    private var labelWingWidth: CGFloat {
        if shouldShowLabel {
            return max(desiredLabelWidth, minimalWingWidth)
        }
        return (isExpanded || showInactiveIcon) ? minimalWingWidth : 0
    }

    private var minimalWingWidth: CGFloat {
        max(vm.effectiveClosedNotchHeight - 12, 24)
    }

    private var desiredLabelWidth: CGFloat {
        let measuredWidth = labelIntrinsicWidth + 8 // horizontal padding inside the label
        let fallbackWidth = max(vm.closedNotchSize.width * 0.52, 136)
        return max(measuredWidth, fallbackWidth)
    }

    private var shouldShowLabel: Bool {
        showLabelSetting && isExpanded && !labelText.isEmpty
    }

    // MARK: - Focus metadata

    private var focusMode: FocusModeType {
        FocusModeType.resolve(
            identifier: manager.currentFocusModeIdentifier,
            name: manager.currentFocusModeName
        )
    }

    private var activeAccentColor: Color {
        focusMode.accentColor
    }

    private var labelText: String {
        let trimmed = manager.currentFocusModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if focusMode == .doNotDisturb {
                return "Focus"
            }
            return trimmed
        }

        let fallback = focusMode.displayName
        if focusMode == .doNotDisturb {
            return "Focus"
        }
        return fallback.isEmpty ? "Focus" : fallback
    }

    private var accessibilityDescription: String {
        if manager.isDoNotDisturbActive {
            return "Focus active: \(labelText)"
        } else {
            return "Focus inactive"
        }
    }

    private var currentIconName: String {
        if manager.isDoNotDisturbActive {
            return focusMode.sfSymbol
        } else if showInactiveIcon {
            return focusMode.inactiveSymbol
        } else {
            return focusMode.sfSymbol
        }
    }

    private var currentIconColor: Color {
        if manager.isDoNotDisturbActive {
            return activeAccentColor
        } else if showInactiveIcon {
            return .white
        } else {
            return activeAccentColor
        }
    }

    // MARK: - Subviews

    private var iconWing: some View {
        Color.clear
            .overlay(alignment: .center) {
                if iconWingWidth > 0 {
                    Image(systemName: currentIconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(currentIconColor)
                        .contentTransition(.opacity)
                        .scaleEffect(iconScale)
                        .animation(.none, value: iconScale)
                }
            }
            .animation(.smooth(duration: 0.3), value: iconWingWidth)
    }

    private var labelWing: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                if shouldShowLabel {
                    Text(labelText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(activeAccentColor)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: FocusLabelWidthPreferenceKey.self, value: proxy.size.width)
                            }
                        )
                        .padding(.horizontal, 4)
                }
            }
            .animation(.smooth(duration: 0.3), value: shouldShowLabel)
            .onPreferenceChange(FocusLabelWidthPreferenceKey.self) { value in
                labelIntrinsicWidth = value
            }
    }

    // MARK: - State transitions

    private func handleInitialState() {
        if manager.isDoNotDisturbActive {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
        }
    }

    private func handleFocusStateChange(_ oldValue: Bool, _ isActive: Bool) {
        if isActive {
            cancelPendingTasks()
            withAnimation(.smooth(duration: 0.2)) {
                showInactiveIcon = false
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                iconScale = 1.0
                isExpanded = true
            }
        } else {
            triggerInactiveAnimation()
        }
    }

    private func triggerInactiveAnimation() {
        withAnimation(.smooth(duration: 0.2)) {
            showInactiveIcon = true
        }

        withAnimation(.interpolatingSpring(stiffness: 220, damping: 12)) {
            iconScale = 1.2
        }

        scaleResetTask?.cancel()
        scaleResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.smooth(duration: 0.2)) {
                showInactiveIcon = false
            }
        }

        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.smooth(duration: 0.32)) {
                isExpanded = false
            }
        }

        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.smooth(duration: 0.2)) {
                showInactiveIcon = false
            }
        }
    }

    private func cancelPendingTasks() {
        scaleResetTask?.cancel()
        collapseTask?.cancel()
        cleanupTask?.cancel()
        scaleResetTask = nil
        collapseTask = nil
        cleanupTask = nil
    }
}

#Preview {
    DoNotDisturbLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 320, height: 54)
        .background(Color.black)
}

private struct FocusLabelWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
