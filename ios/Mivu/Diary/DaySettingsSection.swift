import SwiftUI
import UserNotifications

/// When a waking day starts, and the optional morning reminder (off until the person turns it on).
struct DaySettingsSection: View {
    @AppStorage(DayCutoff.key) private var cutoff = 4
    @AppStorage(MorningReminder.enabledKey) private var reminder = false
    @AppStorage(MorningReminder.minutesKey) private var minutes = 8 * 60
    @State private var denied = false

    var body: some View {
        Section {
            Picker(selection: $cutoff) {
                ForEach(0...8, id: \.self) { Text(hourLabel($0)).tag($0) }
            } label: { Label("Day starts at", systemImage: "sunrise") }
                .frame(minHeight: 44).accessibilityIdentifier("dayStartHour")
            Toggle(isOn: Binding(get: { reminder }, set: { on in Task { await setReminder(on) } })) {
                Label("Morning check-in", systemImage: "bell")
            }.frame(minHeight: 44).accessibilityIdentifier("morningReminder")
            if reminder {
                DatePicker("Reminder time", selection: time, displayedComponents: .hourAndMinute).frame(minHeight: 44)
            }
        } header: { Text("Your day") } footer: {
            Text(denied ? "Notifications are off for Mivu. You can allow them in iOS Settings."
                 : "Food before \(hourLabel(cutoff)) still counts for the day before. A new day starts the first time you open Mivu after that.")
        }
    }

    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date() },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
                    MorningReminder.schedule(minutes: minutes)
                })
    }

    private func hourLabel(_ hour: Int) -> String {
        (Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()).formatted(.dateTime.hour())
    }

    /// Permission is asked only here, when the person turns the reminder on.
    private func setReminder(_ on: Bool) async {
        guard on else { reminder = false; MorningReminder.cancel(); return }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        denied = !granted; reminder = granted
        if granted { MorningReminder.schedule(minutes: minutes) }
    }
}

enum MorningReminder {
    static let enabledKey = "morningReminder", minutesKey = "morningReminderMinutes"
    private static let id = "morning-check-in"

    /// One repeating local notification; adding it again with the same identifier replaces the old time.
    static func schedule(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Good morning"; content.body = "Log your weight or breakfast."; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    static func cancel() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}
