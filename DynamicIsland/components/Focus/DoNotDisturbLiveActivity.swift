//
//  DoNotDisturbLiveActivity.swift
//  DynamicIsland
//
//  Renders the closed-notch Focus indicator with per-mode colours and
//  an icon-first layout that collapses gracefully when Focus ends.
//

import AppKit
import Defaults
import SwiftUI

struct DoNotDisturbLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = DoNotDisturbManager.shared
    @Default(.showDoNotDisturbLabel) private var showLabelSetting
    @Default(.focusIndicatorNonPersistent) private var focusToastMode

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
                .frame(width: centerSegmentWidth)

            labelWing
                .frame(width: labelWingWidth, height: wingHeight)
        }
        .frame(width: notchEnvelopeWidth, height: vm.effectiveClosedNotchHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onAppear(perform: handleInitialState)
        .onChange(of: manager.isDoNotDisturbActive, handleFocusStateChange)
        .onDisappear(perform: cancelPendingTasks)
    }

    // MARK: - Layout helpers

    private var collapsedNotchWidth: CGFloat {
        let width = currentClosedNotchWidth
        let scale = (resolvedScreen?.backingScaleFactor).flatMap { $0 > 0 ? $0 : nil }
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let aligned = (width * scale).rounded(.down) / scale
        return max(0, aligned)
    }

    private var currentClosedNotchWidth: CGFloat {
        if vm.notchState == .closed, vm.notchSize.width > 0 {
            return vm.notchSize.width
        }
        return vm.closedNotchSize.width
    }

    private var resolvedScreen: NSScreen? {
        if let name = vm.screen,
           let match = NSScreen.screens.first(where: { $0.localizedName == name }) {
            return match
        }
        return NSScreen.main
    }

    private var wingHeight: CGFloat {
        max(vm.effectiveClosedNotchHeight - 10, 20)
    }

    private var iconWingWidth: CGFloat {
        (isExpanded || showInactiveIcon) ? minimalWingWidth : 0
    }

    private var labelWingWidth: CGFloat {
        guard shouldShowLabel else {
            return focusToastMode ? 0 : ((isExpanded || showInactiveIcon) ? minimalWingWidth : 0)
        }

        if focusToastMode {
            return max(labelIntrinsicWidth + 26, minimalWingWidth)
        }

        return max(desiredLabelWidth, minimalWingWidth)
    }

    private var notchEnvelopeWidth: CGFloat {
        centerSegmentWidth + iconWingWidth + labelWingWidth
    }

    private var minimalWingWidth: CGFloat {
        max(vm.effectiveClosedNotchHeight - 12, 24)
    }

    private var closedNotchContentInset: CGFloat {
        cornerRadiusInsets.closed.top + cornerRadiusInsets.closed.bottom
    }

    private var collapsedToastBaseWidth: CGFloat {
        max(0, collapsedNotchWidth - closedNotchContentInset)
    }

    private var centerSegmentWidth: CGFloat {
        if focusToastMode && iconWingWidth == 0 && labelWingWidth == 0 {
            return collapsedToastBaseWidth
        }
        return collapsedNotchWidth
    }

    private var desiredLabelWidth: CGFloat {
        let measuredWidth = labelIntrinsicWidth + 8 // horizontal padding inside the label
        let fallbackWidth = max(collapsedNotchWidth * 0.52, 136)
        var width = max(measuredWidth, fallbackWidth)

        if focusMode == .doNotDisturb && shouldShowLabel {
            width = max(width, 164)
        }

        return width
    }

    private var shouldShowLabel: Bool {
        focusToastMode ? (isExpanded && !labelText.isEmpty) : (showLabelSetting && isExpanded && !labelText.isEmpty)
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
        if focusToastMode {
            return manager.isDoNotDisturbActive ? "On" : "Off"
        }

        let trimmed = manager.currentFocusModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if showLabelSetting {
            if !trimmed.isEmpty {
                return trimmed
            } else if focusMode == .doNotDisturb {
                return "Do Not Disturb"
            } else {
                let fallback = focusMode.displayName
                return fallback.isEmpty ? "Focus" : fallback
            }
        }

        return ""
    }

    private var accessibilityDescription: String {
        if manager.isDoNotDisturbActive {
            return "Focus active: \(labelText)"
        } else {
            return "Focus inactive"
        }
    }

    private var currentIcon: Image {
        if manager.isDoNotDisturbActive {
            return focusMode.resolvedActiveIcon(usePrivateSymbol: true)
        } else if showInactiveIcon {
            return inactiveIconMatchingActiveStyle
        } else {
            return focusMode.resolvedActiveIcon(usePrivateSymbol: true)
        }
    }

    private var inactiveIconMatchingActiveStyle: Image {
        if focusMode == .work {
            return focusMode.resolvedActiveIcon(usePrivateSymbol: true).renderingMode(.template)
        }

        if focusMode == .gaming,
           SymbolAvailabilityCache.shared.isSymbolAvailable("rocket.circle.fill") {
            return Image(systemName: "rocket.circle.fill")
        }

        if let internalName = focusMode.internalSymbolName {
            if let outlineName = outlineVariant(for: internalName),
               SymbolAvailabilityCache.shared.isSymbolAvailable(outlineName),
               let outlinedImage = Image(internalSystemName: outlineName) {
                return outlinedImage.renderingMode(.template)
            }

            if let filledImage = Image(internalSystemName: internalName) {
                return filledImage.renderingMode(.template)
            }
        }

        return Image(systemName: focusMode.inactiveSymbol)
    }

    private func outlineVariant(for internalName: String) -> String? {
        guard internalName.hasSuffix(".fill") else { return nil }
        let trimmed = String(internalName.dropLast(5))
        return trimmed.isEmpty ? nil : trimmed
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
                    currentIcon
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
                        .foregroundColor(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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

    private var labelColor: Color {
        if focusToastMode {
            return manager.isDoNotDisturbActive ? activeAccentColor : .white
        }
        return activeAccentColor
    }

    // MARK: - State transitions

    private func handleInitialState() {
        if manager.isDoNotDisturbActive {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
            if focusToastMode {
                scheduleTransientCollapse()
            }
        }
    }

    private func handleFocusStateChange(_ oldValue: Bool, _ isActive: Bool) {
        cancelPendingTasks()
        if isActive {
            withAnimation(.smooth(duration: 0.2)) {
                showInactiveIcon = false
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                iconScale = 1.0
                isExpanded = true
            }
            if focusToastMode {
                scheduleTransientCollapse()
            }
        } else {
            triggerInactiveAnimation()
        }
    }

    private func triggerInactiveAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            isExpanded = true
        }
        withAnimation(.smooth(duration: 0.2)) {
            showInactiveIcon = true
        }

        if focusToastMode {
            iconScale = 1.0
            scaleResetTask?.cancel()
        } else {
            withAnimation(.interpolatingSpring(stiffness: 220, damping: 12)) {
                iconScale = 1.2
            }

            scaleResetTask?.cancel()
            scaleResetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.interpolatingSpring(stiffness: 180, damping: 18)) {
                    iconScale = 1.0
                }
                withAnimation(.smooth(duration: 0.2)) {
                    showInactiveIcon = false
                }
            }
        }

        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(focusToastMode ? 900 : 320))
            withAnimation(.smooth(duration: 0.32)) {
                isExpanded = false
                if focusToastMode {
                    showInactiveIcon = false
                }
            }
        }

        cleanupTask?.cancel()
        guard !focusToastMode else { return }
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.smooth(duration: 0.2)) {
                showInactiveIcon = false
            }
        }
    }

    private func scheduleTransientCollapse() {
        collapseTask?.cancel()
        cleanupTask?.cancel()

        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1150))
            withAnimation(.smooth(duration: 0.32)) {
                isExpanded = false
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

private final class SymbolAvailabilityCache {
    static let shared = SymbolAvailabilityCache()
    private var cache: [String: Bool] = [:]
    private let lock = NSLock()

    func isSymbolAvailable(_ name: String) -> Bool {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        #if canImport(AppKit)
        let available = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        let available = false
        #endif

        lock.lock()
        cache[name] = available
        lock.unlock()
        return available
    }
}
