//
//  TimerLiveActivity.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 2025-01-13.
//

import SwiftUI
import Defaults

struct TimerLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var timerManager = TimerManager.shared
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    
    var body: some View {
        HStack {
            // Left side - Timer icon animation
            timerIconSection
            
            // Center - Expandable timer info (similar to music banner)
            timerInfoSection
            
            // Right side - Timer countdown text
            timerCountdownSection
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }
    
    private var timerIconSection: some View {
        HStack {
            // Simple timer icon with color, no background circle or animations
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(timerManager.timerColor)
                .frame(width: 24, height: 24)
                .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
                       height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
        }
        .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
               height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)))
    }
    
    private var timerInfoSection: some View {
        Rectangle()
            .fill(.black)
            .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))
    }
    
    private var timerCountdownSection: some View {
        HStack {
            VStack(spacing: 2) {
                // Remaining time
                Text(timerManager.formattedRemainingTime())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(timerManager.isOvertime ? .red : .white)
                
                // Progress indicator
                if timerManager.totalDuration > 0 {
                    ProgressView(value: timerManager.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: timerManager.timerColor))
                        .frame(width: 30, height: 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
               height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
    }
}

#Preview {
    TimerLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 300, height: 32)
        .background(.black)
        .onAppear {
            // Start a demo timer for preview
            TimerManager.shared.startDemoTimer(duration: 300)
        }
}
