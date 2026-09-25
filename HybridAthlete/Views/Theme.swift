import SwiftUI
import UIKit

/// Chart + status colors, validated for colorblind separation and contrast on the card surfaces
/// (white in light mode, #1c1c1e in dark). Each has its own dark-mode step.
enum Theme {
    static let pace = Color(light: 0x2A78D6, dark: 0x3987E5)
    static let elevation = Color(light: 0x008300, dark: 0x008300)
    static let heart = Color(light: 0xE34948, dark: 0xE66767)

    /// HR zones 1–5: one blue, ordered light → dark.
    static let zones: [Color] = [
        Color(light: 0x86B6EF, dark: 0x9EC5F4),
        Color(light: 0x5598E7, dark: 0x6DA7EC),
        Color(light: 0x2A78D6, dark: 0x3987E5),
        Color(light: 0x1C5CAB, dark: 0x256ABF),
        Color(light: 0x104281, dark: 0x184F95),
    ]

    // Status — only where color means good/bad, always next to an icon or label.
    static let good = Color(hex: 0x0CA30C)
    static let warning = Color(hex: 0xFAB219)
    static let serious = Color(hex: 0xEC835A)
    static let critical = Color(hex: 0xD03B3B)

    static let grid = Color(light: 0xE1E0D9, dark: 0x2C2C2A)
    static let muted = Color(hex: 0x898781)

    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case ..<3: good
        case ..<5: warning
        case ..<7: serious
        default: critical
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Rounded card on the grouped background.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
