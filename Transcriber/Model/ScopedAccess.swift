import Foundation

/// Keeps a security-scoped file or folder readable for as long as this object lives.
/// Sandboxed builds need this for media a project points to and for watched folders;
/// elsewhere it is harmless.
nonisolated final class ScopedAccess: Sendable {
    let url: URL
    private let started: Bool

    init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }

    /// A bookmark that restores access in a later launch, if the file is reachable now.
    static func bookmark(for url: URL) -> Data? {
        #if os(macOS)
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        // iOS bookmarks to user-picked files carry their security scope implicitly.
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// Resolves a bookmark and starts accessing it; nil when the file is gone or access was refused.
    static func resolve(_ bookmark: Data) -> ScopedAccess? {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: options, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ScopedAccess(url: url)
    }
}
