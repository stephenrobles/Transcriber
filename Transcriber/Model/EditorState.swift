import Foundation
import Observation
import SwiftUI

/// Per-window editing state: which tab is showing, the list selection, the cue being edited,
/// and the Find & Replace bar.
@Observable
final class EditorState {
    enum Tab: String, CaseIterable, Identifiable {
        case cues, text
        var id: String { rawValue }
        var title: String { self == .cues ? "Cues" : "Text" }
    }

    var tab: Tab = .cues
    var selection: Set<UUID> = []
    var editingCueID: UUID?
    /// Caret position (in characters) inside the cue being edited, for Split Cue.
    var editingCursorOffset: Int?
    /// Set by the Split Cue command; the row editing that cue performs the split with its draft text.
    var pendingSplit: (id: UUID, offset: Int)?
    var showTimestampsInText = false

    // Scrolling
    private(set) var scrollTarget: UUID?
    private(set) var scrollRequest = 0

    func scroll(to id: UUID) {
        scrollTarget = id
        scrollRequest += 1
    }

    // Find & Replace
    var findVisible = false
    var findQuery = "" { didSet { currentMatch = nil } }
    var replacement = ""
    var matchCase = false { didSet { currentMatch = nil } }
    var wholeWords = false { didSet { currentMatch = nil } }
    var currentMatch: MatchID?
    var findFieldFocusRequest = 0

    struct MatchID: Hashable {
        var cueID: UUID
        var ordinal: Int
    }

    struct Match: Hashable {
        var id: MatchID
        var range: Range<String.Index>
    }

    var regex: NSRegularExpression? {
        let query = findQuery
        guard !query.isEmpty else { return nil }
        var pattern = NSRegularExpression.escapedPattern(for: query)
        if wholeWords { pattern = "\\b" + pattern + "\\b" }
        return try? NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive])
    }

    func matches(in text: String, cueID: UUID, regex: NSRegularExpression?) -> [Match] {
        guard let regex else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).enumerated().compactMap { ordinal, result in
            guard let range = Range(result.range, in: text) else { return nil }
            return Match(id: MatchID(cueID: cueID, ordinal: ordinal), range: range)
        }
    }

    func allMatches(in cues: [Cue]) -> [Match] {
        guard let regex else { return [] }
        return cues.flatMap { matches(in: $0.text, cueID: $0.id, regex: regex) }
    }

    func showFind(focusReplace: Bool = false) {
        tab = .cues
        findVisible = true
        findFieldFocusRequest += 1
    }

    func hideFind() {
        findVisible = false
        currentMatch = nil
    }

    /// Moves to the next (or previous) match and returns it, wrapping around the end.
    @discardableResult
    func step(_ direction: Int, in cues: [Cue]) -> Match? {
        let all = allMatches(in: cues)
        guard !all.isEmpty else {
            currentMatch = nil
            return nil
        }
        var index: Int
        if let current = currentMatch, let position = all.firstIndex(where: { $0.id == current }) {
            index = (position + direction + all.count) % all.count
        } else if direction >= 0 {
            index = 0
        } else {
            index = all.count - 1
        }
        if index < 0 { index = 0 }
        let match = all[index]
        currentMatch = match.id
        selection = [match.id.cueID]
        scroll(to: match.id.cueID)
        return match
    }
}
