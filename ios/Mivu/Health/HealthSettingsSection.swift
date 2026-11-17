import SwiftUI

/// Settings › Apple Health: read workouts, and offer to add their calories to the food budget.
struct HealthSettingsSection: View {
    @Bindable var model: DiaryViewModel
    @Bindable var health: HealthWorkoutSync
    @State private var showConnect = false
    @State private var addToBudget = true
    @State private var connecting = false
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Read workouts from Apple Health", isOn: Binding(get: { health.isConnected }, set: { on in
                if on { addToBudget = true; showConnect = true } else { health.disconnect() }
            }))
            .frame(minHeight: 44)
            .disabled(connecting || model.selection == nil)
            .accessibilityIdentifier("healthSettingsToggle")
            if let failure { Text(failure).font(.subheadline).foregroundStyle(Color.diaryError) }
        } header: {
            Text("Apple Health")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workouts from Garmin Connect, Apple Watch and other apps that share with Health. They stay on this iPhone and are not shared with Coach.")
                if health.isConnected {
                    Text("No workouts yet? In Garmin Connect, turn on Apple Health sharing; in iOS Settings › Health › Data Access, allow Mivu.")
                }
            }
        }
        .onAppear { health.refresh() }
        .sheet(isPresented: $showConnect) { connectSheet }
    }

    private var connectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Apply workout calories to your budget?").font(.title3.weight(.semibold))
                    Toggle("Add workout calories to my budget", isOn: $addToBudget)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("healthCreditToggle")
                } footer: {
                    Text("Only each workout's active calories count, once per session. You can change this later in Goals.")
                }
                Section {
                    Button("Connect") { Task { await connect() } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(connecting)
                        .accessibilityIdentifier("healthConnect")
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showConnect = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func connect() async {
        guard let token = model.selection, let zone = model.readModel?.profile.timeZoneID else { return }
        connecting = true; defer { connecting = false }
        do {
            try await health.connect()
            if addToBudget {
                let today = ProgressAnalytics.dateLabel(Date(), zone: zone)
                await model.change { try await model.store.enableExerciseCredit(from: today, expectedProfileID: token.identity.profileID) }
            }
            failure = nil; showConnect = false
        } catch {
            failure = "Could not connect to Apple Health. Check iOS Settings › Health › Data Access › Mivu."
        }
    }
}
