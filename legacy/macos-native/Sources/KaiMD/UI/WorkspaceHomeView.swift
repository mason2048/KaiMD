import SwiftUI

struct WorkspaceHomeView: View {
    @ObservedObject var session: WorkspaceSession
    let onOpen: (URL) -> Void

    @State private var sidebarMode: SidebarMode = .files
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var window: NSWindow?

    init(session: WorkspaceSession, onOpen: @escaping (URL) -> Void) {
        self.session = session
        self.onOpen = onOpen
        let sidebarVisible = UserDefaults.standard.object(forKey: "KaiMD.sidebarVisible") as? Bool ?? true
        _columnVisibility = State(initialValue: sidebarVisible ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebarView(
                session: session,
                mode: $sidebarMode,
                selectedFileURL: nil,
                onOpen: onOpen
            )
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("显示或隐藏侧栏")
                    Text(session.rootURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                Divider()

                ContentUnavailableView {
                    Label("选择一个 Markdown 文件", systemImage: "doc.text")
                } description: {
                    Text("从左侧文件树选择，或新建文档开始写作。")
                } actions: {
                    Button("新建 Markdown 文件") {
                        WorkspaceCoordinator.shared.createMarkdownFileFromKeyWindow()
                    }
                    .buttonStyle(KaiMDButtonStyle(prominent: true))
                }
            }
        }
        .background(WindowAccessor { window = $0 })
        .onReceive(NotificationCenter.default.publisher(for: .kaiMDToggleSidebar)) { note in
            guard note.object == nil || note.object as? NSWindow === window else { return }
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, value in
            UserDefaults.standard.set(value != .detailOnly, forKey: "KaiMD.sidebarVisible")
        }
    }
}
