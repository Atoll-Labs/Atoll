//
//  TimerIconAnimation.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 2025-01-13.
//

import SwiftUI
import Combine

struct TimerIconAnimation: View {
    @ObservedObject var timerManager = TimerManager.shared
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // Background circle with timer color
            Circle()
                .fill(timerManager.timerColor.gradient)
                .frame(width: 24, height: 24)
                .scaleEffect(pulseScale)
                .animation(
                    timerManager.isTimerActive && !timerManager.isPaused
                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.3),
                    value: pulseScale
                )
            
            // Timer icon
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(rotationAngle))
                .animation(
                    timerManager.isTimerActive && !timerManager.isPaused
                        ? .linear(duration: 2.0).repeatForever(autoreverses: false)
                        : .easeInOut(duration: 0.3),
                    value: rotationAngle
                )
            
            // Progress ring
            Circle()
                .trim(from: 0, to: timerManager.progress)
                .stroke(
                    Color.white.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(-90)) // Start from top
                .animation(.easeInOut(duration: 0.5), value: timerManager.progress)
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: timerManager.isTimerActive) { _, isActive in
            if isActive {
                startAnimations()
            } else {
                stopAnimations()
            }
        }
        .onChange(of: timerManager.isPaused) { _, isPaused in
            if isPaused {
                stopAnimations()
            } else if timerManager.isTimerActive {
                startAnimations()
            }
        }
    }
    
    private func startAnimations() {
        guard timerManager.isTimerActive && !timerManager.isPaused else { return }
        
        // Start pulsing
        pulseScale = 1.1
        
        // Start rotation
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    private func stopAnimations() {
        // Stop pulsing
        pulseScale = 1.0
        
        // Stop rotation
        withAnimation(.easeInOut(duration: 0.3)) {
            rotationAngle = 0
        }
    }
}

struct TimerIconView: NSViewRepresentable {
    @ObservedObject var timerManager = TimerManager.shared
    
    func makeNSView(context: Context) -> NSView {
        let hostingView = NSHostingView(rootView: TimerIconAnimation())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        return hostingView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let hostingView = nsView as? NSHostingView<TimerIconAnimation> {
            hostingView.rootView = TimerIconAnimation()
        }
    }
}

#Preview {
    TimerIconAnimation()
        .frame(width: 50, height: 50)
        .background(.black)
        .onAppear {
            // Start a demo timer for preview
            TimerManager.shared.startDemoTimer(duration: 300)
        }
}
