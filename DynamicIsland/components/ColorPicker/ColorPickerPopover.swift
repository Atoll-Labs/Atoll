//
//  ColorPickerPopover.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 14/08/25.
//

import SwiftUI
import Defaults

struct ColorPickerPopover: View {
    @ObservedObject var colorPickerManager = ColorPickerManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Color Picker")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Main actions
            VStack(spacing: 12) {
                // Pick Color Button
                Button(action: {
                    colorPickerManager.startColorPicking()
                    dismiss() // Close popover when starting to pick
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Pick Color")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Show Panel Button
                Button(action: {
                    ColorPickerPanelManager.shared.showColorPickerPanel()
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.grid.2x2")
                            .font(.system(size: 14, weight: .medium))
                        Text("Show Color History")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Recent colors preview (if any)
            if !colorPickerManager.colorHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Colors")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(Array(colorPickerManager.colorHistory.prefix(12))) { color in
                            Button(action: {
                                colorPickerManager.copyToClipboard(color.hexString)
                                
                                if Defaults[.enableHaptics] {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                }
                                
                                dismiss()
                            }) {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
    }
}

#Preview {
    ColorPickerPopover()
        .onAppear {
            ColorPickerManager.shared.colorHistory = PickedColor.sampleColors
        }
}
