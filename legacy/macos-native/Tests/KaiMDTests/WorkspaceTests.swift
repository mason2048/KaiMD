import AppKit
import Foundation
import Testing
@testable import KaiMD

@Suite("Workspace operations")
struct WorkspaceTests {
    @Test("scanner keeps only the Markdown navigation tree")
    @MainActor
    func scannerFiltersWorkspace() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Readme".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("ignore".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("cover.png"))

        let docs = root.appendingPathComponent("docs/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data("# Guide".utf8).write(to: docs.appendingPathComponent("Guide.markdown"))
        try Data([0xFF, 0xD8, 0xFF]).write(to: docs.appendingPathComponent("preview.jpg"))

        let mixed = root.appendingPathComponent("mixed", isDirectory: true)
        try FileManager.default.createDirectory(at: mixed, withIntermediateDirectories: true)
        try Data("# Plan".utf8).write(to: mixed.appendingPathComponent("PLAN.MD"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: mixed.appendingPathComponent("photo.png"))

        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assets.appendingPathComponent("only-image.png"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("empty", isDirectory: true),
            withIntermediateDirectories: true
        )

        let ignored = root.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try Data("# Hidden".utf8).write(to: ignored.appendingPathComponent("hidden.md"))

        let session = WorkspaceSession(rootURL: root)
        session.refresh()
        #expect(session.nodes.map(\.name) == ["docs", "mixed", "README.md"])

        let flattened = flatten(session.nodes)
        #expect(flattened.filter { !$0.isDirectory }.allSatisfy { $0.isMarkdown })
        #expect(flattened.contains { $0.name == "Guide.markdown" })
        #expect(flattened.contains { $0.name == "PLAN.MD" })
        #expect(!flattened.contains { $0.name == "assets" || $0.name == "empty" })
        #expect(!flattened.contains { $0.isImage || $0.name == "notes.txt" })
    }

    @Test("search excludes image filenames")
    @MainActor
    func searchOnlyReturnsMarkdown() async throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# Cover".utf8).write(to: root.appendingPathComponent("cover.md"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("cover.png"))

        let session = WorkspaceSession(rootURL: root)
        let results = await session.search(query: "cover")

        #expect(!results.isEmpty)
        #expect(results.allSatisfy {
            WorkspaceFileScanner.markdownExtensions.contains($0.fileURL.pathExtension.lowercased())
        })
    }

    @Test("sidebar selection matches only the current Markdown file")
    func sidebarSelectionMatchesCurrentMarkdown() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let markdownURL = root.appendingPathComponent("docs/../README.md")
        let canonicalURL = root.appendingPathComponent("README.md")
        let markdown = WorkspaceFileNode(
            url: canonicalURL,
            name: "README.md",
            kind: .markdown,
            children: []
        )
        let directory = WorkspaceFileNode(
            url: canonicalURL,
            name: "README.md",
            kind: .directory,
            children: [markdown]
        )
        let image = WorkspaceFileNode(
            url: canonicalURL,
            name: "README.md",
            kind: .image,
            children: []
        )

        #expect(WorkspaceSidebarSelection.isSelected(markdown, selectedFileURL: markdownURL))
        #expect(!WorkspaceSidebarSelection.isSelected(directory, selectedFileURL: canonicalURL))
        #expect(!WorkspaceSidebarSelection.isSelected(image, selectedFileURL: canonicalURL))
        #expect(!WorkspaceSidebarSelection.isSelected(markdown, selectedFileURL: nil))
        #expect(!WorkspaceSidebarSelection.isSelected(
            markdown,
            selectedFileURL: root.appendingPathComponent("Other.md")
        ))
    }

    @Test("creates, renames, duplicates and searches Markdown")
    @MainActor
    func fileOperationsAndSearch() async throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(rootURL: root)
        let created = try session.createMarkdownFile(named: "Guide")
        try Data("# Guide\nUnique needle lives here.\n".utf8).write(to: created)
        session.refresh()

        let renamed = try session.renameItem(at: created, to: "Manual.md")
        let copy = try session.duplicateItem(at: renamed)
        #expect(copy.lastPathComponent == "Manual copy.md")

        let results = await session.search(query: "needle")
        #expect(results.contains { $0.fileURL.lastPathComponent == "Manual.md" && $0.lineNumber == 2 })
        #expect(results.contains { $0.fileURL.lastPathComponent == "Manual copy.md" && $0.lineNumber == 2 })
    }

    @Test("imports pasted image beside document using a relative link")
    @MainActor
    func importsImage() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent("README.md")
        try Data().write(to: documentURL)

        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()

        let markdown = try AssetImportService.importImage(image, for: documentURL)
        #expect(markdown.hasPrefix("![image](assets/image"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/image.png").path))
    }

    @Test("duplicates the current buffer of an open document")
    @MainActor
    func duplicateUsesOpenDocumentBuffer() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Draft.md")
        try Data("# On disk\n".utf8).write(to: sourceURL)
        let session = WorkspaceSession(rootURL: root)
        session.refresh()

        do {
            let document = try MarkdownDocument(
                contentsOf: sourceURL,
                ofType: "net.daringfireball.markdown"
            )
            document.workspace = session
            NSDocumentController.shared.addDocument(document)
            defer { NSDocumentController.shared.removeDocument(document) }

            document.replaceEntireText("# Current editor buffer\n")
            let duplicateURL = try WorkspaceCoordinator.shared.duplicateItem(
                at: sourceURL,
                in: session
            )

            #expect(try String(contentsOf: sourceURL, encoding: .utf8) == "# On disk\n")
            #expect(try String(contentsOf: duplicateURL, encoding: .utf8) == "# Current editor buffer\n")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaiMDWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func flatten(_ nodes: [WorkspaceFileNode]) -> [WorkspaceFileNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
}
