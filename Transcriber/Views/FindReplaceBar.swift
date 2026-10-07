import SwiftUI

struct FindReplaceBar: View {
    let document: TranscriptDocument
    @Bindable var state: EditorState
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focusedField: Field?

    private enum Field { case find, replace }

    var body: some View {
        let matches = state.allMatches(in: document.cues)
        let position = state.currentMatch.flatMap { current in matches.firstIndex { $0.id == current } }
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find", text: $state.findQuery)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .find)
                    .onSubmit { state.step(1, in: document.cues) }
                Toggle(isOn: $state.matchCase) { Text("Aa") }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Match case")
                Toggle(isOn: $state.wholeWords) { Image(systemName: "textformat.abc.dottedunderline") }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Whole words")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 360)

            Text(countLabel(matches.count, position: position))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .leading)

            Button { state.step(-1, in: document.cues) } label: { Image(systemName: "chevron.up") }
                .disabled(matches.isEmpty)
                .help("Previous match (⇧⌘G)")
            Button { state.step(1, in: document.cues) } label: { Image(systemName: "chevron.down") }
                .disabled(matches.isEmpty)
                .help("Next match (⌘G)")

            Divider().frame(height: 18)

            TextField("Replace", text: $state.replacement)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .replace)
                .frame(maxWidth: 240)
                .onSubmit { replaceCurrent() }
            Button("Replace") { replaceCurrent() }
                .disabled(matches.isEmpty)
            Button("All") { replaceAll() }
                .disabled(matches.isEmpty)
                .help("Replace all matches")

            Spacer()

            Button { state.hideFind() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Close (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { focusedField = .find }
        .onChange(of: state.findFieldFocusRequest) { focusedField = .find }
        .onExitCommand { state.hideFind() }
    }

    private func countLabel(_ count: Int, position: Int?) -> String {
        if state.findQuery.isEmpty { return "" }
        if count == 0 { return "No matches" }
        if let position { return "\(position + 1) of \(count)" }
        return "\(count) match\(count == 1 ? "" : "es")"
    }

    private func replaceCurrent() {
        let cues = document.cues
        var match = state.currentMatch.flatMap { current in state.allMatches(in: cues).first { $0.id == current } }
        if match == nil { match = state.step(1, in: cues) }
        guard let match, var cue = cues.first(where: { $0.id == match.id.cueID }) else { return }
        cue.text.replaceSubrange(match.range, with: state.replacement)
        document.updateText(of: cue.id, to: cue.text, undoManager: undoManager)
        // The replaced match is gone, so the match now at this position is the next one.
        let remaining = state.allMatches(in: document.cues)
        if remaining.isEmpty {
            state.currentMatch = nil
        } else {
            let next = remaining.first { $0.id.cueID == match.id.cueID && $0.id.ordinal >= match.id.ordinal }
                ?? remaining.first { cueIndex($0.id.cueID) > cueIndex(match.id.cueID) }
                ?? remaining[0]
            state.currentMatch = next.id
            state.selection = [next.id.cueID]
            state.scroll(to: next.id.cueID)
        }
    }

    private func replaceAll() {
        guard let regex = state.regex else { return }
        let template = NSRegularExpression.escapedTemplate(for: state.replacement)
        let updated = document.cues.map { cue in
            var cue = cue
            cue.text = regex.stringByReplacingMatches(in: cue.text, range: NSRange(location: 0, length: (cue.text as NSString).length), withTemplate: template)
            return cue
        }
        document.setCues(updated, actionName: "Replace All", undoManager: undoManager)
        state.currentMatch = nil
    }

    private func cueIndex(_ id: UUID) -> Int {
        document.cues.firstIndex { $0.id == id } ?? Int.max
    }
}
