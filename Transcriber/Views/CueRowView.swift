import SwiftUI

struct CueRowView: View {
    let cue: Cue
    let isCurrent: Bool
    let isEditing: Bool
    let forceHours: Bool
    let matches: [EditorState.Match]
    let currentMatch: EditorState.MatchID?
    let document: TranscriptDocument
    let state: EditorState
    let player: PlayerController
    @Environment(\.undoManager) private var undoManager

    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var showTiming = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    player.seek(to: cue.start)
                } label: {
                    Text(TimeFormat.cue(cue.start, forceHours: forceHours))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Jump playback to this cue")
                Button {
                    showTiming = true
                } label: {
                    Text(String(format: "%.1f s", cue.duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Adjust start and end times")
                .popover(isPresented: $showTiming, arrowEdge: .trailing) {
                    TimingPopover(cue: cue, document: document, player: player)
                }
            }
            .frame(width: forceHours ? 86 : 64, alignment: .leading)

            if isEditing {
                TextField("Cue text", text: $draft, selection: $selection, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...20)
                    .focused($focused)
                    .onSubmit { endEditing(commit: true) }
                    .onExitCommand { endEditing(commit: false) }
                    .onAppear {
                        draft = cue.text
                        DispatchQueue.main.async { focused = true }
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, isEditing { endEditing(commit: true) }
                    }
                    .onChange(of: selection) { _, new in
                        state.editingCursorOffset = cursorOffset(new)
                    }
                    .onChange(of: state.pendingSplit?.id) { _, id in
                        guard id == cue.id, let split = state.pendingSplit else { return }
                        state.pendingSplit = nil
                        performSplit(at: split.offset)
                    }
            } else {
                Text(highlighted)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { state.editingCueID = cue.id }
            }
        }
        .padding(.vertical, 5)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    private var highlighted: AttributedString {
        var text = AttributedString(cue.text)
        for match in matches {
            guard let lower = AttributedString.Index(match.range.lowerBound, within: text),
                  let upper = AttributedString.Index(match.range.upperBound, within: text) else { continue }
            let isCurrentMatch = match.id == currentMatch
            text[lower..<upper].backgroundColor = isCurrentMatch ? .orange.opacity(0.75) : .yellow.opacity(0.45)
        }
        return text
    }

    private func cursorOffset(_ selection: TextSelection?) -> Int? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return draft.distance(from: draft.startIndex, to: range.lowerBound)
        case .multiSelection(let ranges):
            guard let first = ranges.ranges.first else { return nil }
            return draft.distance(from: draft.startIndex, to: first.lowerBound)
        @unknown default:
            return nil
        }
    }

    private func endEditing(commit: Bool) {
        if commit {
            document.updateText(of: cue.id, to: draft.trimmingCharacters(in: .whitespacesAndNewlines), undoManager: undoManager)
        }
        if state.editingCueID == cue.id {
            state.editingCueID = nil
            state.editingCursorOffset = nil
        }
    }

    private func performSplit(at offset: Int) {
        let text = draft
        document.updateText(of: cue.id, to: text, undoManager: undoManager)
        state.editingCueID = nil
        state.editingCursorOffset = nil
        document.split(cue.id, at: offset, undoManager: undoManager)
    }
}

/// Start and end time fields for one cue, with buttons to take the playhead position.
struct TimingPopover: View {
    let cue: Cue
    let document: TranscriptDocument
    let player: PlayerController
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var startText = ""
    @State private var endText = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cue Timing")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Start")
                    TextField("0:00:00.000", text: $startText)
                        .frame(width: 120)
                        .monospacedDigit()
                    Button("Playhead") { startText = TimeFormat.precise(player.currentTime) }
                        .disabled(!player.isLoaded)
                }
                GridRow {
                    Text("End")
                    TextField("0:00:00.000", text: $endText)
                        .frame(width: 120)
                        .monospacedDigit()
                    Button("Playhead") { endText = TimeFormat.precise(player.currentTime) }
                        .disabled(!player.isLoaded)
                }
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            startText = TimeFormat.precise(cue.start)
            endText = TimeFormat.precise(cue.end)
        }
    }

    private func apply() {
        guard let start = TimeFormat.parse(startText), let end = TimeFormat.parse(endText) else {
            problem = "Use H:MM:SS.mmm, M:SS or plain seconds."
            return
        }
        guard end > start else {
            problem = "The end must come after the start."
            return
        }
        document.updateTiming(of: cue.id, start: start, end: end, undoManager: undoManager)
        dismiss()
    }
}
