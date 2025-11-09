//
//  FocusIndicator.swift
//  DynamicIsland
//
//  Small purple moon badge shown while Focus mode is active.
//

import SwiftUI

struct FocusIndicator: View {
    @ObservedObject var manager = DoNotDisturbManager.shared

    var body: some View {
        Capsule()
            .fill(Color.black)
            .overlay {
                Image(systemName: focusSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    private var focusMode: FocusModeType {
        FocusModeType.resolve(
            identifier: manager.currentFocusModeIdentifier,
            name: manager.currentFocusModeName
        )
    }

    private var focusSymbol: String {
        focusMode.sfSymbol
    }

    private var accentColor: Color {
        focusMode.accentColor
    }

    private var accessibilityLabel: String {
        let trimmedName = manager.currentFocusModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName: String
        if trimmedName.isEmpty {
            baseName = focusMode.displayName
        } else {
            baseName = trimmedName
        }

        let finalName = focusMode == .doNotDisturb ? "Focus" : baseName
        return "Focus active: \(finalName)"
    }
}

#Preview {
    FocusIndicator()
        .frame(width: 30, height: 30)
        .background(Color.gray.opacity(0.2))
}
