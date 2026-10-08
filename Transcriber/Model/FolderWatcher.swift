import Foundation
import Observation

/// A folder the app keeps an eye on. Files that were already there when it was added are left
/// alone; anything that arrives afterwards is processed once it has stopped changing.
nonisolated struct WatchedFolder: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var path: String
    var isEnabled = true
    var addedAt = Date()

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { (path as NSString).lastPathComponent }
    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
    var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// One file the watcher has handled, for the activity list in Settings.
nonisolated struct WatchActivity: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case running
        case done
        case failed(String)
    }

    let id = UUID()
    var fileName: String
    var folderName: String
    var status: Status
    var date: Date
    var resultURL: URL?
}

/// Polls the watched folders every few seconds, waits for new files to stop growing, then hands
/// them to the app one at a time. The app supplies what counts as a supported file and what to do
/// with it; the watcher owns the folder list, the processed-file memory and the activity log.
@MainActor @Observable
final class FolderWatcher {
    static let shared = FolderWatcher()

    private(set) var folders: [WatchedFolder] = [] {
        didSet { persistFolders() }
    }
    private(set) var activity: [WatchActivity] = []
    private(set) var isProcessing = false

    private struct Candidate {
        var size: Int64
        var modified: Date
        var firstSeen: Date
        var stableSince: Date
    }

    @ObservationIgnored private var accepts: @MainActor (URL) -> Bool = { _ in false }
    @ObservationIgnored private var process: @MainActor (URL) async throws -> URL? = { _ in nil }
    /// Files already handled (or present when their folder was added), by path.
    @ObservationIgnored private var processed: [String: Date] = [:]
    @ObservationIgnored private var candidates: [String: Candidate] = [:]
    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var worker: Task<Void, Never>?

    private let defaults = UserDefaults.standard
    private static let foldersKey = "watchedFolders"
    private static let processedKey = "watchedFolderProcessedFiles"
    /// A file must keep the same size and modification date for this long before it is picked up.
    static let settleTime: TimeInterval = 4
    static let pollInterval: TimeInterval = 3

    private init() {
        if let data = defaults.data(forKey: Self.foldersKey),
           let saved = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders = saved
        }
        if let saved = defaults.dictionary(forKey: Self.processedKey) as? [String: Date] {
            processed = saved
        }
    }

    /// Call once at launch. `process` returns the file worth showing the user when it is done.
    func configure(accepts: @escaping @MainActor (URL) -> Bool, process: @escaping @MainActor (URL) async throws -> URL?) {
        self.accepts = accepts
        self.process = process
        updateTimer()
    }

    var isWatching: Bool { folders.contains { $0.isEnabled } }

    // MARK: - Folder list

    func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !folders.contains(where: { $0.path == path }) else { return }
        // Everything already in the folder is the user's business; only new arrivals get processed.
        for file in contents(of: url) {
            processed[file.standardizedFileURL.path] = Date()
        }
        persistProcessed()
        folders.append(WatchedFolder(path: path))
        updateTimer()
    }

    func remove(_ id: UUID) {
        folders.removeAll { $0.id == id }
        updateTimer()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        if enabled, !folders[index].isEnabled {
            // Re-enabling starts fresh: what accumulated while it was off is not a backlog to churn through.
            for file in contents(of: folders[index].url) {
                processed[file.standardizedFileURL.path] = Date()
            }
            persistProcessed()
        }
        folders[index].isEnabled = enabled
        updateTimer()
    }

    // MARK: - Scanning

    private func updateTimer() {
        if isWatching {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            }
            timer?.tolerance = 1
            scan()
        } else {
            timer?.invalidate()
            timer = nil
            candidates = [:]
        }
    }

    private func contents(of folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            let name = url.lastPathComponent.lowercased()
            // Partial downloads and in-flight copies from browsers and sync tools.
            for suffix in [".part", ".partial", ".download", ".crdownload", ".tmp"] where name.hasSuffix(suffix) { return false }
            return accepts(url)
        }
    }

    private func scan() {
        let now = Date()
        var seen: Set<String> = []
        for folder in folders where folder.isEnabled {
            for url in contents(of: folder.url) {
                let path = url.standardizedFileURL.path
                guard processed[path] == nil, !queue.contains(where: { $0.path == path }) else { continue }
                seen.insert(path)
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate ?? now
                if var candidate = candidates[path] {
                    if candidate.size != size || candidate.modified != modified {
                        candidate.size = size
                        candidate.modified = modified
                        candidate.stableSince = now
                        candidates[path] = candidate
                    } else if now.timeIntervalSince(candidate.stableSince) >= Self.settleTime, size > 0 {
                        candidates[path] = nil
                        enqueue(url)
                    }
                } else {
                    candidates[path] = Candidate(size: size, modified: modified, firstSeen: now, stableSince: now)
                }
            }
        }
        // Forget candidates that disappeared before they settled.
        candidates = candidates.filter { seen.contains($0.key) }
    }

    private func enqueue(_ url: URL) {
        processed[url.standardizedFileURL.path] = Date()
        persistProcessed()
        queue.append(url)
        startWorker()
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !queue.isEmpty {
                let url = queue.removeFirst()
                await run(url)
            }
            worker = nil
        }
    }

    private func run(_ url: URL) async {
        let folderName = url.deletingLastPathComponent().lastPathComponent
        var entry = WatchActivity(fileName: url.lastPathComponent, folderName: folderName, status: .running, date: Date())
        activity.insert(entry, at: 0)
        isProcessing = true
        defer { isProcessing = false }
        let activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Processing a watched folder")
        defer { ProcessInfo.processInfo.endActivity(activityToken) }
        do {
            let result = try await process(url)
            entry.status = .done
            entry.resultURL = result
            Notifier.post(title: "Finished \(url.lastPathComponent)",
                          body: result.map { "Saved \($0.lastPathComponent) in \(folderName)." } ?? "From the watched folder \(folderName).",
                          fileURL: result ?? url)
        } catch {
            entry.status = .failed(error.localizedDescription)
            Notifier.post(title: "Couldn't process \(url.lastPathComponent)", body: error.localizedDescription, fileURL: url)
        }
        entry.date = Date()
        if let index = activity.firstIndex(where: { $0.id == entry.id }) {
            activity[index] = entry
        }
        if activity.count > 50 { activity.removeLast(activity.count - 50) }
    }

    // MARK: - Persistence

    private func persistFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: Self.foldersKey)
        }
    }

    private func persistProcessed() {
        // Keep the memory bounded: the newest few thousand entries are plenty.
        if processed.count > 5000 {
            let keep = processed.sorted { $0.value > $1.value }.prefix(4000)
            processed = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        defaults.set(processed, forKey: Self.processedKey)
    }
}
