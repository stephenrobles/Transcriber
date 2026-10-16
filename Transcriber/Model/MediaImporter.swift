import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video chosen from the Photos library, copied into the app's own Media folder so a project
/// can keep pointing at it after the picker's temporary copy is gone.
nonisolated struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            ImportedMovie(url: try MediaImporter.keep(received.file))
        }
    }
}

nonisolated enum MediaImporter {
    /// `Documents/Media/` inside the app container, created on demand.
    static var mediaFolder: URL {
        get throws {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = documents.appendingPathComponent("Media", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    /// Copies a file into the Media folder under its own name (numbered if that name is taken).
    static func keep(_ file: URL) throws -> URL {
        let folder = try mediaFolder
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var target = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }
}
