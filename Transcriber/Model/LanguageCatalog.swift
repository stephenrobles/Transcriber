import Foundation
import Observation
import Speech

/// The languages Apple's on-device engine supports on this Mac, with display names, loaded once.
/// Also the place where odd system locale identifiers are turned into something the engine and
/// the user both recognize.
@MainActor @Observable
final class LanguageCatalog {
    static let shared = LanguageCatalog()

    private(set) var supported: [Locale] = []
    private(set) var installedIdentifiers: Set<String> = []
    private(set) var isLoaded = false
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// Loads the list the first time it is needed and makes sure the saved default is a real engine locale.
    func load() {
        guard loading == nil else { return }
        loading = Task {
            let supported = await SpeechTranscriber.supportedLocales
            let installed = await SpeechTranscriber.installedLocales
            self.supported = supported.sorted { Self.name($0) < Self.name($1) }
            installedIdentifiers = Set(installed.map(\.identifier))
            isLoaded = true
            await validateDefault()
        }
    }

    /// If the saved language isn't one the engine lists (say `en_US@rg=bezzzz` from a Mac with a
    /// region override), replace it with the engine's equivalent, or English (US) as a last resort.
    private func validateDefault() async {
        let settings = AppSettings.shared
        let current = settings.localeIdentifier
        guard !supported.contains(where: { $0.identifier == current }) else { return }
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: Self.normalized(current))) {
            settings.localeIdentifier = equivalent.identifier
        } else if let english = supported.first(where: { $0.identifier == "en_US" }) ?? supported.first {
            settings.localeIdentifier = english.identifier
        }
    }

    /// "English (United States)", built from the language and region so that variant identifiers
    /// still read well, with the script spelled out for Chinese.
    nonisolated static func name(_ locale: Locale) -> String {
        let display = Locale.current
        var name: String
        if let code = locale.language.languageCode?.identifier, let languageName = display.localizedString(forLanguageCode: code) {
            name = languageName
        } else {
            name = display.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        }
        var qualifiers: [String] = []
        let subtags = locale.identifier.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "@" })
        if subtags.contains("Hans") { qualifiers.append("Simplified") }
        if subtags.contains("Hant") { qualifiers.append("Traditional") }
        if let region = locale.language.region?.identifier, let regionName = display.localizedString(forRegionCode: region) {
            qualifiers.append(regionName)
        }
        if !qualifiers.isEmpty { name += " (" + qualifiers.joined(separator: ", ") + ")" }
        return name
    }

    /// Strips format overrides and other extras (`en_US@rg=bezzzz` → `en_US`), keeping language,
    /// script and region.
    nonisolated static func normalized(_ identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        guard let code = locale.language.languageCode else { return "en_US" }
        // Keep a script only when the identifier spells one out (zh-Hans_CN), not the inferred one (en-Latn).
        let subtags = identifier.split(whereSeparator: { $0 == "@" })[0].split(whereSeparator: { $0 == "-" || $0 == "_" })
        let explicitScript = subtags.dropFirst().first { $0.count == 4 && $0.first!.isUppercase }.map { Locale.Script(String($0)) }
        let components = Locale.Components(languageCode: code, script: explicitScript, languageRegion: locale.language.region)
        return Locale(components: components).identifier
    }
}
