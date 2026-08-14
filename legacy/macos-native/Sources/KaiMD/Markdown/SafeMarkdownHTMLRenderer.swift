import Foundation
import Markdown

/// A deliberately small HTML renderer. It never forwards raw HTML or arbitrary attributes.
struct SafeMarkdownHTMLRenderer: MarkupWalker {
    private(set) var result = ""

    private let urlRouter: PreviewURLRouter
    private var headingIdentifierCounts: [String: Int] = [:]
    private var tableColumnAlignments: [Table.ColumnAlignment?] = []
    private var tableColumnIndex = 0
    private var isInTableHead = false

    init(documentURL: URL?, workspaceRoot: URL?) {
        urlRouter = PreviewURLRouter(documentURL: documentURL, workspaceRoot: workspaceRoot)
    }

    static func render(
        _ document: Document,
        documentURL: URL?,
        workspaceRoot: URL?
    ) -> String {
        var renderer = Self(documentURL: documentURL, workspaceRoot: workspaceRoot)
        renderer.visit(document)
        return renderer.result
    }

    mutating func visitDocument(_ document: Document) {
        descendInto(document)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>\n"
        descendInto(blockQuote)
        result += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let preAttributes: String
        let codeAttributes: String
        if let language = codeBlock.language,
           let token = HTMLEscaping.cssClassToken(language)
        {
            let escapedToken = HTMLEscaping.attribute(token)
            preAttributes = " class=\"code-block\" data-language=\"\(escapedToken)\""
            codeAttributes = " class=\"language-\(escapedToken)\""
        } else {
            preAttributes = " class=\"code-block\""
            codeAttributes = ""
        }

        result += "<pre\(preAttributes)><code\(codeAttributes)>"
        result += HTMLEscaping.text(codeBlock.code)
        result += "</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        let level = min(max(heading.level, 1), 6)
        let identifier = uniqueHeadingIdentifier(for: heading.plainText)
        result += "<h\(level) id=\"\(HTMLEscaping.attribute(identifier))\">"
        descendInto(heading)
        result += "</h\(level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += "<pre class=\"raw-html\"><code>"
        result += HTMLEscaping.text(html.rawHTML)
        result += "</code></pre>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        let taskClass = listItem.checkbox == nil ? "" : " class=\"task-list-item\""
        result += "<li\(taskClass)>"

        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            result += "<input class=\"task-checkbox\" type=\"checkbox\" disabled\(checked) aria-label=\"Task item\">"
        }

        descendInto(listItem)
        result += "</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        let taskClass = listContainsTasks(orderedList) ? " class=\"task-list\"" : ""
        result += "<ol\(start)\(taskClass)>\n"
        descendInto(orderedList)
        result += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let taskClass = listContainsTasks(unorderedList) ? " class=\"task-list\"" : ""
        result += "<ul\(taskClass)>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitTable(_ table: Table) {
        let oldAlignments = tableColumnAlignments
        tableColumnAlignments = table.columnAlignments
        result += "<div class=\"table-scroll\"><table>\n"
        descendInto(table)
        result += "</table></div>\n"
        tableColumnAlignments = oldAlignments
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        result += "<thead><tr>\n"
        isInTableHead = true
        tableColumnIndex = 0
        descendInto(tableHead)
        isInTableHead = false
        result += "</tr></thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard !tableBody.isEmpty else { return }
        result += "<tbody>\n"
        descendInto(tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        tableColumnIndex = 0
        result += "<tr>\n"
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return }

        let tag = isInTableHead ? "th" : "td"
        var attributes = ""

        if tableColumnIndex < tableColumnAlignments.count,
           let alignment = tableColumnAlignments[tableColumnIndex]
        {
            let name: String
            switch alignment {
            case .left: name = "left"
            case .center: name = "center"
            case .right: name = "right"
            }
            attributes += " class=\"align-\(name)\""
        }
        tableColumnIndex += 1

        if tableCell.colspan > 1 {
            attributes += " colspan=\"\(tableCell.colspan)\""
        }
        if tableCell.rowspan > 1 {
            attributes += " rowspan=\"\(tableCell.rowspan)\""
        }

        result += "<\(tag)\(attributes)>"
        descendInto(tableCell)
        result += "</\(tag)>\n"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(HTMLEscaping.text(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        renderInline(tag: "em", content: emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        renderInline(tag: "strong", content: strong)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        renderInline(tag: "del", content: strikethrough)
    }

    mutating func visitImage(_ image: Image) {
        let altText = image.children.compactMap { child in
            (child as? InlineMarkup)?.plainText
        }.joined()

        guard let source = urlRouter.imageURLString(for: image.source) else {
            result += "<span class=\"unavailable-image\">\(HTMLEscaping.text(altText))</span>"
            return
        }

        result += "<img src=\"\(HTMLEscaping.attribute(source))\""
        result += " alt=\"\(HTMLEscaping.attribute(altText))\""
        if let title = image.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.attribute(title))\""
        }
        result += ">"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += "<code class=\"raw-html-inline\">"
        result += HTMLEscaping.text(inlineHTML.rawHTML)
        result += "</code>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    mutating func visitLink(_ link: Link) {
        guard let destination = urlRouter.linkURLString(for: link.destination) else {
            descendInto(link)
            return
        }

        result += "<a href=\"\(HTMLEscaping.attribute(destination))\""
        if let title = link.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.attribute(title))\""
        }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitText(_ text: Text) {
        result += HTMLEscaping.text(text.string)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        guard let destination = symbolLink.destination else { return }
        result += "<code>\(HTMLEscaping.text(destination))</code>"
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) {
        // Arbitrary inline attributes are intentionally discarded.
        descendInto(attributes)
    }

    private mutating func renderInline(tag: String, content: Markup) {
        result += "<\(tag)>"
        descendInto(content)
        result += "</\(tag)>"
    }

    private func listContainsTasks(_ list: Markup) -> Bool {
        list.children.contains { child in
            (child as? ListItem)?.checkbox != nil
        }
    }

    private mutating func uniqueHeadingIdentifier(for plainText: String) -> String {
        var slug = ""
        var pendingSeparator = false

        for scalar in plainText.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar)
                        || scalar == "-"
                        || scalar == "_"
            {
                pendingSeparator = true
            }
        }

        if slug.isEmpty { slug = "section" }
        let count = headingIdentifierCounts[slug, default: 0]
        headingIdentifierCounts[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count + 1)"
    }
}
