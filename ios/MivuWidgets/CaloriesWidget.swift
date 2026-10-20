import AppIntents
import SwiftUI
import WidgetKit

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CaloriesProvider: TimelineProvider {
    static let sample = WidgetSnapshot(day: "", eaten: 1360, target: 2000, hasDiary: true, rolloverAt: .distantFuture, writtenAt: .now)

    func placeholder(in context: Context) -> CaloriesEntry { CaloriesEntry(date: .now, snapshot: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(CaloriesEntry(date: .now, snapshot: context.isPreview ? Self.sample : current(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date()
        var entries = [CaloriesEntry(date: now, snapshot: current(at: now))]
        // The app reloads on every change; the only change it cannot announce is the new day starting.
        if let snapshot = read(), snapshot.rolloverAt > now {
            entries.append(CaloriesEntry(date: snapshot.rolloverAt, snapshot: snapshot.afterRollover()))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func read() -> WidgetSnapshot? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)
            .flatMap { WidgetSnapshot.read(from: WidgetSnapshot.fileURL(in: $0)) }
    }

    private func current(at now: Date) -> WidgetSnapshot? {
        read().map { now >= $0.rolloverAt ? $0.afterRollover() : $0 }
    }
}

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.yakov103.mivu.calories", provider: CaloriesProvider()) { entry in
            CaloriesWidgetView(snapshot: entry.snapshot)
                .tint(Color("AccentColor"))
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "mivu://today"))
        }
        .configurationDisplayName("Calories")
        .description("Today's calories, with Log Food and Coach one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct CaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, snapshot.hasDiary {
            switch family {
            case .accessoryCircular: circular(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            case .systemMedium:
                HStack(spacing: 16) {
                    summary(snapshot)
                    VStack(spacing: 8) {
                        // The dark-mode accent is light teal, so the label flips to the background color to stay readable.
                        Button(intent: LogFoodIntent()) {
                            buttonLabel("Log Food", systemImage: "camera").foregroundStyle(Color(.systemBackground))
                        }
                        .buttonStyle(.borderedProminent)
                        Button(intent: OpenCoachIntent()) { buttonLabel("Coach", systemImage: "bubble.left.fill") }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: 150)
                }
            default: summary(snapshot)
            }
        } else {
            setUp
        }
    }

    private func summary(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                pip.frame(width: 48, height: 48)
                Spacer(minLength: 4)
                ring(snapshot).frame(width: 40, height: 40)
            }
            Spacer(minLength: 4)
            Text(kcal(snapshot.eaten))
                .font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(snapshot.target.map { "of \(kcal($0)) kcal" } ?? "kcal eaten")
                .font(.caption).foregroundStyle(.secondary).minimumScaleFactor(0.8).lineLimit(1)
            if snapshot.target == nil {
                Text("Set a target").font(.caption2.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    private func ring(_ snapshot: WidgetSnapshot) -> some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.2), lineWidth: 6)
            Circle().trim(from: 0, to: snapshot.ringFraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .widgetAccentable()
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        Gauge(value: snapshot.ringFraction) {
            Text("kcal")
        } currentValueLabel: {
            Text(kcal(snapshot.eaten)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(spoken(snapshot))
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mivu").font(.headline).widgetAccentable()
            Text(snapshot.target.map { "\(kcal(snapshot.eaten)) / \(kcal($0)) kcal" } ?? "\(kcal(snapshot.eaten)) kcal eaten")
                .minimumScaleFactor(0.7).lineLimit(1)
            if snapshot.target != nil {
                Gauge(value: snapshot.ringFraction) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(snapshot))
    }

    @ViewBuilder private var setUp: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            Label("Set up Mivu", systemImage: "fork.knife").widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 4) {
                pip.frame(width: 44, height: 44)
                Spacer(minLength: 4)
                Text("Set up Mivu").font(.headline)
                Text("Open the app to start your diary.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pip: some View {
        Image("PipResting").resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
            .accessibilityHidden(true)
    }

    private func buttonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func kcal(_ value: Double) -> String { Int(value.rounded()).formatted() }

    private func spoken(_ snapshot: WidgetSnapshot) -> String {
        snapshot.target.map { "\(kcal(snapshot.eaten)) of \(kcal($0)) calories eaten" } ?? "\(kcal(snapshot.eaten)) calories eaten"
    }
}

private func sampleEntry(eaten: Double, target: Double?, hasDiary: Bool = true) -> CaloriesEntry {
    CaloriesEntry(date: .now, snapshot: WidgetSnapshot(day: "2026-10-20", eaten: eaten, target: target, hasDiary: hasDiary,
                                                      rolloverAt: .distantFuture, writtenAt: .now))
}

#Preview("Small", as: .systemSmall) { CaloriesWidget() } timeline: {
    sampleEntry(eaten: 1360, target: 2000); sampleEntry(eaten: 2300, target: 2000); sampleEntry(eaten: 1360, target: nil)
    sampleEntry(eaten: 0, target: 2000); sampleEntry(eaten: 0, target: nil, hasDiary: false)
}
#Preview("Medium", as: .systemMedium) { CaloriesWidget() } timeline: {
    sampleEntry(eaten: 1360, target: 2000); sampleEntry(eaten: 1360, target: nil); sampleEntry(eaten: 0, target: nil, hasDiary: false)
}
#Preview("Circular", as: .accessoryCircular) { CaloriesWidget() } timeline: {
    sampleEntry(eaten: 1360, target: 2000); sampleEntry(eaten: 0, target: nil, hasDiary: false)
}
#Preview("Rectangular", as: .accessoryRectangular) { CaloriesWidget() } timeline: {
    sampleEntry(eaten: 1360, target: 2000); sampleEntry(eaten: 1360, target: nil)
}
