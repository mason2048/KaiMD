import AppKit
import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    typealias NSViewType = WKWebView

    let rendered: RenderedMarkdown
    let documentURL: URL?
    let workspaceRoot: URL?
    var onOpenDocument: ((URL) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    init(
        rendered: RenderedMarkdown,
        documentURL: URL? = nil,
        workspaceRoot: URL? = nil,
        onOpenDocument: ((URL) -> Void)? = nil,
        onOpenExternalLink: ((URL) -> Void)? = nil
    ) {
        self.rendered = rendered
        self.documentURL = documentURL
        self.workspaceRoot = workspaceRoot
        self.onOpenDocument = onOpenDocument
        self.onOpenExternalLink = onOpenExternalLink
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            documentURL: documentURL,
            workspaceRoot: workspaceRoot,
            onOpenDocument: onOpenDocument,
            onOpenExternalLink: onOpenExternalLink
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(
            context.coordinator.assetSchemeHandler,
            forURLScheme: PreviewURLRouter.assetScheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .clear
        webView.isInspectable = false
        webView.setAccessibilityLabel("Markdown Preview")
        context.coordinator.load(rendered: rendered, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            documentURL: documentURL,
            workspaceRoot: workspaceRoot,
            onOpenDocument: onOpenDocument,
            onOpenExternalLink: onOpenExternalLink
        )
        context.coordinator.load(rendered: rendered, into: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let assetSchemeHandler: WorkspaceAssetSchemeHandler

        private var router: PreviewURLRouter
        private var onOpenDocument: ((URL) -> Void)?
        private var onOpenExternalLink: ((URL) -> Void)?
        private var lastLoadedHTML: String?
        private var contextIdentifier: String

        init(
            documentURL: URL?,
            workspaceRoot: URL?,
            onOpenDocument: ((URL) -> Void)?,
            onOpenExternalLink: ((URL) -> Void)?
        ) {
            router = PreviewURLRouter(documentURL: documentURL, workspaceRoot: workspaceRoot)
            assetSchemeHandler = WorkspaceAssetSchemeHandler(
                workspaceRoot: workspaceRoot ?? documentURL?.deletingLastPathComponent()
            )
            self.onOpenDocument = onOpenDocument
            self.onOpenExternalLink = onOpenExternalLink
            contextIdentifier = Self.identifier(
                documentURL: documentURL,
                workspaceRoot: workspaceRoot
            )
            super.init()
        }

        func update(
            documentURL: URL?,
            workspaceRoot: URL?,
            onOpenDocument: ((URL) -> Void)?,
            onOpenExternalLink: ((URL) -> Void)?
        ) {
            let newIdentifier = Self.identifier(
                documentURL: documentURL,
                workspaceRoot: workspaceRoot
            )
            if newIdentifier != contextIdentifier {
                contextIdentifier = newIdentifier
                lastLoadedHTML = nil
            }
            router = PreviewURLRouter(documentURL: documentURL, workspaceRoot: workspaceRoot)
            assetSchemeHandler.workspaceRoot = workspaceRoot ?? documentURL?.deletingLastPathComponent()
            self.onOpenDocument = onOpenDocument
            self.onOpenExternalLink = onOpenExternalLink
        }

        func load(rendered: RenderedMarkdown, into webView: WKWebView) {
            guard lastLoadedHTML != rendered.html else { return }
            lastLoadedHTML = rendered.html
            webView.loadHTMLString(rendered.html, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                let scheme = navigationAction.request.url?.scheme?.lowercased()
                decisionHandler(scheme == nil || scheme == "about" ? .allow : .cancel)
                return
            }

            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme?.lowercased() == "about", url.fragment != nil {
                decisionHandler(.allow)
                return
            }

            if PreviewURLRouter.isExternalURL(url) {
                if let onOpenExternalLink {
                    onOpenExternalLink(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            if let fileURL = router.documentFileURL(for: url) {
                if let onOpenDocument {
                    onOpenDocument(fileURL)
                } else {
                    NSWorkspace.shared.open(fileURL)
                }
            }
            decisionHandler(.cancel)
        }

        private static func identifier(documentURL: URL?, workspaceRoot: URL?) -> String {
            let document = documentURL?.standardizedFileURL.path ?? ""
            let workspace = workspaceRoot?.standardizedFileURL.path ?? ""
            return workspace + "\u{0}" + document
        }
    }
}

typealias MarkdownPreviewView = MarkdownPreview
