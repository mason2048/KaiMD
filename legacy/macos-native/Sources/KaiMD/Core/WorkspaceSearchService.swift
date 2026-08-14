import Foundation

struct WorkspaceSearchResult: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fileName
        case content
    }

    let kind: Kind
    let fileURL: URL
    let relativePath: String
    let lineNumber: Int?
    let preview: String
    let matchLocation: Int
    let matchLength: Int

    var id: String {
        "\(fileURL.standardizedFilePath)|\(kind.rawValue)|\(lineNumber ?? 0)|\(matchLocation)"
    }
}

struct WorkspaceSearchService: Sendable {
    static let shared = WorkspaceSearchService()

    let maximumFileSize: Int
    let maximumResultCount: Int

    init(maximumFileSize: Int = 5 * 1_024 * 1_024, maximumResultCount: Int = 500) {
        self.maximumFileSize = maximumFileSize
        self.maximumResultCount = maximumResultCount
    }

    /// Performs all disk work away from the main actor. Task cancellation is
    /// checked between directories, files and lines so a superseded query exits
    /// without waiting for the entire workspace to be read.
    func search(query: String, in rootURL: URL) async throws -> [WorkspaceSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let maximumFileSize = maximumFileSize
        let maximumResultCount = maximumResultCount
        let worker = Task.detached(priority: .userInitiated) {
            try Self.performSearch(
                query: trimmedQuery,
                rootURL: rootURL,
                maximumFileSize: maximumFileSize,
                maximumResultCount: maximumResultCount
            )
        }
        return try await withTaskCancellationHandler(
            operation: { try await worker.value },
            onCancel: { worker.cancel() }
        )
    }

    private static func performSearch(
        query: String,
        rootURL: URL,
        maximumFileSize: Int,
        maximumResultCount: Int
    ) throws -> [WorkspaceSearchResult] {
        try Task.checkCancellation()
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw WorkspaceError.rootIsNotDirectory(root)
        }

        var fileNameMatches: [WorkspaceSearchResult] = []
        var contentMatches: [WorkspaceSearchResult] = []

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                continue
            }

            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true {
                if WorkspaceFileScanner.isExcludedDirectoryName(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true,
                  WorkspaceFileScanner.supportedKind(for: url) == .markdown
            else {
                continue
            }

            let relativePath = relativePath(of: url, beneath: root)
            if let range = url.lastPathComponent.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                let match = utf16Range(range, in: url.lastPathComponent)
                fileNameMatches.append(
                    WorkspaceSearchResult(
                        kind: .fileName,
                        fileURL: url,
                        relativePath: relativePath,
                        lineNumber: nil,
                        preview: url.lastPathComponent,
                        matchLocation: match.location,
                        matchLength: match.length
                    )
                )
                if fileNameMatches.count + contentMatches.count >= maximumResultCount {
                    break
                }
            }

            guard values.fileSize.map({ $0 <= maximumFileSize }) ?? false,
                  fileNameMatches.count + contentMatches.count < maximumResultCount
            else {
                continue
            }

            let data: Data
            do {
                data = try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
            } catch {
                continue
            }
            guard data.count <= maximumFileSize,
                  var body = String(data: data, encoding: .utf8)
            else {
                continue
            }
            if body.first == "\u{FEFF}" { body.removeFirst() }
            body = body
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")

            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, rawLine) in lines.enumerated() {
                try Task.checkCancellation()
                var line = String(rawLine)
                if line.hasSuffix("\r") { line.removeLast() }
                guard let range = line.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) else {
                    continue
                }

                let preview = preview(for: line, matching: range)
                contentMatches.append(
                    WorkspaceSearchResult(
                        kind: .content,
                        fileURL: url,
                        relativePath: relativePath,
                        lineNumber: offset + 1,
                        preview: preview.text,
                        matchLocation: preview.match.location,
                        matchLength: preview.match.length
                    )
                )
                if fileNameMatches.count + contentMatches.count >= maximumResultCount {
                    break
                }
            }
            if fileNameMatches.count + contentMatches.count >= maximumResultCount {
                break
            }
        }

        fileNameMatches.sort { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        contentMatches.sort { lhs, rhs in
            if lhs.relativePath != rhs.relativePath {
                return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
            return (lhs.lineNumber ?? 0) < (rhs.lineNumber ?? 0)
        }
        return fileNameMatches + contentMatches
    }

    private static func relativePath(of url: URL, beneath root: URL) -> String {
        let rootPath = root.standardizedFilePath
        let filePath = url.standardizedFilePath
        guard filePath.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func utf16Range(_ range: Range<String.Index>, in value: String) -> NSRange {
        NSRange(range, in: value)
    }

    private static func preview(
        for line: String,
        matching range: Range<String.Index>
    ) -> (text: String, match: NSRange) {
        var start = range.lowerBound
        for _ in 0..<80 where start > line.startIndex {
            start = line.index(before: start)
        }
        var end = range.upperBound
        for _ in 0..<160 where end < line.endIndex {
            end = line.index(after: end)
        }

        let hasLeadingEllipsis = start > line.startIndex
        let hasTrailingEllipsis = end < line.endIndex
        let leading = hasLeadingEllipsis ? "…" : ""
        let trailing = hasTrailingEllipsis ? "…" : ""
        let text = leading + line[start..<end] + trailing
        let leadingUTF16Count = leading.utf16.count + line[start..<range.lowerBound].utf16.count
        let matchUTF16Count = line[range].utf16.count
        return (text, NSRange(location: leadingUTF16Count, length: matchUTF16Count))
    }
}
