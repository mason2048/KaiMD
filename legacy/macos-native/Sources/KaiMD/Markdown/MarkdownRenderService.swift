import Foundation
import Markdown

struct RenderedMarkdown: Sendable, Equatable {
    let html: String
    let bodyHTML: String
    let sourceCharacterCount: Int
}

/// Serializes render requests away from the main actor. Parsing itself runs in a detached task,
/// so a large document cannot occupy the UI executor.
actor MarkdownRenderService {
    static let shared = MarkdownRenderService()

    private let stylesheet: String

    init(stylesheet: String? = nil) {
        self.stylesheet = stylesheet ?? Self.bundledStylesheet()
    }

    func render(
        _ markdown: String,
        documentURL: URL? = nil,
        workspaceRoot: URL? = nil
    ) async -> RenderedMarkdown {
        // Actor isolation intentionally serializes full parses. A superseded
        // request can finish, but rapid edits cannot accumulate many detached
        // cmark/HTML workers and exhaust CPU or memory.
        guard !Task.isCancelled else {
            return RenderedMarkdown(html: "", bodyHTML: "", sourceCharacterCount: markdown.count)
        }
        let document = Document(parsing: markdown)
        guard !Task.isCancelled else {
            return RenderedMarkdown(html: "", bodyHTML: "", sourceCharacterCount: markdown.count)
        }
        let body = SafeMarkdownHTMLRenderer.render(
            document,
            documentURL: documentURL,
            workspaceRoot: workspaceRoot
        )
        let title = documentURL?.lastPathComponent ?? "Markdown Preview"
        let page = Self.makePage(title: title, body: body, stylesheet: stylesheet)
        return RenderedMarkdown(
            html: page,
            bodyHTML: body,
            sourceCharacterCount: markdown.count
        )
    }

    private nonisolated static func makePage(
        title: String,
        body: String,
        stylesheet: String
    ) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none'; object-src 'none'; script-src 'none'; connect-src 'none'; media-src 'none'; font-src 'none'; img-src https: kaimd-asset:; style-src 'unsafe-inline'">
        <meta name="referrer" content="no-referrer">
        <title>\(HTMLEscaping.text(title))</title>
        <style>\(stylesheet)</style>
        </head>
        <body>
        <article class="markdown-body">\(body)</article>
        </body>
        </html>
        """
    }

    private nonisolated static func bundledStylesheet() -> String {
        let packagedResourceBundle: Bundle? = {
            guard let resources = Bundle.main.resourceURL else { return nil }
            return Bundle(url: resources.appendingPathComponent("KaiMD_KaiMD.bundle", isDirectory: true))
        }()
        let url = packagedResourceBundle?.url(forResource: "preview", withExtension: "css")
            ?? Bundle.module.url(forResource: "preview", withExtension: "css")
        guard let url,
              let data = try? Data(contentsOf: url),
              let stylesheet = String(data: data, encoding: .utf8)
        else {
            return "body{font:16px -apple-system,sans-serif;color:#1d1d1f;background:#fff}"
        }
        return stylesheet
    }
}
