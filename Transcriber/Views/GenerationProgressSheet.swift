import AppKit
import SwiftUI

/// A sheet with a spinner and a status line while the on-device model works, with a Cancel button.
@MainActor
enum GenerationProgressSheet {
    @Observable
    final class Model {
        var status = "Starting…"
    }

    static func run(title: String,
                    work: @escaping @MainActor (@escaping @Sendable (String) -> Void) async throws -> String,
                    completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        let model = Model()
        let host = NSApp.keyWindow ?? NSApp.mainWindow
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = title
        var task: Task<Void, Never>?
        sheet.contentView = NSHostingView(rootView: SheetView(title: title, model: model) {
            task?.cancel()
        })
        let finish: @MainActor (Result<String, Error>) -> Void = { result in
            if let host { host.endSheet(sheet) } else { sheet.close() }
            completion(result)
        }
        task = Task {
            do {
                let text = try await work { status in
                    Task { @MainActor in model.status = status }
                }
                try Task.checkCancellation()
                finish(.success(text))
            } catch {
                finish(.failure(error))
            }
        }
        if let host {
            host.beginSheet(sheet)
        } else {
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
        }
    }

    private struct SheetView: View {
        let title: String
        let model: Model
        let cancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Apple's on-device model is writing this on your Mac. Nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Spacer()
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                }
            }
            .padding(18)
            .frame(width: 380)
        }
    }
}
