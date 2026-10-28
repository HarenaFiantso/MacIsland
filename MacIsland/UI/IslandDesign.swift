import SwiftUI

/// Design tokens shared by every island view. Pure black background, white text at
/// graded opacities, hairline separators, continuous corners.
enum IslandDesign {
    static let background = Color.black
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.15)
    static let surfacePressed = Color.white.opacity(0.22)
    static let separator = Color.white.opacity(0.10)
    static let positive = Color(red: 0.30, green: 0.85, blue: 0.39)
    static let warning = Color(red: 1.00, green: 0.62, blue: 0.20)
    static let negative = Color(red: 1.00, green: 0.33, blue: 0.30)

    static let bodyPadding: CGFloat = 14
    static let tileRadius: CGFloat = 12
    static let cardRadius: CGFloat = 16

    static func label(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}
