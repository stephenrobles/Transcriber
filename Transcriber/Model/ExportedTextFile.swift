import SwiftUI
import UniformTypeIdentifiers

/// A finished export handed to the system file exporter (iOS and iPadOS).
struct ExportedTextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .text]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
