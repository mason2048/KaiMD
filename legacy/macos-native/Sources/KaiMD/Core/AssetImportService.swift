import AppKit
import Foundation

enum AssetImportError: LocalizedError, Equatable {
    case unsavedDocument
    case sourceDoesNotExist(URL)
    case unsupportedImage(URL)
    case imageEncodingFailed
    case documentDirectoryUnavailable(URL)
    case unsafeAssetsDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .unsavedDocument:
            "请先保存 Markdown 文件，再导入图片。"
        case let .sourceDoesNotExist(url):
            "图片不存在：\(url.path)"
        case let .unsupportedImage(url):
            "不支持的图片格式：\(url.lastPathComponent)"
        case .imageEncodingFailed:
            "无法将粘贴的图片编码为 PNG。"
        case let .documentDirectoryUnavailable(url):
            "Markdown 文件所在目录不可用：\(url.path)"
        case let .unsafeAssetsDirectory(url):
            "assets 目录是符号链接或指向文档目录之外：\(url.path)"
        }
    }
}

/// Copies dropped files and pasted bitmap data beside a document under
/// `assets/`, then returns the Markdown snippet to insert into the editor.
@MainActor
final class AssetImportService {
    static let shared = AssetImportService()

    init() {}

    static func importImage(
        from sourceURL: URL,
        for documentURL: URL,
        altText: String? = nil
    ) throws -> String {
        try shared.importImage(from: sourceURL, into: documentURL, altText: altText)
    }

    static func importImage(
        _ image: NSImage,
        suggestedFilename: String = "image.png",
        for documentURL: URL,
        altText: String? = nil
    ) throws -> String {
        try shared.importImage(
            image,
            suggestedFilename: suggestedFilename,
            into: documentURL,
            altText: altText
        )
    }

    func importImage(
        from sourceURL: URL,
        into document: MarkdownDocument,
        altText: String? = nil
    ) throws -> String {
        guard let documentURL = document.fileURL else {
            throw AssetImportError.unsavedDocument
        }
        let markdown = try importImage(from: sourceURL, into: documentURL, altText: altText)
        if let workspace = document.workspace {
            workspace.scheduleRefresh()
        }
        return markdown
    }

    func importImage(
        _ image: NSImage,
        suggestedFilename: String = "image.png",
        into document: MarkdownDocument,
        altText: String? = nil
    ) throws -> String {
        guard let documentURL = document.fileURL else {
            throw AssetImportError.unsavedDocument
        }
        let markdown = try importImage(
            image,
            suggestedFilename: suggestedFilename,
            into: documentURL,
            altText: altText
        )
        if let workspace = document.workspace {
            workspace.scheduleRefresh()
        }
        return markdown
    }

    func importImage(
        from sourceURL: URL,
        into documentURL: URL,
        altText: String? = nil
    ) throws -> String {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AssetImportError.sourceDoesNotExist(sourceURL)
        }
        guard WorkspaceFileScanner.imageExtensions.contains(source.pathExtension.lowercased()) else {
            throw AssetImportError.unsupportedImage(sourceURL)
        }

        let assetsDirectory = try prepareAssetsDirectory(for: documentURL)
        if source.deletingLastPathComponent().standardizedFilePath == assetsDirectory.standardizedFilePath {
            return markdownLink(
                for: source,
                assetsDirectory: assetsDirectory,
                altText: altText
            )
        }

        let filename = sanitizedFilename(source.lastPathComponent, defaultExtension: source.pathExtension)
        let destination = uniqueDestination(in: assetsDirectory, desiredFilename: filename)
        try FileManager.default.copyItem(at: source, to: destination)
        return markdownLink(for: destination, assetsDirectory: assetsDirectory, altText: altText)
    }

    func importImage(
        _ image: NSImage,
        suggestedFilename: String = "image.png",
        into documentURL: URL,
        altText: String? = nil
    ) throws -> String {
        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData),
              let pngData = representation.representation(using: .png, properties: [:])
        else {
            throw AssetImportError.imageEncodingFailed
        }

        let assetsDirectory = try prepareAssetsDirectory(for: documentURL)
        let filename = sanitizedFilename(suggestedFilename, defaultExtension: "png")
        let pngFilename = (filename as NSString).deletingPathExtension + ".png"
        let destination = uniqueDestination(in: assetsDirectory, desiredFilename: pngFilename)
        // Foundation does not support combining `.atomic` and
        // `.withoutOverwriting`; the destination is already collision-free.
        try pngData.write(to: destination, options: .withoutOverwriting)
        return markdownLink(for: destination, assetsDirectory: assetsDirectory, altText: altText)
    }

    private func prepareAssetsDirectory(for documentURL: URL) throws -> URL {
        let parent = documentURL.standardizedFileURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AssetImportError.documentDirectoryUnavailable(parent)
        }
        let candidate = parent.appendingPathComponent("assets", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
            let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw AssetImportError.unsafeAssetsDirectory(candidate)
            }
        } else {
            try FileManager.default.createDirectory(
                at: candidate,
                withIntermediateDirectories: false
            )
        }

        let assetsDirectory = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard assetsDirectory.deletingLastPathComponent().standardizedFilePath == parent.standardizedFilePath else {
            throw AssetImportError.unsafeAssetsDirectory(candidate)
        }
        return assetsDirectory
    }

    private func uniqueDestination(in directory: URL, desiredFilename: String) -> URL {
        var destination = directory.appendingPathComponent(desiredFilename)
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }

        let fileExtension = (desiredFilename as NSString).pathExtension
        let stem = (desiredFilename as NSString).deletingPathExtension
        var counter = 2
        repeat {
            destination = directory.appendingPathComponent(
                "\(stem)-\(counter)" + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
            )
            counter += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
    }

    private func sanitizedFilename(_ requestedName: String, defaultExtension: String) -> String {
        var name = URL(fileURLWithPath: requestedName).lastPathComponent
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "-")
        if name.isEmpty || name.hasPrefix(".") {
            name = "image.\(defaultExtension.isEmpty ? "png" : defaultExtension)"
        } else if (name as NSString).pathExtension.isEmpty {
            name += ".\(defaultExtension.isEmpty ? "png" : defaultExtension)"
        }
        return name
    }

    private func markdownLink(
        for imageURL: URL,
        assetsDirectory: URL,
        altText: String?
    ) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        let relativePath = "assets/\(imageURL.lastPathComponent)"
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: allowed) ?? relativePath
        let fallbackAlt = imageURL.deletingPathExtension().lastPathComponent
        let escapedAlt = (altText?.isEmpty == false ? altText! : fallbackAlt)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "![\(escapedAlt)](\(encodedPath))"
    }
}
