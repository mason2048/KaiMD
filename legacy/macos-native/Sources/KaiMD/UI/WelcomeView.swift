import AppKit
import SwiftUI

struct WelcomeView: View {
    let recentWorkspaces: [URL]
    let onOpen: () -> Void
    let onOpenRecent: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 46)

            VStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)

                Text("KaiMD")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text("打开文件夹，专注写作。")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kaiMDSecondaryText)

                Button("打开 Markdown 或文件夹", action: onOpen)
                    .buttonStyle(KaiMDButtonStyle(prominent: true))
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityHint("选择一个 Markdown 文件或包含 Markdown 的文件夹")
            }

            if !recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近打开")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.kaiMDSecondaryText)
                        .padding(.horizontal, 10)

                    ForEach(recentWorkspaces.prefix(5), id: \.standardizedFilePath) { url in
                        Button {
                            onOpenRecent(url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .foregroundStyle(Color.primary)
                                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.kaiMDSecondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.kaiMDSecondaryText)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 420)
                .padding(.top, 34)
            }

            Spacer(minLength: 44)

            Text("本地优先 · CommonMark / GFM · macOS 原生")
                .font(.system(size: 11))
                .foregroundStyle(Color.kaiMDSecondaryText)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 620, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
