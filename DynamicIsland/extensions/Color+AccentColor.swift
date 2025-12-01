#if os(macOS)
import SwiftUI
import Defaults

extension Color {
    /// Returns the accent color configured in settings, falling back to the system accent color.
    static var effectiveAccent: Color {
        Defaults[.accentColor]
    }
    
    /// Returns a subtle background variant of the accent color.
    static var effectiveAccentBackground: Color {
        Defaults[.accentColor].opacity(0.25)
    }
}
#endif
