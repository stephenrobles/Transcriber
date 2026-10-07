import Foundation
import Observation
import UniformTypeIdentifiers

/// Media files handed to the app from the Finder or Dock before a document window could take them.
@Observable
final class PendingMedia {
    static let shared = PendingMedia()

    private(set) var urls: [URL] = []
    /// Document windows that have no media yet and can adopt a dropped file.
    var emptyDocumentIDs: Set<UUID> = []

    func enqueue(_ newURLs: [URL]) {
        urls.append(contentsOf: newURLs)
    }

    func take() -> URL? {
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }

    static let acceptedTypes: [UTType] = [.movie, .audio]

    static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) ?? (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .audio)
    }

    static func isProject(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "transcriber"
    }
}
