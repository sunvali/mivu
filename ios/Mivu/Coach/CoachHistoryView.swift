import SwiftUI
import Observation

@MainActor @Observable final class CoachHistoryModel {
    typealias Load = (String?, CoachDayCursor?, DiarySelectionOwnership) async throws -> CoachDayPage
    let origin: CoachNavigationOrigin
    private let load: Load
    private let isCurrent: () -> Bool
    private var generation: UInt64 = 0
    private(set) var page: CoachDayPage?
    private(set) var dateFilter: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(origin: CoachNavigationOrigin, isCurrent: @escaping () -> Bool, load: @escaping Load) {
        self.origin = origin; self.isCurrent = isCurrent; self.load = load
    }

    func invalidate() { generation &+= 1; page = nil; errorMessage = nil; isLoading = false }

    func show(_ date: String? = nil) async {
        guard isCurrent(), !Task.isCancelled else { return }
        generation &+= 1; dateFilter = date; page = nil; errorMessage = nil
        await fetch(before: nil, generation: generation)
    }

    func earlier() async {
        guard !isLoading, page?.hasMore == true, let cursor = page?.cursor else { return }
        await fetch(before: cursor, generation: generation)
    }

    func target(for row: CoachSegmentSummary) -> CoachSeekTarget? {
        guard isCurrent(), page?.segments.contains(row) == true else { return nil }
        return .turn(row.firstExchangeID)
    }

    private func fetch(before: CoachDayCursor?, generation operation: UInt64) async {
        guard isCurrent(), !Task.isCancelled else { return }
        let filter = dateFilter
        isLoading = true
        defer { if generation == operation, isCurrent() { isLoading = false } }
        do {
            let result = try await load(filter, before, origin.selection)
            guard !Task.isCancelled, generation == operation, isCurrent(), dateFilter == filter,
                  result.identity == origin.selection.identity else { return }
            // Each screenful remains bounded, including scoped date choices.
            page = result; errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == operation, isCurrent(), dateFilter == filter else { return }
            errorMessage = "Chat history is unavailable. Try again."
        }
    }
}

struct CoachHistoryPresentation: Identifiable {
    let id = UUID()
    let origin: CoachNavigationOrigin
    let timeZoneID: String
}

struct CoachHistoryView: View {
    @State private var history: CoachHistoryModel
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    private let zone: String
    private let open: OpenDiaryCoachAction
    @Environment(\.dismiss) private var dismiss

    init(model: DiaryViewModel, routes: CoachNavigationOwner, presentation: CoachHistoryPresentation,
         open: OpenDiaryCoachAction) {
        let origin = presentation.origin
        zone = presentation.timeZoneID; self.open = open
        #if DEBUG
        if DiaryLaunch.isCoachUITest, ProcessInfo.processInfo.arguments.contains("--coach-history-fixture") {
            _selectedDate = State(initialValue: CoachUITestInference.historyCaptureInstant.addingTimeInterval(-86_400))
        }
        #endif
        _history = State(initialValue: CoachHistoryModel(origin: origin, isCurrent: {
            routes.isCurrent(origin, selection: model.selection, isChangingProfile: model.isChangingProfile)
        }, load: { date, cursor, token in
            guard !model.isChangingProfile, model.selection == token else { throw DiaryError.wrongOwner }
            let page: CoachDayPage
            if let date {
                page = try await model.store.coachSegments(displayLocalDate: date, before: cursor,
                    expectedSelection: token, expectedProfileID: token.identity.profileID)
            } else {
                page = try await model.store.coachDays(before: cursor,
                    expectedSelection: token, expectedProfileID: token.identity.profileID)
            }
            let actual = try await model.store.selectionOwnership(expectedProfileID: token.identity.profileID)
            guard actual == token, !model.isChangingProfile, model.selection == token else { throw DiaryError.wrongOwner }
            return page
        }))
    }

    var body: some View {
        NavigationStack {
            List {
                if let date = history.dateFilter {
                    Section {
                        LabeledContent("Selected date", value: CoachReplyLines.dayTitle(date, zone: zone))
                        Button("Show all chat history") { Task { await history.show() } }
                            .frame(minHeight: 44).accessibilityIdentifier("coachHistoryShowAll")
                    }
                }
                if let message = history.errorMessage {
                    ContentUnavailableView("History unavailable", systemImage: "exclamationmark.bubble", description: Text(message))
                    Button("Try again") { Task { await history.show(history.dateFilter) } }.frame(minHeight: 44)
                } else if history.isLoading && history.page == nil {
                    ProgressView("Loading chat history")
                } else if history.page?.segments.isEmpty == true {
                    ContentUnavailableView(history.dateFilter == nil ? "No saved chat" : "No chat for this date", systemImage: "bubble.left", description:
                        Text(history.dateFilter.map { "No saved conversation is labeled \(CoachReplyLines.dayTitle($0, zone: zone))." } ?? "Your saved conversations will appear here."))
                        .accessibilityIdentifier("coachHistoryEmpty")
                }
                ForEach(history.page?.segments ?? []) { row in
                    Button {
                        guard let target = history.target(for: row) else { return }
                        if open(target, expectedSelection: history.origin.selection) { dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(CoachReplyLines.dayTitle(row.displayLocalDate, zone: zone)).font(.headline)
                            Text(captureLabel(row)).font(.subheadline).foregroundStyle(Color.diarySecondary)
                            Text(row.preview).font(.body).lineLimit(2).foregroundStyle(Color.diaryText)
                        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(.vertical, 4)
                    }.buttonStyle(.plain).accessibilityIdentifier("coachHistorySegment-" + row.segmentID.uuidString)
                }
                if history.page?.hasMore == true {
                    Button("Earlier conversations") { Task { await history.earlier() } }
                        .frame(minHeight: 44).disabled(history.isLoading).accessibilityIdentifier("coachHistoryEarlier")
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .foregroundStyle(Color.diaryText).tint(.diaryAccent)
            .navigationTitle("Chat history").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.frame(minHeight: 44) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Choose date", systemImage: "calendar") { showDatePicker = true }
                        .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("coachHistoryChooseDate")
                }
            }
            .task { await history.show() }
            .onDisappear { history.invalidate() }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    Form {
                        DatePicker("Conversation date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical).accessibilityIdentifier("coachHistoryDatePicker")
                        Text("Choose the date shown in your conversation. Separate visits remain separate choices.")
                            .font(.subheadline).foregroundStyle(Color.diarySecondary)
                    }
                    .navigationTitle("Choose date").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDatePicker = false }.frame(minHeight: 44) }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Show date") {
                                let label = ProgressDate.label(selectedDate, zone: zone)
                                showDatePicker = false
                                Task { await history.show(label) }
                            }.frame(minHeight: 44).accessibilityIdentifier("coachHistoryApplyDate")
                        }
                    }
                }.environment(\.timeZone, TimeZone(identifier: zone) ?? .gmt)
            }
        }
    }

    private func captureLabel(_ row: CoachSegmentSummary) -> String {
        let zone = TimeZone(identifier: row.displayTimeZoneID) ?? .gmt
        let time = row.firstCapturedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        // The zone only matters when the chat happened somewhere other than here.
        return zone == .current ? time : time + " · " + (zone.localizedName(for: .shortGeneric, locale: .current) ?? zone.identifier)
    }
}
