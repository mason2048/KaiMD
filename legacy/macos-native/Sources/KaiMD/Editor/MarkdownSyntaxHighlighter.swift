import AppKit

@MainActor
final class MarkdownSyntaxHighlighter {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private static let heading = expression(#"(?m)^[\t ]*#{1,6}(?:[\t ]+.*)?$"#)
    private static let listMarker = expression(#"(?m)^[\t ]*(?:[-+*]|[0-9]+[.)])(?=[\t ]+)"#)
    private static let quoteMarker = expression(#"(?m)^[\t ]*>+"#)
    private static let bold = expression(#"(?:\*\*|__)(?=\S)(?:[^\n]*?\S)(?:\*\*|__)"#)
    private static let italic = expression(#"(?<!\*)\*(?!\*)(?=\S)[^*\n]*?\S\*(?!\*)|(?<!_)_(?!_)(?=\S)[^_\n]*?\S_(?!_)"#)
    private static let link = expression(#"!?\[[^\]\n]+\]\([^\)\n]+\)"#)
    private static let inlineCode = expression(#"(?<!`)`{1,2}[^`\n]+`{1,2}(?!`)"#)
    private static let fence = expression(#"^[\t ]*(`{3,}|~{3,})"#)

    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private static let italicFont: NSFont = {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }()
    private static let inlineCodeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

    func highlight(_ textView: NSTextView) {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else {
            return
        }

        let source = textView.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        let documentRange = contentManager.documentRange

        layoutManager.invalidateRenderingAttributes(for: documentRange)
        layoutManager.setRenderingAttributes([:], for: documentRange)

        apply(
            Self.quoteMarker,
            to: source,
            searchRange: fullRange,
            attributes: [.foregroundColor: NSColor.systemGray],
            layoutManager: layoutManager,
            contentManager: contentManager
        )
        apply(
            Self.listMarker,
            to: source,
            searchRange: fullRange,
            attributes: [.foregroundColor: NSColor.systemOrange],
            layoutManager: layoutManager,
            contentManager: contentManager
        )
        apply(
            Self.heading,
            to: source,
            searchRange: fullRange,
            attributes: [
                .foregroundColor: NSColor.systemBlue,
                .font: Self.boldFont,
            ],
            layoutManager: layoutManager,
            contentManager: contentManager
        )
        apply(
            Self.bold,
            to: source,
            searchRange: fullRange,
            attributes: [.font: Self.boldFont],
            layoutManager: layoutManager,
            contentManager: contentManager
        )
        apply(
            Self.italic,
            to: source,
            searchRange: fullRange,
            attributes: [.font: Self.italicFont],
            layoutManager: layoutManager,
            contentManager: contentManager
        )
        apply(
            Self.link,
            to: source,
            searchRange: fullRange,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ],
            layoutManager: layoutManager,
            contentManager: contentManager
        )

        let inlineCodeAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.inlineCodeFont,
            .foregroundColor: NSColor.systemIndigo,
            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.22),
        ]
        apply(
            Self.inlineCode,
            to: source,
            searchRange: fullRange,
            attributes: inlineCodeAttributes,
            layoutManager: layoutManager,
            contentManager: contentManager
        )
        let fencedCodeAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.baseFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.16),
        ]
        for range in fencedCodeRanges(in: source) {
            set(
                fencedCodeAttributes,
                for: range,
                layoutManager: layoutManager,
                contentManager: contentManager
            )
        }
    }

    /// Removes temporary TextKit rendering attributes without mutating the
    /// document's plain-text storage.
    func clear(_ textView: NSTextView) {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else {
            return
        }
        let documentRange = contentManager.documentRange
        layoutManager.invalidateRenderingAttributes(for: documentRange)
        layoutManager.setRenderingAttributes([:], for: documentRange)
    }

    private func apply(
        _ expression: NSRegularExpression?,
        to source: String,
        searchRange: NSRange,
        attributes: [NSAttributedString.Key: Any],
        layoutManager: NSTextLayoutManager,
        contentManager: NSTextContentManager
    ) {
        guard let expression else {
            return
        }

        expression.enumerateMatches(in: source, range: searchRange) { match, _, _ in
            guard let range = match?.range else {
                return
            }
            set(
                attributes,
                for: range,
                layoutManager: layoutManager,
                contentManager: contentManager
            )
        }
    }

    private func set(
        _ attributes: [NSAttributedString.Key: Any],
        for range: NSRange,
        layoutManager: NSTextLayoutManager,
        contentManager: NSTextContentManager
    ) {
        guard range.location != NSNotFound,
              let start = contentManager.location(
                  contentManager.documentRange.location,
                  offsetBy: range.location
              ),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else {
            return
        }

        layoutManager.setRenderingAttributes(attributes, for: textRange)
    }

    private func fencedCodeRanges(in source: String) -> [NSRange] {
        let sourceString = source as NSString
        var ranges: [NSRange] = []
        var activeFence: (character: Character, minimumLength: Int, start: Int)?
        var location = 0

        while location < sourceString.length {
            let lineRange = sourceString.lineRange(for: NSRange(location: location, length: 0))
            let line = sourceString.substring(with: lineRange)
            let lineSearchRange = NSRange(location: 0, length: (line as NSString).length)

            if let match = Self.fence?.firstMatch(in: line, range: lineSearchRange),
               match.numberOfRanges > 1
            {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                if let character = marker.first {
                    if let currentFence = activeFence {
                        if character == currentFence.character,
                           marker.count >= currentFence.minimumLength
                        {
                            ranges.append(NSRange(
                                location: currentFence.start,
                                length: NSMaxRange(lineRange) - currentFence.start
                            ))
                            activeFence = nil
                        }
                    } else {
                        activeFence = (character, marker.count, lineRange.location)
                    }
                }
            }

            let nextLocation = NSMaxRange(lineRange)
            if nextLocation <= location {
                break
            }
            location = nextLocation
        }

        if let activeFence {
            ranges.append(NSRange(
                location: activeFence.start,
                length: sourceString.length - activeFence.start
            ))
        }

        return ranges
    }

    private static func expression(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }
}
