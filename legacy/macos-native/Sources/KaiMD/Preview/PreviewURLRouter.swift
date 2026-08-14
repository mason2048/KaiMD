import Foundation

/// Converts Markdown URLs into the small set of routes understood by the preview.
///
/// User-authored custom schemes are never preserved. Relative files are resolved first,
/// checked against the workspace boundary, and only then represented as an internal URL.
struct PreviewURLRouter: Sendable {
    static let assetScheme = "kaimd-asset"
    static let documentScheme = "kaimd-document"

    let documentURL: URL?
    let workspaceRoot: URL?

    init(documentURL: URL? = nil, workspaceRoot: URL? = nil) {
        self.documentURL = documentURL?.standardizedFileURL

        if let workspaceRoot {
            self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        } else if let documentURL {
            self.workspaceRoot = documentURL
                .deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
        } else {
            self.workspaceRoot = nil
        }
    }

    /// Returns a safe `href` for a Markdown link.
    func linkURLString(for destination: String?) -> String? {
        guard let destination = validatedInput(destination),
              let components = URLComponents(string: destination)
        else {
            return nil
        }

        if let scheme = components.scheme?.lowercased() {
            switch scheme {
            case "https":
                guard components.host?.isEmpty == false else { return nil }
                return components.url?.absoluteString
            case "mailto":
                guard !components.path.isEmpty else { return nil }
                return components.url?.absoluteString
            default:
                return nil
            }
        }

        // A fragment-only URL can remain inside the generated page.
        if components.path.isEmpty,
           components.query == nil,
           let fragment = components.percentEncodedFragment
        {
            return "#\(fragment)"
        }

        guard components.host == nil,
              let fileURL = resolvedRelativeFile(path: components.path),
              let root = workspaceRoot,
              let relativePath = Self.relativePath(of: fileURL, within: root)
        else {
            return nil
        }

        var route = URLComponents()
        route.scheme = Self.documentScheme
        route.host = "document"
        route.path = "/" + relativePath
        route.percentEncodedFragment = components.percentEncodedFragment
        return route.url?.absoluteString
    }

    /// Returns either a remote HTTPS URL or an internal workspace image route.
    func imageURLString(for source: String?) -> String? {
        guard let source = validatedInput(source),
              let components = URLComponents(string: source)
        else {
            return nil
        }

        if let scheme = components.scheme?.lowercased() {
            guard scheme == "https", components.host?.isEmpty == false else { return nil }
            return components.url?.absoluteString
        }

        guard components.host == nil,
              !components.path.isEmpty,
              let fileURL = resolvedRelativeFile(path: components.path),
              let root = workspaceRoot,
              let relativePath = Self.relativePath(of: fileURL, within: root)
        else {
            return nil
        }

        var route = URLComponents()
        route.scheme = Self.assetScheme
        route.host = "asset"
        route.path = "/" + relativePath
        return route.url?.absoluteString
    }

    /// Resolves a clicked internal document route back into a workspace file URL.
    func documentFileURL(for routedURL: URL) -> URL? {
        guard routedURL.scheme?.lowercased() == Self.documentScheme,
              routedURL.host == "document",
              let root = workspaceRoot,
              let fileURL = Self.workspaceFileURL(for: routedURL, host: "document", root: root)
        else {
            return nil
        }

        guard let fragment = routedURL.fragment else { return fileURL }
        var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? fileURL
    }

    /// Resolves an asset route while preserving the workspace containment invariant.
    static func assetFileURL(for routedURL: URL, workspaceRoot: URL) -> URL? {
        guard routedURL.scheme?.lowercased() == assetScheme,
              routedURL.host == "asset"
        else {
            return nil
        }

        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        return workspaceFileURL(for: routedURL, host: "asset", root: root)
    }

    static func isExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "https":
            return url.host?.isEmpty == false
        case "mailto":
            return !url.path.isEmpty
        default:
            return false
        }
    }

    private func validatedInput(_ input: String?) -> String? {
        guard let input, !input.isEmpty,
              input == input.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.unicodeScalars.contains(where: { scalar in
                  scalar.value < 0x20 || scalar.value == 0x7F
              })
        else {
            return nil
        }
        return input
    }

    private func resolvedRelativeFile(path: String) -> URL? {
        guard let root = workspaceRoot,
              !path.hasPrefix("/"),
              !path.hasPrefix("~")
        else {
            return nil
        }

        let baseURL: URL
        if path.isEmpty, let documentURL {
            baseURL = documentURL
        } else if let documentURL {
            baseURL = documentURL.deletingLastPathComponent().appendingPathComponent(path)
        } else {
            return nil
        }

        let resolved = baseURL.standardizedFileURL.resolvingSymlinksInPath()
        return resolved.isContained(in: root) ? resolved : nil
    }

    private static func workspaceFileURL(for routedURL: URL, host: String, root: URL) -> URL? {
        guard routedURL.host == host else { return nil }

        // `URL.path` is already percent-decoded. Decoding it a second time would both
        // reject valid percent signs in filenames and create double-decoding ambiguity.
        let decodedPath = routedURL.path
        guard !decodedPath.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return nil
        }

        let relativePath = String(decodedPath.drop(while: { $0 == "/" }))
        guard !relativePath.isEmpty else { return nil }

        let candidate = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return candidate.isContained(in: root) ? candidate : nil
    }

    private static func relativePath(of fileURL: URL, within root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents

        guard fileComponents.count > rootComponents.count,
              fileComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
        else {
            return nil
        }

        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
