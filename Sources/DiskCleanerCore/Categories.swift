// Categories.swift – Category enum and classifier
import Foundation

/// Category for a file-system node, used for treemap coloring.
public enum NodeCategory: String, CaseIterable, Sendable {
    case documents      // "Documents & media"
    case devTools       // "Dev tools & other"
    case codeProjects   // "Code projects"
    case sdks           // "iOS & Android SDKs"
    case aiModels       // "AI models"
    case packageCaches  // "Package caches"

    public var displayName: String {
        switch self {
        case .documents:     return "Documents & media"
        case .devTools:      return "Dev tools & other"
        case .codeProjects:  return "Code projects"
        case .sdks:          return "iOS & Android SDKs"
        case .aiModels:      return "AI models"
        case .packageCaches: return "Package caches"
        }
    }
}

/// Classifies a path relative to home into a category.
public struct CategoryClassifier: Sendable {

    public init() {}

    /// Classify a relative-to-home path.
    /// - Parameter relativePath: path relative to the user's home (no leading /).
    /// - Parameter isDirectory: whether the path is a directory.
    /// - Parameter parentCategory: the parent node's category (inherited unless overridden).
    /// - Returns: the determined category.
    public func classify(
        relativePath: String,
        isDirectory: Bool,
        parentCategory: NodeCategory?
    ) -> NodeCategory {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let first = components.first else {
            return parentCategory ?? .devTools
        }

        // Check from the deepest specific match upward.
        let full = relativePath

        // AI models
        if first == ".ollama" || first == ".lmstudio" {
            return .aiModels
        }
        if full.hasPrefix(".cache/huggingface") || full.hasPrefix(".cache/lm-studio") {
            return .aiModels
        }
        let lowerName = components.last?.lowercased() ?? ""
        if lowerName.hasSuffix(".gguf") || lowerName.hasSuffix(".safetensors") {
            return .aiModels
        }

        // Package caches
        if first == ".npm" || first == ".gradle" || first == ".yarn"
            || first == ".pnpm-store" || first == ".cocoapods"
            || first == ".m2" {
            return .packageCaches
        }
        if full.hasPrefix(".cargo/registry") {
            return .packageCaches
        }
        if full.hasPrefix(".cache") && !full.hasPrefix(".cache/huggingface") && !full.hasPrefix(".cache/lm-studio") {
            return .packageCaches
        }
        if full.hasPrefix("Library/Caches") {
            return .packageCaches
        }
        if full.hasPrefix("Library/pnpm") {
            return .packageCaches
        }
        if lowerName == "node_modules" || lowerName == ".next" || lowerName == ".turbo" {
            return .packageCaches
        }

        // SDKs
        if full.hasPrefix("Library/Android") || first == ".android" {
            return .sdks
        }
        if full.hasPrefix("Library/Developer") {
            return .sdks
        }
        if lowerName == ".xcode" {
            return .sdks
        }

        // Documents & media
        let docDirs: Set<String> = [
            "Documents", "Pictures", "Movies", "Music", "Downloads",
            "Photos Library.photoslibrary"
        ]
        if docDirs.contains(first) {
            return .documents
        }
        if full.hasPrefix("Library/Mobile Documents") {
            return .documents
        }
        if lowerName == "photos library.photoslibrary" || lowerName.hasSuffix(".photoslibrary") {
            return .documents
        }

        // Code projects
        let codeDirs: Set<String> = [
            "Desktop", "Developer", "Projects", "Code", "src", "dev",
            "repos", "workspace", "GitHub"
        ]
        if codeDirs.contains(first) {
            return .codeProjects
        }

        // Inherited from parent, or default to devTools
        return parentCategory ?? .devTools
    }

    /// Check if a directory looks like a code project root.
    public func isProjectDirectory(children: [String]) -> Bool {
        let markers: Set<String> = [
            ".git", "package.json", "Package.swift", "Cargo.toml",
            "pyproject.toml", "Makefile", "CMakeLists.txt", "go.mod"
        ]
        return !markers.isDisjoint(with: children)
    }
}
