import SwiftUI

// MARK: - UIColor hex extension
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

// MARK: - Dynamic Colors (auto light/dark)
extension Color {
    static let vtBG = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "0f1117") : UIColor(hex: "f4f6f9") })
    static let vtPanel = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "161a22") : UIColor(hex: "ffffff") })
    static let vtPanel2 = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "1c212b") : UIColor(hex: "edf1f6") })
    static let vtBorder = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "262c38") : UIColor(hex: "dfe4ec") })
    static let vtText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "e6e9ef") : UIColor(hex: "1f2430") })
    static let vtTextDim = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "8a91a0") : UIColor(hex: "6b7280") })
    static let vtBubbleOther = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: "262c38") : UIColor(hex: "e8edf4") })
}

// MARK: - App Theme Colors
struct AppTheme {
    // Dark theme (default)
    static let darkBG = Color.vtBG
    static let darkPanel = Color.vtPanel
    static let darkPanel2 = Color.vtPanel2
    static let darkBorder = Color.vtBorder
    static let darkText = Color.vtText
    static let darkTextDim = Color.vtTextDim

    // Light theme
    static let lightBG = Color(hex: "f4f6f9")
    static let lightPanel = Color(hex: "ffffff")
    static let lightPanel2 = Color(hex: "edf1f6")
    static let lightBorder = Color(hex: "dfe4ec")
    static let lightText = Color(hex: "1f2430")
    static let lightTextDim = Color(hex: "6b7280")

    // Shared
    static let accent = Color(hex: "07c160")
    static let accentDim = Color(hex: "059749")
    static let danger = Color(hex: "e5484d")
    static let bubbleOther = Color.vtBorder
    static let bubbleOtherLight = Color(hex: "e8edf4")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Theme Environment
struct ThemeColors {
    let bg: Color
    let panel: Color
    let panel2: Color
    let border: Color
    let text: Color
    let textDim: Color
    let bubbleOther: Color

    static let dark = ThemeColors(
        bg: AppTheme.darkBG, panel: AppTheme.darkPanel, panel2: AppTheme.darkPanel2,
        border: AppTheme.darkBorder, text: AppTheme.darkText, textDim: AppTheme.darkTextDim,
        bubbleOther: AppTheme.bubbleOther
    )
    static let light = ThemeColors(
        bg: AppTheme.lightBG, panel: AppTheme.lightPanel, panel2: AppTheme.lightPanel2,
        border: AppTheme.lightBorder, text: AppTheme.lightText, textDim: AppTheme.lightTextDim,
        bubbleOther: AppTheme.bubbleOtherLight
    )
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeColors.dark
}

extension EnvironmentValues {
    var theme: ThemeColors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
