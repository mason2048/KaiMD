import AppKit
import SwiftUI

enum WorkspaceSidebarSelection {
    static func isSelected(_ node: WorkspaceFileNode, selectedFileURL: URL?) -> Bool {
        node.isMarkdown && matches(node.url, selectedFileURL: selectedFileURL)
    }

    static func matches(_ candidateURL: URL, selectedFileURL: URL?) -> Bool {
        guard let selectedFileURL else { return false }
        return candidateURL.standardizedFilePath == selectedFileURL.standardizedFilePath
    }
}

private extension WorkspaceFileNode {
    var outlineChildren: [WorkspaceFileNode]? {
        isDirectory ? children : nil
    }
}

struct WorkspaceSidebarView: View {
    @ObservedObject var session: WorkspaceSession
    @Binding var mode: SidebarMode
    let selectedFileURL: URL?
    var openFileURLs: [URL] = []
    let onOpen: (URL) -> Void

    @State private var query = ""
    @State private var results: [WorkspaceSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var window: NSWindow?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 190, idealWidth: KaiMDDesign.sidebarWidth)
        .background(Color.kaiMDSidebar)
        .background(WindowAccessor { window = $0 })
        .onChange(of: query) { _, value in performSearch(value) }
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDQuickOpen)) { note in
            guard isForCurrentWindow(note) else { return }
            mode = .search
            query = ""
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDWorkspaceSearch)) { note in
            guard isForCurrentWindow(note) else { return }
            mode = .search
            searchFieldFocused = true
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                Text(session.rootURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button("新建 Markdown 文件") { createMarkdown() }
                    Button("新建文件夹") { createFolder() }
                    Divider()
                    Button("刷新") { session.refresh() }
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([session.rootURL])
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("工作区操作")
            }

            Picker("侧栏内容", selection: $mode) {
                ForEach(SidebarMode.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .files:
            if session.nodes.isEmpty, session.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.nodes.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.kaiMDSecondaryText)
                    Text("还没有 Markdown 文件")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kaiMDSecondaryText)
                    Button("新建文件") { createMarkdown() }
                        .buttonStyle(.link)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !uniqueOpenFileURLs.isEmpty {
                            openFilesSection
                            Divider()
                                .padding(.vertical, 6)
                        }
                        OutlineGroup(session.nodes, children: \.outlineChildren) { node in
                            fileRow(node)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        case .search:
            searchContent
        }
    }

    private var openFilesSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("已打开")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.kaiMDSecondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, 13)
                .padding(.bottom, 3)

            ForEach(uniqueOpenFileURLs, id: \.standardizedFilePath) { url in
                let isSelected = WorkspaceSidebarSelection.matches(
                    url,
                    selectedFileURL: selectedFileURL
                )
                Button { onOpen(url) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(isSelected ? selectedTextColor : Color.accentColor)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? selectedTextColor : Color.primary)
                                .lineLimit(1)
                            if !url.isContained(in: session.rootURL) {
                                Text(url.deletingLastPathComponent().lastPathComponent)
                                    .font(.system(size: 9))
                                    .foregroundStyle(isSelected ? selectedTextColor.opacity(0.82) : Color.kaiMDSecondaryText)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                    .background(selectionBackground(isSelected))
                    .padding(.horizontal, 5)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-file-\(url.standardizedFilePath)")
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
            }
        }
    }

    private var uniqueOpenFileURLs: [URL] {
        var seen = Set<String>()
        return openFileURLs.filter { seen.insert($0.standardizedFilePath).inserted }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.kaiMDSecondaryText)
                TextField("搜索文件和正文", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.kaiMDSecondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(10)

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(allMarkdownNodes, id: \.id) { node in
                            quickFileRow(node)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            } else if results.isEmpty {
                ContentUnavailableView(
                    "没有结果",
                    systemImage: "magnifyingglass",
                    description: Text("试试更短的关键词")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { result in
                            Button {
                                onOpen(result.fileURL)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Image(systemName: result.kind == .fileName ? "doc.text" : "text.magnifyingglass")
                                        Text(result.relativePath)
                                            .lineLimit(1)
                                        Spacer()
                                        if let line = result.lineNumber {
                                            Text("L\(line)")
                                                .foregroundStyle(Color.kaiMDSecondaryText)
                                        }
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    if result.kind == .content {
                                        Text(result.preview)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.kaiMDSecondaryText)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .background(selectionBackground(
                                    WorkspaceSidebarSelection.matches(
                                        result.fileURL,
                                        selectedFileURL: selectedFileURL
                                    )
                                ))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                WorkspaceSidebarSelection.matches(
                                    result.fileURL,
                                    selectedFileURL: selectedFileURL
                                ) ? .isSelected : AccessibilityTraits()
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
            Text(session.rootURL.path(percentEncoded: false))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.kaiMDSecondaryText)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func fileRow(_ node: WorkspaceFileNode) -> some View {
        let isSelected = WorkspaceSidebarSelection.isSelected(
            node,
            selectedFileURL: selectedFileURL
        )
        return Group {
            if node.isMarkdown {
                Button { onOpen(node.url) } label: { rowLabel(node, isSelected: isSelected) }
                    .buttonStyle(.plain)
            } else {
                rowLabel(node, isSelected: false)
            }
        }
        .accessibilityIdentifier("workspace-file-\(session.relativePath(for: node.url) ?? node.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
        .contextMenu {
            if node.isMarkdown {
                Button("打开") { onOpen(node.url) }
            }
            Button("重命名…") { rename(node) }
            Button("复制") { duplicate(node) }
            Divider()
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Button("复制相对路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.relativePath(for: node.url) ?? node.name, forType: .string)
            }
            Divider()
            Button("移到废纸篓", role: .destructive) { trash(node) }
        }
    }

    private func rowLabel(_ node: WorkspaceFileNode, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: node))
                .foregroundStyle(isSelected ? selectedTextColor : iconColor(for: node))
                .frame(width: 16)
            Text(node.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? selectedTextColor : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .background(selectionBackground(isSelected))
        .padding(.horizontal, 5)
    }

    private func quickFileRow(_ node: WorkspaceFileNode) -> some View {
        let isSelected = WorkspaceSidebarSelection.isSelected(
            node,
            selectedFileURL: selectedFileURL
        )
        return Button { onOpen(node.url) } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.text")
                    .foregroundStyle(isSelected ? selectedTextColor : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Text(session.relativePath(for: node.url) ?? node.name)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? selectedTextColor.opacity(0.85) : Color.kaiMDSecondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? selectedTextColor : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(selectionBackground(isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace-file-\(session.relativePath(for: node.url) ?? node.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }

    private var selectedTextColor: Color {
        Color(nsColor: .selectedControlTextColor)
    }

    private func selectionBackground(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
    }

    private var allMarkdownNodes: [WorkspaceFileNode] {
        func flatten(_ nodes: [WorkspaceFileNode]) -> [WorkspaceFileNode] {
            nodes.flatMap { node in
                node.isMarkdown ? [node] : flatten(node.children)
            }
        }
        return flatten(session.nodes)
    }

    private func iconName(for node: WorkspaceFileNode) -> String {
        switch node.kind {
        case .directory: "folder"
        case .markdown: "doc.text"
        case .image: "photo"
        }
    }

    private func iconColor(for node: WorkspaceFileNode) -> Color {
        switch node.kind {
        case .directory: .accentColor
        case .markdown: .primary
        case .image: .kaiMDSecondaryText
        }
    }

    private func performSearch(_ value: String) {
        searchTask?.cancel()
        results = []
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let matches = await session.search(query: value)
            guard !Task.isCancelled else { return }
            results = matches
            isSearching = false
        }
    }

    private func createMarkdown() {
        guard let name = prompt(title: "新建 Markdown 文件", defaultValue: "Untitled.md") else { return }
        do {
            let url = try session.createMarkdownFile(named: name)
            onOpen(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFolder() {
        guard let name = prompt(title: "新建文件夹", defaultValue: "New Folder") else { return }
        do {
            _ = try session.createFolder(named: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(_ node: WorkspaceFileNode) {
        guard let name = prompt(title: "重命名", defaultValue: node.name) else { return }
        WorkspaceCoordinator.shared.renameItem(at: node.url, to: name, in: session) { error in
            if let error {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func duplicate(_ node: WorkspaceFileNode) {
        do {
            _ = try WorkspaceCoordinator.shared.duplicateItem(at: node.url, in: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trash(_ node: WorkspaceFileNode) {
        let alert = NSAlert()
        alert.messageText = "将“\(node.name)”移到废纸篓？"
        alert.informativeText = node.isDirectory ? "文件夹中的内容也会一并移动。" : "可以从废纸篓恢复。"
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try WorkspaceCoordinator.shared.moveItemToTrash(at: node.url, in: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prompt(title: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func isForCurrentWindow(_ notification: Notification) -> Bool {
        notification.object == nil || notification.object as? NSWindow === window
    }
}
