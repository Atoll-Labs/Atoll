//
//  ClipboardShared.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 12/08/25.
//

import SwiftUI

enum ClipboardTab: String, CaseIterable {
    case history = "History"
    case favorites = "Favorites"
    
    var icon: String {
        switch self {
        case .history: return "clock"
        case .favorites: return "heart.fill"
        }
    }
}

struct ClipboardTabButton: View {
    let tab: ClipboardTab
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    
    var itemCount: Int {
        switch tab {
        case .history:
            return clipboardManager.regularHistory.count
        case .favorites:
            return clipboardManager.pinnedItems.count
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .medium))
                
                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.3) : Color.gray.opacity(0.2))
                        )
                }
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
