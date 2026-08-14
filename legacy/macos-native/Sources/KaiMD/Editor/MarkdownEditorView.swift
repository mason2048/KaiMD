import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The current editing statistics reported by ``MarkdownEditorView``.
public struct MarkdownEditorMetrics: Equatable, Sendable {
    /// One-based logical line containing the insertion point.
    public let line: Int

    /// One-based character column containing the insertion point.
    public let column: Int

    /// The number of words in the document, using the system word tokenizer.
    public let wordCount: Int

    /// The number of extended grapheme clusters in the document.
    public let characterCount: Int

    public init(line: Int, column: Int, wordCount: Int, characterCount: Int) {
        self.line = line
        self.column = column
        self.wordCount = wordCount
        self.characterCount = characterCount
    }
}

public typealias MarkdownEditorMetricsHandler = (MarkdownEditorMetrics) -> Void
public typealias MarkdownEditorImageHandler = (NSImage) -> String?
public typealias MarkdownEditorImageFileHandler = (URL) -> String?

/// A plain-text Markdown editor backed by TextKit 2.
///
/// Image callbacks import the supplied image into the caller's document model
/// and return the Markdown source that should be inserted at the caret.
public struct MarkdownEditorView: NSViewRepresentable {
    @Binding private var text: String

    private let suppliedUndoManager: UndoManager?
    private let onMetricsChange: MarkdownEditorMetricsHandler
    private let onImage: MarkdownEditorImageHandler
    private let onImageFile: MarkdownEditorImageFileHandler

    public init(
        text: Binding<String>,
        undoManager: UndoManager? = nil,
        onMetricsChange: @escaping MarkdownEditorMetricsHandler = { _ in },
        onImage: @escaping MarkdownEditorImageHandler = { _ in nil },
        onImageFile: @escaping MarkdownEditorImageFileHandler = { _ in nil }
    ) {
        _text = text
        suppliedUndoManager = undoManager
        self.onMetricsChange = onMetricsChange
        self.onImage = onImage
        self.onImageFile = onImageFile
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = MarkdownTextView(usingTextLayoutManager: true)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        configure(textView, coordinator: context.coordinator)
        context.coordinator.textView = textView
        _ = context.coordinator.replaceTextIfNeeded(with: text)
        context.coordinator.schedulePresentationAndMetrics(after: .zero)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? MarkdownTextView else {
            return
        }

        textView.suppliedUndoManager = suppliedUndoManager
        if context.coordinator.replaceTextIfNeeded(with: text) {
            context.coordinator.schedulePresentationAndMetrics(after: .zero)
        }
    }

    private func configure(_ textView: MarkdownTextView, coordinator: Coordinator) {
        let font = MarkdownSyntaxHighlighter.baseFont

        textView.delegate = coordinator
        textView.suppliedUndoManager = suppliedUndoManager
        textView.font = font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.textColor,
        ]

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 4

        textView.imageHandler = { [weak coordinator] image in
            coordinator?.parent.onImage(image)
        }
        textView.imageFileHandler = { [weak coordinator] url in
            coordinator?.parent.onImageFile(url)
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        fileprivate var parent: MarkdownEditorView
        fileprivate weak var textView: MarkdownTextView?

        private let highlighter = MarkdownSyntaxHighlighter()
        private var isSynchronizing = false
        private var lastMetrics: MarkdownEditorMetrics?
        private var presentationTask: Task<Void, Never>?
        private var metricsTask: Task<Void, Never>?
        private var syntaxHighlightingEnabled = true

        /// Whole-document regular-expression highlighting is intentionally
        /// disabled above this size so opening a large note never locks the UI.
        private static let syntaxHighlightingUTF16Limit = 250_000

        fileprivate init(parent: MarkdownEditorView) {
            self.parent = parent
            super.init()

            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(insertBold(_:)),
                name: .kaiMDInsertBold,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(insertItalic(_:)),
                name: .kaiMDInsertItalic,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(insertLink(_:)),
                name: .kaiMDInsertLink,
                object: nil
            )
        }

        deinit {
            presentationTask?.cancel()
            metricsTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        public func textDidChange(_ notification: Notification) {
            guard !isSynchronizing, let textView else {
                return
            }

            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
            }
            schedulePresentationAndMetrics()
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            scheduleMetrics(after: .milliseconds(20))
        }

        @discardableResult
        fileprivate func replaceTextIfNeeded(with newText: String) -> Bool {
            guard let textView, textView.string != newText else {
                return false
            }

            let oldSelection = textView.selectedRange()
            let undoManager = textView.undoManager
            let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled ?? false

            isSynchronizing = true
            if wasUndoRegistrationEnabled {
                undoManager?.disableUndoRegistration()
            }
            textView.string = newText
            if wasUndoRegistrationEnabled {
                undoManager?.enableUndoRegistration()
            }
            isSynchronizing = false

            let location = min(oldSelection.location, (newText as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            return true
        }

        fileprivate func schedulePresentationAndMetrics(
            after delay: Duration = .milliseconds(80)
        ) {
            presentationTask?.cancel()
            presentationTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self, let textView = self.textView else {
                    return
                }

                if (textView.string as NSString).length <= Self.syntaxHighlightingUTF16Limit {
                    self.highlighter.highlight(textView)
                    self.syntaxHighlightingEnabled = true
                } else if self.syntaxHighlightingEnabled {
                    self.highlighter.clear(textView)
                    self.syntaxHighlightingEnabled = false
                }
                textView.typingAttributes = [
                    .font: MarkdownSyntaxHighlighter.baseFont,
                    .foregroundColor: NSColor.textColor,
                ]
                self.scheduleMetrics(after: .zero)
                self.presentationTask = nil
            }
        }

        private func scheduleMetrics(after delay: Duration) {
            metricsTask?.cancel()
            guard let textView else {
                return
            }

            let source = textView.string
            let selectionLocation = textView.selectedRange().location
            metricsTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let metrics = await Task.detached(priority: .utility) {
                    Self.metrics(for: source, selectionLocation: selectionLocation)
                }.value
                guard !Task.isCancelled,
                      let self,
                      let currentTextView = self.textView,
                      currentTextView.string == source,
                      currentTextView.selectedRange().location == selectionLocation,
                      metrics != self.lastMetrics
                else {
                    return
                }

                self.lastMetrics = metrics
                self.parent.onMetricsChange(metrics)
                self.metricsTask = nil
            }
        }

        @objc private func insertBold(_ notification: Notification) {
            guard shouldHandleFormattingCommand(notification) else {
                return
            }
            textView?.wrapSelection(prefix: "**", suffix: "**")
        }

        @objc private func insertItalic(_ notification: Notification) {
            guard shouldHandleFormattingCommand(notification) else {
                return
            }
            textView?.wrapSelection(prefix: "*", suffix: "*")
        }

        @objc private func insertLink(_ notification: Notification) {
            guard shouldHandleFormattingCommand(notification) else {
                return
            }
            textView?.wrapSelection(prefix: "[", suffix: "](url)")
        }

        private func shouldHandleFormattingCommand(_ notification: Notification) -> Bool {
            guard let textView,
                  let editorWindow = textView.window,
                  editorWindow === NSApplication.shared.keyWindow,
                  editorWindow.firstResponder === textView
            else {
                return false
            }

            guard let target = notification.object else {
                return true
            }
            return (target as AnyObject) === editorWindow
        }

        nonisolated private static func metrics(
            for text: String,
            selectionLocation: Int
        ) -> MarkdownEditorMetrics {
            let source = text as NSString
            let clampedLocation = min(max(selectionLocation, 0), source.length)
            let prefix = source.substring(to: clampedLocation)
            let line = prefix.reduce(into: 1) { count, character in
                if character == "\n" {
                    count += 1
                }
            }
            let lastLineBreak = (prefix as NSString).range(of: "\n", options: .backwards).location
            let lineStart = lastLineBreak == NSNotFound ? 0 : lastLineBreak + 1
            let columnText = source.substring(with: NSRange(
                location: lineStart,
                length: clampedLocation - lineStart
            ))

            var wordCount = 0
            text.enumerateSubstrings(
                in: text.startIndex..<text.endIndex,
                options: [.byWords, .substringNotRequired]
            ) { _, _, _, _ in
                wordCount += 1
            }

            return MarkdownEditorMetrics(
                line: line,
                column: columnText.count + 1,
                wordCount: wordCount,
                characterCount: text.count
            )
        }
    }
}

@MainActor
private final class MarkdownTextView: NSTextView {
    weak var suppliedUndoManager: UndoManager?
    var imageHandler: MarkdownEditorImageHandler?
    var imageFileHandler: MarkdownEditorImageFileHandler?

    override var undoManager: UndoManager? {
        suppliedUndoManager ?? super.undoManager
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0,
              let continuation = listContinuation(at: selection.location)
        else {
            super.insertNewline(sender)
            return
        }

        if continuation.shouldEndList {
            insertText("", replacementRange: continuation.markerRange)
            return
        }

        insertText("\n" + continuation.prefix, replacementRange: selection)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let insertedText = insertString as? String,
              insertedText.count == 1,
              let typedCharacter = insertedText.first
        else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let effectiveRange = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange

        let closingPairs: [Character: Character] = [
            "(": ")",
            "[": "]",
            "{": "}",
            "`": "`",
        ]

        if closingPairs.values.contains(typedCharacter),
           effectiveRange.length == 0,
           effectiveRange.location < (string as NSString).length,
           (string as NSString).substring(
               with: NSRange(location: effectiveRange.location, length: 1)
           ) == String(typedCharacter)
        {
            setSelectedRange(NSRange(location: effectiveRange.location + 1, length: 0))
            return
        }

        if let closingCharacter = closingPairs[typedCharacter] {
            let selectedText = (string as NSString).substring(with: effectiveRange)
            let replacement = String(typedCharacter) + selectedText + String(closingCharacter)
            super.insertText(replacement, replacementRange: effectiveRange)

            let newSelection = NSRange(
                location: effectiveRange.location + 1,
                length: effectiveRange.length
            )
            setSelectedRange(newSelection)
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        if importImages(from: .general) {
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if containsImportableImage(in: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if containsImportableImage(in: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let insertionLocation = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: insertionLocation, length: 0))

        if importImages(from: sender.draggingPasteboard) {
            return true
        }
        return super.performDragOperation(sender)
    }

    func wrapSelection(prefix: String, suffix: String) {
        let selection = selectedRange()
        let selectedText = (string as NSString).substring(with: selection)
        let replacement = prefix + selectedText + suffix

        insertText(replacement, replacementRange: selection)
        setSelectedRange(NSRange(
            location: selection.location + (prefix as NSString).length,
            length: (selectedText as NSString).length
        ))
        window?.makeFirstResponder(self)
    }

    private func listContinuation(at insertionLocation: Int) -> ListContinuation? {
        let source = string as NSString
        guard insertionLocation <= source.length else {
            return nil
        }

        let lineRange = source.lineRange(for: NSRange(location: insertionLocation, length: 0))
        let prefixLength = insertionLocation - lineRange.location
        guard prefixLength >= 0 else {
            return nil
        }

        let textBeforeCaret = source.substring(with: NSRange(
            location: lineRange.location,
            length: prefixLength
        ))
        let pattern = #"^([\t ]*)([-+*]|([0-9]+)([.)]))([\t ]+)(.*)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: textBeforeCaret,
                  range: NSRange(location: 0, length: (textBeforeCaret as NSString).length)
              )
        else {
            return nil
        }

        let indentation = (textBeforeCaret as NSString).substring(with: match.range(at: 1))
        let marker = (textBeforeCaret as NSString).substring(with: match.range(at: 2))
        let spacing = (textBeforeCaret as NSString).substring(with: match.range(at: 5))
        let content = (textBeforeCaret as NSString).substring(with: match.range(at: 6))
        let markerEnd = match.range(at: 5).location + match.range(at: 5).length
        let markerRange = NSRange(location: lineRange.location, length: markerEnd)

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ListContinuation(prefix: "", markerRange: markerRange, shouldEndList: true)
        }

        var nextMarker = marker
        let numberRange = match.range(at: 3)
        if numberRange.location != NSNotFound,
           let number = Int((textBeforeCaret as NSString).substring(with: numberRange))
        {
            let punctuation = (textBeforeCaret as NSString).substring(with: match.range(at: 4))
            let (incremented, overflowed) = number.addingReportingOverflow(1)
            if !overflowed {
                nextMarker = "\(incremented)\(punctuation)"
            }
        }

        return ListContinuation(
            prefix: indentation + nextMarker + spacing,
            markerRange: markerRange,
            shouldEndList: false
        )
    }

    private func containsImportableImage(in pasteboard: NSPasteboard) -> Bool {
        !imageFileURLs(from: pasteboard).isEmpty || NSImage(pasteboard: pasteboard) != nil
    }

    /// Returns true whenever the pasteboard contains an image, even when the
    /// importer declines it. This keeps the plain-text editor from creating an
    /// NSTextAttachment as a fallback.
    private func importImages(from pasteboard: NSPasteboard) -> Bool {
        let imageURLs = imageFileURLs(from: pasteboard)
        if !imageURLs.isEmpty {
            let snippets = imageURLs.compactMap { imageFileHandler?($0) }
            if !snippets.isEmpty {
                insertText(snippets.joined(separator: "\n"), replacementRange: selectedRange())
            }
            return true
        }

        if let image = NSImage(pasteboard: pasteboard) {
            if let markdown = imageHandler?(image) {
                insertText(markdown, replacementRange: selectedRange())
            }
            return true
        }

        return false
    }

    private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL] ?? []

        return objects.compactMap { object in
            let url = object as URL
            guard url.isFileURL,
                  let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image)
            else {
                return nil
            }
            return url
        }
    }
}

private struct ListContinuation {
    let prefix: String
    let markerRange: NSRange
    let shouldEndList: Bool
}
