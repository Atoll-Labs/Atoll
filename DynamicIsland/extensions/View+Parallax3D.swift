//
//  View+Parallax3D.swift
//  DynamicIsland
//
//  Created for 3D Parallax Effect
//

import SwiftUI
import AppKit

import Defaults

struct ParallaxMotionModifier: ViewModifier {
    var magnitude: Double
    var enableOverride: Bool?
    var isSuspended: Bool
    
    @Default(.enableParallaxEffect) var enableParallaxEffect
    @State private var offset: CGSize = .zero
    @State private var isHovering = false
    @State private var viewSize: CGSize = .zero
    
    func body(content: Content) -> some View {
        if isSuspended || !(enableOverride ?? enableParallaxEffect) {
            content
        } else {
            content
                .contentShape(Rectangle())
                .overlay(
                    GeometryReader { proxy in
                        Color.clear
                            .allowsHitTesting(false)
                            .onAppear {
                                viewSize = proxy.size
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                viewSize = newSize
                            }
                    }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard viewSize.width > 0, viewSize.height > 0 else { return }
                        guard NSEvent.pressedMouseButtons == 0 else { return } // Skip hover math while clicking to avoid lag
                        let x = (location.x / viewSize.width) * 2 - 1
                        let y = (location.y / viewSize.height) * 2 - 1

                        withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.5)) {
                            offset = CGSize(width: x, height: y)
                            isHovering = true
                        }
                    case .ended:
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            offset = .zero
                            isHovering = false
                        }
                    }
                }
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
    func parallax3D(
        magnitude: Double = 10,
        enableOverride: Bool? = nil,
        suspended: Bool = false
    ) -> some View {
        modifier(ParallaxMotionModifier(magnitude: magnitude, enableOverride: enableOverride, isSuspended: suspended))
    }
}
