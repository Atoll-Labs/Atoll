import SwiftUI
import AppKit

struct LockScreenReminderWidgetSnapshot: Equatable {
    struct RGBAColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(nsColor: NSColor) {
            let color = nsColor.usingColorSpace(.sRGB) ?? nsColor
            self.red = Double(color.redComponent)
            self.green = Double(color.greenComponent)
            self.blue = Double(color.blueComponent)
            self.alpha = Double(color.alphaComponent)
        }

        var color: Color {
            Color(red: red, green: green, blue: blue, opacity: alpha)
        }
    }

    let title: String
    let eventTimeText: String
    let relativeDescription: String?
    let accent: RGBAColor
    let chipStyle: LockScreenReminderChipStyle
    let isCritical: Bool
    let iconName: String
}
