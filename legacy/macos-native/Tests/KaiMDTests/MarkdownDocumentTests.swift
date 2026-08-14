import AppKit
import Combine
import Foundation
import Testing
@testable import KaiMD

@Suite("Markdown document encoding")
struct MarkdownDocumentTests {
    @Test("reads and preserves UTF-8 BOM with CRLF")
    @MainActor
    func preservesBOMAndCRLF() throws {
        _ = NSApplication.shared
        let source = Data([0xEF, 0xBB, 0xBF]) + Data("# 标题\r\n\r\n正文\r\n".utf8)
        let document = MarkdownDocument()

        try document.read(from: source, ofType: "net.daringfireball.markdown")

        #expect(document.text == "# 标题\n\n正文\n")
        #expect(document.hasUTF8BOM)
        #expect(document.newlineStyle == .carriageReturnLineFeed)
        #expect(document.hasTrailingNewline)
        #expect(try document.data(ofType: "net.daringfireball.markdown") == source)
    }

    @Test("rejects invalid UTF-8")
    @MainActor
    func rejectsInvalidUTF8() {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        #expect(throws: MarkdownDocumentError.invalidUTF8) {
            try document.read(from: Data([0xFF, 0xFE, 0x00]), ofType: "net.daringfireball.markdown")
        }
    }

    @Test("mixed line endings require an explicit resolution")
    @MainActor
    func mixedNewlinesRequireResolution() throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        try document.read(
            from: Data("first\r\nsecond\nthird".utf8),
            ofType: "net.daringfireball.markdown"
        )
        #expect(document.newlineStyle == .mixed)
        #expect(throws: MarkdownDocumentError.mixedNewlinesRequireResolution) {
            try document.data(ofType: "net.daringfireball.markdown")
        }

        document.resolveMixedNewlines(using: .lineFeed)
        #expect(try String(data: document.data(ofType: "net.daringfireball.markdown"), encoding: .utf8) == "first\nsecond\nthird")
    }

    @Test("publishes when the backing URL changes")
    @MainActor
    func fileURLChangePublishes() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaiMDDocumentURLTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = WorkspaceSession(rootURL: root)
        let document = MarkdownDocument(workspace: session)
        var publicationCount = 0
        let observation = document.objectWillChange.sink { publicationCount += 1 }

        document.fileURL = root.appendingPathComponent("Renamed.md")
        await Task.yield()
        await Task.yield()

        #expect(publicationCount > 0)
        withExtendedLifetime(observation) {}
    }

    @Test("external deletion preserves the buffer and marks the document dirty")
    @MainActor
    func externalDeletionPreservesBuffer() async throws {
        _ = NSApplication.shared
        let original = Data("# Still in memory\n".utf8)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: "net.daringfireball.markdown")
        await Task.yield()

        let completed = await withCheckedContinuation { continuation in
            document.accommodatePresentedItemDeletion { error in
                continuation.resume(returning: error == nil)
            }
        }

        #expect(completed)
        #expect(document.text == "# Still in memory\n")
        #expect(document.isDocumentEdited)
        #expect((document.lastSaveError as? MarkdownDocumentError) == .backingFileDeleted)
        #expect(try document.data(ofType: "net.daringfireball.markdown") == original)
    }
}
