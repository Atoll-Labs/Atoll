//
//  LockScreenLiveActivity.swift
//  DynamicIsland
//
//  Created for lock screen live activity
//

import SwiftUI
import Defaults
import SkyLightWindow

struct LockScreenLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    // Don't observe lockScreenManager - just show static lock icon without state-driven animations
    // This prevents animation conflicts with panel window teardown
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    @State private var isExpanded: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left - Lock icon with subtle glow
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.15))
                                
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                    .modifier(LockPulsingModifier())
                            }
                            .frame(width: vm.effectiveClosedNotchHeight - 12, height: vm.effectiveClosedNotchHeight - 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0, height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
            
            // Center - Black fill
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))
            
            // Right - Empty for symmetry with animation
            Color.clear
                .frame(width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0, height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            // Expand immediately without animation to avoid conflicts
            isExpanded = true
        }
        .onDisappear {
            // Collapse immediately when removed from hierarchy
            isExpanded = false
        }
    }
}

// Pulsing animation modifier for lock indicator
struct LockPulsingModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
