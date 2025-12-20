//
//  View+Parallax3D.swift
//  DynamicIsland
//
//  Created for 3D Parallax Effect
//

import SwiftUI

import Defaults

struct ParallaxMotionModifier: ViewModifier {
    var magnitude: Double
    
    @Default(.enableParallaxEffect) var enableParallaxEffect
    @State private var offset: CGSize = .zero
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        if !enableParallaxEffect {
            content
        } else {
            content
                .overlay(
                    GeometryReader { proxy in
                        Color.clear
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let width = proxy.size.width
                                    let height = proxy.size.height
                                    
                                    // Normalize -1 to 1
                                    // (0,0) is top left, so we want center (width/2, height/2) to be (0,0)
                                    let x = (location.x / width) * 2 - 1
                                    let y = (location.y / height) * 2 - 1
                                    
                                    // Animate the transition to the new hover position
                                    withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.5)) {
                                        offset = CGSize(width: x, height: y)
                                        isHovering = true
                                    }
                                case .ended:
                                    // Return to center when hover ends
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                        offset = .zero
                                        isHovering = false
                                    }
                                }
                            }
                    }
                )
                .rotation3DEffect(
                    .degrees(offset.height * magnitude), // Y movement rotates around X axis
                    axis: (x: 1, y: 0, z: 0)
                )
                .rotation3DEffect(
                    .degrees(offset.width * -magnitude), // X movement rotates around Y axis (inverted to look naturally)
                    axis: (x: 0, y: 1, z: 0)
                )
                .scaleEffect(isHovering ? 1.02 : 1.0) // Subtle scale up on hover
        }
    }
}

extension View {
    func parallax3D(magnitude: Double = 10) -> some View {
        modifier(ParallaxMotionModifier(magnitude: magnitude))
    }
}
