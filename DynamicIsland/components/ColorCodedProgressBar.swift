//
//  ColorCodedProgressBar.swift
//  DynamicIsland
//
//  Created for color-coded battery and volume displays
//  Provides smooth gradient transitions from red to green (or reversed)
//

import SwiftUI
import Defaults

struct ColorCodedProgressBar: View {
    let value: CGFloat  // 0.0 to 1.0
    let reversed: Bool  // If true: green at low, red at high (for volume)
    let width: CGFloat
    let height: CGFloat
    let smoothGradient: Bool  // If true: smooth gradient, if false: discrete colors
    
    init(value: CGFloat, reversed: Bool = false, width: CGFloat = 100, height: CGFloat = 4, smoothGradient: Bool = true) {
        self.value = min(max(value, 0), 1)  // Clamp between 0 and 1
        self.reversed = reversed
        self.width = width
        self.height = height
        self.smoothGradient = smoothGradient
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: width, height: height)
                
                // Filled track with color gradient or solid color
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(smoothGradient ? 
                        AnyShapeStyle(LinearGradient(
                            gradient: gradientForValue,
                            startPoint: .leading,
                            endPoint: .trailing
                        )) :
                        AnyShapeStyle(colorForPercentage(value, reversed: reversed))
                    )
                    .frame(width: width * value, height: height)
            }
        }
        .frame(width: width, height: height)
    }
    
    /// Generates a gradient based on the current value
    private var gradientForValue: Gradient {
        let color = colorForPercentage(value, reversed: reversed)
        
        // Create a gradient that transitions smoothly
        let startColor = colorForPercentage(max(value - 0.1, 0), reversed: reversed)
        let endColor = color
        
        return Gradient(colors: [startColor, endColor])
    }
    
    /// Calculates discrete color for a given percentage (no smooth transitions)
    /// - Parameters:
    ///   - percentage: Value from 0.0 to 1.0
    ///   - reversed: If true, reverses the color scale (green at low, red at high)
    /// - Returns: Discrete color (red, yellow, or green only)
    private func discreteColorForPercentage(_ percentage: CGFloat, reversed: Bool) -> Color {
        let normalized = reversed ? (1.0 - percentage) : percentage
        
        switch normalized {
        case 0.0..<0.33:
            // Red zone (critical/low)
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        case 0.33..<0.67:
            // Yellow zone (medium)
            return Color(red: 1.0, green: 0.8, blue: 0.0)
        default:
            // Green zone (healthy/high)
            return Color(red: 0.2, green: 0.78, blue: 0.35)
        }
    }
    
    /// Calculates color for a given percentage with smooth transitions
    /// - Parameters:
    ///   - percentage: Value from 0.0 to 1.0
    ///   - reversed: If true, reverses the color scale (green at low, red at high)
    /// - Returns: Color with smooth gradient transitions
    private func colorForPercentage(_ percentage: CGFloat, reversed: Bool) -> Color {
        let normalized = reversed ? (1.0 - percentage) : percentage
        
        switch normalized {
        case 0.0..<0.2:
            // Pure Red zone (critical/low)
            return Color(red: 1.0, green: 0.23, blue: 0.19)
            
        case 0.2..<0.35:
            // Red → Orange transition
            let t = (normalized - 0.2) / 0.15
            let red: CGFloat = 1.0
            let green: CGFloat = 0.23 + (0.37 * t)  // 0.23 → 0.6
            let blue: CGFloat = 0.19
            return Color(red: red, green: green, blue: blue)
            
        case 0.35..<0.5:
            // Orange → Yellow transition
            let t = (normalized - 0.35) / 0.15
            let red: CGFloat = 1.0
            let green: CGFloat = 0.6 + (0.4 * t)  // 0.6 → 1.0
            let blue: CGFloat = 0.19
            return Color(red: red, green: green, blue: blue)
            
        case 0.5..<0.65:
            // Yellow → Yellow-Green transition
            let t = (normalized - 0.5) / 0.15
            let red: CGFloat = 1.0 - (0.4 * t)  // 1.0 → 0.6
            let green: CGFloat = 1.0
            let blue: CGFloat = 0.19 + (0.4 * t)  // 0.19 → 0.59
            return Color(red: red, green: green, blue: blue)
            
        case 0.65..<0.8:
            // Yellow-Green → Green transition
            let t = (normalized - 0.65) / 0.15
            let red: CGFloat = 0.6 - (0.4 * t)  // 0.6 → 0.2
            let green: CGFloat = 1.0 - (0.22 * t)  // 1.0 → 0.78
            let blue: CGFloat = 0.59 - (0.24 * t)  // 0.59 → 0.35
            return Color(red: red, green: green, blue: blue)
            
        default:
            // Pure Green zone (healthy/high)
            return Color(red: 0.2, green: 0.78, blue: 0.35)
        }
    }
}

// MARK: - Convenience Extensions

extension ColorCodedProgressBar {
    /// Creates a battery-style progress bar (green at high, red at low)
    static func battery(value: CGFloat, width: CGFloat = 100, height: CGFloat = 4, smoothGradient: Bool = true) -> some View {
        ColorCodedProgressBar(value: value, reversed: false, width: width, height: height, smoothGradient: smoothGradient)
    }
    
    /// Creates a volume-style progress bar (red at high, green at low)
    static func volume(value: CGFloat, width: CGFloat = 100, height: CGFloat = 4, smoothGradient: Bool = true) -> some View {
        ColorCodedProgressBar(value: value, reversed: true, width: width, height: height, smoothGradient: smoothGradient)
    }
}

// MARK: - Preview

#Preview("Battery Mode") {
    VStack(spacing: 20) {
        ForEach([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], id: \.self) { value in
            HStack {
                Text("\(Int(value * 100))%")
                    .frame(width: 50, alignment: .trailing)
                    .foregroundColor(.white)
                ColorCodedProgressBar.battery(value: value, width: 200)
            }
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("Volume Mode (Reversed)") {
    VStack(spacing: 20) {
        ForEach([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], id: \.self) { value in
            HStack {
                Text("\(Int(value * 100))%")
                    .frame(width: 50, alignment: .trailing)
                    .foregroundColor(.white)
                ColorCodedProgressBar.volume(value: value, width: 200)
            }
        }
    }
    .padding()
    .background(Color.black)
}
