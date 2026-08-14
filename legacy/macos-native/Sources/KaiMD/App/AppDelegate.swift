import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasFinishedLaunching = false
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.install(for: self)
        NSDocumentController.shared.autosavingDelay = 0.5
        hasFinishedLaunching = true

        if pendingOpenURLs.isEmpty {
            if !WorkspaceCoordinator.shared.restorePreviousSession() {
                WorkspaceCoordinator.shared.showWelcomeIfNeeded()
            }
        } else {
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            open(urls)
        }

        if NSApplication.shared.windows.allSatisfy({ !$0.isVisible }) {
            WorkspaceCoordinator.shared.showWelcomeIfNeeded()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceCoordinator.shared.persistSessionState()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WorkspaceCoordinator.shared.showWelcome()
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if hasFinishedLaunching {
            open(urls)
        } else {
            for url in urls where !pendingOpenURLs.contains(where: {
                $0.standardizedFilePath == url.standardizedFilePath
            }) {
                pendingOpenURLs.append(url)
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    @objc func openItem(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "打开 Markdown 文件或文件夹"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        WorkspaceCoordinator.shared.open(url: url)
    }

    @objc func newMarkdownFile(_ sender: Any?) {
        WorkspaceCoordinator.shared.createMarkdownFileFromKeyWindow()
    }

    @objc func quickOpen(_ sender: Any?) { post(.kaiMDQuickOpen) }
    @objc func workspaceSearch(_ sender: Any?) { post(.kaiMDWorkspaceSearch) }
    @objc func sourceMode(_ sender: Any?) { post(.kaiMDSetSourceMode) }
    @objc func splitMode(_ sender: Any?) { post(.kaiMDSetSplitMode) }
    @objc func previewMode(_ sender: Any?) { post(.kaiMDSetPreviewMode) }
    @objc func toggleSidebar(_ sender: Any?) { post(.kaiMDToggleSidebar) }
    @objc func insertBold(_ sender: Any?) { post(.kaiMDInsertBold) }
    @objc func insertItalic(_ sender: Any?) { post(.kaiMDInsertItalic) }
    @objc func insertLink(_ sender: Any?) { post(.kaiMDInsertLink) }

    @objc func revealCurrentDocument(_ sender: Any?) {
        guard let url = WorkspaceCoordinator.shared.currentDocumentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func showWelcome(_ sender: Any?) {
        WorkspaceCoordinator.shared.showWelcome()
    }

    @objc func showAboutPanel(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "KaiMD",
            .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "一个极简、原生、本地优先的 Markdown 编辑器。"),
        ])
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: NSApplication.shared.keyWindow)
    }

    private func open(_ urls: [URL]) {
        for url in urls {
            WorkspaceCoordinator.shared.open(url: url)
        }
    }
}
