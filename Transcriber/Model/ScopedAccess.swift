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
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark and starts accessing it; nil when the file is gone or access was refused.
    static func resolve(_ bookmark: Data) -> ScopedAccess? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ScopedAccess(url: url)
    }
}
