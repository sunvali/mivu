import SwiftUI

struct DiaryReportSettings: View {
    private enum Range: String, CaseIterable, Identifiable { case week = "Last 7 days", month = "Last 30 days", all = "All time", custom = "Custom"; var id: Self { self } }
    @Bindable var model: DiaryViewModel
    @State private var range = Range.month
    @State private var format = DiaryReport.Format.pdf
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var end = Date.now
    @State private var preparing = false
    @State private var shared: [URL]?

    var body: some View {
        Picker("Range", selection: $range) { ForEach(Range.allCases) { Text($0.rawValue).tag($0) } }
        if range == .custom {
            DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
            DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
        }
        Picker("Format", selection: $format) { ForEach(DiaryReport.Format.allCases) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).frame(minHeight: 44)
            .accessibilityLabel("Report format")
        Text(format == .pdf ? "A summary page with daily totals and weight, then every saved meal. Made for a doctor or dietitian."
                            : "Three spreadsheet files: meals, daily totals against targets, and weigh-ins.")
            .font(.subheadline).foregroundStyle(Color.diarySecondary)
        Button { share() } label: {
            if preparing { ProgressView("Preparing report") } else { Label("Share report", systemImage: "square.and.arrow.up") }
        }
        .frame(minHeight: 44).disabled(preparing || model.selection == nil)
        .sheet(isPresented: Binding(get: { shared != nil }, set: { if !$0 { cleanUp() } })) {
            ActivitySheet(items: shared ?? []).ignoresSafeArea()
        }
    }

    private func share() {
        guard let token = model.selection else { return }
        preparing = true
        let range = range, format = format, start = start, end = end
        Task {
            defer { preparing = false }
            do {
                let snapshot = try await model.store.snapshotForExport(expectedProfileID: token.identity.profileID)
                let urls = try await Task.detached {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: snapshot.profile.timeZoneID) ?? .current
                    func local(_ date: Date) -> String {
                        let parts = calendar.dateComponents([.year, .month, .day], from: date)
                        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                    }
                    let (from, through): (Date?, Date?) = switch range {
                    case .week: (calendar.date(byAdding: .day, value: -6, to: .now), .now)
                    case .month: (calendar.date(byAdding: .day, value: -29, to: .now), .now)
                    case .all: (nil, nil)
                    case .custom: (start, end)
                    }
                    let report = DiaryReport(snapshot, from: from.map(local), through: through.map(local))
                    return try report.write(format, to: FileManager.default.temporaryDirectory.appendingPathComponent("Report-" + UUID().uuidString))
                }.value
                guard model.selection == token else { return }
                shared = urls
            } catch { model.errorMessage = "Could not prepare this report. Your local diary is preserved." }
        }
    }
    private func cleanUp() {
        if let folder = shared?.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: folder) }
        shared = nil
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
