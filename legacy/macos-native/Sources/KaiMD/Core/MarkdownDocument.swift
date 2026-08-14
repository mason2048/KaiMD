import AppKit
import Combine
import Foundation

enum MarkdownDocumentError: LocalizedError, Equatable {
    case invalidUTF8
    case mixedNewlinesRequireResolution
    case unsavedDocument
    case backingFileDeleted

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "KaiMD 只支持 UTF-8 编码的 Markdown 文件。"
        case .mixedNewlinesRequireResolution:
            "文件同时包含 LF、CRLF 或旧式 CR 换行符，请先选择 LF 或 CRLF 再保存。"
        case .unsavedDocument:
            "请先保存 Markdown 文件。"
        case .backingFileDeleted:
            "文件已在磁盘删除，可重新保存或另存为。"
        }
    }
}

/// A UTF-8 Markdown document backed by AppKit's document infrastructure.
///
/// Text is kept internally with `\n` line endings. The original UTF-8 BOM and
/// newline style are restored when the document is written. Mixed newline input
/// is deliberately not written until the caller explicitly chooses LF or CRLF.
final class MarkdownDocument: NSDocument, ObservableObject {
    nonisolated override class var autosavesInPlace: Bool { true }

    override var fileURL: URL? {
        didSet {
            let changedURL = fileURL
            guard changedURL?.standardizedFilePath != oldValue?.standardizedFilePath else {
                return
            }
            Task { @MainActor [weak self, changedURL] in
                guard let self,
                      self.fileURL?.standardizedFilePath == changedURL?.standardizedFilePath
                else {
                    return
                }
                self.objectWillChange.send()
                guard let newURL = changedURL else { return }
                if let workspace = self.workspace, newURL.isContained(in: workspace.rootURL) {
                    workspace.scheduleRefresh()
                } else {
                    let nextWorkspace = WorkspaceRegistry.shared.session(for: newURL.deletingLastPathComponent())
                    WorkspaceCoordinator.shared.rebind(document: self, to: nextWorkspace)
                }
            }
        }
    }

    // NSDocument imports synchronous read/write overrides as `nonisolated`.
    // A small lock-protected value store keeps those callbacks race-free while
    // UI-facing changes are still announced on the main actor.
    nonisolated private let state = LockedMarkdownDocumentState()

    nonisolated var text: String { state.text }
    nonisolated var newlineStyle: NewlineStyle { state.newlineStyle }
    nonisolated var hasUTF8BOM: Bool { state.hasUTF8BOM }
    nonisolated var hasTrailingNewline: Bool { state.hasTrailingNewline }
    nonisolated var lastSaveError: Error? { state.lastSaveError }
    @Published var workspace: WorkspaceSession?

    @MainActor private var autosaveTask: Task<Void, Never>?

    override init() {
        super.init()
    }

    @MainActor
    override func makeWindowControllers() {
        guard windowControllers.isEmpty else { return }
        let session = workspace
            ?? WorkspaceRegistry.shared.session(
                for: fileURL?.deletingLastPathComponent()
                    ?? FileManager.default.homeDirectoryForCurrentUser
            )
        workspace = session
        WorkspaceCoordinator.shared.present(document: self, in: session)
    }

    @MainActor
    convenience init(workspace: WorkspaceSession?) {
        self.init()
        self.workspace = workspace
    }

    var requiresNewlineNormalization: Bool {
        newlineStyle == .mixed
    }

    /// Applies an edit and participates in NSDocument undo by default. The
    /// NSTextView binding passes `undoHandledByEditor: true`, because TextKit
    /// has already registered its incremental undo operation on the same
    /// manager; registering a second full-document undo would duplicate it.
    @MainActor
    func applyEditedText(_ editedText: String, undoHandledByEditor: Bool = false) {
        replaceText(
            Self.normalizeLineEndings(in: editedText),
            registerUndo: !undoHandledByEditor,
            markChangedWhenUndoIsUnavailable: !undoHandledByEditor
        )
    }

    /// Replaces the complete source outside NSTextView while preserving normal
    /// NSDocument undo and dirty-state semantics.
    @MainActor
    func replaceEntireText(_ replacement: String) {
        applyEditedText(replacement, undoHandledByEditor: false)
    }

    @MainActor
    func setUTF8BOMEnabled(_ enabled: Bool) {
        guard hasUTF8BOM != enabled else { return }
        let previous = hasUTF8BOM
        let undoManager = undoManager
        let undoTracksChange = undoManager?.isUndoRegistrationEnabled == true
        undoManager?.registerUndo(withTarget: self) { document in
            document.setUTF8BOMEnabled(previous)
        }
        objectWillChange.send()
        state.update { $0.hasUTF8BOM = enabled }
        if !undoTracksChange { updateChangeCount(.changeDone) }
        scheduleDebouncedAutosave()
    }

    /// Resolves a mixed-newline file without changing its visible text.
    @MainActor
    func resolveMixedNewlines(using style: NewlineStyle) {
        guard style != .mixed, newlineStyle != style else { return }
        let previous = newlineStyle
        let undoManager = undoManager
        let undoTracksChange = undoManager?.isUndoRegistrationEnabled == true
        undoManager?.registerUndo(withTarget: self) { document in
            document.setNewlineStyleForUndo(previous)
        }
        objectWillChange.send()
        state.update {
            $0.newlineStyle = style
            $0.lastSaveError = nil
        }
        if !undoTracksChange { updateChangeCount(.changeDone) }
        scheduleDebouncedAutosave()
    }

    @MainActor
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        save(nil)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try Self.decode(data)
        state.update {
            $0.text = decoded.text
            $0.newlineStyle = decoded.newlineStyle
            $0.hasUTF8BOM = decoded.hasBOM
            $0.hasTrailingNewline = decoded.hasTrailingNewline
            $0.lastSaveError = nil
            $0.isBackingFileMissing = false
        }
        Task { @MainActor [weak self] in
            self?.objectWillChange.send()
            self?.undoManager?.removeAllActions()
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let snapshot = state.serializationSnapshot()
        guard snapshot.newlineStyle != .mixed else {
            throw MarkdownDocumentError.mixedNewlinesRequireResolution
        }

        var serialized = snapshot.text
        if snapshot.newlineStyle == .carriageReturnLineFeed {
            serialized = serialized.replacingOccurrences(of: "\n", with: "\r\n")
        }

        guard var result = serialized.data(using: .utf8) else {
            throw MarkdownDocumentError.invalidUTF8
        }
        if snapshot.hasUTF8BOM {
            result.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: result.startIndex)
        }
        return result
    }

    override func write(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        originalContentsURL absoluteOriginalContentsURL: URL?
    ) throws {
        do {
            try super.write(
                to: url,
                ofType: typeName,
                for: saveOperation,
                originalContentsURL: absoluteOriginalContentsURL
            )
            state.update {
                $0.lastSaveError = nil
                $0.isBackingFileMissing = false
            }
            publishStateChange()
        } catch {
            state.update { $0.lastSaveError = error }
            publishStateChange()
            throw error
        }
    }

    /// Keeps the in-memory buffer alive when Finder or another process removes
    /// the backing file. NSDocument's default implementation may close the
    /// document; KaiMD instead marks it dirty so closing still requires an
    /// explicit user decision and saving can recreate the file.
    override nonisolated func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        let shouldMarkChanged = state.markBackingFileDeleted()
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(nil)
                return
            }
            self.autosaveTask?.cancel()
            self.autosaveTask = nil
            self.objectWillChange.send()
            if shouldMarkChanged {
                self.updateChangeCount(.changeDone)
            }
            self.workspace?.scheduleRefresh(after: .zero)
            completionHandler(nil)
        }
    }

    @MainActor
    private func replaceText(
        _ newText: String,
        registerUndo: Bool,
        markChangedWhenUndoIsUnavailable: Bool
    ) {
        guard text != newText else { return }
        let previous = text
        let undoManager = undoManager
        let undoTracksChange = registerUndo && undoManager?.isUndoRegistrationEnabled == true

        if registerUndo {
            undoManager?.registerUndo(withTarget: self) { document in
                document.replaceText(
                    previous,
                    registerUndo: true,
                    markChangedWhenUndoIsUnavailable: true
                )
            }
        }

        objectWillChange.send()
        state.update {
            $0.text = newText
            $0.hasTrailingNewline = newText.hasSuffix("\n")
        }

        if markChangedWhenUndoIsUnavailable, !undoTracksChange {
            updateChangeCount(.changeDone)
        }
        scheduleDebouncedAutosave()
    }

    @MainActor
    private func setNewlineStyleForUndo(_ style: NewlineStyle) {
        let previous = newlineStyle
        let undoManager = undoManager
        let undoTracksChange = undoManager?.isUndoRegistrationEnabled == true
        undoManager?.registerUndo(withTarget: self) { document in
            document.setNewlineStyleForUndo(previous)
        }
        objectWillChange.send()
        state.update { $0.newlineStyle = style }
        if !undoTracksChange { updateChangeCount(.changeDone) }
        scheduleDebouncedAutosave()
    }

    @MainActor
    private func scheduleDebouncedAutosave() {
        guard fileURL != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            guard self.newlineStyle != .mixed else {
                self.setLastSaveError(MarkdownDocumentError.mixedNewlinesRequireResolution)
                return
            }
            self.autosave(withImplicitCancellability: true) { [weak self] error in
                self?.setLastSaveError(error)
            }
        }
    }

    @MainActor
    private func setLastSaveError(_ error: Error?) {
        objectWillChange.send()
        state.update {
            if let error {
                $0.lastSaveError = error
            } else if $0.isBackingFileMissing {
                $0.lastSaveError = MarkdownDocumentError.backingFileDeleted
            } else {
                $0.lastSaveError = nil
            }
        }
    }

    nonisolated private func publishStateChange() {
        Task { @MainActor [weak self] in
            self?.objectWillChange.send()
        }
    }

    nonisolated private static func normalizeLineEndings(in value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    nonisolated private static func decode(_ data: Data) throws -> DecodedDocument {
        let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
        let payload = bom ? data.dropFirst(3) : data[...]
        guard let source = String(data: payload, encoding: .utf8) else {
            throw MarkdownDocumentError.invalidUTF8
        }

        return DecodedDocument(
            text: normalizeLineEndings(in: source),
            newlineStyle: detectNewlineStyle(in: payload),
            hasBOM: bom,
            hasTrailingNewline: payload.last == 0x0A || payload.last == 0x0D
        )
    }

    nonisolated private static func detectNewlineStyle(in bytes: Data.SubSequence) -> NewlineStyle {
        var lfCount = 0
        var crlfCount = 0
        var loneCRCount = 0
        var index = bytes.startIndex

        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 0x0D {
                let next = bytes.index(after: index)
                if next < bytes.endIndex, bytes[next] == 0x0A {
                    crlfCount += 1
                    index = bytes.index(after: next)
                    continue
                }
                loneCRCount += 1
            } else if byte == 0x0A {
                lfCount += 1
            }
            index = bytes.index(after: index)
        }

        if loneCRCount > 0 || (lfCount > 0 && crlfCount > 0) {
            return .mixed
        }
        if crlfCount > 0 {
            return .carriageReturnLineFeed
        }
        return .lineFeed
    }
}

private final class LockedMarkdownDocumentState: @unchecked Sendable {
    struct Values {
        var text = ""
        var newlineStyle: NewlineStyle = .lineFeed
        var hasUTF8BOM = false
        var hasTrailingNewline = false
        var lastSaveError: Error?
        var isBackingFileMissing = false
    }

    private let lock = NSLock()
    private var values = Values()

    var text: String { read(\.text) }
    var newlineStyle: NewlineStyle { read(\.newlineStyle) }
    var hasUTF8BOM: Bool { read(\.hasUTF8BOM) }
    var hasTrailingNewline: Bool { read(\.hasTrailingNewline) }
    var lastSaveError: Error? { read(\.lastSaveError) }

    func markBackingFileDeleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let shouldMarkChanged = !values.isBackingFileMissing
        values.isBackingFileMissing = true
        values.lastSaveError = MarkdownDocumentError.backingFileDeleted
        return shouldMarkChanged
    }

    func update(_ body: (inout Values) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&values)
    }

    func serializationSnapshot() -> MarkdownSerializationSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return MarkdownSerializationSnapshot(
            text: values.text,
            newlineStyle: values.newlineStyle,
            hasUTF8BOM: values.hasUTF8BOM
        )
    }

    private func read<T>(_ keyPath: KeyPath<Values, T>) -> T {
        lock.lock()
        defer { lock.unlock() }
        return values[keyPath: keyPath]
    }
}

private struct MarkdownSerializationSnapshot: Sendable {
    let text: String
    let newlineStyle: NewlineStyle
    let hasUTF8BOM: Bool
}

private struct DecodedDocument {
    let text: String
    let newlineStyle: NewlineStyle
    let hasBOM: Bool
    let hasTrailingNewline: Bool
}
