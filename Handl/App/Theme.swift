import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

/// Warm, flat, spacious. Light is cream + terracotta; dark keeps the same
/// warmth on deep browns. All text pairs meet WCAG AA on their backgrounds.
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    /// Terracotta for TEXT and ICONS — lightened in dark mode so it reads
    /// against the dark background.
    static let terracotta = dynamic(light: 0xB0431F, dark: 0xE0693D)
    /// Terracotta for FILLS under white text — must stay dark enough for
    /// 4.5:1 with white in BOTH modes (the dark text variant is only 3.4:1).
    static let terracottaFill = dynamic(light: 0xB0431F, dark: 0xB0431F)
    static let background = dynamic(light: 0xFAF4EC, dark: 0x201914)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2C231C)
    static let ink = dynamic(light: 0x2E2117, dark: 0xF5EDE4)
    static let inkSecondary = dynamic(light: 0x6B5B4D, dark: 0xBCAC9D)
    /// Fill colors under white text keep their light values in dark mode —
    /// the lighter dark variants failed 4.5:1 with white.
    static let callGreen = dynamic(light: 0x1E7A3C, dark: 0x1E7A3C)
    static let whatsappTeal = dynamic(light: 0x0F7B6C, dark: 0x0F7B6C)
    static let danger = dynamic(light: 0xB3261E, dark: 0xE46962)
}
