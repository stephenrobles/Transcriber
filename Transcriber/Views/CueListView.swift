import SwiftUI

struct CueListView: View {
    let document: TranscriptDocument
    @Bindable var state: EditorState
    let player: PlayerController
    @Environment(\.undoManager) private var undoManager

    private var settings: AppSettings { AppSettings.shared }

    private var currentCueID: UUID? {
        guard let transcript = document.transcript, player.isLoaded,
              let index = transcript.cueIndex(at: player.currentTime) else { return nil }
        let cue = transcript.cues[index]
        // Keep the last cue highlighted through a short pause, but not through a long one.
        return player.currentTime < cue.end + 0.75 ? cue.id : nil
    }

    var body: some View {
        let cues = document.cues
        let regex = state.regex
        let currentID = currentCueID
        let forceHours = (cues.last?.end ?? 0) >= 3600
        ScrollViewReader { proxy in
            List(selection: $state.selection) {
                ForEach(cues) { cue in
                    CueRowView(cue: cue,
                               isCurrent: cue.id == currentID,
                               isEditing: state.editingCueID == cue.id,
                               forceHours: forceHours,
                               matches: state.matches(in: cue.text, cueID: cue.id, regex: regex),
                               currentMatch: state.currentMatch,
                               document: document,
                               state: state,
                               player: player)
                        .id(cue.id)
                        .tag(cue.id)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if let id = ids.first, let cue = cues.first(where: { $0.id == id }) {
                    player.seek(to: cue.start)
                }
            }
            .onDeleteCommand {
                guard state.editingCueID == nil else { return }
                document.delete(state.selection, undoManager: undoManager)
                state.selection = []
            }
            .onKeyPress(.space) {
                guard state.editingCueID == nil, player.isLoaded else { return .ignored }
                player.togglePlayback()
                return .handled
            }
            .onKeyPress(.return) {
                guard state.editingCueID == nil, state.selection.count == 1, let id = state.selection.first else { return .ignored }
                state.editingCueID = id
                return .handled
            }
            .onChange(of: state.scrollRequest) {
                if let target = state.scrollTarget {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
            .onChange(of: currentID) { _, id in
                guard settings.followPlayback, player.isPlaying, state.editingCueID == nil, let id else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: state.editingCueID) { _, id in
                if let id { state.selection = [id] }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        if ids.count == 1, let id = ids.first {
            Button("Play from Here") {
                if let cue = document.cues.first(where: { $0.id == id }) { player.seek(to: cue.start, thenPlay: true) }
            }
            Button("Edit Text") { state.editingCueID = id }
            Button("Merge with Next Cue") { document.mergeWithNext(id, undoManager: undoManager) }
            Button("Insert Cue After") {
                let new = document.insertCue(after: id, undoManager: undoManager)
                state.selection = [new]
                state.editingCueID = new
            }
            Divider()
        }
        if !ids.isEmpty {
            Button(ids.count == 1 ? "Delete Cue" : "Delete \(ids.count) Cues") {
                document.delete(ids, undoManager: undoManager)
                state.selection = []
            }
        }
    }
}
