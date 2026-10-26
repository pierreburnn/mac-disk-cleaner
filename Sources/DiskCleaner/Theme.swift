// Theme.swift – Colors, fonts, and visual constants
import SwiftUI
import DiskCleanerCore

/// Visual theme constants matching the reference design.
public struct Theme {

    // MARK: - Background
    public static let background = Color(red: 0.969, green: 0.969, blue: 0.973) // #F7F7F8
    public static let cardBackground = Color.white
    public static let cardBorder = Color(red: 0.910, green: 0.910, blue: 0.918) // #E8E8EA
    public static let divider = Color(red: 0.933, green: 0.933, blue: 0.941) // #EEEEF0

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
    public static let segmentTrack = Color(red: 0.925, green: 0.925, blue: 0.933) // #ECECEE
    public static let segmentSelected = Color.white

    // MARK: - Treemap pastel fills
    public static func tileFill(for category: NodeCategory) -> Color {
        switch category {
        case .documents: return Color(red: 0.992, green: 0.937, blue: 0.902) // #FDEFE6
        case .devTools: return Color(red: 0.937, green: 0.941, blue: 0.949) // #EFF0F2
        case .codeProjects: return Color(red: 0.922, green: 0.922, blue: 1.000) // #EBEBFF
        case .sdks: return Color(red: 0.890, green: 0.953, blue: 0.973) // #E3F3F8
        case .aiModels: return Color(red: 0.992, green: 0.918, blue: 0.941) // #FDEAF0
        case .packageCaches: return Color(red: 0.906, green: 0.933, blue: 0.996) // #E7EEFE
        }
    }

    /// Slightly darker border for treemap tiles.
    public static func tileBorder(for category: NodeCategory) -> Color {
        switch category {
        case .documents: return Color(red: 0.937, green: 0.788, blue: 0.698) // #EFC9B2
        case .devTools: return Color(red: 0.855, green: 0.859, blue: 0.875) // #DADBDF
        case .codeProjects: return Color(red: 0.788, green: 0.784, blue: 0.957) // #C9C8F4
        case .sdks: return Color(red: 0.725, green: 0.863, blue: 0.902) // #B9DCE6
        case .aiModels: return Color(red: 0.953, green: 0.761, blue: 0.839) // #F3C2D6
        case .packageCaches: return Color(red: 0.725, green: 0.796, blue: 0.949) // #B9CBF2
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
        case .documents: return Color(red: 0.992, green: 0.890, blue: 0.839) // #FDE3D6
        case .devTools: return Color(red: 0.902, green: 0.906, blue: 0.918) // #E6E7EA
        case .codeProjects: return Color(red: 0.871, green: 0.875, blue: 0.996) // #DEDFFE
        case .sdks: return Color(red: 0.863, green: 0.937, blue: 0.961) // #DCEFF5
        case .aiModels: return Color(red: 0.984, green: 0.859, blue: 0.910) // #FBDBE8
        case .packageCaches: return Color(red: 0.851, green: 0.894, blue: 0.984) // #D9E4FB
        }
    }

    // MARK: - Cleanup mode
    public static let hatchGreen = Color(red: 0.420, green: 0.749, blue: 0.494).opacity(0.75)
    public static let hatchAmber = Color(red: 0.902, green: 0.620, blue: 0.239).opacity(0.65)
    public static let reviewFill = Color(red: 0.992, green: 0.937, blue: 0.851)   // #FDEFD9
    public static let reviewBorder = Color(red: 0.925, green: 0.698, blue: 0.392) // #ECB264
    public static let mutedFill = Color(red: 0.945, green: 0.945, blue: 0.949)    // #F1F1F2
    public static let mutedInnerFill = Color(red: 0.918, green: 0.918, blue: 0.925)
    public static let mutedBorder = Color(red: 0.882, green: 0.882, blue: 0.894)
    public static let windowWidth: CGFloat = 1200
    public static let windowHeight: CGFloat = 821

    // MARK: - Cleanable overlay
    public static let cleanableHatchColor = Color(red: 0.204, green: 0.659, blue: 0.325).opacity(0.35) // #34A853
    public static let selectionColor = Color(red: 0.0, green: 0.478, blue: 1.0)    // system blue
    public static let selectionBadgeBg = Color(red: 0.882, green: 0.929, blue: 1.0)  // #E1EDFF
    public static let destructive = Color(red: 0.851, green: 0.200, blue: 0.180)     // #D9332E
    public static let destructiveHover = Color(red: 0.776, green: 0.165, blue: 0.149)
    public static let cleanableBorder = Color(red: 0.400, green: 0.733, blue: 0.482) // #66BB7B
    public static let cleanupFill = Color(red: 0.890, green: 0.961, blue: 0.910) // #E3F5E8

    // MARK: - Fonts
    public static let monoBody = Font.system(.body, design: .monospaced)
    public static func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Card
    public static let cardRadius: CGFloat = 12
    public static let tileRadius: CGFloat = 6
    public static let padding: CGFloat = 10
    public static let gap: CGFloat = 16
}
