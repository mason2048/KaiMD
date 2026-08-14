import AppKit
import Foundation
import Testing
@testable import KaiMD

@Suite("Single-window document lifecycle")
struct WindowIntegrationTests {
    @Test("opening another document reuses the workspace window and changes selection")
    @MainActor
    func reusesWindowForDocumentSelection() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaiMDWindowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            for document in NSDocumentController.shared.documents.compactMap({ $0 as? MarkdownDocument })
                where document.workspace?.rootURL.standardizedFilePath == root.standardizedFilePath
            {
                document.windowControllers.forEach { $0.close() }
                NSDocumentController.shared.removeDocument(document)
            }
            WorkspaceRestorationStore.shared.clear()
            try? FileManager.default.removeItem(at: root)
        }

        let firstURL = root.appendingPathComponent("First.md")
        let secondURL = root.appendingPathComponent("Second.md")
        try Data("# First".utf8).write(to: firstURL)
        try Data("# Second".utf8).write(to: secondURL)

        let coordinator = WorkspaceCoordinator.shared
        let session = WorkspaceRegistry.shared.session(for: root)
        try coordinator.openDocument(at: firstURL, in: session)
        let firstDocument = document(at: firstURL)
        let firstWindow = try #require(firstDocument?.windowControllers.first?.window)

        try coordinator.openDocument(at: secondURL, in: session)

        let secondDocument = document(at: secondURL)
        let secondWindow = try #require(secondDocument?.windowControllers.first?.window)
        let controller = try #require(secondWindow.windowController as? WorkspaceWindowController)
        #expect(firstWindow === secondWindow)
        #expect(firstDocument?.windowControllers.isEmpty == true)
        #expect(controller.selectedDocument === secondDocument)
        #expect(secondWindow.tabbingMode == .disallowed)
        #expect(visibleWorkspaceWindows().count == 1)

        try coordinator.openDocument(at: firstURL, in: session)
        #expect(firstDocument?.windowControllers.first?.window === firstWindow)
        #expect(secondDocument?.windowControllers.isEmpty == true)
        #expect(controller.selectedDocument === firstDocument)
        #expect(visibleWorkspaceWindows().count == 1)

        let renamedURL = root.appendingPathComponent("Renamed.md")
        let renameError = await withCheckedContinuation { continuation in
            coordinator.renameItem(at: firstURL, to: renamedURL.lastPathComponent, in: session) {
                continuation.resume(returning: $0)
            }
        }
        #expect(renameError == nil)
        #expect(firstDocument?.fileURL?.standardizedFilePath == renamedURL.standardizedFilePath)
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        var refusedToTrashOpenDocument = false
        do {
            try coordinator.moveItemToTrash(at: renamedURL, in: session)
        } catch {
            refusedToTrashOpenDocument = true
        }
        #expect(refusedToTrashOpenDocument)
    }

    @Test("AppDelegate handles launch and later Finder opens in the same window")
    @MainActor
    func systemOpenFilesLifecycleUsesOneWindow() throws {
        let application = NSApplication.shared
        WorkspaceRestorationStore.shared.clear()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaiMDOpenFilesTests-\(UUID().uuidString)", isDirectory: true)
        let firstRoot = base.appendingPathComponent("A", isDirectory: true)
        let secondRoot = base.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            for document in NSDocumentController.shared.documents.compactMap({ $0 as? MarkdownDocument })
                where document.fileURL?.isContained(in: base) == true
            {
                document.windowControllers.forEach { $0.close() }
                NSDocumentController.shared.removeDocument(document)
            }
            WorkspaceRestorationStore.shared.clear()
            try? FileManager.default.removeItem(at: base)
        }

        let firstURL = firstRoot.appendingPathComponent("From-Finder.md")
        let secondURL = secondRoot.appendingPathComponent("From-Open-With.md")
        try Data("# Finder".utf8).write(to: firstURL)
        try Data("# Open With".utf8).write(to: secondURL)

        let delegate = AppDelegate()
        delegate.application(application, openFiles: [firstURL.path])
        #expect(document(at: firstURL) == nil)

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification, object: application)
        )
        let firstDocument = try #require(document(at: firstURL))
        let window = try #require(firstDocument.windowControllers.first?.window)

        delegate.application(application, openFiles: [secondURL.path])
        let secondDocument = try #require(document(at: secondURL))
        let controller = try #require(window.windowController as? WorkspaceWindowController)

        #expect(secondDocument.windowControllers.first?.window === window)
        #expect(firstDocument.windowControllers.isEmpty)
        #expect(controller.selectedDocument === secondDocument)
        #expect(NSDocumentController.shared.documents.contains { $0 === firstDocument })
        #expect(visibleWorkspaceWindows().count == 1)
    }

    @Test("moving a document outside its workspace rebinds the session")
    @MainActor
    func saveAsRebindsWorkspace() async throws {
        _ = NSApplication.shared
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaiMDRebindTests-\(UUID().uuidString)", isDirectory: true)
        let firstRoot = base.appendingPathComponent("A", isDirectory: true)
        let secondRoot = base.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            for document in NSDocumentController.shared.documents.compactMap({ $0 as? MarkdownDocument })
                where document.fileURL?.isContained(in: base) == true
            {
                document.windowControllers.forEach { $0.close() }
                NSDocumentController.shared.removeDocument(document)
            }
            WorkspaceRestorationStore.shared.clear()
            try? FileManager.default.removeItem(at: base)
        }

        let sourceURL = firstRoot.appendingPathComponent("Source.md")
        let destinationURL = secondRoot.appendingPathComponent("Moved.md")
        try Data("# Move".utf8).write(to: sourceURL)
        let coordinator = WorkspaceCoordinator.shared
        let initialSession = WorkspaceRegistry.shared.session(for: firstRoot)
        try coordinator.openDocument(at: sourceURL, in: initialSession)
        let movedDocument = try #require(document(at: sourceURL))

        let moveError = await withCheckedContinuation { continuation in
            movedDocument.move(to: destinationURL) { continuation.resume(returning: $0) }
        }
        #expect(moveError == nil)
        await Task.yield()
        await Task.yield()

        #expect(movedDocument.fileURL?.standardizedFilePath == destinationURL.standardizedFilePath)
        #expect(movedDocument.workspace?.rootURL.standardizedFilePath == secondRoot.standardizedFilePath)
        #expect(movedDocument.windowControllers.first?.window?.representedURL?.standardizedFilePath == destinationURL.standardizedFilePath)
    }

    @MainActor
    private func document(at url: URL) -> MarkdownDocument? {
        NSDocumentController.shared.documents
            .compactMap { $0 as? MarkdownDocument }
            .first { $0.fileURL?.standardizedFilePath == url.standardizedFilePath }
    }

    @MainActor
    private func visibleWorkspaceWindows() -> [NSWindow] {
        NSApplication.shared.windows.filter {
            $0.isVisible && $0.windowController is WorkspaceWindowController
        }
    }
}
