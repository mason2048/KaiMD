import Foundation

struct RestoredWorkspace: Codable, Equatable, Sendable {
    let rootPath: String
    let openRelativePaths: [String]
    let selectedRelativePath: String?
}

struct WorkspaceRestorationSnapshot: Codable, Equatable, Sendable {
    let workspaces: [RestoredWorkspace]
}

final class WorkspaceRestorationStore: @unchecked Sendable {
    static let shared = WorkspaceRestorationStore()

    private let defaults: UserDefaults
    private let key = "KaiMD.workspaceRestoration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WorkspaceRestorationSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorkspaceRestorationSnapshot.self, from: data)
    }

    func save(_ snapshot: WorkspaceRestorationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
