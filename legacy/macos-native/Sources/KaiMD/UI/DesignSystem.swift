import SwiftUI

enum KaiMDDesign {
    static let sidebarWidth: CGFloat = 236
    static let cornerRadius: CGFloat = 10
    static let statusBarHeight: CGFloat = 24
    static let editorInset: CGFloat = 24
}

extension Color {
    static let kaiMDSidebar = Color(nsColor: .windowBackgroundColor).opacity(0.72)
    static let kaiMDSecondaryText = Color(nsColor: .secondaryLabelColor)
    static let kaiMDSeparator = Color(nsColor: .separatorColor)
}

struct KaiMDButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.kaiMDSeparator.opacity(0.7), lineWidth: 0.5)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct InlineNotice: View {
    enum Kind {
        case info
        case warning
        case error

        var color: Color {
            switch self {
            case .info: .accentColor
            case .warning: .orange
            case .error: .red
            }
        }

        var icon: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }
    }

    let kind: Kind
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(kind.color.opacity(0.09))
        .accessibilityElement(children: .combine)
    }
}
