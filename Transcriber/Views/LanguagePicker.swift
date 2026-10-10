import SwiftUI

/// A menu of the engine's languages bound to a locale identifier. Shows the current value even
/// while the list is still loading or if it isn't in the list.
struct LanguagePicker: View {
    @Binding var selection: String
    var label = "Language"

    private var catalog: LanguageCatalog { LanguageCatalog.shared }

    var body: some View {
        Picker(label, selection: $selection) {
            if !catalog.supported.contains(where: { $0.identifier == selection }) {
                Text(LanguageCatalog.name(Locale(identifier: selection))).tag(selection)
            }
            ForEach(catalog.supported, id: \.identifier) { locale in
                Text(catalog.menuTitle(locale)).tag(locale.identifier)
            }
        }
        .onAppear { catalog.load() }
    }
}
