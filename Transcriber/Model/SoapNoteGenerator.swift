import Foundation
import FoundationModels

/// Turns the transcript of a clinical visit into a SOAP note with Apple's on-device language model.
/// Nothing leaves the Mac. The model's context window is small, so long transcripts are first
/// condensed into clinical notes part by part, then the note is composed from those.
nonisolated enum SoapNoteGenerator {
    enum GenerationError: LocalizedError {
        case unavailable(String)
        case emptyTranscript
        case declined
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let why): why
            case .emptyTranscript: "There is no transcript text to write a note from."
            case .declined: "Apple's on-device model declined to work on this transcript (its built-in safety guardrails)."
            case .failed(let why): why
            }
        }
    }

    /// Why a SOAP note can't be written right now, or nil when it can.
    static func availabilityProblem() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac can't run Apple Intelligence, which the SOAP note needs."
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings to write SOAP notes."
            case .modelNotReady: return "Apple Intelligence is still preparing its model. Try again in a few minutes."
            @unknown default: return "Apple Intelligence isn't available right now."
            }
        }
    }

    /// Words per request to the model, leaving room for its instructions and answer.
    static var chunkWords = 700
    /// Material longer than this is condensed before the note is composed.
    static var composeInputWords = 900

    static func generate(transcript: String, title: String, date: Date = Date(),
                         status: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        if let problem = availabilityProblem() { throw GenerationError.unavailable(problem) }
        let cleaned = transcript.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw GenerationError.emptyTranscript }

        var material = cleaned
        var condensed = false
        var attempts = 0
        while true {
            while wordCount(material) > composeInputWords {
                material = try await condense(material, status: status)
                condensed = true
            }
            status("Writing the note…")
            do {
                let body = try await compose(material: material, isCondensed: condensed, title: title)
                return assemble(body: body, title: title, date: date)
            } catch GenerationError.failed(let why) where why.contains("too long") && attempts < 3 {
                // The model's own token count disagreed with our word estimate: condense harder.
                attempts += 1
                composeInputWords = max(300, composeInputWords * 2 / 3)
                chunkWords = max(250, chunkWords * 2 / 3)
            }
        }
    }

    // MARK: - Steps

    private static let condenseInstructions = """
    You extract clinical facts from part of the transcript of a medical visit. Reply with a dense \
    bulleted list, under 220 words, of everything clinically relevant in this part: the reason for \
    the visit and symptoms in the patient's own words; history (medical, surgical, medications, \
    allergies, family, social); review of systems; vital signs, examination findings and test \
    results that are stated; the clinician's impressions or diagnoses; treatments and medications \
    with doses; instructions, referrals and follow-up; and the patient's questions. Keep every \
    number, name and dose exactly as spoken. Include nothing that was not said. No headings, no \
    commentary, bullets only.
    """

    private static let composeInstructions = """
    You write medical SOAP notes from the transcript of a clinical encounter, or from clinical notes \
    extracted from it, for a clinician to paste into the patient's chart. Reply in Markdown with \
    exactly these sections and headings, in this order:

    ## Summary
    Four to eight bullet points covering the encounter.

    ## Subjective
    Bold field labels, each on its own line: **Chief Complaint:** (in the patient's own words), \
    **History of Present Illness:** (onset, duration, location, severity, character, aggravating and \
    relieving factors, what the patient has tried), **Past Medical History:**, **Medications and \
    Allergies:**, **Family History:**, **Social History:**, **Review of Systems:**.

    ## Objective
    **Vital Signs:** (bulleted, with units), **General Appearance:**, **Physical Examination:** \
    (grouped by system), **Diagnostic Tests and Imaging:**.

    ## Assessment
    **Primary Diagnosis:**, **Differential Diagnoses:** (bulleted, each with a brief reason for or \
    against), **Clinical Reasoning:** (a short paragraph).

    ## Plan
    **Medications:** (drug, dose, frequency, duration, and changes to existing medications), \
    **Lifestyle:**, **Tests and Imaging:**, **Follow-up and Referrals:** (when to return and warning \
    signs that should prompt an earlier visit).

    ## Patient Discharge Summary
    Written to the patient in plain, friendly language with short sentences: what was found, what \
    to do at home, any medications and how to take them, warning signs to watch for, and when to \
    come back or call.

    Rules: use only information in the material you are given. Where the material has nothing for \
    a field, write "Not discussed." Never invent vital signs, doses, test results or diagnoses. Be \
    concise and professional. Do not add a title, preamble or closing remarks; start with "## Summary".
    """

    private static func condense(_ text: String, status: @escaping @Sendable (String) -> Void) async throws -> String {
        let chunks = split(text, maxWords: chunkWords)
        var notes: [String] = []
        for (index, chunk) in chunks.enumerated() {
            status(chunks.count > 1 ? "Reading part \(index + 1) of \(chunks.count)…" : "Reading the transcript…")
            let session = LanguageModelSession(instructions: condenseInstructions)
            let prompt = "Part \(index + 1) of \(chunks.count) of the transcript:\n\n\(chunk)"
            notes.append(try await respond(session, to: prompt, maxTokens: 450))
        }
        return notes.joined(separator: "\n")
    }

    private static func compose(material: String, isCondensed: Bool, title: String) async throws -> String {
        let session = LanguageModelSession(instructions: composeInstructions)
        let kind = isCondensed ? "Clinical notes extracted from the recording" : "Transcript of the recording"
        let prompt = "\(kind) \"\(title)\":\n\n\(material)\n\nWrite the SOAP note now, starting with \"## Summary\"."
        var body = try await respond(session, to: prompt, maxTokens: 2000)
        if let range = body.range(of: "## Summary") {
            body = String(body[range.lowerBound...])
        }
        return body
    }

    private static func respond(_ session: LanguageModelSession, to prompt: String, maxTokens: Int) async throws -> String {
        do {
            let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: maxTokens)
            let response = try await session.respond(to: prompt, options: options)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                throw GenerationError.declined
            case .exceededContextWindowSize:
                throw GenerationError.failed("The transcript section was too long for the on-device model.")
            default:
                throw GenerationError.failed(error.localizedDescription)
            }
        }
    }

    private static func assemble(body: String, title: String, date: Date) -> String {
        let dateText = date.formatted(date: .long, time: .shortened)
        return """
        # SOAP Note: \(title)

        *\(dateText)*

        \(body)

        ---
        *Drafted by Transcriber from the recording with Apple's on-device model. Review and edit before charting.*

        """
    }

    // MARK: - Text helpers

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Splits text into pieces of about `maxWords` words, breaking after sentence ends where possible.
    static func split(_ text: String, maxWords: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > maxWords else { return [text] }
        var chunks: [String] = []
        var start = 0
        while start < words.count {
            var end = min(start + maxWords, words.count)
            if end < words.count {
                // Look back up to a quarter of the chunk for a sentence end.
                var cut = end
                while cut > start + maxWords * 3 / 4 {
                    if let last = words[cut - 1].last, ".?!".contains(last) { break }
                    cut -= 1
                }
                if cut > start + maxWords * 3 / 4 { end = cut }
            }
            chunks.append(words[start..<end].joined(separator: " "))
            start = end
        }
        return chunks
    }
}
