//
//  FocusIndicator.swift
//  DynamicIsland
//
//  Small purple moon badge shown while Focus mode is active.
//

import SwiftUI

struct FocusIndicator: View {
    @ObservedObject var manager = DoNotDisturbManager.shared

    private let focusColor = Color.purple

    var body: some View {
        Capsule()
            .fill(Color.black)
            .overlay {
                ZStack {
                    Circle()
                        .fill(focusColor.opacity(0.2))
                        .frame(width: 20, height: 20)

                    Image(systemName: focusSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(focusColor)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focus mode active")
    }

    private var focusSymbol: String {
        if let symbol = FocusModeType(rawValue: manager.currentFocusModeIdentifier)?.sfSymbol {
            return symbol
        }
        return FocusModeType.doNotDisturb.sfSymbol
    }
}

#Preview {
    FocusIndicator()
        .frame(width: 30, height: 30)
        .background(Color.gray.opacity(0.2))
}
