//
//  IdleAnimationView.swift
//  DynamicIsland
//
//  Created by AI Assistant on 11/10/2025.
//  Unified view for displaying idle animations (Lottie or built-in face)
//

import SwiftUI
import Lottie
import LottieUI
import Defaults

struct IdleAnimationView: View {
    @Default(.selectedIdleAnimation) var selectedAnimation
    @Default(.animationTransformOverrides) var overrides
    
    var body: some View {
        Group {
            if let animation = selectedAnimation {
                AnimationContentView(animation: animation)
                    .id("\(animation.id)-\(overrides[animation.id.uuidString]?.hashValue ?? 0)")  // Force recreation when override changes
            } else {
                // Fallback to original face if nothing selected
                MinimalFaceFeatures(height: 20, width: 30)
            }
        }
    }
}

/// Internal view that renders the actual animation content
private struct AnimationContentView: View {
    let animation: CustomIdleAnimation
    
    var body: some View {
        let config = animation.getTransformConfig()
        
        // Debug logging
        let _ = print("🎨 [IdleAnimationView] Rendering animation: \(animation.name)")
        let _ = print("🎨 [IdleAnimationView] Config: scale=\(config.scale), offset=(\(config.offsetX), \(config.offsetY)), opacity=\(config.opacity)")
        
        switch animation.source {
        case .lottieFile(let url):
            LottieView(state: LUStateData(
                type: .loadedFrom(url),
                speed: animation.speed,
                loopMode: config.loopMode.lottieLoopMode
            ))
            .id(animation.id)  // Force reload when animation changes
            .frame(
                width: config.cropWidth * config.scale,
                height: config.cropHeight * config.scale
            )
            .offset(x: config.offsetX, y: config.offsetY)
            .rotationEffect(.degrees(config.rotation))
            .opacity(config.opacity)
            .padding(.bottom, config.paddingBottom)
            .frame(width: config.expandWithAnimation ? nil : 30, height: 20)
            .clipped()
            
        case .lottieURL(let url):
            LottieView(state: LUStateData(
                type: .loadedFrom(url),
                speed: animation.speed,
                loopMode: config.loopMode.lottieLoopMode
            ))
            .id(animation.id)  // Force reload when animation changes
            .frame(
                width: config.cropWidth * config.scale,
                height: config.cropHeight * config.scale
            )
            .offset(x: config.offsetX, y: config.offsetY)
            .rotationEffect(.degrees(config.rotation))
            .opacity(config.opacity)
            .padding(.bottom, config.paddingBottom)
            .frame(width: config.expandWithAnimation ? nil : 30, height: 20)
            .clipped()
            
        case .builtInFace:
            // Apply transforms to built-in face too!
            MinimalFaceFeatures(height: 20, width: 30)
                .frame(
                    width: config.cropWidth * config.scale,
                    height: config.cropHeight * config.scale
                )
                .offset(x: config.offsetX, y: config.offsetY)
                .rotationEffect(.degrees(config.rotation))
                .opacity(config.opacity)
                .padding(.bottom, config.paddingBottom)
                .frame(width: config.expandWithAnimation ? nil : 30, height: 20)
                .clipped()
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black
        IdleAnimationView()
    }
    .frame(width: 100, height: 50)
}
