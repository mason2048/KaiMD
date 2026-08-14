import Foundation

enum EditorMode: String, CaseIterable, Codable, Sendable {
    case source
    case split
    case preview

    var label: String {
        switch self {
        case .source: "源码"
        case .split: "分栏"
        case .preview: "预览"
        }
    }
}

enum SidebarMode: String, CaseIterable, Codable, Sendable {
    case files
    case search

    var label: String {
        switch self {
        case .files: "文件"
        case .search: "搜索"
        }
    }
}

enum NewlineStyle: String, Codable, Sendable {
    case lineFeed
    case carriageReturnLineFeed
    case mixed

    var displayName: String {
        switch self {
        case .lineFeed: "LF"
        case .carriageReturnLineFeed: "CRLF"
        case .mixed: "Mixed"
        }
    }
}

extension URL {
    var standardizedFilePath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }

    func isContained(in root: URL) -> Bool {
        let rootPath = root.standardizedFilePath
        let candidatePath = standardizedFilePath
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
