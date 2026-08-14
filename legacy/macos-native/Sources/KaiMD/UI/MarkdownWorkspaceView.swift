import AppKit
import SwiftUI

private struct MarkdownRenderRevision: Hashable {
    let source: String
    let documentPath: String?
    let workspacePath: String
}

struct MarkdownWorkspaceView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var session: WorkspaceSession
    private let openFileURLs: [URL]

    @State private var sidebarMode: SidebarMode = .files
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var editorMode: EditorMode
    @State private var metrics = MarkdownEditorMetrics(line: 1, column: 1, wordCount: 0, characterCount: 0)
    @State private var rendered: RenderedMarkdown?
    @State private var transientError: String?
    @State private var window: NSWindow?

    init(document: MarkdownDocument, session: WorkspaceSession, openFileURLs: [URL] = []) {
        self.document = document
        self.openFileURLs = openFileURLs
        _session = State(initialValue: session)
        let stored = UserDefaults.standard.string(forKey: "KaiMD.defaultEditorMode")
        _editorMode = State(initialValue: EditorMode(rawValue: stored ?? "") ?? .split)
        let sidebarVisible = UserDefaults.standard.object(forKey: "KaiMD.sidebarVisible") as? Bool ?? true
        _columnVisibility = State(initialValue: sidebarVisible ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebarView(
                session: session,
                mode: $sidebarMode,
                selectedFileURL: document.fileURL,
                openFileURLs: openFileURLs,
                onOpen: openDocument
            )
        } detail: {
            VStack(spacing: 0) {
                documentToolbar
                Divider()
                notices
                editorContent
                Divider()
                statusBar
            }
        }
        .background(WindowAccessor { resolved in
            window = resolved
            resolved?.title = document.displayName
            resolved?.representedURL = document.fileURL
        })
        .task(id: renderRevision) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let revision = renderRevision
            let nextRender = await MarkdownRenderService.shared.render(
                revision.source,
                documentURL: document.fileURL,
                workspaceRoot: session.rootURL
            )
            guard !Task.isCancelled, revision == renderRevision else { return }
            rendered = nextRender
        }
        .onChange(of: editorMode) { _, value in
            UserDefaults.standard.set(value.rawValue, forKey: "KaiMD.defaultEditorMode")
        }
        .onChange(of: document.workspace?.rootURL) { _, _ in
            if let nextSession = document.workspace, nextSession !== session {
                session = nextSession
            }
        }
        .onChange(of: columnVisibility) { _, value in
            UserDefaults.standard.set(value != .detailOnly, forKey: "KaiMD.sidebarVisible")
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDSetSourceMode)) { note in
            if isForCurrentWindow(note) { editorMode = .source }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDSetSplitMode)) { note in
            if isForCurrentWindow(note) { editorMode = .split }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDSetPreviewMode)) { note in
            if isForCurrentWindow(note) { editorMode = .preview }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDToggleSidebar)) { note in
            guard isForCurrentWindow(note) else { return }
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
        .alert("操作失败", isPresented: Binding(
            get: { transientError != nil },
            set: { if !$0 { transientError = nil } }
        )) {
            Button("好") { transientError = nil }
        } message: {
            Text(transientError ?? "未知错误")
        }
    }

    private var documentToolbar: some View {
        HStack(spacing: 10) {
            Button {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            } label: {
                Image(systemName: "sidebar.leading")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("显示或隐藏侧栏")

            VStack(alignment: .leading, spacing: 1) {
                Text(document.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let fileURL = document.fileURL {
                    Text(session.relativePath(for: fileURL) ?? fileURL.path(percentEncoded: false))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.kaiMDSecondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            Picker("编辑器模式", selection: $editorMode) {
                ForEach(EditorMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Text(saveStatus)
                .font(.system(size: 10))
                .foregroundStyle(document.lastSaveError == nil ? Color.kaiMDSecondaryText : Color.red)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    @ViewBuilder
    private var notices: some View {
        if document.requiresNewlineNormalization {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text("文件包含混合换行符，保存前请选择统一格式。")
                Spacer()
                Button("转为 LF") { document.resolveMixedNewlines(using: .lineFeed) }
                Button("转为 CRLF") { document.resolveMixedNewlines(using: .carriageReturnLineFeed) }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.orange.opacity(0.09))
        }
        if let error = document.lastSaveError {
            let backingFileWasDeleted = (error as? MarkdownDocumentError) == .backingFileDeleted
            InlineNotice(
                kind: .error,
                message: backingFileWasDeleted ? error.localizedDescription : "保存失败：\(error.localizedDescription)",
                actionTitle: backingFileWasDeleted ? "重新保存" : "重试",
                action: { document.saveNow() }
            )
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        switch editorMode {
        case .source:
            sourceEditor
        case .split:
            HSplitView {
                sourceEditor
                    .frame(minWidth: 300)
                preview
                    .frame(minWidth: 300)
            }
        case .preview:
            preview
        }
    }

    private var sourceEditor: some View {
        MarkdownEditorView(
            text: Binding(
                get: { document.text },
                set: { document.applyEditedText($0, undoHandledByEditor: true) }
            ),
            undoManager: document.undoManager,
            onMetricsChange: { metrics = $0 },
            onImage: importImage,
            onImageFile: importImageFile
        )
        .accessibilityLabel("Markdown 源码编辑器")
    }

    @ViewBuilder
    private var preview: some View {
        if let rendered {
            MarkdownPreview(
                rendered: rendered,
                documentURL: document.fileURL,
                workspaceRoot: session.rootURL,
                onOpenDocument: openDocument,
                onOpenExternalLink: { NSWorkspace.shared.open($0) }
            )
            .accessibilityLabel("Markdown 预览")
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("\(metrics.wordCount) 词")
            Text("\(metrics.characterCount) 字符")
            Spacer()
            Text("行 \(metrics.line)，列 \(metrics.column)")
            Text(document.newlineStyle.displayName)
            Text(document.hasUTF8BOM ? "UTF-8 BOM" : "UTF-8")
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.kaiMDSecondaryText)
        .padding(.horizontal, 10)
        .frame(height: KaiMDDesign.statusBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var saveStatus: String {
        if document.lastSaveError != nil { return "保存失败" }
        return document.isDocumentEdited ? "保存中…" : "已保存"
    }

    private var renderRevision: MarkdownRenderRevision {
        MarkdownRenderRevision(
            source: document.text,
            documentPath: document.fileURL?.standardizedFilePath,
            workspacePath: session.rootURL.standardizedFilePath
        )
    }

    private func openDocument(_ rawURL: URL) {
        var url = rawURL
        if var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false), components.fragment != nil {
            components.fragment = nil
            url = components.url ?? rawURL
        }
        guard WorkspaceFileScanner.markdownExtensions.contains(url.pathExtension.lowercased()) else {
            NSWorkspace.shared.open(url)
            return
        }
        WorkspaceCoordinator.shared.open(url: url)
    }

    private func importImage(_ image: NSImage) -> String? {
        do {
            return try AssetImportService.shared.importImage(image, into: document)
        } catch {
            transientError = error.localizedDescription
            return nil
        }
    }

    private func importImageFile(_ url: URL) -> String? {
        do {
            return try AssetImportService.shared.importImage(from: url, into: document)
        } catch {
            transientError = error.localizedDescription
            return nil
        }
    }

    private func isForCurrentWindow(_ notification: Notification) -> Bool {
        notification.object == nil || notification.object as? NSWindow === window
    }
}
