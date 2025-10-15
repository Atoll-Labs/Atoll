//
//  PrivacyLiveActivity.swift
//  DynamicIsland
//
//  Created for camera and microphone privacy indicators
//

import SwiftUI
import Defaults

struct PrivacyLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    @State private var isExpanded: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - Recording pulsator (if recording is active)
            Color.clear
                .background {
                    if recordingManager.isRecording && isExpanded {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.15))
                                
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .modifier(PulsingModifier())
                            }
                            .frame(width: vm.effectiveClosedNotchHeight - 12, height: vm.effectiveClosedNotchHeight - 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: recordingManager.isRecording && isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0, height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
            
            // Center - Black fill
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))
            
            // Right side - Privacy indicators (camera and/or microphone)
            Color.clear
                .background {
                    if isExpanded {
                        HStack(spacing: 8) {
                            // Microphone indicator (shows first if both active)
                            if privacyManager.indicatorLayout.showsMicrophoneIndicator {
                                PrivacyIcon(type: .microphone)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Camera indicator
                            if privacyManager.indicatorLayout.showsCameraIndicator {
                                PrivacyIcon(type: .camera)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0, height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            withAnimation(.smooth(duration: 0.4)) {
                isExpanded = true
            }
        }
        .onChange(of: privacyManager.hasAnyIndicator) { _, newValue in
            if !newValue {
                withAnimation(.smooth(duration: 0.4)) {
                    isExpanded = false
                }
            } else {
                withAnimation(.smooth(duration: 0.4)) {
                    isExpanded = true
                }
            }
        }
    }
}

// Individual privacy icon component
struct PrivacyIcon: View {
    let type: PrivacyIndicatorType
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.4),
                            Color.orange.opacity(0.2),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 20, height: 20)
                .opacity(isPulsing ? 0.8 : 0.5)
            
            // Icon background
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: 16, height: 16)
            
            // Icon
            Image(systemName: type.icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.orange)
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
