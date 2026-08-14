import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceCoordinator {
    static let shared = WorkspaceCoordinator()

    private struct WeakWindow {
        weak var value: NSWindow?
    }

    private var anchors: [String: WeakWindow] = [:]
    private var sessionsByWindow: [ObjectIdentifier: WorkspaceSession] = [:]
    private var workspaceControllers: [ObjectIdentifier: WorkspaceWindowController] = [:]
    private var welcomeController: WelcomeWindowController?
    private var isRestoring = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    var currentDocumentURL: URL? {
        (NSApplication.shared.keyWindow?.windowController as? WorkspaceWindowController)?
            .selectedDocument?
            .fileURL
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let identifier = ObjectIdentifier(window)
        guard let session = sessionsByWindow.removeValue(forKey: identifier) else { return }
        workspaceControllers.removeValue(forKey: identifier)

        let key = session.rootURL.standardizedFilePath
        guard anchors[key]?.value === window else { return }
        let replacement = NSApplication.shared.windows.first { candidate in
            candidate !== window
                && candidate.isVisible
                && sessionsByWindow[ObjectIdentifier(candidate)]?.rootURL.standardizedFilePath == key
        }
        anchors[key] = WeakWindow(value: replacement)
    }

    func showWelcomeIfNeeded() {
        guard NSApplication.shared.windows.allSatisfy({ !$0.isVisible }) else { return }
        showWelcome()
    }

    func showWelcome() {
        if let window = welcomeController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let controller = WelcomeWindowController(
            recentWorkspaces: WorkspaceRegistry.shared.recentWorkspaceURLs,
            onOpen: { [weak self] in self?.presentOpenPanel() },
            onOpenRecent: { [weak self] url in self?.openWorkspace(at: url) }
        )
        welcomeController = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func open(url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                openWorkspace(at: url)
            } else {
                let root = WorkspaceRegistry.shared.session(containing: url)?.rootURL
                    ?? url.deletingLastPathComponent()
                let session = WorkspaceRegistry.shared.session(for: root)
                try openDocument(at: url, in: session)
            }
        } catch {
            present(error: error)
        }
    }

    func openWorkspace(at url: URL) {
        let session = WorkspaceRegistry.shared.session(for: url)
        session.scheduleRefresh(after: .zero)

        if let existing = liveAnchor(for: session) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        if let controller = reusableWorkspaceController(), let window = controller.window {
            unregister(window: window)
            controller.showWorkspace(session)
            configure(window: window, for: session)
            workspaceControllers[ObjectIdentifier(window)] = controller
            register(window: window, for: session, asAnchor: true)
            window.makeKeyAndOrderFront(nil)
            welcomeController?.close()
            welcomeController = nil
            NSApplication.shared.activate(ignoringOtherApps: true)
            persistSessionStateIfNeeded()
            return
        }

        let controller = WorkspaceWindowController(session: session) { [weak self] fileURL in
            self?.open(url: fileURL)
        }
        guard let window = controller.window else { return }
        workspaceControllers[ObjectIdentifier(window)] = controller
        configure(window: window, for: session)
        register(window: window, for: session, asAnchor: true)
        controller.showWindow(nil)
        welcomeController?.close()
        welcomeController = nil
        NSApplication.shared.activate(ignoringOtherApps: true)
        persistSessionStateIfNeeded()
    }

    func openDocument(at url: URL, in session: WorkspaceSession) throws {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard WorkspaceFileScanner.markdownExtensions.contains(canonicalURL.pathExtension.lowercased()) else {
            throw WorkspaceError.operationFailed("KaiMD 仅编辑 .md 和 .markdown 文件。")
        }
        guard canonicalURL.isContained(in: session.rootURL) else {
            throw WorkspaceError.itemOutsideWorkspace(canonicalURL)
        }

        session.scheduleRefresh(after: .zero)

        let document: MarkdownDocument
        if let existing = NSDocumentController.shared.documents
            .compactMap({ $0 as? MarkdownDocument })
            .first(where: { $0.fileURL?.standardizedFilePath == canonicalURL.standardizedFilePath })
        {
            if existing.workspace !== session {
                existing.workspace = session
            }
            document = existing
        } else {
            document = try MarkdownDocument(
                contentsOf: canonicalURL,
                ofType: "net.daringfireball.markdown"
            )
            document.workspace = session
            NSDocumentController.shared.addDocument(document)
        }

        present(document: document, in: session)
        persistSessionStateIfNeeded()
    }

    /// Presents a document through the app's single reusable workspace window.
    /// This is also used by NSDocument's fallback `makeWindowControllers` path,
    /// so AppKit-originated opens cannot bypass the coordinator and spawn a
    /// second editor window.
    func present(document: MarkdownDocument, in session: WorkspaceSession) {
        let controller: WorkspaceWindowController
        if let reusable = reusableWorkspaceController() {
            controller = reusable
        } else {
            controller = WorkspaceWindowController(session: session) { [weak self] fileURL in
                self?.open(url: fileURL)
            }
        }
        guard let window = controller.window else { return }
        unregister(window: window)
        controller.show(document: document, in: session)
        workspaceControllers[ObjectIdentifier(window)] = controller
        configure(window: window, for: session)
        window.representedURL = document.fileURL
        register(window: window, for: session, asAnchor: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        welcomeController?.close()
        welcomeController = nil
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @discardableResult
    func restorePreviousSession() -> Bool {
        guard !isRestoring,
              let snapshot = WorkspaceRestorationStore.shared.load(),
              !snapshot.workspaces.isEmpty
        else {
            return false
        }

        isRestoring = true
        defer { isRestoring = false }
        var restoredAny = false

        for savedWorkspace in snapshot.workspaces {
            let rootURL = URL(fileURLWithPath: savedWorkspace.rootPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }

            openWorkspace(at: rootURL)
            restoredAny = true
            let session = WorkspaceRegistry.shared.session(for: rootURL)
            for relativePath in savedWorkspace.openRelativePaths {
                let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
                guard fileURL.isContained(in: rootURL),
                      FileManager.default.fileExists(atPath: fileURL.path)
                else {
                    continue
                }
                do {
                    try openDocument(at: fileURL, in: session)
                    restoredAny = true
                } catch {
                    continue
                }
            }

            if let selectedRelativePath = savedWorkspace.selectedRelativePath {
                let selectedURL = rootURL.appendingPathComponent(selectedRelativePath).standardizedFileURL
                if document(for: selectedURL) != nil {
                    try? openDocument(at: selectedURL, in: session)
                }
            }
        }
        return restoredAny
    }

    func persistSessionState() {
        let documents = NSDocumentController.shared.documents.compactMap { $0 as? MarkdownDocument }
        var roots = Set(anchors.compactMap { key, weakWindow -> String? in
            guard let window = weakWindow.value,
                  window.isVisible,
                  sessionsByWindow[ObjectIdentifier(window)]?.rootURL.standardizedFilePath == key
            else {
                return nil
            }
            return key
        })
        for document in documents {
            if let root = document.workspace?.rootURL.standardizedFilePath {
                roots.insert(root)
            }
        }

        let selectedDocument = (NSApplication.shared.keyWindow?.windowController as? WorkspaceWindowController)?
            .selectedDocument
        let selectedRootPath = selectedDocument?.workspace?.rootURL.standardizedFilePath
        let orderedRootPaths = roots.sorted { lhs, rhs in
            if lhs == selectedRootPath { return false }
            if rhs == selectedRootPath { return true }
            return lhs < rhs
        }
        let restoredWorkspaces = orderedRootPaths.compactMap { rootPath -> RestoredWorkspace? in
            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            let workspaceDocuments = documents.filter { $0.workspace?.rootURL.standardizedFilePath == rootPath }
            let orderedDocuments = orderedDocumentsForWorkspace(rootPath: rootPath, fallback: workspaceDocuments)
            let openPaths = orderedDocuments.compactMap { document in
                document.fileURL.flatMap { relativePath(of: $0, inside: rootURL) }
            }
            let selectedPath: String?
            if selectedDocument?.workspace?.rootURL.standardizedFilePath == rootPath,
               let fileURL = selectedDocument?.fileURL
            {
                selectedPath = relativePath(of: fileURL, inside: rootURL)
            } else {
                selectedPath = openPaths.first
            }
            return RestoredWorkspace(
                rootPath: rootPath,
                openRelativePaths: openPaths,
                selectedRelativePath: selectedPath
            )
        }
        WorkspaceRestorationStore.shared.save(
            WorkspaceRestorationSnapshot(workspaces: restoredWorkspaces)
        )
    }

    func createMarkdownFileFromKeyWindow() {
        let session = currentWorkspaceSession()
        let panel = NSSavePanel()
        panel.title = "新建 Markdown 文件"
        panel.prompt = "创建"
        panel.nameFieldStringValue = "Untitled.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = session?.rootURL

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try Data().write(to: destination, options: .withoutOverwriting)
            }
            let targetSession: WorkspaceSession
            if let session, destination.isContained(in: session.rootURL) {
                targetSession = session
            } else {
                targetSession = WorkspaceRegistry.shared.session(for: destination.deletingLastPathComponent())
            }
            targetSession.scheduleRefresh(after: .zero)
            try openDocument(at: destination, in: targetSession)
        } catch {
            present(error: error)
        }
    }

    func renameItem(
        at sourceURL: URL,
        to requestedName: String,
        in session: WorkspaceSession,
        completion: @escaping (Error?) -> Void
    ) {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains(":"),
              !trimmed.contains("\0")
        else {
            completion(WorkspaceError.invalidName(requestedName))
            return
        }

        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            completion(WorkspaceError.destinationExists(destination))
            return
        }

        let affected = openDocuments(under: source)
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory, !affected.isEmpty {
            completion(WorkspaceError.operationFailed("请先关闭该文件夹中的已打开文稿，再重命名文件夹。"))
            return
        }

        if !isDirectory, let document = affected.first,
           document.fileURL?.standardizedFilePath == source.standardizedFilePath
        {
            document.move(to: destination) { error in
                session.scheduleRefresh()
                completion(error)
            }
            return
        }

        do {
            _ = try session.renameItem(at: source, to: trimmed)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    /// Duplicates the on-disk item while replacing every open Markdown file in
    /// the copy with its current in-memory serialization. This prevents the
    /// duplicate from silently lagging behind the editor's debounced autosave.
    @discardableResult
    func duplicateItem(at sourceURL: URL, in session: WorkspaceSession) throws -> URL {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        guard source.standardizedFilePath != session.rootURL.standardizedFilePath,
              source.isContained(in: session.rootURL)
        else {
            throw WorkspaceError.itemOutsideWorkspace(sourceURL)
        }

        let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let snapshots = try openDocuments(under: source).map { document -> (components: [String], data: Data) in
            guard let documentURL = document.fileURL else {
                throw MarkdownDocumentError.unsavedDocument
            }

            let components: [String]
            if isDirectory {
                guard let relativeComponents = relativePathComponents(of: documentURL, inside: source),
                      !relativeComponents.isEmpty
                else {
                    throw WorkspaceError.operationFailed("无法确定已打开文稿在复制项目中的位置。")
                }
                components = relativeComponents
            } else {
                guard documentURL.standardizedFilePath == source.standardizedFilePath else {
                    throw WorkspaceError.operationFailed("无法确定已打开文稿的复制位置。")
                }
                components = []
            }

            let typeName = document.fileType ?? "net.daringfireball.markdown"
            return (components, try document.data(ofType: typeName))
        }

        let destination = try session.duplicateItem(at: source)
        do {
            for snapshot in snapshots {
                let target = snapshot.components.reduce(destination) { partial, component in
                    partial.appendingPathComponent(component)
                }
                if isDirectory {
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                }
                try snapshot.data.write(to: target, options: .atomic)
            }
            session.scheduleRefresh(after: .zero)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            session.scheduleRefresh(after: .zero)
            throw error
        }
    }

    func moveItemToTrash(at sourceURL: URL, in session: WorkspaceSession) throws {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        guard openDocuments(under: source).isEmpty else {
            throw WorkspaceError.operationFailed("请先关闭此文件或文件夹中的已打开文稿，再移到废纸篓。")
        }
        try session.moveItemToTrash(at: source)
    }

    func currentWorkspaceSession() -> WorkspaceSession? {
        if let controller = NSApplication.shared.keyWindow?.windowController as? WorkspaceWindowController {
            return controller.session
        }
        if let document = NSDocumentController.shared.currentDocument as? MarkdownDocument,
           let workspace = document.workspace
        {
            return workspace
        }
        guard let window = NSApplication.shared.keyWindow else { return nil }
        return sessionsByWindow[ObjectIdentifier(window)]
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开 Markdown 文件或文件夹"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .folder,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func present(error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        if let window = NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func configure(window: NSWindow, for session: WorkspaceSession) {
        window.tabbingMode = .disallowed
        window.tabbingIdentifier = "KaiMD.workspace.\(stableIdentifier(for: session.rootURL))"
        window.representedURL = session.rootURL
        window.isRestorable = true
    }

    private func register(window: NSWindow, for session: WorkspaceSession, asAnchor: Bool) {
        sessionsByWindow[ObjectIdentifier(window)] = session
        if asAnchor {
            anchors[session.rootURL.standardizedFilePath] = WeakWindow(value: window)
        }
    }

    private func unregister(window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        sessionsByWindow.removeValue(forKey: identifier)
        for key in anchors.keys where anchors[key]?.value === window {
            anchors.removeValue(forKey: key)
        }
    }

    private func reusableWorkspaceController() -> WorkspaceWindowController? {
        if let controller = NSApplication.shared.keyWindow?.windowController as? WorkspaceWindowController,
           controller.window?.isVisible == true
        {
            return controller
        }
        return workspaceControllers.values.first { $0.window?.isVisible == true }
    }

    private func liveAnchor(for session: WorkspaceSession) -> NSWindow? {
        let key = session.rootURL.standardizedFilePath
        if let stored = anchors[key]?.value,
           stored.isVisible,
           sessionsByWindow[ObjectIdentifier(stored)]?.rootURL.standardizedFilePath == key
        {
            return stored
        }

        let candidate = NSApplication.shared.windows.first { window in
            guard window.isVisible,
                  sessionsByWindow[ObjectIdentifier(window)]?.rootURL.standardizedFilePath == key
            else {
                return false
            }
            return window.windowController is WorkspaceWindowController
        }
        anchors[key] = WeakWindow(value: candidate)
        return candidate
    }

    func rebind(document: MarkdownDocument, to session: WorkspaceSession) {
        let oldSession = document.workspace
        guard oldSession !== session else {
            session.scheduleRefresh()
            return
        }

        guard let controller = document.windowControllers.first as? WorkspaceWindowController,
              let window = controller.window
        else {
            document.workspace = session
            oldSession?.scheduleRefresh()
            session.scheduleRefresh()
            return
        }

        unregister(window: window)
        controller.show(document: document, in: session)
        configure(window: window, for: session)
        workspaceControllers[ObjectIdentifier(window)] = controller
        register(window: window, for: session, asAnchor: true)
        window.representedURL = document.fileURL
        window.title = document.displayName

        if let oldSession {
            oldSession.scheduleRefresh()
        }
        session.scheduleRefresh()
        persistSessionStateIfNeeded()
    }

    private func stableIdentifier(for url: URL) -> String {
        String(url.standardizedFilePath.unicodeScalars.reduce(into: UInt64(5_381)) { result, scalar in
            result = ((result << 5) &+ result) &+ UInt64(scalar.value)
        }, radix: 16)
    }

    private func persistSessionStateIfNeeded() {
        guard !isRestoring else { return }
        persistSessionState()
    }

    private func document(for url: URL) -> MarkdownDocument? {
        NSDocumentController.shared.documents
            .compactMap { $0 as? MarkdownDocument }
            .first { $0.fileURL?.standardizedFilePath == url.standardizedFilePath }
    }

    private func orderedDocumentsForWorkspace(
        rootPath _: String,
        fallback: [MarkdownDocument]
    ) -> [MarkdownDocument] {
        fallback
    }

    private func relativePath(of fileURL: URL, inside rootURL: URL) -> String? {
        let file = fileURL.standardizedFileURL
        guard file.isContained(in: rootURL) else { return nil }
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = file.pathComponents
        guard fileComponents.count > rootComponents.count else { return nil }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func relativePathComponents(of fileURL: URL, inside rootURL: URL) -> [String]? {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let file = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let fileComponents = file.pathComponents
        guard fileComponents.count >= rootComponents.count,
              fileComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
        else {
            return nil
        }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    private func openDocuments(under itemURL: URL) -> [MarkdownDocument] {
        NSDocumentController.shared.documents
            .compactMap { $0 as? MarkdownDocument }
            .filter { document in
                guard let fileURL = document.fileURL else { return false }
                return fileURL.standardizedFilePath == itemURL.standardizedFilePath
                    || fileURL.isContained(in: itemURL)
            }
    }
}
