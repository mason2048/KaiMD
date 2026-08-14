import Combine
import Foundation

struct WorkspaceFileNode: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case directory
        case markdown
        case image
    }

    let url: URL
    let name: String
    let kind: Kind
    let children: [WorkspaceFileNode]

    var id: URL { url.standardizedFileURL }
    var isDirectory: Bool { kind == .directory }
    var isMarkdown: Bool { kind == .markdown }
    var isImage: Bool { kind == .image }
}

enum WorkspaceError: LocalizedError, Equatable {
    case rootIsNotDirectory(URL)
    case itemOutsideWorkspace(URL)
    case invalidName(String)
    case destinationExists(URL)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .rootIsNotDirectory(url):
            "工作区不存在或不是文件夹：\(url.path)"
        case let .itemOutsideWorkspace(url):
            "不允许操作工作区之外的项目：\(url.path)"
        case let .invalidName(name):
            "文件名无效：\(name)"
        case let .destinationExists(url):
            "目标已存在：\(url.lastPathComponent)"
        case let .operationFailed(reason):
            reason
        }
    }
}

@MainActor
final class WorkspaceSession: ObservableObject, Identifiable {
    let rootURL: URL

    @Published private(set) var nodes: [WorkspaceFileNode] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var isRefreshing = false

    private let searchService: WorkspaceSearchService
    private var scheduledRefreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(rootURL: URL, searchService: WorkspaceSearchService = .shared) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.searchService = searchService
        scheduleRefresh(after: .zero)
    }

    nonisolated var id: URL { rootURL }

    func refresh() {
        refreshGeneration += 1
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            nodes = try WorkspaceFileScanner.scan(rootURL: rootURL)
            lastError = nil
        } catch {
            nodes = []
            lastError = error
        }
    }

    func refreshAsync() async {
        let rootURL = rootURL
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let worker = Task.detached(priority: .userInitiated) {
                try WorkspaceFileScanner.scan(rootURL: rootURL)
            }
            let refreshedNodes = try await withTaskCancellationHandler(
                operation: { try await worker.value },
                onCancel: { worker.cancel() }
            )
            guard !Task.isCancelled else { return }
            nodes = refreshedNodes
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            nodes = []
            lastError = error
        }
    }

    /// Coalesces bursts of filesystem changes (for example, pasting several
    /// images) into a single background tree scan.
    func scheduleRefresh(after delay: Duration = .milliseconds(80)) {
        refreshGeneration += 1
        let generation = refreshGeneration
        scheduledRefreshTask?.cancel()
        isRefreshing = true
        scheduledRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, self.refreshGeneration == generation else { return }
            await self.refreshAsync()
            guard self.refreshGeneration == generation else { return }
            self.scheduledRefreshTask = nil
        }
    }

    /// Searches filenames and Markdown bodies. Cancelling the caller's task
    /// promptly stops filesystem traversal and returns no partial result.
    func search(query: String) async -> [WorkspaceSearchResult] {
        do {
            return try await searchService.search(query: query, in: rootURL)
        } catch is CancellationError {
            return []
        } catch {
            lastError = error
            return []
        }
    }

    @discardableResult
    func createMarkdownFile(named requestedName: String = "Untitled.md", in directory: URL? = nil) throws -> URL {
        let parent = try validatedDirectory(directory ?? rootURL)
        var name = try validatedName(requestedName)
        let fileExtension = (name as NSString).pathExtension.lowercased()
        if fileExtension.isEmpty {
            name += ".md"
        } else if !WorkspaceFileScanner.markdownExtensions.contains(fileExtension) {
            throw WorkspaceError.invalidName(requestedName)
        }

        let destination = uniqueURL(in: parent, desiredName: name)
        try Data().write(to: destination, options: .withoutOverwriting)
        scheduleRefresh(after: .zero)
        return destination
    }

    @discardableResult
    func createFolder(named requestedName: String = "New Folder", in directory: URL? = nil) throws -> URL {
        let parent = try validatedDirectory(directory ?? rootURL)
        let name = try validatedName(requestedName)
        let destination = uniqueURL(in: parent, desiredName: name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        scheduleRefresh(after: .zero)
        return destination
    }

    @discardableResult
    func rename(_ node: WorkspaceFileNode, to requestedName: String) throws -> URL {
        try renameItem(at: node.url, to: requestedName)
    }

    @discardableResult
    func renameItem(at sourceURL: URL, to requestedName: String) throws -> URL {
        let sourceURL = try validatedItemURL(sourceURL)
        let name = try validatedName(requestedName)
        let destination = sourceURL.deletingLastPathComponent().appendingPathComponent(name)
        guard destination.standardizedFilePath != sourceURL.standardizedFilePath else {
            return sourceURL
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw WorkspaceError.destinationExists(destination)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        scheduleRefresh(after: .zero)
        return destination
    }

    @discardableResult
    func duplicate(_ node: WorkspaceFileNode) throws -> URL {
        try duplicateItem(at: node.url)
    }

    @discardableResult
    func duplicateItem(at sourceURL: URL) throws -> URL {
        let sourceURL = try validatedItemURL(sourceURL)
        let parent = sourceURL.deletingLastPathComponent()
        let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let desiredName: String
        if isDirectory {
            desiredName = sourceURL.lastPathComponent + " copy"
        } else {
            let fileExtension = sourceURL.pathExtension
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            desiredName = stem + " copy" + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        }
        let destination = uniqueURL(in: parent, desiredName: desiredName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        scheduleRefresh(after: .zero)
        return destination
    }

    func moveToTrash(_ node: WorkspaceFileNode) throws {
        try moveItemToTrash(at: node.url)
    }

    func moveItemToTrash(at sourceURL: URL) throws {
        let sourceURL = try validatedItemURL(sourceURL)
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
        scheduleRefresh(after: .zero)
    }

    func relativePath(for url: URL) -> String? {
        let lexicalURL = url.standardizedFileURL
        guard Self.isLexicallyContained(lexicalURL, in: rootURL),
              lexicalURL.resolvingSymlinksInPath().isContained(in: rootURL)
        else {
            return nil
        }
        let rootPath = rootURL.standardizedFilePath
        let path = lexicalURL.path
        guard path != rootPath else { return "." }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func validatedDirectory(_ url: URL) throws -> URL {
        let lexicalURL = url.standardizedFileURL
        let resolvedURL = lexicalURL.resolvingSymlinksInPath()
        guard Self.isLexicallyContained(lexicalURL, in: rootURL),
              resolvedURL.isContained(in: rootURL)
        else {
            throw WorkspaceError.itemOutsideWorkspace(url)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError.rootIsNotDirectory(url)
        }
        return resolvedURL
    }

    private func validatedItemURL(_ url: URL) throws -> URL {
        let lexicalURL = url.standardizedFileURL
        let resolvedURL = lexicalURL.resolvingSymlinksInPath()
        guard lexicalURL.path != rootURL.path,
              resolvedURL != rootURL,
              Self.isLexicallyContained(lexicalURL, in: rootURL),
              resolvedURL.isContained(in: rootURL)
        else {
            throw WorkspaceError.itemOutsideWorkspace(url)
        }
        guard FileManager.default.fileExists(atPath: lexicalURL.path) else {
            throw WorkspaceError.operationFailed("项目不存在：\(url.path)")
        }
        return lexicalURL
    }

    private static func isLexicallyContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        if rootPath == "/" { return candidatePath.hasPrefix("/") }
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = trimmed.isEmpty
            || trimmed == "."
            || trimmed == ".."
            || trimmed.contains("/")
            || trimmed.contains(":")
            || trimmed.contains("\0")
        guard !invalid else { throw WorkspaceError.invalidName(name) }
        return trimmed
    }

    private func uniqueURL(in directory: URL, desiredName: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(desiredName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let pathExtension = (desiredName as NSString).pathExtension
        let stem = pathExtension.isEmpty
            ? desiredName
            : (desiredName as NSString).deletingPathExtension
        var suffix = 2
        repeat {
            let name = "\(stem) \(suffix)" + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }
}

enum WorkspaceFileScanner {
    static let excludedDirectoryNames: Set<String> = [
        ".git", ".build", "node_modules", "vendor", "DerivedData",
    ]

    static let markdownExtensions: Set<String> = ["md", "markdown"]
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg",
    ]

    static func scan(rootURL: URL) throws -> [WorkspaceFileNode] {
        try Task.checkCancellation()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceError.rootIsNotDirectory(rootURL)
        }
        return try scanDirectory(rootURL)
    }

    static func isExcludedDirectoryName(_ name: String) -> Bool {
        name.hasPrefix(".") || excludedDirectoryNames.contains(name)
    }

    static func supportedKind(for url: URL) -> WorkspaceFileNode.Kind? {
        let fileExtension = url.pathExtension.lowercased()
        if markdownExtensions.contains(fileExtension) { return .markdown }
        if imageExtensions.contains(fileExtension) { return .image }
        return nil
    }

    private static func scanDirectory(_ directory: URL) throws -> [WorkspaceFileNode] {
        try Task.checkCancellation()
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var result: [WorkspaceFileNode] = []
        for url in contents {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isSymbolicLink == true { continue }

            if values.isDirectory == true {
                guard !isExcludedDirectoryName(url.lastPathComponent) else { continue }
                let children: [WorkspaceFileNode]
                do {
                    children = try scanDirectory(url)
                } catch {
                    try Task.checkCancellation()
                    children = []
                }
                // The sidebar is a Markdown navigator, so directories that do
                // not contain any Markdown descendants stay out of the tree.
                if !children.isEmpty {
                    result.append(
                        WorkspaceFileNode(
                            url: url,
                            name: url.lastPathComponent,
                            kind: .directory,
                            children: children
                        )
                    )
                }
            } else if values.isRegularFile == true,
                      supportedKind(for: url) == .markdown
            {
                result.append(
                    WorkspaceFileNode(
                        url: url,
                        name: url.lastPathComponent,
                        kind: .markdown,
                        children: []
                    )
                )
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
