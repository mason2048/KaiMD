import Foundation
import Testing
@testable import KaiMD

@Suite("Safe Markdown rendering")
struct MarkdownRenderTests {
    @Test("renders GFM structures")
    func rendersGFM() async {
        let source = """
        # Title

        - [x] shipped
        - [ ] pending

        | Name | Value |
        | --- | ---: |
        | one | 1 |

        ~~removed~~ and `code`
        """

        let rendered = await MarkdownRenderService(stylesheet: "body{}").render(source)
        #expect(rendered.bodyHTML.contains("<h1"))
        #expect(rendered.bodyHTML.contains("<table>"))
        #expect(rendered.bodyHTML.contains("type=\"checkbox\""))
        #expect(rendered.bodyHTML.contains("<del>removed</del>"))
        #expect(rendered.bodyHTML.contains("<code>code</code>"))
        #expect(rendered.html.contains("script-src 'none'"))
    }

    @Test("escapes raw HTML and rejects dangerous links")
    func blocksRawHTMLAndJavaScript() async {
        let source = """
        <script>alert('x')</script>

        [bad](javascript:alert(1))
        [good](https://example.com/path)
        """
        let rendered = await MarkdownRenderService(stylesheet: "").render(source)

        #expect(!rendered.bodyHTML.contains("<script>"))
        #expect(rendered.bodyHTML.contains("&lt;script&gt;"))
        #expect(!rendered.bodyHTML.contains("javascript:"))
        #expect(rendered.bodyHTML.contains("https://example.com/path"))
    }

    @Test("code blocks expose a safe language label and scrolling styles")
    func rendersPracticalCodeBlocks() async {
        let source = """
        ```Swift<script>
        let message = "<unsafe>" + String(repeating: "long", count: 40)
        ```
        """
        let rendered = await MarkdownRenderService().render(source)

        #expect(rendered.bodyHTML.contains("<pre class=\"code-block\" data-language=\"swiftscript\">"))
        #expect(rendered.bodyHTML.contains("class=\"language-swiftscript\""))
        #expect(rendered.bodyHTML.contains("&lt;unsafe&gt;"))
        #expect(!rendered.bodyHTML.contains("<script>"))
        #expect(rendered.html.contains("overflow-x: auto"))
        #expect(rendered.html.contains("min-width: max-content"))
        #expect(rendered.html.contains("content: attr(data-language)"))
    }

    @Test("routes local images inside workspace only")
    func routesLocalImagesSafely() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let document = docs.appendingPathComponent("guide.md")
        try Data().write(to: document)

        let router = PreviewURLRouter(documentURL: document, workspaceRoot: root)
        #expect(router.imageURLString(for: "../assets/image.png") == "kaimd-asset://asset/assets/image.png")
        #expect(router.imageURLString(for: "../../outside.png") == nil)
        #expect(router.imageURLString(for: "file:///etc/passwd") == nil)
        #expect(router.imageURLString(for: "https://example.com/image.png") == "https://example.com/image.png")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaiMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
