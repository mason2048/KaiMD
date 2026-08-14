import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves preview images without granting WebKit general `file:` URL access.
final class WorkspaceAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let maximumAssetSize = 50 * 1_024 * 1_024

    var workspaceRoot: URL?

    init(workspaceRoot: URL? = nil) {
        self.workspaceRoot = workspaceRoot
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let workspaceRoot,
              let fileURL = PreviewURLRouter.assetFileURL(
                  for: requestURL,
                  workspaceRoot: workspaceRoot
              )
        else {
            urlSchemeTask.didFailWithError(assetError("Invalid or out-of-workspace asset URL."))
            return
        }

        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw assetError("The requested asset is not a regular file.")
            }
            guard let fileSize = values.fileSize, fileSize <= Self.maximumAssetSize else {
                throw assetError("The requested asset is too large.")
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            guard let contentType = UTType(filenameExtension: fileExtension),
                  contentType.conforms(to: .image),
                  let mimeType = contentType.preferredMIMEType
            else {
                throw assetError("Only image assets can be loaded in the preview.")
            }

            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Reads are completed synchronously and therefore have no pending operation to cancel.
    }

    private func assetError(_ message: String) -> NSError {
        NSError(
            domain: "KaiMD.WorkspaceAsset",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
