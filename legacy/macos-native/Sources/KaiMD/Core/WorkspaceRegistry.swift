import Combine
import Foundation

/// Owns the one-session-per-root invariant and persists a small recent list.
/// Security-scoped bookmarks are stored when macOS can create them; an absolute
/// file URL is retained as the non-sandboxed fallback used by the v1 app.
@MainActor
final class WorkspaceRegistry: ObservableObject {
    static let shared = WorkspaceRegistry()

    @Published private(set) var recentWorkspaceURLs: [URL]

    private var sessionsByPath: [String: WorkspaceSession] = [:]
    private let defaults: UserDefaults
    private let recentKey = "KaiMD.recentWorkspaces.v1"
    private let maximumRecentCount = 5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentWorkspaceURLs = Self.loadRecentWorkspaces(from: defaults, key: recentKey)
    }

    func session(for rootURL: URL) -> WorkspaceSession {
        let normalized = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let key = normalized.standardizedFilePath
        if let existing = sessionsByPath[key] {
            recordRecent(normalized)
            return existing
        }

        let session = WorkspaceSession(rootURL: normalized)
        sessionsByPath[key] = session
        recordRecent(normalized)
        return session
    }

    func existingSession(for rootURL: URL) -> WorkspaceSession? {
        sessionsByPath[rootURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFilePath]
    }

    func session(containing fileURL: URL) -> WorkspaceSession? {
        sessionsByPath.values
            .filter { fileURL.isContained(in: $0.rootURL) }
            .max { lhs, rhs in lhs.rootURL.path.count < rhs.rootURL.path.count }
    }

    func recordRecent(_ rootURL: URL) {
        let normalized = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        recentWorkspaceURLs.removeAll { $0.standardizedFilePath == normalized.standardizedFilePath }
        recentWorkspaceURLs.insert(normalized, at: 0)
        if recentWorkspaceURLs.count > maximumRecentCount {
            recentWorkspaceURLs.removeLast(recentWorkspaceURLs.count - maximumRecentCount)
        }
        persistRecentWorkspaces()
    }

    func removeRecent(_ rootURL: URL) {
        recentWorkspaceURLs.removeAll { $0.standardizedFilePath == rootURL.standardizedFilePath }
        persistRecentWorkspaces()
    }

    func clearRecentWorkspaces() {
        recentWorkspaceURLs = []
        persistRecentWorkspaces()
    }

    func discardSession(for rootURL: URL) {
        sessionsByPath.removeValue(forKey: rootURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFilePath)
    }

    private func persistRecentWorkspaces() {
        let entries: [[String: Any]] = recentWorkspaceURLs.map { url in
            var entry: [String: Any] = ["url": url.absoluteString]
            if let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                entry["bookmark"] = bookmark
            }
            return entry
        }
        defaults.set(entries, forKey: recentKey)
    }

    private static func loadRecentWorkspaces(from defaults: UserDefaults, key: String) -> [URL] {
        guard let entries = defaults.array(forKey: key) as? [[String: Any]] else { return [] }

        var seen: Set<String> = []
        var result: [URL] = []
        for entry in entries {
            var resolvedURL: URL?
            if let bookmark = entry["bookmark"] as? Data {
                var isStale = false
                resolvedURL = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            }
            if resolvedURL == nil,
               let string = entry["url"] as? String
            {
                resolvedURL = URL(string: string)
            }
            guard let url = resolvedURL?.standardizedFileURL.resolvingSymlinksInPath() else { continue }
            let path = url.standardizedFilePath
            guard seen.insert(path).inserted else { continue }
            result.append(url)
        }
        return Array(result.prefix(5))
    }
}
