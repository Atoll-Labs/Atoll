//
//  Constants.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.c, modifiers: [.shift, .command]))
    static let colorPickerPanel = Self("colorPickerPanel", default: .init(.p, modifiers: [.shift, .command]))
    static let screenAssistantPanel = Self("screenAssistantPanel", default: .init(.a, modifiers: [.shift, .command]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let startDemoTimer = Self("startDemoTimer", default: .init(.t, modifiers: [.command, .shift]))
}
