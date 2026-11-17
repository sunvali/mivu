import SwiftUI

enum TimeZoneCatalog {
    static func entries(matching query: String, at: Date) -> [(id: String, city: String, offset: String)] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            let city = TimeZoneSync.city(id)
            guard query.isEmpty || city.localizedCaseInsensitiveContains(query) || id.localizedCaseInsensitiveContains(query),
                  let zone = TimeZone(identifier: id) else { return nil }
            return (id, city, offset(zone.secondsFromGMT(for: at)))
        }.sorted { $0.city.localizedStandardCompare($1.city) == .orderedAscending }
    }

    /// "GMT+2", "GMT−5" (a true minus sign), "GMT+5:30".
    static func offset(_ seconds: Int) -> String {
        guard seconds != 0 else { return "GMT" }
        let minutes = abs(seconds) / 60
        return "GMT" + (seconds > 0 ? "+" : "−") + "\(minutes / 60)" + (minutes % 60 == 0 ? "" : String(format: ":%02d", minutes % 60))
    }
}

/// A searchable list of cities; choosing one pins the diary to that zone.
struct TimeZonePicker: View {
    let selected: String
    let choose: (String) async -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(TimeZoneCatalog.entries(matching: query, at: .now), id: \.id) { entry in
            Button {
                Task { await choose(entry.id); dismiss() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.city).foregroundStyle(Color.diaryText)
                        Text(entry.offset).font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                    Spacer(minLength: 8)
                    if entry.id == selected { Image(systemName: "checkmark").foregroundStyle(Color.diaryAccent).accessibilityHidden(true) }
                }.frame(minHeight: 44).contentShape(.rect)
            }
            .accessibilityAddTraits(entry.id == selected ? .isSelected : [])
        }
        .searchable(text: $query, prompt: Text("City"))
        .navigationTitle("Time zone")
    }
}
