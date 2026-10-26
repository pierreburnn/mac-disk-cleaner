// Theme.swift – Colors, fonts, and visual constants
import SwiftUI
import DiskCleanerCore

/// Visual theme constants matching the reference design.
public struct Theme {

    // MARK: - Background
    public static let background = Color(red: 0.957, green: 0.957, blue: 0.961) // #F4F4F5
    public static let cardBackground = Color.white
    public static let cardBorder = Color(red: 0.902, green: 0.902, blue: 0.910) // #E6E6E8
    public static let divider = Color(red: 0.902, green: 0.902, blue: 0.910) // #E6E6E8

    // MARK: - Text colors
    public static let textPrimary = Color(red: 0.1, green: 0.1, blue: 0.1)
    public static let textSecondary = Color(red: 0.420, green: 0.420, blue: 0.439) // #6B6B70
    public static let textTertiary = Color(red: 0.55, green: 0.55, blue: 0.58)

    // MARK: - Status colors
    public static let safeGreen = Color(red: 0.133, green: 0.647, blue: 0.357) // #22A55B
    public static let reviewOrange = Color(red: 0.910, green: 0.537, blue: 0.169) // #E8892B

    // MARK: - Badge colors
    public static let safeBadgeBg = Color(red: 0.867, green: 0.953, blue: 0.894) // #DDF3E4
    public static let safeBadgeText = Color(red: 0.118, green: 0.557, blue: 0.306) // #1E8E4E
    public static let reviewBadgeBg = Color(red: 0.988, green: 0.922, blue: 0.843) // #FCEBD7
    public static let reviewBadgeText = Color(red: 0.761, green: 0.416, blue: 0.071) // #C26A12

    // MARK: - Segment control
    public static let segmentTrack = Color(red: 0.941, green: 0.941, blue: 0.949) // #F0F0F2
    public static let segmentSelected = Color.white

    // MARK: - Treemap pastel fills
    public static func tileFill(for category: NodeCategory) -> Color {
        switch category {
        case .documents:     return Color(red: 0.988, green: 0.902, blue: 0.839) // #FCE6D6
        case .devTools:      return Color(red: 0.925, green: 0.925, blue: 0.933) // #ECECEE
        case .codeProjects:  return Color(red: 0.902, green: 0.894, blue: 0.984) // #E6E4FB
        case .sdks:          return Color(red: 0.867, green: 0.941, blue: 0.957) // #DDF0F4
        case .aiModels:      return Color(red: 0.984, green: 0.882, blue: 0.918) // #FBE1EA
        case .packageCaches: return Color(red: 0.863, green: 0.902, blue: 0.969) // #DCE6F7
        }
    }

    /// Slightly darker border for treemap tiles.
    public static func tileBorder(for category: NodeCategory) -> Color {
        switch category {
        case .documents:     return Color(red: 0.949, green: 0.765, blue: 0.627) // #F2C3A0
        case .devTools:      return Color(red: 0.827, green: 0.827, blue: 0.847) // #D3D3D8
        case .codeProjects:  return Color(red: 0.749, green: 0.729, blue: 0.941) // #BFBAF0
        case .sdks:          return Color(red: 0.663, green: 0.839, blue: 0.878) // #A9D6E0
        case .aiModels:      return Color(red: 0.941, green: 0.702, blue: 0.780) // #F0B3C7
        case .packageCaches: return Color(red: 0.686, green: 0.769, blue: 0.918) // #AFC4EA
        }
    }

    /// Saturated legend dot colors.
    public static func legendColor(for category: NodeCategory) -> Color {
        switch category {
        case .documents:     return Color(red: 0.933, green: 0.478, blue: 0.231) // #EE7A3B
        case .devTools:      return Color(red: 0.604, green: 0.604, blue: 0.627) // #9A9AA0
        case .codeProjects:  return Color(red: 0.431, green: 0.384, blue: 0.878) // #6E62E0
        case .sdks:          return Color(red: 0.231, green: 0.702, blue: 0.788) // #3BB3C9
        case .aiModels:      return Color(red: 0.878, green: 0.314, blue: 0.541) // #E0508A
        case .packageCaches: return Color(red: 0.310, green: 0.484, blue: 0.878) // #4F7BE0
        }
    }

    // MARK: - Treemap inner tile fills (lighter)
    public static func innerTileFill(for category: NodeCategory) -> Color {
        switch category {
        case .documents:     return Color(red: 0.996, green: 0.961, blue: 0.933)
        case .devTools:      return Color(red: 0.965, green: 0.965, blue: 0.969)
        case .codeProjects:  return Color(red: 0.953, green: 0.949, blue: 0.996)
        case .sdks:          return Color(red: 0.937, green: 0.973, blue: 0.984)
        case .aiModels:      return Color(red: 0.996, green: 0.945, blue: 0.961)
        case .packageCaches: return Color(red: 0.937, green: 0.953, blue: 0.988)
        }
    }

    // MARK: - Cleanable overlay
    public static let cleanableHatchColor = Color(red: 0.204, green: 0.659, blue: 0.325).opacity(0.35) // #34A853
    public static let cleanableBorder = Color(red: 0.365, green: 0.733, blue: 0.478) // #5DBB7A
    public static let cleanupFill = Color(red: 0.890, green: 0.961, blue: 0.910) // #E3F5E8

    // MARK: - Fonts
    public static let monoBody = Font.system(.body, design: .monospaced)
    public static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Card
    public static let cardRadius: CGFloat = 12
    public static let tileRadius: CGFloat = 6
    public static let padding: CGFloat = 16
    public static let gap: CGFloat = 12
}
