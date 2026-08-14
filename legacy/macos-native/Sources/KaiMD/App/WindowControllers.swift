import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController {
    init(
        recentWorkspaces: [URL],
        onOpen: @escaping () -> Void,
        onOpenRecent: @escaping (URL) -> Void
    ) {
        let rootView = WelcomeView(
            recentWorkspaces: recentWorkspaces,
            onOpen: onOpen,
            onOpenRecent: onOpenRecent
        )
        let window = Self.makeWindow(
            title: "KaiMD",
            size: NSSize(width: 720, height: 560),
            rootView: rootView
        )
        window.tabbingMode = .disallowed
        super.init(window: window)
        shouldCascadeWindows = false
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    fileprivate static func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 620, height: 440)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
    }
}

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private(set) var session: WorkspaceSession
    private(set) var selectedDocument: MarkdownDocument?
    private let onOpen: (URL) -> Void

    init(session: WorkspaceSession, onOpen: @escaping (URL) -> Void) {
        self.session = session
        self.onOpen = onOpen
        let rootView = WorkspaceHomeView(session: session, onOpen: onOpen)
        let window = WelcomeWindowController.makeWindow(
            title: session.rootURL.lastPathComponent,
            size: NSSize(width: 1_080, height: 720),
            rootView: rootView
        )
        super.init(window: window)
        window.setFrameAutosaveName("KaiMD.WorkspaceWindow")
    }

    func show(document: MarkdownDocument, in session: WorkspaceSession) {
        if selectedDocument !== document {
            if let selectedDocument {
                selectedDocument.removeWindowController(self)
            }
            if !document.windowControllers.contains(where: { $0 === self }) {
                document.addWindowController(self)
            }
            selectedDocument = document
        }

        self.session = session
        document.workspace = session
        let openFileURLs = NSDocumentController.shared.documents
            .compactMap { ($0 as? MarkdownDocument)?.fileURL }
        window?.contentViewController = NSHostingController(
            rootView: MarkdownWorkspaceView(
                document: document,
                session: session,
                openFileURLs: openFileURLs
            )
        )
        window?.title = document.displayName
        window?.representedURL = document.fileURL
        window?.setFrameAutosaveName("KaiMD.WorkspaceWindow")
    }

    func showWorkspace(_ session: WorkspaceSession) {
        if let selectedDocument {
            selectedDocument.removeWindowController(self)
            self.selectedDocument = nil
        }
        self.session = session
        window?.contentViewController = NSHostingController(
            rootView: WorkspaceHomeView(session: session, onOpen: onOpen)
        )
        window?.title = session.rootURL.lastPathComponent
        window?.representedURL = session.rootURL
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
