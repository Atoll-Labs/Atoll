//
//  ClipboardPanelManager.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 12/08/25.
//

import AppKit
import SwiftUI

class ClipboardPanelManager: ObservableObject {
    static let shared = ClipboardPanelManager()
    
    private var clipboardPanel: ClipboardPanel?
    
    private init() {}
    
    func showClipboardPanel() {
        hideClipboardPanel() // Close any existing panel
        
        let panel = ClipboardPanel()
        panel.positionNearNotch()
        
        self.clipboardPanel = panel
        
        // Make the panel key and order front to ensure it can receive focus
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        
        // Activate the app to ensure proper focus handling
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure the panel becomes the key window for text input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            panel.makeKey()
        }
    }
    
    func hideClipboardPanel() {
        clipboardPanel?.close()
        clipboardPanel = nil
    }
    
    func toggleClipboardPanel() {
        if let panel = clipboardPanel, panel.isVisible {
            hideClipboardPanel()
        } else {
            showClipboardPanel()
        }
    }
    
    var isPanelVisible: Bool {
        return clipboardPanel?.isVisible ?? false
    }
}
